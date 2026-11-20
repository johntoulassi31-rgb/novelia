-- Novelia literary contests. Applied in production on 2026-11-20.
create table if not exists public.novelia_contests (
id uuid primary key default gen_random_uuid(), title text not null check(char_length(btrim(title)) between 3 and 120),
slug text not null unique check(slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'), theme text not null check(char_length(btrim(theme)) between 3 and 160),
description text not null default '' check(char_length(description)<=5000), category text not null default 'general' check(category in ('romance','fantasy','thriller','science_fiction','webtoon','general')),
rules jsonb not null default '[]'::jsonb check(jsonb_typeof(rules)='array'), starts_at timestamptz, submissions_close_at timestamptz, voting_starts_at timestamptz, voting_ends_at timestamptz, ends_at timestamptz,
status text not null default 'draft' check(status in ('draft','open','voting','closed')), max_entries_per_user integer not null default 1 check(max_entries_per_user between 1 and 5),
created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
constraint novelia_contest_dates_valid check((submissions_close_at is null or starts_at is null or submissions_close_at>=starts_at) and (voting_starts_at is null or submissions_close_at is null or voting_starts_at>=submissions_close_at) and (voting_ends_at is null or voting_starts_at is null or voting_ends_at>=voting_starts_at) and (ends_at is null or voting_ends_at is null or ends_at>=voting_ends_at)));
create table if not exists public.novelia_contest_entries (
id uuid primary key default gen_random_uuid(), contest_id uuid not null references public.novelia_contests(id) on delete cascade, author_id uuid not null references auth.users(id) on delete cascade,
story_id uuid not null references public.stories(id) on delete cascade, pitch text not null default '' check(char_length(pitch)<=1000), excerpt text not null default '' check(char_length(excerpt)<=5000),
status text not null default 'pending' check(status in ('pending','approved','rejected','withdrawn')), submitted_at timestamptz not null default now(), reviewed_at timestamptz, unique(contest_id,story_id));
create table if not exists public.novelia_contest_votes (
id uuid primary key default gen_random_uuid(), contest_id uuid not null references public.novelia_contests(id) on delete cascade, entry_id uuid not null references public.novelia_contest_entries(id) on delete cascade,
voter_id uuid not null references auth.users(id) on delete cascade, created_at timestamptz not null default now(), unique(contest_id,voter_id));
create index if not exists idx_novelia_contests_status_dates on public.novelia_contests(status,starts_at,submissions_close_at);
create index if not exists idx_novelia_contests_created_by on public.novelia_contests(created_by);
create index if not exists idx_novelia_contest_entries_contest_status on public.novelia_contest_entries(contest_id,status,submitted_at desc);
create index if not exists idx_novelia_contest_entries_author on public.novelia_contest_entries(author_id,submitted_at desc);
create index if not exists idx_novelia_contest_entries_story_id on public.novelia_contest_entries(story_id);
create index if not exists idx_novelia_contest_votes_entry on public.novelia_contest_votes(entry_id);
create index if not exists idx_novelia_contest_votes_voter_id on public.novelia_contest_votes(voter_id);
alter table public.novelia_contests enable row level security; alter table public.novelia_contest_entries enable row level security; alter table public.novelia_contest_votes enable row level security;
revoke all privileges on table public.novelia_contests,public.novelia_contest_entries,public.novelia_contest_votes from anon,authenticated; grant select on public.novelia_contests,public.novelia_contest_entries to anon,authenticated; grant insert on public.novelia_contest_entries to authenticated; grant select,insert on public.novelia_contest_votes to authenticated;
create policy "Public can view published Novelia contests" on public.novelia_contests for select to anon,authenticated using(status in ('open','voting','closed'));
create policy "Authors can view approved contest entries" on public.novelia_contest_entries for select to anon,authenticated using(status='approved' or author_id=(select auth.uid()));
create policy "Authors can submit their published stories" on public.novelia_contest_entries for insert to authenticated with check(author_id=(select auth.uid()) and status='pending' and exists(select 1 from public.novelia_contests c where c.id=contest_id and c.status='open' and (c.submissions_close_at is null or c.submissions_close_at>now())) and exists(select 1 from public.stories s where s.id=story_id and s.author_id=(select auth.uid()) and s.status='published' and coalesce(s.moderation_hidden,false)=false) and not public.novelia_is_suspended() and (select count(*) from public.novelia_contest_entries e where e.contest_id=novelia_contest_entries.contest_id and e.author_id=(select auth.uid()) and e.status<>'withdrawn')<(select c.max_entries_per_user from public.novelia_contests c where c.id=contest_id));
create policy "Users can view their own contest votes" on public.novelia_contest_votes for select to authenticated using(voter_id=(select auth.uid()));
create policy "Users can vote once in active contests" on public.novelia_contest_votes for insert to authenticated with check(voter_id=(select auth.uid()) and not public.novelia_is_suspended() and exists(select 1 from public.novelia_contests c join public.novelia_contest_entries e on e.contest_id=c.id where c.id=contest_id and e.id=entry_id and c.status='voting' and e.status='approved' and e.author_id<>(select auth.uid()) and (c.voting_starts_at is null or c.voting_starts_at<=now()) and (c.voting_ends_at is null or c.voting_ends_at>now())));
