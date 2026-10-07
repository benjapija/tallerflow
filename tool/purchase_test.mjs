import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';import assert from 'node:assert/strict';
let n=11000,passed=0;const id=()=>`00000000-0000-4000-8000-${String(n++).padStart(12,'0')}`;
const w=id(),office=id(),tech=id(),other=id(),od=id(),td=id(),xd=id(),order=id(),task=id(),inspection=id(),row=id();
const db=new PGlite();
await db.exec("create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);create table auth.sessions(id uuid primary key,user_id uuid not null);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;");
await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
for(const f of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(new URL('../supabase/migrations/'+f,import.meta.url),'utf8'));
await db.query('insert into auth.users values($1),($2),($3)',[office,tech,other]);
await db.query("insert into private.workshops(id,name) values($1,'Fictional purchases')",[w]);
await db.query("insert into private.members values($1,$2,'Office','admin',true,true),($1,$3,'Technician','technician',false,true),($1,$4,'Other','technician',false,true)",[w,office,tech,other]);
let actor,device;
async function login(u,d){await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[d,u]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[u]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:u,session_id:d})]);await db.exec('set role authenticated');actor=u;device=d;await snap();}
const snap=async()=>(await db.query('select public.device_snapshot($1,$2) r',[w,device])).rows[0].r;
const command=async(action,p)=>(await db.query('select public.reliability_command($1,$2,$3,$4,$5) r',[w,device,id(),action,p])).rows[0].r;
async function op(kind,p,{opid=id(),revision}={}){const s=await snap();const o=s.orders.find(o=>o.id===order);const record={id:opid,orderId:order,actorId:actor,kind,at:new Date().toISOString(),baseRevision:revision??o?.revision??0,payload:p};return {record,result:(await db.query('select public.apply_operation($1,$2,$3) r',[w,device,record])).rows[0].r};}

const item=id(),purchase=id(),line=id();
const test=async(name,f)=>{await f();passed++;console.log('PASS '+name);};
const stock=async()=> (await snap()).catalog.find(x=>x.id===item).stockMilli;
const ledger=async()=> (await snap()).purchaseLedger;
const inventory=async(action,p,cid=id())=> (await db.query('select public.inventory_command($1,$2,$3,$4,$5) r',[w,device,cid,action,p])).rows[0].r;
const draft=()=>({revision:0,at:new Date().toISOString(),id:purchase,supplier:'Fictional supplier',reference:'Manual request',expectedAt:'2026-10-08T00:00:00Z',orderId:null,reason:'Fictional stock replenishment',lines:[{id:line,itemId:item,packageSizeMilli:5000,packagesMilli:2000,unitCostCents:650}]});
const movement=async(packages)=>({revision:(await ledger()).revision,at:new Date().toISOString(),purchaseId:purchase,lineId:line,packagesMilli:packages,reference:'Fictional delivery note',reason:'Physically counted in test'});
try {
 await db.query("insert into private.catalog(workshop_id,id,reference,description,unit,price_cents,cost_cents,stock_milli) values($1,$2,'OIL','Fictional oil','L',1200,650,0)",[w,item]);
 await login(office,od);let first,receipt;
 await test('Request snapshots packages and cost without adding stock',async()=>{first=draft();assert.equal((await inventory('purchase_create',first)).revision,1);assert.equal(await stock(),0);assert.equal((await ledger()).orders[0].lines[0].requestedMilli,10000);});
 await test('Partial receipt applies five litres with original cost',async()=>{receipt=await movement(1000);assert.equal((await inventory('purchase_receive',receipt)).revision,2);assert.equal(await stock(),5000);assert.equal((await ledger()).movements[0].costCents,3250);});
 await test('Lost-response receipt is applied once and altered command identity fails',async()=>{const p=await movement(500),cid=id();const r=await inventory('purchase_receive',p,cid);assert.deepEqual(await inventory('purchase_receive',p,cid),r);await assert.rejects(()=>inventory('purchase_receive',{...p,packagesMilli:501},cid),/Command ID reused/);assert.equal(await stock(),7500);});
 await test('Stale, over-received and unknown fields are refused without changing stock',async()=>{const p=await movement(1000);for(const v of [{...p,revision:0},p,{...p,approvedCents:1}])await assert.rejects(()=>inventory('purchase_receive',v));assert.equal(await stock(),7500);});
 await test('Supplier returns retain receipt, reduce stock once and cannot exceed original remainder',async()=>{const p=await movement(500),cid=id();await inventory('supplier_return',p,cid);await inventory('supplier_return',p,cid);assert.equal(await stock(),5000);assert.equal((await ledger()).movements[0].quantityMilli,5000);const excessive=await movement(1001);await assert.rejects(()=>inventory('supplier_return',excessive));});
 await test('Operators and office without cost permission cannot view or modify purchases',async()=>{await login(tech,td);assert.equal((await snap()).purchaseLedger,undefined);await assert.rejects(()=>inventory('purchase_receive',{...receipt,revision:4}),/permission/i);await db.exec('reset role');await db.query("update private.members set role='office' where workshop_id=$1 and user_id=$2",[w,office]);await login(office,od);assert.equal((await snap()).purchaseLedger,undefined);await assert.rejects(()=>inventory('purchase_receive',{...receipt,revision:4}),/permission/i);await db.exec('reset role');await db.query("update private.members set role='admin' where workshop_id=$1 and user_id=$2",[w,office]);await login(office,od);});
 await test('Private stock helpers and state table are inaccessible directly',async()=>{await assert.rejects(()=>db.exec('select * from private.inventory_state'),/permission denied/);await assert.rejects(()=>db.query('select private.purchase_quantity(1,1)'),/permission denied/);});
 await test('Complete export contains purchase ledger, movement receipts and updated stock',async()=>{const a=(await db.query('select public.export_workshop($1,$2) r',[w,device])).rows[0].r;assert.equal(a.databaseVersion,12);assert.equal(a.tables.inventory_state[0].data.movements.length,3);assert.equal(a.tables.catalog[0].stock_milli,5000);assert.equal(a.tables.audit.filter(x=>x.kind==='supplier_return').length,1);});
 console.log(`${passed} purchase checks passed in PostgreSQL/PGlite with synthetic Auth.`);
} finally {await db.close();}
