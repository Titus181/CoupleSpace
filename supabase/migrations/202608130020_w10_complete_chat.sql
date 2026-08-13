alter table public.moments
    add column source_shared_item_client_id uuid,
    add foreign key (relationship_id, source_shared_item_client_id)
        references public.shared_items(relationship_id, client_id);

create unique index moments_one_per_source_shared_item
on public.moments (relationship_id, source_shared_item_client_id)
where source_shared_item_client_id is not null;

alter table public.moments
    drop constraint moments_content_matches_kind;

alter table public.moments
    add constraint moments_content_matches_kind check (
        (kind = 'mood'
            and mood_value is not null
            and text_content is null
            and media_byte_size is null
            and question_key is null
            and question_prompt is null
            and source_shared_item_client_id is null)
        or (kind = 'text'
            and mood_value is null
            and text_content is not null
            and char_length(text_content) between 1 and (
                case when source_shared_item_client_id is null then 280 else 4000 end
            )
            and media_byte_size is null
            and question_key is null
            and question_prompt is null)
        or (kind = 'photo'
            and mood_value is null
            and text_content is null
            and media_byte_size > 0
            and question_key is null
            and question_prompt is null)
        or (kind = 'question'
            and mood_value is null
            and text_content is null
            and media_byte_size is null
            and question_key is not null
            and question_prompt is not null
            and source_shared_item_client_id is null)
    );

alter table public.moments
    add constraint moments_source_shared_item_matches_kind check (
        source_shared_item_client_id is null or kind in ('text', 'photo')
    );

create table public.shared_item_reactions (
    id uuid primary key default gen_random_uuid(),
    relationship_id uuid not null,
    message_client_id uuid not null,
    client_id uuid not null,
    reactor_user_id uuid not null references auth.users(id),
    emoji_value text not null
        check (emoji_value in ('heart', 'hug', 'smile', 'cheer', 'laugh', 'support')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (relationship_id, client_id),
    constraint shared_item_reactions_one_per_reactor
        unique (relationship_id, message_client_id, reactor_user_id),
    foreign key (relationship_id, message_client_id)
        references public.shared_items(relationship_id, client_id)
        on delete cascade
);

-- Reaction removals are DELETE events, which cannot be safely relationship-filtered
-- by Postgres Changes. Touching the parent emits an RLS-filterable synchronization hint.
alter table public.shared_items
    add column reaction_updated_at timestamptz;

alter table public.shared_item_reactions enable row level security;

create policy "Current members can read shared item reactions"
on public.shared_item_reactions for select
to authenticated
using (public.is_current_relationship_member(relationship_id));

revoke all on public.shared_item_reactions from anon, authenticated;
grant select on public.shared_item_reactions to authenticated;

drop index public.shared_items_message_order_idx;

create index shared_items_conversation_order_idx
on public.shared_items (relationship_id, created_at, client_id)
where item_kind = 'message'
   or (item_kind = 'photo' and media_byte_size is not null);

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
    where message.relationship_id = target_relationship_id
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
        last_read_created_at,
        last_read_client_id
    ) values (
        target_relationship_id,
        participant_id,
        read_created_at,
        target_message_client_id
    )
    on conflict (relationship_id, user_id) do update
    set last_read_created_at = excluded.last_read_created_at,
        last_read_client_id = excluded.last_read_client_id,
        updated_at = now()
    where (excluded.last_read_created_at, excluded.last_read_client_id)
          > (conversation_read_states.last_read_created_at,
             conversation_read_states.last_read_client_id);
end;
$$;

create function public.finalize_chat_photo_upload(
    target_relationship_id uuid,
    target_client_id uuid,
    target_byte_size bigint
)
returns table (
    accepted boolean,
    reason text,
    accepted_at timestamptz
)
language sql
set search_path = ''
as $$
    select result.accepted, result.reason, result.accepted_at
    from public.finalize_w1_photo_upload(
        target_relationship_id,
        target_client_id,
        target_byte_size
    ) result;
$$;

create function public.set_shared_item_reaction(
    target_relationship_id uuid,
    target_message_client_id uuid,
    target_client_id uuid,
    target_emoji_value text
)
returns table (
    message_client_id uuid,
    client_id uuid,
    reactor_user_id uuid,
    emoji_value text,
    updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    message_creator_id uuid;
    message_kind text;
    relationship_status text;
    active_member_count integer;
    existing_message_client_id uuid;
    existing_reactor_user_id uuid;
    existing_emoji_value text;
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

    select item.creator_user_id, item.item_kind
    into message_creator_id, message_kind
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.client_id = target_message_client_id
      and (
          item.item_kind = 'message'
          or (item.item_kind = 'photo' and item.media_byte_size is not null)
      );

    if message_creator_id is null or message_kind not in ('message', 'photo') then
        raise exception 'message_not_found' using errcode = 'P0002';
    end if;
    if message_creator_id = participant_id then
        raise exception 'sender_cannot_react' using errcode = '23514';
    end if;
    if target_emoji_value is null
       or target_emoji_value not in ('heart', 'hug', 'smile', 'cheer', 'laugh', 'support') then
        raise exception 'invalid_message_reaction' using errcode = '22023';
    end if;

    select reaction.message_client_id, reaction.reactor_user_id, reaction.emoji_value
    into existing_message_client_id, existing_reactor_user_id, existing_emoji_value
    from public.shared_item_reactions reaction
    where reaction.relationship_id = target_relationship_id
      and reaction.client_id = target_client_id;

    if found then
        if existing_message_client_id <> target_message_client_id
           or existing_reactor_user_id <> participant_id
           or existing_emoji_value <> target_emoji_value then
            raise exception 'message_reaction_identity_collision' using errcode = '23505';
        end if;
    else
        insert into public.shared_item_reactions (
            relationship_id,
            message_client_id,
            client_id,
            reactor_user_id,
            emoji_value
        ) values (
            target_relationship_id,
            target_message_client_id,
            target_client_id,
            participant_id,
            target_emoji_value
        )
        on conflict on constraint shared_item_reactions_one_per_reactor do update
        set client_id = excluded.client_id,
            emoji_value = excluded.emoji_value,
            updated_at = now();
    end if;

    update public.shared_items item
    set reaction_updated_at = now()
    where item.relationship_id = target_relationship_id
      and item.client_id = target_message_client_id;

    return query
    select
        reaction.message_client_id,
        reaction.client_id,
        reaction.reactor_user_id,
        reaction.emoji_value,
        reaction.updated_at
    from public.shared_item_reactions reaction
    where reaction.relationship_id = target_relationship_id
      and reaction.message_client_id = target_message_client_id
      and reaction.reactor_user_id = participant_id;
end;
$$;

create function public.remove_shared_item_reaction(
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
    message_creator_id uuid;
    message_kind text;
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
    for share;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    select item.creator_user_id, item.item_kind
    into message_creator_id, message_kind
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.client_id = target_message_client_id
      and (
          item.item_kind = 'message'
          or (item.item_kind = 'photo' and item.media_byte_size is not null)
      );

    if message_creator_id is null or message_kind not in ('message', 'photo') then
        raise exception 'message_not_found' using errcode = 'P0002';
    end if;
    if message_creator_id = participant_id then
        raise exception 'sender_cannot_react' using errcode = '23514';
    end if;

    delete from public.shared_item_reactions reaction
    where reaction.relationship_id = target_relationship_id
      and reaction.message_client_id = target_message_client_id
      and reaction.reactor_user_id = participant_id;

    update public.shared_items item
    set reaction_updated_at = now()
    where item.relationship_id = target_relationship_id
      and item.client_id = target_message_client_id;
end;
$$;

create function public.create_moment_from_shared_item(
    target_relationship_id uuid,
    target_message_client_id uuid,
    target_moment_client_id uuid
)
returns table (
    moment_client_id uuid,
    creator_user_id uuid,
    source_message_client_id uuid,
    source_message_creator_user_id uuid,
    kind text,
    text_content text,
    media_byte_size bigint,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    active_member_count integer;
    source_item public.shared_items%rowtype;
    stored_moment public.moments%rowtype;
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

    select item.*
    into source_item
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.client_id = target_message_client_id
      and (
          item.item_kind = 'message'
          or (item.item_kind = 'photo' and item.media_byte_size is not null)
      )
    for share;

    if source_item.id is null then
        raise exception 'message_not_found' using errcode = 'P0002';
    end if;

    select moment.*
    into stored_moment
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_moment_client_id;

    if found then
        if stored_moment.creator_user_id <> participant_id
           or stored_moment.source_shared_item_client_id is distinct from source_item.client_id
           or stored_moment.kind <> (case
               when source_item.item_kind = 'message' then 'text'
               else 'photo'
           end)
           or stored_moment.text_content is distinct from source_item.text_content
           or stored_moment.media_byte_size is distinct from source_item.media_byte_size then
            raise exception 'moment_identity_collision' using errcode = '23505';
        end if;
    else
        select moment.*
        into stored_moment
        from public.moments moment
        where moment.relationship_id = target_relationship_id
          and moment.source_shared_item_client_id = source_item.client_id;

        if not found then
            insert into public.moments (
                relationship_id,
                client_id,
                creator_user_id,
                kind,
                text_content,
                media_byte_size,
                source_shared_item_client_id
            ) values (
                target_relationship_id,
                target_moment_client_id,
                participant_id,
                case when source_item.item_kind = 'message' then 'text' else 'photo' end,
                source_item.text_content,
                source_item.media_byte_size,
                source_item.client_id
            )
            on conflict (relationship_id, source_shared_item_client_id)
                where source_shared_item_client_id is not null
                do nothing
            returning * into stored_moment;

            if not found then
                select moment.*
                into stored_moment
                from public.moments moment
                where moment.relationship_id = target_relationship_id
                  and moment.source_shared_item_client_id = source_item.client_id;
            end if;
        end if;
    end if;

    return query
    select
        stored_moment.client_id,
        stored_moment.creator_user_id,
        source_item.client_id,
        source_item.creator_user_id,
        stored_moment.kind,
        stored_moment.text_content,
        stored_moment.media_byte_size,
        stored_moment.created_at;
end;
$$;

revoke all on function public.finalize_chat_photo_upload(uuid, uuid, bigint) from public;
revoke all on function public.set_shared_item_reaction(uuid, uuid, uuid, text) from public;
revoke all on function public.remove_shared_item_reaction(uuid, uuid) from public;
revoke all on function public.create_moment_from_shared_item(uuid, uuid, uuid) from public;

grant execute on function public.finalize_chat_photo_upload(uuid, uuid, bigint) to authenticated;
grant execute on function public.set_shared_item_reaction(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.remove_shared_item_reaction(uuid, uuid) to authenticated;
grant execute on function public.create_moment_from_shared_item(uuid, uuid, uuid) to authenticated;
