-- W11 durable idempotency for appointment edits and cancellations.

create table public.shared_appointment_operations (
    relationship_id uuid not null,
    operation_id uuid not null,
    appointment_client_id uuid not null,
    actor_user_id uuid not null references auth.users(id),
    operation_kind text not null check (operation_kind in ('update', 'cancel')),
    title text,
    starts_at timestamptz,
    location text,
    note text,
    reminder_at timestamptz,
    created_at timestamptz not null default now(),
    primary key (relationship_id, operation_id),
    foreign key (relationship_id, appointment_client_id)
        references public.shared_appointments(relationship_id, client_id)
        on delete cascade,
    constraint shared_appointment_operations_payload_matches_kind check (
        (operation_kind = 'update' and title is not null and starts_at is not null)
        or (operation_kind = 'cancel'
            and title is null
            and starts_at is null
            and location is null
            and note is null
            and reminder_at is null)
    )
);

alter table public.shared_appointment_operations enable row level security;
revoke all on public.shared_appointment_operations from anon, authenticated;

drop function public.update_shared_appointment(
    uuid, uuid, text, timestamptz, text, text, timestamptz
);
drop function public.cancel_shared_appointment(uuid, uuid);

create function public.update_shared_appointment(
    target_relationship_id uuid,
    target_appointment_client_id uuid,
    target_operation_id uuid,
    target_title text,
    target_starts_at timestamptz,
    target_location text default null,
    target_note text default null,
    target_reminder_at timestamptz default null
)
returns setof public.shared_appointments
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    normalized_title text := btrim(target_title, E' \t\n\r');
    normalized_location text := nullif(btrim(target_location, E' \t\n\r'), '');
    normalized_note text := nullif(btrim(target_note, E' \t\n\r'), '');
    stored_appointment public.shared_appointments%rowtype;
    stored_operation public.shared_appointment_operations%rowtype;
    inserted_operation boolean := false;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if target_operation_id is null
       or normalized_title is null
       or char_length(normalized_title) not between 1 and 200
       or target_starts_at is null
       or (normalized_location is not null and char_length(normalized_location) > 200)
       or (normalized_note is not null and char_length(normalized_note) > 1000)
       or (target_reminder_at is not null and target_reminder_at > target_starts_at) then
        raise exception 'invalid_appointment_content' using errcode = '22023';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    select appointment.*
    into stored_appointment
    from public.shared_appointments appointment
    where appointment.relationship_id = target_relationship_id
      and appointment.client_id = target_appointment_client_id
    for update;

    if stored_appointment.id is null then
        raise exception 'appointment_not_found' using errcode = 'P0002';
    end if;

    insert into public.shared_appointment_operations (
        relationship_id,
        operation_id,
        appointment_client_id,
        actor_user_id,
        operation_kind,
        title,
        starts_at,
        location,
        note,
        reminder_at
    ) values (
        target_relationship_id,
        target_operation_id,
        target_appointment_client_id,
        participant_id,
        'update',
        normalized_title,
        target_starts_at,
        normalized_location,
        normalized_note,
        target_reminder_at
    )
    on conflict do nothing
    returning * into stored_operation;

    inserted_operation := stored_operation.operation_id is not null;
    if not inserted_operation then
        select operation.*
        into stored_operation
        from public.shared_appointment_operations operation
        where operation.relationship_id = target_relationship_id
          and operation.operation_id = target_operation_id;
    end if;

    if stored_operation.actor_user_id <> participant_id
       or stored_operation.appointment_client_id <> target_appointment_client_id
       or stored_operation.operation_kind <> 'update'
       or stored_operation.title <> normalized_title
       or stored_operation.starts_at <> target_starts_at
       or stored_operation.location is distinct from normalized_location
       or stored_operation.note is distinct from normalized_note
       or stored_operation.reminder_at is distinct from target_reminder_at then
        raise exception 'appointment_operation_identity_collision' using errcode = '23505';
    end if;

    if not inserted_operation then
        return next stored_appointment;
        return;
    end if;

    if stored_appointment.status = 'cancelled' then
        raise exception 'appointment_cancelled' using errcode = '23514';
    end if;

    update public.shared_appointments appointment
    set title = normalized_title,
        starts_at = target_starts_at,
        location = normalized_location,
        note = normalized_note,
        reminder_at = target_reminder_at,
        updated_at = now()
    where appointment.id = stored_appointment.id
    returning appointment.* into stored_appointment;

    return next stored_appointment;
end;
$$;

create function public.cancel_shared_appointment(
    target_relationship_id uuid,
    target_appointment_client_id uuid,
    target_operation_id uuid
)
returns setof public.shared_appointments
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    stored_appointment public.shared_appointments%rowtype;
    stored_operation public.shared_appointment_operations%rowtype;
    inserted_operation boolean := false;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if target_operation_id is null then
        raise exception 'invalid_appointment_operation' using errcode = '22023';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    select appointment.*
    into stored_appointment
    from public.shared_appointments appointment
    where appointment.relationship_id = target_relationship_id
      and appointment.client_id = target_appointment_client_id
    for update;

    if stored_appointment.id is null then
        raise exception 'appointment_not_found' using errcode = 'P0002';
    end if;

    insert into public.shared_appointment_operations (
        relationship_id,
        operation_id,
        appointment_client_id,
        actor_user_id,
        operation_kind
    ) values (
        target_relationship_id,
        target_operation_id,
        target_appointment_client_id,
        participant_id,
        'cancel'
    )
    on conflict do nothing
    returning * into stored_operation;

    inserted_operation := stored_operation.operation_id is not null;
    if not inserted_operation then
        select operation.*
        into stored_operation
        from public.shared_appointment_operations operation
        where operation.relationship_id = target_relationship_id
          and operation.operation_id = target_operation_id;
    end if;

    if stored_operation.actor_user_id <> participant_id
       or stored_operation.appointment_client_id <> target_appointment_client_id
       or stored_operation.operation_kind <> 'cancel' then
        raise exception 'appointment_operation_identity_collision' using errcode = '23505';
    end if;

    if not inserted_operation or stored_appointment.status = 'cancelled' then
        return next stored_appointment;
        return;
    end if;

    update public.shared_appointments appointment
    set status = 'cancelled',
        cancelled_by_user_id = participant_id,
        cancelled_at = now(),
        updated_at = now()
    where appointment.id = stored_appointment.id
    returning appointment.* into stored_appointment;

    return next stored_appointment;
end;
$$;

revoke all on function public.update_shared_appointment(
    uuid, uuid, uuid, text, timestamptz, text, text, timestamptz
) from public;
revoke all on function public.cancel_shared_appointment(uuid, uuid, uuid) from public;

grant execute on function public.update_shared_appointment(
    uuid, uuid, uuid, text, timestamptz, text, text, timestamptz
) to authenticated;
grant execute on function public.cancel_shared_appointment(uuid, uuid, uuid) to authenticated;
