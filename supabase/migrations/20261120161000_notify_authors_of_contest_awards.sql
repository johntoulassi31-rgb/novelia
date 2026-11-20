-- Notify authors automatically when a contest award is granted.
alter table public.notifications drop constraint if exists novelia_notifications_type_check;
alter table public.notifications add constraint novelia_notifications_type_check check(type in ('new_follower','new_chapter','comment_reply','moderation_warning','new_review','new_comment','new_message','contest_award'));
create or replace function private.novelia_contest_award_notification_trigger()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_title text; v_label text; v_story uuid;
begin
select s.title,e.story_id into v_title,v_story from public.novelia_contest_entries e join public.stories s on s.id=e.story_id where e.id=new.entry_id;
v_label:=case new.award_type when 'grand_prix' then 'Grand Prix Novelia' when 'prix_jury' then 'Prix du jury' when 'prix_public' then 'Prix du public' when 'coup_de_coeur' then 'Coup de cœur du jury' end;
insert into public.notifications(recipient_id,actor_id,type,story_id,message) values(new.author_id,new.awarded_by,'contest_award',v_story,'Félicitations ! « '||coalesce(v_title,'ton œuvre')||' » reçoit la distinction « '||v_label||' » lors d’un concours Novelia.');
return new;
end; $$;
revoke all on function private.novelia_contest_award_notification_trigger() from public,anon,authenticated;
drop trigger if exists nov_contest_award_notification on public.novelia_contest_awards;
create trigger nov_contest_award_notification after insert on public.novelia_contest_awards for each row execute function private.novelia_contest_award_notification_trigger();
