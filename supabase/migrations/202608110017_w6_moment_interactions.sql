alter table public.moments
    add column question_key text,
    add column question_prompt text;

alter table public.moments
    drop constraint moments_kind_check,
    drop constraint moments_content_matches_kind;

alter table public.moments
    add constraint moments_kind_check
        check (kind in ('mood', 'text', 'photo', 'question')),
    add constraint moments_content_matches_kind check (
        (kind = 'mood'
            and mood_value is not null
            and text_content is null
            and media_byte_size is null
            and question_key is null
            and question_prompt is null)
        or (kind = 'text'
            and mood_value is null
            and text_content is not null
            and char_length(text_content) between 1 and 280
            and media_byte_size is null
            and question_key is null
            and question_prompt is null)
        or (kind = 'photo'
            and mood_value is null
            and text_content is null
            and media_byte_size > 0
            and question_key is null
            and question_prompt is null)
        or (kind = 'question'
            and mood_value is null
            and text_content is null
            and media_byte_size is null
            and question_key is not null
            and question_prompt is not null)
    );

create table public.moment_question_bank (
    question_key text primary key,
    prompt_zh_hant text not null check (char_length(prompt_zh_hant) between 1 and 280),
    display_order integer not null unique,
    is_active boolean not null default true
);

insert into public.moment_question_bank (question_key, prompt_zh_hant, display_order)
values
    ('understand_today', '今天最希望我理解你什麼？', 1),
    ('recent_small_happiness', '最近有哪件小事讓你感到幸福？', 2),
    ('together_this_week', '這週想一起完成什麼？', 3),
    ('unsaid_recently', '最近有沒有想說、但一直沒找到時機的事？', 4);

alter table public.moment_question_bank enable row level security;

create policy "Authenticated users can read the fixed Moment question bank"
on public.moment_question_bank for select
to authenticated
using (true);

revoke all on public.moment_question_bank from anon, authenticated;
grant select on public.moment_question_bank to authenticated;

create table public.moment_responses (
    id uuid primary key default gen_random_uuid(),
    relationship_id uuid not null,
    moment_client_id uuid not null,
    client_id uuid not null,
    responder_user_id uuid not null references auth.users(id),
    kind text not null check (kind in ('emoji', 'text')),
    emoji_value text,
    text_content text,
    created_at timestamptz not null default now(),
    unique (relationship_id, client_id),
    unique (relationship_id, moment_client_id, responder_user_id),
    foreign key (relationship_id, moment_client_id)
        references public.moments(relationship_id, client_id)
        on delete cascade,
    constraint moment_responses_content_matches_kind check (
        (kind = 'emoji'
            and emoji_value in ('heart', 'hug', 'smile', 'cheer', 'laugh', 'support')
            and text_content is null)
        or (kind = 'text'
            and emoji_value is null
            and text_content is not null
            and char_length(text_content) between 1 and 80)
    )
);

alter table public.moment_responses enable row level security;

create policy "Current members can read Moment responses"
on public.moment_responses for select
to authenticated
using (public.is_current_relationship_member(relationship_id));

revoke all on public.moment_responses from anon, authenticated;
grant select on public.moment_responses to authenticated;

create table public.moment_question_answers (
    id uuid primary key default gen_random_uuid(),
    relationship_id uuid not null,
    moment_client_id uuid not null,
    client_id uuid not null,
    answerer_user_id uuid not null references auth.users(id),
    answer_content text not null check (char_length(answer_content) between 1 and 280),
    created_at timestamptz not null default now(),
    unique (relationship_id, client_id),
    unique (relationship_id, moment_client_id, answerer_user_id),
    foreign key (relationship_id, moment_client_id)
        references public.moments(relationship_id, client_id)
        on delete cascade
);

alter table public.moment_question_answers enable row level security;

create function public.is_moment_question_revealed(
    target_relationship_id uuid,
    target_moment_client_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select public.is_current_relationship_member(target_relationship_id)
       and count(distinct answer.answerer_user_id) = 2
    from public.moment_question_answers answer
    where answer.relationship_id = target_relationship_id
      and answer.moment_client_id = target_moment_client_id;
$$;

revoke all on function public.is_moment_question_revealed(uuid, uuid) from public;
grant execute on function public.is_moment_question_revealed(uuid, uuid) to authenticated;

create policy "Members see their own answer until both have answered"
on public.moment_question_answers for select
to authenticated
using (
    public.is_current_relationship_member(relationship_id)
    and (
        answerer_user_id = (select auth.uid())
        or public.is_moment_question_revealed(relationship_id, moment_client_id)
    )
);

revoke all on public.moment_question_answers from anon, authenticated;
grant select on public.moment_question_answers to authenticated;

create function public.create_moment_response(
    target_relationship_id uuid,
    target_moment_client_id uuid,
    target_client_id uuid,
    target_kind text,
    target_emoji_value text default null,
    target_text_content text default null
)
returns table (
    moment_client_id uuid,
    client_id uuid,
    responder_user_id uuid,
    kind text,
    emoji_value text,
    text_content text,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    normalized_text text := btrim(target_text_content, E' \t\n\r');
    moment_creator_id uuid;
    moment_kind text;
    active_member_count integer;
    relationship_status text;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    select count(*)
    into active_member_count
    from public.relationship_members member
    where member.relationship_id = target_relationship_id
      and member.membership_status = 'active';

    if relationship_status <> 'active' or active_member_count <> 2 then
        raise exception 'relationship_not_active_pair' using errcode = '23514';
    end if;

    select moment.creator_user_id, moment.kind
    into moment_creator_id, moment_kind
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_moment_client_id;

    if moment_creator_id is null then
        raise exception 'moment_not_found' using errcode = 'P0002';
    end if;
    if moment_creator_id = participant_id then
        raise exception 'creator_cannot_respond' using errcode = '23514';
    end if;
    if moment_kind = 'question' then
        raise exception 'question_requires_answer' using errcode = '23514';
    end if;

    if target_kind = 'emoji' then
        if target_emoji_value is null
           or target_emoji_value not in ('heart', 'hug', 'smile', 'cheer', 'laugh', 'support')
           or target_text_content is not null then
            raise exception 'invalid_moment_response' using errcode = '22023';
        end if;
    elsif target_kind = 'text' then
        if normalized_text is null
           or char_length(normalized_text) not between 1 and 80
           or target_emoji_value is not null then
            raise exception 'invalid_moment_response' using errcode = '22023';
        end if;
    else
        raise exception 'invalid_moment_response_kind' using errcode = '22023';
    end if;

    insert into public.moment_responses (
        relationship_id,
        moment_client_id,
        client_id,
        responder_user_id,
        kind,
        emoji_value,
        text_content
    ) values (
        target_relationship_id,
        target_moment_client_id,
        target_client_id,
        participant_id,
        target_kind,
        target_emoji_value,
        case when target_kind = 'text' then normalized_text else null end
    )
    on conflict on constraint moment_responses_relationship_id_client_id_key do nothing;

    if not exists (
        select 1
        from public.moment_responses response
        where response.relationship_id = target_relationship_id
          and response.moment_client_id = target_moment_client_id
          and response.client_id = target_client_id
          and response.responder_user_id = participant_id
          and response.kind = target_kind
          and response.emoji_value is not distinct from target_emoji_value
          and response.text_content is not distinct from (
              case when target_kind = 'text' then normalized_text else null end
          )
    ) then
        raise exception 'moment_response_identity_collision' using errcode = '23505';
    end if;

    return query
    select
        response.moment_client_id,
        response.client_id,
        response.responder_user_id,
        response.kind,
        response.emoji_value,
        response.text_content,
        response.created_at
    from public.moment_responses response
    where response.relationship_id = target_relationship_id
      and response.client_id = target_client_id;
end;
$$;

revoke all on function public.create_moment_response(uuid, uuid, uuid, text, text, text) from public;
grant execute on function public.create_moment_response(uuid, uuid, uuid, text, text, text) to authenticated;

create function public.create_question_moment(
    target_relationship_id uuid,
    target_moment_client_id uuid,
    target_question_key text,
    target_answer_client_id uuid,
    target_answer_content text
)
returns table (
    moment_client_id uuid,
    creator_user_id uuid,
    question_key text,
    question_prompt text,
    answer_client_id uuid,
    answer_content text,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    normalized_answer text := btrim(target_answer_content, E' \t\n\r');
    selected_prompt text;
    stored_moment_id uuid;
    active_member_count integer;
    relationship_status text;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    select count(*)
    into active_member_count
    from public.relationship_members member
    where member.relationship_id = target_relationship_id
      and member.membership_status = 'active';

    if relationship_status <> 'active' or active_member_count <> 2 then
        raise exception 'relationship_not_active_pair' using errcode = '23514';
    end if;

    select question.prompt_zh_hant
    into selected_prompt
    from public.moment_question_bank question
    where question.question_key = target_question_key
      and question.is_active;

    if selected_prompt is null then
        raise exception 'question_not_available' using errcode = '22023';
    end if;
    if normalized_answer is null or char_length(normalized_answer) not between 1 and 280 then
        raise exception 'invalid_question_answer' using errcode = '22023';
    end if;

    insert into public.moments (
        relationship_id,
        client_id,
        creator_user_id,
        kind,
        question_key,
        question_prompt
    ) values (
        target_relationship_id,
        target_moment_client_id,
        participant_id,
        'question',
        target_question_key,
        selected_prompt
    )
    on conflict on constraint moments_relationship_id_client_id_key do nothing;

    select moment.id
    into stored_moment_id
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_moment_client_id
      and moment.creator_user_id = participant_id
      and moment.kind = 'question'
      and moment.question_key = target_question_key
      and moment.question_prompt = selected_prompt;

    if stored_moment_id is null then
        raise exception 'moment_identity_collision' using errcode = '23505';
    end if;

    insert into public.moment_question_answers (
        relationship_id,
        moment_client_id,
        client_id,
        answerer_user_id,
        answer_content
    ) values (
        target_relationship_id,
        target_moment_client_id,
        target_answer_client_id,
        participant_id,
        normalized_answer
    )
    on conflict on constraint moment_question_answers_relationship_id_client_id_key do nothing;

    if not exists (
        select 1
        from public.moment_question_answers answer
        where answer.relationship_id = target_relationship_id
          and answer.moment_client_id = target_moment_client_id
          and answer.client_id = target_answer_client_id
          and answer.answerer_user_id = participant_id
          and answer.answer_content = normalized_answer
    ) then
        raise exception 'question_answer_identity_collision' using errcode = '23505';
    end if;

    return query
    select
        moment.client_id,
        moment.creator_user_id,
        moment.question_key,
        moment.question_prompt,
        answer.client_id,
        answer.answer_content,
        moment.created_at
    from public.moments moment
    join public.moment_question_answers answer
      on answer.relationship_id = moment.relationship_id
     and answer.moment_client_id = moment.client_id
     and answer.answerer_user_id = participant_id
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_moment_client_id;
end;
$$;

revoke all on function public.create_question_moment(uuid, uuid, text, uuid, text) from public;
grant execute on function public.create_question_moment(uuid, uuid, text, uuid, text) to authenticated;

create function public.answer_moment_question(
    target_relationship_id uuid,
    target_moment_client_id uuid,
    target_answer_client_id uuid,
    target_answer_content text
)
returns table (
    moment_client_id uuid,
    client_id uuid,
    answerer_user_id uuid,
    answer_content text,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    normalized_answer text := btrim(target_answer_content, E' \t\n\r');
    moment_creator_id uuid;
    moment_kind text;
    active_member_count integer;
    relationship_status text;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    select count(*)
    into active_member_count
    from public.relationship_members member
    where member.relationship_id = target_relationship_id
      and member.membership_status = 'active';

    if relationship_status <> 'active' or active_member_count <> 2 then
        raise exception 'relationship_not_active_pair' using errcode = '23514';
    end if;

    select moment.creator_user_id, moment.kind
    into moment_creator_id, moment_kind
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_moment_client_id;

    if moment_creator_id is null or moment_kind <> 'question' then
        raise exception 'question_moment_not_found' using errcode = 'P0002';
    end if;
    if moment_creator_id = participant_id then
        raise exception 'creator_already_answered' using errcode = '23514';
    end if;
    if normalized_answer is null or char_length(normalized_answer) not between 1 and 280 then
        raise exception 'invalid_question_answer' using errcode = '22023';
    end if;

    insert into public.moment_question_answers (
        relationship_id,
        moment_client_id,
        client_id,
        answerer_user_id,
        answer_content
    ) values (
        target_relationship_id,
        target_moment_client_id,
        target_answer_client_id,
        participant_id,
        normalized_answer
    )
    on conflict on constraint moment_question_answers_relationship_id_client_id_key do nothing;

    if not exists (
        select 1
        from public.moment_question_answers answer
        where answer.relationship_id = target_relationship_id
          and answer.moment_client_id = target_moment_client_id
          and answer.client_id = target_answer_client_id
          and answer.answerer_user_id = participant_id
          and answer.answer_content = normalized_answer
    ) then
        raise exception 'question_answer_identity_collision' using errcode = '23505';
    end if;

    return query
    select
        answer.moment_client_id,
        answer.client_id,
        answer.answerer_user_id,
        answer.answer_content,
        answer.created_at
    from public.moment_question_answers answer
    where answer.relationship_id = target_relationship_id
      and answer.client_id = target_answer_client_id;
end;
$$;

revoke all on function public.answer_moment_question(uuid, uuid, uuid, text) from public;
grant execute on function public.answer_moment_question(uuid, uuid, uuid, text) to authenticated;

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'moment_responses'
    ) then
        alter publication supabase_realtime add table public.moment_responses;
    end if;
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'moment_question_answers'
    ) then
        alter publication supabase_realtime add table public.moment_question_answers;
    end if;
end;
$$;
