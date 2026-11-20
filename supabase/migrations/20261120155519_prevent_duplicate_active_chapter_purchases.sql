drop index if exists public.idx_novelia_paid_chapter_purchase;
create unique index idx_novelia_active_chapter_purchase
on public.novelia_chapter_purchases(buyer_id,chapter_id)
where status in ('pending','paid');
