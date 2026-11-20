alter table public.novelia_payout_requests
  add column provider_fee_xof bigint not null default 0 check (provider_fee_xof >= 0);
grant select (provider_fee_xof) on public.novelia_payout_requests to authenticated;
