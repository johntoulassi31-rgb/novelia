-- Prevent jury conflicts of interest: a juror cannot score their own work.
drop policy if exists "Assigned jurors submit reviews" on public.novelia_contest_reviews;
create policy "Assigned jurors submit reviews" on public.novelia_contest_reviews
for insert to authenticated with check (
 juror_id=(select auth.uid()) and not public.novelia_is_suspended()
 and exists(select 1 from public.novelia_contest_jurors j where j.contest_id=novelia_contest_reviews.contest_id and j.juror_id=(select auth.uid()))
 and exists(select 1 from public.novelia_contest_entries e join public.novelia_contests c on c.id=e.contest_id
 where e.id=novelia_contest_reviews.entry_id and e.contest_id=novelia_contest_reviews.contest_id
 and e.status='approved' and e.author_id<>(select auth.uid()) and c.status in ('judging','voting'))
);
drop policy if exists "Assigned jurors update their reviews" on public.novelia_contest_reviews;
create policy "Assigned jurors update their reviews" on public.novelia_contest_reviews
for update to authenticated
using (juror_id=(select auth.uid()) and exists(select 1 from public.novelia_contest_jurors j where j.contest_id=novelia_contest_reviews.contest_id and j.juror_id=(select auth.uid())))
with check (
 juror_id=(select auth.uid()) and not public.novelia_is_suspended()
 and exists(select 1 from public.novelia_contest_jurors j where j.contest_id=novelia_contest_reviews.contest_id and j.juror_id=(select auth.uid()))
 and exists(select 1 from public.novelia_contest_entries e join public.novelia_contests c on c.id=e.contest_id
 where e.id=novelia_contest_reviews.entry_id and e.contest_id=novelia_contest_reviews.contest_id
 and e.status='approved' and e.author_id<>(select auth.uid()) and c.status in ('judging','voting'))
);
