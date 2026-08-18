-- Debug-only client control calls this server-authoritative cursor reset.
create function public.mark_all_relationship_interactions_read(target_relationship_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare participant_id uuid := auth.uid(); cursor record; begin
    if participant_id is null or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;
    for cursor in
        select distinct on (scope_id) scope_id, created_at, id
        from public.relationship_interaction_events
        where relationship_id = target_relationship_id
        order by scope_id, created_at desc, id desc
    loop
        insert into public.relationship_interaction_read_states (
            relationship_id, scope_id, user_id, last_read_created_at, last_read_event_id
        ) values (
            target_relationship_id, cursor.scope_id, participant_id, cursor.created_at, cursor.id
        ) on conflict (relationship_id, scope_id, user_id) do update set
            last_read_created_at = excluded.last_read_created_at,
            last_read_event_id = excluded.last_read_event_id,
            updated_at = now()
        where (excluded.last_read_created_at, excluded.last_read_event_id) >
            (relationship_interaction_read_states.last_read_created_at,
             relationship_interaction_read_states.last_read_event_id);
    end loop;
end;
$$;
revoke all on function public.mark_all_relationship_interactions_read(uuid) from public;
grant execute on function public.mark_all_relationship_interactions_read(uuid) to authenticated;
