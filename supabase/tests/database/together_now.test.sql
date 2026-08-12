begin;

create extension if not exists pgtap with schema extensions;
select plan(31);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'together-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'together-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'together-c@example.test', '');

insert into public.relationships (id)
values ('e0000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000e1'),
    ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000e2');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true);

select lives_ok(
    $$ select public.update_relationship_names(
        'e0000000-0000-0000-0000-000000000001',
        '  小日  ',
        '  小月亮  '
    ) $$,
    'a member can set a normalized display name and private partner name'
);

select results_eq(
    $$ select display_name from public.user_profiles
       where user_id = '00000000-0000-0000-0000-0000000000e1' $$,
    array['小日'::text],
    'the owner can read their normalized display name'
);

select results_eq(
    $$ select private_name from public.relationship_partner_aliases
       where relationship_id = 'e0000000-0000-0000-0000-000000000001' $$,
    array['小月亮'::text],
    'the owner can read their private partner name'
);

select throws_ok(
    $$ select public.update_relationship_names(
        'e0000000-0000-0000-0000-000000000001',
        repeat('a', 21),
        null
    ) $$,
    '22023',
    'invalid_display_name',
    'an oversized display name is rejected'
);

select throws_ok(
    $$ insert into public.user_profiles (user_id, display_name)
       values ('00000000-0000-0000-0000-0000000000e2', 'bypass') $$,
    '42501',
    null,
    'authenticated clients cannot bypass the display-name RPC'
);

select lives_ok(
    $$ select public.set_current_relationship_status(
        'e0000000-0000-0000-0000-000000000001',
        'busy',
        target_expiration_kind => 'one_hour'
    ) $$,
    'a member can set a fixed one-hour status'
);

select results_eq(
    $$ select status_kind || '/' || expiration_kind
       from public.current_relationship_statuses
       where relationship_id = 'e0000000-0000-0000-0000-000000000001' $$,
    array['busy/one_hour'::text],
    'the current status keeps its stable kind and expiration kind'
);

select ok(
    (select expires_at between now() + interval '59 minutes' and now() + interval '61 minutes'
     from public.current_relationship_statuses
     where relationship_id = 'e0000000-0000-0000-0000-000000000001'),
    'one-hour expiration is calculated from server time'
);

select lives_ok(
    $$ select public.set_current_relationship_status(
        'e0000000-0000-0000-0000-000000000001',
        'custom',
        '  今天需要一點自己的時間  ',
        'manual'
    ) $$,
    'a normalized custom status can remain until manual clearing'
);

select results_eq(
    $$ select custom_text from public.current_relationship_statuses
       where relationship_id = 'e0000000-0000-0000-0000-000000000001' $$,
    array['今天需要一點自己的時間'::text],
    'custom status text is normalized'
);

select throws_ok(
    $$ select public.set_current_relationship_status(
        'e0000000-0000-0000-0000-000000000001',
        'custom',
        repeat('a', 41),
        'manual'
    ) $$,
    '22023',
    'invalid_current_status',
    'an oversized custom status is rejected'
);

select throws_ok(
    $$ select public.set_current_relationship_status(
        'e0000000-0000-0000-0000-000000000001',
        'busy',
        'hidden text',
        'manual'
    ) $$,
    '22023',
    'invalid_current_status',
    'a fixed status cannot smuggle custom text'
);

select lives_ok(
    $$ select public.set_current_relationship_status(
        'e0000000-0000-0000-0000-000000000001',
        'thinking_of_you',
        target_expiration_kind => 'four_hours',
        target_moment_client_id => 'e1000000-0000-0000-0000-000000000001'
    ) $$,
    'a status can atomically create an independent Moment'
);

select lives_ok(
    $$ select public.set_current_relationship_status(
        'e0000000-0000-0000-0000-000000000001',
        'thinking_of_you',
        target_expiration_kind => 'four_hours',
        target_moment_client_id => 'e1000000-0000-0000-0000-000000000001'
    ) $$,
    'retrying the same status and Moment identity is accepted'
);

select results_eq(
    $$ select count(*)::integer from public.moments
       where client_id = 'e1000000-0000-0000-0000-000000000001' $$,
    array[1],
    'a status retry creates no duplicate Moment'
);

select results_eq(
    $$ select text_content from public.moments
       where client_id = 'e1000000-0000-0000-0000-000000000001' $$,
    array['想到你'::text],
    'the independent Moment preserves the status at creation time'
);

select lives_ok(
    $$ select public.set_current_relationship_status(
        'e0000000-0000-0000-0000-000000000001',
        'quiet',
        target_expiration_kind => 'manual'
    ) $$,
    'later status changes do not rewrite the saved Moment'
);

select results_eq(
    $$ select text_content from public.moments
       where client_id = 'e1000000-0000-0000-0000-000000000001' $$,
    array['想到你'::text],
    'the saved Moment remains immutable after status changes'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);

select results_eq(
    $$ select display_name from public.user_profiles
       where user_id = '00000000-0000-0000-0000-0000000000e1' $$,
    array['小日'::text],
    'the active partner can read the display name'
);

select is_empty(
    $$ select private_name from public.relationship_partner_aliases
       where relationship_id = 'e0000000-0000-0000-0000-000000000001' $$,
    'the partner cannot read the owner-only private name'
);

select results_eq(
    $$ select status_kind from public.current_relationship_statuses
       where relationship_id = 'e0000000-0000-0000-0000-000000000001' $$,
    array['quiet'::text],
    'the active partner can read the current status'
);

reset role;
update public.current_relationship_statuses
set expires_at = now() - interval '1 second',
    expiration_kind = 'one_hour'
where relationship_id = 'e0000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);
select is_empty(
    $$ select status_kind from public.current_relationship_statuses
       where relationship_id = 'e0000000-0000-0000-0000-000000000001' $$,
    'expired statuses are filtered by server time'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e3', true);

select is_empty(
    $$ select display_name from public.user_profiles $$,
    'a third user cannot read display names'
);

select is_empty(
    $$ select status_kind from public.current_relationship_statuses $$,
    'a third user cannot read current statuses'
);

select throws_ok(
    $$ select public.set_current_relationship_status(
        'e0000000-0000-0000-0000-000000000001',
        'busy',
        target_expiration_kind => 'manual'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot set a status'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true);

select lives_ok(
    $$ select public.clear_current_relationship_status(
        'e0000000-0000-0000-0000-000000000001'
    ) $$,
    'the owner can clear their current status'
);

select results_eq(
    $$ select count(*)::integer from public.current_relationship_statuses
       where relationship_id = 'e0000000-0000-0000-0000-000000000001' $$,
    array[0],
    'clearing removes the current status without creating history'
);

select lives_ok(
    $$ select public.set_current_relationship_status(
        'e0000000-0000-0000-0000-000000000001',
        'tired',
        target_expiration_kind => 'manual'
    ) $$,
    'a current status exists before relationship closing'
);

select public.begin_unpairing('e0000000-0000-0000-0000-000000000001');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);

select is_empty(
    $$ select display_name from public.user_profiles
       where user_id = '00000000-0000-0000-0000-0000000000e1' $$,
    'a former partner cannot read the display name after relationship closing'
);

select is_empty(
    $$ select status_kind from public.current_relationship_statuses
       where relationship_id = 'e0000000-0000-0000-0000-000000000001' $$,
    'a former partner cannot read current status after relationship closing'
);

select throws_ok(
    $$ select public.set_current_relationship_status(
        'e0000000-0000-0000-0000-000000000001',
        'busy',
        target_expiration_kind => 'manual'
    ) $$,
    '23514',
    'relationship_not_paired',
    'a closing relationship rejects status updates'
);

select * from finish();
rollback;
