alter table public.novelia_payout_requests
  add column client_transaction_id text not null
    default ('NVP' || substr(replace(gen_random_uuid()::text,'-',''),1,22)),
  add column notify_token text;
create unique index idx_novelia_payout_client_transaction
on public.novelia_payout_requests(client_transaction_id);

revoke select on public.novelia_payout_requests from authenticated;
grant select (
  id,author_id,destination_id,destination_operator,destination_phone_number,
  destination_account_holder,amount_xof,status,provider_transaction_id,
  admin_note,created_at,updated_at,processed_at
) on public.novelia_payout_requests to authenticated;

create or replace function private.novelia_validate_payout_transition()
returns trigger language plpgsql set search_path='' as $$
begin
  if new.author_id<>old.author_id or new.destination_id<>old.destination_id
     or new.destination_operator<>old.destination_operator or new.destination_phone_number<>old.destination_phone_number
     or new.destination_account_holder<>old.destination_account_holder or new.amount_xof<>old.amount_xof
     or new.client_transaction_id<>old.client_transaction_id then
    raise exception 'Les informations d’une demande de retrait sont immuables.';
  end if;
  if old.notify_token is not null and new.notify_token is distinct from old.notify_token then
    raise exception 'Le jeton de notification est immuable.';
  end if;
  if old.status in ('paid','failed','cancelled') and new.status<>old.status then
    raise exception 'Cette demande de retrait est terminée.';
  end if;
  if old.status='requested' and new.status not in ('requested','approved','processing','failed','cancelled') then
    raise exception 'Transition de retrait invalide.';
  elsif old.status='approved' and new.status not in ('approved','processing','failed','cancelled') then
    raise exception 'Transition de retrait invalide.';
  elsif old.status='processing' and new.status not in ('processing','paid','failed') then
    raise exception 'Transition de retrait invalide.';
  end if;
  if new.status='paid' then
    if new.provider_transaction_id is null or length(trim(new.provider_transaction_id))=0 then
      raise exception 'Référence ou jeton du transfert manquant.';
    end if;
    new.processed_at:=coalesce(new.processed_at,now());
  end if;
  new.updated_at:=now();
  return new;
end;
$$;