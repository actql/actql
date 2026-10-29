import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {updateArrayOffsetContracts, arrayOffsetLaws} from './array-offset-expression-contract.mjs';
import {machineCid} from './actql-spec-family.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const prior = JSON.parse(gunzipSync(readFileSync('scripts/fixtures/array-offset/predecessor.json.gz')));
const expressionPath = 'spec/contracts/actql-expressions.json';
const protocolPath = 'spec/contracts/actql-protocol-schemas.json';
const grammar = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');

test('array offset contract registers every closed source and machine embedding', () => {
  assert.deepEqual(updateArrayOffsetContracts(read(expressionPath),read(protocolPath),grammar),{source:14,node:6});
  const expressions = read(expressionPath), protocol = read(protocolPath);
  const shapes = expressions.schemas.expression.$defs.expression.oneOf;
  const offset = shapes.find(x => x.properties?.array_offset);
  assert.deepEqual(offset.properties.array_offset.required,['value','index']);
  assert.equal(offset.properties.array_offset.additionalProperties,false);
  offset.properties.array_offset.additionalProperties = true;
  assert.throws(() => updateArrayOffsetContracts(expressions,protocol,grammar), /stale/);
  assert.throws(() => updateArrayOffsetContracts(read(expressionPath),read(protocolPath),grammar.replace('"array_offset"','"not_array_offset"')), /missing/);
});

test('offset and safe offset retain distinct out-of-range laws and existing subscript meaning', () => {
  assert.match(arrayOffsetLaws.array_offset.value,/outside-array indexes fail evaluation/);
  assert.match(arrayOffsetLaws.array_safe_offset.value,/outside-array indexes return NULL/);
  assert.deepEqual(read(expressionPath).laws.access,prior.bodies[expressionPath].laws.access);
  assert.equal(prior.source_commit,'f74d8e6436f314092b412669ba1281d246b604a4');
  assert.equal(machineCid(prior.bodies[expressionPath]),'sha256:76278686ed580a90862ab54680c2e1969b8e3c6b5bec8078e0049e5d9079e9f8');
  assert.equal(machineCid(prior.bodies[protocolPath]),'sha256:b427868d155dc9390894b0fbf4c735955fd16c3e4bed1d6c3979bb86d715352c');
});

test('registration preserves the complete fixed predecessor except the declared extension', () => {
  // Exercise this exact historical transition on its complete retained owners.
  // Later model-resource artifact changes are independently governed and must
  // not be mistaken for changes made by the array-offset registration.
  const expressions = structuredClone(prior.bodies[expressionPath]);
  const protocol = structuredClone(prior.bodies[protocolPath]);
  const countShapes = roots => {
    const counts = {source: 0, node: 0};
    const visit = value => {
      if (!value || typeof value !== 'object') return;
      for (const shape of value.oneOf ?? []) {
        for (const name of ['array_offset', 'array_safe_offset']) {
          if (shape.required?.includes(name)) counts.source++;
          if (shape.properties?.op?.const === name) counts.node++;
        }
      }
      for (const child of Object.values(value)) visit(child);
    };
    roots.forEach(visit);
    return counts;
  };
  assert.deepEqual(countShapes([expressions.schemas, protocol.artifact_schemas]),
    {source: 0, node: 0});
  updateArrayOffsetContracts(expressions, protocol, grammar, true);
  // Count actual inserted shapes independently of the updater's return value.
  // A no-op registration cannot satisfy the round-trip preservation assertion.
  assert.deepEqual(countShapes([expressions.schemas, protocol.artifact_schemas]),
    {source: 14, node: 6});
  const remove = value => {
    if (!value || typeof value !== 'object') return;
    if (Array.isArray(value.oneOf)) value.oneOf=value.oneOf.filter(x =>
      !['array_offset','array_safe_offset'].some(name=>x.required?.includes(name)||x.properties?.op?.const===name));
    for(const x of Object.values(value)) remove(x);
  };
  remove(expressions.schemas);remove(protocol.artifact_schemas);
  delete expressions.laws.array_offset;delete expressions.laws.array_safe_offset;
  expressions.grammar_sha256=prior.bodies[expressionPath].grammar_sha256;
  assert.deepEqual(expressions,prior.bodies[expressionPath]);
  for(const [name,schema] of Object.entries(protocol.artifact_schemas)) protocol.artifact_schema_cids[name]=machineCid(schema);
  protocol.artifact_registry_cid=machineCid(protocol.artifact_schemas);
  assert.deepEqual(protocol,prior.bodies[protocolPath]);
});
