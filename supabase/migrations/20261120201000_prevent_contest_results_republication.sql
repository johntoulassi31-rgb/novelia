-- Publish official contest results only once. Lock the contest row to prevent concurrent duplicate publication.
create or replace function public.novelia_publish_contest_results(p_contest_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  published_count integer;
  contest_status text;
  already_published timestamptz;
begin
  if (select auth.uid()) is null or not exists (
    select 1 from public.app_admins a where a.user_id = (select auth.uid())
  ) then
    raise exception 'Accès réservé aux administrateurs.';
  end if;

  select c.status, c.results_published_at
    into contest_status, already_published
    from public.novelia_contests c
   where c.id = p_contest_id
   for update;

  if not found or contest_status <> 'closed' then
    raise exception 'Le concours doit être clôturé avant la publication.';
  end if;

  if already_published is not null then
    raise exception 'Les résultats de ce concours ont déjà été publiés.';
  end if;

  insert into public.novelia_contest_results
    (entry_id, contest_id, jury_score, jury_reviews_count, vote_count, final_score, published_at)
  select e.id, e.contest_id, coalesce(e.jury_score,0),
         coalesce(e.jury_reviews_count,0), coalesce(e.vote_count,0),
         coalesce(e.final_score,0), now()
    from public.novelia_contest_entries e
   where e.contest_id = p_contest_id and e.status = 'approved';

  get diagnostics published_count = row_count;

  update public.novelia_contests
     set results_published_at = now(), updated_at = now()
   where id = p_contest_id;

  return published_count;
end;
$$;
revoke all on function public.novelia_publish_contest_results(uuid) from public, anon, authenticated;
grant execute on function public.novelia_publish_contest_results(uuid) to authenticated;
