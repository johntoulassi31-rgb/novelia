alter table public.novelia_monetization_settings
  add column moov_fee_bps integer not null default 250 check (moov_fee_bps between 0 and 2000),
  add column tmoney_fee_bps integer not null default 300 check (tmoney_fee_bps between 0 and 2000);

alter table public.novelia_chapter_purchases
  add column payment_method text not null default 'MOOV_TG'
    check (payment_method in ('MOOV_TG','TMONEY_TG')),
  add column notify_token text;

revoke select on public.novelia_chapter_purchases from authenticated;
grant select (id,buyer_id,story_id,chapter_id,status,gross_amount_xof,created_at,paid_at,updated_at,client_transaction_id)
on public.novelia_chapter_purchases to authenticated;
