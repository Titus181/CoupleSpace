begin;

create extension if not exists pgtap with schema extensions;
select plan(27);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'interaction-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'interaction-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'interaction-c@example.test', '');

insert into public.relationships (id)
values ('c0000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000c1'),
    ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000c2');

select results_eq(
    $$ select question_key || '/' || prompt_zh_hant
       from public.moment_question_bank
       where is_active
       order by display_order $$,
    array[
        'understand_today/今天最希望我理解你什麼？'::text,
        'recent_small_happiness/最近有哪件小事讓你感到幸福？'::text,
        'together_this_week/這週想一起完成什麼？'::text,
        'unsaid_recently/最近有沒有想說、但一直沒找到時機的事？'::text
    ],
    'W6 starts with the four accepted fixed questions and canonical prompts'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);

select lives_ok(
    $$ select public.create_moment(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        'text',
        target_text_content => '今天有點累'
    ) $$,
    'A can create the original Moment'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', true);

select lives_ok(
    $$ select public.create_moment_response(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000001',
        'emoji',
        target_emoji_value => 'hug'
    ) $$,
    'B can respond to the partner Moment with an accepted emoji'
);

select lives_ok(
    $$ select public.create_moment_response(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000001',
        'emoji',
        target_emoji_value => 'hug'
    ) $$,
    'retrying the same response identity and content is accepted'
);

reset role;
select results_eq(
    $$ select count(*)::integer from public.moment_responses $$,
    array[1],
    'an accepted retry creates no duplicate response'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', true);

select throws_ok(
    $$ select public.create_moment_response(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000002',
        'emoji',
        target_emoji_value => 'angry'
    ) $$,
    '22023',
    'invalid_moment_response',
    'unsupported emoji values are rejected'
);

select throws_ok(
    $$ select public.create_moment_response(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000003',
        'text',
        target_text_content => '換一則回應'
    ) $$,
    '23505',
    null,
    'one partner cannot create a second response for the same Moment'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);

select throws_ok(
    $$ select public.create_moment_response(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000004',
        'text',
        target_text_content => '自己的回應'
    ) $$,
    '23514',
    'creator_cannot_respond',
    'the Moment creator cannot respond to their own Moment'
);

select throws_ok(
    $$ insert into public.moment_responses (
        relationship_id, moment_client_id, client_id, responder_user_id, kind, emoji_value
    ) values (
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000005',
        '00000000-0000-0000-0000-0000000000c1',
        'emoji',
        'heart'
    ) $$,
    '42501',
    null,
    'authenticated clients cannot bypass the response RPC'
);

select results_eq(
    $$ select count(*)::integer from public.moment_responses $$,
    array[1],
    'A can read the relationship response'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', true);

select results_eq(
    $$ select count(*)::integer from public.moment_responses $$,
    array[0],
    'a third user cannot read Moment responses'
);

select throws_ok(
    $$ select public.create_moment_response(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000006',
        'text',
        target_text_content => '越權回應'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot respond to the private Moment'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);

select lives_ok(
    $$ select public.create_question_moment(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000010',
        'recent_small_happiness',
        'c3000000-0000-0000-0000-000000000001',
        '  下班一起吃飯  '
    ) $$,
    'A can create a fixed question and answer atomically'
);

select results_eq(
    $$ select count(*)::integer from public.moments where kind = 'question' $$,
    array[1],
    'the question is one Moment in the shared timeline'
);

select results_eq(
    $$ select answer_content
       from public.moment_question_answers
       where moment_client_id = 'c1000000-0000-0000-0000-000000000010' $$,
    array['下班一起吃飯'::text],
    'A sees the normalized answer they submitted'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', true);

select results_eq(
    $$ select count(*)::integer
       from public.moment_question_answers
       where moment_client_id = 'c1000000-0000-0000-0000-000000000010' $$,
    array[0],
    'B cannot read A answer before submitting their own'
);

select lives_ok(
    $$ select public.answer_moment_question(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000010',
        'c3000000-0000-0000-0000-000000000002',
        '有人記得我喜歡的飲料'
    ) $$,
    'B can submit the second answer'
);

select results_eq(
    $$ select count(*)::integer
       from public.moment_question_answers
       where moment_client_id = 'c1000000-0000-0000-0000-000000000010' $$,
    array[2],
    'B sees both answers after the joint reveal'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);

select results_eq(
    $$ select count(*)::integer
       from public.moment_question_answers
       where moment_client_id = 'c1000000-0000-0000-0000-000000000010' $$,
    array[2],
    'A also sees both answers after the joint reveal'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', true);

select lives_ok(
    $$ select public.answer_moment_question(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000010',
        'c3000000-0000-0000-0000-000000000002',
        '有人記得我喜歡的飲料'
    ) $$,
    'retrying the same question answer is accepted'
);

reset role;
select results_eq(
    $$ select count(*)::integer from public.moment_question_answers $$,
    array[2],
    'an accepted answer retry creates no duplicate'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', true);

select throws_ok(
    $$ select public.answer_moment_question(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000010',
        'c3000000-0000-0000-0000-000000000003',
        repeat('a', 281)
    ) $$,
    '22023',
    'invalid_question_answer',
    'an oversized question answer is rejected'
);

select throws_ok(
    $$ select public.create_moment_response(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000010',
        'c2000000-0000-0000-0000-000000000007',
        'emoji',
        target_emoji_value => 'heart'
    ) $$,
    '23514',
    'question_requires_answer',
    'a question uses answers rather than ordinary Moment responses'
);

select throws_ok(
    $$ insert into public.moment_question_answers (
        relationship_id, moment_client_id, client_id, answerer_user_id, answer_content
    ) values (
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000010',
        'c3000000-0000-0000-0000-000000000004',
        '00000000-0000-0000-0000-0000000000c2',
        '繞過 RPC'
    ) $$,
    '42501',
    null,
    'authenticated clients cannot bypass the question answer RPC'
);

reset role;
select results_eq(
    $$ select question_prompt
       from public.moments
       where client_id = 'c1000000-0000-0000-0000-000000000010' $$,
    array['最近有哪件小事讓你感到幸福？'::text],
    'the canonical question prompt is snapshotted into the Moment'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);
select public.begin_unpairing('c0000000-0000-0000-0000-000000000001');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', true);

select throws_ok(
    $$ select public.create_moment_response(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000008',
        'text',
        target_text_content => '關係已關閉'
    ) $$,
    '23514',
    'relationship_not_active_pair',
    'a closing relationship rejects new Moment responses'
);

select throws_ok(
    $$ select public.create_question_moment(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000011',
        'understand_today',
        'c3000000-0000-0000-0000-000000000005',
        '關係已關閉'
    ) $$,
    '23514',
    'relationship_not_active_pair',
    'a closing relationship rejects new question Moments'
);

select * from finish();
rollback;
