-- W13 photo finalization uses the same stable shared-item source as text.
create or replace function public.enqueue_push_event(target_event_kind text, target_source_item_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare participant_id uuid := auth.uid(); source public.shared_items%rowtype; event_id uuid; job_id uuid; relationship_status text; begin
    if participant_id is null then raise exception 'authentication_required' using errcode = '42501'; end if;
    if target_event_kind not in ('chat_message_created', 'appointment_discussion_message_created') then
        raise exception 'unsupported_push_event_kind' using errcode = '22023'; end if;
    select * into source from public.shared_items where id = target_source_item_id for share;
    if source.id is null or source.creator_user_id <> participant_id
       or (source.item_kind <> 'message' and (source.item_kind <> 'photo' or source.media_byte_size is null)) then
        raise exception 'push_event_source_not_accessible' using errcode = '42501'; end if;
    if (target_event_kind = 'chat_message_created' and source.appointment_client_id is not null)
       or (target_event_kind = 'appointment_discussion_message_created' and source.appointment_client_id is null) then
        raise exception 'push_event_source_not_accessible' using errcode = '42501'; end if;
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
