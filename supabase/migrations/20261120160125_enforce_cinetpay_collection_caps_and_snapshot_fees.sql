alter table public.novelia_monetization_settings
  add column daily_collection_limit_xof bigint not null default 400000 check (daily_collection_limit_xof between 1 and 10000000),
  add column weekly_collection_limit_xof bigint not null default 700000 check (weekly_collection_limit_xof between 1 and 50000000),
  add column monthly_collection_limit_xof bigint not null default 1000000 check (monthly_collection_limit_xof between 1 and 100000000),
  add constraint nov_monetization_collection_caps_order
  check (weekly_collection_limit_xof >= daily_collection_limit_xof
     and monthly_collection_limit_xof >= weekly_collection_limit_xof);

create or replace function private.novelia_validate_chapter_purchase()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_author uuid; v_story uuid; v_price integer; v_premium boolean; v_hidden boolean;
  v_story_status text; v_enabled boolean; v_share_bps integer; v_fee_bps integer;
  v_daily_limit bigint; v_weekly_limit bigint; v_monthly_limit bigint;
  v_daily_used bigint; v_weekly_used bigint; v_monthly_used bigint;
  v_net bigint; v_expected_fee bigint; v_expected_platform bigint;
begin
  if tg_op='INSERT' then
    if new.status<>'pending' then raise exception 'Une transaction doit commencer en attente.'; end if;
    select s.author_id,c.story_id,c.price_xof,c.is_premium,c.moderation_hidden,s.status
      into v_author,v_story,v_price,v_premium,v_hidden,v_story_status
      from public.chapters c join public.stories s on s.id=c.story_id where c.id=new.chapter_id;
    if not found or v_premium is distinct from true or v_hidden=true or v_story_status<>'published' then raise exception 'Ce chapitre ne peut pas être acheté.'; end if;
    if new.author_id<>v_author or new.story_id<>v_story or new.buyer_id=v_author then raise exception 'Informations d’achat incohérentes.'; end if;
    if new.gross_amount_xof<>v_price then raise exception 'Le prix du chapitre a changé. Actualise la page.'; end if;
    if new.payment_method not in ('MOOV_TG','TMONEY_TG') then raise exception 'Méthode de paiement non prise en charge.'; end if;
    select m.enabled,m.author_share_bps,
      case new.payment_method when 'MOOV_TG' then m.moov_fee_bps when 'TMONEY_TG' then m.tmoney_fee_bps end,
      m.daily_collection_limit_xof,m.weekly_collection_limit_xof,m.monthly_collection_limit_xof
    into v_enabled,v_share_bps,v_fee_bps,v_daily_limit,v_weekly_limit,v_monthly_limit
    from public.novelia_monetization_settings m where m.id=true;
    if coalesce(v_enabled,false)=false then raise exception 'La monétisation est temporairement désactivée.'; end if;
    perform pg_advisory_xact_lock(hashtextextended('novelia_cinetpay_collection_limits',0));
    select coalesce(sum(p.gross_amount_xof),0)::bigint into v_daily_used from public.novelia_chapter_purchases p
    where p.status in ('pending','paid') and p.created_at>=date_trunc('day',now());
    if v_daily_used+new.gross_amount_xof>v_daily_limit then raise exception 'Plafond journalier d’encaissement CinetPay atteint.'; end if;
    select coalesce(sum(p.gross_amount_xof),0)::bigint into v_weekly_used from public.novelia_chapter_purchases p
    where p.status in ('pending','paid') and p.created_at>=date_trunc('week',now());
    if v_weekly_used+new.gross_amount_xof>v_weekly_limit then raise exception 'Plafond hebdomadaire d’encaissement CinetPay atteint.'; end if;
    select coalesce(sum(p.gross_amount_xof),0)::bigint into v_monthly_used from public.novelia_chapter_purchases p
    where p.status in ('pending','paid') and p.created_at>=date_trunc('month',now());
    if v_monthly_used+new.gross_amount_xof>v_monthly_limit then raise exception 'Plafond mensuel d’encaissement CinetPay atteint.'; end if;
    new.author_share_bps:=v_share_bps;new.provider_fee_bps:=v_fee_bps;
    new.provider_fee_xof:=0;new.platform_fee_xof:=0;new.author_earning_xof:=0;new.paid_at:=null;
    return new;
  end if;
  if new.buyer_id<>old.buyer_id or new.author_id<>old.author_id or new.story_id<>old.story_id
     or new.chapter_id<>old.chapter_id or new.gross_amount_xof<>old.gross_amount_xof
     or new.payment_provider<>old.payment_provider or new.payment_method<>old.payment_method
     or new.client_transaction_id<>old.client_transaction_id
     or new.author_share_bps<>old.author_share_bps or new.provider_fee_bps<>old.provider_fee_bps then
    raise exception 'Les informations principales d’un achat sont immuables.';
  end if;
  if old.status in ('failed','refunded') and new.status<>old.status then raise exception 'Cette transaction est terminée et ne peut plus changer de statut.'; end if;
  if old.status='pending' and new.status='paid' then
    if new.provider_transaction_id is null or length(trim(new.provider_transaction_id))=0 or new.notify_token is null or length(trim(new.notify_token))=0 then raise exception 'Référence ou jeton de paiement manquant.'; end if;
    if new.paid_at is null then new.paid_at:=now(); end if;
    if new.provider_fee_xof<0 or new.provider_fee_xof>new.gross_amount_xof then raise exception 'Frais de paiement invalides.'; end if;
    v_expected_fee:=ceil(new.gross_amount_xof*new.provider_fee_bps::numeric/10000)::bigint;
    if new.provider_fee_xof<>v_expected_fee then raise exception 'Frais du prestataire incohérents avec la méthode de paiement.'; end if;
    v_net:=new.gross_amount_xof-new.provider_fee_xof;
    v_expected_platform:=floor(v_net*(10000-new.author_share_bps)::numeric/10000)::bigint;
    if new.platform_fee_xof<>v_expected_platform or new.author_earning_xof<>v_net-v_expected_platform then raise exception 'Répartition des revenus invalide.'; end if;
  elsif old.status='pending' and new.status='failed' then new.author_earning_xof:=0;new.platform_fee_xof:=0;new.provider_fee_xof:=0;new.paid_at:=null;
  elsif old.status='paid' and new.status='refunded' then
    if new.author_earning_xof<>old.author_earning_xof or new.platform_fee_xof<>old.platform_fee_xof or new.provider_fee_xof<>old.provider_fee_xof or new.paid_at<>old.paid_at then raise exception 'Les montants d’une transaction payée ne peuvent pas être modifiés.'; end if;
  elsif new.status<>old.status then raise exception 'Transition de paiement non autorisée.';
  end if;
  new.updated_at:=now();return new;
end;
$$;
revoke all on function private.novelia_validate_chapter_purchase() from public,anon,authenticated;

create or replace view public.novelia_public_monetization_config
with (security_invoker=true,security_barrier=true)
as
select enabled,author_share_bps,minimum_payout_xof,minimum_chapter_price_xof,
       maximum_chapter_price_xof,updated_at,maximum_payout_xof,settlement_hold_days,
       daily_payout_limit_xof,weekly_payout_limit_xof,monthly_payout_limit_xof,
       daily_collection_limit_xof,weekly_collection_limit_xof,monthly_collection_limit_xof
from public.novelia_monetization_settings where id=true;
grant select (daily_collection_limit_xof,weekly_collection_limit_xof,monthly_collection_limit_xof)
on public.novelia_monetization_settings to anon,authenticated;
