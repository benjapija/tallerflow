import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const db = new PGlite();
let passed=0, seq=10;
const id=()=>`00000000-0000-4000-8000-${String(seq++).padStart(12,'0')}`;
const w=id(), w2=id(), a=id(), b=id(), office=id(), foreign=id(), order=id(), task=id(), taskB=id(), item=id(), da=id(), dbb=id(), desk=id();
await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth; create table auth.users(id uuid primary key); create table auth.sessions(id uuid primary key,user_id uuid not null);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;`);
await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
for(const f of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort()) await db.exec(await readFile(new URL(`../supabase/migrations/${f}`,import.meta.url),'utf8'));
await db.query('insert into auth.users values($1),($2),($3),($4)',[a,b,office,foreign]);
await db.query("insert into private.workshops(id,name) values($1,'Synthetic A'),($2,'Synthetic B')",[w,w2]);
await db.query("insert into private.members values($1,$2,'A','technician',false,true),($1,$3,'B','technician',false,true),($1,$4,'Office','admin',true,true),($5,$6,'Foreign','admin',true,true)",[w,a,b,office,w2,foreign]);
await db.query("insert into private.catalog(workshop_id,id,reference,description,unit,price_cents,cost_cents,stock_milli) values($1,$2,'OIL','Oil','L',1450,650,1000)",[w,item]);
let who=office, device=desk;const sessions=new Map();
async function login(user,dev,session=sessions.get(dev)??dev){sessions.set(dev,session);who=user;device=dev;await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[session,user]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:session})]);await db.exec('set role authenticated');}
async function snap(ws=w,dev=device){return (await db.query('select public.device_snapshot($1,$2) r',[ws,dev])).rows[0].r;}
async function rev(){return (await snap()).orders.find(o=>o.id===order).revision;}
async function push(kind,payload,opts={}) {
 const op={id:opts.id??id(),orderId:order,actorId:who,kind,at:new Date().toISOString(),baseRevision:opts.rev??await rev(),payload};
 const result=(await db.query('select public.apply_operation($1,$2,$3) r',[w,device,op])).rows[0].r;return {op,result};
}
async function cmd(action,payload,cid=id(),ws=w){return (await db.query('select public.reliability_command($1,$2,$3,$4,$5) r',[ws,device,cid,action,payload])).rows[0].r;}
async function test(name,fn){await fn();passed++;console.log(`PASS ${name}`);}
async function close(reason=null){return cmd('request_close',{orderId:order,revision:await rev(),exceptionReason:reason});}
async function ack(req,cid=id()){return cmd('ack_close',{orderId:order,requestId:req.requestId,revision:req.revision,locallyFrozen:true},cid);}

async function manage(action,payload,cid=id(),revision=null){
 const p={...payload,revision:revision??(await snap()).managementRevision};
 return (await db.query('select public.management_command($1,$2,$3,$4,$5) r',[w,device,cid,action,p])).rows[0].r;
}
const settings={hourlyRateCents:6000,taxBps:1000,internalHourlyCostCents:2500,internalCostKnown:true};
const member=(user,role,extra={})=>({userId:user,name:'Synthetic user',role,active:true,seePrices:false,seeCosts:false,reason:'Synthetic permission review',...extra});
try{
 await login(office,desk);await snap();
 const data={plate:'1234 ABC',country:'ES',vin:'',vehicle:'Synthetic',engine:'2020',client:'Synthetic',phone:'',km:0,symptom:'Test',location:'Bay',keys:'Board',due:'Today',priority:'Normal',tasks:[{id:task,title:'Task A',assignees:[a,b],estimateMinutes:30},{id:taskB,title:'Task B',assignees:[b],estimateMinutes:30}]};
 assert.equal((await push('receive',data,{rev:0})).result.status,'accepted');
 for(const tid of [task,taskB])await push('authorize',{taskId:tid,approvedCents:50000,version:1,customer:'Synthetic',evidence:'Synthetic consent'});
 await test('Administrator settings update is audited; stale concurrent update is rejected',async()=>{
  const old=(await snap()).managementRevision;
  await manage('settings_save',{settings,reason:'Synthetic rates'},id(),old);
  await assert.rejects(()=>manage('settings_save',{settings,reason:'Stale'},id(),old),/revision conflict/);
  assert.equal((await snap()).settings.hourlyRateCents,6000);
 });
 await test('Settings reject missing or excessive tax without partial changes',async()=>{
  const revision=(await snap()).managementRevision;
  await assert.rejects(()=>manage('settings_save',{settings:{...settings,taxBps:10001},reason:'Invalid'}),/out of range/);
  await assert.rejects(()=>manage('settings_save',{settings:{...settings,taxBps:null},reason:'Invalid'}),/integer/);
  assert.equal((await snap()).managementRevision,revision);
 });
 await test('Command retries are idempotent and altered payload is rejected',async()=>{
  const cid=id(),revision=(await snap()).managementRevision,p={settings,reason:'Idempotent'};
  assert.deepEqual(await manage('settings_save',p,cid,revision),await manage('settings_save',p,cid,revision));
  await assert.rejects(()=>manage('settings_save',{...p,reason:'Changed'},cid,revision),/ID reused/);
 });
 await test('Last administrator cannot disable or demote itself',async()=>{
  await assert.rejects(()=>manage('member_save',member(office,'office')),/active administrator/);
  await assert.rejects(()=>manage('member_save',member(office,'admin',{active:false})),/active administrator/);
 });
 await login(a,da);await snap();
 await test('Technician has neither administration API nor hidden tariff/cost data',async()=>{
  await assert.rejects(()=>manage('settings_save',{settings,reason:'Forbidden'}),/Administrator/);
  const s=await snap();assert.equal(s.settings.hourlyRateCents,undefined);assert.equal(s.settings.internalHourlyCostCents,undefined);
  assert.equal(s.catalog[0].costCents,undefined);
 });
 await login(office,desk);
 await test('Configurable price and cost access is enforced by the server',async()=>{
  await assert.rejects(()=>manage('member_save',member(a,'technician',{seeCosts:true})),/requires price/);
  await manage('member_save',member(a,'technician',{seePrices:true,seeCosts:true}));await login(a,da);
  let s=await snap();assert.equal(s.catalog[0].costCents,650);assert.equal(s.settings.internalHourlyCostCents,2500);
  await login(office,desk);await manage('member_save',member(a,'technician',{seePrices:true}));await login(a,da);
  s=await snap();assert.equal(s.catalog[0].priceCents,1450);assert.equal(s.catalog[0].costCents,undefined);assert.equal(s.settings.internalHourlyCostCents,undefined);
 });
 await login(office,desk);
 let savedItem={id:item,reference:'OIL',description:'Oil revised',unit:'L',priceCents:2000,costCents:900,stockMilli:5000,minMilli:1000,taxBps:1000,costKnown:true,active:true,supplier:'Synthetic'};
 await test('Catalog adjustment retains previous movements and frozen prices',async()=>{
  await login(a,da);let prior=await push('part',{taskId:task,itemId:item,kind:'consume',quantityMilli:500});assert.equal(prior.result.status,'accepted');
  await login(office,desk);await manage('catalog_save',{item:savedItem,reason:'Synthetic stock count'});
  let s=await snap(),o=s.orders[0];assert.equal(o.parts[0].priceCents,1450);
  assert.equal(s.catalog[0].stockMilli-o.parts.reduce((sum,p)=>sum+(p.kind==='consume'?p.quantityMilli:0),0),5000);
  await login(a,da);assert.equal((await push('part',{taskId:task,itemId:item,kind:'consume',quantityMilli:250})).result.status,'accepted');
  s=await snap();assert.equal(s.orders[0].parts[1].priceCents,2000);assert.equal(s.orders[0].parts[1].taxBps,1000);
 });
 await login(office,desk);
 await test('Duplicate catalog references and inactive consumption are prevented',async()=>{
  await assert.rejects(()=>manage('catalog_save',{item:{...savedItem,id:id(),reference:'oil'},reason:'Duplicate'}),/Duplicate/);
  await manage('catalog_save',{item:{...savedItem,active:false},reason:'Deactivated'});await login(a,da);
  const r=await push('part',{taskId:task,itemId:item,kind:'consume',quantityMilli:100});assert.equal(r.result.status,'conflict');assert.match(r.result.reason,/deactivated/);
  await login(office,desk);await manage('catalog_save',{item:savedItem,reason:'Available'});
 });
 let templateId=id();
 await test('Versioned templates prepare unauthorized tasks after compatibility review',async()=>{
  const tpl={id:templateId,name:'Synthetic service',active:true,vehicleRule:'Synthetic',engineRule:'2020',tasks:[{title:'Inspection',estimateMinutes:30,references:[{itemId:item,quantityMilli:500}]}]};
  await manage('template_save',{template:tpl,reason:'Synthetic template'});
  const ids=[id()];const p={templateId,templateVersion:1,taskIds:ids,assignees:[a,b],compatibilityChecked:true,reason:'Checked'};
  const r=await push('template_apply',p);assert.equal(r.result.status,'accepted');
  const t=(await snap()).orders[0].tasks.find(t=>t.id===ids[0]);assert.equal(t.authorized,false);assert.equal(t.billableMinutes,0);assert.equal(t.suggestedReferences[0].quantityMilli,500);
  await manage('template_save',{template:tpl,reason:'New version'});
  assert.equal((await push('template_apply',{...p,taskIds:[id()]})).result.status,'conflict');
  assert.equal((await snap()).orders[0].tasks.find(t=>t.id===ids[0]).templateVersion,1);
 });
 await test('Tasks reject foreign assignees and retain evidence on stale editing',async()=>{
  const p={taskId:task,title:'Task A',estimateMinutes:45,assignees:[a,foreign],reason:'Invalid'};
  assert.equal((await push('task_edit',p)).result.status,'conflict');
  assert.equal((await push('task_edit',{...p,assignees:[a,b]},{rev:0})).result.status,'conflict');
  assert.deepEqual((await snap()).orders[0].tasks[0].assignees,[a,b]);
 });
 await login(a,da);let timer=await push('start',{taskId:task});assert.equal(timer.result.status,'accepted');await login(office,desk);
 await test('Active timers prevent reassignment and account removal',async()=>{
  assert.equal((await push('task_edit',{taskId:task,title:'Task A',assignees:[b],estimateMinutes:45,reason:'Reassign'})).result.status,'conflict');
  await assert.rejects(()=>manage('member_save',member(a,'technician',{active:false})),/timers first/);
 });
 await login(a,da);await push('stop',{sessionId:timer.op.id});
 await test('Task blocks require a responsible member and stop starts until resolved',async()=>{
  const p={taskId:task,reason:'Waiting',nextAction:'Review supplier',ownerId:office};
  assert.equal((await push('task_block',p)).result.status,'accepted');
  assert.equal((await push('start',{taskId:task})).result.status,'conflict');
  assert.equal((await push('task_unblock',{taskId:task,reason:'Parts arrived'})).result.status,'accepted');
 });
 await login(office,desk);
 await test('Scope edits preserve prior authorization and other task consent',async()=>{
  assert.equal((await push('task_edit',{taskId:task,title:'Revised scope',estimateMinutes:60,assignees:[a,b],reason:'Human expansion'})).result.status,'accepted');
  const tasks=(await snap()).orders[0].tasks;assert.equal(tasks[0].authorized,false);assert.equal(tasks[0].previousAuthorizations.length,1);assert.equal(tasks[1].authorized,true);
  assert.equal((await snap()).orders[0].parts.length,2);
 });
 await test('Cancellation retains tasks and refuses work with recorded time/consumption',async()=>{
  assert.equal((await push('task_cancel',{taskId:task,reason:'Cannot erase work'})).result.status,'conflict');
  assert.equal((await push('task_cancel',{taskId:taskB,reason:'Customer declined'})).result.status,'accepted');
  assert.equal((await push('authorize',{taskId:taskB,approvedCents:1000,version:2,customer:'Synthetic',evidence:'Invalid'})).result.status,'conflict');
 });
 await test('Priority/location updates are scoped, audited and require latest revision',async()=>{
  const p={priority:'Urgente',due:'Tomorrow',location:'Bay 2',keys:'Board A',reason:'Customer planning'};
  assert.equal((await push('order_plan',p)).result.status,'accepted');assert.equal((await snap()).orders[0].priority,'Urgente');
  await login(a,da);assert.equal((await push('order_plan',p)).result.status,'conflict');
 });
 await login(office,desk);
 await test('Backup includes management data, versions and permissions',async()=>{
  const s=(await db.query('select public.export_workshop($1,$2) r',[w,desk])).rows[0].r;
  assert.equal(s.databaseVersion,12);assert.equal(s.tables.templates[0].version,2);assert.ok(s.tables.member_permissions.length);assert.ok(s.tables.management_state[0].revision>0);
 });
 console.log(`${passed} administration and task checks passed. Hosted Auth and actual devices require separate validation.`);
}finally{await db.close();}
