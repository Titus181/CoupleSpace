alter table public.shared_items
    add column text_content text;

alter table public.personal_archive_items
    add column text_content text;

update public.shared_items
set text_content = '[legacy W1 message]'
where item_kind = 'message'
  and text_content is null;

update public.personal_archive_items
set text_content = '[legacy W1 message]'
where item_kind = 'message'
  and text_content is null;

alter table public.shared_items
    add constraint shared_items_text_content_matches_kind check (
        (item_kind = 'message'
            and text_content is not null
            and char_length(text_content) between 1 and 4000)
        or (item_kind <> 'message' and text_content is null)
    );

alter table public.personal_archive_items
    add constraint personal_archive_items_text_content_matches_kind check (
        (item_kind = 'message'
            and text_content is not null
            and char_length(text_content) between 1 and 4000)
        or (item_kind <> 'message' and text_content is null)
    );

create function public.write_shared_message(
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
        text_content
    ) values (
        target_relationship_id,
        target_client_id,
        participant_id,
        'message',
        normalized_body
    )
    on conflict (relationship_id, client_id) do nothing
    returning created_at into accepted_at;

    if accepted_at is null then
        select item.creator_user_id, item.item_kind, item.text_content, item.created_at
        into existing_creator_id, existing_kind, existing_body, accepted_at
        from public.shared_items item
        where item.relationship_id = target_relationship_id
          and item.client_id = target_client_id;

        if existing_creator_id <> participant_id
           or existing_kind <> 'message'
           or existing_body <> normalized_body then
            raise exception 'shared_item_identity_collision' using errcode = '23505';
        end if;
    end if;

    return accepted_at;
end;
$$;

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

    insert into public.personal_archive_items (
        archive_id,
        owner_user_id,
        source_item_id,
        client_id,
        item_kind,
        text_content,
        created_at
    )
    select
        created_archive_id,
        participant_id,
        item.id,
        item.client_id,
        item.item_kind,
        item.text_content,
        item.created_at
    from public.shared_items item
    where item.relationship_id = target_relationship_id
    on conflict (archive_id, source_item_id) do nothing;

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

revoke all on function public.write_shared_message(uuid, uuid, text) from public;
grant execute on function public.write_shared_message(uuid, uuid, text) to authenticated;
