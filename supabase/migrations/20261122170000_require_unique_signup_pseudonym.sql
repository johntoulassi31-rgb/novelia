-- Require a unique, case-insensitive Novelia username at account creation.
create unique index if not exists profiles_username_lower_uidx
  on public.profiles (lower(username))
  where username is not null;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requested_username text;
  auth_provider text;
begin
  requested_username := nullif(btrim(new.raw_user_meta_data ->> 'username'), '');
  auth_provider := coalesce(new.raw_app_meta_data ->> 'provider', '');

  if auth_provider = 'email' and requested_username is null then
    raise exception 'Un pseudonyme est obligatoire pour créer un compte Novelia.';
  end if;

  if requested_username is not null
     and requested_username !~ '^[A-Za-z0-9_]{3,24}$' then
    raise exception 'Le pseudonyme doit contenir 3 à 24 caractères : lettres, chiffres ou _.';
  end if;

  insert into public.profiles (id, username, display_name)
  values (new.id, requested_username, null)
  on conflict (id) do update
    set username = coalesce(public.profiles.username, excluded.username);

  return new;
end;
$function$;
