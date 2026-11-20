alter table public.notifications drop constraint if exists novelia_notifications_type_check;
alter table public.notifications add constraint novelia_notifications_type_check
check (type = any (array[
  'new_follower','new_chapter','comment_reply','moderation_warning','new_review',
  'new_comment','new_message','contest_award','contest_update','contest_results',
  'chapter_sale','payout_update','purchase_refund','sale_refund','purchase_update'
]::text[]));

create or replace function private.novelia_notify_author_chapter_sale()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_chapter_title text; v_hold_days integer;
begin
  if new.status='paid' and old.status is distinct from 'paid' then
    select title into v_chapter_title from public.chapters where id=new.chapter_id;
    select settlement_hold_days into v_hold_days from public.novelia_monetization_settings where id=true;
    insert into public.notifications(recipient_id,type,story_id,chapter_id,message)
    values(new.author_id,'chapter_sale',new.story_id,new.chapter_id,
      'Ton chapitre « '||coalesce(v_chapter_title,'Chapitre')||' » vient d’être acheté. Ton gain net est de '||
      new.author_earning_xof::text||' XOF. Il sera disponible après le délai de règlement de '||
      coalesce(v_hold_days,7)::text||' jour(s).');
    insert into public.notifications(recipient_id,type,story_id,chapter_id,message)
    values(new.buyer_id,'purchase_update',new.story_id,new.chapter_id,
      'Ton achat du chapitre « '||coalesce(v_chapter_title,'Chapitre')||' » est confirmé. Tu peux maintenant le lire.');
  end if;
  return new;
end;
$$;
revoke all on function private.novelia_notify_author_chapter_sale() from public,anon,authenticated;
