-- Private trigger functions keep SECURITY DEFINER helpers outside the exposed public schema.
create schema if not exists private;
revoke all on schema private from public,anon,authenticated;
create or replace function private.novelia_refresh_contest_entry_totals(p_entry_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_score numeric(4,2); v_reviews integer; v_votes integer;
begin
select coalesce(round(avg((r.originality+r.writing_style+r.coherence+r.theme_respect)::numeric/4),2),0),count(*) into v_score,v_reviews from public.novelia_contest_reviews r where r.entry_id=p_entry_id;
select count(*) into v_votes from public.novelia_contest_votes v where v.entry_id=p_entry_id;
update public.novelia_contest_entries set jury_score=v_score,jury_reviews_count=v_reviews,vote_count=v_votes where id=p_entry_id;
end; $$;
create or replace function private.novelia_contest_review_totals_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin if tg_op='DELETE' then perform private.novelia_refresh_contest_entry_totals(old.entry_id); return old; else perform private.novelia_refresh_contest_entry_totals(new.entry_id); return new; end if; end; $$;
create or replace function private.novelia_contest_vote_totals_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin if tg_op='DELETE' then perform private.novelia_refresh_contest_entry_totals(old.entry_id); return old; else perform private.novelia_refresh_contest_entry_totals(new.entry_id); return new; end if; end; $$;
revoke all on function private.novelia_refresh_contest_entry_totals(uuid) from public,anon,authenticated;
revoke all on function private.novelia_contest_review_totals_trigger() from public,anon,authenticated;
revoke all on function private.novelia_contest_vote_totals_trigger() from public,anon,authenticated;
drop trigger if exists nov_contest_review_totals on public.novelia_contest_reviews;
create trigger nov_contest_review_totals after insert or update or delete on public.novelia_contest_reviews for each row execute function private.novelia_contest_review_totals_trigger();
drop trigger if exists nov_contest_vote_totals on public.novelia_contest_votes;
create trigger nov_contest_vote_totals after insert or update or delete on public.novelia_contest_votes for each row execute function private.novelia_contest_vote_totals_trigger();
drop function if exists public.novelia_refresh_contest_entry_totals(uuid);
drop function if exists public.novelia_contest_review_totals_trigger();
drop function if exists public.novelia_contest_vote_totals_trigger();
