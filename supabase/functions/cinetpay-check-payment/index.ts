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
  if(!publicKey||!serviceKey||!auth?.startsWith("Bearer "))return json({error:"Connexion requise."},401);
  const userClient=createClient(url,publicKey,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:userError}=await userClient.auth.getUser();
  if(userError||!user)return json({error:"Session invalide."},401);
  if(!apiKey||!apiPassword)return json({error:"La vérification CinetPay n’est pas encore configurée."},503);

  const body=await req.json(),purchaseId=String(body.purchase_id||"");
  if(!purchaseId)return json({error:"Référence d’achat manquante."},400);
  const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:purchase,error}=await admin.from("novelia_chapter_purchases")
   .select("id,buyer_id,client_transaction_id,provider_transaction_id,notify_token,status,gross_amount_xof,author_share_bps,provider_fee_bps")
   .eq("id",purchaseId).eq("buyer_id",user.id).maybeSingle();
  if(error||!purchase)return json({error:"Achat introuvable sur ce compte."},404);
  if(purchase.status==="paid"||purchase.status==="failed"||purchase.status==="refunded")return json({status:purchase.status});
  if(!purchase.provider_transaction_id)return json({status:"pending",message:"Le paiement est encore en cours d’initialisation."});

  const client=new CinetPayClient({credentials:{TG:{apiKey,apiPassword}}});
  const status=await client.payment.getStatus(purchase.provider_transaction_id,"TG");
  if(status.merchantTransactionId!==purchase.client_transaction_id||
     status.transactionId!==purchase.provider_transaction_id)return json({error:"Transaction non concordante."},409);
  if(status.status==="PENDING"||status.status==="INITIATED")return json({status:"pending"});
  if(status.status==="FAILED"){
   const failed=await admin.from("novelia_chapter_purchases").update({status:"failed"})
    .eq("id",purchase.id).eq("status","pending");
   if(failed.error)return json({error:"Impossible d’actualiser le statut."},500);
   return json({status:"failed"});
  }
  if(status.status!=="SUCCESS")return json({status:"pending"});
  const gross=Number(purchase.gross_amount_xof);
  const providerFee=Math.ceil(gross*Number(purchase.provider_fee_bps)/10000);
  const net=gross-providerFee;
  const platformFee=Math.floor(net*(10000-Number(purchase.author_share_bps))/10000);
  const authorEarning=net-platformFee;
  const {error:updateError}=await admin.from("novelia_chapter_purchases").update({
   status:"paid",provider_fee_xof:providerFee,platform_fee_xof:platformFee,
   author_earning_xof:authorEarning,paid_at:new Date().toISOString()
  }).eq("id",purchase.id).eq("status","pending");
  if(updateError)return json({error:"Paiement confirmé, mais l’accès doit encore être synchronisé."},500);
  return json({status:"paid"});
 }catch{
  return json({error:"Impossible de vérifier le paiement auprès de CinetPay."},502);
 }
});