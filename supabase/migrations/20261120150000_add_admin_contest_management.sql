-- Admin-only contest publishing and entry review.
create or replace function public.novelia_is_admin()
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.app_admins a where a.user_id=(select auth.uid())); $$;
revoke all on function public.novelia_is_admin() from public,anon;
grant execute on function public.novelia_is_admin() to authenticated;
grant insert,update,delete on public.novelia_contests to authenticated;
grant update on public.novelia_contest_entries to authenticated;
create policy "Novelia admins manage contests" on public.novelia_contests for all to authenticated using(public.novelia_is_admin()) with check(public.novelia_is_admin());
create policy "Novelia admins review contest entries" on public.novelia_contest_entries for select to authenticated using(public.novelia_is_admin());
create policy "Novelia admins update contest entries" on public.novelia_contest_entries for update to authenticated using(public.novelia_is_admin()) with check(public.novelia_is_admin());

-- Keep the SELECT policy set lean and separate anonymous from authenticated access.
drop policy if exists "Novelia admins manage contests" on public.novelia_contests;
drop policy if exists "Public can view published Novelia contests" on public.novelia_contests;
create policy "Public visitors view published contests" on public.novelia_contests for select to anon using(status in ('open','voting','closed'));
create policy "Members view published or manage contests" on public.novelia_contests for select to authenticated using(status in ('open','voting','closed') or public.novelia_is_admin());
create policy "Novelia admins create contests" on public.novelia_contests for insert to authenticated with check(public.novelia_is_admin());
create policy "Novelia admins update contests" on public.novelia_contests for update to authenticated using(public.novelia_is_admin()) with check(public.novelia_is_admin());
create policy "Novelia admins delete contests" on public.novelia_contests for delete to authenticated using(public.novelia_is_admin());
drop policy if exists "Authors can view approved contest entries" on public.novelia_contest_entries;
drop policy if exists "Novelia admins review contest entries" on public.novelia_contest_entries;
create policy "Public visitors view approved contest entries" on public.novelia_contest_entries for select to anon using(status='approved');
create policy "Authors and admins view contest entries" on public.novelia_contest_entries for select to authenticated using(status='approved' or author_id=(select auth.uid()) or public.novelia_is_admin());
