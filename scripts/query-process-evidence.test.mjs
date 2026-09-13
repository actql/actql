// Independent bounded mock executor and ownership model, not a product lowerer.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync,writeFileSync} from 'node:fs';
import {machineCid as cid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {contract} from './query-process-evidence.mjs';

const read=p=>JSON.parse(readFileSync(p,'utf8'));
const corpus=read('portability/corpus/query-acquisition.json');
// These source/owner identities are external fixture inputs, not evidence issuers.
const requirement={...read('portability/corpus/query-acquisition-identities.json')[0].body,source_order_cid:null};
const roles=['source_validation','filter','select'];
function matches(s,v) {
  if(s.const!==undefined && canonicalText(s.const)!==canonicalText(v)) return false;
  if(s.enum && !s.enum.includes(v)) return false;
  if(s.anyOf && !s.anyOf.some(x=>matches(x,v))) return false;
  if(s.type){
    const actual=v===null?'null':Array.isArray(v)?'array':typeof v;
    if(s.type==='integer'?!Number.isSafeInteger(v):actual!==s.type) return false;
  }
  if(typeof v==='string' && ((s.minLength && [...v].length<s.minLength) ||
    (s.pattern && !new RegExp(s.pattern).test(v)))) return false;
  if(typeof v==='number' && (v<(s.minimum??-Infinity) || v>(s.maximum??Infinity))) return false;
  if(Array.isArray(v)){
    if(s.uniqueItems && new Set(v.map(canonicalText)).size!==v.length) return false;
    if(s.items && !v.every(x=>matches(s.items,x))) return false;
  } else if(v!==null && typeof v==='object'){
    if((s.required??[]).some(k=>!Object.hasOwn(v,k))) return false;
    for(const [k,x] of Object.entries(v)){
      if(s.properties?.[k]){if(!matches(s.properties[k],x)) return false;}
      else if(s.additionalProperties===false) return false;
    }
  }
  return true;
}
const scope=r=>cid({version:'actql-query-scan-scope/0.1',source_ref:r.source_ref,
  source_contract_cid:r.source_contract_cid,resolved_request_cid:cid(r.request)});
const freeze=v=>{if(v && typeof v==='object'){Object.values(v).forEach(freeze);Object.freeze(v);}return v;};
function mockHost(issuer) {
  let next=0;
  const live=new WeakMap();
  function execute(strategy, r=requirement, rows=corpus.rows, snapshot=null) {
    const attempt=String(++next);
    assert.equal(r.source_order_cid,null,'UnsupportedOrderEvidence');
    // The mock source owns the entire finite scan. A projected-only provider
    // cannot run this validation over missing fields or omitted rows.
    for(const row of rows) {
      assert.deepEqual(Object.keys(row).sort(),['amount','id','status'],'SourceAdmission');
      assert.equal(typeof row.amount,'number','SourceAdmission');
      assert.ok(Number.isFinite(row.amount),'SourceAdmission');
      assert.equal(typeof row.id,'string','SourceAdmission');
      assert.equal(typeof row.status,'string','SourceAdmission');
      assert.ok(Buffer.byteLength(canonicalText(row))<=r.logical_guards.max_value_bytes,'LogicalGuard');
    }
    const outputRows=rows.filter(v=>v.status==='open').map(v=>({id:v.id}));
    assert.ok(outputRows.length<=r.logical_guards.max_rows,'LogicalGuard');
    const received=strategy==='native'?outputRows:rows;
    const fields=strategy==='native'?['id']:['amount','id','status'];
    const access={scope_cid:cid({version:'actql-query-access-scope/0.1',requirement_cid:cid(r),
      received_rows_cid:cid(received),received_fields:fields}),provider_scope_cid:null,
      received_rows:received.length,received_fields:fields,received_bytes:Buffer.byteLength(canonicalText(received))};
    const output={contract_cid:r.output_contract_cid,rows_cid:cid(outputRows),row_count:outputRows.length};
    const records=roles.map(role=>({version:'actql-query-process-evidence/0.1',issuer,attempt,
      requirement_cid:cid(r),role,snapshot,scan_scope_cid:scope(r),actual_access:access,output}));
    const handle=freeze(structuredClone({records,rows:outputRows}));
    // Expected execution identity belongs to the Host task, independently of
    // the submitted record. Never derive the expected attempt from the payload.
    live.set(handle,freeze({issuer,attempt,requirement_cid:cid(r),
      snapshot:structuredClone(snapshot)}));
    return handle;
  }
  function admit(handle, r=requirement, attempt, snapshot=null) {
    const task=live.get(handle);
    assert.ok(task,'UnissuedEvidence');
    assert.equal(task.requirement_cid,cid(r),'ForeignRequirement');
    assert.equal(task.attempt,attempt??task.attempt,'ForeignAttempt');
    assert.deepEqual(task.snapshot,snapshot,'ForeignSnapshot');
    for(const [i,record] of handle.records.entries()) {
      assert.equal(record.role,roles[i]);
      assert.equal(record.issuer,task.issuer,'ForeignIssuer');
      assert.equal(record.requirement_cid,task.requirement_cid,'ForeignRequirement');
      assert.equal(record.attempt,task.attempt,'ForeignAttempt');
      assert.deepEqual(record.snapshot,snapshot,'ForeignSnapshot');
      assert.equal(record.scan_scope_cid,scope(r));
      assert.equal(record.output.rows_cid,cid(handle.rows));
    }
    return handle.records.map(cid);
  }
  return {execute,admit};
}
test('issued native and broad records retain identical output and distinct access',()=>{
  const host=mockHost('fixture-process');
  const native=host.execute('native'), broad=host.execute('broad');
  assert.deepEqual(native.rows,corpus.expected_output);
  assert.deepEqual(native.rows,broad.rows);
  assert.notDeepEqual(host.admit(native),host.admit(broad));
  assert.equal(native.records[0].actual_access.received_rows,2);
  assert.equal(broad.records[0].actual_access.received_rows,3);
  assert.equal(native.records[0].actual_access.received_fields.length,1);
  assert.equal(broad.records[0].actual_access.received_fields.length,3);
  assert.throws(()=>host.admit(structuredClone(native)),/UnissuedEvidence/);
  const omitted=structuredClone(native);
  // Even a source-validation record claiming the full scan, with a recomputed
  // CID, cannot replace the issuer's live full-scan completion handle.
  omitted.records[0].actual_access.received_rows=2;
  assert.throws(()=>host.admit(omitted),/UnissuedEvidence/);
  assert.throws(()=>mockHost('other-process').admit(native),/UnissuedEvidence/);
  assert.throws(()=>host.admit(native,requirement,broad.records[0].attempt),/ForeignAttempt/);
  // Identical rows and strategy do not make two executions interchangeable.
  const retry=host.execute('native');
  assert.deepEqual(retry.rows,native.rows);
  assert.throws(()=>host.admit(retry,requirement,native.records[0].attempt),/ForeignAttempt/);
});
test('exact owner parameter request source and snapshot bindings are mandatory',()=>{
  const host=mockHost('fixture-process'), handle=host.execute('broad');
  const variants=[{...requirement,owner:{...requirement.owner,input:'other'}},
    {...requirement,parameter_values_cid:cid({other:'values'})},
    {...requirement,request:{tenant:'other'}},
    {...requirement,source_ref:'other'},
    {...requirement,source_contract_cid:cid({other:'source'})}];
  for(const r of variants) assert.throws(()=>host.admit(handle,r),/ForeignRequirement/);
  const snapshot={contract_cid:cid({snapshot:'contract'}),token_cid:cid({token:'one'})};
  const snap=host.execute('broad',requirement,corpus.rows,snapshot);
  host.admit(snap,requirement,snap.records[0].attempt,snapshot);
  assert.throws(()=>host.admit(snap),/ForeignSnapshot/);
  assert.throws(()=>host.admit(snap,requirement,snap.records[0].attempt,
    {...snapshot,token_cid:cid({token:'two'})}),/ForeignSnapshot/);
});
test('proposal hashes and incomplete native source validation cannot issue evidence',()=>{
  const host=mockHost('fixture-process');
  assert.throws(()=>host.admit({records:[],validated:true}),/UnissuedEvidence/);
  for(const strategy of ['native','broad']) {
    const rows=structuredClone(corpus.rows); rows[1].amount='invalid';
    assert.throws(()=>host.execute(strategy,requirement,rows),/SourceAdmission/);
  }
  assert.throws(()=>host.execute('native',requirement,corpus.expected_output),/SourceAdmission/);
  assert.throws(()=>host.execute('broad',{...requirement,source_order_cid:cid({physical:'order'})}),/UnsupportedOrderEvidence/);
});
const host=mockHost('fixture-process');
const vectors=[host.execute('native'),host.execute('broad')].flatMap(h=>h.records)
  .map(body=>({body,cid:cid(body)}));
const path='portability/corpus/query-process-evidence.json';
if(process.argv.includes('--write')) writeFileSync(path,JSON.stringify(vectors,null,2)+'\n');
test('fixed record preimages match independent oracle and closed schema',()=>{
  assert.deepEqual(read(path),vectors);
  const schema=contract.schemas.record;
  for(const v of vectors){
    assert.ok(matches(schema,v.body));
    for(const key of schema.required){const missing={...v.body}; delete missing[key];assert.equal(matches(schema,missing),false);}
    assert.equal(matches(schema,{...v.body,validated:true}),false);
    assert.equal(matches(schema,{...v.body,role:'proposal'}),false);
    assert.equal(matches(schema,{...v.body,output:{...v.body.output,extra:1}}),false);
    assert.deepEqual(Object.keys(v.body).sort(),schema.required.slice().sort());
    assert.equal(v.body.version,schema.properties.version.const);
    assert.ok(schema.properties.role.enum.includes(v.body.role));
  }
  assert.equal(schema.additionalProperties,false);
});
const moon=['// Generated from independent process-evidence preimages; do not edit.',''];
for(const [i,v] of vectors.entries()) moon.push('///|',`test "process evidence preimage ${i}" {`,
  '  let input = @json.parse(',`    ${JSON.stringify(canonicalText(v.body))},`,'  )',
  '  let value = @canonical_json.from_json(input, 10000, 100, 100000)',
  '  assert_eq(', '    @canonical_json.cid_value(value, 100000, 10000, 100),',
  `    ${JSON.stringify(v.cid)},`,'  )','}','');
const moonPath='src/canonical_json/query_process_evidence.generated_test.mbt';
if(process.argv.includes('--write')) writeFileSync(moonPath,moon.join('\n'));
test('three-target preimages are current',()=>assert.equal(readFileSync(moonPath,'utf8'),moon.join('\n')));
