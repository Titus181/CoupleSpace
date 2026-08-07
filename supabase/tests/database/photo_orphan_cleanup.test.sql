begin;

create extension if not exists pgtap with schema extensions;
select plan(15);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'orphan-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'orphan-b@example.test', ''),
    ('00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'orphan-c@example.test', '');

insert into public.relationships (id)
values ('30000000-0000-0000-0000-000000000009');

insert into public.relationship_members (relationship_id, user_id)
values
    ('30000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000091'),
    ('30000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000092');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);

select lives_ok(
    $$
        insert into storage.objects (bucket_id, name, owner_id)
        values (
            'couplespace-w1-photos',
            '30000000-0000-0000-0000-000000000009/40000000-0000-0000-0000-000000000009.jpg',
            '00000000-0000-0000-0000-000000000091'
        )
    $$,
    'first member can upload the future orphan while active'
);

select lives_ok(
    $$
        insert into storage.objects (bucket_id, name, owner_id)
        values (
            'couplespace-w1-photos',
            '30000000-0000-0000-0000-000000000009/40000000-0000-0000-0000-000000000010.jpg',
            '00000000-0000-0000-0000-000000000091'
        )
    $$,
    'first member can upload a photo that will keep metadata'
);

reset role;
insert into public.shared_items (
    relationship_id,
    client_id,
    creator_user_id,
    item_kind
) values (
    '30000000-0000-0000-0000-000000000009',
    '40000000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000091',
    'photo'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);
select public.begin_unpairing('30000000-0000-0000-0000-000000000009');
select public.seal_personal_archive('30000000-0000-0000-0000-000000000009');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', true);
select public.seal_personal_archive('30000000-0000-0000-0000-000000000009');

reset role;
select results_eq(
    $$ select status from public.relationships where id = '30000000-0000-0000-0000-000000000009' $$,
    array['archived'::text],
    'both sealed archives move the relationship to archived'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', true);
select is(
    public.is_w1_photo_orphan(
        '30000000-0000-0000-0000-000000000009/40000000-0000-0000-0000-000000000009.jpg'
    ),
    false,
    'partner cannot use the helper to inspect an object they do not own'
);
select set_config('storage.allow_delete_query', 'true', true);
select results_eq(
    $$
        with deleted as (
            delete from storage.objects
            where bucket_id = 'couplespace-w1-photos'
            returning 1
        )
        select count(*)::integer from deleted
    $$,
    array[0],
    'partner cannot delete an orphan owned by the first uploader'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000093', true);
select set_config('storage.allow_delete_query', 'true', true);
select results_eq(
    $$
        with deleted as (
            delete from storage.objects
            where bucket_id = 'couplespace-w1-photos'
            returning 1
        )
        select count(*)::integer from deleted
    $$,
    array[0],
    'third user cannot delete the archived orphan'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);

select is(
    public.is_w1_photo_orphan(
        '30000000-0000-0000-0000-000000000009/40000000-0000-0000-0000-000000000009.jpg'
    ),
    true,
    'uploader can identify their own unreferenced object'
);

select is(
    public.is_w1_photo_orphan(
        '30000000-0000-0000-0000-000000000009/40000000-0000-0000-0000-000000000010.jpg'
    ),
    false,
    'uploader cannot classify their referenced archived photo as an orphan'
);

select results_eq(
    $$ select count(*)::integer from public.personal_archive_items where client_id = '40000000-0000-0000-0000-000000000009' $$,
    array[0],
    'the uploaded object has no sealed metadata reference'
);

select results_eq(
    $$ select count(*)::integer from public.personal_archive_items where client_id = '40000000-0000-0000-0000-000000000010' $$,
    array[1],
    'the referenced photo is present in the uploader archive'
);

select set_config('storage.allow_delete_query', 'true', true);
select lives_ok(
    $$
        delete from storage.objects
        where bucket_id = 'couplespace-w1-photos'
          and name = '30000000-0000-0000-0000-000000000009/40000000-0000-0000-0000-000000000009.jpg'
    $$,
    'archive owner can delete their own unreferenced object after archival'
);

select results_eq(
    $$
        select count(*)::integer
        from storage.objects
        where bucket_id = 'couplespace-w1-photos'
          and name = '30000000-0000-0000-0000-000000000009/40000000-0000-0000-0000-000000000009.jpg'
    $$,
    array[0],
    'the archived orphan object is removed'
);

select results_eq(
    $$
        with deleted as (
            delete from storage.objects
            where bucket_id = 'couplespace-w1-photos'
              and name = '30000000-0000-0000-0000-000000000009/40000000-0000-0000-0000-000000000010.jpg'
            returning 1
        )
        select count(*)::integer from deleted
    $$,
    array[0],
    'archive owner cannot delete their own photo while sealed metadata still references it'
);

select results_eq(
    $$
        select count(*)::integer
        from storage.objects
        where bucket_id = 'couplespace-w1-photos'
          and name = '30000000-0000-0000-0000-000000000009/40000000-0000-0000-0000-000000000010.jpg'
    $$,
    array[1],
    'the referenced archived photo remains stored'
);

reset role;
select results_eq(
    $$ select count(*)::integer from public.storage_gc_queue $$,
    array[0],
    'client-side orphan cleanup does not create a duplicate GC job'
);

select * from finish();
rollback;
