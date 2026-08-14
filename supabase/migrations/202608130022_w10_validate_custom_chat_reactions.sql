alter table public.shared_item_reactions
    drop constraint shared_item_reactions_emoji_value_check;

alter table public.shared_item_reactions
    add constraint shared_item_reactions_emoji_value_check
    check (
        emoji_value in ('heart', 'hug', 'smile', 'cheer', 'laugh', 'support')
        or (
            char_length(emoji_value) between 1 and 8
            and octet_length(emoji_value) <= 32
            and emoji_value !~ '[[:alnum:][:space:][:cntrl:][:punct:]]'
        )
    );

create function public.validate_shared_item_reaction_emoji()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.emoji_value in ('heart', 'hug', 'smile', 'cheer', 'laugh', 'support')
       or (
           char_length(new.emoji_value) between 1 and 8
           and octet_length(new.emoji_value) <= 32
           and new.emoji_value !~ '[[:alnum:][:space:][:cntrl:][:punct:]]'
       ) then
        return new;
    end if;

    raise exception 'invalid_message_reaction' using errcode = '22023';
end;
$$;

create trigger validate_shared_item_reaction_emoji
before insert or update of emoji_value on public.shared_item_reactions
for each row execute function public.validate_shared_item_reaction_emoji();

revoke all on function public.validate_shared_item_reaction_emoji() from public;
