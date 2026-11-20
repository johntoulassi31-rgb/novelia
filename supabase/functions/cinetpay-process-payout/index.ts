import { createClient } from "npm:@supabase/supabase-js@2.109.0";
import { CinetPayClient } from "npm:cinetpay-js@0.1.0";

const cors={"Access-Control-Allow-Origin":"https://johntoulassi31-rgb.github.io","Access-Control-Allow-Headers":"authorization, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors});

Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed"},405);
 try{
  const url=Deno.env.get("SUPABASE_URL")!;
  const publicKey=Deno.env.get("SUPABASE_ANON_KEY")??Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey=Deno.env.get("CINETPAY_API_KEY_TG"),apiPassword=Deno.env.get("CINETPAY_API_PASSWORD_TG");
  const auth=req.headers.get("Authorization");
  if(!publicKey||!serviceKey||!auth?.startsWith("Bearer "))return json({error:"Authentication required"},401);
  const userClient=createClient(url,publicKey,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:userError}=await userClient.auth.getUser();
  if(userError||!user)return json({error:"Invalid session"},401);
  const isAdmin=await userClient.rpc("novelia_is_admin");
  if(isAdmin.error||isAdmin.data!==true)return json({error:"Admin only"},403);
  if(!apiKey||!apiPassword)return json({error:"CinetPay n’est pas configuré."},503);

  const body=await req.json(),requestId=String(body.request_id||"");
  if(!requestId)return json({error:"Référence de retrait manquante."},400);
  const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:request,error}=await admin.from("novelia_payout_requests")
   .select("id,client_transaction_id,author_id,destination_operator,destination_phone_number,amount_xof,status,provider_transaction_id,notify_token")
   .eq("id",requestId).single();
  if(error||!request)return json({error:"Demande de retrait introuvable."},404);
  if(!["approved","processing"].includes(request.status))return json({error:"Approuve la demande avant de lancer le transfert."},409);

  const client=new CinetPayClient({credentials:{TG:{apiKey,apiPassword}}});
  let transfer:Awaited<ReturnType<typeof client.transfer.create>>|null=null;
  if(request.status==="approved"){
   try{
    transfer=await client.transfer.create({
     currency:"XOF",
     merchantTransactionId:request.client_transaction_id,
     phoneNumber:request.destination_phone_number,
     amount:Number(request.amount_xof),
     paymentMethod:(request.destination_operator==="moov_tg"?"MOOV_TG":"TMONEY_TG") as "MOOV_TG"|"TMONEY_TG",
     reason:"Rémunération auteur Novelia",
     notifyUrl:url+"/functions/v1/cinetpay-payout-webhook"
    },"TG");
   }catch{
    try{
     const recovered=await client.transfer.getStatus(request.client_transaction_id,"TG");
     if(recovered.merchantTransactionId!==request.client_transaction_id||
        Number(recovered.amount)!==Number(request.amount_xof)||
        (recovered.phoneNumber&&recovered.phoneNumber!==request.destination_phone_number))throw new Error("Mismatch");
     const next=recovered.status==="FAILED"?"failed":"processing";
     const update=await admin.from("novelia_payout_requests").update({
      status:next,provider_transaction_id:recovered.transactionId,provider_fee_xof:Math.round(Number(recovered.feeAmount)||0)
     }).eq("id",request.id).eq("status","approved");
     if(update.error)return json({error:"Impossible d’enregistrer le transfert retrouvé."},500);
     if(next==="failed")return json({status:"failed",message:"CinetPay confirme l’échec. Le solde a été libéré."});
     const statusRecovered=await client.transfer.getStatus(recovered.transactionId,"TG");
     if(statusRecovered.status==="SUCCESS"){
      const paid=await admin.from("novelia_payout_requests").update({status:"paid",provider_transaction_id:statusRecovered.transactionId,provider_fee_xof:Math.round(Number(statusRecovered.feeAmount)||0)})
       .eq("id",request.id).eq("status","processing");
      if(paid.error)return json({error:"Transfert confirmé mais portefeuille non actualisé."},500);
      return json({status:"paid",message:"Transfert confirmé par CinetPay."});
     }
     return json({status:"processing",message:"Transfert retrouvé. Le statut reste en vérification."});
    }catch{
     return json({error:"Impossible d’initier ou de retrouver le transfert CinetPay."},502);
    }
   }
   const nextStatus=transfer.status==="FAILED"?"failed":"processing";
   const update=await admin.from("novelia_payout_requests").update({
    status:nextStatus,provider_transaction_id:transfer.transactionId,notify_token:transfer.notifyToken,provider_fee_xof:Math.round(Number(transfer.feeAmount)||0)
   }).eq("id",request.id).eq("status","approved");
   if(update.error)return json({error:"Transfert créé mais enregistrement du suivi impossible. Contacte l’assistance."},500);
   if(nextStatus==="failed")return json({status:"failed",message:"CinetPay a refusé le transfert. Le solde a été libéré."});
  }

  const transactionId=transfer?.transactionId||request.provider_transaction_id||request.client_transaction_id;
  const status=await client.transfer.getStatus(transactionId,"TG");
  if(status.merchantTransactionId!==request.client_transaction_id||
     Number(status.amount)!==Number(request.amount_xof)||
     (status.phoneNumber&&status.phoneNumber!==request.destination_phone_number)){
    return json({error:"Les informations du transfert ne correspondent pas à la demande."},409);
  }
  if(status.status==="SUCCESS"){
   const {error:updateError}=await admin.from("novelia_payout_requests").update({
    status:"paid",provider_transaction_id:status.transactionId,provider_fee_xof:Math.round(Number(status.feeAmount)||0)
   }).eq("id",request.id).eq("status","processing");
   if(updateError)return json({error:"Transfert confirmé mais mise à jour du portefeuille impossible."},500);
   return json({status:"paid",message:"Transfert confirmé par CinetPay."});
  }
  if(status.status==="FAILED"){
   const {error:updateError}=await admin.from("novelia_payout_requests").update({
    status:"failed",provider_transaction_id:status.transactionId,provider_fee_xof:Math.round(Number(status.feeAmount)||0)
   }).eq("id",request.id).eq("status","processing");
   if(updateError)return json({error:"Échec confirmé, mais le portefeuille n’a pas pu être actualisé."},500);
   return json({status:"failed",message:"Transfert échoué. Le solde a été libéré."});
  }
  return json({status:"processing",message:"Transfert en cours. Novelia vérifiera le statut automatiquement à la prochaine vérification."});
 }catch{
  return json({error:"Erreur pendant le traitement du retrait."},500);
 }
});