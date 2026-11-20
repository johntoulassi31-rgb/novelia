import { createClient } from "npm:@supabase/supabase-js@2.109.0";
import { CinetPayClient, parseNotification, verifyNotification } from "npm:cinetpay-js@0.1.0";

const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"Content-Type":"application/json"}});
const samePhone=(a:string,b:string)=>String(a||"").replace(/\D/g,"").slice(-8)===String(b||"").replace(/\D/g,"").slice(-8);
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return json({error:"Method not allowed"},405);
 try{
  const url=Deno.env.get("SUPABASE_URL")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey=Deno.env.get("CINETPAY_API_KEY_TG"),apiPassword=Deno.env.get("CINETPAY_API_PASSWORD_TG");
  if(!serviceKey||!apiKey||!apiPassword)return json({error:"Webhook not configured"},503);
  const notification=parseNotification(await req.text());
  const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:request,error}=await admin.from("novelia_payout_requests")
   .select("id,client_transaction_id,provider_transaction_id,notify_token,status,amount_xof,destination_phone_number")
   .eq("client_transaction_id",notification.merchantTransactionId).maybeSingle();
  if(error||!request||!request.notify_token||
     !verifyNotification(request.notify_token,notification.notifyToken))return json({error:"Invalid notification"},401);
  if(request.status==="paid"||request.status==="failed"||request.status==="cancelled")return json({ok:true,duplicate:true});
  if(request.status!=="processing")return json({ok:true,ignored:true});

  const client=new CinetPayClient({credentials:{TG:{apiKey,apiPassword}}});
  const status=await client.transfer.getStatus(notification.transactionId,"TG");
  if(status.merchantTransactionId!==request.client_transaction_id||
     status.transactionId!==notification.transactionId||
     Number(status.amount)!==Number(request.amount_xof)||
     (status.phoneNumber&&!samePhone(status.phoneNumber,request.destination_phone_number))){
    return json({error:"Transfer mismatch"},400);
  }
  if(status.status==="PENDING"||status.status==="INITIATED")return json({ok:true,pending:true});
  if(status.status!=="SUCCESS"&&status.status!=="FAILED")return json({ok:true,pending:true});
  const next=status.status==="SUCCESS"?"paid":"failed";
  const {error:updateError}=await admin.from("novelia_payout_requests").update({
   status:next,provider_transaction_id:status.transactionId,provider_fee_xof:Math.round(Number(status.feeAmount)||0)
  }).eq("id",request.id).eq("status","processing");
  if(updateError)return json({error:"Unable to update payout"},500);
  return json({ok:true,status:next});
 }catch{
  return json({error:"Invalid or unverifiable transfer notification"},400);
 }
});