drop policy if exists "Read visible chapters of accessible stories" on public.chapters;
create policy "Public readers access free or purchased chapters"
on public.chapters for select to anon,authenticated
using (
  moderation_hidden=false
  and exists (
    select 1 from public.stories s
    where s.id=chapters.story_id and s.status='published' and s.moderation_hidden=false
  )
  and (
    coalesce(is_premium,false)=false
    or exists (
      select 1 from public.novelia_chapter_purchases p
      where p.chapter_id=chapters.id
        and p.buyer_id=(select auth.uid())
        and p.status='paid'
    )
  )
);
create policy "Authors and admins access their chapters"
on public.chapters for select to authenticated
using (
  exists (select 1 from public.stories s where s.id=chapters.story_id and s.author_id=(select auth.uid()))
  or public.novelia_is_admin()
);
