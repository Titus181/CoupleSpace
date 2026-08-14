create table public.shared_appointments (
    id uuid primary key default gen_random_uuid(),
    relationship_id uuid not null references public.relationships(id) on delete cascade,
    client_id uuid not null,
    creator_user_id uuid not null references auth.users(id),
    title text not null check (char_length(title) between 1 and 200),
    starts_at timestamptz not null,
    location text check (location is null or char_length(location) between 1 and 200),
    note text check (note is null or char_length(note) between 1 and 1000),
    reminder_at timestamptz,
    status text not null default 'scheduled'
        check (status in ('scheduled', 'cancelled')),
    source_shared_item_client_id uuid,
    cancelled_by_user_id uuid references auth.users(id),
    cancelled_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (relationship_id, client_id),
    foreign key (relationship_id, source_shared_item_client_id)
        references public.shared_items(relationship_id, client_id),
    constraint shared_appointments_reminder_precedes_start check (
        reminder_at is null or reminder_at <= starts_at
    ),
    constraint shared_appointments_cancellation_matches_status check (
        (status = 'scheduled'
            and cancelled_by_user_id is null
            and cancelled_at is null)
        or (status = 'cancelled'
            and cancelled_by_user_id is not null
            and cancelled_at is not null)
    )
);

create unique index shared_appointments_one_per_source_message
on public.shared_appointments (relationship_id, source_shared_item_client_id)
where source_shared_item_client_id is not null;

create index shared_appointments_relationship_start_idx
on public.shared_appointments (relationship_id, starts_at, client_id);

alter table public.shared_appointments enable row level security;

create policy "Current members can read shared appointments"
on public.shared_appointments for select
to authenticated
using (public.is_current_relationship_member(relationship_id));

revoke all on public.shared_appointments from anon, authenticated;
grant select on public.shared_appointments to authenticated;

create function public.create_shared_appointment(
    target_relationship_id uuid,
    target_client_id uuid,
    target_title text,
    target_starts_at timestamptz,
    target_location text default null,
    target_note text default null,
    target_reminder_at timestamptz default null,
    target_source_shared_item_client_id uuid default null
)
returns setof public.shared_appointments
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    active_member_count integer;
    normalized_title text := btrim(target_title, E' \t\n\r');
    normalized_location text := nullif(btrim(target_location, E' \t\n\r'), '');
    normalized_note text := nullif(btrim(target_note, E' \t\n\r'), '');
    stored_appointment public.shared_appointments%rowtype;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    select count(*)
    into active_member_count
    from public.relationship_members member
    where member.relationship_id = target_relationship_id
      and member.membership_status = 'active';

    if relationship_status <> 'active' or active_member_count <> 2 then
        raise exception 'relationship_not_active_pair' using errcode = '23514';
    end if;

    if normalized_title is null
       or char_length(normalized_title) not between 1 and 200
       or target_starts_at is null
       or (normalized_location is not null and char_length(normalized_location) > 200)
       or (normalized_note is not null and char_length(normalized_note) > 1000)
       or (target_reminder_at is not null and target_reminder_at > target_starts_at) then
        raise exception 'invalid_appointment_content' using errcode = '22023';
    end if;

    if target_source_shared_item_client_id is not null
       and not exists (
           select 1
           from public.shared_items item
           where item.relationship_id = target_relationship_id
             and item.client_id = target_source_shared_item_client_id
             and (
                 item.item_kind = 'message'
                 or (item.item_kind = 'photo' and item.media_byte_size is not null)
             )
       ) then
        raise exception 'source_message_not_found' using errcode = 'P0002';
    end if;

    insert into public.shared_appointments (
        relationship_id,
        client_id,
        creator_user_id,
        title,
        starts_at,
        location,
        note,
        reminder_at,
        source_shared_item_client_id
    ) values (
        target_relationship_id,
        target_client_id,
        participant_id,
        normalized_title,
        target_starts_at,
        normalized_location,
        normalized_note,
        target_reminder_at,
        target_source_shared_item_client_id
    )
    on conflict do nothing;

    select appointment.*
    into stored_appointment
    from public.shared_appointments appointment
    where appointment.relationship_id = target_relationship_id
      and appointment.client_id = target_client_id;

    if found then
        if stored_appointment.creator_user_id <> participant_id
           or stored_appointment.title <> normalized_title
           or stored_appointment.starts_at <> target_starts_at
           or stored_appointment.location is distinct from normalized_location
           or stored_appointment.note is distinct from normalized_note
           or stored_appointment.reminder_at is distinct from target_reminder_at
           or stored_appointment.source_shared_item_client_id
                is distinct from target_source_shared_item_client_id then
            raise exception 'appointment_identity_collision' using errcode = '23505';
        end if;
    elsif target_source_shared_item_client_id is not null then
        select appointment.*
        into stored_appointment
        from public.shared_appointments appointment
        where appointment.relationship_id = target_relationship_id
          and appointment.source_shared_item_client_id = target_source_shared_item_client_id;
    end if;

    if stored_appointment.id is null then
        raise exception 'appointment_create_conflict' using errcode = '40001';
    end if;

    return next stored_appointment;
end;
$$;

create function public.update_shared_appointment(
    target_relationship_id uuid,
    target_appointment_client_id uuid,
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
    normalized_title text := btrim(target_title, E' \t\n\r');
    normalized_location text := nullif(btrim(target_location, E' \t\n\r'), '');
    normalized_note text := nullif(btrim(target_note, E' \t\n\r'), '');
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if not exists (
        select 1 from public.relationships relationship
        where relationship.id = target_relationship_id
          and relationship.status = 'active'
    ) then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    if normalized_title is null
       or char_length(normalized_title) not between 1 and 200
       or target_starts_at is null
       or (normalized_location is not null and char_length(normalized_location) > 200)
       or (normalized_note is not null and char_length(normalized_note) > 1000)
       or (target_reminder_at is not null and target_reminder_at > target_starts_at) then
        raise exception 'invalid_appointment_content' using errcode = '22023';
    end if;

    return query
    update public.shared_appointments appointment
    set title = normalized_title,
        starts_at = target_starts_at,
        location = normalized_location,
        note = normalized_note,
        reminder_at = target_reminder_at,
        updated_at = now()
    where appointment.relationship_id = target_relationship_id
      and appointment.client_id = target_appointment_client_id
      and appointment.status = 'scheduled'
    returning appointment.*;

    if not found then
        if exists (
            select 1 from public.shared_appointments appointment
            where appointment.relationship_id = target_relationship_id
              and appointment.client_id = target_appointment_client_id
              and appointment.status = 'cancelled'
        ) then
            raise exception 'appointment_cancelled' using errcode = '23514';
        end if;
        raise exception 'appointment_not_found' using errcode = 'P0002';
    end if;
end;
$$;

create function public.cancel_shared_appointment(
    target_relationship_id uuid,
    target_appointment_client_id uuid
)
returns setof public.shared_appointments
language plpgsql
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

    if not exists (
        select 1 from public.relationships relationship
        where relationship.id = target_relationship_id
          and relationship.status = 'active'
    ) then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    update public.shared_appointments appointment
    set status = 'cancelled',
        cancelled_by_user_id = participant_id,
        cancelled_at = now(),
        updated_at = now()
    where appointment.relationship_id = target_relationship_id
      and appointment.client_id = target_appointment_client_id
      and appointment.status = 'scheduled';

    if not found and not exists (
        select 1 from public.shared_appointments appointment
        where appointment.relationship_id = target_relationship_id
          and appointment.client_id = target_appointment_client_id
    ) then
        raise exception 'appointment_not_found' using errcode = 'P0002';
    end if;

    return query
    select appointment.*
    from public.shared_appointments appointment
    where appointment.relationship_id = target_relationship_id
      and appointment.client_id = target_appointment_client_id;
end;
$$;

revoke all on function public.create_shared_appointment(
    uuid, uuid, text, timestamptz, text, text, timestamptz, uuid
) from public;
revoke all on function public.update_shared_appointment(
    uuid, uuid, text, timestamptz, text, text, timestamptz
) from public;
revoke all on function public.cancel_shared_appointment(uuid, uuid) from public;

grant execute on function public.create_shared_appointment(
    uuid, uuid, text, timestamptz, text, text, timestamptz, uuid
) to authenticated;
grant execute on function public.update_shared_appointment(
    uuid, uuid, text, timestamptz, text, text, timestamptz
) to authenticated;
grant execute on function public.cancel_shared_appointment(uuid, uuid) to authenticated;

do $$
begin
    if exists (
        select 1 from pg_publication where pubname = 'supabase_realtime'
    ) and not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'shared_appointments'
    ) then
        alter publication supabase_realtime add table public.shared_appointments;
    end if;
end;
$$;
