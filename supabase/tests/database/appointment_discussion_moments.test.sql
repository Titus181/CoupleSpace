begin;

select plan(8);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'discussion-moment-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'discussion-moment-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'discussion-moment-c@example.test', '');

insert into public.relationships (id)
values ('a0000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1'),
    ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a2');

insert into public.shared_appointments (
    relationship_id, client_id, creator_user_id, title, starts_at
)
values (
    'a0000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-0000000000a1',
    '一起吃晚餐',
    now() + interval '1 day'
);

insert into public.shared_items (
    relationship_id, client_id, creator_user_id, item_kind,
    text_content, media_byte_size, appointment_client_id
)
values
    (
        'a0000000-0000-0000-0000-000000000001',
        'a2000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000a1',
        'message', '記得訂窗邊的位置', null,
        'a1000000-0000-0000-0000-000000000001'
    ),
    (
        'a0000000-0000-0000-0000-000000000001',
        'a2000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-0000000000a1',
        'photo', null, 2048,
        'a1000000-0000-0000-0000-000000000001'
    ),
    (
        'a0000000-0000-0000-0000-000000000001',
        'a2000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-0000000000a1',
        'message', '一般對話', null, null
    );

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);

select lives_ok(
    $$ select public.create_moment_from_shared_item(
        'a0000000-0000-0000-0000-000000000001',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001'
    ) $$,
    'a member can save appointment discussion text as a Moment'
);

select results_eq(
    $$ select source_appointment_client_id::text || '/' || text_content
       from public.moments
       where client_id = 'a3000000-0000-0000-0000-000000000001' $$,
    array['a1000000-0000-0000-0000-000000000001/記得訂窗邊的位置'::text],
    'saved discussion text retains its appointment source'
);

select lives_ok(
    $$ select public.create_moment_from_shared_item(
        'a0000000-0000-0000-0000-000000000001',
        'a2000000-0000-0000-0000-000000000002',
        'a3000000-0000-0000-0000-000000000002'
    ) $$,
    'a member can save appointment discussion photo as a Moment'
);

select results_eq(
    $$ select kind || '/' || source_appointment_client_id::text
       from public.moments
       where client_id = 'a3000000-0000-0000-0000-000000000002' $$,
    array['photo/a1000000-0000-0000-0000-000000000001'::text],
    'saved discussion photo retains its appointment source'
);

select results_eq(
    $$ select moment_client_id::text
       from public.create_moment_from_shared_item(
           'a0000000-0000-0000-0000-000000000001',
           'a2000000-0000-0000-0000-000000000001',
           'a3000000-0000-0000-0000-000000000099'
       ) $$,
    array['a3000000-0000-0000-0000-000000000001'::text],
    'a retry with another Moment id converges on the existing saved source'
);

select lives_ok(
    $$ select public.create_moment_from_shared_item(
        'a0000000-0000-0000-0000-000000000001',
        'a2000000-0000-0000-0000-000000000003',
        'a3000000-0000-0000-0000-000000000003'
    ) $$,
    'main chat saving remains supported'
);

select is(
    (select source_appointment_client_id
     from public.moments
     where client_id = 'a3000000-0000-0000-0000-000000000003'),
    null::uuid,
    'main chat Moment has no appointment source'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', true);

select throws_ok(
    $$ select public.create_moment_from_shared_item(
        'a0000000-0000-0000-0000-000000000001',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000004'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a non-member cannot save an appointment discussion Moment'
);

select * from finish();
rollback;
