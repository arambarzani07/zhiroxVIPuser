import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { PDFDocument, rgb } from "npm:pdf-lib@1.17.1";
import fontkit from "npm:@pdf-lib/fontkit@1.1.1";

const A4: [number, number] = [595.28, 841.89];
const MARGIN = 42;
const MAX_STATEMENT_ROWS = 200;
let fontPromise: Promise<Uint8Array> | null = null;

function env(name: string): string { return (Deno.env.get(name) ?? "").trim(); }
function serviceKey(): string {
  const modern = env("SUPABASE_SECRET_KEYS");
  if (modern) {
    try {
      const parsed = JSON.parse(modern) as Record<string,string>;
      const value = parsed.default ?? Object.values(parsed)[0];
      if (value) return String(value).trim();
    } catch (_) {}
  }
  return env("SUPABASE_SERVICE_ROLE_KEY");
}
async function sha256Hex(value:string):Promise<string>{
  const data=new TextEncoder().encode(value);
  const hash=new Uint8Array(await crypto.subtle.digest("SHA-256",data));
  return Array.from(hash).map(b=>b.toString(16).padStart(2,"0")).join("");
}
async function secureEqual(left:string,right:string):Promise<boolean>{
  const [a,b]=await Promise.all([sha256Hex(left),sha256Hex(right)]);
  if(a.length!==b.length)return false; let diff=0;
  for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);
  return diff===0;
}
async function loadBotToken(admin:any):Promise<string>{
  const direct=env("TELEGRAM_BOT_TOKEN"); if(direct)return direct;
  const {data,error}=await admin.rpc("get_telegram_runtime_config_service");
  if(error)return ""; const row=Array.isArray(data)?data[0]:data;
  return String(row?.bot_token??"").trim();
}
async function loadFont():Promise<Uint8Array>{
  if(!fontPromise){fontPromise=(async()=>{
    const r=await fetch("https://raw.githubusercontent.com/google/fonts/main/ofl/notosansarabic/NotoSansArabic%5Bwdth%2Cwght%5D.ttf",{signal:AbortSignal.timeout(10000)});
    if(!r.ok)throw new Error(`font_${r.status}`); return new Uint8Array(await r.arrayBuffer());
  })();}
  return await fontPromise;
}
function clean(v:unknown):string{return String(v??"").replace(/[\r\n\t]+/g," ").replace(/\s+/g," ").trim();}
function fmtDate(v:unknown):string{
  const d=new Date(String(v??"")); if(!Number.isFinite(d.getTime()))return "—";
  return new Intl.DateTimeFormat("en-GB",{timeZone:"Asia/Baghdad",year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit",hour12:false}).format(d);
}
function fmtAmount(v:unknown,c:unknown="IQD"):string{
  const n=Number(v??0),x=Number.isFinite(n)?n:0;
  return String(c??"IQD").toUpperCase()==="USD"?`$${x.toLocaleString("en-US",{minimumFractionDigits:2,maximumFractionDigits:2})}`:`${Math.round(x).toLocaleString("en-US")} د.ع`;
}
async function newPdf(){
  const bytes=await loadFont(); const pdf=await PDFDocument.create(); pdf.registerFontkit(fontkit);
  const font=await pdf.embedFont(bytes,{subset:true}); return {pdf,font};
}
function pdfHelpers(pdf:any,font:any){
  const W=A4[0],H=A4[1],usable=W-MARGIN*2; let page=pdf.addPage(A4),y=H-54;
  const addPage=()=>{page=pdf.addPage(A4);y=H-52;};
  const ensure=(h:number)=>{if(y-h<42)addPage();};
  const right=(text:string,size=9,color=rgb(.07,.07,.07))=>{const t=clean(text),w=font.widthOfTextAtSize(t,size);page.drawText(t,{x:Math.max(MARGIN,W-MARGIN-w),y,size,font,color});};
  const left=(text:string,size=8.2)=>page.drawText(clean(text),{x:MARGIN,y,size,font,color:rgb(.07,.07,.07)});
  const wrap=(text:string,size=8.2,max=usable)=>{const ws=clean(text).split(" ").filter(Boolean),ls:string[]=[];let cur="";for(const w of ws){const n=cur?`${cur} ${w}`:w;if(font.widthOfTextAtSize(n,size)<=max)cur=n;else{if(cur)ls.push(cur);cur=w;}}if(cur)ls.push(cur);return ls;};
  const wrapRight=(text:string,size=8.2,max=usable)=>{for(const l of wrap(text,size,max)){ensure(13);right(l,size);y-=13;}};
  const line=()=>page.drawLine({start:{x:MARGIN,y},end:{x:W-MARGIN,y},thickness:.45,color:rgb(.78,.78,.78)});
  const down=(n:number)=>{y-=n;}; const pages=()=>pdf.getPages();
  return {usable,ensure,right,left,wrapRight,line,down,pages};
}
async function loadChunk(admin:any,chatId:string,offset:number,limit:number):Promise<any>{
  const {data,error}=await admin.rpc("get_telegram_customer_statement_chunk_service",{p_chat_id:chatId,p_offset:offset,p_limit:limit});
  if(error)throw error; if(!data)throw new Error("telegram_not_linked"); return data;
}
async function statementPdf(current:any,rows:any[],offset:number,totalRows:number|null,partNo:number|null,totalParts:number|null):Promise<Uint8Array>{
  const {pdf,font}=await newPdf(); const h=pdfHelpers(pdf,font);
  h.right(partNo&&totalParts?`کەشف حسابی تەواوی ZHIROX • بەشی ${partNo}/${totalParts}`:"کەشف حسابی ZHIROX",18);h.down(28);
  h.right(`مارکێت: ${clean(current.market_name)}`,10);h.down(16);
  h.right(`کڕیار: ${clean(current.customer_name)}`,10);h.down(16);
  h.right(`قەرزی ماوە: ${fmtAmount(current.remaining_iqd,"IQD")}`,11);h.down(16);
  if(totalRows!==null){h.right(`مامەڵەکانی ئەم بەشە: ${offset+1}-${offset+rows.length} لە کۆی ${totalRows}`,8.5);h.down(15);}
  else{h.right(`مامەڵە پیشاندراوەکان: ${rows.length}`,8.5);h.down(15);}
  h.right(`بەرواری دروستکردن: ${fmtDate(new Date().toISOString())}`,8.5);h.down(18);h.line();h.down(15);
  if(!rows.length){h.right("هیچ مامەڵەیەک تۆمار نەکراوە.",10);h.down(18);}
  let local=0;
  for(const row of rows){local++;h.ensure(42);const kind=row.kind==="payment"?"پارەدان":"قەرز";
    h.left(`${offset+local}. ${fmtDate(row.occurred_at)} | ${kind} | ${fmtAmount(row.amount,row.currency)}`,8.2);h.down(13);
    if(clean(row.note))h.wrapRight(`تێبینی: ${clean(row.note).slice(0,180)}`,7.8,h.usable-8);
    h.line();h.down(8);
  }
  const pages=h.pages();pages.forEach((pg:any,i:number)=>{const s=`${i+1} / ${pages.length}`,w=font.widthOfTextAtSize(s,7);pg.drawText(s,{x:(A4[0]-w)/2,y:17,size:7,font,color:rgb(.45,.45,.45)});});
  return await pdf.save({useObjectStreams:true,addDefaultPage:false,objectsPerTick:100});
}
async function receiptPdf(admin:any,current:any,row:any):Promise<Uint8Array>{
  const {pdf,font}=await newPdf();const h=pdfHelpers(pdf,font);let receiptNumber="";
  if(row.payment_scope!=="general"){
    const sourceType=row.kind==="payment"?"payment":"debt";
    const {data}=await admin.from("receipt_documents").select("receipt_number").eq("admin_id",current.market_id).eq("source_type",sourceType).eq("source_id",row.id).order("created_at",{ascending:false}).limit(1);
    receiptNumber=String(data?.[0]?.receipt_number??"");
  }
  h.right("پسووڵەی مامەڵە - ZHIROX",18);h.down(30);h.right(`مارکێت: ${clean(current.market_name)}`,10);h.down(18);h.right(`کڕیار: ${clean(current.customer_name)}`,10);h.down(18);h.line();h.down(20);
  h.right(`جۆر: ${row.kind==="payment"?"پارەدان":"قەرز"}`,11);h.down(18);h.right(`بڕ: ${fmtAmount(row.amount,row.currency)}`,12);h.down(18);h.right(`کات: ${fmtDate(row.occurred_at)}`,9);h.down(18);h.right(`قەرزی ماوەی ئێستا: ${fmtAmount(current.remaining_iqd,"IQD")}`,10);h.down(18);
  if(receiptNumber){h.right(`ژمارەی پسووڵە: ${receiptNumber}`,9);h.down(18);}h.right(`ناسنامەی مامەڵە: ${String(row.id).slice(0,18)}…`,8);h.down(18);
  if(clean(row.note))h.wrapRight(`تێبینی: ${clean(row.note).slice(0,500)}`,9);h.down(8);h.line();h.down(18);h.right("ئەم پسووڵەیە لە سیستەمی ZHIROX دەرکراوە.",8.5);
  return await pdf.save({useObjectStreams:true,addDefaultPage:false,objectsPerTick:100});
}
async function sendDocument(botToken:string,chatId:string,bytes:Uint8Array,filename:string,caption:string):Promise<any>{
  const form=new FormData();form.append("chat_id",chatId);form.append("caption",caption);form.append("document",new Blob([bytes],{type:"application/pdf"}),filename);
  const r=await fetch(`https://api.telegram.org/bot${botToken}/sendDocument`,{method:"POST",body:form,signal:AbortSignal.timeout(20000)});let body:any={};try{body=await r.json();}catch(_){}
  if(!r.ok||body?.ok!==true)throw new Error(`telegram_sendDocument_${r.status}`);return body.result;
}
function json(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});}

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return json({error:"method_not_allowed"},405);
  const url=env("SUPABASE_URL"),secret=serviceKey();if(!url||!secret)return json({error:"server_not_configured"},500);
  const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});const botToken=await loadBotToken(admin);if(!botToken)return json({error:"telegram_not_configured"},503);
  const expected=await sha256Hex(`${botToken}:customer-pdf`),provided=req.headers.get("x-zhirox-telegram-internal")??"";
  if(!provided||!(await secureEqual(provided,expected)))return json({error:"unauthorized"},401);
  let body:any;try{body=await req.json();}catch(_){return json({error:"invalid_json"},400);}
  const chatId=String(body?.chat_id??"").trim(),action=String(body?.action??"").trim();
  if(!chatId||!["statement","statement_chunk","receipt"].includes(action))return json({error:"invalid_input"},400);
  try{
    if(action==="receipt"){
      const current=await loadChunk(admin,chatId,0,1);const rows=Array.isArray(current.rows)?current.rows:[];const latest=rows[0];
      if(!latest)return json({ok:true,sent:false,reason:"no_transactions"});
      const bytes=await receiptPdf(admin,current,latest);const result=await sendDocument(botToken,chatId,bytes,`ZHIROX-receipt-${String(latest.id).slice(0,8)}.pdf`,`🧾 پسووڵەی کۆتا مامەڵە • ${fmtAmount(latest.amount,latest.currency)}`);
      return json({ok:true,sent:true,action,message_id:result?.message_id??null,statement_rows:1,has_more:Boolean(current.has_more)});
    }
    const offset=action==="statement_chunk"?Math.max(0,Number(body?.offset??0)|0):0;
    const limit=Math.min(MAX_STATEMENT_ROWS,Math.max(1,Number(body?.limit??MAX_STATEMENT_ROWS)|0));
    const current=await loadChunk(admin,chatId,offset,limit);const rows=Array.isArray(current.rows)?current.rows:[];
    const totalRows=action==="statement_chunk"?Math.max(rows.length,Number(body?.total_rows??rows.length)|0):null;
    const partNo=action==="statement_chunk"?Math.max(1,Number(body?.part_no??1)|0):null;
    const totalParts=action==="statement_chunk"?Math.max(1,Number(body?.total_parts??1)|0):null;
    const bytes=await statementPdf(current,rows,offset,totalRows,partNo,totalParts);const day=new Date().toISOString().slice(0,10);
    const filename=action==="statement_chunk"?`ZHIROX-full-statement-part-${String(partNo).padStart(2,"0")}-of-${String(totalParts).padStart(2,"0")}.pdf`:`ZHIROX-statement-${day}.pdf`;
    const caption=action==="statement_chunk"?`📚 کەشف حسابی تەواو • بەشی ${partNo}/${totalParts}\nمامەڵە ${offset+1}-${offset+rows.length} لە کۆی ${totalRows}`:`📄 کەشف حساب • ${clean(current.market_name)}\n${rows.length} مامەڵەی کۆتایی\nقەرزی ماوە: ${fmtAmount(current.remaining_iqd,"IQD")}`;
    const result=await sendDocument(botToken,chatId,bytes,filename,caption);
    return json({ok:true,sent:true,action,message_id:result?.message_id??null,statement_rows:rows.length,has_more:Boolean(current.has_more),offset});
  }catch(error){console.error("telegram-customer-pdf",String(error instanceof Error?error.message:error));return json({error:"document_failed"},500);}
});
