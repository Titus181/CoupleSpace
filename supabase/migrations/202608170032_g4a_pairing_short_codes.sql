alter table public.relationship_invitations
add column short_code text;

create function public.generate_relationship_invitation_short_code(
    test_candidates text[] default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
    candidate text;
    candidate_index integer := 1;
    random_byte integer;
begin
    for attempt_number in 1..64 loop
        if test_candidates is not null
           and candidate_index <= coalesce(array_length(test_candidates, 1), 0) then
            candidate := upper(test_candidates[candidate_index]);
            candidate_index := candidate_index + 1;
        else
            candidate := '';
            while char_length(candidate) < 8 loop
                random_byte := get_byte(extensions.gen_random_bytes(1), 0);
                if random_byte < 248 then
                    candidate := candidate
                        || substr(alphabet, mod(random_byte, 31) + 1, 1);
                end if;
            end loop;
        end if;

        if candidate !~ '^[2-9A-HJ-KM-NP-Z]{8}$' then
            continue;
        end if;

        perform pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended('couplespace-pairing-short-code:' || candidate, 0)
        );
        if not exists (
            select 1
            from public.relationship_invitations invitation
            where invitation.short_code = candidate
        ) then
            return candidate;
        end if;
    end loop;

    raise exception 'short_code_generation_exhausted' using errcode = '54000';
end;
$$;

revoke all on function public.generate_relationship_invitation_short_code(text[]) from public;

do $$
declare
    invitation_record record;
begin
    for invitation_record in
        select invitation.id
        from public.relationship_invitations invitation
        where invitation.short_code is null
        order by invitation.id
    loop
        update public.relationship_invitations invitation
        set short_code = public.generate_relationship_invitation_short_code()
        where invitation.id = invitation_record.id;
    end loop;
end;
$$;

alter table public.relationship_invitations
alter column short_code set default public.generate_relationship_invitation_short_code(),
alter column short_code set not null,
add constraint relationship_invitations_short_code_format
    check (short_code ~ '^[2-9A-HJ-KM-NP-Z]{8}$'),
add constraint relationship_invitations_short_code_key unique (short_code);

create table public.relationship_invitation_invalid_attempts (
    user_id uuid primary key references auth.users(id) on delete cascade,
    window_started_at timestamptz not null default now(),
    invalid_attempt_count integer not null default 0
        check (invalid_attempt_count between 0 and 5),
    updated_at timestamptz not null default now()
);

alter table public.relationship_invitation_invalid_attempts enable row level security;
revoke all on public.relationship_invitation_invalid_attempts from anon, authenticated;

create function public.resolve_relationship_invitation_identifier(
    provided_identifier text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    trimmed_identifier text := btrim(provided_identifier, E' \t\n\r');
    normalized_short_code text;
    provided_token uuid;
    resolved_token uuid;
    attempt_record public.relationship_invitation_invalid_attempts%rowtype;
begin
    if participant_id is null then
        raise exception 'authentication_required' using errcode = '42501';
    end if;

    insert into public.relationship_invitation_invalid_attempts (user_id)
    values (participant_id)
    on conflict (user_id) do nothing;

    select attempt.*
    into attempt_record
    from public.relationship_invitation_invalid_attempts attempt
    where attempt.user_id = participant_id
    for update;

    if attempt_record.window_started_at <= now() - interval '10 minutes' then
        update public.relationship_invitation_invalid_attempts attempt
        set window_started_at = now(),
            invalid_attempt_count = 0,
            updated_at = now()
        where attempt.user_id = participant_id;
        attempt_record.invalid_attempt_count := 0;
    end if;

    if attempt_record.invalid_attempt_count >= 5 then
        return null;
    end if;

    normalized_short_code := upper(
        regexp_replace(trimmed_identifier, '[[:space:]-]', '', 'g')
    );
    if trimmed_identifier ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        provided_token := trimmed_identifier::uuid;
    end if;

    select invitation.invite_token
    into resolved_token
    from public.relationship_invitations invitation
    where (
            invitation.short_code = normalized_short_code
            or invitation.invite_token = provided_token
        )
      and invitation.accepted_at is null
      and invitation.declined_at is null
      and invitation.expires_at > now()
    for update;

    if resolved_token is null then
        update public.relationship_invitation_invalid_attempts attempt
        set invalid_attempt_count = least(attempt.invalid_attempt_count + 1, 5),
            updated_at = now()
        where attempt.user_id = participant_id;
        return null;
    end if;

    delete from public.relationship_invitation_invalid_attempts attempt
    where attempt.user_id = participant_id;
    return resolved_token;
end;
$$;

revoke all on function public.resolve_relationship_invitation_identifier(text) from public;

create or replace function public.create_relationship_invitation()
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
    invitation_was_declined boolean;
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
          and member.membership_status = 'active';

        if current_member_count = 1 then
            select
                invitation.invite_token,
                invitation.expires_at,
                invitation.declined_at is not null
            into created_invite_token, created_expires_at, invitation_was_declined
            from public.relationship_invitations invitation
            where invitation.relationship_id = existing_relationship_id
              and invitation.created_by_user_id = participant_id
              and invitation.accepted_at is null
            for update;

            if found then
                if created_expires_at <= now() or invitation_was_declined then
                    update public.relationship_invitations invitation
                    set invite_token = gen_random_uuid(),
                        short_code = public.generate_relationship_invitation_short_code(),
                        expires_at = now() + interval '1 hour',
                        declined_by_user_id = null,
                        declined_at = null
                    where invitation.relationship_id = existing_relationship_id
                    returning invitation.invite_token, invitation.expires_at
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

    insert into public.relationship_invitations (relationship_id, created_by_user_id)
    values (created_relationship_id, participant_id)
    returning
        relationship_invitations.invite_token,
        relationship_invitations.expires_at
    into created_invite_token, created_expires_at;

    return query
    select created_relationship_id, created_invite_token, created_expires_at;
end;
$$;

create function public.create_relationship_invitation_v2()
returns table (
    relationship_id uuid,
    invite_token uuid,
    short_code text,
    expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    created_record record;
begin
    select *
    into created_record
    from public.create_relationship_invitation();

    return query
    select
        created_record.relationship_id,
        created_record.invite_token,
        invitation.short_code,
        created_record.expires_at
    from public.relationship_invitations invitation
    where invitation.relationship_id = created_record.relationship_id;
end;
$$;

create function public.accept_relationship_invitation_v2(provided_identifier text)
returns table (
    relationship_id uuid,
    result text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_token uuid;
begin
    resolved_token := public.resolve_relationship_invitation_identifier(provided_identifier);
    if resolved_token is null then
        return query select null::uuid, 'invitation_not_available'::text;
        return;
    end if;

    return query
    select public.accept_relationship_invitation(resolved_token), 'accepted'::text;
end;
$$;

create function public.decline_relationship_invitation_v2(provided_identifier text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_token uuid;
begin
    resolved_token := public.resolve_relationship_invitation_identifier(provided_identifier);
    if resolved_token is null then
        return 'invitation_not_available';
    end if;

    perform public.decline_relationship_invitation(resolved_token);
    return 'declined';
end;
$$;

revoke all on function public.create_relationship_invitation_v2() from public;
revoke all on function public.accept_relationship_invitation_v2(text) from public;
revoke all on function public.decline_relationship_invitation_v2(text) from public;
grant execute on function public.create_relationship_invitation_v2() to authenticated;
grant execute on function public.accept_relationship_invitation_v2(text) to authenticated;
grant execute on function public.decline_relationship_invitation_v2(text) to authenticated;
