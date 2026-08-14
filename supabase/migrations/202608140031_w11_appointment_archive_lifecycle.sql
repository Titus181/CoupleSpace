-- W11 preserves appointments, scoped discussion links, and immutable status events
-- in each owner's personal archive. Broader archive export remains a W14 concern.

alter table public.personal_archive_items
    add column source_creator_user_id uuid references auth.users(id),
    add column appointment_client_id uuid;

update public.personal_archive_items archive_item
set source_creator_user_id = shared_item.creator_user_id,
    appointment_client_id = shared_item.appointment_client_id
from public.shared_items shared_item
where archive_item.source_item_id = shared_item.id;

alter table public.personal_archive_items
    alter column source_creator_user_id set not null,
    add constraint personal_archive_items_archive_client_key
        unique (archive_id, client_id);

create table public.personal_archive_appointments (
    archive_id uuid not null references public.personal_archives(id) on delete cascade,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    client_id uuid not null,
    creator_user_id uuid not null references auth.users(id),
    title text not null check (char_length(title) between 1 and 200),
    starts_at timestamptz not null,
    location text check (location is null or char_length(location) between 1 and 200),
    note text check (note is null or char_length(note) between 1 and 1000),
    reminder_at timestamptz,
    status text not null check (status in ('scheduled', 'cancelled')),
    source_shared_item_client_id uuid,
    cancelled_by_user_id uuid references auth.users(id),
    cancelled_at timestamptz,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    primary key (archive_id, client_id),
    constraint personal_archive_appointments_source_item_fk
        foreign key (archive_id, source_shared_item_client_id)
        references public.personal_archive_items(archive_id, client_id)
        deferrable initially deferred,
    constraint personal_archive_appointments_reminder_precedes_start check (
        reminder_at is null or reminder_at <= starts_at
    ),
    constraint personal_archive_appointments_cancellation_matches_status check (
        (status = 'scheduled'
            and cancelled_by_user_id is null
            and cancelled_at is null)
        or (status = 'cancelled'
            and cancelled_by_user_id is not null
            and cancelled_at is not null)
    )
);

insert into public.personal_archive_appointments (
    archive_id,
    owner_user_id,
    client_id,
    creator_user_id,
    title,
    starts_at,
    location,
    note,
    reminder_at,
    status,
    source_shared_item_client_id,
    cancelled_by_user_id,
    cancelled_at,
    created_at,
    updated_at
)
select
    archive.id,
    archive.owner_user_id,
    appointment.client_id,
    appointment.creator_user_id,
    appointment.title,
    appointment.starts_at,
    appointment.location,
    appointment.note,
    appointment.reminder_at,
    appointment.status,
    appointment.source_shared_item_client_id,
    appointment.cancelled_by_user_id,
    appointment.cancelled_at,
    appointment.created_at,
    appointment.updated_at
from public.personal_archives archive
join public.shared_appointments appointment
  on appointment.relationship_id = archive.relationship_id
on conflict (archive_id, client_id) do nothing;

alter table public.personal_archive_items
    add constraint personal_archive_items_appointment_fk
        foreign key (archive_id, appointment_client_id)
        references public.personal_archive_appointments(archive_id, client_id)
        deferrable initially deferred;

create table public.personal_archive_appointment_events (
    archive_id uuid not null references public.personal_archives(id) on delete cascade,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    operation_id uuid not null,
    appointment_client_id uuid not null,
    actor_user_id uuid not null references auth.users(id),
    event_kind text not null check (event_kind in ('rescheduled', 'cancelled')),
    previous_starts_at timestamptz,
    starts_at timestamptz,
    created_at timestamptz not null,
    primary key (archive_id, operation_id),
    foreign key (archive_id, appointment_client_id)
        references public.personal_archive_appointments(archive_id, client_id)
        on delete cascade,
    constraint personal_archive_appointment_events_payload_matches_kind check (
        (event_kind = 'rescheduled'
            and previous_starts_at is not null
            and starts_at is not null
            and previous_starts_at <> starts_at)
        or (event_kind = 'cancelled'
            and previous_starts_at is null
            and starts_at is null)
    )
);

insert into public.personal_archive_appointment_events (
    archive_id,
    owner_user_id,
    operation_id,
    appointment_client_id,
    actor_user_id,
    event_kind,
    previous_starts_at,
    starts_at,
    created_at
)
select
    archive.id,
    archive.owner_user_id,
    event.operation_id,
    event.appointment_client_id,
    event.actor_user_id,
    event.event_kind,
    event.previous_starts_at,
    event.starts_at,
    event.created_at
from public.personal_archives archive
join public.shared_appointment_events event
  on event.relationship_id = archive.relationship_id
on conflict (archive_id, operation_id) do nothing;

alter table public.personal_archive_appointments enable row level security;
alter table public.personal_archive_appointment_events enable row level security;

create policy "Owners can read personal archive appointments"
on public.personal_archive_appointments for select
to authenticated
using (owner_user_id = (select auth.uid()));

create policy "Owners can read personal archive appointment events"
on public.personal_archive_appointment_events for select
to authenticated
using (owner_user_id = (select auth.uid()));

revoke all on public.personal_archive_appointments from anon, authenticated;
revoke all on public.personal_archive_appointment_events from anon, authenticated;
grant select on public.personal_archive_appointments to authenticated;
grant select on public.personal_archive_appointment_events to authenticated;

create or replace function public.seal_personal_archive(target_relationship_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    created_archive_id uuid;
    relationship_status text;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for update;

    if relationship_status <> 'closing' then
        raise exception 'relationship_not_closing' using errcode = '23514';
    end if;

    insert into public.personal_archives (relationship_id, owner_user_id)
    values (target_relationship_id, participant_id)
    on conflict (relationship_id, owner_user_id) do nothing
    returning id into created_archive_id;

    if created_archive_id is null then
        select archive.id
        into created_archive_id
        from public.personal_archives archive
        where archive.relationship_id = target_relationship_id
          and archive.owner_user_id = participant_id;
    end if;

    insert into public.personal_archive_appointments (
        archive_id,
        owner_user_id,
        client_id,
        creator_user_id,
        title,
        starts_at,
        location,
        note,
        reminder_at,
        status,
        source_shared_item_client_id,
        cancelled_by_user_id,
        cancelled_at,
        created_at,
        updated_at
    )
    select
        created_archive_id,
        participant_id,
        appointment.client_id,
        appointment.creator_user_id,
        appointment.title,
        appointment.starts_at,
        appointment.location,
        appointment.note,
        appointment.reminder_at,
        appointment.status,
        appointment.source_shared_item_client_id,
        appointment.cancelled_by_user_id,
        appointment.cancelled_at,
        appointment.created_at,
        appointment.updated_at
    from public.shared_appointments appointment
    where appointment.relationship_id = target_relationship_id
    on conflict (archive_id, client_id) do nothing;

    insert into public.personal_archive_items (
        archive_id,
        owner_user_id,
        source_item_id,
        client_id,
        source_creator_user_id,
        item_kind,
        text_content,
        media_byte_size,
        appointment_client_id,
        created_at
    )
    select
        created_archive_id,
        participant_id,
        item.id,
        item.client_id,
        item.creator_user_id,
        item.item_kind,
        item.text_content,
        item.media_byte_size,
        item.appointment_client_id,
        item.created_at
    from public.shared_items item
    where item.relationship_id = target_relationship_id
    on conflict (archive_id, source_item_id) do nothing;

    insert into public.personal_archive_appointment_events (
        archive_id,
        owner_user_id,
        operation_id,
        appointment_client_id,
        actor_user_id,
        event_kind,
        previous_starts_at,
        starts_at,
        created_at
    )
    select
        created_archive_id,
        participant_id,
        event.operation_id,
        event.appointment_client_id,
        event.actor_user_id,
        event.event_kind,
        event.previous_starts_at,
        event.starts_at,
        event.created_at
    from public.shared_appointment_events event
    where event.relationship_id = target_relationship_id
    on conflict (archive_id, operation_id) do nothing;

    if (
        select count(*)
        from public.personal_archives archive
        where archive.relationship_id = target_relationship_id
    ) = 2 then
        update public.relationships
        set status = 'archived',
            archived_at = now()
        where id = target_relationship_id;

        update public.relationship_members
        set membership_status = 'archived'
        where relationship_id = target_relationship_id;
    end if;

    return created_archive_id;
end;
$$;

revoke all on function public.seal_personal_archive(uuid) from public;
grant execute on function public.seal_personal_archive(uuid) to authenticated;
