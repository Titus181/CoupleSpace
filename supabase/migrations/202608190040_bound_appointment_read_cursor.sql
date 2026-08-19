-- Appointment detail needs a durable boundary that survives stale snapshots
-- and does not depend on round-tripping a microsecond PostgreSQL timestamp
-- through Foundation Date (which serializes only milliseconds here).
--
-- The boundary is a server-owned source identity: the appointment client ID
-- for creation, or the applied operation ID for an effective update/cancel.
-- Clients may echo the value rendered with an appointment snapshot, but the
-- RPC treats it as untrusted and re-verifies its relationship, appointment,
-- operation state, and ledger event kind.

alter table public.shared_appointments
    add column interaction_boundary_source_identity uuid;

-- Existing post-ledger appointments inherit their latest verified lifecycle
-- source.  Pre-ledger appointments remain null and are a safe read no-op.
update public.shared_appointments appointment
set interaction_boundary_source_identity = (
    select event.source_identity
    from public.relationship_interaction_events event
    where event.relationship_id = appointment.relationship_id
      and event.scope_id = appointment.client_id
      and (
          (
              event.event_kind = 'appointment_created'
              and event.source_identity = appointment.client_id
          )
          or exists (
              select 1
              from public.shared_appointment_operations operation
              where operation.relationship_id = appointment.relationship_id
                and operation.appointment_client_id = appointment.client_id
                and operation.operation_id = event.source_identity
                and operation.applied_at is not null
                and (
                    (operation.operation_kind = 'update'
                     and event.event_kind = 'appointment_updated')
                    or (operation.operation_kind = 'cancel'
                        and event.event_kind = 'appointment_cancelled')
                )
          )
      )
    order by event.created_at desc, event.id desc
    limit 1
);

create function public.set_shared_appointment_interaction_boundary()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_operation_id uuid;
begin
    if tg_op = 'INSERT' then
        new.interaction_boundary_source_identity := new.client_id;
        return new;
    end if;

    if old.status = new.status
       and old.title is not distinct from new.title
       and old.starts_at is not distinct from new.starts_at
       and old.location is not distinct from new.location
       and old.note is not distinct from new.note
       and old.reminder_at is not distinct from new.reminder_at then
        -- Idempotent/no-op writes do not create a lifecycle event and must not
        -- manufacture a new boundary.
        new.interaction_boundary_source_identity :=
            old.interaction_boundary_source_identity;
        return new;
    end if;

    if new.status = 'cancelled' then
        select operation.operation_id
        into target_operation_id
        from public.shared_appointment_operations operation
        where operation.relationship_id = new.relationship_id
          and operation.appointment_client_id = new.client_id
          and operation.operation_kind = 'cancel'
        order by operation.created_at desc, operation.operation_id desc
        limit 1;
    else
        select operation.operation_id
        into target_operation_id
        from public.shared_appointment_operations operation
        where operation.relationship_id = new.relationship_id
          and operation.appointment_client_id = new.client_id
          and operation.operation_kind = 'update'
          and operation.title = new.title
          and operation.starts_at = new.starts_at
          and operation.location is not distinct from new.location
          and operation.note is not distinct from new.note
          and operation.reminder_at is not distinct from new.reminder_at
        order by operation.created_at desc, operation.operation_id desc
        limit 1;
    end if;

    -- Unsupported direct writes have no verified operation.  Preserve the
    -- prior boundary; the existing AFTER trigger likewise records no event.
    new.interaction_boundary_source_identity :=
        coalesce(target_operation_id, old.interaction_boundary_source_identity);
    return new;
end;
$$;

create trigger shared_appointments_interaction_boundary
before insert or update on public.shared_appointments
for each row execute function public.set_shared_appointment_interaction_boundary();

revoke all on function public.set_shared_appointment_interaction_boundary()
from public, anon, authenticated;

create function public.mark_appointment_interactions_read_through_source(
    target_relationship_id uuid,
    target_appointment_client_id uuid,
    target_visible_source_identity uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    visible_appointment public.shared_appointments%rowtype;
    source_operation public.shared_appointment_operations%rowtype;
    target_event public.relationship_interaction_events%rowtype;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    -- A relationship and one of its appointments must never share a ledger
    -- scope.  Existing rows with that collision are unsafe to advance.
    if target_appointment_client_id = target_relationship_id then
        raise exception 'interaction_scope_not_found' using errcode = '22023';
    end if;

    -- Serialize against update_shared_appointment/cancel_shared_appointment.
    -- A lifecycle operation committed after this lock cannot be mistaken for
    -- the source carried by an older rendered snapshot.
    select appointment.*
    into visible_appointment
    from public.shared_appointments appointment
    where appointment.relationship_id = target_relationship_id
      and appointment.client_id = target_appointment_client_id
    for share;

    if visible_appointment.id is null then
        raise exception 'interaction_scope_not_found' using errcode = '22023';
    end if;

    -- A pre-ledger/cached snapshot has no server boundary and contributes no
    -- lifecycle event that this RPC can mark read.
    if target_visible_source_identity is null then return; end if;

    if target_visible_source_identity = visible_appointment.client_id then
        select event.*
        into target_event
        from public.relationship_interaction_events event
        where event.relationship_id = target_relationship_id
          and event.scope_id = target_appointment_client_id
          and event.source_identity = target_visible_source_identity
          and event.event_kind = 'appointment_created';
    else
        select operation.*
        into source_operation
        from public.shared_appointment_operations operation
        where operation.relationship_id = target_relationship_id
          and operation.appointment_client_id = target_appointment_client_id
          and operation.operation_id = target_visible_source_identity
          and operation.applied_at is not null;

        if source_operation.operation_id is null then
            raise exception 'interaction_source_not_found' using errcode = '22023';
        end if;

        select event.*
        into target_event
        from public.relationship_interaction_events event
        where event.relationship_id = target_relationship_id
          and event.scope_id = target_appointment_client_id
          and event.source_identity = source_operation.operation_id
          and (
              (source_operation.operation_kind = 'update'
               and event.event_kind = 'appointment_updated')
              or (source_operation.operation_kind = 'cancel'
                  and event.event_kind = 'appointment_cancelled')
          );
    end if;

    -- A verified source created before the W13 ledger (or missing because an
    -- old deployment never captured it) is a safe no-op.  Never substitute a
    -- scope-latest event.
    if target_event.id is null then return; end if;

    insert into public.relationship_interaction_read_states (
        relationship_id,
        scope_id,
        user_id,
        last_read_created_at,
        last_read_event_id
    ) values (
        target_relationship_id,
        target_appointment_client_id,
        participant_id,
        target_event.created_at,
        target_event.id
    )
    on conflict (relationship_id, scope_id, user_id) do update set
        last_read_created_at = excluded.last_read_created_at,
        last_read_event_id = excluded.last_read_event_id,
        updated_at = now()
    where (excluded.last_read_created_at, excluded.last_read_event_id) >
          (relationship_interaction_read_states.last_read_created_at,
           relationship_interaction_read_states.last_read_event_id);
end;
$$;

revoke all on function public.mark_appointment_interactions_read_through_source(
    uuid, uuid, uuid
) from public, anon, authenticated;
grant execute on function public.mark_appointment_interactions_read_through_source(
    uuid, uuid, uuid
) to authenticated;

-- Keep both internal writers inaccessible even if an earlier deployment
-- accidentally retained PostgreSQL's default PUBLIC execute privilege.
revoke all on function public.record_relationship_interaction_event(
    uuid, uuid, uuid, uuid, text
) from public, anon, authenticated;
