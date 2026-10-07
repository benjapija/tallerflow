// PostgreSQL-produced canonical text/digests consumed by Dart tests. Local only.
import {PGlite} from '@electric-sql/pglite';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';

const path=new URL('./fixtures/fiscal-draft-integrity.json',import.meta.url);
const db=new PGlite();
try {
 const inputs=[
  {body:{b:2,a:1,long:'Álvarez & <ensayo>',z:[true,false,null,7]},previousHash:''},
  {body:{'é':'España 🛠','a':'quote " slash \\ line\n tab\t','zz':1000000000000,'汉':'漢字'},previousHash:'A'.repeat(64)},
  {body:{draftFormat:1,scope:'sandbox',emissionEnabled:false,transmissionEnabled:false,
    id:'00000000-0000-4000-8000-000000000001',issuerNif:'B12345678',installation:'sandbox-a',
    sequence:1,kind:'draft',prefix:'ENSAYO-A',number:1,reason:'Ensayo ficticio',
    actorId:'00000000-0000-4000-8000-000000000002',deviceId:'00000000-0000-4000-8000-000000000003',
    createdAt:'2026-10-07T12:00:00.123456+00:00',issueDate:'2026-10-07',
    recipient:{name:'Cliente ficticio',nif:'12345678Z'},calculation:{lines:[{
      id:'00000000-0000-4000-8000-000000000004',description:'Revisión ficticia',
      unitCents:3333,quantityMilli:1500,discountBps:1250,taxBps:2100,tax:'iva',treatment:'taxable',
      baseCents:4375,taxCents:919,totalCents:5294,
    }],baseCents:4375,taxCents:919,totalCents:5294}},previousHash:''},
 ];
 const cases=[];
 for(const input of inputs){
  const result=await db.query("select $1::jsonb::text canonical, upper(encode(sha256(convert_to('TALLERFLOW-DRAFT-1|'||$2||'|'||$1::jsonb::text,'UTF8')),'hex')) hash",[input.body,input.previousHash]);
  const row=result.rows[0];
  assert.equal(createHash('sha256').update('TALLERFLOW-DRAFT-1|'+input.previousHash+'|'+row.canonical).digest('hex').toUpperCase(),row.hash);
  cases.push({...input,canonical:row.canonical,ledgerHash:row.hash});
 }
 if(process.argv.includes('--write-fixture')){
  await writeFile(path,JSON.stringify({scope:'Local PostgreSQL/PGlite jsonb::text and sandbox fingerprints, fictional only',cases},null,2)+'\n');
 }else{
  const expected=JSON.parse(await readFile(path,'utf8'));
  assert.deepEqual(cases,expected.cases);
 }
 console.log(`${cases.length} PostgreSQL sandbox fingerprint vectors passed; no hosted request or AEAT submission.`);
}finally{await db.close();}
