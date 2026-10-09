import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {admitEnvironment, prepareProgram, prepare, prepareEffect, compileValues,
  compileEffect, effectExecutionShape, privateEffectCompilationWires,
  prepareRequest, requestFields} from '@actql/run-host-core';

const fixture = name => readFileSync(new URL(name, import.meta.url), 'utf8');
const effectDocument = fixture('./fixtures/source-compute-effect.program.json');
const effectWire = fixture('./fixtures/source-compute-effect.environment.json').trimEnd();
const effectEnvironment = admitEnvironment(effectWire,
  JSON.parse(effectWire).evidence_bundle_cid, {rela: true});
const pureDocument = fixture('../sdk/fixtures/parameter-values.json');
const pureWire = fixture('../sdk/fixtures/values.environment.json').trimEnd();
const pureEnvironment = admitEnvironment(pureWire,
  JSON.parse(pureWire).evidence_bundle_cid, {rela: true});
const cid = letter => 'sha256:' + letter.repeat(64);

test('parsed Effect selection preserves the original two-task semantic Owner', () => {
  const selected = prepareProgram(effectDocument, 'json', effectEnvironment);
  assert.equal(selected.kind, 'effect');
  assert(Object.isFrozen(selected));
  const compilation = compileEffect(selected.prepared);
  assert.deepEqual(effectExecutionShape(selected.prepared, compilation),
    {taskCount: 2, acquisitionCount: 1, effectCount: 1});
  assert.deepEqual(privateEffectCompilationWires(compilation),
    privateEffectCompilationWires(compileEffect(prepareEffect(effectDocument,
      'json', effectEnvironment))));
  assert.throws(() => compileValues(selected.prepared), /ForeignRunHostHandle/u);
});

test('parsed Pure selection preserves supplied values and the existing request identity', () => {
  const selected = prepareProgram(pureDocument, 'json', pureEnvironment, '{"n":3}');
  assert.equal(selected.kind, 'effect_free');
  compileValues(selected.prepared);
  assert.deepEqual(requestFields(prepareRequest(selected.prepared, cid('a'),
    'original-request', cid('b'))), requestFields(prepareRequest(
    prepare(pureDocument, 'json', pureEnvironment, '{"n":3}'), cid('a'),
    'original-request', cid('b'))));
  assert.throws(() => compileEffect(selected.prepared), /ForeignRunHostHandle/u);
});

test('a data field named effects cannot select the Effect Owner', () => {
  const program = JSON.parse(pureDocument);
  const values = program.stages[0].steps[0].values;
  values.schema.effects = {type: 'string', nullable: false};
  values.rows[0].effects = 'not an Effect declaration';
  const selected = prepareProgram(JSON.stringify(program), 'json', pureEnvironment, '{"n":3}');
  assert.equal(selected.kind, 'effect_free');
  compileValues(selected.prepared);
});

test('invalid syntax, values, environment and Effect closure never fall back to Pure preparation', () => {
  for (const document of ['{', effectDocument.replace('mapping:crm.account.v1', 'mapping:missing.v1')]) {
    assert.throws(() => prepareProgram(document, 'json', effectEnvironment),
      {code: 'RunHostProgramPreparationRejected'});
  }
  for (const values of ['{', JSON.stringify({n: 'x'.repeat(65536)})]) {
    assert.throws(() => prepareProgram(pureDocument, 'json', pureEnvironment, values),
      {code: 'RunHostProgramPreparationRejected'});
  }
  assert.throws(() => prepareProgram(pureDocument, 'json', {...pureEnvironment}),
    /ForeignRunHostHandle/u);
  assert.throws(() => prepareProgram(pureDocument, 'sql', pureEnvironment),
    /InvalidRunHostPreparation/u);
});
