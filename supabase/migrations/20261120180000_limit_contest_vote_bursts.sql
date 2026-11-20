create or replace function private.novelia_limit_contest_vote_bursts()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  recent_votes integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.voter_id::text, 0)
  );

  select count(*)::integer
    into recent_votes
    from public.novelia_contest_votes v
   where v.voter_id = new.voter_id
     and v.created_at > now() - interval '10 minutes';

  if recent_votes >= 5 then
    raise exception 'Trop de votes en peu de temps. Réessaie dans quelques minutes.'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function private.novelia_limit_contest_vote_bursts() from public, anon, authenticated;

drop trigger if exists nov_contest_vote_burst_limit on public.novelia_contest_votes;
create trigger nov_contest_vote_burst_limit
before insert on public.novelia_contest_votes
for each row execute function private.novelia_limit_contest_vote_bursts();
