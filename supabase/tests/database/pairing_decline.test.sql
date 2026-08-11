begin;

create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'decline-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'decline-b@example.test', ''),
    ('00000000-0000-0000-0000-000000000023', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'decline-c@example.test', '');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', true);
select * from public.create_relationship_invitation();

reset role;
select set_config(
    'test.declined_invite_token',
    (select invite_token::text from public.relationship_invitations limit 1),
    true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', true);
select throws_ok(
    format(
        'select public.decline_relationship_invitation(%L::uuid)',
        current_setting('test.declined_invite_token')
    ),
    '42501',
    'cannot_decline_own_invitation',
    'creator cannot decline their own invitation'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', true);
select lives_ok(
    format(
        'select public.decline_relationship_invitation(%L::uuid)',
        current_setting('test.declined_invite_token')
    ),
    'invited participant can decline an invitation'
);

reset role;
select ok(
    (select declined_at is not null from public.relationship_invitations limit 1),
    'decline is recorded on the server'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000023', true);
select throws_ok(
    format(
        'select public.accept_relationship_invitation(%L::uuid)',
        current_setting('test.declined_invite_token')
    ),
    '22023',
    'invitation_not_available',
    'declined invitation cannot be accepted'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', true);
select isnt(
    (select invite_token::text from public.create_relationship_invitation()),
    current_setting('test.declined_invite_token'),
    'creator receives a rotated token after decline'
);

reset role;
select ok(
    (select declined_at is null from public.relationship_invitations limit 1),
    'retry clears the previous decline outcome'
);

select results_eq(
    $$ select count(*)::integer from public.relationships $$,
    array[1],
    'retry reuses the same relationship'
);

select * from finish();
rollback;
