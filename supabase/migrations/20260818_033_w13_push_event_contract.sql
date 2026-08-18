-- W13 formal, content-free push event boundary.  W1 jobs were only a test
-- entrypoint, so pending generic jobs are deliberately not carried forward.

delete from public.push_delivery_jobs;

alter table public.push_delivery_jobs
    drop constraint push_delivery_jobs_relationship_id_event_id_recipient_user__key,
    drop constraint push_delivery_jobs_relationship_id_fkey,
    drop constraint push_delivery_jobs_event_kind_check,
    drop column relationship_id;

alter table public.push_delivery_jobs
    rename column event_id to source_item_id;

alter table public.push_delivery_jobs
    add column claim_token uuid,
    add constraint push_delivery_jobs_source_item_id_fkey
        foreign key (source_item_id)
        references public.shared_items(id)
        on delete cascade,
    add constraint push_delivery_jobs_event_kind_check
        check (event_kind in ('chat_message_created', 'appointment_discussion_message_created')),
    add constraint push_delivery_jobs_source_recipient_key
        unique (source_item_id, recipient_user_id);

drop function public.enqueue_w1_test_push(uuid, uuid);
drop function public.claim_w1_push_job(uuid, uuid);
drop function public.complete_w1_push_job(uuid, boolean, text);

create function public.enqueue_push_event(
    target_event_kind text,
    target_source_item_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    source_item public.shared_items%rowtype;
    relationship_status text;
    active_member_count integer;
    derived_recipient_id uuid;
    queued_job public.push_delivery_jobs%rowtype;
begin
    if participant_id is null then
        raise exception 'authentication_required' using errcode = '42501';
    end if;

    if target_event_kind not in (
        'chat_message_created',
        'appointment_discussion_message_created'
    ) then
        raise exception 'unsupported_push_event_kind' using errcode = '22023';
    end if;

    select item.*
    into source_item
    from public.shared_items item
    where item.id = target_source_item_id
    for share;

    if source_item.id is null
       or source_item.creator_user_id <> participant_id
       or source_item.item_kind <> 'message'
       or (
           target_event_kind = 'chat_message_created'
           and source_item.appointment_client_id is not null
       )
       or (
           target_event_kind = 'appointment_discussion_message_created'
           and source_item.appointment_client_id is null
       ) then
        raise exception 'push_event_source_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = source_item.relationship_id
    for share;

    select count(*)
    into active_member_count
    from public.relationship_members member
    where member.relationship_id = source_item.relationship_id
      and member.membership_status = 'active';

    if relationship_status <> 'active' or active_member_count <> 2 then
        raise exception 'relationship_not_active_pair' using errcode = '23514';
    end if;

    select member.user_id
    into derived_recipient_id
    from public.relationship_members member
    where member.relationship_id = source_item.relationship_id
      and member.membership_status = 'active'
      and member.user_id <> participant_id;

    if derived_recipient_id is null then
        raise exception 'push_recipient_not_available' using errcode = '23514';
    end if;

    insert into public.push_delivery_jobs (
        source_item_id,
        sender_user_id,
        recipient_user_id,
        event_kind
    ) values (
        source_item.id,
        participant_id,
        derived_recipient_id,
        target_event_kind
    )
    on conflict (source_item_id, recipient_user_id) do nothing
    returning * into queued_job;

    if queued_job.id is null then
        select job.*
        into queued_job
        from public.push_delivery_jobs job
        where job.source_item_id = source_item.id
          and job.recipient_user_id = derived_recipient_id;

        if queued_job.sender_user_id <> participant_id
           or queued_job.event_kind <> target_event_kind then
            raise exception 'push_event_identity_collision' using errcode = '23505';
        end if;
    end if;

    return queued_job.id;
end;
$$;

create function public.claim_push_delivery_job(
    target_job_id uuid,
    target_sender_user_id uuid
)
returns table (
    job_id uuid,
    source_item_id uuid,
    event_kind text,
    recipient_user_id uuid,
    claim_token uuid,
    attempt_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    return query
    update public.push_delivery_jobs job
    set claimed_at = now(),
        claim_token = gen_random_uuid(),
        attempt_count = job.attempt_count + 1,
        last_error = null
    where job.id = target_job_id
      and job.sender_user_id = target_sender_user_id
      and job.delivered_at is null
      and (
          job.claimed_at is null
          or job.claimed_at < now() - interval '5 minutes'
      )
    returning
        job.id,
        job.source_item_id,
        job.event_kind,
        job.recipient_user_id,
        job.claim_token,
        job.attempt_count;

    if not found then
        if not exists (
            select 1
            from public.push_delivery_jobs job
            where job.id = target_job_id
              and job.sender_user_id = target_sender_user_id
        ) then
            raise exception 'push_job_not_accessible' using errcode = '42501';
        end if;

        raise exception 'push_job_not_claimable' using errcode = '55000';
    end if;
end;
$$;

create function public.complete_push_delivery_job(
    target_job_id uuid,
    target_claim_token uuid,
    target_succeeded boolean,
    target_error text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if target_succeeded then
        update public.push_delivery_jobs job
        set delivered_at = now(),
            last_error = null
        where job.id = target_job_id
          and job.claim_token = target_claim_token
          and job.claimed_at is not null
          and job.delivered_at is null;
    else
        update public.push_delivery_jobs job
        set claimed_at = null,
            claim_token = null,
            last_error = left(coalesce(target_error, 'apns_delivery_failed'), 500)
        where job.id = target_job_id
          and job.claim_token = target_claim_token
          and job.claimed_at is not null
          and job.delivered_at is null;
    end if;

    if not found then
        raise exception 'push_job_not_completable' using errcode = '55000';
    end if;
end;
$$;

create or replace function public.cancel_relationship_invitation()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    target_relationship_id uuid;
begin
    if participant_id is null then
        raise exception 'authentication_required' using errcode = '42501';
    end if;

    select invitation.relationship_id
    into target_relationship_id
    from public.relationship_invitations invitation
    join public.relationships relationship
      on relationship.id = invitation.relationship_id
    join public.relationship_members member
      on member.relationship_id = invitation.relationship_id
     and member.user_id = participant_id
     and member.membership_status = 'active'
    where invitation.created_by_user_id = participant_id
      and invitation.accepted_at is null
      and relationship.status = 'active'
    for update of invitation, relationship, member;

    if target_relationship_id is null or (
        select count(*)
        from public.relationship_members member
        where member.relationship_id = target_relationship_id
          and member.membership_status = 'active'
    ) <> 1 then
        raise exception 'invitation_not_cancellable' using errcode = '23514';
    end if;

    if exists (
        select 1 from public.shared_items item
        where item.relationship_id = target_relationship_id
    ) or exists (
        select 1 from public.personal_archives archive
        where archive.relationship_id = target_relationship_id
    ) or exists (
        select 1 from storage.objects object
        where object.name like target_relationship_id::text || '/%'
    ) then
        raise exception 'relationship_not_empty' using errcode = '23514';
    end if;

    delete from public.relationships where id = target_relationship_id;
end;
$$;

revoke all on function public.enqueue_push_event(text, uuid) from public;
revoke all on function public.claim_push_delivery_job(uuid, uuid) from public;
revoke all on function public.complete_push_delivery_job(uuid, uuid, boolean, text) from public;

grant execute on function public.enqueue_push_event(text, uuid) to authenticated;
grant execute on function public.claim_push_delivery_job(uuid, uuid) to service_role;
grant execute on function public.complete_push_delivery_job(uuid, uuid, boolean, text) to service_role;
