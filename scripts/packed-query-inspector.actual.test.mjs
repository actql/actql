// Explicit diagnostic capability test, not ordinary packed product acceptance.
// Run this file deliberately; unavailable/aborted instrumentation is not a pass.
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {observePackedSubmissionCause} from './fixtures/packed-query-transport-owner.mjs';

test('explicit Inspector diagnostic preserves a plain original throw through resume and close', {timeout: 10_000}, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-explicit-inspector-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'original-ingress.mjs');
  await writeFile(path, `const publicFailure = error => error;
function unusedResult(original) {
  try {throw original;}
  catch (error) {
    throw publicFailure(error);
  }
}
export function originalIngress(original) {
  try {throw original;}
  catch (error) {
    throw publicFailure(error);
  }
}
`);
  const sourceURL = pathToFileURL(path), target = await import(sourceURL.href), reports = [];
  const primary = Object.assign(new Error('private-original'), {code: 'EIO'});
  const observer = await observePackedSubmissionCause({enabled: true, sourceURL,
    report: value => reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  await observer.close();
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, true, 'Inspector unavailable: diagnostic capability not established');
  assert.deepEqual(reports[0].originalCauseTypes, [[{edge: 'original', type: 'Error', code: 'EIO'}]]);
  assert.doesNotMatch(JSON.stringify(reports), /private-original|message|stack/u);
  assert.throws(() => target.originalIngress(primary), error => error === primary);
});
