-- W14-02 Moment soft deletion, interaction removal, and 30-day restore.

alter table public.moments
    add column deleted_at timestamptz,
    add column purge_after timestamptz,
    add column lifecycle_revision bigint not null default 0,
    add constraint moments_soft_deletion_window check (
        (deleted_at is null and purge_after is null)
        or (
            deleted_at is not null
            and purge_after is not null
            and purge_after = deleted_at + interval '30 days'
        )
    ),
    add constraint moments_lifecycle_revision_nonnegative check (
        lifecycle_revision >= 0
    );

create index moments_active_collection_idx
on public.moments (relationship_id, created_at, client_id)
where deleted_at is null;

create index moments_recently_deleted_idx
on public.moments (relationship_id, creator_user_id, deleted_at desc, client_id)
where deleted_at is not null;

create index moments_lifecycle_sync_idx
on public.moments (relationship_id, client_id)
where lifecycle_revision > 0;

alter table public.moment_question_answers
    alter column answer_content drop not null,
    drop constraint moment_question_answers_answer_content_check,
    add column removed_at timestamptz,
    add constraint moment_question_answers_content_or_removed check (
        (
            removed_at is null
            and answer_content is not null
            and char_length(answer_content) between 1 and 280
        )
        or (removed_at is not null and answer_content is null)
    );

create table public.moment_lifecycle_operations (
    relationship_id uuid not null,
    operation_id uuid not null,
    moment_client_id uuid not null,
    interaction_client_id uuid,
    actor_user_id uuid not null references auth.users(id),
    operation_kind text not null check (
        operation_kind in ('delete', 'restore', 'remove_response', 'remove_answer')
    ),
    created_at timestamptz not null default statement_timestamp(),
    primary key (relationship_id, operation_id),
    foreign key (relationship_id, moment_client_id)
        references public.moments(relationship_id, client_id)
        on delete cascade,
    constraint moment_lifecycle_operation_target_matches_kind check (
        (
            operation_kind in ('delete', 'restore')
            and interaction_client_id is null
        )
        or (
            operation_kind in ('remove_response', 'remove_answer')
            and interaction_client_id is not null
        )
    )
);

create index moment_lifecycle_operations_target_idx
on public.moment_lifecycle_operations (relationship_id, moment_client_id);

create index moment_lifecycle_removed_response_idx
on public.moment_lifecycle_operations (
    relationship_id,
    moment_client_id,
    interaction_client_id
)
where operation_kind = 'remove_response';

alter table public.moment_lifecycle_operations enable row level security;
revoke all on public.moment_lifecycle_operations from anon, authenticated;
grant select on public.moment_lifecycle_operations to service_role;

create function public.is_active_relationship_member(target_relationship_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.relationship_members member
        join public.relationships relationship
          on relationship.id = member.relationship_id
        where member.relationship_id = target_relationship_id
          and member.user_id = (select auth.uid())
          and member.membership_status = 'active'
          and relationship.status = 'active'
    );
$$;

revoke all on function public.is_active_relationship_member(uuid) from public;
grant execute on function public.is_active_relationship_member(uuid) to authenticated;

create function public.can_read_moment_interactions(
    target_relationship_id uuid,
    target_moment_client_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select public.is_active_relationship_member(target_relationship_id)
       and exists (
           select 1
           from public.moments moment
           where moment.relationship_id = target_relationship_id
             and moment.client_id = target_moment_client_id
             and (
                 moment.deleted_at is null
                 or (
                     moment.creator_user_id = (select auth.uid())
                     and moment.purge_after > statement_timestamp()
                 )
             )
       );
$$;

revoke all on function public.can_read_moment_interactions(uuid, uuid)
from public;
grant execute on function public.can_read_moment_interactions(uuid, uuid)
to authenticated;

drop policy if exists "Current members can read moments" on public.moments;
create policy "Active members can read live Moments"
on public.moments for select
to authenticated
using (
    deleted_at is null
    and public.is_active_relationship_member(relationship_id)
);

drop policy if exists "Current members can read Moment responses"
on public.moment_responses;
create policy "Active members can read live Moment responses"
on public.moment_responses for select
to authenticated
using (
    public.can_read_moment_interactions(relationship_id, moment_client_id)
);

drop policy if exists "Members see their own answer until both have answered"
on public.moment_question_answers;
create policy "Active members follow reveal rules for live Moment answers"
on public.moment_question_answers for select
to authenticated
using (
    public.can_read_moment_interactions(relationship_id, moment_client_id)
    and (
        answerer_user_id = (select auth.uid())
        or public.is_moment_question_revealed(
            relationship_id,
            moment_client_id
        )
    )
);

revoke insert, update, delete on public.moments from anon, authenticated;
revoke insert, update, delete on public.moment_responses from anon, authenticated;
revoke insert, update, delete on public.moment_question_answers from anon, authenticated;

create or replace function public.is_moment_question_revealed(
    target_relationship_id uuid,
    target_moment_client_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select public.is_active_relationship_member(target_relationship_id)
       and exists (
           select 1
           from public.moments moment
           where moment.relationship_id = target_relationship_id
             and moment.client_id = target_moment_client_id
             and moment.kind = 'question'
             and (
                 moment.deleted_at is null
                 or (
                     moment.creator_user_id = (select auth.uid())
                     and moment.purge_after > statement_timestamp()
                 )
             )
       )
       and (
           select count(distinct answer.answerer_user_id) = 2
           from public.moment_question_answers answer
           where answer.relationship_id = target_relationship_id
             and answer.moment_client_id = target_moment_client_id
       );
$$;

revoke all on function public.is_moment_question_revealed(uuid, uuid) from public;
grant execute on function public.is_moment_question_revealed(uuid, uuid)
to authenticated;

create function public.reject_deleted_moment_recreation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    existing_deleted_at timestamptz;
begin
    select moment.deleted_at
    into existing_deleted_at
    from public.moments moment
    where moment.relationship_id = new.relationship_id
      and moment.client_id = new.client_id
    for share;

    if found and existing_deleted_at is not null then
        raise exception 'moment_deleted' using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger reject_deleted_moment_recreation
before insert on public.moments
for each row execute function public.reject_deleted_moment_recreation();

revoke all on function public.reject_deleted_moment_recreation() from public;

create function public.require_live_moment_for_interaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    parent_deleted_at timestamptz;
begin
    select moment.deleted_at
    into parent_deleted_at
    from public.moments moment
    where moment.relationship_id = new.relationship_id
      and moment.client_id = new.moment_client_id
    for share;

    if not found then
        raise exception 'moment_not_found' using errcode = 'P0002';
    end if;
    if parent_deleted_at is not null then
        raise exception 'moment_deleted' using errcode = '23514';
    end if;

    if tg_table_name = 'moment_responses'
       and exists (
           select 1
           from public.moment_lifecycle_operations operation
           where operation.relationship_id = new.relationship_id
             and operation.moment_client_id = new.moment_client_id
             and operation.interaction_client_id = new.client_id
             and operation.operation_kind = 'remove_response'
       ) then
        raise exception 'moment_response_removed' using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger require_live_moment_for_response
before insert on public.moment_responses
for each row execute function public.require_live_moment_for_interaction();

create trigger require_live_moment_for_answer
before insert on public.moment_question_answers
for each row execute function public.require_live_moment_for_interaction();

revoke all on function public.require_live_moment_for_interaction() from public;

create function public.can_read_moment_photo_object(
    target_relationship_id_text text,
    target_filename text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.moments moment
        where moment.relationship_id::text = target_relationship_id_text
          and lower(moment.client_id::text || '.jpg') = lower(target_filename)
          and moment.kind = 'photo'
          and public.is_active_relationship_member(moment.relationship_id)
          and (
              moment.deleted_at is null
              or (
                  moment.creator_user_id = (select auth.uid())
                  and moment.purge_after > statement_timestamp()
              )
          )
    );
$$;

revoke all on function public.can_read_moment_photo_object(text, text) from public;
grant execute on function public.can_read_moment_photo_object(text, text)
to authenticated;

drop policy if exists "Relationship members can read Moment photos"
on storage.objects;
create policy "Authorized users can read visible Moment photos"
on storage.objects for select
to authenticated
using (
    bucket_id = 'couplespace-moment-photos'
    and array_length(storage.foldername(name), 1) = 1
    and public.can_read_moment_photo_object(
        (storage.foldername(name))[1],
        storage.filename(name)
    )
);

drop policy if exists "Active relationship members receive Moment lifecycle broadcasts"
on realtime.messages;
create policy "Active relationship members receive Moment lifecycle broadcasts"
on realtime.messages for select
to authenticated
using (
    realtime.messages.extension = 'broadcast'
    and exists (
        select 1
        from public.relationship_members member
        join public.relationships relationship
          on relationship.id = member.relationship_id
        where member.user_id = (select auth.uid())
          and member.membership_status = 'active'
          and relationship.status = 'active'
          and (select realtime.topic()) =
              'relationship:' || member.relationship_id::text
    )
);

-- Supabase owns realtime.messages and retains its platform ACL. Intentionally
-- provide no INSERT policy: clients can receive this private Broadcast but an
-- authenticated direct INSERT is rejected by RLS.

create function public._delete_moment_at(
    target_relationship_id uuid,
    target_moment_client_id uuid,
    target_operation_id uuid,
    target_server_time timestamptz
)
returns setof public.moments
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    stored_moment public.moments%rowtype;
    stored_operation public.moment_lifecycle_operations%rowtype;
    inserted_operation boolean := false;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;
    if target_operation_id is null or target_server_time is null then
        raise exception 'invalid_moment_operation' using errcode = '22023';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    select moment.*
    into stored_moment
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_moment_client_id
    for update;

    if stored_moment.id is null then
        raise exception 'moment_not_found' using errcode = 'P0002';
    end if;
    if stored_moment.creator_user_id <> participant_id then
        raise exception 'moment_not_owned' using errcode = '42501';
    end if;

    insert into public.moment_lifecycle_operations (
        relationship_id,
        operation_id,
        moment_client_id,
        actor_user_id,
        operation_kind
    ) values (
        target_relationship_id,
        target_operation_id,
        target_moment_client_id,
        participant_id,
        'delete'
    )
    on conflict do nothing
    returning * into stored_operation;

    inserted_operation := stored_operation.operation_id is not null;
    if not inserted_operation then
        select operation.*
        into stored_operation
        from public.moment_lifecycle_operations operation
        where operation.relationship_id = target_relationship_id
          and operation.operation_id = target_operation_id;
    end if;

    if stored_operation.actor_user_id <> participant_id
       or stored_operation.moment_client_id <> target_moment_client_id
       or stored_operation.operation_kind <> 'delete'
       or stored_operation.interaction_client_id is not null then
        raise exception 'moment_operation_identity_collision' using errcode = '23505';
    end if;

    if not inserted_operation then
        if stored_moment.deleted_at is null
           or stored_moment.purge_after > target_server_time then
            return next stored_moment;
        end if;
        return;
    end if;

    if stored_moment.deleted_at is null then
        update public.moments moment
        set deleted_at = target_server_time,
            purge_after = target_server_time + interval '30 days',
            lifecycle_revision = moment.lifecycle_revision + 1
        where moment.id = stored_moment.id
        returning moment.* into stored_moment;

        perform realtime.send(
            jsonb_build_object(
                'moment_client_id', target_moment_client_id,
                'change_kind', 'deleted'
            ),
            'moment-lifecycle',
            'relationship:' || target_relationship_id::text,
            true
        );
    end if;

    if stored_moment.purge_after > target_server_time then
        return next stored_moment;
    end if;
end;
$$;

create function public._restore_moment_at(
    target_relationship_id uuid,
    target_moment_client_id uuid,
    target_operation_id uuid,
    target_server_time timestamptz
)
returns setof public.moments
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    stored_moment public.moments%rowtype;
    stored_operation public.moment_lifecycle_operations%rowtype;
    inserted_operation boolean := false;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;
    if target_operation_id is null or target_server_time is null then
        raise exception 'invalid_moment_operation' using errcode = '22023';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    select moment.*
    into stored_moment
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_moment_client_id
    for update;

    if stored_moment.id is null then
        raise exception 'moment_not_found' using errcode = 'P0002';
    end if;
    if stored_moment.creator_user_id <> participant_id then
        raise exception 'moment_not_owned' using errcode = '42501';
    end if;

    insert into public.moment_lifecycle_operations (
        relationship_id,
        operation_id,
        moment_client_id,
        actor_user_id,
        operation_kind
    ) values (
        target_relationship_id,
        target_operation_id,
        target_moment_client_id,
        participant_id,
        'restore'
    )
    on conflict do nothing
    returning * into stored_operation;

    inserted_operation := stored_operation.operation_id is not null;
    if not inserted_operation then
        select operation.*
        into stored_operation
        from public.moment_lifecycle_operations operation
        where operation.relationship_id = target_relationship_id
          and operation.operation_id = target_operation_id;
    end if;

    if stored_operation.actor_user_id <> participant_id
       or stored_operation.moment_client_id <> target_moment_client_id
       or stored_operation.operation_kind <> 'restore'
       or stored_operation.interaction_client_id is not null then
        raise exception 'moment_operation_identity_collision' using errcode = '23505';
    end if;

    if not inserted_operation then
        if stored_moment.deleted_at is null
           or stored_moment.purge_after > target_server_time then
            return next stored_moment;
        end if;
        return;
    end if;

    if stored_moment.deleted_at is null then
        return next stored_moment;
        return;
    end if;
    if target_server_time >= stored_moment.purge_after then
        raise exception 'moment_restore_window_expired' using errcode = '23514';
    end if;

    update public.moments moment
    set deleted_at = null,
        purge_after = null,
        lifecycle_revision = moment.lifecycle_revision + 1
    where moment.id = stored_moment.id
    returning moment.* into stored_moment;

    perform realtime.send(
        jsonb_build_object(
            'moment_client_id', target_moment_client_id,
            'change_kind', 'restored'
        ),
        'moment-lifecycle',
        'relationship:' || target_relationship_id::text,
        true
    );

    return next stored_moment;
end;
$$;

create function public.delete_moment(
    target_relationship_id uuid,
    target_moment_client_id uuid,
    target_operation_id uuid
)
returns setof public.moments
language sql
volatile
security definer
set search_path = ''
as $$
    select *
    from public._delete_moment_at(
        target_relationship_id,
        target_moment_client_id,
        target_operation_id,
        statement_timestamp()
    );
$$;

create function public.restore_moment(
    target_relationship_id uuid,
    target_moment_client_id uuid,
    target_operation_id uuid
)
returns setof public.moments
language sql
volatile
security definer
set search_path = ''
as $$
    select *
    from public._restore_moment_at(
        target_relationship_id,
        target_moment_client_id,
        target_operation_id,
        statement_timestamp()
    );
$$;

create function public.remove_moment_response(
    target_relationship_id uuid,
    target_moment_client_id uuid,
    target_interaction_client_id uuid,
    target_operation_id uuid
)
returns setof public.moments
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    stored_moment public.moments%rowtype;
    stored_response public.moment_responses%rowtype;
    stored_operation public.moment_lifecycle_operations%rowtype;
    inserted_operation boolean := false;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;
    if target_operation_id is null or target_interaction_client_id is null then
        raise exception 'invalid_moment_operation' using errcode = '22023';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    select moment.*
    into stored_moment
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_moment_client_id
    for update;

    if stored_moment.id is null then
        raise exception 'moment_not_found' using errcode = 'P0002';
    end if;

    insert into public.moment_lifecycle_operations (
        relationship_id,
        operation_id,
        moment_client_id,
        interaction_client_id,
        actor_user_id,
        operation_kind
    ) values (
        target_relationship_id,
        target_operation_id,
        target_moment_client_id,
        target_interaction_client_id,
        participant_id,
        'remove_response'
    )
    on conflict do nothing
    returning * into stored_operation;

    inserted_operation := stored_operation.operation_id is not null;
    if not inserted_operation then
        select operation.*
        into stored_operation
        from public.moment_lifecycle_operations operation
        where operation.relationship_id = target_relationship_id
          and operation.operation_id = target_operation_id;
    end if;

    if stored_operation.actor_user_id <> participant_id
       or stored_operation.moment_client_id <> target_moment_client_id
       or stored_operation.operation_kind <> 'remove_response'
       or stored_operation.interaction_client_id <> target_interaction_client_id then
        raise exception 'moment_operation_identity_collision' using errcode = '23505';
    end if;

    if not inserted_operation then
        if stored_moment.deleted_at is null then
            return next stored_moment;
        end if;
        return;
    end if;
    if stored_moment.deleted_at is not null then
        raise exception 'moment_deleted' using errcode = '23514';
    end if;

    select response.*
    into stored_response
    from public.moment_responses response
    where response.relationship_id = target_relationship_id
      and response.moment_client_id = target_moment_client_id
      and response.client_id = target_interaction_client_id
    for update;

    if stored_response.id is null then
        raise exception 'moment_response_not_found' using errcode = 'P0002';
    end if;
    if stored_response.responder_user_id <> participant_id then
        raise exception 'moment_response_not_owned' using errcode = '42501';
    end if;

    delete from public.moment_responses response
    where response.id = stored_response.id;

    update public.moments moment
    set lifecycle_revision = moment.lifecycle_revision + 1
    where moment.id = stored_moment.id
    returning moment.* into stored_moment;

    perform realtime.send(
        jsonb_build_object(
            'moment_client_id', target_moment_client_id,
            'change_kind', 'response_removed'
        ),
        'moment-lifecycle',
        'relationship:' || target_relationship_id::text,
        true
    );

    return next stored_moment;
end;
$$;

create function public.remove_moment_answer(
    target_relationship_id uuid,
    target_moment_client_id uuid,
    target_interaction_client_id uuid,
    target_operation_id uuid
)
returns setof public.moments
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    stored_moment public.moments%rowtype;
    stored_answer public.moment_question_answers%rowtype;
    stored_operation public.moment_lifecycle_operations%rowtype;
    inserted_operation boolean := false;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;
    if target_operation_id is null or target_interaction_client_id is null then
        raise exception 'invalid_moment_operation' using errcode = '22023';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    select moment.*
    into stored_moment
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_moment_client_id
    for update;

    if stored_moment.id is null then
        raise exception 'moment_not_found' using errcode = 'P0002';
    end if;

    insert into public.moment_lifecycle_operations (
        relationship_id,
        operation_id,
        moment_client_id,
        interaction_client_id,
        actor_user_id,
        operation_kind
    ) values (
        target_relationship_id,
        target_operation_id,
        target_moment_client_id,
        target_interaction_client_id,
        participant_id,
        'remove_answer'
    )
    on conflict do nothing
    returning * into stored_operation;

    inserted_operation := stored_operation.operation_id is not null;
    if not inserted_operation then
        select operation.*
        into stored_operation
        from public.moment_lifecycle_operations operation
        where operation.relationship_id = target_relationship_id
          and operation.operation_id = target_operation_id;
    end if;

    if stored_operation.actor_user_id <> participant_id
       or stored_operation.moment_client_id <> target_moment_client_id
       or stored_operation.operation_kind <> 'remove_answer'
       or stored_operation.interaction_client_id <> target_interaction_client_id then
        raise exception 'moment_operation_identity_collision' using errcode = '23505';
    end if;

    if not inserted_operation then
        if stored_moment.deleted_at is null then
            return next stored_moment;
        end if;
        return;
    end if;
    if stored_moment.deleted_at is not null then
        raise exception 'moment_deleted' using errcode = '23514';
    end if;

    select answer.*
    into stored_answer
    from public.moment_question_answers answer
    where answer.relationship_id = target_relationship_id
      and answer.moment_client_id = target_moment_client_id
      and answer.client_id = target_interaction_client_id
    for update;

    if stored_answer.id is null then
        raise exception 'moment_answer_not_found' using errcode = 'P0002';
    end if;
    if stored_answer.answerer_user_id <> participant_id then
        raise exception 'moment_answer_not_owned' using errcode = '42501';
    end if;

    if stored_answer.removed_at is null then
        update public.moment_question_answers answer
        set answer_content = null,
            removed_at = statement_timestamp()
        where answer.id = stored_answer.id;

        update public.moments moment
        set lifecycle_revision = moment.lifecycle_revision + 1
        where moment.id = stored_moment.id
        returning moment.* into stored_moment;

        perform realtime.send(
            jsonb_build_object(
                'moment_client_id', target_moment_client_id,
                'change_kind', 'answer_removed'
            ),
            'moment-lifecycle',
            'relationship:' || target_relationship_id::text,
            true
        );
    end if;

    return next stored_moment;
end;
$$;

create function public.list_recently_deleted_moments(
    target_relationship_id uuid
)
returns setof public.moments
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    return query
    select moment.*
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.creator_user_id = participant_id
      and moment.deleted_at is not null
      and moment.purge_after > statement_timestamp()
    order by moment.deleted_at desc, moment.client_id;
end;
$$;

create function public.list_hidden_moment_ids(target_relationship_id uuid)
returns table (
    moment_client_id uuid,
    source_message_client_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    return query
    select moment.client_id,
           moment.source_shared_item_client_id
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.deleted_at is not null
    order by moment.client_id;
end;
$$;

create function public.list_moment_sync_hints(
    target_relationship_id uuid,
    after_moment_client_id uuid default null,
    target_limit integer default 500
)
returns table (
    moment_client_id uuid,
    is_deleted boolean,
    source_message_client_id uuid,
    revision bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    return query
    select moment.client_id,
           moment.deleted_at is not null,
           moment.source_shared_item_client_id,
           moment.lifecycle_revision
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.lifecycle_revision > 0
      and (
          after_moment_client_id is null
          or moment.client_id > after_moment_client_id
      )
    order by moment.client_id
    limit least(greatest(coalesce(target_limit, 500), 1), 500);
end;
$$;

create or replace function public.create_moment_from_shared_item(
    target_relationship_id uuid,
    target_message_client_id uuid,
    target_moment_client_id uuid
)
returns table (
    moment_client_id uuid,
    creator_user_id uuid,
    source_message_client_id uuid,
    source_message_creator_user_id uuid,
    kind text,
    text_content text,
    media_byte_size bigint,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    active_member_count integer;
    source_item public.shared_items%rowtype;
    stored_moment public.moments%rowtype;
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

    select item.*
    into source_item
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.client_id = target_message_client_id
      and (
          item.item_kind = 'message'
          or (item.item_kind = 'photo' and item.media_byte_size is not null)
      )
    for share;

    if source_item.id is null then
        raise exception 'message_not_found' using errcode = 'P0002';
    end if;

    select moment.*
    into stored_moment
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_moment_client_id
    for share;

    if found then
        if stored_moment.deleted_at is not null then
            raise exception 'moment_deleted' using errcode = '23514';
        end if;
        if stored_moment.creator_user_id <> participant_id
           or stored_moment.source_shared_item_client_id is distinct from source_item.client_id
           or stored_moment.source_appointment_client_id
                is distinct from source_item.appointment_client_id
           or stored_moment.kind <> (case
               when source_item.item_kind = 'message' then 'text'
               else 'photo'
           end)
           or stored_moment.text_content is distinct from source_item.text_content
           or stored_moment.media_byte_size is distinct from source_item.media_byte_size then
            raise exception 'moment_identity_collision' using errcode = '23505';
        end if;
    else
        select moment.*
        into stored_moment
        from public.moments moment
        where moment.relationship_id = target_relationship_id
          and moment.source_shared_item_client_id = source_item.client_id
        for share;

        if found and stored_moment.deleted_at is not null then
            raise exception 'moment_deleted' using errcode = '23514';
        end if;

        if not found then
            insert into public.moments (
                relationship_id,
                client_id,
                creator_user_id,
                kind,
                text_content,
                media_byte_size,
                source_shared_item_client_id,
                source_appointment_client_id
            ) values (
                target_relationship_id,
                target_moment_client_id,
                participant_id,
                case when source_item.item_kind = 'message' then 'text' else 'photo' end,
                source_item.text_content,
                source_item.media_byte_size,
                source_item.client_id,
                source_item.appointment_client_id
            )
            on conflict (relationship_id, source_shared_item_client_id)
                where source_shared_item_client_id is not null
                do nothing
            returning * into stored_moment;

            if not found then
                select moment.*
                into stored_moment
                from public.moments moment
                where moment.relationship_id = target_relationship_id
                  and moment.source_shared_item_client_id = source_item.client_id
                for share;

                if stored_moment.deleted_at is not null then
                    raise exception 'moment_deleted' using errcode = '23514';
                end if;
            end if;
        end if;
    end if;

    return query
    select
        stored_moment.client_id,
        stored_moment.creator_user_id,
        source_item.client_id,
        source_item.creator_user_id,
        stored_moment.kind,
        stored_moment.text_content,
        stored_moment.media_byte_size,
        stored_moment.created_at;
end;
$$;

revoke all on function public._delete_moment_at(
    uuid, uuid, uuid, timestamptz
) from public, anon, authenticated;
revoke all on function public._restore_moment_at(
    uuid, uuid, uuid, timestamptz
) from public, anon, authenticated;

revoke all on function public.delete_moment(uuid, uuid, uuid) from public;
revoke all on function public.restore_moment(uuid, uuid, uuid) from public;
revoke all on function public.remove_moment_response(
    uuid, uuid, uuid, uuid
) from public;
revoke all on function public.remove_moment_answer(
    uuid, uuid, uuid, uuid
) from public;
revoke all on function public.list_recently_deleted_moments(uuid) from public;
revoke all on function public.list_hidden_moment_ids(uuid) from public;
revoke all on function public.list_moment_sync_hints(uuid, uuid, integer)
from public;

grant execute on function public.delete_moment(uuid, uuid, uuid)
to authenticated;
grant execute on function public.restore_moment(uuid, uuid, uuid)
to authenticated;
grant execute on function public.remove_moment_response(
    uuid, uuid, uuid, uuid
) to authenticated;
grant execute on function public.remove_moment_answer(
    uuid, uuid, uuid, uuid
) to authenticated;
grant execute on function public.list_recently_deleted_moments(uuid)
to authenticated;
grant execute on function public.list_hidden_moment_ids(uuid)
to authenticated;
grant execute on function public.list_moment_sync_hints(uuid, uuid, integer)
to authenticated;
