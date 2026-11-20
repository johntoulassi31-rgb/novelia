create or replace view public.novelia_public_monetization_config
with (security_barrier = true)
as
select enabled,author_share_bps,minimum_payout_xof,
       minimum_chapter_price_xof,maximum_chapter_price_xof,updated_at
from public.novelia_monetization_settings
where id=true;

revoke all on public.novelia_public_monetization_config from public;
grant select on public.novelia_public_monetization_config to anon,authenticated;
