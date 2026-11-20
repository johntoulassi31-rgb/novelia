-- Contest awards and automatic winner profile badges. Applied on 2026-11-20.
alter table public.novelia_badge_catalog drop constraint if exists novelia_badge_catalog_category_check;
alter table public.novelia_badge_catalog add constraint novelia_badge_catalog_category_check check(category in ('auteur','lecteur','communaute','concours'));
insert into public.novelia_badge_catalog(id,name,description,icon,category,threshold) values
('concours_grand_prix','Grand Prix Novelia','Lauréat du Grand Prix d’un concours littéraire Novelia.','🏆','concours',1),
('concours_prix_jury','Prix du jury','Œuvre distinguée par le jury littéraire Novelia.','⚖️','concours',1),
('concours_prix_public','Prix du public','Œuvre préférée des lecteurs lors d’un concours Novelia.','❤️','concours',1),
('concours_coup_de_coeur','Coup de cœur du jury','Œuvre remarquée par le jury pour sa singularité.','✨','concours',1)
on conflict(id) do nothing;
create table if not exists public.novelia_contest_awards(id uuid primary key default gen_random_uuid(),contest_id uuid not null references public.novelia_contests(id) on delete cascade,entry_id uuid not null references public.novelia_contest_entries(id) on delete cascade,author_id uuid not null references auth.users(id) on delete cascade,award_type text not null check(award_type in ('grand_prix','prix_jury','prix_public','coup_de_coeur')),prize_description text not null default '' check(char_length(prize_description)<=1200),awarded_by uuid references auth.users(id) on delete set null,awarded_at timestamptz not null default now(),unique(contest_id,award_type),unique(contest_id,entry_id,award_type),constraint contest_award_author_matches_entry check(author_id is not null));
create index if not exists idx_novelia_contest_awards_author on public.novelia_contest_awards(author_id,awarded_at desc);
create index if not exists idx_novelia_contest_awards_entry on public.novelia_contest_awards(entry_id);
alter table public.novelia_contest_awards enable row level security;
grant select on public.novelia_contest_awards to anon,authenticated;
grant insert,delete on public.novelia_contest_awards to authenticated;
create policy "Public can view contest awards" on public.novelia_contest_awards for select to anon,authenticated using(true);
create policy "Admins award contest winners" on public.novelia_contest_awards for insert to authenticated with check(public.novelia_is_admin() and exists(select 1 from public.novelia_contests c where c.id=contest_id and c.status='closed') and exists(select 1 from public.novelia_contest_entries e where e.id=entry_id and e.contest_id=contest_id and e.author_id=author_id and e.status='approved'));
create policy "Admins revoke contest awards" on public.novelia_contest_awards for delete to authenticated using(public.novelia_is_admin());
create or replace function private.novelia_contest_award_badge_trigger() returns trigger language plpgsql security definer set search_path='' as $$
declare v_badge text;
begin
if tg_op='DELETE' then
 v_badge:=case old.award_type when 'grand_prix' then 'concours_grand_prix' when 'prix_jury' then 'concours_prix_jury' when 'prix_public' then 'concours_prix_public' when 'coup_de_coeur' then 'concours_coup_de_coeur' end;
 if not exists(select 1 from public.novelia_contest_awards a where a.author_id=old.author_id and a.award_type=old.award_type) then delete from public.novelia_user_badges where user_id=old.author_id and badge_id=v_badge; end if;
 return old;
else
 v_badge:=case new.award_type when 'grand_prix' then 'concours_grand_prix' when 'prix_jury' then 'concours_prix_jury' when 'prix_public' then 'concours_prix_public' when 'coup_de_coeur' then 'concours_coup_de_coeur' end;
 insert into public.novelia_user_badges(user_id,badge_id) values(new.author_id,v_badge) on conflict(user_id,badge_id) do nothing;
 return new;
end if;
end; $$;
revoke all on function private.novelia_contest_award_badge_trigger() from public,anon,authenticated;
drop trigger if exists nov_contest_award_badge on public.novelia_contest_awards;
create trigger nov_contest_award_badge after insert or delete on public.novelia_contest_awards for each row execute function private.novelia_contest_award_badge_trigger();
