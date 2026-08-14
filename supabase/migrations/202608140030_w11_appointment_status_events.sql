-- W11 immutable, idempotent records for appointment reschedules and cancellations.

create table public.shared_appointment_events (
    relationship_id uuid not null,
    operation_id uuid not null,
    appointment_client_id uuid not null,
    actor_user_id uuid not null references auth.users(id),
    event_kind text not null check (event_kind in ('rescheduled', 'cancelled')),
    previous_starts_at timestamptz,
    starts_at timestamptz,
    created_at timestamptz not null default now(),
    primary key (relationship_id, operation_id),
    foreign key (relationship_id, operation_id)
        references public.shared_appointment_operations(relationship_id, operation_id)
        on delete cascade,
    foreign key (relationship_id, appointment_client_id)
        references public.shared_appointments(relationship_id, client_id)
        on delete cascade,
    constraint shared_appointment_events_payload_matches_kind check (
        (event_kind = 'rescheduled'
            and previous_starts_at is not null
            and starts_at is not null
            and previous_starts_at <> starts_at)
        or (event_kind = 'cancelled'
            and previous_starts_at is null
            and starts_at is null)
    )
);

create index shared_appointment_events_relationship_time_idx
on public.shared_appointment_events (relationship_id, created_at, operation_id);

create index shared_appointment_events_appointment_time_idx
on public.shared_appointment_events (
    relationship_id,
    appointment_client_id,
    created_at,
    operation_id
);

alter table public.shared_appointment_events enable row level security;

create policy "Current members can read appointment events"
on public.shared_appointment_events for select
to authenticated
using (public.is_current_relationship_member(relationship_id));

revoke all on public.shared_appointment_events from anon, authenticated;
grant select on public.shared_appointment_events to authenticated;

create or replace function public.update_shared_appointment(
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

    if stored_appointment.starts_at <> target_starts_at then
        insert into public.shared_appointment_events (
            relationship_id,
            operation_id,
            appointment_client_id,
            actor_user_id,
            event_kind,
            previous_starts_at,
            starts_at
        ) values (
            target_relationship_id,
            target_operation_id,
            target_appointment_client_id,
            participant_id,
            'rescheduled',
            stored_appointment.starts_at,
            target_starts_at
        );
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

create or replace function public.cancel_shared_appointment(
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

    insert into public.shared_appointment_events (
        relationship_id,
        operation_id,
        appointment_client_id,
        actor_user_id,
        event_kind
    ) values (
        target_relationship_id,
        target_operation_id,
        target_appointment_client_id,
        participant_id,
        'cancelled'
    );

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

create or replace function public.recent_appointment_discussions(
    target_relationship_id uuid
)
returns table (
    appointment_client_id uuid,
    latest_activity_at timestamptz,
    unread_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    return query
    with discussion_activity as (
        select
            item.appointment_client_id,
            greatest(item.created_at, coalesce(item.reaction_updated_at, item.created_at))
                as activity_at,
            item.client_id as activity_id
        from public.shared_items item
        where item.relationship_id = target_relationship_id
          and item.appointment_client_id is not null
          and (
              item.item_kind = 'message'
              or (item.item_kind = 'photo' and item.media_byte_size is not null)
          )
        union all
        select
            event.appointment_client_id,
            event.created_at,
            event.operation_id
        from public.shared_appointment_events event
        where event.relationship_id = target_relationship_id
    ), latest_discussion_activity as (
        select distinct on (activity.appointment_client_id)
            activity.appointment_client_id,
            activity.activity_at as latest_activity_at,
            activity.activity_id
        from discussion_activity activity
        order by
            activity.appointment_client_id,
            activity.activity_at desc,
            activity.activity_id desc
    )
    select
        latest.appointment_client_id,
        latest.latest_activity_at,
        (
            select count(*)
            from public.shared_items unread_item
            left join public.conversation_read_states read_state
              on read_state.relationship_id = target_relationship_id
             and read_state.user_id = participant_id
             and read_state.scope_id = latest.appointment_client_id
            where unread_item.relationship_id = target_relationship_id
              and unread_item.appointment_client_id = latest.appointment_client_id
              and (
                  unread_item.item_kind = 'message'
                  or (
                      unread_item.item_kind = 'photo'
                      and unread_item.media_byte_size is not null
                  )
              )
              and unread_item.creator_user_id <> participant_id
              and (
                  read_state.user_id is null
                  or (unread_item.created_at, unread_item.client_id)
                     > (read_state.last_read_created_at, read_state.last_read_client_id)
              )
        )::bigint as unread_count
    from latest_discussion_activity latest
    order by latest.latest_activity_at desc, latest.activity_id desc;
end;
$$;
