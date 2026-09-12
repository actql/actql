import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {rowKernelSchemas, prepareExpressionEvidence, executionContract, checkOrderedRegistration} from './ordered-derive-contract.mjs';
const read = p => JSON.parse(readFileSync(p,'utf8'));
const expressions=read('spec/contracts/actql-expressions.json');
const stages=read('spec/contracts/actql-stage-contracts.json');
const protocol=read('spec/contracts/actql-protocol-schemas.json');

test('candidate ordered params are closed, nonempty and do not redefine expression nodes', () => {
  const {params}=rowKernelSchemas(protocol);
  assert.deepEqual(params.required,['row_kernel_contract_cid','bindings','references']);
  assert.equal(params.additionalProperties,false);
  assert.equal(params.properties.bindings.minItems,1);
  assert.deepEqual(params.properties.bindings.items.required,['name','expr']);
  assert.deepEqual(params.properties.bindings.items.properties.expr,{$ref:expressions.schemas.expression_node.$id});
  assert.deepEqual(params.properties.references.items.properties.target.oneOf.map(x => x.required),[['input_field'],['prior_slot']]);
  for (const arm of params.properties.references.items.properties.target.oneOf) assert.equal(arm.additionalProperties,false);
});

test('candidate contexts preserve checked contract definitions and partial row evidence', () => {
  const {context,shape}=rowKernelSchemas(protocol);
  assert.deepEqual(context.$defs,protocol.schemas.canonical_value_contract.$defs);
  assert.deepEqual(shape.$defs,protocol.schemas.canonical_value_contract.$defs);
  assert.deepEqual(context.required,['version','input_contract_cid','prior_slots','self_cid']);
  assert.deepEqual(shape.required,['version','fields','required_fields','additional_fields','self_cid']);
  assert.equal(context.additionalProperties,false); assert.equal(shape.additionalProperties,false);
});

test('candidate evidence augments but does not replace the existing fragment and derive evidence', () => {
  const original=structuredClone(expressions);
  const prepared=prepareExpressionEvidence(structuredClone(expressions),stages,protocol);
  assert.deepEqual(expressions,original);
  const {row_kernel_evidence:evidence,...rest}=prepared.schemas.fragment.properties;
  const {row_kernel_evidence:existing,...originalProperties}=expressions.schemas.fragment.properties;
  assert.deepEqual(rest,originalProperties);
  assert.deepEqual(prepared.schemas.fragment.required,expressions.schemas.fragment.required);
  assert.deepEqual(evidence.properties.bindings.items,stages.schemas.derive_binding);
  assert.equal(evidence.additionalProperties,false);
  assert.deepEqual(evidence.required,['bindings','contexts','limits','shapes']);
});

test('candidate limits distinguish logical bytes and work and permit exact zero ceilings', () => {
  const {limits}=rowKernelSchemas(protocol);
  for (const k of ['max_input_rows','max_value_bytes','max_live_value_bytes','max_work']) {
    assert.deepEqual(limits.properties[k],{type:'integer',minimum:0,maximum:9007199254740991});
  }
  const body=executionContract(prepareExpressionEvidence(structuredClone(expressions),stages,protocol),stages,protocol);
  assert.equal(body.operation,'REL.derive');
  assert.equal(body.applies_to,'ordered_parameters_only');
  assert.deepEqual(body.inputs,['relation']); assert.equal(body.output,'relation');
  assert.ok(!Object.hasOwn(body,'self_cid'));
  assert.deepEqual(body.schemas.params.properties.row_kernel_contract_cid,{type:'string',pattern:'^sha256:[a-f0-9]{64}$'});
  assert.match(body.semantics.acyclic,/not_evidence_self_cid/);
});

test('selected row kernel resolves exact bodies and rejects incompatible pins', () => {
  const aoa=read('spec/contracts/actql-aoa.json'),registry=read(aoa.pipeline_registry_file);
  checkOrderedRegistration(aoa,expressions,stages,protocol,registry);
  for(const mutate of [
    r=>{delete r['REL.derive'].execution_extensions;},
    r=>{r['REL.derive'].execution_extensions.ordered_bindings.cid='sha256:'+'0'.repeat(64);},
    r=>{r['REL.derive'].execution_extensions.ordered_bindings.pointer='/execution_contracts/REL.values';},
  ]) {
    const bad=structuredClone(registry);mutate(bad);
    assert.throws(()=>checkOrderedRegistration(aoa,expressions,stages,protocol,bad));
  }
  const bad=structuredClone(aoa);bad.execution_contracts['REL.derive.ordered'].semantics.evaluation='slot_major';
  assert.throws(()=>checkOrderedRegistration(bad,expressions,stages,protocol,registry));
});

test('historical fragment registry retains its identity but cannot select ordered bindings', () => {
  const historical=read('portability/fixtures/pipeline-registry-fragment.json');
  assert.equal(machineCid(historical),'sha256:23a7f1081d1a2cdab7b20e425dddce846510355ba964058e0c809350fae33816');
  assert.ok(historical['ACTQL.expression_fragment/0.1']);
  assert.equal(historical['REL.derive'].execution_extensions,undefined);
  const aoa=read('spec/contracts/actql-aoa.json');
  assert.throws(()=>checkOrderedRegistration(aoa,expressions,stages,protocol,historical));
  aoa.pipeline_registry_cid=machineCid(historical);
  assert.throws(()=>checkOrderedRegistration(aoa,expressions,stages,protocol,historical));
});

// A deliberately limited schema interpreter for the new limits and reference
// alternatives. Unrecognized keywords fail the test instead of being ignored.
function validShape(s,v) {
  const keywords=['$id','type','properties','additionalProperties','required','const','minimum','maximum','pattern','minLength','oneOf'];
  for(const key of Object.keys(s))assert.ok(keywords.includes(key),key);
  if(s.oneOf)return s.oneOf.filter(x=>validShape(x,v)).length===1;
  if(Object.hasOwn(s,'const')&&v!==s.const)return false;
  if(s.type==='integer')return Number.isSafeInteger(v)&&v>=s.minimum&&v<=s.maximum;
  if(s.type==='string')return typeof v==='string'&&v.length>=(s.minLength??0)&&(!s.pattern||new RegExp(s.pattern).test(v));
  if(s.type==='object'){
    if(v===null||typeof v!=='object'||Array.isArray(v))return false;
    if(s.required.some(k=>!Object.hasOwn(v,k)))return false;
    return Object.entries(v).every(([k,x])=>Object.hasOwn(s.properties,k)?validShape(s.properties[k],x):s.additionalProperties!==false);
  }
  return true;
}

test('resource limit schema accepts exact endpoints and rejects missing or malformed caps', () => {
  const schema=rowKernelSchemas(protocol).limits;
  const base={version:'actql-derive-row-limits/0.1',self_cid:'sha256:'+'a'.repeat(64),
    max_input_rows:0,max_value_bytes:0,max_live_value_bytes:0,max_work:0};
  assert.equal(validShape(schema,base),true);
  for(const key of schema.required){const bad={...base};delete bad[key];assert.equal(validShape(schema,bad),false,key);}
  for(const key of ['max_input_rows','max_value_bytes','max_live_value_bytes','max_work']){
    for(const value of [0,1,9007199254740991])assert.equal(validShape(schema,{...base,[key]:value}),true);
    for(const value of [-1,0.5,9007199254740992,'1',null])assert.equal(validShape(schema,{...base,[key]:value}),false);
  }
  assert.equal(validShape(schema,{...base,extra:1}),false);
  assert.equal(validShape(schema,{...base,self_cid:'sha256:'+'A'.repeat(64)}),false);
});

test('reference targets are exclusive closed alternatives', () => {
  const target=rowKernelSchemas(protocol).params.properties.references.items.properties.target;
  for(const value of [{input_field:'x'},{prior_slot:0}])assert.equal(validShape(target,value),true);
  for(const value of [{},{input_field:''},{prior_slot:-1},{prior_slot:'0'},
    {input_field:'x',prior_slot:0},{input_field:'x',extra:true}])assert.equal(validShape(target,value),false);
});
