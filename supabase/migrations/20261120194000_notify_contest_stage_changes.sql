-- Notify approved contest participants when judging, voting, closure, or official results are announced.
alter table public.notifications
  add column if not exists contest_id uuid references public.novelia_contests(id) on delete set null;

alter table public.notifications drop constraint if exists novelia_notifications_type_check;
alter table public.notifications add constraint novelia_notifications_type_check
  check (type = any (array[
    'new_follower','new_chapter','comment_reply','moderation_warning',
    'new_review','new_comment','new_message','contest_award',
    'contest_update','contest_results'
  ]));

create or replace function private.novelia_notify_contest_stage_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_message text;
begin
  if new.results_published_at is distinct from old.results_published_at
     and new.results_published_at is not null then
    v_type := 'contest_results';
    v_message := 'Les résultats officiels du concours « ' || new.title || ' » sont publiés. Consulte le classement et les distinctions.';
  elsif new.status is distinct from old.status then
    if new.status = 'judging' then
      v_type := 'contest_update';
      v_message := 'Les candidatures du concours « ' || new.title || ' » sont closes. Le jury commence son évaluation.';
    elsif new.status = 'voting' then
      v_type := 'contest_update';
      v_message := 'La phase de vote du concours « ' || new.title || ' » est ouverte. Découvre les œuvres sélectionnées.';
    elsif new.status = 'closed' then
      v_type := 'contest_update';
      v_message := 'Le concours « ' || new.title || ' » est terminé. Les résultats seront annoncés après leur publication officielle.';
    else
      return new;
    end if;
  else
    return new;
  end if;

  insert into public.notifications(recipient_id, type, contest_id, message)
  select distinct e.author_id, v_type, new.id, v_message
  from public.novelia_contest_entries e
  where e.contest_id = new.id
    and e.status = 'approved'
    and e.author_id is not null;

  return new;
end;
$$;

revoke all on function private.novelia_notify_contest_stage_change() from public, anon, authenticated;

drop trigger if exists nov_contest_stage_notifications on public.novelia_contests;
create trigger nov_contest_stage_notifications
after update of status, results_published_at on public.novelia_contests
for each row execute function private.novelia_notify_contest_stage_change();

create index if not exists idx_notifications_contest_id on public.notifications(contest_id) where contest_id is not null;
