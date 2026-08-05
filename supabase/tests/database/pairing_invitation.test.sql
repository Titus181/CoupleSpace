begin;

create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pairing-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pairing-b@example.test', ''),
    ('00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pairing-c@example.test', ''),
    ('00000000-0000-0000-0000-000000000014', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pairing-d@example.test', '');

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000011',
    true
);

select lives_ok(
    $$ select * from public.create_relationship_invitation() $$,
    'first participant can create a pairing invitation'
);

reset role;

select results_eq(
    $$ select count(*)::integer from public.relationships $$,
    array[1],
    'creating an invitation creates one relationship'
);

select results_eq(
    $$ select count(*)::integer from public.relationship_members $$,
    array[1],
    'creating an invitation adds only its creator'
);

select results_eq(
    $$ select count(*)::integer from public.relationship_invitations $$,
    array[1],
    'creating an invitation stores one server-only token'
);

select set_config(
    'test.first_invite_token',
    (select invite_token::text from public.relationship_invitations limit 1),
    true
);

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000011',
    true
);

select results_eq(
    $$ select invite_token::text from public.create_relationship_invitation() $$,
    array[current_setting('test.first_invite_token')],
    'creator can recover the same unaccepted invitation after restart'
);

select throws_ok(
    format(
        'select public.accept_relationship_invitation(%L::uuid)',
        current_setting('test.first_invite_token')
    ),
    '42501',
    'cannot_accept_own_invitation',
    'creator cannot accept their own invitation'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000012',
    true
);

select lives_ok(
    format(
        'select public.accept_relationship_invitation(%L::uuid)',
        current_setting('test.first_invite_token')
    ),
    'second participant can accept the invitation'
);

reset role;

select results_eq(
    $$ select count(*)::integer from public.relationship_members $$,
    array[2],
    'accepted relationship has exactly two members'
);

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000013',
    true
);

select throws_ok(
    format(
        'select public.accept_relationship_invitation(%L::uuid)',
        current_setting('test.first_invite_token')
    ),
    '22023',
    'invitation_not_available',
    'used invitation cannot be accepted again'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000012',
    true
);

select throws_ok(
    $$ select * from public.create_relationship_invitation() $$,
    '23505',
    'participant_already_paired',
    'joined participant cannot create another active relationship'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000013',
    true
);
select * from public.create_relationship_invitation();

reset role;
update public.relationship_invitations
set expires_at = now() - interval '1 minute'
where created_by_user_id = '00000000-0000-0000-0000-000000000013';

select set_config(
    'test.expired_invite_token',
    (
        select invite_token::text
        from public.relationship_invitations
        where created_by_user_id = '00000000-0000-0000-0000-000000000013'
    ),
    true
);

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000014',
    true
);

select throws_ok(
    format(
        'select public.accept_relationship_invitation(%L::uuid)',
        current_setting('test.expired_invite_token')
    ),
    '22023',
    'invitation_not_available',
    'expired invitation cannot be accepted'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000013',
    true
);

select isnt(
    (select invite_token::text from public.create_relationship_invitation()),
    current_setting('test.expired_invite_token'),
    'creator receives a rotated token after expiration'
);

select * from finish();
rollback;
