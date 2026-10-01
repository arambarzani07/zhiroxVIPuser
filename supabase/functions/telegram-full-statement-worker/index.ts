import { createClient } from "npm:@supabase/supabase-js@2.116.0";

function env(name:string):string{return(Deno.env.get(name)??"").trim();}
function serviceKey():string{
  const modern=env("SUPABASE_SECRET_KEYS");
  if(modern){try{const parsed=JSON.parse(modern) as Record<string,string>;const v=parsed.default??Object.values(parsed)[0];if(v)return String(v).trim();}catch(_) {}}
  return env("SUPABASE_SERVICE_ROLE_KEY");
}
async function sha256Hex(value:string):Promise<string>{const d=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value));return Array.from(new Uint8Array(d)).map(x=>x.toString(16).padStart(2,"0")).join("");}
async function secureEqual(a:string,b:string):Promise<boolean>{const [x,y]=await Promise.all([sha256Hex(a),sha256Hex(b)]);if(x.length!==y.length)return false;let d=0;for(let i=0;i<x.length;i++)d|=x.charCodeAt(i)^y.charCodeAt(i);return d===0;}
async function loadBotToken(admin:any):Promise<string>{const direct=env("TELEGRAM_BOT_TOKEN");if(direct)return direct;const{data,error}=await admin.rpc("get_telegram_runtime_config_service");if(error)return"";const row=Array.isArray(data)?data[0]:data;return String(row?.bot_token??"").trim();}
async function sendMessage(token:string,chatId:string,text:string){try{await fetch(`https://api.telegram.org/bot${token}/sendMessage`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({chat_id:chatId,text,disable_web_page_preview:true}),signal:AbortSignal.timeout(8000)});}catch(_) {}}
function json(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});}

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return json({error:"method_not_allowed"},405);
  const url=env("SUPABASE_URL"),secret=serviceKey();if(!url||!secret)return json({error:"server_not_configured"},500);
  const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const config=await admin.rpc("get_customer_push_runtime_config_service");
  const workerSecret=String((Array.isArray(config.data)?config.data[0]:config.data)?.customer_push_worker_secret??"").trim();
  const provided=req.headers.get("x-zhirox-push-worker")??"";
  if(!workerSecret||!provided||!(await secureEqual(workerSecret,provided)))return json({error:"unauthorized"},401);
  const botToken=await loadBotToken(admin);if(!botToken)return json({error:"telegram_not_configured"},503);
  const internal=await sha256Hex(`${botToken}:customer-pdf`);
  const processed:any[]=[];

  for(let cycle=0;cycle<3;cycle++){
    const claim=await admin.rpc("claim_telegram_full_statement_job_service");
    if(claim.error){console.error("claim",claim.error.message);break;}
    const job=Array.isArray(claim.data)?claim.data[0]:claim.data;
    if(!job)break;
    const jobId=String(job.job_id),chatId=String(job.chat_id);
    try{
      const response=await fetch(`${url}/functions/v1/telegram-customer-pdf`,{
        method:"POST",
        headers:{"Content-Type":"application/json","x-zhirox-telegram-internal":internal},
        body:JSON.stringify({action:"statement_chunk",chat_id:chatId,offset:Number(job.next_offset),limit:Number(job.chunk_size),total_rows:Number(job.total_rows),part_no:Number(job.part_no),total_parts:Number(job.total_parts)}),
        signal:AbortSignal.timeout(35000),
      });
      let body:any={};try{body=await response.json();}catch(_){}
      if(!response.ok||body?.ok!==true||body?.sent!==true)throw new Error(`pdf_${response.status}_${String(body?.error??"failed")}`);
      const sentCount=Math.max(0,Number(body.statement_rows??0)|0),hasMore=Boolean(body.has_more);
      const finish=await admin.rpc("finish_telegram_full_statement_chunk_service",{p_job_id:jobId,p_sent_count:sentCount,p_has_more:hasMore});
      if(finish.error)throw finish.error;
      processed.push({job_id:jobId,part:Number(job.part_no),sent:sentCount,has_more:hasMore});
      if(!hasMore){await sendMessage(botToken,chatId,`✅ کەشف حسابی تەواو نێردرا.\nکۆی ${Number(job.total_rows).toLocaleString("en-US")} مامەڵە لە ${Number(job.total_parts)} بەشی PDF.`);}
    }catch(error){
      const message=String(error instanceof Error?error.message:error).slice(0,900);
      await admin.rpc("retry_telegram_full_statement_job_service",{p_job_id:jobId,p_error:message});
      processed.push({job_id:jobId,error:message});
      break;
    }
  }
  return json({ok:true,processed});
});
