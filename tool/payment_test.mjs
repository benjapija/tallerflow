import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';import assert from 'node:assert/strict';
let n=9000,passed=0;const id=()=>`00000000-0000-4000-8000-${String(n++).padStart(12,'0')}`;
const w=id(),office=id(),tech=id(),other=id(),od=id(),td=id(),xd=id(),order=id(),task=id(),inspection=id(),row=id();
const db=new PGlite();
await db.exec("create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);create table auth.sessions(id uuid primary key,user_id uuid not null);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;");
await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
for(const f of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(new URL('../supabase/migrations/'+f,import.meta.url),'utf8'));
await db.query('insert into auth.users values($1),($2),($3)',[office,tech,other]);
await db.query("insert into private.workshops(id,name) values($1,'Fictional payments')",[w]);
await db.query("insert into private.members values($1,$2,'Office','admin',true,true),($1,$3,'Technician','technician',false,true),($1,$4,'Other','technician',false,true)",[w,office,tech,other]);
let actor,device;
async function login(u,d){await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[d,u]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[u]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:u,session_id:d})]);await db.exec('set role authenticated');actor=u;device=d;await snap();}
const snap=async()=>(await db.query('select public.device_snapshot($1,$2) r',[w,device])).rows[0].r;
const command=async(action,p)=>(await db.query('select public.reliability_command($1,$2,$3,$4,$5) r',[w,device,id(),action,p])).rows[0].r;
async function op(kind,p,{opid=id(),revision}={}){const s=await snap();const o=s.orders.find(o=>o.id===order);const record={id:opid,orderId:order,actorId:actor,kind,at:new Date().toISOString(),baseRevision:revision??o?.revision??0,payload:p};return {record,result:(await db.query('select public.apply_operation($1,$2,$3) r',[w,device,record])).rows[0].r};}

const test=async(name,f)=>{await f();passed++;console.log('PASS '+name);};
const get=async()=>(await snap()).orders.find(o=>o.id===order);
const pay=(amount)=>({amountCents:amount,method:'cash',paidAt:new Date().toISOString(),reference:'Fictional receipt',reason:'Fictional money already received'});
const refund=(source,amount)=>{const p=pay(amount);delete p.method;return {...p,sourceId:source,reason:'Fictional money already returned'};};
try {
 await login(office,od);
 assert.equal((await op('receive',{plate:'9901FIC',country:'ES',vin:'PAYMENTS-FICTIONAL',vehicle:'Fictional',engine:'2020',client:'Fictional private owner',phone:'600000000',km:10,symptom:'Fictional symptom',tasks:[{id:task,title:'Check',assignees:[tech],estimateMinutes:30}]})).result.status,'accepted');
 await test('No receipt before work-note issuance',async()=>{const r=await op('payment_record',pay(100));assert.equal(r.result.status,'conflict');await command('resolve',{operationId:r.record.id,outcome:'archive',reason:'Fictional rejected test: no money received',revision:(await get()).revision});});
 assert.equal((await op('authorize',{taskId:task,approvedCents:50000,version:1,customer:'Fictional owner',evidence:'Fictional telephone approval'})).result.status,'accepted');
 await login(tech,td);assert.equal((await op('finish_task',{taskId:task})).result.status,'accepted');
 await login(office,od);assert.equal((await op('billable',{taskId:task,minutes:60,reason:'Fictional completed repair'})).result.status,'accepted');
 assert.equal((await op('review_parts',{})).result.status,'accepted');assert.equal((await op('quality',{result:'Verified',pendingSymptoms:''})).result.status,'accepted');
 const req=await command('request_close',{orderId:order,revision:(await get()).revision});
 const ack=()=>command('ack_close',{orderId:order,requestId:req.requestId,revision:req.revision,locallyFrozen:true});
 await ack();await login(tech,td);await ack();await login(office,od);
 const document=(await command('issue',{orderId:order,requestId:req.requestId})).document;assert.equal(document.totalCents,5808);
 let first;
 await test('Partial payment preserves issued note and integer balance',async()=>{first=await op('payment_record',pay(2001));assert.equal(first.result.status,'accepted');const o=await get();assert.equal(o.payments.length,1);assert.equal(o.payments[0].orderId,order);assert.deepEqual(o.document,document);});
 await test('Lost response replays once; altered idempotency content fails',async()=>{assert.deepEqual((await db.query('select public.apply_operation($1,$2,$3) r',[w,device,first.record])).rows[0].r,first.result);await assert.rejects(()=>db.query('select public.apply_operation($1,$2,$3)',[w,device,{...first.record,payload:pay(1)}]),/Idempotency/);assert.equal((await get()).payments.length,1);});
 await test('Two partial reversals retain original and reject an excessive third',async()=>{assert.equal((await op('payment_reverse',refund(first.record.id,500))).result.status,'accepted');assert.equal((await op('payment_reverse',refund(first.record.id,501))).result.status,'accepted');assert.equal((await op('payment_reverse',refund(first.record.id,1001))).result.status,'conflict');assert.equal((await get()).payments[0].amountCents,2001);});
 await test('Stale revision, extra fields, overpayment and invalid date retain conflicts without changing ledger',async()=>{const before=(await get()).payments;for(const p of [{...pay(1),totalCents:1},pay(10000),pay(0),{...pay(1),paidAt:'2000-01-01T00:00:00Z'},{...pay(1),paidAt:'2100-01-01T00:00:00Z'},{...pay(1),method:'unknown'}])assert.equal((await op('payment_record',p)).result.status,'conflict');assert.equal((await op('payment_record',pay(1),{revision:0})).result.status,'conflict');assert.deepEqual((await get()).payments,before);});
 await test('Missing source and refund before original receipt are rejected',async()=>{assert.equal((await op('payment_reverse',refund(id(),1))).result.status,'conflict');assert.equal((await op('payment_reverse',{...refund(first.record.id,1),paidAt:document.issuedAt})).result.status,'conflict');});
 await test('Credit delivery records its reason and balance without creating money',async()=>{assert.equal((await op('deliver',{reason:'Fictional office explicitly authorizes credit'})).result.status,'accepted');const o=await get();assert.equal(o.delivery.outstandingCents,4808);assert.equal(o.delivery.creditAuthorized,true);assert.equal(o.delivery.paymentStatus,'partial');assert.equal(o.payments.length,3);});
 await test('Settlement after delivery preserves original credit decision and work note',async()=>{const before=(await get()).delivery;assert.equal((await op('payment_record',pay(4808))).result.status,'accepted');const o=await get();assert.deepEqual(o.delivery,before);assert.deepEqual(o.document,document);assert.equal((await op('deliver',{reason:'Attempt to rewrite delivery'})).result.status,'conflict');assert.equal((await op('payment_record',pay(1))).result.status,'conflict');});
 await test('Operators with price permission never see private receipts or delivery evidence and cannot record money',async()=>{await db.exec('reset role');await db.query('update private.members set see_prices=true where workshop_id=$1 and user_id=$2',[w,tech]);await login(tech,td);const o=await get();assert.equal(o.payments,undefined);assert.equal(o.delivery,undefined);assert.equal((await op('payment_record',pay(1))).result.status,'conflict');await assert.rejects(()=>db.query('select private.payment_balance($1)',[{}]),/permission denied/);await login(office,od);});
 await test('Complete backup contains receipts, linked reversals, original document and audit',async()=>{const a=(await db.query('select public.export_workshop($1,$2) r',[w,device])).rows[0].r;assert.equal(a.tables.orders[0].data.payments.length,4);assert.deepEqual(a.tables.documents[0].snapshot,document);assert.equal(a.tables.audit.filter(x=>x.kind==='payment_reverse').length,2);assert.deepEqual(a.tables.operations.find(x=>x.id===first.record.id).operation,first.record);});
 console.log(`${passed} payment checks passed in PostgreSQL/PGlite with synthetic Auth.`);
} finally {await db.close();}
