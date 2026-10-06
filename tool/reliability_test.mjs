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
try {
 await login(office,desk); await snap();
 const data={plate:'1234 abc',country:'ES',vin:'',vehicle:'Synthetic',engine:'2020',client:'Synthetic client',phone:'',km:0,symptom:'Synthetic only',location:'Bay',keys:'Board',due:'Today',priority:'Normal',tasks:[{id:task,title:'Task A',assignees:[a],estimateMinutes:30},{id:taskB,title:'Task B',assignees:[b],estimateMinutes:30}]};
 assert.equal((await push('receive',data,{rev:0})).result.status,'accepted');
 for(const t of [task,taskB]) assert.equal((await push('authorize',{taskId:t,approvedCents:50000,version:1,customer:'Synthetic client',evidence:'Phone'})).result.status,'accepted');
 await login(a,da); await snap(); await login(b,dbb); await snap();
 await test('Downloads enrol two technicians and office; direct privileged helpers denied',async()=>{
  await assert.rejects(()=>db.query('select private.apply_record($1,$2,$3,$4)',[w,dbb,{},office]),/permission denied/);
  await assert.rejects(()=>db.exec('delete from private.order_devices'),/permission denied/);
 });
 await login(a,da); const first=await push('part',{taskId:task,itemId:item,kind:'consume',quantityMilli:900});
 assert.equal(first.result.status,'accepted');
 await login(b,dbb); let stock;
 await test('Concurrent last-stock consumption is retained as conflict without negative stock',async()=>{
  stock=await push('part',{taskId:taskB,itemId:item,kind:'consume',quantityMilli:300});assert.equal(stock.result.status,'conflict');assert.match(stock.result.reason,/stock/i);
  assert.equal((await snap()).orders[0].parts.length,1);
 });
 await test('Same UUID after lost response produces one effect',async()=>{
  await login(a,da);const r=(await db.query('select public.apply_operation($1,$2,$3) r',[w,da,first.op])).rows[0].r;assert.equal(r.status,'accepted');assert.equal((await snap()).orders[0].parts.length,1);
 });
 await test('Technician cannot resolve incidents or retire devices',async()=>{
  await assert.rejects(()=>cmd('resolve',{operationId:stock.op.id,outcome:'archive',reason:'Unauthorized',revision:0}),/Office permission/);
  await assert.rejects(()=>cmd('retire_device',{deviceId:dbb,reason:'Unauthorized'}),/Office permission/);
 });
 await push('return',{sourceId:first.op.id,quantityMilli:400}); await login(office,desk);
 await test('Office retries with original actor, preserving evidence and resolution audit',async()=>{
  const r=await cmd('resolve',{operationId:stock.op.id,outcome:'retry',reason:'Return verified; stock now available',revision:await rev()});
  assert.ok(r.correctionId); const s=await snap();const i=s.incidents.find(i=>i.operation.id===stock.op.id);
  assert.deepEqual(i.operation,stock.op);assert.equal(i.resolution.responsibleId,office);assert.equal(i.resolution.correctionId,r.correctionId);
  assert.equal(s.orders[0].parts.find(p=>p.id===r.correctionId).actorId,b);
 });
 await login(b,dbb);
 await test('Original device receives resolution receipt and can reconcile its preserved queue',async()=>{
  assert.equal((await snap()).receipts.find(r=>r.id===stock.op.id).resolved,true);
 });
 await login(a,da);const timer=await push('start',{taskId:task});await login(office,desk);let req=await close();
 await login(a,da);
 await test('Active timer prevents acknowledgement',async()=>{await assert.rejects(()=>ack(req),/Stop timers/);});
 await push('stop',{sessionId:timer.op.id});
 await test('Change during closure invalidates request and old confirmation',async()=>{await assert.rejects(()=>ack(req),/Obsolete/);assert.equal((await snap()).closures.find(c=>c.id===req.requestId).status,'invalidated');});
 await push('finish_task',{taskId:task}); await login(b,dbb);await push('finish_task',{taskId:taskB});
 await login(office,desk);await push('billable',{taskId:task,minutes:60,reason:'Human review'});await push('review_parts',{});await push('quality',{result:'Verified',pendingSymptoms:''});
 req=await close();await ack(req);await login(a,da);await ack(req);await login(office,desk);
 await test('Offline second technician blocks issue despite office empty queue',async()=>{await assert.rejects(()=>cmd('issue',{orderId:order,requestId:req.requestId}),/Unreconciled/);});
 await login(b,dbb);const ackId=id();await ack(req,ackId);
 await test('Lost acknowledgement response can be retried idempotently',async()=>{assert.equal((await ack(req,ackId)).confirmed,true);});
 await login(office,desk);
 await test('New device enrolment invalidates fully confirmed request',async()=>{
  const replacement=id();await login(office,replacement);await snap();await login(office,desk);await assert.rejects(()=>cmd('issue',{orderId:order,requestId:req.requestId}),/Active reconciled/);
  await cmd('retire_device',{deviceId:replacement,reason:'Synthetic unused replacement retired'});
 });
 await test('Retirement never counts as normal reconciliation',async()=>{await assert.rejects(()=>close(),/explicit administrator/);});
 req=await close('Synthetic retired replacement; no records captured; reviewed by administrator');
 await ack(req);await login(a,da);await ack(req);await login(b,dbb);await ack(req);await login(office,desk);
 await test('Device retirement invalidates affected closure and cannot silently bypass it',async()=>{
  await cmd('retire_device',{deviceId:dbb,reason:'Lost mobile B; records require review'});
  await assert.rejects(()=>cmd('issue',{orderId:order,requestId:req.requestId}),/Active reconciled/);
 });
 await login(b,dbb);
 const recovered={id:id(),orderId:order,kind:'note',actorId:b,at:new Date().toISOString(),baseRevision:0,payload:{text:'Actual recovered evidence from retired device'}};
 await test('Retired device cannot download or confirm, but recovered record is conserved',async()=>{
  await assert.rejects(()=>snap(),/Device retired/);await assert.rejects(()=>snap(w,id()),/Session belongs to retired/);await assert.rejects(()=>ack(req),/Active registered/);
  const r=(await db.query('select public.apply_operation($1,$2,$3) r',[w,dbb,recovered])).rows[0].r;assert.equal(r.status,'late');
 });
 await login(office,desk);
 await test('Retired record requires review; retry creates attributable correction before issue',async()=>{
  const r=await cmd('resolve',{operationId:recovered.id,outcome:'retry',reason:'Recovered observation checked',revision:await rev()});
  assert.ok(r.correctionId);assert.equal((await snap()).orders[0].notes.find(n=>n.id===r.correctionId).text,recovered.payload.text);
 });
 req=await close('B lost and synthetic replacement retired; recovered evidence reviewed; remaining loss risk accepted explicitly');
 await ack(req);await login(a,da);await ack(req);await login(office,desk);
 let doc, issueId=id();
 await test('Issue is atomic, computes frozen prices and labels administrative exception',async()=>{
  doc=(await cmd('issue',{orderId:order,requestId:req.requestId},issueId)).document;
  assert.equal(doc.netCents,5960);assert.equal(doc.taxCents,1251);assert.equal(doc.totalCents,7211);assert.ok(doc.closureException);assert.ok(doc.retiredDevices.includes(dbb));
 });
 await test('Issuing retry returns same document, without duplicate document rows',async()=>{
  assert.deepEqual((await cmd('issue',{orderId:order,requestId:req.requestId},issueId)).document,doc);
  await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from private.documents')).rows[0].n,1);await login(office,desk);
 });
 await login(a,da);let late;
 await test('Late operation after issue creates incident and leaves document unchanged',async()=>{late=await push('note',{text:'Late symptom'});assert.equal(late.result.status,'late');await login(office,desk);assert.deepEqual((await snap()).orders[0].document,doc);});
 await test('Late resolution cannot mutate emitted document, archive retains original and reason',async()=>{
  const payload={operationId:late.op.id,outcome:'retry',reason:'Must not modify document',revision:await rev()};
  await assert.rejects(()=>cmd('resolve',payload),/Issued document/);
  await cmd('resolve',{...payload,outcome:'archive',reason:'Preserved for follow-up correction order'});assert.deepEqual((await snap()).orders[0].document,doc);
 });
 await test('Authenticated clients and private helpers cannot bypass immutability',async()=>{
  await assert.rejects(()=>db.exec('delete from private.documents'),/permission denied/);
  await db.exec('reset role');await assert.rejects(()=>db.query("update private.orders set data=jsonb_set(data,'{document}','{}') where workshop_id=$1",[w]),/immutable/);
  await assert.rejects(()=>db.exec('delete from private.operations'),/immutable/);await login(office,desk);
 });
 await test('Commands and device snapshots isolate workshops and reject anonymous access',async()=>{
  await assert.rejects(()=>snap(w2),/Membership required/);await assert.rejects(()=>cmd('retire_device',{deviceId:dbb,reason:'Cross workshop'},id(),w2),/Membership required/);
  await db.exec('reset role;set role anon');await assert.rejects(()=>snap(),/permission denied/);await login(office,desk);
 });
 await test('Technician snapshots redact amounts in conflicts and documents',async()=>{
  await login(a,da);const s=await snap();assert.equal(JSON.stringify(s).includes('priceCents'),false);assert.equal(JSON.stringify(s).includes('totalCents'),false);
 });
 await test('Retired owner registers replacement idempotently without restoring old authority',async()=>{
  await login(b,dbb);const next=id(),cid=id();await assert.rejects(()=>cmd('replace_device',{newDeviceId:next},cid),/Fresh login/);await login(b,dbb,next);const r=await cmd('replace_device',{newDeviceId:next},cid);
  assert.equal(r.newDeviceId,next);assert.equal((await cmd('replace_device',{newDeviceId:next},cid)).newDeviceId,next);
  await assert.rejects(()=>snap(),/Device retired/);await login(b,next);assert.equal((await snap()).orders[0].document,undefined);await login(office,desk);assert.deepEqual((await snap()).orders[0].document,doc);
 });
 await test('Recovered offline reception is retained even if its order was never uploaded',async()=>{
  await login(office,desk);const oldDesk=id();await login(office,oldDesk);await snap();await login(office,desk);await cmd('retire_device',{deviceId:oldDesk,reason:'Lost secondary office tablet'});
  await login(office,oldDesk);const newOrder=id();const receive={id:id(),orderId:newOrder,kind:'receive',actorId:office,at:new Date().toISOString(),baseRevision:0,payload:data};
  assert.equal((await db.query('select public.apply_operation($1,$2,$3) r',[w,oldDesk,receive])).rows[0].r.status,'late');
  await login(office,desk);const incident=(await snap()).incidents.find(i=>i.operation.id===receive.id);assert.deepEqual(incident.operation,receive);
  const result=await cmd('resolve',{operationId:receive.id,outcome:'retry',reason:'Reception recovered and reviewed',revision:null});assert.ok(result.correctionId);
  assert.ok((await snap()).orders.find(o=>o.id===newOrder));
 });
 await test('Lost active timer remains explicit until office records actual end with evidence',async()=>{
  await login(office,desk);const extra=id(),startDevice=id();
  await db.exec('reset role');await db.query('insert into private.devices(workshop_id,id,user_id) values($1,$2,$3)',[w,startDevice,a]);
  const o=(await db.query('select id,data,revision from private.orders where workshop_id=$1 and id<>$2',[w,order])).rows[0];
  const started=new Date(Date.now()-120000).toISOString(),stopped=new Date(Date.now()-60000).toISOString();
  await db.query('insert into private.time_sessions values($1,$2,$3,$4,$5,$6,$7,null)',[w,extra,o.id,task,a,startDevice,started]);
  o.data.times.push({id:extra,taskId:task,actorId:a,start:started,end:null,source:'timer'});
  await db.query('update private.orders set data=$1 where workshop_id=$2 and id=$3',[o.data,w,o.id]);
  await db.query('insert into private.order_devices(workshop_id,order_id,device_id) values($1,$2,$3)',[w,o.id,startDevice]);await login(office,desk);
  await cmd('retire_device',{deviceId:startDevice,reason:'Lost with active timer'});
  assert.ok((await snap()).retiredTimers.find(t=>t.id===extra));
  await assert.rejects(()=>cmd('end_retired_timer',{sessionId:extra,end:stopped,reason:''}),/Actual stop/);
  await cmd('end_retired_timer',{sessionId:extra,end:stopped,reason:'Technician confirms actual stop; supervisor reviewed'});
  const s=await snap();assert.equal(s.retiredTimers.find(t=>t.id===extra),undefined);
  const time=s.orders.find(x=>x.id===o.id).times.find(t=>t.id===extra);assert.equal(time.recoveryAuthor,office);assert.equal(time.actorId,a);assert.equal(new Date(time.end).toISOString(),stopped);
 });
 await test('Fresh sign-in rebinds active identity and invalidates old closure confirmations',async()=>{
  await login(office,desk);const s=await snap(),o=s.orders.find(o=>o.id!==order);const req=await cmd('request_close',{orderId:o.id,revision:o.revision,exceptionReason:'Recovered office tablet and timer device retired; explicit synthetic exception'});
  await login(office,desk,id());const refreshed=await snap();assert.equal(refreshed.closures.find(c=>c.id===req.requestId).status,'invalidated');
 });
 await test('Retirement blocks all earlier sessions bound to the same physical identity',async()=>{
  await login(a,da,id());await snap();await login(office,desk);await cmd('retire_device',{deviceId:da,reason:'Lost phone with earlier and refreshed login sessions'});
  await login(a,da,da);await assert.rejects(()=>snap(w,id()),/Session belongs to retired/);
 });
 await test('Signed-out session cannot modify or read even with an unexpired JWT',async()=>{
  await login(office,desk);const session=sessions.get(desk);await db.exec('reset role');await db.query('delete from auth.sessions where id=$1',[session]);await db.exec('set role authenticated');
  await assert.rejects(()=>snap(),/Auth session no longer exists/);await assert.rejects(()=>cmd('retire_device',{deviceId:da,reason:'Signed-out old JWT'}),/Auth session no longer exists/);
 });
 await test('All reliability tables use RLS',async()=>{await db.exec('reset role');assert.equal((await db.query("select relname from pg_class join pg_namespace n on n.oid=relnamespace where n.nspname='private' and relkind='r' and not relrowsecurity")).rows.length,0);});
 console.log(`${passed} reliability checks passed. PostgreSQL/PGlite with simulated Auth; no hosted Supabase or physical devices.`);
} finally { await db.close(); }
