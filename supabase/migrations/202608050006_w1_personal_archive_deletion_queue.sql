create table public.storage_gc_queue (
    bucket_id text not null,
    object_path text not null,
    enqueued_at timestamptz not null default now(),
    attempt_count integer not null default 0 check (attempt_count >= 0),
    last_error text,
    primary key (bucket_id, object_path)
);

alter table public.storage_gc_queue enable row level security;

drop policy "Owners can delete personal archives"
on public.personal_archives;

revoke delete on public.personal_archives from authenticated;
revoke all on public.storage_gc_queue from anon, authenticated;
grant select, update, delete on public.storage_gc_queue to service_role;

create function public.delete_personal_archive(target_archive_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    target_relationship_id uuid;
    relationship_status text;
    queued_object_count integer := 0;
begin
    select archive.relationship_id, relationship.status
    into target_relationship_id, relationship_status
    from public.personal_archives archive
    join public.relationships relationship
      on relationship.id = archive.relationship_id
    where archive.id = target_archive_id
      and archive.owner_user_id = participant_id
    for update of archive;

    if target_relationship_id is null then
        raise exception 'personal_archive_not_accessible' using errcode = '42501';
    end if;

    if relationship_status <> 'archived' then
        raise exception 'relationship_not_archived' using errcode = '23514';
    end if;

    delete from public.personal_archives
    where id = target_archive_id
      and owner_user_id = participant_id;

    if not exists (
        select 1
        from public.personal_archives archive
        where archive.relationship_id = target_relationship_id
    ) then
        insert into public.storage_gc_queue (bucket_id, object_path)
        select
            'couplespace-w1-photos',
            target_relationship_id::text || '/' || item.client_id::text || '.jpg'
        from public.shared_items item
        where item.relationship_id = target_relationship_id
          and item.item_kind = 'photo'
        on conflict (bucket_id, object_path) do nothing;

        get diagnostics queued_object_count = row_count;
    end if;

    return queued_object_count;
end;
$$;

revoke all on function public.delete_personal_archive(uuid) from public;
grant execute on function public.delete_personal_archive(uuid) to authenticated;
