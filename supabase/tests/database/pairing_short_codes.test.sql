begin;

create extension if not exists pgtap with schema extensions;
select plan(19);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'short-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'short-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'short-c@example.test', '');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
select * from public.create_relationship_invitation_v2();

reset role;
select matches(
    (select short_code from public.relationship_invitations limit 1),
    '^[2-9A-HJ-KM-NP-Z]{8}$',
    'new invitations receive an eight-character unambiguous short code'
);

select is(
    public.generate_relationship_invitation_short_code(array[
        (select short_code from public.relationship_invitations limit 1),
        '2345ABCD'
    ]),
    '2345ABCD',
    'short-code generation retries after a deterministic collision'
);

select set_config(
    'test.short_code',
    (select short_code from public.relationship_invitations limit 1),
    true
);
select set_config(
    'test.invite_token',
    (select invite_token::text from public.relationship_invitations limit 1),
    true
);
select set_config(
    'test.relationship_id',
    (select relationship_id::text from public.relationship_invitations limit 1),
    true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
select results_eq(
    $$ select short_code from public.create_relationship_invitation_v2() $$,
    array[current_setting('test.short_code')],
    'creator recovers the same active short code after restart'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
select results_eq(
    format(
        $$ select result from public.accept_relationship_invitation_v2(%L) $$,
        lower(substr(current_setting('test.short_code'), 1, 4))
            || ' - '
            || lower(substr(current_setting('test.short_code'), 5, 4))
    ),
    array['accepted'::text],
    'normalized lowercase short code with spaces and hyphen is accepted'
);

reset role;
select results_eq(
    $$ select count(*)::integer from public.relationship_members where relationship_id = current_setting('test.relationship_id')::uuid $$,
    array[2],
    'short-code acceptance creates exactly two members'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', true);
select results_eq(
    format(
        $$ select result from public.accept_relationship_invitation_v2(%L) $$,
        current_setting('test.short_code')
    ),
    array['invitation_not_available'::text],
    'used short code returns the neutral unavailable result'
);

reset role;
delete from public.relationship_members
where relationship_id = current_setting('test.relationship_id')::uuid
  and user_id = '00000000-0000-0000-0000-0000000000a2';
update public.relationship_invitations
set accepted_by_user_id = null,
    accepted_at = null
where relationship_id = current_setting('test.relationship_id')::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
select results_eq(
    format(
        $$ select result from public.accept_relationship_invitation_v2(%L) $$,
        current_setting('test.invite_token')
    ),
    array['accepted'::text],
    'legacy full UUID token remains accepted'
);

reset role;
delete from public.relationships;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
select * from public.create_relationship_invitation_v2();

reset role;
select set_config(
    'test.decline_code',
    (select short_code from public.relationship_invitations limit 1),
    true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
select is(
    public.decline_relationship_invitation_v2(current_setting('test.decline_code')),
    'declined',
    'short code can decline an invitation'
);

reset role;
select ok(
    (select declined_at is not null from public.relationship_invitations limit 1),
    'short-code decline records the server outcome'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
select * from public.create_relationship_invitation_v2();

reset role;
select isnt(
    (select short_code from public.relationship_invitations limit 1),
    current_setting('test.decline_code'),
    'retry after decline rotates the short code'
);

select set_config(
    'test.rotated_code',
    (select short_code from public.relationship_invitations limit 1),
    true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
select results_eq(
    format(
        $$ select result from public.accept_relationship_invitation_v2(%L) $$,
        current_setting('test.decline_code')
    ),
    array['invitation_not_available'::text],
    'rotated short code is immediately invalid'
);

select results_eq(
    $$ select result from public.accept_relationship_invitation_v2('ZZZZZZZZ') $$,
    array['invitation_not_available'::text],
    'first invalid attempt is neutral'
);
select results_eq(
    $$ select result from public.accept_relationship_invitation_v2('YYYYYYYY') $$,
    array['invitation_not_available'::text],
    'second invalid attempt is neutral'
);
select results_eq(
    $$ select result from public.accept_relationship_invitation_v2('XXXXXXXX') $$,
    array['invitation_not_available'::text],
    'third invalid attempt is neutral'
);
select results_eq(
    $$ select result from public.accept_relationship_invitation_v2('WWWWWWWW') $$,
    array['invitation_not_available'::text],
    'fourth invalid attempt is neutral'
);

select results_eq(
    format(
        $$ select result from public.accept_relationship_invitation_v2(%L) $$,
        current_setting('test.rotated_code')
    ),
    array['invitation_not_available'::text],
    'a user at five invalid attempts cannot use another identifier'
);

reset role;
select is(
    (
        select invalid_attempt_count
        from public.relationship_invitation_invalid_attempts
        where user_id = '00000000-0000-0000-0000-0000000000a2'
    ),
    5,
    'server stores at most five invalid attempts'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
select results_eq(
    format(
        $$ select result from public.accept_relationship_invitation_v2(%L) $$,
        current_setting('test.rotated_code')
    ),
    array['invitation_not_available'::text],
    'rate-limited user cannot probe a valid code during the window'
);

reset role;
update public.relationship_invitation_invalid_attempts
set window_started_at = now() - interval '11 minutes'
where user_id = '00000000-0000-0000-0000-0000000000a2';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
select results_eq(
    format(
        $$ select result from public.accept_relationship_invitation_v2(%L) $$,
        current_setting('test.rotated_code')
    ),
    array['accepted'::text],
    'valid short code works after the rate-limit window resets'
);

select * from finish();
rollback;
