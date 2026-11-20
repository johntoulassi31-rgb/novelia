-- Prevent submissions before the scheduled opening as well as after the deadline.
DROP POLICY IF EXISTS "Authors can submit their published stories" ON public.novelia_contest_entries;
CREATE POLICY "Authors can submit their published stories"
ON public.novelia_contest_entries
FOR INSERT TO authenticated
WITH CHECK (
  author_id = (SELECT auth.uid())
  AND status = 'pending'
  AND EXISTS (
    SELECT 1 FROM public.novelia_contests c
    WHERE c.id = novelia_contest_entries.contest_id
      AND c.status = 'open'
      AND (c.starts_at IS NULL OR c.starts_at <= now())
      AND (c.submissions_close_at IS NULL OR c.submissions_close_at > now())
  )
  AND EXISTS (
    SELECT 1 FROM public.stories s
    WHERE s.id = novelia_contest_entries.story_id
      AND s.author_id = (SELECT auth.uid())
      AND s.status = 'published'
      AND COALESCE(s.moderation_hidden,false) = false
  )
  AND NOT public.novelia_is_suspended()
  AND (
    SELECT count(*) FROM public.novelia_contest_entries e
    WHERE e.contest_id = novelia_contest_entries.contest_id
      AND e.author_id = (SELECT auth.uid())
      AND e.status <> 'withdrawn'
  ) < (
    SELECT c.max_entries_per_user FROM public.novelia_contests c
    WHERE c.id = novelia_contest_entries.contest_id
  )
);