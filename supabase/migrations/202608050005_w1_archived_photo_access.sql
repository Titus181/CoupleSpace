drop policy "Relationship members can read W1 photos" on storage.objects;

create policy "Relationship members or archive owners can read W1 photos"
on storage.objects for select
to authenticated
using (
    bucket_id = 'couplespace-w1-photos'
    and array_length(storage.foldername(name), 1) = 1
    and (
        exists (
            select 1
            from public.relationship_members member
            where member.relationship_id::text = (storage.foldername(name))[1]
              and member.user_id = (select auth.uid())
              and member.membership_status = 'active'
        )
        or exists (
            select 1
            from public.personal_archives archive
            where archive.relationship_id::text = (storage.foldername(name))[1]
              and archive.owner_user_id = (select auth.uid())
        )
    )
);
