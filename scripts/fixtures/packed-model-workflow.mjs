// Wrap the unchanged public README consumer. No second close or recovery Run.
import assert from 'node:assert/strict';
import {readFile, lstat} from 'node:fs/promises';
import {resolve} from 'node:path';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';
const phase = process.argv[2];
assert(['capture', 'approve', 'recover'].includes(phase));
const registry = JSON.parse(await readFile('model-tasks.json', 'utf8'));
assert.equal(Object.keys(registry.tasks).length, 129);
const config = JSON.parse(await readFile('actql.config.json', 'utf8'));
assert.equal(Object.keys(config.mock.answers).length, 2);
const removed = ['deal-review.program.json', ...Object.values(config.mock.answers).map(path => path.replace(/^\.\//u, ''))];
if (phase !== 'capture') for (const path of removed) await assert.rejects(lstat(path), {code: 'ENOENT'});
let failed = false, primary;
try {await import('./workflow-original.mjs');} catch (error) {failed = true; primary = error;}
let observation, diagnostic;
try {
  const fd = await observeRecordApprovalDescriptors([resolve('.actql'), resolve('mock')]);
  observation = {after: fd.openPaths.length}; assert.equal(fd.openPaths.length, 0);
} catch (error) {diagnostic = error;}
console.log(JSON.stringify({kind: 'model-registry-workflow', phase, pid: process.pid,
  registeredMetadata: 129, selectedModelTasks: 2, selectedCallsOnCapture: 4,
  claims129SelectedSlots: false, originalImportFailed: failed,
  inputsAbsentBeforeRecovery: phase !== 'capture', aliveScopedFD: observation,
  diagnosticCode: diagnostic?.code}));
if (failed) throw primary;
if (diagnostic) throw diagnostic;
