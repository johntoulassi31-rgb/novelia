drop policy if exists "Admins manage monetization settings" on public.novelia_monetization_settings;
create policy "Admins update monetization settings"
on public.novelia_monetization_settings for update to authenticated
using (public.novelia_is_admin())
with check (public.novelia_is_admin());
