begin;

create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'moment-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'moment-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'moment-c@example.test', '');

insert into public.relationships (id)
values ('b0000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('b0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1'),
    ('b0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b2');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);

select lives_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001',
        'mood',
        'calm'
    ) $$,
    'a member can create a mood Moment'
);

select lives_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000002',
        'text',
        target_text_content => '  今天看到很漂亮的天空  '
    ) $$,
    'a member can create a normalized short-text Moment'
);

select lives_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000002',
        'text',
        target_text_content => '今天看到很漂亮的天空'
    ) $$,
    'retrying the same Moment identity and content is accepted'
);

reset role;
select results_eq(
    $$ select count(*)::integer
       from public.moments
       where relationship_id = 'b0000000-0000-0000-0000-000000000001' $$,
    array[2],
    'an accepted retry creates no duplicate Moment'
);

select results_eq(
    $$ select kind || '/' || coalesce(mood_value, text_content)
       from public.moments
       where relationship_id = 'b0000000-0000-0000-0000-000000000001'
       order by created_at, client_id $$,
    array['mood/calm'::text, 'text/今天看到很漂亮的天空'::text],
    'Moments preserve kind and normalized content in deterministic order'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);

select throws_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000002',
        'text',
        target_text_content => '不同內容'
    ) $$,
    '23505',
    'moment_identity_collision',
    'the same client identity cannot be reused with different content'
);

select throws_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000003',
        'text',
        target_text_content => '   '
    ) $$,
    '22023',
    'invalid_moment_content',
    'a blank short-text Moment is rejected'
);

select throws_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000004',
        'text',
        target_text_content => repeat('a', 281)
    ) $$,
    '22023',
    'invalid_moment_content',
    'an oversized short-text Moment is rejected'
);

select throws_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000005',
        'mood',
        'angry'
    ) $$,
    '22023',
    'invalid_moment_content',
    'an unsupported mood is rejected'
);

insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
    'couplespace-moment-photos',
    'b0000000-0000-0000-0000-000000000001/b1000000-0000-0000-0000-000000000006.jpg',
    '00000000-0000-0000-0000-0000000000b1',
    '{"size": 1024}'::jsonb
);

select lives_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000006',
        'photo',
        target_media_byte_size => 1024
    ) $$,
    'an uploader can finalize an owned Moment photo'
);

select throws_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000007',
        'photo',
        target_media_byte_size => 1024
    ) $$,
    '23514',
    'moment_photo_not_available',
    'a photo Moment requires its matching private Storage object'
);

select throws_ok(
    $$ insert into public.moments (
        relationship_id, client_id, creator_user_id, kind, text_content
    ) values (
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000008',
        '00000000-0000-0000-0000-0000000000b1',
        'text',
        'bypass'
    ) $$,
    '42501',
    null,
    'authenticated clients cannot bypass the Moment RPC'
);

select results_eq(
    $$ select count(*)::integer from public.moments $$,
    array[3],
    'mood, text and photo Moments share one timeline source'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);

select results_eq(
    $$ select count(*)::integer
       from public.moments
       where relationship_id = 'b0000000-0000-0000-0000-000000000001' $$,
    array[3],
    'the partner can read the same relationship timeline'
);

select throws_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000006',
        'photo',
        target_media_byte_size => 1024
    ) $$,
    '23514',
    'moment_photo_not_available',
    'the partner cannot finalize an uploader-owned photo object'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b3', true);

select results_eq(
    $$ select count(*)::integer
       from public.moments
       where relationship_id = 'b0000000-0000-0000-0000-000000000001' $$,
    array[0],
    'a third user cannot read the private relationship timeline'
);

select throws_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000009',
        'mood',
        'happy'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot create a Moment'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);
select public.begin_unpairing('b0000000-0000-0000-0000-000000000001');

select throws_ok(
    $$ select public.create_moment(
        'b0000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000010',
        'mood',
        'happy'
    ) $$,
    '23514',
    'relationship_not_active',
    'a closing relationship rejects new Moments'
);

select * from finish();
rollback;
