insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
values (
    'couplespace-w1-photos',
    'couplespace-w1-photos',
    false,
    5242880,
    array['image/jpeg']
)
on conflict (id) do nothing;

create policy "Relationship members can read W1 photos"
on storage.objects for select
to authenticated
using (
    bucket_id = 'couplespace-w1-photos'
    and array_length(storage.foldername(name), 1) = 1
    and exists (
        select 1
        from public.relationship_members member
        where member.relationship_id::text = (storage.foldername(name))[1]
          and member.user_id = (select auth.uid())
          and member.membership_status = 'active'
    )
);

create policy "Relationship members can upload W1 photos while active"
on storage.objects for insert
to authenticated
with check (
    bucket_id = 'couplespace-w1-photos'
    and owner_id = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 1
    and exists (
        select 1
        from public.relationship_members member
        join public.relationships relationship
          on relationship.id = member.relationship_id
        where member.relationship_id::text = (storage.foldername(name))[1]
          and member.user_id = (select auth.uid())
          and member.membership_status = 'active'
          and relationship.status = 'active'
    )
);

create policy "Uploaders can delete their W1 photos"
on storage.objects for delete
to authenticated
using (
    bucket_id = 'couplespace-w1-photos'
    and owner_id = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 1
    and exists (
        select 1
        from public.relationship_members member
        where member.relationship_id::text = (storage.foldername(name))[1]
          and member.user_id = (select auth.uid())
          and member.membership_status = 'active'
    )
);
