begin;

create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'quota-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'quota-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'quota-c@example.test', ''),
    ('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'quota-d@example.test', '');

insert into public.relationships (id)
values
    ('a0000000-0000-0000-0000-000000000001'),
    ('a0000000-0000-0000-0000-000000000002'),
    ('a0000000-0000-0000-0000-000000000003');

insert into public.relationship_members (relationship_id, user_id)
values
    ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1'),
    ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a2'),
    ('a0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a4'),
    ('a0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000000a3');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);

insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
    'couplespace-w1-photos',
    'a0000000-0000-0000-0000-000000000001/a1000000-0000-0000-0000-000000000001.jpg',
    '00000000-0000-0000-0000-0000000000a1',
    '{"size": 1024}'::jsonb
);

select results_eq(
    $$
        select accepted::text || '/' || coalesce(reason, 'ok')
        from public.finalize_w1_photo_upload(
            'a0000000-0000-0000-0000-000000000001',
            'a1000000-0000-0000-0000-000000000001',
            1024
        )
    $$,
    array['true/ok'::text],
    'an active member can finalize an owned photo object'
);

select results_eq(
    $$
        select accepted
        from public.finalize_w1_photo_upload(
            'a0000000-0000-0000-0000-000000000001',
            'a1000000-0000-0000-0000-000000000001',
            1024
        )
    $$,
    array[true],
    'retrying the same photo identity is accepted'
);

reset role;
select results_eq(
    $$
        select count(*)::integer
        from public.shared_items
        where relationship_id = 'a0000000-0000-0000-0000-000000000001'
          and client_id = 'a1000000-0000-0000-0000-000000000001'
    $$,
    array[1],
    'an accepted retry creates no duplicate metadata'
);

select results_eq(
    $$
        select creator_user_id::text || '/' || item_kind || '/' || media_byte_size::text
        from public.shared_items
        where relationship_id = 'a0000000-0000-0000-0000-000000000001'
          and client_id = 'a1000000-0000-0000-0000-000000000001'
    $$,
    array['00000000-0000-0000-0000-0000000000a1/photo/1024'::text],
    'the RPC derives identity and records the verified object size'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
select throws_ok(
    $$
        insert into public.shared_items (relationship_id, client_id, creator_user_id, item_kind, media_byte_size)
        values (
            'a0000000-0000-0000-0000-000000000001',
            'a1000000-0000-0000-0000-000000000002',
            '00000000-0000-0000-0000-0000000000a1',
            'photo',
            1
        )
    $$,
    '42501',
    null,
    'authenticated clients cannot bypass photo finalization'
);

select throws_ok(
    $$
        select public.finalize_w1_photo_upload(
            'a0000000-0000-0000-0000-000000000001',
            'a1000000-0000-0000-0000-000000000001',
            2048
        )
    $$,
    '22023',
    'photo_byte_size_mismatch',
    'the RPC rejects a byte size that differs from Storage metadata'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
select throws_ok(
    $$
        select public.finalize_w1_photo_upload(
            'a0000000-0000-0000-0000-000000000001',
            'a1000000-0000-0000-0000-000000000001',
            1024
        )
    $$,
    '42501',
    'photo_object_not_accessible',
    'the partner cannot finalize an object owned by the uploader'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', true);
select throws_ok(
    $$
        select public.finalize_w1_photo_upload(
            'a0000000-0000-0000-0000-000000000001',
            'a1000000-0000-0000-0000-000000000003',
            1
        )
    $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot finalize a relationship photo'
);

reset role;
insert into public.shared_items (
    relationship_id,
    client_id,
    creator_user_id,
    item_kind,
    media_byte_size,
    created_at
)
select
    'a0000000-0000-0000-0000-000000000001',
    ('a2000000-0000-0000-0000-' || lpad(sequence::text, 12, '0'))::uuid,
    '00000000-0000-0000-0000-0000000000a1',
    'photo',
    1,
    now()
from generate_series(1, 29) sequence;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
    'couplespace-w1-photos',
    'a0000000-0000-0000-0000-000000000001/a1000000-0000-0000-0000-000000000004.jpg',
    '00000000-0000-0000-0000-0000000000a1',
    '{"size": 1}'::jsonb
);

select results_eq(
    $$
        select accepted::text || '/' || reason
        from public.finalize_w1_photo_upload(
            'a0000000-0000-0000-0000-000000000001',
            'a1000000-0000-0000-0000-000000000004',
            1
        )
    $$,
    array['false/monthly_photo_limit'::text],
    'the relationship monthly photo count is enforced'
);

reset role;
insert into public.shared_items (
    relationship_id,
    client_id,
    creator_user_id,
    item_kind,
    media_byte_size,
    created_at
) values (
    'a0000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-0000000000a3',
    'photo',
    999999996,
    now() - interval '2 months'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', true);
insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
    'couplespace-w1-photos',
    'a0000000-0000-0000-0000-000000000003/a3000000-0000-0000-0000-000000000002.jpg',
    '00000000-0000-0000-0000-0000000000a3',
    '{"size": 5}'::jsonb
);

select results_eq(
    $$
        select accepted::text || '/' || reason
        from public.finalize_w1_photo_upload(
            'a0000000-0000-0000-0000-000000000003',
            'a3000000-0000-0000-0000-000000000002',
            5
        )
    $$,
    array['false/total_storage_limit'::text],
    'the relationship total storage cap includes photos from older months'
);

reset role;
insert into public.shared_items (
    relationship_id,
    client_id,
    creator_user_id,
    item_kind,
    media_byte_size,
    created_at
)
select
    'a0000000-0000-0000-0000-000000000002',
    ('a4000000-0000-0000-0000-' || lpad(sequence::text, 12, '0'))::uuid,
    '00000000-0000-0000-0000-0000000000a4',
    'photo',
    1,
    now() - interval '2 months'
from generate_series(1, 30) sequence;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a4', true);
insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
    'couplespace-w1-photos',
    'a0000000-0000-0000-0000-000000000002/a4000000-0000-0000-0000-000000000031.jpg',
    '00000000-0000-0000-0000-0000000000a4',
    '{"size": 4}'::jsonb
);

select results_eq(
    $$
        select accepted
        from public.finalize_w1_photo_upload(
            'a0000000-0000-0000-0000-000000000002',
            'a4000000-0000-0000-0000-000000000031',
            4
        )
    $$,
    array[true],
    'an older-month photo does not consume the current monthly count'
);

reset role;
select lives_ok(
    $$
        insert into public.shared_items (relationship_id, client_id, creator_user_id, item_kind)
        values (
            'a0000000-0000-0000-0000-000000000001',
            'a1000000-0000-0000-0000-000000000005',
            '00000000-0000-0000-0000-0000000000a1',
            'marker'
        )
    $$,
    'legacy non-photo inserts remain valid for trusted server paths'
);

update public.relationships
set status = 'closing',
    closing_started_at = now()
where id = 'a0000000-0000-0000-0000-000000000003';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', true);

select throws_ok(
    $$
        select public.finalize_w1_photo_upload(
            'a0000000-0000-0000-0000-000000000003',
            'a3000000-0000-0000-0000-000000000002',
            5
        )
    $$,
    '23514',
    'relationship_not_active',
    'closing relationships reject photo finalization even on retry'
);

select throws_ok(
    $$
        select public.finalize_w1_photo_upload(
            'a0000000-0000-0000-0000-000000000003',
            'a3000000-0000-0000-0000-000000000099',
            5242881
        )
    $$,
    '22023',
    'invalid_photo_byte_size',
    'the RPC rejects sizes above the bucket object limit'
);

select * from finish();
rollback;
