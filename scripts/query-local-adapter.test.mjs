// Independent finite ownership/accounting model. No database or product lowerer.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {machineCid as cid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {contract} from './query-process-evidence.mjs';

const fixture=JSON.parse(readFileSync('portability/corpus/query-local-adapter.json','utf8'));
const bytes=rows=>Buffer.byteLength(canonicalText(rows));
const freeze=x=>{if(x&&typeof x==='object'){Object.values(x).forEach(freeze);Object.freeze(x);}return x;};
const initial=JSON.parse(readFileSync('portability/corpus/query-acquisition-identities.json','utf8'))[0].body;
const fields={amount:{type:'number',nullable:false},id:{type:'number',nullable:false}};
const requirement=freeze({...initial,source_order_cid:null,
  source_ref:'connector://fixture/local-read#scan',
  source_contract_cid:cid({fixture_source:'authorized-local-read',schema:fields}),
  input_contract_cid:cid(fields),output_contract_cid:cid({id:fields.id}),
  filter:{...initial.filter,expression_cid:cid({gt:[{field:'id'},{literal:1}]})},
  source_validation:{scope:'selected_scan',fields:['amount','id']}});

test('local read-view conditions do not change the shared record wire shape',()=>{
  assert.equal(cid(contract.schemas.record),
    'sha256:758c9c4f1942890e73462776f3230400e7076c146af8eb3f7e39602715c7427e');
  assert.equal(contract.semantics.preimage,'entire_record_canonical_json_utf8_sha256_no_self_cid');
  assert.ok(!Object.hasOwn(contract.schemas.record.properties,'transaction'));
});

function host(authorized=true) {
  let ordinal=0;
  const tasks=new WeakSet(), state=new WeakMap(), validations=new WeakMap(), completed=new WeakMap();
  function begin(r=requirement) {
    const task=freeze({requirement:r,attempt:String(++ordinal),session:{},transaction:{}});
    tasks.add(task);state.set(task,'new');return task;
  }
  function validate(task, scan) {
    assert.ok(authorized&&tasks.has(task),'UnauthorizedTask');
    assert.equal(state.get(task),'new','ClosedAttempt');state.set(task,'failed');
    for(const [row,value] of scan.entries()) {
      assert.deepEqual(Object.keys(value).sort(),['amount','id'],'SourceAdmission');
      for(const field of ['amount','id']) {
        if(typeof value[field]!=='number'||!Number.isFinite(value[field])||Object.is(value[field],-0))
          throw Object.assign(new Error('SourceAdmission'),{row,field});
      }
    }
    const proof=Object.freeze({});
    validations.set(proof,{task,scan:freeze(structuredClone(scan))});state.set(task,'validated');return proof;
  }
  function execute(task, validation, strategy, options={}) {
    const v=validations.get(validation);
    assert.ok(v&&v.task===task&&tasks.has(task),'ForeignValidation');
    assert.equal(state.get(task),'validated','ClosedAttempt');state.set(task,'failed');
    assert.strictEqual(options.session??task.session,task.session,'ForeignSession');
    assert.strictEqual(options.transaction??task.transaction,task.transaction,'ForeignTransaction');
    // This source fixture has no snapshot evidence. Paths/mtime cannot invent it.
    assert.equal(options.snapshot??null,null,'UnsupportedSnapshotEvidence');
    const scan=v.scan;
    // Evaluation follows full validation. The fixture fixes this traversal only.
    const output=scan.filter(row=>row.id>1).map(row=>({id:row.id}));
    const ledger=[], seen=new Set();
    function receive(rows, fields) {
      const transfer={rows,fields};
      function charge() {
        if(!seen.has(transfer)){seen.add(transfer);ledger.push({rows:rows.length,fields,bytes:bytes(rows)});}
      }
      charge();charge(); // Two uses of one transfer are not two receipts.
      return transfer;
    }
    let received;
    if(strategy==='internal-validation') received=receive(output,['id']);
    else if(strategy==='single-broad-receipt') received=receive(scan,['amount','id']);
    else {
      assert.equal(strategy,'export-validation-and-native');
      receive(scan,['amount','id']);received=receive(output,['id']);
    }
    // Explicit validation/query passes in this model, not engine page/I/O costs.
    // Export itself scans rows too; it is not an extra receipt on top of ledger.
    const accounting={engine_validation_rows:strategy==='internal-validation'?scan.length:0,
      engine_query_rows:strategy==='single-broad-receipt'?0:scan.length,
      engine_broad_export_rows:strategy==='internal-validation'?0:scan.length,receipts:ledger,
      retained_rows:output.length,retained_wire_bytes:bytes(output)};
    assert.ok(ledger.reduce((n,x)=>n+x.bytes,0)<=(options.receiptBudget??Infinity),'ReceiptBudget');
    assert.ok(!options.cancelled,'Cancelled');
    assert.ok(!options.retentionFailed,'RetentionFailed');
    if(ledger.length!==1)return {accounting,issue:'MultipleAccessContractRequired'};
    const r=task.requirement;
    const actual_access={scope_cid:cid({version:'actql-query-access-scope/0.1',
      requirement_cid:cid(r),received_rows_cid:cid(received.rows),received_fields:received.fields}),
      provider_scope_cid:null,received_rows:ledger[0].rows,received_fields:received.fields,received_bytes:ledger[0].bytes};
    const records=['source_validation','filter','select'].map(role=>({
      version:'actql-query-process-evidence/0.1',issuer:'fixture-local-adapter',attempt:task.attempt,
      requirement_cid:cid(r),role,snapshot:null,
      scan_scope_cid:cid({version:'actql-query-scan-scope/0.1',source_ref:r.source_ref,
        source_contract_cid:r.source_contract_cid,resolved_request_cid:cid(r.request)}),
      actual_access,output:{contract_cid:r.output_contract_cid,rows_cid:cid(output),row_count:output.length}}));
    const handle=freeze({records,rows:output});completed.set(handle,task);state.set(task,'completed');
    return {accounting,handle};
  }
  function admit(task,handle) {
    assert.ok(tasks.has(task)&&completed.has(handle),'UnissuedEvidence');
    assert.strictEqual(completed.get(handle),task,'ForeignTask');
    for(const record of handle.records){
      assert.equal(record.requirement_cid,cid(task.requirement));
      assert.equal(record.attempt,task.attempt);
      assert.deepEqual(Object.keys(record).sort(),contract.schemas.record.required.slice().sort());
    }
    return handle.records.map(cid);
  }
  return {begin,validate,execute,admit};
}

test('mandatory source validation rejects the excluded first row before native selection',()=>{
  const h=host(),t=h.begin();
  assert.deepEqual(fixture.invalid_scan.filter(x=>x.id>1).map(x=>({id:x.id})),fixture.expected_output);
  assert.throws(()=>h.validate(t,fixture.invalid_scan), e=>{
    assert.equal(e.message,'SourceAdmission');
    assert.deepEqual({row:e.row,field:e.field},fixture.invalid_scan_failure);return true;
  });
  assert.throws(()=>h.execute(t,{sqlSucceeded:true},'internal-validation'),/ForeignValidation/);
  assert.throws(()=>h.admit(t,{cid:cid(fixture.expected_output)}),/UnissuedEvidence/);
});
test('same result does not admit foreign task, attempt, transaction, session or reconstructed evidence',()=>{
  const h=host(),t=h.begin(),other=h.begin(),v=h.validate(t,fixture.valid_scan);
  assert.throws(()=>h.execute(other,v,'internal-validation'),/ForeignValidation/);
  for(const key of ['session','transaction']) {
    const task=h.begin(),proof=h.validate(task,fixture.valid_scan);
    assert.throws(()=>h.execute(task,proof,'internal-validation',{[key]:other[key]}),/Foreign/);
    assert.throws(()=>h.execute(task,proof,'internal-validation'),/ClosedAttempt/);
  }
  assert.throws(()=>h.execute(t,structuredClone(v),'internal-validation'),/ForeignValidation/);
  const result=h.execute(t,v,'internal-validation');h.admit(t,result.handle);
  assert.throws(()=>h.admit(other,result.handle),/ForeignTask/);
  assert.throws(()=>h.admit(t,structuredClone(result.handle)),/UnissuedEvidence/);
  const foreign=host();assert.throws(()=>foreign.admit(foreign.begin(),result.handle),/UnissuedEvidence/);
  const untrusted=host(false);assert.throws(()=>untrusted.validate(untrusted.begin(),fixture.valid_scan),/UnauthorizedTask/);
  for(const key of ['cancelled','retentionFailed']) {
    const task=h.begin(),proof=h.validate(task,fixture.valid_scan);
    assert.throws(()=>h.execute(task,proof,'internal-validation',{[key]:true}),/Cancelled|RetentionFailed/);
    assert.throws(()=>h.execute(task,proof,'internal-validation'),/ClosedAttempt/);
  }
  const task=h.begin(),proof=h.validate(task,fixture.valid_scan);
  assert.throws(()=>h.execute(task,proof,'internal-validation',
    {snapshot:{path:'fixture.db',mtime:123}}),/UnsupportedSnapshotEvidence/);
});
test('internal scan, auxiliary receipt, native receipt and retention remain distinct',()=>{
  const observations=[];
  for(const c of fixture.cases) {
    const h=host(),t=h.begin(),v=h.validate(t,fixture.valid_scan);
    const result=h.execute(t,v,c.strategy);
    assert.equal(result.accounting.engine_validation_rows,c.engine_validation_rows);
    assert.equal(result.accounting.engine_query_rows,c.engine_query_rows);
    assert.equal(result.accounting.engine_broad_export_rows,c.strategy==='internal-validation'?0:2);
    assert.deepEqual(result.accounting.receipts.map(x=>x.rows),c.receipt_rows);
    assert.deepEqual(result.accounting.receipts.map(x=>x.fields),c.receipt_fields);
    assert.equal(result.accounting.retained_rows,c.retained_rows);
    assert.equal(result.accounting.retained_wire_bytes,bytes(fixture.expected_output));
    if(c.capture){
      observations.push(result.handle);h.admit(t,result.handle);
      assert.deepEqual(result.handle.rows,fixture.expected_output);
      assert.equal(result.handle.records[0].actual_access.received_rows,c.receipt_rows[0]);
    }else{
      assert.equal(result.issue,c.issue);assert.equal(result.handle,undefined);
      assert.equal(result.accounting.receipts.reduce((n,x)=>n+x.rows,0),3);
      assert.throws(()=>h.admit(t,{rows:fixture.expected_output}),/UnissuedEvidence/);
    }
    const total=result.accounting.receipts.reduce((n,x)=>n+x.bytes,0);
    const exact=h.begin(),exactProof=h.validate(exact,fixture.valid_scan);
    h.execute(exact,exactProof,c.strategy,{receiptBudget:total});
    const short=h.begin(),shortProof=h.validate(short,fixture.valid_scan);
    assert.throws(()=>h.execute(short,shortProof,c.strategy,{receiptBudget:total-1}),/ReceiptBudget/);
    assert.throws(()=>h.execute(short,shortProof,c.strategy),/ClosedAttempt/);
  }
  assert.equal(observations[0].records[0].output.rows_cid,observations[1].records[0].output.rows_cid);
  assert.notEqual(observations[0].records[0].actual_access.scope_cid,observations[1].records[0].actual_access.scope_cid);
  assert.notEqual(cid(observations[0].records[0]),cid(observations[1].records[0]));
});
