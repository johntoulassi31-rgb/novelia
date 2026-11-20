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
  perform pg_advisory_xact_lock(hashtextextended('novelia_cinetpay_payout_limits',0));
  select coalesce(sum(r.amount_xof),0)::bigint into v_daily_used from public.novelia_payout_requests r
  where r.status in ('requested','approved','processing','paid') and r.created_at>=date_trunc('day',now());
  if v_daily_used+p_amount_xof>v_daily_limit then raise exception 'Plafond journalier global de retrait CinetPay atteint.'; end if;
  select coalesce(sum(r.amount_xof),0)::bigint into v_weekly_used from public.novelia_payout_requests r
  where r.status in ('requested','approved','processing','paid') and r.created_at>=date_trunc('week',now());
  if v_weekly_used+p_amount_xof>v_weekly_limit then raise exception 'Plafond hebdomadaire global de retrait CinetPay atteint.'; end if;
  select coalesce(sum(r.amount_xof),0)::bigint into v_monthly_used from public.novelia_payout_requests r
  where r.status in ('requested','approved','processing','paid') and r.created_at>=date_trunc('month',now());
  if v_monthly_used+p_amount_xof>v_monthly_limit then raise exception 'Plafond mensuel global de retrait CinetPay atteint.'; end if;
  insert into public.novelia_payout_requests(author_id,destination_id,destination_operator,destination_phone_number,destination_account_holder,amount_xof)
  values(v_user,p_destination_id,v_operator,v_phone,v_holder,p_amount_xof) returning id into v_request_id;
  insert into public.novelia_author_wallet_ledger(author_id,amount_xof,entry_type,payout_request_id,description,idempotency_key)
  values(v_user,-p_amount_xof,'payout_hold',v_request_id,'Montant réservé pour une demande de retrait','payout_hold:'||v_request_id::text);
  return v_request_id;
end;
$$;
revoke all on function public.novelia_request_payout(uuid,bigint) from public,anon;
grant execute on function public.novelia_request_payout(uuid,bigint) to authenticated;
