alter table public.novelia_chapter_purchases
  add column refund_reference text,
  add column refund_reason text,
  add column refunded_at timestamptz;

create function private.novelia_validate_purchase_refund_fields()
returns trigger language plpgsql set search_path='' as $$
begin
  if new.status='refunded' and old.status='paid' then
    if new.refund_reference is null or length(trim(new.refund_reference))<3 or length(trim(new.refund_reference))>120 then
      raise exception 'Référence de remboursement obligatoire.';
    end if;
    if new.refunded_at is null then new.refunded_at:=now(); end if;
    if new.refund_reason is not null and length(new.refund_reason)>500 then raise exception 'Motif de remboursement trop long.'; end if;
  elsif old.status='refunded' then
    if new.refund_reference is distinct from old.refund_reference or new.refund_reason is distinct from old.refund_reason or new.refunded_at is distinct from old.refunded_at then
      raise exception 'Les informations de remboursement sont immuables.';
    end if;
  elsif new.status<>'refunded' and (new.refund_reference is not null or new.refund_reason is not null or new.refunded_at is not null) then
    raise exception 'Un remboursement doit être enregistré avec le statut remboursé.';
  end if;
  return new;
end;
$$;
revoke all on function private.novelia_validate_purchase_refund_fields() from public,anon,authenticated;
create trigger nov_validate_purchase_refund_fields
before update of status,refund_reference,refund_reason,refunded_at on public.novelia_chapter_purchases
for each row execute function private.novelia_validate_purchase_refund_fields();

create or replace function public.novelia_mark_chapter_purchase_refunded(p_purchase_id uuid,p_refund_reference text,p_reason text default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_count integer;
begin
  if not public.novelia_is_admin() then raise exception 'Action réservée aux administrateurs.'; end if;
  if p_refund_reference is null or length(trim(p_refund_reference))<3 or length(trim(p_refund_reference))>120 then raise exception 'Référence de remboursement invalide.'; end if;
  if p_reason is not null and length(p_reason)>500 then raise exception 'Motif trop long.'; end if;
  update public.novelia_chapter_purchases
  set status='refunded',refund_reference=trim(p_refund_reference),refund_reason=nullif(trim(coalesce(p_reason,'')),''),refunded_at=now()
  where id=p_purchase_id and status='paid';
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Achat introuvable ou déjà remboursé.'; end if;
  return true;
end;
$$;
revoke all on function public.novelia_mark_chapter_purchase_refunded(uuid,text,text) from public,anon;
grant execute on function public.novelia_mark_chapter_purchase_refunded(uuid,text,text) to authenticated;

alter table public.notifications drop constraint if exists novelia_notifications_type_check;
alter table public.notifications add constraint novelia_notifications_type_check
check (type = any (array[
  'new_follower','new_chapter','comment_reply','moderation_warning','new_review',
  'new_comment','new_message','contest_award','contest_update','contest_results',
  'chapter_sale','payout_update','purchase_refund','sale_refund'
]::text[]));

create function private.novelia_notify_purchase_refund()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_title text;
begin
  if new.status='refunded' and old.status is distinct from 'refunded' then
    select title into v_title from public.chapters where id=new.chapter_id;
    insert into public.notifications(recipient_id,type,story_id,chapter_id,message)
    values(new.buyer_id,'purchase_refund',new.story_id,new.chapter_id,
      'Ton achat du chapitre « '||coalesce(v_title,'Chapitre')||' » a été remboursé. Ton accès à ce chapitre a été retiré.');
    insert into public.notifications(recipient_id,type,story_id,chapter_id,message)
    values(new.author_id,'sale_refund',new.story_id,new.chapter_id,
      'La vente du chapitre « '||coalesce(v_title,'Chapitre')||' » a été remboursée. Ton solde a été ajusté.');
  end if;
  return new;
end;
$$;
revoke all on function private.novelia_notify_purchase_refund() from public,anon,authenticated;
create trigger nov_notify_purchase_refund after update of status on public.novelia_chapter_purchases
for each row execute function private.novelia_notify_purchase_refund();
