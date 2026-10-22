import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {sourceTypedLiteral, nodeTypedLiteral, updateTypedJsonContracts,
  typedJsonClientPin} from './typed-json-literal-contract.mjs';
import {jsonValueWireContractCid, resultSerializationContractCids} from '../packages/sdk/json-value-wire.generated.mjs';
import {parameterPrograms} from './parameter-schema.mjs';
import {checkValuesSchemas} from './values-schema.mjs';
import {checkPivotSchemas} from './pivot-schema.mjs';

test('generated SDK serialization identities match all three independent existing wire vectors', () => {
  const vectors = JSON.parse(readFileSync('portability/corpus/typed-json-literals.json')).serialization_contracts;
  assert.deepEqual(Object.keys(vectors), ['json', 'jsonl', 'csv']);
  assert.deepEqual(resultSerializationContractCids, Object.fromEntries(Object.values(vectors)
    .map(vector => [vector.preimage.version, vector.cid])));
  assert(Object.isFrozen(resultSerializationContractCids));
  for (const vector of Object.values(vectors)) {
    assert.equal(vector.preimage.json_value_wire_contract_cid, jsonValueWireContractCid);
  }
  assert.equal(typedJsonClientPin(), readFileSync('packages/sdk/json-value-wire.generated.mjs', 'utf8'));
});

test('typed literal has explicit JSON domain and opaque source data', () => {
  assert.equal(sourceTypedLiteral.additionalProperties, false);
  assert.deepEqual(sourceTypedLiteral.properties.typed_literal.required, ['type', 'value']);
  assert.deepEqual(sourceTypedLiteral.properties.typed_literal.properties.type, {const:'json'});
  assert.deepEqual(sourceTypedLiteral.properties.typed_literal.properties.value, {type:'string'});
  assert.equal(nodeTypedLiteral.properties.body.additionalProperties, false);
  assert.deepEqual(nodeTypedLiteral.properties.body.required, ['$json']);
  assert.deepEqual(nodeTypedLiteral.properties.body.properties.$json, {});
});

test('every embedded source/node schema and complete artifact pin is current', () => {
  const expressions = JSON.parse(readFileSync('spec/contracts/actql-expressions.json'));
  const protocol = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  updateTypedJsonContracts(expressions, protocol);
  const damaged = structuredClone(expressions);
  const typed = damaged.schemas.expression.$defs.expression.oneOf.find(v => v.properties?.typed_literal);
  typed.properties.typed_literal.properties.type = {type:'string'};
  assert.throws(() => updateTypedJsonContracts(damaged, protocol), /stale source/);
  const missing = structuredClone(expressions);
  missing.schemas.expression.$defs.expression.oneOf = missing.schemas.expression.$defs.expression.oneOf
    .filter(form => form.required?.[0] !== 'typed_literal');
  assert.throws(() => updateTypedJsonContracts(missing, protocol), /stale source/);
  const changed = structuredClone(protocol);
  changed.artifact_schema_cids.executable_plan = 'sha256:' + '0'.repeat(64);
  assert.throws(() => updateTypedJsonContracts(expressions, changed));
});

test('typed expression generation preserves Values whole-cell grammar', () => {
  const expressions = JSON.parse(readFileSync('spec/contracts/actql-expressions.json'));
  const protocol = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  const cells = parameterPrograms(protocol).map(program =>
    structuredClone(program.properties.steps.items.properties.values.properties.rows.items.additionalProperties));
  updateTypedJsonContracts(expressions, protocol, true);
  parameterPrograms(protocol).forEach((program, index) => {
    const cell = program.properties.steps.items.properties.values.properties.rows.items.additionalProperties;
    assert.deepEqual(cell, cells[index]);
    assert.equal(cell.oneOf.length, 3);
    assert.deepEqual(cell.oneOf[2].not.anyOf.map(form => form.required[0]),
      ['$param', 'literal']);
  });
  checkValuesSchemas(protocol);
  assert.deepEqual(expressions.schemas.expression.$defs.expression.oneOf
    .find(form => form.required?.[0] === 'typed_literal'), sourceTypedLiteral);
});

// Evaluate the JSON Schema keywords used by CellValue independently of the
// generator. Cases below come from language.md's whole-value grammar.
function matchesCellSchema(schema, value) {
  if (schema.oneOf && schema.oneOf.filter(form => matchesCellSchema(form, value)).length !== 1) return false;
  if (schema.anyOf && !schema.anyOf.some(form => matchesCellSchema(form, value))) return false;
  if (schema.not && matchesCellSchema(schema.not, value)) return false;
  if (Object.hasOwn(schema, 'const') && schema.const !== value) return false;
  const object = value !== null && typeof value === 'object' && !Array.isArray(value);
  if (schema.type === 'object' && !object) return false;
  if (schema.type === 'string' && typeof value !== 'string') return false;
  if (typeof value === 'string' && schema.pattern && !new RegExp(schema.pattern).test(value)) return false;
  if (object) {
    const keys = Object.keys(value);
    if (schema.required?.some(key => !Object.hasOwn(value, key))) return false;
    if (schema.minProperties !== undefined && keys.length < schema.minProperties) return false;
    if (schema.maxProperties !== undefined && keys.length > schema.maxProperties) return false;
    if (schema.additionalProperties === false && keys.some(key => !Object.hasOwn(schema.properties ?? {}, key))) return false;
    if (Object.entries(schema.properties ?? {}).some(([key, form]) =>
      Object.hasOwn(value, key) && !matchesCellSchema(form, value[key]))) return false;
  }
  return true;
}

test('typed expression generation preserves pivot whole-value data and reserved-root rejection', () => {
  const expressions = JSON.parse(readFileSync('spec/contracts/actql-expressions.json'));
  const expressionBefore = structuredClone(expressions);
  const protocol = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  updateTypedJsonContracts(expressions, protocol, true);
  assert.deepEqual(expressions, expressionBefore);
  checkPivotSchemas(protocol);
  checkValuesSchemas(protocol);
  for (const program of parameterPrograms(protocol)) {
    const fill = program.properties.steps.items.properties.pivot.properties.fill;
    for (const value of [null, false, 0, '0.00', [], {}, {$param:'fill'},
      {literal:{$param:3}}, {nested:{$param:'data'}}, {$param:3, other:true},
      {typed_literal:{type:'json', value:'null'}},
      {typed_literal:{type:'business-data', value:0}}]) {
      assert.equal(matchesCellSchema(fill, value), true, JSON.stringify(value));
    }
    for (const value of [{$param:3}, {$param:null}, {$param:''}, {$param:'bad.name'}]) {
      assert.equal(matchesCellSchema(fill, value), false, JSON.stringify(value));
    }
    assert.equal(fill.oneOf.length, 3);
  }
  assert.deepEqual(expressions.schemas.expression.$defs.expression.oneOf
    .find(form => form.required?.[0] === 'typed_literal'), sourceTypedLiteral);
});

test('typed literal checker rejects and writer removes polluted pivot alternatives in both copies', () => {
  const expressions = JSON.parse(readFileSync('spec/contracts/actql-expressions.json'));
  const protocol = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  updateTypedJsonContracts(expressions, protocol, true);
  for (const index of [0, 1]) {
    const damaged = structuredClone(protocol);
    const fill = parameterPrograms(damaged)[index].properties.steps.items.properties.pivot.properties.fill;
    fill.oneOf.push({type:'object', additionalProperties:false,
      required:['typed_literal'], properties:{typed_literal:{type:'object',
        additionalProperties:false, required:['type','value'],
        properties:{type:{const:'json'}, value:{type:'string'}}}}});
    assert.throws(() => updateTypedJsonContracts(expressions, damaged), /CellValue/);
    updateTypedJsonContracts(expressions, damaged, true);
    assert.deepEqual(damaged, protocol);
  }
});

test('typed literal writer preserves current registry bytes and is idempotent', () => {
  const paths = ['spec/contracts/actql-expressions.json',
    'spec/contracts/actql-protocol-schemas.json'];
  const original = paths.map(path => readFileSync(path, 'utf8'));
  const bodies = original.map(body => JSON.parse(body));
  for (let attempt = 0; attempt < 2; attempt++) {
    updateTypedJsonContracts(...bodies, true);
    bodies.forEach((body, index) =>
      assert.equal(JSON.stringify(body, null, 2) + '\n', original[index]));
    updateTypedJsonContracts(...bodies);
  }
});

test('typed literal writer ignores unrelated lookalike schemas and nested example data', () => {
  const expressions = JSON.parse(readFileSync('spec/contracts/actql-expressions.json'));
  const protocol = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  // Authored independently of the generator's root list and exported arms.
  // The old recursive writer would insert or remove alternatives here.
  const sourceData = {oneOf:[{type:'object', additionalProperties:false,
    required:['literal'], properties:{literal:{}}}]};
  const machineData = {oneOf:[{type:'object', properties:{op:{const:'literal'}}}]};
  const wholeData = {oneOf:[
    {not:{type:'object', minProperties:1, maxProperties:1,
      anyOf:[{required:['$param']}, {required:['literal']}]}},
    {required:['typed_literal'], properties:{typed_literal:{const:'business-data'}}},
  ]};
  const examples = [sourceData, machineData, wholeData];
  expressions.schemas.unrelated_data = structuredClone(examples);
  expressions.schemas.expression.$defs.expression.examples = structuredClone(examples);
  protocol.schemas.unrelated_data = structuredClone(examples);
  protocol.artifact_schemas.executable_plan.examples = structuredClone(examples);
  updateTypedJsonContracts(expressions, protocol, true);
  for (const actual of [expressions.schemas.unrelated_data,
    expressions.schemas.expression.$defs.expression.examples,
    protocol.schemas.unrelated_data,
    protocol.artifact_schemas.executable_plan.examples]) {
    assert.deepEqual(actual, examples);
  }
  // Read-only validation also ignores lookalikes with no generated typed arm.
  updateTypedJsonContracts(expressions, protocol);
});

test('typed literal ownership covers each current expression and EffectValue arm', () => {
  const expressions = JSON.parse(readFileSync('spec/contracts/actql-expressions.json'));
  const protocol = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  // Enumerate expected owners in the test without importing a product table.
  const source = [expressions.schemas.expression.$defs.expression,
    expressions.schemas.fragment.$defs.source_expression,
    expressions.schemas.predicate_consumer.$defs.source_expression];
  const machine = [expressions.schemas.expression_node.$defs.expression,
    expressions.schemas.fragment.$defs.machine_expression,
    expressions.schemas.predicate_consumer.$defs.machine_expression];
  const programs = [protocol.artifact_schemas.executable_plan.properties.execution_material.properties.program,
    protocol.artifact_schemas.plan_document.properties.plan.properties.execution_material.properties.program];
  for (const program of programs) {
    source.push(program.$defs.predicate, program.$defs.value_expression);
    for (const [operation, member] of [['update', 'set'], ['upsert', 'set'], ['command', 'input']]) {
      const body = program.properties.effects.additionalProperties.oneOf
        .find(form => form.properties?.[operation]).properties[operation];
      source.push(body.properties[member].additionalProperties);
    }
  }
  assert.equal(source.length, 13);
  assert.equal(machine.length, 3);
  for (const schema of source) {
    schema.oneOf = schema.oneOf.filter(form => form.required?.[0] !== 'typed_literal');
  }
  for (const schema of machine) {
    schema.oneOf = schema.oneOf.filter(form => form.properties?.op?.const !== 'typed_literal');
  }
  const withoutOwnedArms = structuredClone([expressions, protocol]);
  updateTypedJsonContracts(expressions, protocol, true);
  // Missing-arm repair owns the new arm, not its historical position among
  // alternatives later added by other writers. Preserve every foreign arm's
  // exact body and order. Current-registry byte idempotence is tested separately.
  for (const [schemas, typed, expected] of [
    [source, form => form.required?.[0] === 'typed_literal', sourceTypedLiteral],
    [machine, form => form.properties?.op?.const === 'typed_literal', nodeTypedLiteral],
  ]) {
    for (const schema of schemas) {
      assert.deepEqual(schema.oneOf.filter(typed), [expected]);
    }
  }
  // Reordered canonical preimages must carry their corresponding new pins.
  // Validate them before excluding only the owned arms and these verified pins
  // from the full foreign-content comparison. No registry file is written.
  updateTypedJsonContracts(expressions, protocol);
  for (const schema of source) {
    schema.oneOf = schema.oneOf.filter(form => form.required?.[0] !== 'typed_literal');
  }
  for (const schema of machine) {
    schema.oneOf = schema.oneOf.filter(form => form.properties?.op?.const !== 'typed_literal');
  }
  protocol.artifact_schema_cids = withoutOwnedArms[1].artifact_schema_cids;
  protocol.artifact_registry_cid = withoutOwnedArms[1].artifact_registry_cid;
  assert.deepEqual([expressions, protocol], withoutOwnedArms);
});

test('typed literal ownership rejects missing, duplicate and aliased roots before writing', () => {
  for (const mutate of [
    expressions => { delete expressions.schemas.fragment.$defs.source_expression; },
    expressions => { expressions.schemas.fragment.$defs.machine_expression =
      expressions.schemas.expression_node.$defs.expression; },
    expressions => {
      const schema = expressions.schemas.predicate_consumer.$defs.source_expression;
      schema.oneOf.push(structuredClone(schema.oneOf.find(form =>
        form.required?.[0] === 'typed_literal')));
    },
  ]) {
    const expressions = JSON.parse(readFileSync('spec/contracts/actql-expressions.json'));
    const protocol = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
    mutate(expressions);
    const before = structuredClone([expressions, protocol]);
    for (const write of [false, true]) {
      assert.throws(() => updateTypedJsonContracts(expressions, protocol, write),
        /Missing owned|Duplicate owned/);
      assert.deepEqual([expressions, protocol], before);
    }
  }
});

test('ordered derive and expression fragments bind the integrated expression law', async () => {
  const {createHash} = await import('node:crypto');
  const canonical = value => Array.isArray(value) ? `[${value.map(canonical)}]`
    : value !== null && typeof value === 'object'
      ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
      : JSON.stringify(value);
  const expressions = JSON.parse(readFileSync('spec/contracts/actql-expressions.json'));
  const aoa = JSON.parse(readFileSync('spec/contracts/actql-aoa.json'));
  const expected = `sha256:${createHash('sha256').update(canonical(expressions)).digest('hex')}`;
  assert.equal(aoa.execution_contracts['REL.derive.ordered'].dependencies.expression_contract.cid, expected);
  assert.equal(aoa.execution_contracts['ACTQL.expression_fragment/0.1'].dependencies.expression_contract.cid, expected);
});
