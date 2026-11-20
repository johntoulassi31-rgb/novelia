revoke select on public.novelia_chapter_catalog from anon,authenticated;
grant select (id,story_id,title,chapter_number,created_at,is_premium,price_xof)
on public.novelia_chapter_catalog to anon,authenticated;
