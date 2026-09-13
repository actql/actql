// Finite specification model; no product evaluator, lowerer or database.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {canonicalText} from './check-canonical-json.mjs';
import {machineCid as cid} from './actql-spec-family.mjs';
import {contract} from './query-resource-scopes.mjs';
const fixture = JSON.parse(readFileSync('portability/corpus/query-resource-scopes.json','utf8'));
const bytes = value => Buffer.byteLength(canonicalText(value));

function run(c) {
  const scan = c.scan ?? fixture.scan;
  const state = {captured:false, output:null};
  const fail = issue => ({...state, issue});
  if (c.missing_root_evidence) return fail('Unsupported');
  if (c.physical_stop) return fail('PhysicalBudget');
  if ((c.mode==='local'||c.same_fragment) && scan.length>(c.local_rows??2)) return fail('LocalRows');
  // This fixture fixes validation scan order, not logical total-order evidence.
  for (const row of scan) {
    if (Object.keys(row).sort().join(',')!=='amount,id' ||
      Object.values(row).some(v=>typeof v!=='number'||!Number.isFinite(v)||Object.is(v,-0)))
      return fail('SourceAdmission');
    if (bytes(row)>c.bytes) return fail('ValueBytes');
  }
  const output=[];
  for (const row of scan) {
    const threshold=c.threshold??1;
    const predicate=row.id>threshold;
    // Exact typed-wire sizes of the demanded scalar roots, independent of SQL representation.
    if ([row.id,threshold,predicate].some(v=>bytes(v)>c.bytes)) return fail('ValueBytes');
    if (predicate) output.push({id:row.id});
  }
  if (output.length>c.rows) return fail('OutputRows');
  state.captured=true;state.output=output;
  if (c.consumer_rows!==undefined) {
    if(output.length>c.consumer_rows) return fail('ConsumerRows');
    return fail('Consumed');
  }
  return fail('Captured');
}

for (const c of fixture.cases) test(c.name,()=>{
  const result=run(c);
  assert.equal(result.issue,c.expected);
  assert.equal(result.captured,['Captured','Consumed','ConsumerRows'].includes(c.expected));
  if(result.captured && c.scan===undefined && c.threshold===undefined)
    assert.deepEqual(result.output,fixture.output);
});

test('independent typed-wire quantities differ from output and transfer quantities',()=>{
  assert.deepEqual(fixture.scan.map(bytes),fixture.record_bytes);
  assert.equal(bytes(fixture.scan),43);
  assert.equal(bytes(fixture.output),10);
  assert.equal(bytes([]),2);
  assert.equal(bytes(false),5);
});

test('logical ordered limits remain fragment scoped, not native physical counters',()=>{
  for(const name of ['ordered_rows','ordered_value','ordered_live','ordered_work'])
    assert.equal(contract.limits[name].subject,'selected_ordered_step');
  const expression=JSON.parse(readFileSync('spec/contracts/actql-expressions.json','utf8'));
  const required=expression.schemas.fragment.properties.request.properties.row_kernel_limits
    .additionalProperties.required;
  for(const name of ['max_input_rows','max_value_bytes','max_live_value_bytes','max_work'])
    assert.ok(required.includes(name));
  assert.equal(contract.dependencies.fragment.cid,cid(expression.schemas.fragment));
  assert.match(contract.semantics.initial_shape,/omitted_not_synthesized/);
});

test('execution evidence binds actual guard selection and ownership, not equal output alone',()=>{
  const selected={requirement:'q',owner:'p',parameters:'v',task:'t',attempt:'a',read_view:'r',
    max_rows:1,max_value_bytes:20,demand:'id>1',output:fixture.output};
  const issued=new WeakMap();
  const handle=Object.freeze({});issued.set(handle,structuredClone(selected));
  const admit=(h,expected)=>{assert.ok(issued.has(h));assert.deepEqual(issued.get(h),expected);};
  admit(handle,selected);
  assert.throws(()=>admit({},selected));
  for(const key of ['requirement','owner','parameters','task','attempt','read_view','demand'])
    assert.throws(()=>admit(handle,{...selected,[key]:'other'}));
  for(const key of ['max_rows','max_value_bytes'])
    assert.throws(()=>admit(handle,{...selected,[key]:selected[key]+1}));
});
