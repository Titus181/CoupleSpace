begin;
select plan(19);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'chat-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'chat-b@example.test', ''),
    ('00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'chat-c@example.test', '');

insert into public.relationships (id)
values ('90000000-0000-0000-0000-000000000009');

insert into public.relationship_members (relationship_id, user_id)
values
    ('90000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000091'),
    ('90000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000092');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);

select lives_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000001',
        '第一則訊息'
    ) $$,
    'first participant can write the first message'
);

select lives_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000002',
        '第二則訊息'
    ) $$,
    'first participant can write the second message'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', true);

select results_eq(
    $$ select public.conversation_unread_count('90000000-0000-0000-0000-000000000009') $$,
    array[2::bigint],
    'partner initially has two unread messages'
);

select lives_ok(
    $$ select public.mark_conversation_read(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000001'
    ) $$,
    'partner can mark through the first visible message'
);

select results_eq(
    $$ select public.conversation_unread_count('90000000-0000-0000-0000-000000000009') $$,
    array[1::bigint],
    'one later partner message remains unread'
);

select lives_ok(
    $$ select public.mark_conversation_read(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000002'
    ) $$,
    'partner can mark through the latest visible message'
);

select results_eq(
    $$ select public.conversation_unread_count('90000000-0000-0000-0000-000000000009') $$,
    array[0::bigint],
    'no partner messages remain unread'
);

select lives_ok(
    $$ select public.mark_conversation_read(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000001'
    ) $$,
    'an older cursor is accepted as an idempotent no-op'
);

select results_eq(
    $$ select public.conversation_unread_count('90000000-0000-0000-0000-000000000009') $$,
    array[0::bigint],
    'read cursor never moves backwards'
);

select lives_ok(
    $$ select public.write_shared_message(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000003',
        '伴侶回覆'
    ) $$,
    'partner can reply in the same conversation'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);

select results_eq(
    $$ select public.conversation_unread_count('90000000-0000-0000-0000-000000000009') $$,
    array[1::bigint],
    'first participant sees the partner reply as unread'
);

select lives_ok(
    $$ select public.mark_conversation_read(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000003'
    ) $$,
    'first participant can mark the partner reply read'
);

select results_eq(
    $$ select public.conversation_unread_count('90000000-0000-0000-0000-000000000009') $$,
    array[0::bigint],
    'first participant unread count returns to zero'
);

select throws_ok(
    $$ select public.mark_conversation_read(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000099'
    ) $$,
    '22023',
    'message_not_found',
    'cursor cannot target a missing message'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000093', true);

select throws_ok(
    $$ select public.conversation_unread_count('90000000-0000-0000-0000-000000000009') $$,
    '42501',
    'relationship_not_accessible',
    'third user cannot read the unread count'
);

select throws_ok(
    $$ select public.mark_conversation_read(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000003'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'third user cannot write a read cursor'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', true);

select results_eq(
    $$ select user_id::text from public.conversation_read_states $$,
    array['00000000-0000-0000-0000-000000000092'::text],
    'RLS exposes only the signed-in users private cursor'
);

reset role;

select results_eq(
    $$ select count(*)::integer from public.conversation_read_states
       where relationship_id = '90000000-0000-0000-0000-000000000009' $$,
    array[2],
    'each participant owns an independent cursor'
);

select results_eq(
    $$ select count(*)::integer from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'conversation_read_states' $$,
    array[1],
    'private cursor changes are available for same-user cross-device refresh'
);

select * from finish();
rollback;
