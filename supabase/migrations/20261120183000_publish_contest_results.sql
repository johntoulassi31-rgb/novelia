alter table public.novelia_contests add column if not exists results_published_at timestamptz;

create table if not exists public.novelia_contest_results (
  entry_id uuid primary key references public.novelia_contest_entries(id) on delete cascade,
  contest_id uuid not null references public.novelia_contests(id) on delete cascade,
  jury_score numeric(5,2) not null default 0,
  jury_reviews_count integer not null default 0,
  vote_count integer not null default 0,
  final_score numeric(5,2) not null default 0,
  published_at timestamptz not null default now()
);
create index if not exists idx_novelia_contest_results_contest_rank
  on public.novelia_contest_results(contest_id, final_score desc, published_at asc);
alter table public.novelia_contest_results enable row level security;
revoke all on public.novelia_contest_results from public, anon, authenticated;
grant select on public.novelia_contest_results to anon, authenticated;
drop policy if exists "Public view published contest results" on public.novelia_contest_results;
create policy "Public view published contest results" on public.novelia_contest_results
for select to anon, authenticated
using (exists (select 1 from public.novelia_contests c where c.id=contest_id and c.results_published_at is not null));
revoke select (jury_score, jury_reviews_count, vote_count, final_score) on public.novelia_contest_entries from anon, authenticated;

create or replace function public.novelia_publish_contest_results(p_contest_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare published_count integer;
begin
  if (select auth.uid()) is null or not exists (select 1 from public.app_admins a where a.user_id=(select auth.uid())) then
    raise exception 'Accès réservé aux administrateurs.';
  end if;
  if not exists (select 1 from public.novelia_contests c where c.id=p_contest_id and c.status='closed') then
    raise exception 'Le concours doit être clôturé avant la publication.';
  end if;
  insert into public.novelia_contest_results(entry_id,contest_id,jury_score,jury_reviews_count,vote_count,final_score,published_at)
  select e.id,e.contest_id,coalesce(e.jury_score,0),coalesce(e.jury_reviews_count,0),coalesce(e.vote_count,0),coalesce(e.final_score,0),now()
  from public.novelia_contest_entries e where e.contest_id=p_contest_id and e.status='approved'
  on conflict(entry_id) do update set jury_score=excluded.jury_score,jury_reviews_count=excluded.jury_reviews_count,vote_count=excluded.vote_count,final_score=excluded.final_score,published_at=now();
  get diagnostics published_count=row_count;
  update public.novelia_contests set results_published_at=now(),updated_at=now() where id=p_contest_id;
  return published_count;
end; $$;
revoke all on function public.novelia_publish_contest_results(uuid) from public,anon,authenticated;
grant execute on function public.novelia_publish_contest_results(uuid) to authenticated;
