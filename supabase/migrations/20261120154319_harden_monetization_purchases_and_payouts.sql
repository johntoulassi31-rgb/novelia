alter table public.novelia_payout_requests
  add column destination_operator text,
  add column destination_phone_number text,
  add column destination_account_holder text;

update public.novelia_payout_requests r
set destination_operator=d.operator,destination_phone_number=d.phone_number,destination_account_holder=d.account_holder
from public.novelia_payout_destinations d where d.id=r.destination_id;

alter table public.novelia_payout_requests
  alter column destination_operator set not null,
  alter column destination_phone_number set not null,
  alter column destination_account_holder set not null;

create unique index idx_novelia_one_default_payout_destination
on public.novelia_payout_destinations(author_id) where is_default=true;

create function private.novelia_validate_chapter_purchase()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_author uuid; v_story uuid; v_price integer; v_premium boolean; v_hidden boolean;
  v_story_status text; v_enabled boolean; v_share_bps integer; v_fee_bps integer;
  v_net bigint; v_expected_platform bigint;
begin
  if tg_op='INSERT' then
    if new.status<>'pending' then raise exception 'Une transaction doit commencer en attente.'; end if;
    select s.author_id,c.story_id,c.price_xof,c.is_premium,c.moderation_hidden,s.status
      into v_author,v_story,v_price,v_premium,v_hidden,v_story_status
      from public.chapters c join public.stories s on s.id=c.story_id where c.id=new.chapter_id;
    if not found or v_premium is distinct from true or v_hidden=true or v_story_status<>'published' then
      raise exception 'Ce chapitre ne peut pas être acheté.';
    end if;
    if new.author_id<>v_author or new.story_id<>v_story or new.buyer_id=v_author then
      raise exception 'Informations d’achat incohérentes.';
    end if;
    if new.gross_amount_xof<>v_price then raise exception 'Le prix du chapitre a changé. Actualise la page.'; end if;
    select m.enabled,m.author_share_bps into v_enabled,v_share_bps
      from public.novelia_monetization_settings m where m.id=true;
    if coalesce(v_enabled,false)=false then raise exception 'La monétisation est temporairement désactivée.'; end if;
    new.author_share_bps:=v_share_bps;
    new.provider_fee_xof:=0; new.platform_fee_xof:=0; new.author_earning_xof:=0; new.paid_at:=null;
    return new;
  end if;
  if new.buyer_id<>old.buyer_id or new.author_id<>old.author_id or new.story_id<>old.story_id
     or new.chapter_id<>old.chapter_id or new.gross_amount_xof<>old.gross_amount_xof
     or new.payment_provider<>old.payment_provider or new.client_transaction_id<>old.client_transaction_id
     or new.author_share_bps<>old.author_share_bps then
    raise exception 'Les informations principales d’un achat sont immuables.';
  end if;
  if old.status in ('failed','refunded') and new.status<>old.status then
    raise exception 'Cette transaction est terminée et ne peut plus changer de statut.';
  end if;
  if old.status='pending' and new.status='paid' then
    if new.provider_transaction_id is null or length(trim(new.provider_transaction_id))=0
       or new.notify_token is null or length(trim(new.notify_token))=0 then
      raise exception 'Référence ou jeton de paiement manquant.';
    end if;
    if new.paid_at is null then new.paid_at:=now(); end if;
    if new.provider_fee_xof<0 or new.provider_fee_xof>new.gross_amount_xof then raise exception 'Frais de paiement invalides.'; end if;
    v_net:=new.gross_amount_xof-new.provider_fee_xof;
    v_expected_platform:=floor(v_net*(10000-new.author_share_bps)::numeric/10000)::bigint;
    if new.platform_fee_xof<>v_expected_platform or new.author_earning_xof<>v_net-v_expected_platform then
      raise exception 'Répartition des revenus invalide.';
    end if;
  elsif old.status='pending' and new.status='failed' then
    new.author_earning_xof:=0; new.platform_fee_xof:=0; new.provider_fee_xof:=0; new.paid_at:=null;
  elsif old.status='paid' and new.status='refunded' then
    if new.author_earning_xof<>old.author_earning_xof or new.platform_fee_xof<>old.platform_fee_xof
       or new.provider_fee_xof<>old.provider_fee_xof or new.paid_at<>old.paid_at then
      raise exception 'Les montants d’une transaction payée ne peuvent pas être modifiés.';
    end if;
  elsif new.status<>old.status then raise exception 'Transition de paiement non autorisée.';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function private.novelia_validate_chapter_purchase() from public,anon,authenticated;
create trigger nov_validate_chapter_purchase before insert or update on public.novelia_chapter_purchases
for each row execute function private.novelia_validate_chapter_purchase();

create function private.novelia_validate_payout_transition()
returns trigger language plpgsql set search_path='' as $$
begin
  if new.author_id<>old.author_id or new.destination_id<>old.destination_id
     or new.destination_operator<>old.destination_operator or new.destination_phone_number<>old.destination_phone_number
     or new.destination_account_holder<>old.destination_account_holder or new.amount_xof<>old.amount_xof then
    raise exception 'Les informations d’une demande de retrait sont immuables.';
  end if;
  if old.status in ('paid','failed','cancelled') and new.status<>old.status then
    raise exception 'Cette demande de retrait est terminée.';
  end if;
  if old.status='requested' and new.status not in ('requested','approved','processing','failed','cancelled') then
    raise exception 'Transition de retrait invalide.';
  elsif old.status='approved' and new.status not in ('approved','processing','failed','cancelled') then
    raise exception 'Transition de retrait invalide.';
  elsif old.status='processing' and new.status not in ('processing','paid','failed') then
    raise exception 'Transition de retrait invalide.';
  end if;
  if new.status='paid' then
    if new.provider_transaction_id is null or length(trim(new.provider_transaction_id))=0 then
      raise exception 'Référence du transfert manquante.';
    end if;
    new.processed_at:=coalesce(new.processed_at,now());
  end if;
  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function private.novelia_validate_payout_transition() from public,anon,authenticated;
create trigger nov_validate_payout_transition before update on public.novelia_payout_requests
for each row execute function private.novelia_validate_payout_transition();

create or replace function public.novelia_request_payout(p_destination_id uuid,p_amount_xof bigint)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_user uuid := (select auth.uid()); v_request_id uuid; v_balance bigint;
  v_minimum bigint; v_enabled boolean; v_operator text; v_phone text; v_holder text;
begin
  if v_user is null then raise exception 'Connecte-toi pour demander un retrait.'; end if;
  if public.novelia_is_suspended() then raise exception 'Ton compte ne peut pas effectuer de retrait actuellement.'; end if;
  if p_amount_xof is null or p_amount_xof<=0 then raise exception 'Montant de retrait invalide.'; end if;
  select enabled,minimum_payout_xof into v_enabled,v_minimum from public.novelia_monetization_settings where id=true;
  if coalesce(v_enabled,false)=false then raise exception 'Les retraits ne sont pas encore activés.'; end if;
  if p_amount_xof<v_minimum then raise exception 'Le montant est inférieur au minimum de retrait.'; end if;
  select d.operator,d.phone_number,d.account_holder into v_operator,v_phone,v_holder
  from public.novelia_payout_destinations d where d.id=p_destination_id and d.author_id=v_user;
  if not found then raise exception 'Moyen de paiement introuvable.'; end if;
  insert into public.novelia_author_wallets(author_id) values(v_user) on conflict(author_id) do nothing;
  perform 1 from public.novelia_author_wallets w where w.author_id=v_user for update;
  select coalesce(sum(l.amount_xof),0)::bigint into v_balance
  from public.novelia_author_wallet_ledger l where l.author_id=v_user;
  if p_amount_xof>v_balance then raise exception 'Solde disponible insuffisant.'; end if;
  insert into public.novelia_payout_requests(author_id,destination_id,destination_operator,destination_phone_number,destination_account_holder,amount_xof)
  values(v_user,p_destination_id,v_operator,v_phone,v_holder,p_amount_xof) returning id into v_request_id;
  insert into public.novelia_author_wallet_ledger(author_id,amount_xof,entry_type,payout_request_id,description,idempotency_key)
  values(v_user,-p_amount_xof,'payout_hold',v_request_id,'Montant réservé pour une demande de retrait','payout_hold:'||v_request_id::text);
  return v_request_id;
end;
$$;
revoke all on function public.novelia_request_payout(uuid,bigint) from public,anon;
grant execute on function public.novelia_request_payout(uuid,bigint) to authenticated;
