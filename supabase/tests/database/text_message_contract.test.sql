begin;

create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'message-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000082', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'message-b@example.test', ''),
    ('00000000-0000-0000-0000-000000000083', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'message-c@example.test', '');

insert into public.relationships (id)
values ('90000000-0000-0000-0000-000000000008');

insert into public.relationship_members (relationship_id, user_id)
values
    ('90000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000081'),
    ('90000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000082');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000081', true);

select lives_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000008',
        '93000000-0000-0000-0000-000000000001',
        '  W1 test message 1  '
    ) $$,
    'member can write a normalized text message'
);

select lives_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000008',
        '93000000-0000-0000-0000-000000000001',
        'W1 test message 1'
    ) $$,
    'same identity and body retry is accepted'
);

reset role;
select results_eq(
    $$ select count(*)::integer from public.shared_items
       where relationship_id = '90000000-0000-0000-0000-000000000008'
         and client_id = '93000000-0000-0000-0000-000000000001' $$,
    array[1],
    'retry creates exactly one row'
);

select results_eq(
    $$ select creator_user_id::text || '/' || item_kind || '/' || text_content
       from public.shared_items
       where relationship_id = '90000000-0000-0000-0000-000000000008'
         and client_id = '93000000-0000-0000-0000-000000000001' $$,
    array['00000000-0000-0000-0000-000000000081/message/W1 test message 1'::text],
    'session supplies creator and RPC stores normalized body'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000081', true);

select throws_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000008',
        '93000000-0000-0000-0000-000000000001',
        'different body'
    ) $$,
    '23505',
    'shared_item_identity_collision',
    'same identity cannot be retried with different content'
);

select throws_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000008',
        '93000000-0000-0000-0000-000000000002',
        '   '
    ) $$,
    '22023',
    'invalid_message_body',
    'blank message is rejected'
);

select throws_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000008',
        '93000000-0000-0000-0000-000000000006',
        E'\n\t\r'
    ) $$,
    '22023',
    'invalid_message_body',
    'newline and tab only message is rejected'
);

select throws_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000008',
        '93000000-0000-0000-0000-000000000003',
        repeat('a', 4001)
    ) $$,
    '22023',
    'invalid_message_body',
    'oversized message is rejected'
);

select lives_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000008',
        '93000000-0000-0000-0000-000000000002',
        'W1 test message 2'
    ) $$,
    'second identity creates an independent message'
);

reset role;
select results_eq(
    $$ select text_content from public.shared_items
       where relationship_id = '90000000-0000-0000-0000-000000000008'
         and item_kind = 'message'
       order by created_at, client_id $$,
    array['W1 test message 1'::text, 'W1 test message 2'::text],
    'messages have deterministic server ordering'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000083', true);
select throws_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000008',
        '93000000-0000-0000-0000-000000000004',
        'third user message'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'third user cannot write a message'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000081', true);
select public.begin_unpairing('90000000-0000-0000-0000-000000000008');

select throws_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000008',
        '93000000-0000-0000-0000-000000000005',
        'closing message'
    ) $$,
    '23514',
    'relationship_not_active',
    'closing relationship rejects a message'
);

select lives_ok(
    $$ select public.seal_personal_archive('90000000-0000-0000-0000-000000000008') $$,
    'first participant can seal message content into an archive'
);

reset role;
select results_eq(
    $$ select text_content from public.personal_archive_items
       where owner_user_id = '00000000-0000-0000-0000-000000000081'
         and item_kind = 'message'
       order by created_at, client_id $$,
    array['W1 test message 1'::text, 'W1 test message 2'::text],
    'personal archive preserves message content and order'
);

select * from finish();
rollback;
