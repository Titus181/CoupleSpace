begin;

select plan(4);

select ok(
    to_regprocedure('public.register_push_device(text,text)') is not null,
    'generic push registration keeps the two-argument RPC'
);

select ok(
    to_regprocedure('public.register_push_device(text,text,boolean)') is null,
    'content preview registration overload is unavailable'
);

select ok(
    position(
        'content_preview_enabled' in
        pg_get_functiondef('public.register_push_device(text,text)'::regprocedure)
    ) = 0,
    'generic push registration does not read or update the legacy preference'
);

select ok(
    not exists (
        select 1
        from public.push_devices
        where content_preview_enabled
    ),
    'migration resets legacy preview preferences to generic-only'
);

select * from finish();

rollback;
