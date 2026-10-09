import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {admitEnvironment, prepare, compileValues, compileTasks,
  resultSchema, taskResultSchema} from '@actql/run-host-core';
const read = name => readFileSync(new URL(`../sdk/fixtures/${name}`, import.meta.url), 'utf8');
const environmentWire = read('values.environment.json').trimEnd();
const evidenceCid = JSON.parse(environmentWire).evidence_bundle_cid;


for (const mode of ['values', 'tasks']) {
  test(`portable ${mode} schema preserves canonical numeric field names`, () => {
    const document = JSON.parse(read('values.json'));
    const stage = document.stages[0];
    stage.steps[0].values = {
      schema: {'10': {type: 'number', nullable: false}, '2': {type: 'number', nullable: false}},
      rows: [{'10': 10, '2': 2}],
    };
    stage.results.rows.fields = ['10', '2'];
    const prepared = prepare(JSON.stringify(document), 'json',
      admitEnvironment(environmentWire, evidenceCid, {rela: true}));
    const actual = mode === 'values'
      ? resultSchema(prepared, compileValues(prepared))
      : taskResultSchema(prepared, compileTasks(prepared), 'answer');
    const wire = '{"10":{"nullable":false,"type":"number"},"2":{"nullable":false,"type":"number"}}';
    assert.deepEqual(actual, {wire, fields: ['10', '2'],
      cid: 'sha256:' + createHash('sha256').update(wire).digest('hex')});
  });
}
