create or replace function public.novelia_admin_monetization_metrics()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  if not public.novelia_is_admin() then raise exception 'Action réservée aux administrateurs.'; end if;
  select jsonb_build_object(
    'paid_purchases_count',(select count(*) from public.novelia_chapter_purchases where status='paid'),
    'refunded_purchases_count',(select count(*) from public.novelia_chapter_purchases where status='refunded'),
    'gross_collected_xof',(select coalesce(sum(gross_amount_xof),0) from public.novelia_chapter_purchases where status='paid'),
    'gross_refunded_xof',(select coalesce(sum(gross_amount_xof),0) from public.novelia_chapter_purchases where status='refunded'),
    'provider_fees_xof',(select coalesce(sum(provider_fee_xof),0) from public.novelia_chapter_purchases where status in ('paid','refunded')),
    'payout_provider_fees_xof',(select coalesce(sum(provider_fee_xof),0) from public.novelia_payout_requests where status='paid'),
    'platform_revenue_xof',(select coalesce(sum(case when status='paid' then platform_fee_xof when status='refunded' then -platform_fee_xof else 0 end),0) from public.novelia_chapter_purchases where status in ('paid','refunded')),
    'author_earnings_net_xof',(select coalesce(sum(case when status='paid' then author_earning_xof when status='refunded' then -author_earning_xof else 0 end),0) from public.novelia_chapter_purchases where status in ('paid','refunded')),
    'paid_payouts_xof',(select coalesce(sum(amount_xof),0) from public.novelia_payout_requests where status='paid'),
    'pending_payouts_count',(select count(*) from public.novelia_payout_requests where status in ('requested','approved','processing')),
    'pending_payouts_xof',(select coalesce(sum(amount_xof),0) from public.novelia_payout_requests where status in ('requested','approved','processing')),
    'available_author_balance_xof',(select coalesce(sum(available_balance_xof),0) from public.novelia_author_wallet_balances),
    'pending_author_balance_xof',(select coalesce(sum(pending_balance_xof),0) from public.novelia_author_wallet_pending_balances)
  ) into v_result;
  return v_result;
end;
$$;
revoke all on function public.novelia_admin_monetization_metrics() from public,anon;
grant execute on function public.novelia_admin_monetization_metrics() to authenticated;
