create function public.write_shared_marker(
    target_relationship_id uuid,
    target_client_id uuid
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    accepted_at timestamptz;
    existing_creator_id uuid;
    existing_kind text;
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

    insert into public.shared_items (
        relationship_id,
        client_id,
        creator_user_id,
        item_kind
    ) values (
        target_relationship_id,
        target_client_id,
        participant_id,
        'marker'
    )
    on conflict (relationship_id, client_id) do nothing
    returning created_at into accepted_at;

    if accepted_at is null then
        select item.creator_user_id, item.item_kind, item.created_at
        into existing_creator_id, existing_kind, accepted_at
        from public.shared_items item
        where item.relationship_id = target_relationship_id
          and item.client_id = target_client_id;

        if existing_creator_id <> participant_id or existing_kind <> 'marker' then
            raise exception 'shared_item_identity_collision' using errcode = '23505';
        end if;
    end if;

    return accepted_at;
end;
$$;

revoke all on function public.write_shared_marker(uuid, uuid) from public;
grant execute on function public.write_shared_marker(uuid, uuid) to authenticated;
