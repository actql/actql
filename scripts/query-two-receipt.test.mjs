// Independent finite execution/ownership oracle; not a database adapter or lowerer.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync,writeFileSync} from 'node:fs';
import {machineCid as cid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {contract} from './query-two-receipt.mjs';
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const fixture=read('portability/corpus/query-local-adapter.json');
const initial=read('portability/corpus/query-acquisition-identities.json')[0].body;
const fields={amount:{type:'number',nullable:false},id:{type:'number',nullable:false}};
const requirement={...initial,source_order_cid:null,source_ref:'connector://fixture/local-read#scan',
  source_contract_cid:cid({fixture_source:'authorized-local-read',schema:fields}),
  input_contract_cid:cid(fields),output_contract_cid:cid({id:fields.id}),
  filter:{...initial.filter,expression_cid:cid({gt:[{field:'id'},{literal:1}]})},
  source_validation:{scope:'selected_scan',fields:['amount','id']}};
const freeze=v=>{if(v&&typeof v==='object'){Object.values(v).forEach(freeze);Object.freeze(v);}return v;};
const byteLength=v=>Buffer.byteLength(canonicalText(v));
const roles=['source_validation','filter','select'];

function matches(s,v) {
  if(s.const!==undefined&&canonicalText(s.const)!==canonicalText(v))return false;
  if(s.enum&&!s.enum.includes(v))return false;
  if(s.anyOf&&!s.anyOf.some(x=>matches(x,v)))return false;
  if(s.type){const t=v===null?'null':Array.isArray(v)?'array':typeof v;
    if(s.type==='integer'?!Number.isSafeInteger(v):t!==s.type)return false;}
  if(typeof v==='number'&&(v<(s.minimum??-Infinity)||v>(s.maximum??Infinity)))return false;
  if(typeof v==='string'&&((s.minLength&&[...v].length<s.minLength)||(s.pattern&&!new RegExp(s.pattern).test(v))))return false;
  if(Array.isArray(v)){
    if(s.uniqueItems&&new Set(v.map(canonicalText)).size!==v.length)return false;
    if(s.items&&!v.every(x=>matches(s.items,x)))return false;
  }else if(v&&typeof v==='object'){
    if((s.required??[]).some(k=>!Object.hasOwn(v,k)))return false;
    for(const [k,x] of Object.entries(v)){
      if(s.properties?.[k]){if(!matches(s.properties[k],x))return false;}
      else if(s.additionalProperties===false)return false;
    }
  }
  return true;
}

function bodies(r,scan,native,attempt='1',read_view='view-1') {
  const binding={issuer:'fixture-two-receipt',attempt,read_view,requirement_cid:cid(r),snapshot:null,
    scan_scope_cid:cid({version:'actql-query-scan-scope/0.1',source_ref:r.source_ref,
      source_contract_cid:r.source_contract_cid,resolved_request_cid:cid(r.request)})};
  const receipt=(role,rows,received_fields)=>({version:'actql-query-receipt/0.1',...binding,role,
    received_rows_cid:cid(rows),received_rows:rows.length,received_fields,received_bytes:byteLength(rows)});
  const receipts=[receipt('validation_scan',scan,['amount','id']),receipt('native_result',native,['id'])];
  const accesses={validation_scan_cid:cid(receipts[0]),native_result_cid:cid(receipts[1])};
  const output={contract_cid:r.output_contract_cid,rows_cid:cid(native),row_count:native.length};
  const records=roles.map(role=>({version:'actql-query-two-receipt-evidence/0.1',...binding,role,accesses,output}));
  const observation={version:'actql-query-two-receipt-observation/0.1',requirement_cid:cid(r),
    owner:r.owner,source_ref:r.source_ref,source_contract_cid:r.source_contract_cid,
    parameter_values_cid:r.parameter_values_cid,resolved_request_cid:cid(r.request),snapshot:null,
    evidence_contract_cid:cid(contract),execution:{issuer:binding.issuer,attempt,read_view},accesses,
    coverage:{scope_cid:binding.scan_scope_cid,complete:true,source_validation_evidence_cid:cid(records[0]),
      filter_evidence_cid:cid(records[1]),select_evidence_cid:cid(records[2])},output,retention:'process'};
  return {receipts,records,observation};
}

function host() {
  let next=0;
  const tasks=new WeakMap(),issued=new WeakMap();
  function start(r=requirement) {
    const task=Object.freeze({});const attempt=String(++next);
    tasks.set(task,{r:freeze(structuredClone(r)),attempt,view:'view-'+attempt,
      session:{},transaction:{},state:'new'});return task;
  }
  function execute(task,scan=fixture.valid_scan,options={}) {
    const t=tasks.get(task);assert.ok(t,'ForeignTask');assert.equal(t.state,'new','ClosedAttempt');t.state='failed';
    assert.strictEqual(options.transaction??t.transaction,t.transaction,'ForeignTransaction');
    assert.strictEqual(options.session??t.session,t.session,'ForeignSession');
    assert.equal(t.r.source_order_cid,null,'UnsupportedOrder');
    // Two real logical transfers. The first is received before Host validation.
    const validation=structuredClone(scan);
    const received=[{rows:validation,fields:['amount','id']}];
    const charge=()=>{
      const bytes=received.reduce((n,v)=>n+byteLength(v.rows),0);
      const rows=received.reduce((n,v)=>n+v.rows.length,0);
      assert.ok(Number.isSafeInteger(bytes)&&Number.isSafeInteger(rows),'ReceiptOverflow');
      assert.ok(bytes<=(options.maxBytes??Infinity)&&rows<=(options.maxRows??Infinity),'ReceiptBudget');
    };
    charge();
    for(const [i,row] of validation.entries()) {
      assert.deepEqual(Object.keys(row).sort(),['amount','id'],'SourceAdmission');
      for(const name of ['amount','id']) if(typeof row[name]!=='number'||!Number.isFinite(row[name])||Object.is(row[name],-0))
        throw Object.assign(new Error('SourceAdmission'),{row:i,field:name});
      assert.ok(byteLength(row)<=t.r.logical_guards.max_value_bytes,'ValueGuard');
    }
    assert.strictEqual(options.queryTransaction??t.transaction,t.transaction,'ForeignQueryTransaction');
    assert.strictEqual(options.querySession??t.session,t.session,'ForeignQuerySession');
    const expected=validation.filter(row=>row.id>1).map(row=>({id:row.id}));
    const native=structuredClone(options.native??expected);
    received.push({rows:native,fields:['id']});charge();
    assert.deepEqual(native,expected,'NativeMismatch');
    assert.ok(native.length<=t.r.logical_guards.max_rows,'RowGuard');
    assert.ok(!options.cancelled,'Cancelled');assert.ok(!options.retentionFailed,'RetentionFailed');
    assert.ok(byteLength(native)<=(options.maxRetention??Infinity),'RetentionBudget');
    const data=freeze(bodies(t.r,validation,native,t.attempt,t.view));
    const handles=[...data.receipts,...data.records].map(body=>{
      const h=Object.freeze({});issued.set(h,{task,body,session:t.session,transaction:t.transaction});return h;
    });
    t.data=data;t.output=freeze(native);t.state='completed';
    return {handles,observation:data.observation,accounting:{
      receipt_rows:received.map(v=>v.rows.length),receipt_bytes:received.map(v=>byteLength(v.rows)),
      retained_rows:native.length,retained_wire_bytes:byteLength(native)}};
  }
  function admit(task,result) {
    const t=tasks.get(task);assert.ok(t?.state==='completed','IncompleteTask');
    assert.equal(result.handles.length,5,'MissingEvidence');
    const expected=[...t.data.receipts,...t.data.records];
    result.handles.forEach((h,i)=>{
      const record=issued.get(h);assert.ok(record,'UnissuedEvidence');
      assert.strictEqual(record.task,task,'ForeignTask');
      assert.strictEqual(record.session,t.session,'ForeignSession');
      assert.strictEqual(record.transaction,t.transaction,'ForeignTransaction');
      assert.equal(cid(record.body),cid(expected[i]),'ForeignRole');
    });
    assert.deepEqual(result.observation,t.data.observation,'ObservationMismatch');
    assert.equal(cid(t.output),result.observation.output.rows_cid);
    return cid(result.observation);
  }
  return {start,execute,admit};
}

test('two distinct receipt roles bind full scan and native output with exact physical accounting',()=>{
  const h=host(),task=h.start(),result=h.execute(task);h.admit(task,result);
  assert.deepEqual(result.accounting.receipt_rows,[2,1]);
  assert.deepEqual(result.accounting.receipt_bytes,[43,10]);
  assert.equal(result.accounting.retained_rows,1);assert.equal(result.accounting.retained_wire_bytes,10);
  const data=bodies(requirement,fixture.valid_scan,fixture.expected_output);
  assert.deepEqual(data.receipts.map(v=>v.received_fields),[['amount','id'],['id']]);
  assert.equal(data.receipts[1].received_rows_cid,data.observation.output.rows_cid);
  assert.notEqual(cid(data.receipts[1]),cid(data.observation));
  assert.notEqual(cid(data.receipts[1]),cid({...data.receipts[1],role:'validation_scan'}));
  const retry=h.start(),again=h.execute(retry);assert.notEqual(h.admit(task,result),h.admit(retry,again));
});

test('missing, foreign, swapped and serialized evidence cannot produce capture',()=>{
  const h=host(),a=h.start(),b=h.start(),x=h.execute(a),y=h.execute(b);
  for(let i=0;i<5;i++) {
    assert.throws(()=>h.admit(a,{...x,handles:x.handles.filter((_,j)=>j!==i)}),/MissingEvidence/);
    assert.throws(()=>h.admit(a,{...x,handles:x.handles.map((v,j)=>j===i?y.handles[i]:v)}),/ForeignTask/);
  }
  assert.throws(()=>h.admit(a,{...x,handles:[x.handles[1],x.handles[0],...x.handles.slice(2)]}),/ForeignRole/);
  assert.throws(()=>h.admit(a,structuredClone(x)),/UnissuedEvidence/);
  assert.throws(()=>h.admit(a,{...x,observation:{...x.observation,execution:y.observation.execution}}),/ObservationMismatch/);
  assert.throws(()=>h.admit(a,{...x,observation:{...x.observation,evidence_contract_cid:cid({other:'profile'})}}),/ObservationMismatch/);
});

test('empty and repeated rows retain both receipt roles and exact multiplicity',()=>{
  const h=host(),empty=h.start(),e=h.execute(empty,[]);h.admit(empty,e);
  assert.deepEqual(e.accounting.receipt_rows,[0,0]);assert.deepEqual(e.accounting.receipt_bytes,[2,2]);
  assert.notEqual(e.observation.accesses.validation_scan_cid,e.observation.accesses.native_result_cid);
  const repeated=h.start(),r=h.execute(repeated,[...fixture.valid_scan,fixture.valid_scan[1]]);h.admit(repeated,r);
  assert.deepEqual(r.accounting.receipt_rows,[3,2]);assert.equal(r.accounting.retained_rows,2);
});

test('invalid excluded rows and terminal failures cannot be retried into completion',()=>{
  const h=host();
  for(const options of [{transaction:{}},{session:{}},{queryTransaction:{}},{querySession:{}},{cancelled:true},{retentionFailed:true},
    {maxBytes:52},{maxRows:2},{maxRetention:9},{native:[{id:0}]}]) {
    const task=h.start();assert.throws(()=>h.execute(task,fixture.valid_scan,options));
    assert.throws(()=>h.execute(task),/ClosedAttempt/);assert.throws(()=>h.admit(task,{handles:[]}),/IncompleteTask/);
  }
  const task=h.start();
  assert.throws(()=>h.execute(task,fixture.invalid_scan),e=>{
    assert.equal(e.message,'SourceAdmission');assert.equal(e.row,0);assert.equal(e.field,'amount');return true;
  });
  assert.throws(()=>h.execute(task),/ClosedAttempt/);
  const exact=h.start();h.admit(exact,h.execute(exact,fixture.valid_scan,{maxBytes:53,maxRows:3,maxRetention:10}));
});

const data=bodies(requirement,fixture.valid_scan,fixture.expected_output);
const vectors={requirement:{body:requirement,cid:cid(requirement)},
  receipts:data.receipts.map(body=>({body,cid:cid(body)})),
  records:data.records.map(body=>({body,cid:cid(body)})),
  observation:{body:data.observation,cid:cid(data.observation)}};
const path='portability/corpus/query-two-receipt.json';
if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(vectors,null,2)+'\n');
test('fixed preimages remain independent of product output and old profile identities remain pinned',()=>{
  assert.deepEqual(read(path),vectors);
  assert.equal(cid(read('spec/contracts/actql-query-acquisition.json')),contract.dependencies.query_acquisition.cid);
  assert.equal(contract.dependencies.query_acquisition.cid,'sha256:4bb69dfaade0a15952fe23a8202a9475ff450c9f0fab93f9dd5cef1b82045ab1');
  assert.equal(contract.dependencies.process_evidence.cid,'sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89');
});
test('closed shapes do not replace receipt content, role, ordering and ownership checks',()=>{
  for(const [schema,items] of [[contract.schemas.receipt,data.receipts],
    [contract.schemas.record,data.records],[contract.schemas.completed_observation,[data.observation]]]){
    for(const body of items){
      assert.ok(matches(schema,body));
      for(const key of schema.required){const missing={...body};delete missing[key];assert.equal(matches(schema,missing),false);}
      assert.equal(matches(schema,{...body,extra:true}),false);
    }
  }
  assert.equal(matches(contract.schemas.receipt,{...data.receipts[0],role:'output'}),false);
  assert.equal(matches(contract.schemas.receipt,{...data.receipts[0],received_fields:['id','id']}),false);
  assert.equal(matches(contract.schemas.receipt,{...data.receipts[0],received_bytes:-1}),false);
  assert.equal(matches(contract.schemas.record,{...data.records[0],accesses:{validation_scan_cid:cid(data.receipts[0])}}),false);
  assert.equal(matches(read('spec/contracts/actql-query-acquisition.json').schemas.completed_observation,data.observation),false);
  const reordered=bodies(requirement,[...fixture.valid_scan].reverse(),fixture.expected_output);
  assert.notEqual(cid(reordered.receipts[0]),cid(data.receipts[0]));
  assert.equal(reordered.observation.output.rows_cid,data.observation.output.rows_cid);
  assert.notEqual(cid(reordered.observation),cid(data.observation));
  const keyOrder=fixture.valid_scan.map(row=>({id:row.id,amount:row.amount}));
  assert.equal(cid(bodies(requirement,keyOrder,fixture.expected_output).observation),cid(data.observation));
  const repeated=[...fixture.valid_scan,fixture.valid_scan[1]], output=[{id:2},{id:2}];
  const multiple=bodies(requirement,repeated,output);
  assert.equal(multiple.receipts[0].received_rows,3);assert.equal(multiple.receipts[1].received_rows,2);
  assert.notEqual(multiple.observation.output.rows_cid,data.observation.output.rows_cid);
});
const moon=['// Generated from independent two-receipt preimages; do not edit.',''];
for(const [i,v] of [...vectors.receipts,...vectors.records,vectors.observation].entries())moon.push(
  '///|',`test "two receipt preimage ${i}" {`,
  `  let input = @json.parse(${JSON.stringify(canonicalText(v.body))})`,
  '  let value = @canonical_json.from_json(input, 10000, 100, 100000)',
  `  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), ${JSON.stringify(v.cid)})`,'}','');
const moonPath='src/canonical_json/query_two_receipt.generated_test.mbt';
if(process.argv.includes('--write'))writeFileSync(moonPath,moon.join('\n'));
test('three-target preimages are current',()=>assert.equal(readFileSync(moonPath,'utf8'),moon.join('\n')));
