alter table public.novelia_chapter_purchases
  add column provider_fee_bps integer not null default 250 check (provider_fee_bps between 0 and 2000);

create or replace function private.novelia_validate_chapter_purchase()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_author uuid; v_story uuid; v_price integer; v_premium boolean; v_hidden boolean;
  v_story_status text; v_enabled boolean; v_share_bps integer; v_fee_bps integer;
  v_net bigint; v_expected_fee bigint; v_expected_platform bigint;
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
    if new.payment_method='MOOV_TG' then
      select m.moov_fee_bps into v_fee_bps from public.novelia_monetization_settings m where m.id=true;
    elsif new.payment_method='TMONEY_TG' then
      select m.tmoney_fee_bps into v_fee_bps from public.novelia_monetization_settings m where m.id=true;
    else raise exception 'Méthode de paiement non prise en charge.';
    end if;
    new.author_share_bps:=v_share_bps;
    new.provider_fee_bps:=v_fee_bps;
    new.provider_fee_xof:=0; new.platform_fee_xof:=0; new.author_earning_xof:=0; new.paid_at:=null;
    return new;
  end if;
  if new.buyer_id<>old.buyer_id or new.author_id<>old.author_id or new.story_id<>old.story_id
     or new.chapter_id<>old.chapter_id or new.gross_amount_xof<>old.gross_amount_xof
     or new.payment_provider<>old.payment_provider or new.payment_method<>old.payment_method
     or new.client_transaction_id<>old.client_transaction_id or new.author_share_bps<>old.author_share_bps or new.provider_fee_bps<>old.provider_fee_bps then
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
    v_expected_fee:=ceil(new.gross_amount_xof*new.provider_fee_bps::numeric/10000)::bigint;
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
