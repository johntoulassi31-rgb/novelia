-- Restrict table ACLs; RLS remains the row-level authorization layer.
revoke all privileges on table public.novelia_contest_awards from public,anon,authenticated;
grant select on public.novelia_contest_awards to anon,authenticated;
grant insert,delete on public.novelia_contest_awards to authenticated;
revoke all privileges on table public.novelia_contest_jurors from public,anon,authenticated;
grant select,insert,delete on public.novelia_contest_jurors to authenticated;
revoke all privileges on table public.novelia_contest_reviews from public,anon,authenticated;
grant select,insert,update on public.novelia_contest_reviews to authenticated;
