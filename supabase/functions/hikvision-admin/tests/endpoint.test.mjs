import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile, unlink } from 'node:fs/promises';
// Node strips TS locally; replacing only the runtime imports lets us exercise
// the real handler with a tenant-checking database double, without credentials.
const path = new URL('../index.test-runtime.ts', import.meta.url);
const code = (await readFile(new URL('../index.ts',import.meta.url),'utf8'))
 .replace(/import \{ createClient \} from "[^"]+";/,'const createClient = globalThis.testCreateClient;');
let handler;
let mode='authenticated';
const row={id:'clip-a',market_id:'market-a',status:'ready',object_path:'private.mp4',content_sha256:'same',channel_id:10,clip_start_at:'2026-10-04T09:00:00Z',clip_end_at:'2026-10-04T09:00:30Z'};
const other={...row,id:'clip-b',clip_start_at:'2026-10-04T08:00:00Z',clip_end_at:'2026-10-04T08:00:30Z'};
let queries=[];
globalThis.Deno={env:{get:()=> 'test-value'},serve:fn=>handler=fn};
globalThis.testCreateClient=()=>({
 auth:{getUser:async()=>({data:{user:mode==='authenticated'?{id:'market-a'}:null},error:null})},
 from(table){
  const filters=[];let single=false;
  const result=()=>{
   if(table==='profiles')return {data:{role:'admin',active:true,approved:true,market_name:'test'},error:null};
   if(table==='transaction_video_evidence') {
    assert.ok(filters.some(([key,value])=>key==='market_id'&&value==='market-a'));
    queries.push(filters);
    return {data:single?row:[other],error:null};
   }
   return {data:null,error:null};
  };
  const q={select:()=>q,eq:(key,value)=>{filters.push([key,value]);return q;},neq:()=>q,or:()=>q,order:()=>q,limit:()=>q,maybeSingle:()=>{single=true;return q;},then:(resolve)=>Promise.resolve(result()).then(resolve)};
  return q;
 },
 storage:{from:()=>({createSignedUrl:async()=>({data:{signedUrl:'https://example.com/clip?token=test'},error:null})})},
});
await writeFile(path,code);
try { await import(path.href); } finally { await unlink(path); }
const request=action=>new Request('https://example.com',{method:'POST',headers:{authorization:'Bearer test','content-type':'application/json'},body:JSON.stringify({action,source_type:'debt',source_id:'00000000-0000-0000-0000-000000000001',market_id:'attacker-tenant'})});
test('status and signed playback warn without exposing hashes; client cannot choose tenant',async()=>{
 for(const action of ['video_status','video_url']) {
  const response=await handler(request(action));assert.equal(response.status,200);
  const data=await response.json();assert.equal(data.evidence.integrity.duplicate_warning,true);
  assert.equal(data.evidence.content_sha256,undefined);assert.equal(data.evidence.market_id,undefined);
  if(action==='video_url')assert.equal(data.ready,true);
 }
 assert.equal(queries.length,4);
});
test('unauthenticated requests fail before accessing clips',async()=>{
 mode='unauthenticated';const count=queries.length;
 assert.equal((await handler(request('video_status'))).status,401);
 assert.equal(queries.length,count);
});
