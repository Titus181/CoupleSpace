create function public.claim_w1_push_job(
    target_job_id uuid,
    target_sender_user_id uuid
)
returns table (
    job_id uuid,
    event_id uuid,
    event_kind text,
    recipient_user_id uuid,
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
        job.event_id,
        job.event_kind,
        job.recipient_user_id,
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

create function public.complete_w1_push_job(
    target_job_id uuid,
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
          and job.claimed_at is not null
          and job.delivered_at is null;
    else
        update public.push_delivery_jobs job
        set claimed_at = null,
            last_error = left(coalesce(target_error, 'apns_delivery_failed'), 500)
        where job.id = target_job_id
          and job.claimed_at is not null
          and job.delivered_at is null;
    end if;

    if not found then
        raise exception 'push_job_not_completable' using errcode = '55000';
    end if;
end;
$$;

revoke update on public.push_delivery_jobs from service_role;
revoke all on function public.claim_w1_push_job(uuid, uuid) from public;
revoke all on function public.complete_w1_push_job(uuid, boolean, text) from public;

grant execute on function public.claim_w1_push_job(uuid, uuid) to service_role;
grant execute on function public.complete_w1_push_job(uuid, boolean, text) to service_role;
