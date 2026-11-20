-- Live Supabase migration applied 2026-11-20. Hardens trigger return behavior
-- and ensures jury review updates remain bound to approved entries in the active phase.
create or replace function public.novelia_contest_review_totals_trigger()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='DELETE' then perform public.novelia_refresh_contest_entry_totals(old.entry_id); return old;
  else perform public.novelia_refresh_contest_entry_totals(new.entry_id); return new; end if;
end; $$;
create or replace function public.novelia_contest_vote_totals_trigger()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='DELETE' then perform public.novelia_refresh_contest_entry_totals(old.entry_id); return old;
  else perform public.novelia_refresh_contest_entry_totals(new.entry_id); return new; end if;
end; $$;
drop policy if exists "Assigned jurors update their reviews" on public.novelia_contest_reviews;
create policy "Assigned jurors update their reviews" on public.novelia_contest_reviews for update to authenticated
using(juror_id=(select auth.uid()) and exists(select 1 from public.novelia_contest_jurors j where j.contest_id=novelia_contest_reviews.contest_id and j.juror_id=(select auth.uid())))
with check(juror_id=(select auth.uid()) and exists(select 1 from public.novelia_contest_jurors j where j.contest_id=novelia_contest_reviews.contest_id and j.juror_id=(select auth.uid()))
and exists(select 1 from public.novelia_contest_entries e join public.novelia_contests c on c.id=e.contest_id where e.id=novelia_contest_reviews.entry_id and e.contest_id=novelia_contest_reviews.contest_id and e.status='approved' and c.status in ('judging','voting')));
