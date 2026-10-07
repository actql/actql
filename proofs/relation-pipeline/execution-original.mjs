// Shared raw-original consumer. It binds an execution, not a full campaign.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {hash} from './inventory.mjs';
import {auditFixture, payload, inputVariable} from './fixture.mjs';
import {program} from './engine.mjs';
import {registry} from './registry.mjs';

export function readExecutionFiles(directory, executions) {
  const files = {};
  for (const {path, receipt} of executions) for (const input of [path, receipt.sourcePath, receipt.logPath, receipt.inputPath, receipt.fixturePath]) {
    assert(/^\.artifacts\/relation-pipeline\/[A-Za-z0-9_.\/-]+$/u.test(input) && !input.split('/').includes('..'), 'Unregistered original path');
    files[input] = readFileSync(join(directory, input), 'utf8');
  }
  return files;
}

export function validateExecutionOriginal({execution, source, files, testCase, target, role, correspondence}) {
  const run = execution.receipt;
  assert.equal(hash(JSON.stringify(run)), execution.digest);
  assert.deepEqual(JSON.parse(files[execution.path]), run);
  assert.equal(run.target, target); assert.equal(run.correspondence, correspondence);
  assert.equal(run.boundary.role, role); assert.equal(run.sourceDigest, source.digest);
  assert.deepEqual(JSON.parse(files[run.sourcePath]), source);
  assert.equal(run.cases.length, 1); assert.deepEqual(run.cases[0].testCase, testCase);
  assert.equal(run.cases[0].caseDigest, hash(JSON.stringify(testCase)));
  assert.equal(run.inputVariable, inputVariable);
  const inputs = payload(run.cases, correspondence);
  assert.equal(files[run.inputPath], inputs); assert.equal(hash(inputs), run.inputDigest);
  const log = files[run.logPath]; assert.equal(hash(log), run.logDigest);
  auditFixture(run, files[run.fixturePath], log, target);
  let id, faults = []; const observations = [];
  for (const line of log.split('\n')) {
    if (line.startsWith('ACTQL_PIPELINE_CASE:')) { id = JSON.parse(line.slice(20)); faults = []; }
    if (line.startsWith('ACTQL_PIPELINE_FAULT:')) faults.push(JSON.parse(line.slice(21)));
    if (line.startsWith('ACTQL_PIPELINE:')) {
      const actual = JSON.parse(line.slice(15)); assert.equal(actual.id, id);
      observations.push({...actual, tableRows: actual.rows,
        rows: actual.wireRows.map(row => actual.columns.map(field => row[field])), faults});
    }
  }
  assert.deepEqual(run.cases.map(entry => entry.observation), observations);
  assert(observations[0]?.checked && observations[0]?.registered);
  assert(Object.keys(run.artifacts).length > 0);
  for (const path of Object.keys(run.artifacts))
    assert(path.startsWith(`_build/${target}/debug/test/query_integration/`) && /^[a-f0-9]{64}$/u.test(run.artifacts[path]));
  return observations[0];
}

export function validateRequestedProgram(run) {
  for (const entry of run.cases) {
    const expected = program(entry.testCase, registry);
    assert.deepEqual(entry.program, expected, 'Requested pipeline Program differs from independent minimum');
    assert.equal(entry.observation.source, expected.source, 'Executed Source differs from requested Program');
    assert.equal(entry.observation.steps, expected.steps, 'Executed steps differ from requested Program');
  }
  return true;
}
