drop policy "Uploaders can delete their W1 photos" on storage.objects;

create function public.is_w1_photo_orphan(target_object_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from storage.objects object
        where object.bucket_id = 'couplespace-w1-photos'
          and lower(object.name) = lower(target_object_path)
          and object.owner_id = (select auth.uid())::text
    )
    and not exists (
        select 1
        from public.shared_items item
        where lower(item.relationship_id::text)
                || '/'
                || lower(item.client_id::text)
                || '.jpg' = lower(target_object_path)
          and item.item_kind = 'photo'
    );
$$;

revoke all on function public.is_w1_photo_orphan(text) from public;
grant execute on function public.is_w1_photo_orphan(text) to authenticated;

create policy "Uploaders can delete active or archived W1 photos"
on storage.objects for delete
to authenticated
using (
    bucket_id = 'couplespace-w1-photos'
    and owner_id = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 1
    and (
        exists (
            select 1
            from public.relationship_members member
            where member.relationship_id::text = (storage.foldername(name))[1]
              and member.user_id = (select auth.uid())
              and member.membership_status = 'active'
        )
        or (
            exists (
                select 1
                from public.personal_archives archive
                where archive.relationship_id::text = (storage.foldername(name))[1]
                  and archive.owner_user_id = (select auth.uid())
            )
            and public.is_w1_photo_orphan(name)
        )
    )
);
