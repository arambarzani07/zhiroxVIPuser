import { createClient } from "npm:@supabase/supabase-js@2.116.0";
const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store"}});
const env=(name:string)=>(Deno.env.get(name)??"").trim();
function serviceKey(){const raw=env("SUPABASE_SECRET_KEYS");if(raw){try{const p=JSON.parse(raw) as Record<string,string>;const v=p.default??Object.values(p)[0];if(v)return String(v).trim()}catch(_){}}return env("SUPABASE_SERVICE_ROLE_KEY")}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
 if(req.method!=="POST")return json({error:"method_not_allowed"},405);
 const url=env("SUPABASE_URL"),secret=serviceKey(); if(!url||!secret)return json({error:"server_not_configured"},500);
 const h=(req.headers.get("Authorization")??"").trim();const token=h.toLowerCase().startsWith("bearer ")?h.slice(7).trim():"";if(!token)return json({error:"authentication_required"},401);
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:a,error:ae}=await admin.auth.getUser(token);if(ae||!a.user)return json({error:"authentication_required"},401);
 const {data:p,error:pe}=await admin.from("profiles").select("id,active,is_system_owner").eq("id",a.user.id).maybeSingle();
 if(pe)return json({error:"profile_lookup_failed"},500);if(!p||p.active!==true||p.is_system_owner!==true)return json({error:"system_owner_required"},403);
 let b:Record<string,unknown>={};try{b=await req.json()}catch(_){}
 const search=String(b.search??"").trim().slice(0,100);const allowed=new Set(["all","healthy","degraded","attention"]);const rh=String(b.health??"all").trim().toLowerCase();const health=allowed.has(rh)?rh:"all";
 const page=Math.max(1,Math.min(100000,Number(b.page??1)||1));const perPage=Math.max(10,Math.min(100,Number(b.per_page??25)||25));
 const {data,error}=await admin.rpc("get_system_owner_autopilot_overview_service",{p_search:search,p_health:health,p_page:page,p_per_page:perPage});
 if(error){console.error("owner-autopilot-dashboard",error.message);return json({error:"dashboard_unavailable"},500)}
 return json(data??{});
});