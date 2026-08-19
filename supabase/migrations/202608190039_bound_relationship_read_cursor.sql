-- A visible conversation may only advance the W13 ledger through the exact
-- message that the client displayed.  A newer event arriving while an older
-- read request is in flight must remain unread.

alter table public.relationship_interaction_events
    alter column created_at set default clock_timestamp();

-- This helper is owned by trigger/function code.  It accepts actor and source
-- identities directly, so clients must never be able to invoke it.
revoke all on function public.record_relationship_interaction_event(
    uuid, uuid, uuid, uuid, text
) from public, anon, authenticated;

create function public.mark_relationship_interactions_read_through_message(
    target_relationship_id uuid,
    target_scope_id uuid,
    target_message_client_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    source_item_id uuid;
    target_event public.relationship_interaction_events%rowtype;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select item.id
    into source_item_id
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.client_id = target_message_client_id
      and (
          (target_scope_id = target_relationship_id
           and item.appointment_client_id is null)
          or (target_scope_id <> target_relationship_id
              and item.appointment_client_id = target_scope_id)
      )
      and (
          item.item_kind = 'message'
          or (item.item_kind = 'photo' and item.media_byte_size is not null)
      );

    if source_item_id is null then
        raise exception 'interaction_source_not_found' using errcode = '22023';
    end if;

    select event.*
    into target_event
    from public.relationship_interaction_events event
    where event.relationship_id = target_relationship_id
      and event.scope_id = target_scope_id
      and event.source_identity = source_item_id;

    -- Messages created before the W13 ledger was introduced have no event and
    -- therefore cannot contribute to the W13 unread total.
    if target_event.id is null then return; end if;

    insert into public.relationship_interaction_read_states (
        relationship_id,
        scope_id,
        user_id,
        last_read_created_at,
        last_read_event_id
    ) values (
        target_relationship_id,
        target_scope_id,
        participant_id,
        target_event.created_at,
        target_event.id
    )
    on conflict (relationship_id, scope_id, user_id) do update set
        last_read_created_at = excluded.last_read_created_at,
        last_read_event_id = excluded.last_read_event_id,
        updated_at = now()
    where (excluded.last_read_created_at, excluded.last_read_event_id) >
          (relationship_interaction_read_states.last_read_created_at,
           relationship_interaction_read_states.last_read_event_id);
end;
$$;

revoke all on function public.mark_relationship_interactions_read_through_message(
    uuid, uuid, uuid
) from public;
grant execute on function public.mark_relationship_interactions_read_through_message(
    uuid, uuid, uuid
) to authenticated;
