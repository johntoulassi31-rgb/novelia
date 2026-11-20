drop view if exists public.novelia_chapter_catalog;
create table public.novelia_chapter_catalog (
  id uuid primary key references public.chapters(id) on delete cascade,
  story_id uuid not null references public.stories(id) on delete cascade,
  title text not null,
  chapter_number integer not null,
  created_at timestamptz not null,
  is_premium boolean not null default false,
  price_xof integer,
  audio_url text,
  audio_title text,
  audio_duration_seconds integer,
  moderation_hidden boolean not null default false
);
create index idx_novelia_chapter_catalog_story_order on public.novelia_chapter_catalog(story_id,chapter_number);
alter table public.novelia_chapter_catalog enable row level security;
revoke all on public.novelia_chapter_catalog from public,anon,authenticated;
grant select on public.novelia_chapter_catalog to anon,authenticated;
create policy "Public catalog shows metadata for published stories"
on public.novelia_chapter_catalog for select to anon,authenticated
using (
  moderation_hidden=false
  and exists (
    select 1 from public.stories s
    where s.id=novelia_chapter_catalog.story_id
      and s.status='published' and s.moderation_hidden=false
  )
);

create function private.novelia_sync_chapter_catalog()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='DELETE' then
    delete from public.novelia_chapter_catalog where id=old.id;
    return old;
  end if;
  insert into public.novelia_chapter_catalog(
    id,story_id,title,chapter_number,created_at,is_premium,price_xof,
    audio_url,audio_title,audio_duration_seconds,moderation_hidden
  ) values (
    new.id,new.story_id,new.title,new.chapter_number,new.created_at,
    coalesce(new.is_premium,false),new.price_xof,new.audio_url,new.audio_title,
    new.audio_duration_seconds,coalesce(new.moderation_hidden,false)
  )
  on conflict(id) do update set
    story_id=excluded.story_id,title=excluded.title,chapter_number=excluded.chapter_number,
    created_at=excluded.created_at,is_premium=excluded.is_premium,price_xof=excluded.price_xof,
    audio_url=excluded.audio_url,audio_title=excluded.audio_title,
    audio_duration_seconds=excluded.audio_duration_seconds,moderation_hidden=excluded.moderation_hidden;
  return new;
end;
$$;
revoke all on function private.novelia_sync_chapter_catalog() from public,anon,authenticated;
create trigger nov_sync_chapter_catalog after insert or update or delete on public.chapters
for each row execute function private.novelia_sync_chapter_catalog();

insert into public.novelia_chapter_catalog(
  id,story_id,title,chapter_number,created_at,is_premium,price_xof,
  audio_url,audio_title,audio_duration_seconds,moderation_hidden
)
select id,story_id,title,chapter_number,created_at,coalesce(is_premium,false),price_xof,
       audio_url,audio_title,audio_duration_seconds,coalesce(moderation_hidden,false)
from public.chapters
on conflict(id) do update set
  story_id=excluded.story_id,title=excluded.title,chapter_number=excluded.chapter_number,
  created_at=excluded.created_at,is_premium=excluded.is_premium,price_xof=excluded.price_xof,
  audio_url=excluded.audio_url,audio_title=excluded.audio_title,
  audio_duration_seconds=excluded.audio_duration_seconds,moderation_hidden=excluded.moderation_hidden;

create or replace view public.novelia_public_monetization_config
with (security_invoker=true,security_barrier=true)
as
select enabled,author_share_bps,minimum_payout_xof,
       minimum_chapter_price_xof,maximum_chapter_price_xof,updated_at
from public.novelia_monetization_settings where id=true;
revoke all on public.novelia_public_monetization_config from public;
grant select on public.novelia_public_monetization_config to anon,authenticated;

revoke select on public.novelia_monetization_settings from authenticated;
grant select (id,enabled,author_share_bps,minimum_payout_xof,minimum_chapter_price_xof,
              maximum_chapter_price_xof,moov_fee_bps,tmoney_fee_bps,updated_at)
on public.novelia_monetization_settings to authenticated;
grant select (id,enabled,author_share_bps,minimum_payout_xof,minimum_chapter_price_xof,
              maximum_chapter_price_xof,updated_at)
on public.novelia_monetization_settings to anon;
create policy "Public can view safe monetization settings"
on public.novelia_monetization_settings for select to anon,authenticated using (id=true);

drop policy if exists "Authors manage their payout destinations" on public.novelia_payout_destinations;
drop policy if exists "Admins view payout destinations" on public.novelia_payout_destinations;
create policy "Authors and admins view payout destinations"
on public.novelia_payout_destinations for select to authenticated
using (author_id=(select auth.uid()) or public.novelia_is_admin());
create policy "Authors add payout destinations"
on public.novelia_payout_destinations for insert to authenticated
with check (author_id=(select auth.uid()) and not public.novelia_is_suspended());
create policy "Authors update payout destinations"
on public.novelia_payout_destinations for update to authenticated
using (author_id=(select auth.uid()) and not public.novelia_is_suspended())
with check (author_id=(select auth.uid()) and not public.novelia_is_suspended());
create policy "Authors delete payout destinations"
on public.novelia_payout_destinations for delete to authenticated
using (author_id=(select auth.uid()) and not public.novelia_is_suspended());

create index if not exists idx_novelia_wallet_ledger_payout_request on public.novelia_author_wallet_ledger(payout_request_id);
create index if not exists idx_novelia_wallet_ledger_purchase on public.novelia_author_wallet_ledger(purchase_id);
create index if not exists idx_novelia_chapter_purchases_chapter on public.novelia_chapter_purchases(chapter_id);
create index if not exists idx_novelia_chapter_purchases_story on public.novelia_chapter_purchases(story_id);
create index if not exists idx_novelia_monetization_settings_updated_by on public.novelia_monetization_settings(updated_by);
create index if not exists idx_novelia_payout_requests_destination on public.novelia_payout_requests(destination_id);
