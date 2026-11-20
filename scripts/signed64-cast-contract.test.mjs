import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const predecessor = JSON.parse(gunzipSync(readFileSync(
  'scripts/fixtures/pre-sql-integer-support-identities.json.gz')));

test('SQL integer support retains complete published expression and Stage identity preimages', () => {
  assert.equal(predecessor.source_commit, '2ddbaa90b6bf349a057d9e11b433ae957b19b7a6');
  assert.equal(predecessor.expression_contract_cid,
    'sha256:2849a6667980fc51ed51a04879470a97068fd08e358d784262602a09b22dacda');
  assert.equal(machineCid(predecessor.records['spec/contracts/actql-expressions.json']),
    predecessor.expression_contract_cid);
  for (const name of ['stage-semantics', 'local-unit-stage-body']) {
    const original = predecessor.records[`portability/corpus/${name}.json`];
    assert.equal(original.cases.length, 3);
    for (const fixture of original.cases) {
      assert.equal(fixture.envelope.expression_contract_cid, predecessor.expression_contract_cid);
      assert.equal(machineCid(fixture.envelope), fixture.expected_cid);
    }
  }
  const stages = predecessor.records['portability/corpus/stage-semantics.json'];
  for (const fixture of predecessor.records['portability/corpus/stage-definition.json'].cases) {
    const stage = stages.cases.find(value => value.name === fixture.stage_case);
    assert(stage);
    assert.equal(machineCid({version: 'actql-stage-definition/0.1', id: fixture.id,
      stage_semantics_cid: stage.expected_cid}), fixture.expected_cid);
  }
});

test('INT64 has a closed cast target in original source, machine and containing Program schemas', () => {
  const expressions = read('spec/contracts/actql-expressions.json');
  const protocol = read('spec/contracts/actql-protocol-schemas.json');
  const scopes = [
    [expressions.schemas.expression.$defs.expression, 'source'],
    [expressions.schemas.expression_node.$defs.expression, 'node'],
    [expressions.schemas.fragment.$defs.source_expression, 'source'],
    [expressions.schemas.fragment.$defs.machine_expression, 'node'],
    [expressions.schemas.predicate_consumer.$defs.source_expression, 'source'],
    [expressions.schemas.predicate_consumer.$defs.machine_expression, 'node'],
    ...['executable_plan', 'plan_document'].flatMap(name => {
      const artifact = protocol.artifact_schemas[name];
      const program = (name === 'plan_document' ? artifact.properties.plan : artifact)
        .properties.execution_material.properties.program;
      return [program.$defs.predicate, program.$defs.value_expression].map(scope => [scope, 'source']);
    }),
  ];
  for (const [scope, kind] of scopes) {
    const casts = scope.oneOf.filter(shape => kind === 'source'
      ? shape.properties?.cast : shape.properties?.op?.const === 'cast');
    assert.equal(casts.length, 1);
    const body = kind === 'source' ? casts[0].properties.cast : casts[0].properties.body;
    const target = body.properties.target.oneOf.find(shape => shape.properties?.type?.enum?.includes('int64'));
    assert(target);
    assert.equal(target.additionalProperties, false);
    assert.deepEqual(target.required, ['type']);
    assert.deepEqual(Object.keys(target.properties), ['type']);
  }
});

test('the full-range SQL cast input retains its independent source identity without a Number intermediary', () => {
  const expected = {cast: {target: {type: 'int64'}, value: {literal: '9007199254740993'}}};
  assert.equal(machineCid(expected),
    'sha256:1695a6f276898281dd683d703c5decddb8d92bc214ae5a63f29a396e32e4e3d6');
  const fixture = read('portability/corpus/actql-expression-text-v0.1.json').positive
    .find(value => value.source === "CAST('9007199254740993' AS INT64)");
  assert(fixture);
  assert.deepEqual(fixture.tree, expected);
});
