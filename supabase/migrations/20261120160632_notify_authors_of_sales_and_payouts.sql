alter table public.notifications drop constraint if exists novelia_notifications_type_check;
alter table public.notifications add constraint novelia_notifications_type_check
check (type = any (array[
  'new_follower','new_chapter','comment_reply','moderation_warning','new_review',
  'new_comment','new_message','contest_award','contest_update','contest_results',
  'chapter_sale','payout_update'
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
  end if;
  return new;
end;
$$;
revoke all on function private.novelia_notify_author_chapter_sale() from public,anon,authenticated;
create trigger nov_notify_author_chapter_sale after update of status on public.novelia_chapter_purchases
for each row execute function private.novelia_notify_author_chapter_sale();

create or replace function private.novelia_notify_author_payout_status()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_message text;
begin
  if tg_op='INSERT' then
    v_message:='Ta demande de retrait de '||new.amount_xof::text||' XOF a bien été reçue.';
    insert into public.notifications(recipient_id,type,message) values(new.author_id,'payout_update',v_message);
    return new;
  end if;
  if new.status is distinct from old.status then
    v_message:=case new.status
      when 'approved' then 'Ta demande de retrait de '||new.amount_xof::text||' XOF a été approuvée.'
      when 'processing' then 'Ton retrait de '||new.amount_xof::text||' XOF est en cours de transfert.'
      when 'paid' then 'Ton retrait de '||new.amount_xof::text||' XOF a été confirmé par CinetPay.'
      when 'failed' then 'Le transfert de '||new.amount_xof::text||' XOF a échoué. Le montant a été libéré sur ton solde.'
      when 'cancelled' then 'Ta demande de retrait de '||new.amount_xof::text||' XOF a été annulée et le montant libéré.'
      else null end;
    if v_message is not null then
      insert into public.notifications(recipient_id,type,message) values(new.author_id,'payout_update',v_message);
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.novelia_notify_author_payout_status() from public,anon,authenticated;
create trigger nov_notify_author_payout_status after insert or update of status on public.novelia_payout_requests
for each row execute function private.novelia_notify_author_payout_status();
