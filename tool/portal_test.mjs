import {PGlite} from '@electric-sql/pglite';import {readFile,readdir} from 'node:fs/promises';import assert from 'node:assert/strict';
let seq=16000,passed=0;const id=()=>`00000000-0000-4000-8000-${String(seq++).padStart(12,'0')}`;
const w=id(),admin=id(),tech=id(),ad=id(),td=id(),oid=id(),task=id(),qid=id(),line=id(),gid=id();const token='a'.repeat(64),code='b'.repeat(64);
const db=new PGlite();await db.exec("create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);create table auth.sessions(id uuid primary key,user_id uuid not null);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;");await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
for(const f of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(x=>x.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${f}`,import.meta.url),'utf8'));
await db.query('insert into auth.users values($1),($2)',[admin,tech]);await db.query("insert into private.workshops(id,name) values($1,'Fictional portal validation')",[w]);await db.query("insert into private.members values($1,$2,'Admin','admin',true,true),($1,$3,'Tech','technician',false,true)",[w,admin,tech]);
let actor=admin,dev=ad;
async function login(user,device){await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[device,user]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:device})]);await db.exec('set role authenticated');actor=user;dev=device;await snap();}
const snap=async()=>(await db.query('select public.device_snapshot($1,$2) r',[w,dev])).rows[0].r;
async function op(kind,p){const record={id:id(),orderId:oid,actorId:actor,kind,baseRevision:(await snap()).orders[0]?.revision??0,at:new Date().toISOString(),payload:p};const r=(await db.query('select public.apply_operation($1,$2,$3) r',[w,dev,record])).rows[0].r;assert.equal(r.status,'accepted');return record;}
const quote=(version=0)=>({id:qid,expectedVersion:version,title:'Fictional quote',reason:'Private office reason',validUntil:new Date(Date.now()+86400000).toISOString(),lines:[{id:line,taskId:task,description:'Fictional scope',laborMinutes:30,parts:[]}]});
const command=async(action,p,cid=id())=>(await db.query('select public.portal_command($1,$2,$3,$4,$5) r',[w,dev,cid,action,p])).rows[0].r;
const create=async(g=gid,overrides={})=>({id:g,orderId:oid,revision:(await snap()).orders[0].revision,quoteId:qid,quoteVersion:1,tokenHash:token,codeHash:code,expiresAt:new Date(Date.now()+3600000).toISOString(),recipientConfirmed:true,verificationEvidence:'Fictional in-person identity check; independent channel',photoIds:[],documentIds:[],reason:'Fictional access',...overrides});
const access=async(action='read',p={},cid=null,g=gid,t=token,c=code)=>{await db.exec('reset role;set role service_role');return(await db.query('select public.customer_portal($1,$2,$3,$4,$5,$6) r',[g,t,c,action,cid,p])).rows[0].r;};
const test=async(name,fn)=>{await fn();passed++;console.log('PASS '+name);};
try{
 await login(admin,ad);await op('receive',{plate:'9300FIC',country:'ES',vin:'FICTIONAL-PORTAL',vehicle:'Fictional',engine:'2020',client:'Fictional recipient',phone:'Private phone',km:100,symptom:'Symptom',tasks:[{id:task,title:'Diagnosis',estimateMinutes:30,assignees:[tech]}]});await op('quote_draft',quote());
 await test('Only admin can configure HTTPS portal without credentials or query and keep other settings',async()=>{
  const before=(await snap()).settings;
  for(const url of ['http://portal.invalid','https://name:pass@portal.invalid','https://portal.invalid?token=secret'])await assert.rejects(()=>command('portal_configure',{url,reason:'Configuration'}));
  await command('portal_configure',{url:'https://portal.example.invalid',reason:'Fictional hosting'});
  assert.equal((await snap()).settings.portalBaseUrl,'https://portal.example.invalid');assert.equal((await snap()).settings.taxBps,before.taxBps);
  await login(tech,td);await assert.rejects(()=>command('portal_configure',{url:'',reason:'Disable'}),/Office|Administrator/);await login(admin,ad);
 });
 let payload,cid=id(),first;
 await test('Office verifies recipient, scope, expiry and secret hashes before creation',async()=>{
  for(const p of [await create(gid,{recipientConfirmed:false}),await create(gid,{tokenHash:'weak'}),await create(gid,{quoteVersion:99}),await create(gid,{expiresAt:new Date(Date.now()+8*86400000).toISOString()}),await create(gid,{documentIds:[id()]}),await create(gid,{photoIds:[id()]})])await assert.rejects(()=>command('portal_create',p));
  payload=await create();first=await command('portal_create',payload,cid);assert.equal(first.saved,true);
 });
 await test('Lost create reply returns original grant without another access and rejects altered identity',async()=>{
  assert.deepEqual(await command('portal_create',payload,cid),first);await assert.rejects(()=>command('portal_create',{...payload,reason:'Altered'},cid),/ID reused/);assert.equal((await snap()).portalGrants.length,1);assert.equal(JSON.stringify(await snap()).includes(token),false);
 });
 await test('Staff and anonymous cannot invoke the service-only customer boundary',async()=>{
  await assert.rejects(()=>db.query('select public.customer_portal($1,$2,$3,$4,$5,$6)',[gid,token,code,'read',null,{}]),/permission denied/);
  await login(tech,td);assert.equal((await snap()).portalGrants,undefined);await assert.rejects(()=>command('portal_create',payload),/Office/);
  await db.exec('reset role;set role anon');await assert.rejects(()=>db.query('select public.customer_portal($1,$2,$3,$4,$5,$6)',[gid,token,code,'read',null,{}]),/permission denied/);
 });
 await test('Link alone, wrong code and unknown grant return no private detail',async()=>{
  for(const [g,t,c] of [[gid,'c'.repeat(64),code],[gid,token,'d'.repeat(64)],[id(),token,code]])assert.deepEqual(await access('read',{},null,g,t,c),{error:'access'});
 });
 await test('Verified read exposes selected version and status without office notes, costs or contact',async()=>{
  const r=await access();assert.equal(r.quote.version,1);assert.equal(r.quote.customer,'Fictional recipient');assert.equal(r.canDecide,true);assert.equal(JSON.stringify(r).includes('Private'),false);assert.equal(r.quote.lines[0].taskId,undefined);assert.deepEqual(r.documents,[]);assert.deepEqual(r.photos,[]);
 });
 const decisionId=id();
 await test('Customer acceptance applies exact original amount and records distinct customer identity',async()=>{
  const r=await access('decide',{decisions:[{lineId:line,accepted:true}]},decisionId);assert.equal(r.accepted,true);
  await login(admin,ad);const o=(await snap()).orders[0];assert.equal(o.tasks[0].authorized,true);assert.equal(o.tasks[0].approvedCents,2904);assert.equal(o.tasks[0].authorization.actorType,'customer');assert.equal(o.tasks[0].authorization.channel,'portal');assert.equal(o.quoteLedger.decisions[0].portalGrantId,gid);
 });
 await test('Decision response hides internal tasks while workshop keeps original audit links',async()=>{
  const r=await access();assert.deepEqual(r.decisions[0].decisions,[{lineId:line,accepted:true,approvedCents:2904}]);assert.equal(JSON.stringify(r).includes('taskId'),false);
  await login(admin,ad);assert.equal((await snap()).orders[0].quoteLedger.decisions[0].decisions[0].taskId,task);
 });
 await test('Lost acceptance reply cannot duplicate authorization and changed decisions fail',async()=>{
  assert.equal((await access('decide',{decisions:[{lineId:line,accepted:true}]},decisionId)).accepted,true);
  await assert.rejects(()=>access('decide',{decisions:[{lineId:line,accepted:false}]},decisionId),/ID reused/);
  await assert.rejects(()=>access('decide',{decisions:[{lineId:line,accepted:false}]},id()),/immutable/);
  await login(admin,ad);assert.equal((await snap()).orders[0].quoteLedger.decisions.length,1);
 });
 await test('Old link displays its version and never accepts a later version or invented amount',async()=>{
  await op('quote_draft',quote(1));const r=await access();assert.equal(r.quote.version,1);assert.equal(r.canDecide,false);
  await assert.rejects(()=>access('decide',{decisions:[{lineId:line,accepted:true}]},id()),/version unavailable/);
  await assert.rejects(()=>access('decide',{decisions:[{lineId:line,accepted:true}],totalCents:1},id()),/selected lines/);
 });
 await test('Revocation and expiry deny previous secrets and preserve original decisions',async()=>{
  await login(admin,ad);await command('portal_revoke',{id:gid,reason:'Recipient requested revocation'});assert.deepEqual(await access(),{error:'access'});
  await login(admin,ad);const expired=id();await command('portal_create',await create(expired));await db.exec('reset role');await db.query("update private.portal_grants set expires_at=now()-interval '1 second' where id=$1",[expired]);assert.deepEqual(await access('read',{},null,expired),{error:'access'});
 });
 await test('Five failed codes lock only the known grant; unknown token cannot lock access',async()=>{
  await login(admin,ad);const locked=id();await command('portal_create',await create(locked));for(let n=0;n<8;n++)await access('read',{},null,locked,'e'.repeat(64),code);assert.equal((await access('read',{},null,locked)).quote.version,1);
  for(let n=0;n<5;n++)assert.deepEqual(await access('read',{},null,locked,token,'f'.repeat(64)),{error:'access'});assert.deepEqual(await access('read',{},null,locked),{error:'access'});
 });
 await test('Current owner transfer and retired issuing account stop previous recipient access',async()=>{
  await login(admin,ad);const transferred=id();await command('portal_create',await create(transferred));await db.exec('reset role');const original=(await db.query('select owner_id from private.vehicle_profiles where workshop_id=$1',[w])).rows[0].owner_id;
  await db.query('update private.vehicle_profiles set owner_id=$1 where workshop_id=$2',[id(),w]);assert.deepEqual(await access('read',{},null,transferred),{error:'access'});
  await db.exec('reset role');await db.query('update private.vehicle_profiles set owner_id=$1 where workshop_id=$2',[original,w]);await db.query('update private.members set active=false where workshop_id=$1 and user_id=$2',[w,admin]);assert.deepEqual(await access('read',{},null,transferred),{error:'access'});await db.exec('reset role');await db.query('update private.members set active=true where workshop_id=$1 and user_id=$2',[w,admin]);
 });
 await test('Complete archive includes grant hashes, customer decisions and audit without raw credentials',async()=>{
  await login(admin,ad);const a=(await db.query('select public.export_workshop($1,$2) r',[w,dev])).rows[0].r;assert.equal(a.databaseVersion,13);assert.ok(a.tables.portal_grants.length>=4);assert.equal(a.tables.portal_receipts.length,1);assert.equal(a.tables.audit.filter(x=>x.kind==='portal_decision').length,1);assert.equal(a.tables.orders[0].data.quoteLedger.decisions[0].channel,'portal');
 });
 console.log(`${passed} customer portal checks passed in PostgreSQL/PGlite with synthetic Auth.`);
}finally{await db.close();}
