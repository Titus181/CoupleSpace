begin;

create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cancel-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cancel-b@example.test', '');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', true);
select * from public.create_relationship_invitation();

reset role;
select set_config(
    'test.cancel_relationship_id',
    (select relationship_id::text from public.relationship_invitations limit 1),
    true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000032', true);
select throws_ok(
    $$ select public.cancel_relationship_invitation() $$,
    '23514',
    'invitation_not_cancellable',
    'another participant cannot cancel the creator invitation'
);

reset role;
insert into public.shared_items (relationship_id, client_id, creator_user_id, item_kind)
values (
    current_setting('test.cancel_relationship_id')::uuid,
    '00000000-0000-0000-0000-000000000039',
    '00000000-0000-0000-0000-000000000031',
    'marker'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', true);
select throws_ok(
    $$ select public.cancel_relationship_invitation() $$,
    '23514',
    'relationship_not_empty',
    'creator cannot cancel a relationship containing shared data'
);

reset role;
select is(
    (select count(*)::integer from public.relationships),
    1,
    'rejected cancellation preserves the relationship'
);

delete from public.shared_items
where relationship_id = current_setting('test.cancel_relationship_id')::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', true);
select lives_ok(
    $$ select public.cancel_relationship_invitation() $$,
    'creator can cancel an empty one-person invitation relationship'
);

reset role;
select is(
    (select count(*)::integer from public.relationships),
    0,
    'cancellation removes the empty relationship'
);
select is(
    (select count(*)::integer from public.relationship_members),
    0,
    'cancellation removes the active membership'
);
select is(
    (select count(*)::integer from public.relationship_invitations),
    0,
    'cancellation removes the invitation'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', true);
select * from public.create_relationship_invitation();

reset role;
select set_config(
    'test.accepted_invite_token',
    (select invite_token::text from public.relationship_invitations limit 1),
    true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000032', true);
select public.accept_relationship_invitation(
    current_setting('test.accepted_invite_token')::uuid
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', true);
select throws_ok(
    $$ select public.cancel_relationship_invitation() $$,
    '23514',
    'invitation_not_cancellable',
    'creator cannot cancel an accepted relationship'
);

reset role;
select is(
    (select count(*)::integer from public.relationship_members where membership_status = 'active'),
    2,
    'failed cancellation preserves both accepted members'
);

select * from finish();
rollback;
