import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const db=new PGlite();let seq=1,passed=0;const id=()=>`00000000-0000-4000-8000-${String(seq++).padStart(12,'0')}`;
const w=id(),admin=id(),tech=id(),office=id(),desk=id(),phone=id(),officeDesk=id(),oid=id(),tid=id(),item=id();
await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);create table auth.sessions(id uuid primary key,user_id uuid not null);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
for(const file of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort()) await db.exec(await readFile(new URL(`../supabase/migrations/${file}`,import.meta.url),'utf8'));
await db.query('insert into auth.users values($1),($2),($3)',[admin,tech,office]);
await db.query("insert into private.workshops(id,name,settings) values($1,'Fictional pricing',$2)",[w,{hourlyRateCents:4801,taxBps:2100,internalHourlyCostCents:2200,internalCostKnown:true}]);
await db.query("insert into private.members values($1,$2,'Admin','admin',true,true),($1,$3,'Tech','technician',false,true),($1,$4,'Office','office',true,true)",[w,admin,tech,office]);
await db.query("insert into private.catalog(workshop_id,id,reference,description,unit,price_cents,cost_cents,stock_milli) values($1,$2,'FICT-OIL','Fictional oil','L',1450,650,10000)",[w,item]);
await db.query('insert into private.catalog_details values($1,$2,2100,true,true,\'Fictional\')',[w,item]);
let who,device;
async function login(user,dev){who=user;device=dev;await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[dev,user]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:dev})]);await db.exec('set role authenticated');}
async function snap(){return (await db.query('select public.device_snapshot($1,$2) r',[w,device])).rows[0].r;}
async function push(kind,p,{revision,opid=id()}={}){const s=await snap();const op={id:opid,orderId:oid,actorId:who,kind,at:new Date().toISOString(),baseRevision:revision??s.orders[0]?.revision??0,payload:p};const r=(await db.query('select public.apply_operation($1,$2,$3) r',[w,device,op])).rows[0].r;return {r,op};}
async function replay(op){return (await db.query('select public.apply_operation($1,$2,$3) r',[w,device,op])).rows[0].r;}
async function pricing(target,targetId,more={},opts={}){return push('pricing_review',{target,targetId,unitPriceCents:target==='labor'?4801:1450,taxBps:2100,discountBps:0,charge:true,reason:'Fictional review',...more},opts);}
async function test(name,fn){await fn();passed++;console.log(`PASS ${name}`);}
async function note(){await db.exec('reset role');const d=(await db.query('select data from private.orders where workshop_id=$1 and id=$2',[w,oid])).rows[0].data;const r=(await db.query('select private.note_snapshot($1) r',[d])).rows[0].r;await login(who,device);return r;}
try{
 await login(admin,desk);await snap();
 const receive=await push('receive',{plate:'FICT0008',country:'ES',vin:'',vehicle:'Fictional',engine:'Fictional',client:'Fictional client',phone:'',km:1,symptom:'Fictional',location:'Box',keys:'Panel',due:'Today',priority:'Normal',tasks:[{id:tid,title:'Fictional labor',assignees:[tech],estimateMinutes:30,internalCostCents:1,discountBps:10000}]});assert.equal(receive.r.status,'accepted');
 await test('Internal labor costs and initial prices come from validated workshop settings',async()=>{const t=(await snap()).orders[0].tasks[0];assert.equal(t.internalCostCents,2200);assert.equal(t.internalCostKnown,true);assert.equal(t.discountBps,0);assert.equal(t.priceVersion,1);});
 assert.equal((await push('authorize',{taskId:tid,approvedCents:50000,version:1,customer:'Fictional',evidence:'Fictional approval'})).r.status,'accepted');
 assert.equal((await push('billable',{taskId:tid,minutes:37,reason:'Fictional review'})).r.status,'accepted');
 const consume=await push('part',{taskId:tid,itemId:item,kind:'consume',quantityMilli:4500});assert.equal(consume.r.status,'accepted');const pid=consume.op.id;
 assert.equal((await push('return',{sourceId:pid,quantityMilli:500})).r.status,'accepted');
 await test('Discounts apply to frozen prices and remaining quantity, with deterministic per-line tax',async()=>{
  const a=await pricing('labor',tid,{discountBps:1250});assert.equal(a.r.status,'accepted');assert.deepEqual(await replay(a.op),a.r);
  assert.equal((await pricing('part',pid,{discountBps:1000})).r.status,'accepted');
  const n=await note();assert.equal(n.netCents,7811);assert.equal(n.taxCents,1640);assert.equal(n.totalCents,9451);assert.equal(n.lines[0].discountCents,370);assert.equal(n.lines[1].grossCents,5800);
  const s=await snap();assert.equal(s.orders[0].pricingReviews.length,2);assert.equal(s.orders[0].parts[0].costCents,650);
 });
 await test('No-charge consumption keeps stock and source costs and documents its reason',async()=>{
  const stock=(await snap()).catalog[0].stockMilli;const r=await pricing('part',pid,{charge:false,reason:'Fictional goodwill'});assert.equal(r.r.status,'accepted');
  const s=await snap();assert.equal(s.catalog[0].stockMilli,stock);assert.equal(s.orders[0].parts[0].costCents,650);assert.equal(s.orders[0].parts[0].quantityMilli,4500);
  const p=(await note()).lines[1];assert.equal(p.netCents,0);assert.equal(p.taxCents,0);assert.equal(p.discountCents,5800);assert.equal(p.noChargeReason,'Fictional goodwill');
 });
 await test('Stale concurrent review preserves its original as conflict and does not replace current prices',async()=>{
  const before=(await snap()).orders[0];const r=await pricing('part',pid,{unitPriceCents:1600},{revision:before.revision-1});assert.equal(r.r.status,'conflict');assert.match(r.r.reason,/Revision conflict/);
  const after=(await snap()).orders[0];assert.equal(after.revision,before.revision);assert.deepEqual(after.pricingReviews,before.pricingReviews);
 });
 await test('Recharging a gift invalidates the old authorization and preserves its exact evidence',async()=>{
  const r=await pricing('part',pid,{charge:true});assert.equal(r.r.status,'accepted');const s=await snap();const t=s.orders[0].tasks[0];assert.equal(t.authorized,false);assert.equal(t.authorization,null);assert.equal(t.previousAuthorizations[0].version,1);assert.equal(t.priceVersion,5);
  await assert.rejects(()=>note(),/Unauthorized/);await login(admin,desk);
  assert.equal((await push('authorize',{taskId:tid,approvedCents:50000,version:9,customer:'Fictional',evidence:'New fictional decision',priceVersion:0})).r.status,'accepted');
  assert.equal((await snap()).orders[0].tasks[0].authorization.priceVersion,5);
 });
 await test('Invalid discounts, missing reasons, forged costs and unsupported targets are retained without mutation',async()=>{
  const before=(await snap()).orders[0];
  for(const more of [{discountBps:10001},{reason:''},{costCents:1},{target:'return'}]){const r=await pricing('part',pid,more);assert.equal(r.r.status,'conflict');}
  const s=await snap();assert.equal(s.orders[0].revision,before.revision);assert.deepEqual(s.orders[0].parts,before.parts);
 });
 await test('Operator access hides price reviews, discounts and internal costs and cannot edit prices',async()=>{
  await login(tech,phone);const s=await snap();const text=JSON.stringify(s);for(const key of ['unitPriceCents','pricingReviews','discountBps','internalCostCents','costCents'])assert.equal(text.includes(`"${key}"`),false,key);
  await assert.rejects(()=>pricing('part',pid),/Office/);await login(admin,desk);
 });
 await test('Office without cost permission can inspect prices while internal cost snapshots remain absent',async()=>{
  await login(office,officeDesk);const s=await snap();assert(s.orders[0].pricingReviews);assert.equal(s.orders[0].tasks[0].internalCostCents,undefined);assert.equal(s.orders[0].parts[0].costCents,undefined);await login(admin,desk);
 });
 await test('Portable export preserves review evidence, returned quantities and frozen costs',async()=>{
  const a=(await db.query('select public.export_workshop($1,$2) r',[w,device])).rows[0].r;const d=a.tables.orders[0].data;assert.equal(d.pricingReviews.length,4);assert.equal(d.parts[0].costCents,650);assert.equal(d.parts[1].quantityMilli,500);assert(a.tables.operations.some(o=>o.operation.kind==='pricing_review'&&o.status==='conflict'));
 });
 await test('Late price reviews preserve issued personal documents and enter recovery evidence',async()=>{
  await db.exec('reset role');const doc={type:'work_note',netCents:1234,taxCents:100,totalCents:1334};await db.query("update private.orders set data=data||jsonb_build_object('document',$3::jsonb) where workshop_id=$1 and id=$2",[w,oid,doc]);await login(admin,desk);
  const r=await pricing('part',pid);assert.equal(r.r.status,'late');assert.deepEqual((await snap()).orders[0].document,doc);
 });
 console.log(`${passed} pricing PostgreSQL integration tests passed (local PGlite, synthetic Auth)`);
}finally{await db.close();}
