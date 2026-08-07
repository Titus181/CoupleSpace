alter table public.personal_archive_items
    add column media_byte_size bigint;

update public.personal_archive_items archive_item
set media_byte_size = shared_item.media_byte_size
from public.shared_items shared_item
where archive_item.source_item_id = shared_item.id
  and archive_item.item_kind = 'photo'
  and archive_item.media_byte_size is null;

alter table public.personal_archive_items
    add constraint personal_archive_items_media_byte_size_matches_kind check (
        (item_kind = 'photo' and (media_byte_size is null or media_byte_size > 0))
        or (item_kind <> 'photo' and media_byte_size is null)
    );

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
        media_byte_size,
        created_at
    )
    select
        created_archive_id,
        participant_id,
        item.id,
        item.client_id,
        item.item_kind,
        item.text_content,
        item.media_byte_size,
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

revoke all on function public.seal_personal_archive(uuid) from public;
grant execute on function public.seal_personal_archive(uuid) to authenticated;
