import { readFileSync, writeFileSync, unlinkSync, existsSync, mkdirSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { execute, executions, root, environment, toolchain } from '../../execute.mjs';
import { registry } from '../../registry.mjs';
import { snapshot, hash } from '../../inventory.mjs';
import { generatedObservers, installGeneratedObservers, restoreGeneratedObservers } from '../instrument.mjs';
import { checkNativeRuntime } from '../backing/source.mjs';
import { parentOverlay, helper, paths } from './overlay.mjs';
import { auditParentStartup, parentCase, directory } from './audit.mjs';
import { rejectParentSubstitutions } from './regression.mjs';
import { checkParentCensus, inspectParentCorePhases } from './bounds.mjs';

// The C reader borrows existing roots only for this synchronous call.
// It never stores a MoonBit pointer, changes RC, or adds a persistent holder.
const read = path => readFileSync(join(root, path));
const source = snapshot(root);
checkParentCensus(read);
const originals = Object.fromEntries(paths.map(path => [path, read(path)]));
const overlay = parentOverlay(read);
const nativeRuntime = checkNativeRuntime(environment.MOON_HOME, toolchain);
assert(!existsSync(join(root, helper)), 'Foreign parent observation helper');
assert(Object.keys(generatedObservers).every(path => !existsSync(join(root, path))), 'Another task owns a temporary capacity observer');
mkdirSync(join(root, directory), { recursive: true });
const command = ['node', 'proofs/relation-pipeline/capacity/parent-control/check.mjs'];
const model = spawnSync(process.execPath, command.slice(1), { cwd: root, env: environment, encoding: 'utf8' });
const modelLog = `${model.stdout ?? ''}${model.stderr ?? ''}`;
assert.equal(model.status, 0, modelLog);
const modelDigest = hash(modelLog);
const modelPath = `${directory}/models/${modelDigest}.log`;
mkdirSync(join(root, directory, 'models'), { recursive: true });
writeFileSync(join(root, modelPath), modelLog);
const modelReceipt = { command, exit: model.status, sourceDigest: source.digest,
  logPath: modelPath, logDigest: modelDigest };
const modelReceiptPath = `${directory}/models/${hash(JSON.stringify(modelReceipt))}.json`;
writeFileSync(join(root, modelReceiptPath), JSON.stringify(modelReceipt, null, 2) + '\n');
let ownsHelper = false;
let installed = false;
let report;
try {
  installGeneratedObservers(root);
  installed = true;
  writeFileSync(join(root, helper), overlay[helper], { flag: 'wx' });
  ownsHelper = true;
  for (const [path, code] of Object.entries(overlay)) if (path !== helper) writeFileSync(join(root, path), code);
  const testCase = parentCase();
  const observation = execute([testCase], registry, 'native', true, 'parent-control-startup')[0];
  const execution = executions.at(-1);
  execution.parentArchives = {};
  for (const [path, digest] of Object.entries(execution.receipt.artifacts)) {
    const archive = `${directory}/binaries/${digest}`;
    mkdirSync(join(root, directory, 'binaries'), { recursive: true });
    if (!existsSync(join(root, archive))) copyFileSync(join(root, path), join(root, archive));
    assert.equal(hash(read(archive)), digest);
    execution.parentArchives[path] = archive;
  }
  assert.deepEqual(checkNativeRuntime(environment.MOON_HOME, toolchain), nativeRuntime);
  report = { version: 'actql-native-parent-startup/0.1', target: 'native', source, toolchain,
    nativeRuntime, model: { ...modelReceipt, receiptPath: modelReceiptPath },
    overlays: Object.fromEntries(Object.entries(overlay).map(([path, code]) => [path, hash(code)])),
    case: testCase, observation, execution,
    scope: 'two-child native startup requested object extents; not a full parent upper bound or total-reservation violation',
    unconditionalAllocationBytes: false };
  report.retainedCore = inspectParentCorePhases(testCase,
    observation.faults.find(f => f.kind === 'parent control investigation'),
    observation.faults.filter(f => f.kind === 'parent core observation'), 'native');
} finally {
  for (const [path, code] of Object.entries(originals)) writeFileSync(join(root, path), code);
  if (installed) for (const [path, code] of Object.entries(generatedObservers)) writeFileSync(join(root, path), code);
  if (ownsHelper) unlinkSync(join(root, helper));
  restoreGeneratedObservers(root);
  assert.equal(snapshot(root).digest, source.digest, 'Parent probe source restoration failed');
}
const result = auditParentStartup(report, source, read);
console.log(rejectParentSubstitutions(report, source, read));
writeFileSync(join(root, directory, 'all.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(result));
