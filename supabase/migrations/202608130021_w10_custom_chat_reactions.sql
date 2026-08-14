alter table public.shared_item_reactions
    drop constraint shared_item_reactions_emoji_value_check;

alter table public.shared_item_reactions
    add constraint shared_item_reactions_emoji_value_check
    check (
        emoji_value in ('heart', 'hug', 'smile', 'cheer', 'laugh', 'support')
        or (
            char_length(emoji_value) between 1 and 8
            and octet_length(emoji_value) <= 32
            and emoji_value !~ '[[:space:][:cntrl:]]'
        )
    );

create or replace function public.set_shared_item_reaction(
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
    custom_emoji_is_valid boolean := false;
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

    if target_emoji_value is not null
       and char_length(target_emoji_value) between 1 and 8
       and octet_length(target_emoji_value) <= 32
       and target_emoji_value !~ '[[:space:][:cntrl:]]' then
        custom_emoji_is_valid := ascii(target_emoji_value) > 127;
    end if;

    if target_emoji_value is null
       or not (
           target_emoji_value in ('heart', 'hug', 'smile', 'cheer', 'laugh', 'support')
           or custom_emoji_is_valid
       ) then
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
