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
  const auth=req.headers.get("Authorization");
  if(!publicKey||!auth?.startsWith("Bearer "))return json({error:"Authentication required"},401);
  const userClient=createClient(url,publicKey,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error}=await userClient.auth.getUser();
  if(error||!user)return json({error:"Invalid session"},401);
  const admin=await userClient.rpc("novelia_is_admin");
  if(admin.error||admin.data!==true)return json({error:"Admin only"},403);

  const apiKey=Deno.env.get("CINETPAY_API_KEY_TG");
  const apiPassword=Deno.env.get("CINETPAY_API_PASSWORD_TG");
  if(!apiKey||!apiPassword)return json({configured:false,verified:false,environment:"missing"});
  const environment=apiKey.startsWith("sk_live_")?"production":apiKey.startsWith("sk_test_")?"sandbox":"unknown";
  if(environment==="unknown")return json({configured:true,verified:false,environment});
  try{
    const client=new CinetPayClient({credentials:{TG:{apiKey,apiPassword}}});
    await client.balance.get("TG");
    return json({configured:true,verified:true,environment});
  }catch{
    return json({configured:true,verified:false,environment});
  }
 }catch{
  return json({error:"Health check failed"},500);
 }
});