-- W13 relationship interaction unread authority.  This intentionally leaves
-- the W8/W11 cursors intact for their existing screens; the new ledger is the
-- only source used for the relationship badge and lifecycle unread state.

create table public.relationship_interaction_events (
    id uuid primary key default gen_random_uuid(),
    relationship_id uuid not null references public.relationships(id) on delete cascade,
    scope_id uuid not null,
    source_identity uuid not null,
    actor_user_id uuid not null references auth.users(id),
    event_kind text not null check (event_kind in (
        'chat_text_created', 'chat_photo_created', 'appointment_created',
        'appointment_updated', 'appointment_cancelled'
    )),
    created_at timestamptz not null default now(),
    unique (relationship_id, source_identity)
);

create index relationship_interaction_events_recipient_order_idx
on public.relationship_interaction_events (relationship_id, scope_id, created_at, id);

alter table public.relationship_interaction_events enable row level security;
create policy "Current members can read relationship interaction events"
on public.relationship_interaction_events for select to authenticated
using (public.is_current_relationship_member(relationship_id));
revoke all on public.relationship_interaction_events from anon, authenticated;
grant select on public.relationship_interaction_events to authenticated;

create table public.relationship_interaction_read_states (
    relationship_id uuid not null,
    scope_id uuid not null,
    user_id uuid not null,
    last_read_created_at timestamptz not null,
    last_read_event_id uuid not null,
    updated_at timestamptz not null default now(),
    primary key (relationship_id, scope_id, user_id),
    foreign key (relationship_id, user_id)
        references public.relationship_members(relationship_id, user_id) on delete cascade
);
alter table public.relationship_interaction_read_states enable row level security;
create policy "Users can read only their relationship interaction cursor"
on public.relationship_interaction_read_states for select to authenticated
using (user_id = (select auth.uid()));
revoke all on public.relationship_interaction_read_states from anon, authenticated;
grant select on public.relationship_interaction_read_states to authenticated;

create function public.record_relationship_interaction_event(
    target_relationship_id uuid,
    target_scope_id uuid,
    target_source_identity uuid,
    target_actor_user_id uuid,
    target_event_kind text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
    event_id uuid;
    recipient_id uuid;
begin
    insert into public.relationship_interaction_events (
        relationship_id, scope_id, source_identity, actor_user_id, event_kind
    ) values (
        target_relationship_id, target_scope_id, target_source_identity,
        target_actor_user_id, target_event_kind
    ) on conflict (relationship_id, source_identity) do nothing
    returning id into event_id;

    if event_id is null then
        select id into event_id from public.relationship_interaction_events
        where relationship_id = target_relationship_id and source_identity = target_source_identity;
        return event_id;
    end if;

    return event_id;
end;
$$;

-- The prior foreign key only supported shared_items.  W13 sources include
-- appointments and operation IDs, so jobs reference the stable ledger event.
alter table public.push_delivery_jobs
    drop constraint push_delivery_jobs_event_kind_check,
    alter column source_item_id drop not null,
    add constraint push_delivery_jobs_event_kind_check check (event_kind in (
        'chat_message_created', 'appointment_discussion_message_created',
        'appointment_created', 'appointment_updated', 'appointment_cancelled'
    )),
    add column interaction_event_id uuid references public.relationship_interaction_events(id) on delete cascade;
create unique index push_delivery_jobs_interaction_event_recipient_key
on public.push_delivery_jobs (interaction_event_id, recipient_user_id)
where interaction_event_id is not null;

create function public.capture_shared_item_interaction_event()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if new.item_kind = 'message' then
        perform public.record_relationship_interaction_event(new.relationship_id,
            coalesce(new.appointment_client_id, new.relationship_id), new.id,
            new.creator_user_id, 'chat_text_created');
    elsif new.item_kind = 'photo' and new.media_byte_size is not null then
        perform public.record_relationship_interaction_event(new.relationship_id,
            coalesce(new.appointment_client_id, new.relationship_id), new.id,
            new.creator_user_id, 'chat_photo_created');
    end if;
    return new;
end;
$$;
create trigger shared_items_relationship_interaction_event
after insert on public.shared_items for each row execute function public.capture_shared_item_interaction_event();

create function public.capture_appointment_created_interaction_event()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    perform public.record_relationship_interaction_event(new.relationship_id, new.client_id,
        new.client_id, new.creator_user_id, 'appointment_created');
    return new;
end;
$$;
create trigger shared_appointments_created_interaction_event
after insert on public.shared_appointments for each row execute function public.capture_appointment_created_interaction_event();

alter table public.shared_appointment_operations add column applied_at timestamptz;

create function public.capture_appointment_changed_interaction_event()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target_operation_id uuid; actor_id uuid; interaction_kind text; begin
    if old.status = new.status
       and old.title is not distinct from new.title
       and old.starts_at is not distinct from new.starts_at
       and old.location is not distinct from new.location
       and old.note is not distinct from new.note
       and old.reminder_at is not distinct from new.reminder_at then
        return new;
    end if;
    if new.status = 'cancelled' then
        select operation.operation_id, operation.actor_user_id into target_operation_id, actor_id
        from public.shared_appointment_operations operation
        where operation.relationship_id = new.relationship_id
          and operation.appointment_client_id = new.client_id and operation.operation_kind = 'cancel'
        order by operation.created_at desc, operation.operation_id desc limit 1;
        interaction_kind := 'appointment_cancelled';
    else
        select operation.operation_id, operation.actor_user_id into target_operation_id, actor_id
        from public.shared_appointment_operations operation
        where operation.relationship_id = new.relationship_id
          and operation.appointment_client_id = new.client_id and operation.operation_kind = 'update'
          and operation.title = new.title and operation.starts_at = new.starts_at
          and operation.location is not distinct from new.location
          and operation.note is not distinct from new.note
          and operation.reminder_at is not distinct from new.reminder_at
        order by operation.created_at desc, operation.operation_id desc limit 1;
        interaction_kind := 'appointment_updated';
    end if;
    if target_operation_id is not null then
        update public.shared_appointment_operations as operation set applied_at = now()
        where operation.relationship_id = new.relationship_id
          and operation.operation_id = target_operation_id;
        perform public.record_relationship_interaction_event(new.relationship_id, new.client_id,
            target_operation_id, actor_id, interaction_kind);
    end if;
    return new;
end;
$$;
create trigger shared_appointments_changed_interaction_event
after update on public.shared_appointments for each row execute function public.capture_appointment_changed_interaction_event();

create or replace function public.enqueue_push_event(target_event_kind text, target_source_item_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare participant_id uuid := auth.uid(); source public.shared_items%rowtype; event_id uuid; job_id uuid; relationship_status text; begin
    if participant_id is null then raise exception 'authentication_required' using errcode = '42501'; end if;
    if target_event_kind not in ('chat_message_created', 'appointment_discussion_message_created') then
        raise exception 'unsupported_push_event_kind' using errcode = '22023'; end if;
    select * into source from public.shared_items where id = target_source_item_id for share;
    if source.id is null or source.creator_user_id <> participant_id then
        raise exception 'push_event_source_not_accessible' using errcode = '42501';
    end if;
    if (target_event_kind = 'chat_message_created' and source.appointment_client_id is not null)
       or (target_event_kind = 'appointment_discussion_message_created' and source.appointment_client_id is null)
       then raise exception 'push_event_source_not_accessible' using errcode = '42501'; end if;
    select status into relationship_status from public.relationships where id = source.relationship_id;
    if relationship_status <> 'active' then raise exception 'relationship_not_active_pair' using errcode = '23514'; end if;
    select id into event_id from public.relationship_interaction_events
    where relationship_id = source.relationship_id and source_identity = source.id;
    if event_id is null then return null; end if;
    insert into public.push_delivery_jobs (source_item_id, sender_user_id, recipient_user_id, event_kind)
    select source.id, participant_id, member.user_id, target_event_kind
    from public.relationship_members member where member.relationship_id = source.relationship_id
      and member.membership_status = 'active' and member.user_id <> participant_id
    on conflict (source_item_id, recipient_user_id) do nothing returning id into job_id;
    if job_id is null then
      select id into job_id from public.push_delivery_jobs where source_item_id = source.id
        and sender_user_id = participant_id and event_kind = target_event_kind limit 1;
      if job_id is null then raise exception 'push_event_identity_collision' using errcode = '23505'; end if;
    end if;
    return job_id;
end;
$$;

create function public.enqueue_relationship_interaction_push(target_event_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare participant_id uuid := auth.uid(); event public.relationship_interaction_events%rowtype; recipient_id uuid; job_id uuid; begin
    if participant_id is null then raise exception 'authentication_required' using errcode = '42501'; end if;
    select * into event from public.relationship_interaction_events where id = target_event_id for share;
    if event.id is null or event.actor_user_id <> participant_id then
        raise exception 'push_event_source_not_accessible' using errcode = '42501'; end if;
    select user_id into recipient_id from public.relationship_members where relationship_id = event.relationship_id
      and membership_status = 'active' and user_id <> participant_id;
    if recipient_id is null or (select count(*) from public.relationship_members where relationship_id = event.relationship_id and membership_status = 'active') <> 2 then
        raise exception 'relationship_not_active_pair' using errcode = '23514'; end if;
    insert into public.push_delivery_jobs (source_item_id, interaction_event_id, sender_user_id, recipient_user_id, event_kind)
    values (null, event.id, participant_id, recipient_id, case event.event_kind
      when 'appointment_created' then 'appointment_created' when 'appointment_updated' then 'appointment_updated'
      else 'appointment_cancelled' end)
    on conflict do nothing returning id into job_id;
    if job_id is null then select id into job_id from public.push_delivery_jobs
      where interaction_event_id = event.id and recipient_user_id = recipient_id; end if;
    return job_id;
end;
$$;

create function public.enqueue_relationship_interaction_push_for_source(
    target_relationship_id uuid, target_source_identity uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare event_id uuid; begin
    select id into event_id from public.relationship_interaction_events
    where relationship_id = target_relationship_id and source_identity = target_source_identity;
    if event_id is null then raise exception 'push_event_source_not_accessible' using errcode = '42501'; end if;
    return public.enqueue_relationship_interaction_push(event_id);
end;
$$;
revoke all on function public.enqueue_relationship_interaction_push(uuid) from public;
revoke all on function public.enqueue_relationship_interaction_push_for_source(uuid, uuid) from public;
grant execute on function public.enqueue_relationship_interaction_push(uuid) to authenticated;
grant execute on function public.enqueue_relationship_interaction_push_for_source(uuid, uuid) to authenticated;

drop function public.claim_push_delivery_job(uuid, uuid);
create function public.claim_push_delivery_job(target_job_id uuid, target_sender_user_id uuid)
returns table (job_id uuid, source_item_id uuid, event_kind text, recipient_user_id uuid,
               claim_token uuid, attempt_count integer, badge_count integer)
language plpgsql security definer set search_path = '' as $$
declare claimed public.push_delivery_jobs%rowtype; target_relationship uuid; begin
    update public.push_delivery_jobs job set claimed_at = now(), claim_token = gen_random_uuid(),
      attempt_count = job.attempt_count + 1, last_error = null
    where job.id = target_job_id and job.sender_user_id = target_sender_user_id and job.delivered_at is null
      and (job.claimed_at is null or job.claimed_at < now() - interval '5 minutes')
    returning job.* into claimed;
    if claimed.id is null then
      if not exists (select 1 from public.push_delivery_jobs where id = target_job_id and sender_user_id = target_sender_user_id) then
        raise exception 'push_job_not_accessible' using errcode = '42501'; end if;
      raise exception 'push_job_not_claimable' using errcode = '55000';
    end if;
    select event.relationship_id into target_relationship from public.relationship_interaction_events event
      where event.id = claimed.interaction_event_id;
    if target_relationship is null then select item.relationship_id into target_relationship from public.shared_items item where item.id = claimed.source_item_id; end if;
    return query select claimed.id, coalesce(claimed.interaction_event_id, claimed.source_item_id),
      claimed.event_kind, claimed.recipient_user_id, claimed.claim_token, claimed.attempt_count,
      coalesce((select count(*)::integer from public.relationship_interaction_events event
        left join public.relationship_interaction_read_states state on state.relationship_id = event.relationship_id
          and state.scope_id = event.scope_id and state.user_id = claimed.recipient_user_id
        where event.relationship_id = target_relationship and event.actor_user_id <> claimed.recipient_user_id
          and (state.user_id is null or (event.created_at, event.id) > (state.last_read_created_at, state.last_read_event_id))), 0);
end;
$$;
revoke all on function public.claim_push_delivery_job(uuid, uuid) from public;
grant execute on function public.claim_push_delivery_job(uuid, uuid) to service_role;

create function public.relationship_unread_counts(target_relationship_id uuid)
returns table (scope_id uuid, unread_count bigint, total_unread_count bigint)
language plpgsql stable security definer set search_path = '' as $$
declare participant_id uuid := auth.uid(); begin
    if participant_id is null or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;
    return query with unread as (
        select event.scope_id, count(*)::bigint as count
        from public.relationship_interaction_events event
        left join public.relationship_interaction_read_states state
          on state.relationship_id = event.relationship_id and state.scope_id = event.scope_id
         and state.user_id = participant_id
        where event.relationship_id = target_relationship_id
          and event.actor_user_id <> participant_id
          and (state.user_id is null or (event.created_at, event.id) >
               (state.last_read_created_at, state.last_read_event_id))
        group by event.scope_id
    ) select unread.scope_id, unread.count, sum(unread.count) over ()::bigint from unread;
end;
$$;

create function public.mark_relationship_interactions_read(target_relationship_id uuid, target_scope_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare participant_id uuid := auth.uid(); latest public.relationship_interaction_events%rowtype; begin
    if participant_id is null or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;
    if target_scope_id <> target_relationship_id and not exists (
        select 1 from public.shared_appointments where relationship_id = target_relationship_id and client_id = target_scope_id
    ) then raise exception 'interaction_scope_not_found' using errcode = '22023'; end if;
    select * into latest from public.relationship_interaction_events
    where relationship_id = target_relationship_id and scope_id = target_scope_id
    order by created_at desc, id desc limit 1;
    if latest.id is null then return; end if;
    insert into public.relationship_interaction_read_states (relationship_id, scope_id, user_id, last_read_created_at, last_read_event_id)
    values (target_relationship_id, target_scope_id, participant_id, latest.created_at, latest.id)
    on conflict (relationship_id, scope_id, user_id) do update set
      last_read_created_at = excluded.last_read_created_at, last_read_event_id = excluded.last_read_event_id, updated_at = now()
    where (excluded.last_read_created_at, excluded.last_read_event_id) >
      (relationship_interaction_read_states.last_read_created_at, relationship_interaction_read_states.last_read_event_id);
end;
$$;

revoke all on function public.relationship_unread_counts(uuid) from public;
revoke all on function public.mark_relationship_interactions_read(uuid, uuid) from public;
grant execute on function public.relationship_unread_counts(uuid) to authenticated;
grant execute on function public.mark_relationship_interactions_read(uuid, uuid) to authenticated;
