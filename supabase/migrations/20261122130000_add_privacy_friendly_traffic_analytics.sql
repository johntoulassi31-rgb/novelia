create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.novelia_traffic_events (
  id bigint generated always as identity primary key,
  visitor_id uuid not null,
  session_id uuid not null,
  user_id uuid references auth.users(id) on delete set null,
  page_path text not null check (length(page_path) between 1 and 200),
  source text not null default 'direct' check (source in ('direct','search','social','referral','internal','unknown')),
  referrer_host text,
  visited_at timestamptz not null default now()
);
alter table private.novelia_traffic_events enable row level security;
revoke all on private.novelia_traffic_events from public, anon, authenticated;
grant usage on schema private to anon, authenticated;
grant insert on private.novelia_traffic_events to anon, authenticated;
drop policy if exists "Allow privacy-safe traffic events" on private.novelia_traffic_events;
create policy "Allow privacy-safe traffic events" on private.novelia_traffic_events
  for insert to anon, authenticated
  with check (user_id is not distinct from (select auth.uid()));
create index if not exists nov_traffic_visited_at_idx on private.novelia_traffic_events (visited_at desc);
create index if not exists nov_traffic_visitor_idx on private.novelia_traffic_events (visitor_id, visited_at desc);
create index if not exists nov_traffic_session_idx on private.novelia_traffic_events (session_id, visited_at desc);
create index if not exists nov_traffic_user_idx on private.novelia_traffic_events (user_id, visited_at desc);

create or replace function public.novelia_track_visit(
  p_visitor_id uuid, p_session_id uuid, p_page_path text,
  p_source text default 'direct', p_referrer_host text default null
) returns void
language plpgsql security invoker set search_path = ''
as $$
declare
  safe_path text;
  safe_source text;
  safe_host text;
begin
  if p_visitor_id is null or p_session_id is null then return; end if;
  safe_path := left(coalesce(nullif(p_page_path, ''), '/'), 200);
  if safe_path !~ '^/[A-Za-z0-9._/-]*$' or safe_path like '%..%' then safe_path := '/'; end if;
  safe_source := case when p_source in ('direct','search','social','referral','internal') then p_source else 'unknown' end;
  safe_host := left(regexp_replace(coalesce(p_referrer_host, ''), '[^A-Za-z0-9.-]', '', 'g'), 120);
  if safe_host = '' then safe_host := null; end if;
  insert into private.novelia_traffic_events
    (visitor_id, session_id, user_id, page_path, source, referrer_host)
  values (p_visitor_id, p_session_id, (select auth.uid()), safe_path, safe_source, safe_host);
end;
$$;
revoke all on function public.novelia_track_visit(uuid,uuid,text,text,text) from public;
grant execute on function public.novelia_track_visit(uuid,uuid,text,text,text) to anon, authenticated;

create or replace function public.novelia_admin_traffic_stats(p_days integer default 30)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  result jsonb;
  days_back integer := greatest(7, least(coalesce(p_days,30), 90));
begin
  if not exists (
    select 1 from public.app_admins a where a.user_id = (select auth.uid())
  ) then
    raise exception 'Action réservée aux administrateurs Novelia.' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'generated_at', now(),
    'period_days', days_back,
    'visitors_total', (select count(distinct visitor_id) from private.novelia_traffic_events),
    'visitors_7d', (select count(distinct visitor_id) from private.novelia_traffic_events where visited_at >= now() - interval '7 days'),
    'visitors_30d', (select count(distinct visitor_id) from private.novelia_traffic_events where visited_at >= now() - interval '30 days'),
    'sessions_7d', (select count(distinct session_id) from private.novelia_traffic_events where visited_at >= now() - interval '7 days'),
    'pageviews_7d', (select count(*) from private.novelia_traffic_events where visited_at >= now() - interval '7 days'),
    'pageviews_30d', (select count(*) from private.novelia_traffic_events where visited_at >= now() - interval '30 days'),
    'identified_visitors', (select count(distinct visitor_id) from private.novelia_traffic_events where user_id is not null),
    'daily_visitors', (
      select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'count', d.n) order by d.day), '[]'::jsonb)
      from (
        select gs.d::date as day,
          (select count(distinct e.visitor_id) from private.novelia_traffic_events e
           where e.visited_at >= gs.d and e.visited_at < gs.d + interval '1 day') as n
        from generate_series(current_date - (days_back - 1), current_date, interval '1 day') as gs(d)
      ) d
    ),
    'top_pages', (
      select coalesce(jsonb_agg(jsonb_build_object('path', p.page_path, 'views', p.views, 'visitors', p.visitors) order by p.views desc), '[]'::jsonb)
      from (
        select page_path, count(*) as views, count(distinct visitor_id) as visitors
        from private.novelia_traffic_events
        where visited_at >= now() - make_interval(days => days_back)
        group by page_path order by count(*) desc limit 8
      ) p
    ),
    'sources', (
      select coalesce(jsonb_agg(jsonb_build_object('source', s.source, 'visitors', s.visitors) order by s.visitors desc), '[]'::jsonb)
      from (
        select source, count(distinct visitor_id) as visitors
        from private.novelia_traffic_events
        where visited_at >= now() - make_interval(days => days_back)
        group by source
      ) s
    ),
    'signed_up_visitors', (select count(distinct visitor_id) from private.novelia_traffic_events where user_id is not null)
  ) into result;
  return result;
end;
$$;
revoke all on function public.novelia_admin_traffic_stats(integer) from public, anon;
grant execute on function public.novelia_admin_traffic_stats(integer) to authenticated;
