create index shared_items_appointment_discussion_activity_idx
on public.shared_items (
    relationship_id,
    appointment_client_id,
    (greatest(created_at, coalesce(reaction_updated_at, created_at))) desc,
    client_id desc
)
where appointment_client_id is not null
  and (
      item_kind = 'message'
      or (item_kind = 'photo' and media_byte_size is not null)
  );

create function public.recent_appointment_discussions(
    target_relationship_id uuid
)
returns table (
    appointment_client_id uuid,
    latest_activity_at timestamptz,
    unread_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    return query
    with latest_discussion_activity as (
        select distinct on (item.appointment_client_id)
            item.appointment_client_id,
            greatest(item.created_at, coalesce(item.reaction_updated_at, item.created_at))
                as latest_activity_at,
            item.client_id
        from public.shared_items item
        where item.relationship_id = target_relationship_id
          and item.appointment_client_id is not null
          and (
              item.item_kind = 'message'
              or (item.item_kind = 'photo' and item.media_byte_size is not null)
          )
        order by
            item.appointment_client_id,
            greatest(item.created_at, coalesce(item.reaction_updated_at, item.created_at)) desc,
            item.client_id desc
    )
    select
        latest.appointment_client_id,
        latest.latest_activity_at,
        (
            select count(*)
            from public.shared_items unread_item
            left join public.conversation_read_states read_state
              on read_state.relationship_id = target_relationship_id
             and read_state.user_id = participant_id
             and read_state.scope_id = latest.appointment_client_id
            where unread_item.relationship_id = target_relationship_id
              and unread_item.appointment_client_id = latest.appointment_client_id
              and (
                  unread_item.item_kind = 'message'
                  or (
                      unread_item.item_kind = 'photo'
                      and unread_item.media_byte_size is not null
                  )
              )
              and unread_item.creator_user_id <> participant_id
              and (
                  read_state.user_id is null
                  or (unread_item.created_at, unread_item.client_id)
                     > (read_state.last_read_created_at, read_state.last_read_client_id)
              )
        )::bigint as unread_count
    from latest_discussion_activity latest
    order by latest.latest_activity_at desc, latest.client_id desc;
end;
$$;

revoke all on function public.recent_appointment_discussions(uuid) from public;
grant execute on function public.recent_appointment_discussions(uuid) to authenticated;
