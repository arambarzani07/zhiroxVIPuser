import { createClient } from 'npm:@supabase/supabase-js@2.116.0';
const headers = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Cache-Control':'no-store','Content-Type':'application/json','Referrer-Policy':'no-referrer'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
const hash=async(s:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s))),x=>x.toString(16).padStart(2,'0')).join('');
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS') return new Response('ok',{headers});
 if(req.method!=='POST') return reply({error:'method_not_allowed'},405);
 try{
 const raw=Deno.env.get('SUPABASE_SECRET_KEYS');
 const key=raw ? (JSON.parse(raw).default ?? Object.values(JSON.parse(raw))[0]) : Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 const db=createClient(Deno.env.get('SUPABASE_URL')!,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const body=await req.json();
 if(body.action==='read'){
 if(typeof body.token!=='string'||!/^[a-f0-9]{64}$/.test(body.token)) return reply({error:'link_unavailable'},404);
 const offset=Number(body.offset??0);
 if(!Number.isInteger(offset)||offset<0||offset>1000000) return reply({error:'invalid_input'},400);
 const {data,error}=await db.rpc('read_customer_link',{p_hash:await hash(body.token),p_offset:offset});
 if(error) return reply({error:'link_unavailable'},404);
 return reply(data);
 }
 if(!['create','revoke'].includes(body.action)) return reply({error:'invalid_action'},400);
 const bearer=req.headers.get('Authorization')??'';
 const {data:auth,error:authError}=await db.auth.getUser(bearer.replace(/^Bearer /,''));
 if(authError||!auth.user) return reply({error:'authentication_required'},401);
 if(typeof body.customer_id!=='string'||!/^[0-9a-f-]{36}$/i.test(body.customer_id)) return reply({error:'invalid_input'},400);
 const token=Array.from(crypto.getRandomValues(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join('');
 if(body.action==='create'){
   const {error}=await db.rpc('manage_customer_push_link',{
     p_actor:auth.user.id,
     p_customer:body.customer_id,
     p_token_hash:await hash(token),
     p_expires_at:null
   });
   if(error) return reply({error:'forbidden'},403);
   return reply({url:'https://push.zhirox.com/?token='+token,expires_days:null});
 }
 const {error}=await db.rpc('revoke_customer_push_subscriptions_service',{
   p_actor:auth.user.id,
   p_customer:body.customer_id
 });
 if(error) return reply({error:'forbidden'},403);
 return reply({revoked:true});
 }catch{return reply({error:'request_failed'},400);}
});
