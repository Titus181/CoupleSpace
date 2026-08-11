create function public.cancel_relationship_invitation()
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
        select 1
        from public.shared_items item
        where item.relationship_id = target_relationship_id
    ) or exists (
        select 1
        from public.personal_archives archive
        where archive.relationship_id = target_relationship_id
    ) or exists (
        select 1
        from public.push_delivery_jobs job
        where job.relationship_id = target_relationship_id
    ) or exists (
        select 1
        from storage.objects object
        where object.name like target_relationship_id::text || '/%'
    ) then
        raise exception 'relationship_not_empty' using errcode = '23514';
    end if;

    delete from public.relationships
    where id = target_relationship_id;
end;
$$;

revoke all on function public.cancel_relationship_invitation() from public;
grant execute on function public.cancel_relationship_invitation() to authenticated;
