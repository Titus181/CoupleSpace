alter table public.shared_items
    add column media_byte_size bigint;

update public.shared_items item
set media_byte_size = (object.metadata ->> 'size')::bigint
from storage.objects object
where item.item_kind = 'photo'
  and item.media_byte_size is null
  and object.bucket_id = 'couplespace-w1-photos'
  and lower(object.name) = lower(
      item.relationship_id::text || '/' || item.client_id::text || '.jpg'
  )
  and object.metadata ->> 'size' ~ '^[0-9]+$';

alter table public.shared_items
    add constraint shared_items_media_byte_size_matches_kind check (
        (item_kind = 'photo' and (media_byte_size is null or media_byte_size > 0))
        or (item_kind <> 'photo' and media_byte_size is null)
    );

drop policy "Current members can add shared items while active"
on public.shared_items;

create policy "Current members can add non-photo items while active"
on public.shared_items for insert
to authenticated
with check (
    item_kind <> 'photo'
    and creator_user_id = (select auth.uid())
    and public.is_current_relationship_member(relationship_id)
    and exists (
        select 1
        from public.relationships relationship
        where relationship.id = relationship_id
          and relationship.status = 'active'
    )
);

create function public.finalize_w1_photo_upload(
    target_relationship_id uuid,
    target_client_id uuid,
    target_byte_size bigint
)
returns table (
    accepted boolean,
    reason text,
    accepted_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    target_path text := lower(target_relationship_id::text)
        || '/'
        || lower(target_client_id::text)
        || '.jpg';
    stored_owner_id text;
    stored_byte_size bigint;
    existing_creator_id uuid;
    existing_kind text;
    existing_byte_size bigint;
    existing_created_at timestamptz;
    monthly_photo_count integer;
    relationship_total_bytes bigint;
    month_start timestamptz := (
        date_trunc('month', now() at time zone 'UTC') at time zone 'UTC'
    );
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if target_byte_size is null
       or target_byte_size not between 1 and 5242880 then
        raise exception 'invalid_photo_byte_size' using errcode = '22023';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for update;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    select
        object.owner_id,
        case
            when object.metadata ->> 'size' ~ '^[0-9]+$'
                then (object.metadata ->> 'size')::bigint
            else null
        end
    into stored_owner_id, stored_byte_size
    from storage.objects object
    where object.bucket_id = 'couplespace-w1-photos'
      and lower(object.name) = target_path;

    if not found
       or stored_owner_id <> participant_id::text then
        raise exception 'photo_object_not_accessible' using errcode = '42501';
    end if;

    if stored_byte_size is null
       or stored_byte_size <> target_byte_size then
        raise exception 'photo_byte_size_mismatch' using errcode = '22023';
    end if;

    select
        item.creator_user_id,
        item.item_kind,
        item.media_byte_size,
        item.created_at
    into
        existing_creator_id,
        existing_kind,
        existing_byte_size,
        existing_created_at
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.client_id = target_client_id;

    if found then
        if existing_creator_id <> participant_id
           or existing_kind <> 'photo'
           or (existing_byte_size is not null and existing_byte_size <> target_byte_size) then
            raise exception 'shared_item_identity_collision' using errcode = '23505';
        end if;

        if existing_byte_size is null then
            update public.shared_items
            set media_byte_size = target_byte_size
            where relationship_id = target_relationship_id
              and client_id = target_client_id;
        end if;

        return query select true, null::text, existing_created_at;
        return;
    end if;

    select count(*)::integer
    into monthly_photo_count
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.item_kind = 'photo'
      and item.created_at >= month_start;

    if monthly_photo_count >= 30 then
        return query select false, 'monthly_photo_limit'::text, null::timestamptz;
        return;
    end if;

    select coalesce(sum(item.media_byte_size), 0)::bigint
    into relationship_total_bytes
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.item_kind = 'photo';

    if relationship_total_bytes + target_byte_size > 1000000000 then
        return query select false, 'total_storage_limit'::text, null::timestamptz;
        return;
    end if;

    insert into public.shared_items (
        relationship_id,
        client_id,
        creator_user_id,
        item_kind,
        media_byte_size
    ) values (
        target_relationship_id,
        target_client_id,
        participant_id,
        'photo',
        target_byte_size
    )
    returning created_at into existing_created_at;

    return query select true, null::text, existing_created_at;
end;
$$;

revoke all on function public.finalize_w1_photo_upload(uuid, uuid, bigint) from public;
grant execute on function public.finalize_w1_photo_upload(uuid, uuid, bigint) to authenticated;
