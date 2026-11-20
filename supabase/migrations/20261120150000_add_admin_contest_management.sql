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
