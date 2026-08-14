alter table public.shared_items
    add column appointment_client_id uuid,
    add constraint shared_items_appointment_discussion_kind check (
        appointment_client_id is null or item_kind = 'message'
    ),
    add constraint shared_items_appointment_discussion_fk
        foreign key (relationship_id, appointment_client_id)
        references public.shared_appointments(relationship_id, client_id)
        on delete cascade;

drop index public.shared_items_conversation_order_idx;

create index shared_items_conversation_order_idx
on public.shared_items (relationship_id, created_at, client_id)
where appointment_client_id is null
  and (
      item_kind = 'message'
      or (item_kind = 'photo' and media_byte_size is not null)
  );

create index shared_items_appointment_discussion_order_idx
on public.shared_items (relationship_id, appointment_client_id, created_at, client_id)
where appointment_client_id is not null
  and item_kind = 'message';

alter table public.conversation_read_states
    add column scope_id uuid;

update public.conversation_read_states
set scope_id = relationship_id;

alter table public.conversation_read_states
    alter column scope_id set not null,
    drop constraint conversation_read_states_pkey,
    add primary key (relationship_id, user_id, scope_id);

create or replace function public.write_shared_message(
    target_relationship_id uuid,
    target_client_id uuid,
    target_body text
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    normalized_body text := btrim(target_body, E' \t\n\r');
    accepted_at timestamptz;
    existing_creator_id uuid;
    existing_kind text;
    existing_body text;
    existing_appointment_client_id uuid;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if normalized_body is null
       or char_length(normalized_body) not between 1 and 4000 then
        raise exception 'invalid_message_body' using errcode = '22023';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    insert into public.shared_items (
        relationship_id,
        client_id,
        creator_user_id,
        item_kind,
        text_content,
        appointment_client_id
    ) values (
        target_relationship_id,
        target_client_id,
        participant_id,
        'message',
        normalized_body,
        null
    )
    on conflict (relationship_id, client_id) do nothing
    returning created_at into accepted_at;

    if accepted_at is null then
        select item.creator_user_id,
               item.item_kind,
               item.text_content,
               item.created_at,
               item.appointment_client_id
        into existing_creator_id,
             existing_kind,
             existing_body,
             accepted_at,
             existing_appointment_client_id
        from public.shared_items item
        where item.relationship_id = target_relationship_id
          and item.client_id = target_client_id;

        if existing_creator_id <> participant_id
           or existing_kind <> 'message'
           or existing_body <> normalized_body
           or existing_appointment_client_id is not null then
            raise exception 'shared_item_identity_collision' using errcode = '23505';
        end if;
    end if;

    return accepted_at;
end;
$$;

create function public.write_appointment_discussion_message(
    target_relationship_id uuid,
    target_appointment_client_id uuid,
    target_client_id uuid,
    target_body text
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    appointment_status text;
    normalized_body text := btrim(target_body, E' \t\n\r');
    accepted_at timestamptz;
    existing_creator_id uuid;
    existing_kind text;
    existing_body text;
    existing_appointment_client_id uuid;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if normalized_body is null
       or char_length(normalized_body) not between 1 and 4000 then
        raise exception 'invalid_message_body' using errcode = '22023';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    select appointment.status
    into appointment_status
    from public.shared_appointments appointment
    where appointment.relationship_id = target_relationship_id
      and appointment.client_id = target_appointment_client_id
    for share;

    if appointment_status is null then
        raise exception 'appointment_not_found' using errcode = 'P0002';
    end if;
    if appointment_status <> 'scheduled' then
        raise exception 'appointment_cancelled' using errcode = '23514';
    end if;

    insert into public.shared_items (
        relationship_id,
        client_id,
        creator_user_id,
        item_kind,
        text_content,
        appointment_client_id
    ) values (
        target_relationship_id,
        target_client_id,
        participant_id,
        'message',
        normalized_body,
        target_appointment_client_id
    )
    on conflict (relationship_id, client_id) do nothing
    returning created_at into accepted_at;

    if accepted_at is null then
        select item.creator_user_id,
               item.item_kind,
               item.text_content,
               item.created_at,
               item.appointment_client_id
        into existing_creator_id,
             existing_kind,
             existing_body,
             accepted_at,
             existing_appointment_client_id
        from public.shared_items item
        where item.relationship_id = target_relationship_id
          and item.client_id = target_client_id;

        if existing_creator_id <> participant_id
           or existing_kind <> 'message'
           or existing_body <> normalized_body
           or existing_appointment_client_id is distinct from target_appointment_client_id then
            raise exception 'shared_item_identity_collision' using errcode = '23505';
        end if;
    end if;

    return accepted_at;
end;
$$;

create or replace function public.conversation_unread_count(target_relationship_id uuid)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    unread_count bigint;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select count(*)
    into unread_count
    from public.shared_items message
    left join public.conversation_read_states read_state
      on read_state.relationship_id = target_relationship_id
     and read_state.user_id = participant_id
     and read_state.scope_id = target_relationship_id
    where message.relationship_id = target_relationship_id
      and message.appointment_client_id is null
      and (
          message.item_kind = 'message'
          or (message.item_kind = 'photo' and message.media_byte_size is not null)
      )
      and message.creator_user_id <> participant_id
      and (
          read_state.user_id is null
          or (message.created_at, message.client_id)
             > (read_state.last_read_created_at, read_state.last_read_client_id)
      );

    return unread_count;
end;
$$;

create or replace function public.mark_conversation_read(
    target_relationship_id uuid,
    target_message_client_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    read_created_at timestamptz;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select message.created_at
    into read_created_at
    from public.shared_items message
    where message.relationship_id = target_relationship_id
      and message.client_id = target_message_client_id
      and message.appointment_client_id is null
      and (
          message.item_kind = 'message'
          or (message.item_kind = 'photo' and message.media_byte_size is not null)
      );

    if read_created_at is null then
        raise exception 'message_not_found' using errcode = '22023';
    end if;

    insert into public.conversation_read_states (
        relationship_id,
        user_id,
        scope_id,
        last_read_created_at,
        last_read_client_id
    ) values (
        target_relationship_id,
        participant_id,
        target_relationship_id,
        read_created_at,
        target_message_client_id
    )
    on conflict (relationship_id, user_id, scope_id) do update
    set last_read_created_at = excluded.last_read_created_at,
        last_read_client_id = excluded.last_read_client_id,
        updated_at = now()
    where (excluded.last_read_created_at, excluded.last_read_client_id)
          > (conversation_read_states.last_read_created_at,
             conversation_read_states.last_read_client_id);
end;
$$;

create function public.appointment_discussion_unread_count(
    target_relationship_id uuid,
    target_appointment_client_id uuid
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    unread_count bigint;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if not exists (
        select 1
        from public.shared_appointments appointment
        where appointment.relationship_id = target_relationship_id
          and appointment.client_id = target_appointment_client_id
    ) then
        raise exception 'appointment_not_found' using errcode = 'P0002';
    end if;

    select count(*)
    into unread_count
    from public.shared_items message
    left join public.conversation_read_states read_state
      on read_state.relationship_id = target_relationship_id
     and read_state.user_id = participant_id
     and read_state.scope_id = target_appointment_client_id
    where message.relationship_id = target_relationship_id
      and message.appointment_client_id = target_appointment_client_id
      and message.item_kind = 'message'
      and message.creator_user_id <> participant_id
      and (
          read_state.user_id is null
          or (message.created_at, message.client_id)
             > (read_state.last_read_created_at, read_state.last_read_client_id)
      );

    return unread_count;
end;
$$;

create function public.mark_appointment_discussion_read(
    target_relationship_id uuid,
    target_appointment_client_id uuid,
    target_message_client_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    read_created_at timestamptz;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select message.created_at
    into read_created_at
    from public.shared_items message
    where message.relationship_id = target_relationship_id
      and message.appointment_client_id = target_appointment_client_id
      and message.client_id = target_message_client_id
      and message.item_kind = 'message';

    if read_created_at is null then
        raise exception 'message_not_found' using errcode = '22023';
    end if;

    insert into public.conversation_read_states (
        relationship_id,
        user_id,
        scope_id,
        last_read_created_at,
        last_read_client_id
    ) values (
        target_relationship_id,
        participant_id,
        target_appointment_client_id,
        read_created_at,
        target_message_client_id
    )
    on conflict (relationship_id, user_id, scope_id) do update
    set last_read_created_at = excluded.last_read_created_at,
        last_read_client_id = excluded.last_read_client_id,
        updated_at = now()
    where (excluded.last_read_created_at, excluded.last_read_client_id)
          > (conversation_read_states.last_read_created_at,
             conversation_read_states.last_read_client_id);
end;
$$;

revoke all on function public.write_appointment_discussion_message(
    uuid, uuid, uuid, text
) from public;
revoke all on function public.appointment_discussion_unread_count(uuid, uuid) from public;
revoke all on function public.mark_appointment_discussion_read(uuid, uuid, uuid) from public;

grant execute on function public.write_appointment_discussion_message(
    uuid, uuid, uuid, text
) to authenticated;
grant execute on function public.appointment_discussion_unread_count(uuid, uuid) to authenticated;
grant execute on function public.mark_appointment_discussion_read(
    uuid, uuid, uuid
) to authenticated;
