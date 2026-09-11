import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {isDeepStrictEqual} from 'node:util';
import {checkExecutionContract} from './values-execution-contract.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const aoa = read('spec/contracts/actql-aoa.json');
const registry = read('spec/dependencies/aoa-pipeline-registry.json');
const base = read('portability/fixtures/pipeline-registry-base.json');
const protocol = read('spec/contracts/actql-protocol-schemas.json');
const oldCid = 'sha256:00ac46baefe7fa34412ad83beb85cf1899b906e792d74fa89211a7c4972f0d5a';
const newCid = 'sha256:b97a22de3664c1dafe3bc1e6791f1f8bcfb70324a1fcc1087450fe057e0f2311';
// Independent oracle for these ASCII-key, ordinary JSON registry fixtures.
// Not the product lowerer, a backend resolver, or a general JSON validator.
const canonical = v => Array.isArray(v) ? `[${v.map(canonical).join(',')}]`
  : v !== null && typeof v === 'object'
    ? `{${Object.keys(v).sort().map(k => `${JSON.stringify(k)}:${canonical(v[k])}`).join(',')}}`
    : JSON.stringify(v);
const cid = v => `sha256:${createHash('sha256').update(canonical(v)).digest('hex')}`;
const same = (a,b,message) => {if (!isDeepStrictEqual(a,b)) throw new Error(message);};

// The registration-only acceptance algorithm, deliberately excluding params
// admission, backend support, permission, and whole-Program completeness.
function resolveValues(body, selected = aoa.pipeline_registry_cid, contract = aoa) {
  if (cid(body) !== selected) throw new Error('RegistryCidMismatch');
  if (!Object.hasOwn(body,'REL.values')) throw new Error('MissingRegistration');
  const entry = body['REL.values'];
  const required = contract.target_registry_requirements['REL.values'];
  same(Object.keys(entry).sort(), ['execution_contract','inputs','output'], 'InvalidRegistration');
  same({inputs:entry.inputs,output:entry.output},
    {inputs:required.inputs,output:required.output}, 'SignatureMismatch');
  same(entry.execution_contract, {
    file:'spec/contracts/actql-aoa.json', ...required.execution_contract,
  }, 'ContractReferenceMismatch');
  const resolved = entry.execution_contract.pointer.split('/').slice(1)
    .reduce((value,key) => value?.[key.replace(/~1/g,'/').replace(/~0/g,'~')],contract);
  if (!resolved || cid(resolved) !== entry.execution_contract.cid) throw new Error('ContractCidMismatch');
  same({operation:resolved.operation,inputs:resolved.inputs,output:resolved.output},
    {operation:'REL.values',inputs:entry.inputs,output:entry.output}, 'ContractSignatureMismatch');
  checkExecutionContract(contract,protocol);
  return entry;
}

test('shared registry extends the exact historical body without relabeling its CID', () => {
  assert.equal(cid(base),oldCid);
  assert.equal(Object.keys(base).length,57);
  assert.equal(cid(registry),newCid);
  assert.equal(aoa.pipeline_registry_file,'spec/dependencies/aoa-pipeline-registry.json');
  assert.equal(aoa.pipeline_registry_cid,newCid);
  assert.equal(Object.keys(registry).length,58);
  const {['REL.values']:added,...retained} = registry;
  assert.deepEqual(retained,base);
  assert.ok(added);
  assert.equal(Object.hasOwn(base,'REL.values'),false);
});

test('selected registration resolves the complete execution contract and checked-type dependency', () => {
  const entry = resolveValues(registry);
  assert.deepEqual(entry.inputs,[]);
  assert.equal(entry.output,'relation');
  assert.equal(entry.execution_contract.cid,'sha256:c95bc0d474fd6fbe62d3182bdefe6af412070f6ad2c8e102c5279d7a8b3eed17');
});

test('old selected registry cannot resolve values and a new body cannot reuse the old CID', () => {
  assert.throws(() => resolveValues(base,oldCid),/MissingRegistration/);
  assert.throws(() => resolveValues(base),/RegistryCidMismatch/);
  assert.throws(() => resolveValues(registry,oldCid),/RegistryCidMismatch/);
});

test('rehashing a changed signature or contract reference does not satisfy the requirement', () => {
  for (const [mutate,issue] of [
    [e => {e.inputs = ['relation'];}, /SignatureMismatch/],
    [e => {e.output = 'events';}, /SignatureMismatch/],
    [e => {delete e.execution_contract;}, /InvalidRegistration/],
    [e => {e.execution_contract.cid = oldCid;}, /ContractReferenceMismatch/],
    [e => {e.execution_contract.pointer += '/params_schema';}, /ContractReferenceMismatch/],
    [e => {e.execution_contract.file = 'another-contract.json';}, /ContractReferenceMismatch/],
  ]) {
    const changed = structuredClone(registry); mutate(changed['REL.values']);
    assert.throws(() => resolveValues(changed,cid(changed)),issue);
  }
});

test('a matching reference cannot hide a changed execution body or dependency', () => {
  const changed = structuredClone(aoa);
  changed.execution_contracts['REL.values'].semantics.row_order = 'sort';
  assert.throws(() => resolveValues(registry,newCid,changed),/ContractCidMismatch/);
  const altered = structuredClone(aoa), body = structuredClone(registry);
  altered.execution_contracts['REL.values'].dependencies.canonical_value_contract.cid = oldCid;
  const forgedCid = cid(altered.execution_contracts['REL.values']);
  altered.target_registry_requirements['REL.values'].execution_contract.cid = forgedCid;
  body['REL.values'].execution_contract.cid = forgedCid;
  assert.throws(() => resolveValues(body,cid(body),altered));
});
