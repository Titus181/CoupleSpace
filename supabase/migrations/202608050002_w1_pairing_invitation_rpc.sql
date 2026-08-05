create table public.relationship_invitations (
    id uuid primary key default gen_random_uuid(),
    relationship_id uuid not null unique
        references public.relationships(id) on delete cascade,
    invite_token uuid not null unique default gen_random_uuid(),
    created_by_user_id uuid not null references auth.users(id),
    expires_at timestamptz not null default (now() + interval '1 hour'),
    accepted_by_user_id uuid references auth.users(id),
    accepted_at timestamptz,
    check (
        (accepted_by_user_id is null and accepted_at is null)
        or (accepted_by_user_id is not null and accepted_at is not null)
    )
);

alter table public.relationship_invitations enable row level security;

create function public.create_relationship_invitation()
returns table (
    relationship_id uuid,
    invite_token uuid,
    expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    existing_relationship_id uuid;
    current_member_count integer;
    created_relationship_id uuid;
    created_invite_token uuid;
    created_expires_at timestamptz;
begin
    if participant_id is null then
        raise exception 'authentication_required' using errcode = '42501';
    end if;

    select member.relationship_id
    into existing_relationship_id
    from public.relationship_members member
    where member.user_id = participant_id
      and member.membership_status = 'active';

    if existing_relationship_id is not null then
        select count(*)
        into current_member_count
        from public.relationship_members member
        where member.relationship_id = existing_relationship_id
          and member.membership_status = 'active'
        ;

        if current_member_count = 1 then
            select
                invitation.invite_token,
                invitation.expires_at
            into created_invite_token, created_expires_at
            from public.relationship_invitations invitation
            where invitation.relationship_id = existing_relationship_id
              and invitation.created_by_user_id = participant_id
              and invitation.accepted_at is null
            for update;

            if found then
                if created_expires_at <= now() then
                    update public.relationship_invitations invitation
                    set invite_token = gen_random_uuid(),
                        expires_at = now() + interval '1 hour'
                    where invitation.relationship_id = existing_relationship_id
                    returning
                        invitation.invite_token,
                        invitation.expires_at
                    into created_invite_token, created_expires_at;
                end if;

                return query
                select existing_relationship_id, created_invite_token, created_expires_at;
                return;
            end if;
        end if;

        raise exception 'participant_already_paired' using errcode = '23505';
    end if;

    insert into public.relationships default values
    returning id into created_relationship_id;

    insert into public.relationship_members (relationship_id, user_id)
    values (created_relationship_id, participant_id);

    insert into public.relationship_invitations (
        relationship_id,
        created_by_user_id
    )
    values (created_relationship_id, participant_id)
    returning
        relationship_invitations.invite_token,
        relationship_invitations.expires_at
    into created_invite_token, created_expires_at;

    return query
    select created_relationship_id, created_invite_token, created_expires_at;
end;
$$;

create function public.accept_relationship_invitation(provided_invite_token uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    invited_relationship_id uuid;
    inviting_user_id uuid;
begin
    if participant_id is null then
        raise exception 'authentication_required' using errcode = '42501';
    end if;

    select
        invitation.relationship_id,
        invitation.created_by_user_id
    into invited_relationship_id, inviting_user_id
    from public.relationship_invitations invitation
    where invitation.invite_token = provided_invite_token
      and invitation.accepted_at is null
      and invitation.expires_at > now()
    for update;

    if not found then
        raise exception 'invitation_not_available' using errcode = '22023';
    end if;

    if inviting_user_id = participant_id then
        raise exception 'cannot_accept_own_invitation' using errcode = '42501';
    end if;

    if not exists (
        select 1
        from public.relationships relationship
        where relationship.id = invited_relationship_id
          and relationship.status = 'active'
    ) or (
        select count(*)
        from public.relationship_members member
        where member.relationship_id = invited_relationship_id
          and member.membership_status = 'active'
    ) <> 1 then
        raise exception 'invitation_not_available' using errcode = '22023';
    end if;

    insert into public.relationship_members (relationship_id, user_id)
    values (invited_relationship_id, participant_id);

    update public.relationship_invitations
    set accepted_by_user_id = participant_id,
        accepted_at = now()
    where invite_token = provided_invite_token;

    return invited_relationship_id;
end;
$$;

revoke all on public.relationship_invitations from anon, authenticated;
revoke all on function public.create_relationship_invitation() from public;
revoke all on function public.accept_relationship_invitation(uuid) from public;

grant execute on function public.create_relationship_invitation() to authenticated;
grant execute on function public.accept_relationship_invitation(uuid) to authenticated;
