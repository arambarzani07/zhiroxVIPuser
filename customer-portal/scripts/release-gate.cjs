'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const assets = ['index.html','app.js','styles.css','portal-banking.css','manifest.webmanifest','manifest-bootstrap.js','sw.js','apple-touch-icon.png'];
const fail = (message) => { throw new Error('PORTAL_GATE: ' + message); };
const assert = (condition, message) => { if (!condition) fail(message); };
const read = (name) => fs.readFileSync(path.join(root,name),'utf8');
for (const name of [...assets,'vercel.json']) {
  const p = path.join(root,name);
  assert(fs.existsSync(p), 'missing ' + name);
  assert(fs.lstatSync(p).isFile() && fs.statSync(p).size > 0, 'invalid ' + name);
}
for (const name of ['app.js','manifest-bootstrap.js','sw.js']) {
  execFileSync(process.execPath,['--check',path.join(root,name)],{stdio:'inherit'});
}
const html = read('index.html');
const ids = [...html.matchAll(/\bid\s*=\s*["']([^"']+)["']/g)].map(m=>m[1]);
assert(ids.length>0 && ids.length===new Set(ids).size,'duplicate or missing HTML IDs');
for (const m of read('app.js').matchAll(/getElementById\(\s*["']([^"']+)["']\s*\)/g)) assert(ids.includes(m[1]),'missing DOM ID '+m[1]);
for(const name of ['app.js','styles.css','portal-banking.css','manifest-bootstrap.js']) assert(html.includes(name),'HTML missing '+name);
const manifest=JSON.parse(read('manifest.webmanifest'));
assert(manifest.lang==='ckb' && manifest.dir==='rtl' && manifest.display==='standalone','invalid Kurdish PWA manifest');
assert(manifest.start_url==='./index.html' && manifest.scope==='./','invalid PWA scope');
assert(manifest.icons?.some(i=>i.src==='./apple-touch-icon.png'&&i.sizes==='1024x1024'&&i.type==='image/png'),'invalid manifest icon');
const png=fs.readFileSync(path.join(root,'apple-touch-icon.png'));
assert(png.length>=24 && png.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])) && png.toString('ascii',12,16)==='IHDR' && png.readUInt32BE(16)===1024 && png.readUInt32BE(20)===1024,'invalid PNG dimensions or signature');
const config=JSON.parse(read('vercel.json'));
const headers=Object.fromEntries((config.headers?.find(h=>h.source==='/(.*)')?.headers||[]).map(h=>[h.key.toLowerCase(),h.value]));
const expected={'cache-control':'no-store','referrer-policy':'no-referrer','x-frame-options':'DENY','x-content-type-options':'nosniff','permissions-policy':'camera=(), microphone=(), geolocation=()','x-robots-tag':'noindex, nofollow','strict-transport-security':'max-age=31536000'};
for(const [key,value] of Object.entries(expected)) assert(headers[key]===value,'missing or weakened '+key);
const csp="default-src 'self'; connect-src 'self' https://ryzgbajgjctmliwhvezo.supabase.co; worker-src 'self'; manifest-src 'self'; script-src 'self' https://cdnjs.cloudflare.com; style-src 'self'; img-src 'self' data: blob:; base-uri 'none'; frame-ancestors 'none'; form-action 'self'; object-src 'none'";
assert(headers['content-security-policy']===csp,'CSP changed; security review required');
for(const [source,destination] of [['/portal.html','/index.html'],['/install-manifest.webmanifest','/manifest.webmanifest']]) assert(config.rewrites?.some(r=>r.source===source&&r.destination===destination),'missing rewrite '+source);
assert(config.buildCommand==='node scripts/release-gate.cjs'&&config.outputDirectory==='dist','gate configuration mismatch');
for(const name of assets.filter(n=>!n.endsWith('.png'))){
  assert(!/-----BEGIN [A-Z ]*PRIVATE KEY-----|sb_secret_[A-Za-z0-9_-]+|gh[pousr]_[A-Za-z0-9]{25,}|sk_live_[A-Za-z0-9]+|AKIA[A-Z0-9]{16}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/.test(read(name)),'possible secret in '+name);
}
const out=path.join(root,'dist');
fs.rmSync(out,{recursive:true,force:true});
fs.mkdirSync(out);
for(const name of assets) fs.copyFileSync(path.join(root,name),path.join(out,name));
console.log('PORTAL_GATE: PASS; 8 public assets copied; static validation only');
