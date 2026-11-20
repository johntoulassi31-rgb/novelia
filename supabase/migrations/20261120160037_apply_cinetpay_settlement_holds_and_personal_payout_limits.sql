alter table public.novelia_monetization_settings
  add column settlement_hold_days integer not null default 7 check (settlement_hold_days between 0 and 30),
  add column daily_payout_limit_xof bigint not null default 400000 check (daily_payout_limit_xof between 1 and 10000000),
  add column weekly_payout_limit_xof bigint not null default 700000 check (weekly_payout_limit_xof between 1 and 50000000),
  add column monthly_payout_limit_xof bigint not null default 1000000 check (monthly_payout_limit_xof between 1 and 100000000);

update public.novelia_monetization_settings
set maximum_payout_xof=400000
where id=true and maximum_payout_xof=1500000 and enabled=false;

alter table public.novelia_monetization_settings
  add constraint nov_monetization_payout_caps_order
  check (weekly_payout_limit_xof >= daily_payout_limit_xof
     and monthly_payout_limit_xof >= weekly_payout_limit_xof
     and maximum_payout_xof <= daily_payout_limit_xof);

alter table public.novelia_author_wallet_ledger
  add column available_at timestamptz not null default now();

create or replace function private.novelia_sync_purchase_wallet_ledger()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_hold_days integer;
  v_sale_available_at timestamptz;
begin
  select settlement_hold_days into v_hold_days from public.novelia_monetization_settings where id=true;
  v_hold_days:=coalesce(v_hold_days,7);
  if new.status='paid' and old.status is distinct from 'paid' then
    insert into public.novelia_author_wallets(author_id) values(new.author_id) on conflict(author_id) do nothing;
    insert into public.novelia_author_wallet_ledger(
      author_id,amount_xof,entry_type,purchase_id,description,idempotency_key,available_at
    ) values(
      new.author_id,new.author_earning_xof,'chapter_sale',new.id,
      'Vente du chapitre '||new.chapter_id::text,'purchase_paid:'||new.id::text,
      coalesce(new.paid_at,now())+make_interval(days=>v_hold_days)
    ) on conflict(idempotency_key) do nothing;
  elsif old.status='paid' and new.status='refunded' then
    select available_at into v_sale_available_at from public.novelia_author_wallet_ledger
    where idempotency_key='purchase_paid:'||new.id::text;
    insert into public.novelia_author_wallet_ledger(
      author_id,amount_xof,entry_type,purchase_id,description,idempotency_key,available_at
    ) values(
      new.author_id,-new.author_earning_xof,'chapter_refund',new.id,
      'Remboursement du chapitre '||new.chapter_id::text,'purchase_refund:'||new.id::text,
      greatest(now(),coalesce(v_sale_available_at,now()))
    ) on conflict(idempotency_key) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.novelia_sync_purchase_wallet_ledger() from public,anon,authenticated;

create or replace view public.novelia_author_wallet_balances
with (security_invoker=true) as
select w.author_id,
       coalesce(sum(l.amount_xof) filter(where l.available_at<=now()),0)::bigint as available_balance_xof
from public.novelia_author_wallets w
left join public.novelia_author_wallet_ledger l on l.author_id=w.author_id
group by w.author_id;

create or replace view public.novelia_author_wallet_pending_balances
with (security_invoker=true) as
select w.author_id,
       coalesce(sum(l.amount_xof) filter(where l.available_at>now()),0)::bigint as pending_balance_xof,
       min(l.available_at) filter(where l.available_at>now()) as next_available_at
from public.novelia_author_wallets w
left join public.novelia_author_wallet_ledger l on l.author_id=w.author_id
group by w.author_id;
revoke all on public.novelia_author_wallet_pending_balances from public;
grant select on public.novelia_author_wallet_pending_balances to authenticated;

create or replace function public.novelia_request_payout(p_destination_id uuid,p_amount_xof bigint)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_user uuid := (select auth.uid()); v_request_id uuid; v_balance bigint;
  v_minimum bigint; v_maximum bigint; v_daily_limit bigint; v_weekly_limit bigint; v_monthly_limit bigint;
  v_daily_used bigint; v_weekly_used bigint; v_monthly_used bigint; v_enabled boolean;
  v_operator text; v_phone text; v_holder text;
begin
  if v_user is null then raise exception 'Connecte-toi pour demander un retrait.'; end if;
  if public.novelia_is_suspended() then raise exception 'Ton compte ne peut pas effectuer de retrait actuellement.'; end if;
  if p_amount_xof is null or p_amount_xof<=0 then raise exception 'Montant de retrait invalide.'; end if;
  select enabled,minimum_payout_xof,maximum_payout_xof,daily_payout_limit_xof,weekly_payout_limit_xof,monthly_payout_limit_xof
  into v_enabled,v_minimum,v_maximum,v_daily_limit,v_weekly_limit,v_monthly_limit
  from public.novelia_monetization_settings where id=true;
  if coalesce(v_enabled,false)=false then raise exception 'Les retraits ne sont pas encore activés.'; end if;
  if p_amount_xof<v_minimum then raise exception 'Le montant est inférieur au minimum de retrait.'; end if;
  if p_amount_xof>v_maximum then raise exception 'Le montant dépasse le maximum par retrait autorisé.'; end if;
  select d.operator,d.phone_number,d.account_holder into v_operator,v_phone,v_holder
  from public.novelia_payout_destinations d where d.id=p_destination_id and d.author_id=v_user;
  if not found then raise exception 'Moyen de paiement introuvable.'; end if;
  insert into public.novelia_author_wallets(author_id) values(v_user) on conflict(author_id) do nothing;
  perform 1 from public.novelia_author_wallets w where w.author_id=v_user for update;
  select coalesce(sum(l.amount_xof),0)::bigint into v_balance
  from public.novelia_author_wallet_ledger l where l.author_id=v_user and l.available_at<=now();
  if p_amount_xof>v_balance then raise exception 'Solde disponible insuffisant ou encore en délai de règlement.'; end if;
  select coalesce(sum(r.amount_xof),0)::bigint into v_daily_used from public.novelia_payout_requests r
  where r.author_id=v_user and r.status in ('requested','approved','processing','paid') and r.created_at>=date_trunc('day',now());
  if v_daily_used+p_amount_xof>v_daily_limit then raise exception 'Plafond journalier de retrait atteint.'; end if;
  select coalesce(sum(r.amount_xof),0)::bigint into v_weekly_used from public.novelia_payout_requests r
  where r.author_id=v_user and r.status in ('requested','approved','processing','paid') and r.created_at>=date_trunc('week',now());
  if v_weekly_used+p_amount_xof>v_weekly_limit then raise exception 'Plafond hebdomadaire de retrait atteint.'; end if;
  select coalesce(sum(r.amount_xof),0)::bigint into v_monthly_used from public.novelia_payout_requests r
  where r.author_id=v_user and r.status in ('requested','approved','processing','paid') and r.created_at>=date_trunc('month',now());
  if v_monthly_used+p_amount_xof>v_monthly_limit then raise exception 'Plafond mensuel de retrait atteint.'; end if;
  insert into public.novelia_payout_requests(author_id,destination_id,destination_operator,destination_phone_number,destination_account_holder,amount_xof)
  values(v_user,p_destination_id,v_operator,v_phone,v_holder,p_amount_xof) returning id into v_request_id;
  insert into public.novelia_author_wallet_ledger(author_id,amount_xof,entry_type,payout_request_id,description,idempotency_key)
  values(v_user,-p_amount_xof,'payout_hold',v_request_id,'Montant réservé pour une demande de retrait','payout_hold:'||v_request_id::text);
  return v_request_id;
end;
$$;
revoke all on function public.novelia_request_payout(uuid,bigint) from public,anon;
grant execute on function public.novelia_request_payout(uuid,bigint) to authenticated;

create or replace view public.novelia_public_monetization_config
with (security_invoker=true,security_barrier=true)
as
select enabled,author_share_bps,minimum_payout_xof,minimum_chapter_price_xof,
       maximum_chapter_price_xof,updated_at,maximum_payout_xof,settlement_hold_days,
       daily_payout_limit_xof,weekly_payout_limit_xof,monthly_payout_limit_xof
from public.novelia_monetization_settings where id=true;

grant select (maximum_payout_xof,settlement_hold_days,daily_payout_limit_xof,
              weekly_payout_limit_xof,monthly_payout_limit_xof)
on public.novelia_monetization_settings to anon,authenticated;
