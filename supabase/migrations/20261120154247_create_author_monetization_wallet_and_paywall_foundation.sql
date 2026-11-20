create table if not exists public.novelia_monetization_settings (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  author_share_bps integer not null default 7000 check (author_share_bps between 1 and 9999),
  minimum_payout_xof bigint not null default 5000 check (minimum_payout_xof > 0),
  minimum_chapter_price_xof integer not null default 100 check (minimum_chapter_price_xof > 0),
  maximum_chapter_price_xof integer not null default 50000 check (maximum_chapter_price_xof >= minimum_chapter_price_xof),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.novelia_monetization_settings(id) values(true) on conflict(id) do nothing;
alter table public.novelia_monetization_settings enable row level security;
revoke all on public.novelia_monetization_settings from anon, authenticated;
grant select, update on public.novelia_monetization_settings to authenticated;
create policy "Admins manage monetization settings" on public.novelia_monetization_settings
for all to authenticated using (public.novelia_is_admin()) with check (public.novelia_is_admin());

alter table public.chapters add column if not exists is_premium boolean not null default false;
alter table public.chapters add column if not exists price_xof integer;
alter table public.chapters add constraint chapters_premium_price_check
check ((is_premium = false and price_xof is null) or (is_premium = true and price_xof > 0));

create view public.novelia_chapter_catalog with (security_barrier = true) as
select c.id,c.story_id,c.title,c.chapter_number,c.created_at,c.is_premium,c.price_xof,
       c.audio_url,c.audio_title,c.audio_duration_seconds
from public.chapters c
where c.moderation_hidden=false and exists (
  select 1 from public.stories s where s.id=c.story_id
    and s.status='published' and s.moderation_hidden=false
);
revoke all on public.novelia_chapter_catalog from public;
grant select on public.novelia_chapter_catalog to anon,authenticated;

create table public.novelia_author_wallets (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.novelia_author_wallets enable row level security;
revoke all on public.novelia_author_wallets from anon,authenticated;
grant select on public.novelia_author_wallets to authenticated;
create policy "Authors view their wallet and admins view all" on public.novelia_author_wallets
for select to authenticated using (author_id=(select auth.uid()) or public.novelia_is_admin());

create table public.novelia_payout_destinations (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  country_code text not null default 'TG' check (country_code='TG'),
  operator text not null check (operator in ('moov_tg','tmoney_tg')),
  phone_number text not null check (phone_number ~ '^\+228[0-9]{8}$'),
  account_holder text not null check (length(trim(account_holder)) between 2 and 120),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  unique(author_id,operator,phone_number)
);
create index idx_novelia_payout_destinations_author on public.novelia_payout_destinations(author_id);
alter table public.novelia_payout_destinations enable row level security;
revoke all on public.novelia_payout_destinations from anon,authenticated;
grant select,insert,update,delete on public.novelia_payout_destinations to authenticated;
create policy "Authors manage their payout destinations" on public.novelia_payout_destinations
for all to authenticated using (author_id=(select auth.uid()) and not public.novelia_is_suspended())
with check (author_id=(select auth.uid()) and not public.novelia_is_suspended());
create policy "Admins view payout destinations" on public.novelia_payout_destinations
for select to authenticated using (public.novelia_is_admin());

create table public.novelia_chapter_purchases (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete restrict,
  author_id uuid not null references auth.users(id) on delete restrict,
  story_id uuid not null references public.stories(id) on delete restrict,
  chapter_id uuid not null references public.chapters(id) on delete restrict,
  payment_provider text not null default 'cinetpay' check (payment_provider in ('cinetpay')),
  client_transaction_id text not null unique,
  provider_transaction_id text unique,
  status text not null default 'pending' check (status in ('pending','paid','failed','refunded')),
  gross_amount_xof bigint not null check (gross_amount_xof > 0),
  provider_fee_xof bigint not null default 0 check (provider_fee_xof >= 0),
  platform_fee_xof bigint not null default 0 check (platform_fee_xof >= 0),
  author_earning_xof bigint not null default 0 check (author_earning_xof >= 0),
  checkout_url text,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  updated_at timestamptz not null default now(),
  check (buyer_id <> author_id),
  check (status <> 'paid' or provider_fee_xof+platform_fee_xof+author_earning_xof=gross_amount_xof)
);
create unique index idx_novelia_paid_chapter_purchase on public.novelia_chapter_purchases(buyer_id,chapter_id) where status='paid';
create index idx_novelia_chapter_purchases_buyer on public.novelia_chapter_purchases(buyer_id,created_at desc);
create index idx_novelia_chapter_purchases_author on public.novelia_chapter_purchases(author_id,created_at desc);
alter table public.novelia_chapter_purchases enable row level security;
revoke all on public.novelia_chapter_purchases from anon,authenticated;
grant select on public.novelia_chapter_purchases to authenticated;
create policy "Buyers view their purchases and admins view all" on public.novelia_chapter_purchases
for select to authenticated using (buyer_id=(select auth.uid()) or public.novelia_is_admin());

create table public.novelia_payout_requests (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete restrict,
  destination_id uuid not null references public.novelia_payout_destinations(id) on delete restrict,
  amount_xof bigint not null check (amount_xof > 0),
  status text not null default 'requested' check (status in ('requested','approved','processing','paid','failed','cancelled')),
  provider_transaction_id text unique,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  processed_at timestamptz
);
create index idx_novelia_payout_requests_author on public.novelia_payout_requests(author_id,created_at desc);
create index idx_novelia_payout_requests_status on public.novelia_payout_requests(status,created_at);
alter table public.novelia_payout_requests enable row level security;
revoke all on public.novelia_payout_requests from anon,authenticated;
grant select on public.novelia_payout_requests to authenticated;
grant update(status,provider_transaction_id,admin_note,processed_at,updated_at) on public.novelia_payout_requests to authenticated;
create policy "Authors and admins view payout requests" on public.novelia_payout_requests
for select to authenticated using (author_id=(select auth.uid()) or public.novelia_is_admin());
create policy "Admins process payout requests" on public.novelia_payout_requests
for update to authenticated using (public.novelia_is_admin()) with check (public.novelia_is_admin());

create table public.novelia_author_wallet_ledger (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete restrict,
  amount_xof bigint not null check (amount_xof<>0),
  entry_type text not null check (entry_type in ('chapter_sale','chapter_refund','payout_hold','payout_release','manual_adjustment')),
  purchase_id uuid references public.novelia_chapter_purchases(id) on delete restrict,
  payout_request_id uuid references public.novelia_payout_requests(id) on delete restrict,
  description text not null,
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  check (num_nonnulls(purchase_id,payout_request_id)<=1)
);
create index idx_novelia_wallet_ledger_author_created on public.novelia_author_wallet_ledger(author_id,created_at desc);
alter table public.novelia_author_wallet_ledger enable row level security;
revoke all on public.novelia_author_wallet_ledger from anon,authenticated;
grant select on public.novelia_author_wallet_ledger to authenticated;
create policy "Authors view their ledger and admins view all" on public.novelia_author_wallet_ledger
for select to authenticated using (author_id=(select auth.uid()) or public.novelia_is_admin());

create view public.novelia_author_wallet_balances with (security_invoker=true) as
select w.author_id,coalesce(sum(l.amount_xof),0)::bigint as available_balance_xof
from public.novelia_author_wallets w left join public.novelia_author_wallet_ledger l on l.author_id=w.author_id
group by w.author_id;
revoke all on public.novelia_author_wallet_balances from public;
grant select on public.novelia_author_wallet_balances to authenticated;

create function private.novelia_sync_purchase_wallet_ledger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status='paid' and old.status is distinct from 'paid' then
    insert into public.novelia_author_wallets(author_id) values(new.author_id) on conflict(author_id) do nothing;
    insert into public.novelia_author_wallet_ledger(author_id,amount_xof,entry_type,purchase_id,description,idempotency_key)
    values(new.author_id,new.author_earning_xof,'chapter_sale',new.id,'Vente du chapitre '||new.chapter_id::text,'purchase_paid:'||new.id::text)
    on conflict(idempotency_key) do nothing;
  elsif old.status='paid' and new.status='refunded' then
    insert into public.novelia_author_wallet_ledger(author_id,amount_xof,entry_type,purchase_id,description,idempotency_key)
    values(new.author_id,-new.author_earning_xof,'chapter_refund',new.id,'Remboursement du chapitre '||new.chapter_id::text,'purchase_refund:'||new.id::text)
    on conflict(idempotency_key) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.novelia_sync_purchase_wallet_ledger() from public,anon,authenticated;
create trigger nov_chapter_purchase_wallet_ledger after update of status on public.novelia_chapter_purchases
for each row execute function private.novelia_sync_purchase_wallet_ledger();

create function private.novelia_release_failed_payout_hold()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.status in ('requested','approved','processing') and new.status in ('failed','cancelled') then
    insert into public.novelia_author_wallet_ledger(author_id,amount_xof,entry_type,payout_request_id,description,idempotency_key)
    values(new.author_id,new.amount_xof,'payout_release',new.id,'Libération du solde après échec ou annulation du retrait','payout_release:'||new.id::text)
    on conflict(idempotency_key) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.novelia_release_failed_payout_hold() from public,anon,authenticated;
create trigger nov_payout_release_hold after update of status on public.novelia_payout_requests
for each row execute function private.novelia_release_failed_payout_hold();

create function public.novelia_request_payout(p_destination_id uuid,p_amount_xof bigint)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_user uuid := (select auth.uid());
  v_request_id uuid;
  v_balance bigint;
  v_minimum bigint;
  v_enabled boolean;
begin
  if v_user is null then raise exception 'Connecte-toi pour demander un retrait.'; end if;
  if public.novelia_is_suspended() then raise exception 'Ton compte ne peut pas effectuer de retrait actuellement.'; end if;
  if p_amount_xof is null or p_amount_xof<=0 then raise exception 'Montant de retrait invalide.'; end if;
  select enabled,minimum_payout_xof into v_enabled,v_minimum from public.novelia_monetization_settings where id=true;
  if coalesce(v_enabled,false)=false then raise exception 'Les retraits ne sont pas encore activés.'; end if;
  if p_amount_xof<v_minimum then raise exception 'Le montant est inférieur au minimum de retrait.'; end if;
  if not exists(select 1 from public.novelia_payout_destinations d where d.id=p_destination_id and d.author_id=v_user) then
    raise exception 'Moyen de paiement introuvable.';
  end if;
  insert into public.novelia_author_wallets(author_id) values(v_user) on conflict(author_id) do nothing;
  perform 1 from public.novelia_author_wallets w where w.author_id=v_user for update;
  select coalesce(sum(l.amount_xof),0)::bigint into v_balance from public.novelia_author_wallet_ledger l where l.author_id=v_user;
  if p_amount_xof>v_balance then raise exception 'Solde disponible insuffisant.'; end if;
  insert into public.novelia_payout_requests(author_id,destination_id,amount_xof)
  values(v_user,p_destination_id,p_amount_xof) returning id into v_request_id;
  insert into public.novelia_author_wallet_ledger(author_id,amount_xof,entry_type,payout_request_id,description,idempotency_key)
  values(v_user,-p_amount_xof,'payout_hold',v_request_id,'Montant réservé pour une demande de retrait','payout_hold:'||v_request_id::text);
  return v_request_id;
end;
$$;
revoke all on function public.novelia_request_payout(uuid,bigint) from public,anon;
grant execute on function public.novelia_request_payout(uuid,bigint) to authenticated;

drop policy if exists "Read visible chapters of accessible stories" on public.chapters;
create policy "Read visible chapters of accessible stories" on public.chapters for select to anon,authenticated
using (
  (moderation_hidden=false and exists(select 1 from public.stories s where s.id=chapters.story_id and s.status='published' and s.moderation_hidden=false)
   and (coalesce(is_premium,false)=false or exists(select 1 from public.novelia_chapter_purchases p where p.chapter_id=chapters.id and p.buyer_id=(select auth.uid()) and p.status='paid')))
  or exists(select 1 from public.stories s where s.id=chapters.story_id and s.author_id=(select auth.uid()))
  or public.novelia_is_admin()
);

drop policy if exists "Authors insert chapters" on public.chapters;
create policy "Authors insert chapters" on public.chapters for insert to authenticated
with check (
  not public.novelia_is_suspended()
  and exists(select 1 from public.stories s where s.id=chapters.story_id and s.author_id=(select auth.uid()))
  and (is_premium=false or exists(select 1 from public.novelia_monetization_settings m where m.id=true and m.enabled=true and price_xof between m.minimum_chapter_price_xof and m.maximum_chapter_price_xof))
);

drop policy if exists "Authors update chapters and admins moderate" on public.chapters;
create policy "Authors update chapters and admins moderate" on public.chapters for update to authenticated
using (not public.novelia_is_suspended() and (exists(select 1 from public.stories s where s.id=chapters.story_id and s.author_id=(select auth.uid())) or public.novelia_is_admin()))
with check (
  not public.novelia_is_suspended()
  and (exists(select 1 from public.stories s where s.id=chapters.story_id and s.author_id=(select auth.uid())) or public.novelia_is_admin())
  and (is_premium=false or exists(select 1 from public.novelia_monetization_settings m where m.id=true and m.enabled=true and price_xof between m.minimum_chapter_price_xof and m.maximum_chapter_price_xof))
);
