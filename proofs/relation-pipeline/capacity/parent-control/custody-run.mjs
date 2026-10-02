import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, existsSync, unlinkSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { root, environment, moon, toolchain } from '../../execute.mjs';
import { custodyInput, custodyOverlay, auditCustody } from './custody.mjs';
import { snapshot, hash } from '../../inventory.mjs';
import { artifacts } from '../../../bounded-session/evidence.mjs';
import { generatedObservers, installGeneratedObservers,
  restoreGeneratedObservers } from '../instrument.mjs';

const target = process.argv[2] ?? 'js';
assert(['js', 'wasm', 'native'].includes(target));
assert(!process.argv[3] || process.argv[3] === '--expect-fixed');
const mode = process.argv[4] ?? 'normal';
assert(['normal', 'pending', 'success'].includes(mode));
const { case: case_, program: input } = custodyInput();
const source = snapshot(root);
const read = path => readFileSync(join(root, path));
const { originals, overlay, fixture, variable } = custodyOverlay(read, mode);
assert(!existsSync(join(root, fixture)), 'Foreign custody fixture');
assert(Object.keys(generatedObservers).every(p => !existsSync(join(root, p))), 'Foreign generated observer');
const directory = '.artifacts/relation-pipeline/capacity/custody';
mkdirSync(join(root, directory), { recursive: true });
const prefix = `${directory}/${Date.now()}-${process.pid}-${target}`;
const command = ['test', fixture, '--target', target, '--deny-warn'];
let ownsFixture = false;
try {
  installGeneratedObservers(root);
  writeFileSync(join(root, fixture), overlay[fixture], { flag: 'wx' }); ownsFixture = true;
  for (const p of Object.keys(originals)) writeFileSync(join(root, p), overlay[p]);
  const executedSource = snapshot(root);
  writeFileSync(join(root, `${prefix}.source.json`), JSON.stringify(executedSource, null, 2) + '\n');
  writeFileSync(join(root, `${prefix}.fixture.mbt`), overlay[fixture]);
  writeFileSync(join(root, `${prefix}.input.json`), JSON.stringify({ case: case_, program: input }, null, 2) + '\n');
  const result = spawnSync(moon, command, { cwd: root, env: { ...environment,
    [variable]: JSON.stringify(input), ACTQL_RELATION_PIPELINE_CUSTODY_MODE: mode }, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  const log = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  writeFileSync(join(root, `${prefix}.log`), log);
  if (result.status !== 0) { process.stderr.write(log); throw result.error ?? new Error(`Custody diagnostic exit ${result.status}`); }
  const rows = log.split('\n').filter(l => l.startsWith('ACTQL_CUSTODY:')).map(l => JSON.parse(l.slice(14)));
  assert.equal(rows.length, 1);
  const observed = rows[0];
  assert(log.includes('ACTQL_CUSTODY_CHAIN:started'), 'Actual serial chain was not started');
  const after = log.indexOf(mode === 'success' ?
    'ACTQL_CUSTODY_STAGE:after-completion-before-cleanup' :
    'ACTQL_CUSTODY_STAGE:after-settlement-before-cleanup');
  const cleanup = log.indexOf('"event":"before-cleanup"');
  const cleaned = log.indexOf('"event":"after-cleanup"');
  assert(after >= 0 && cleanup >= 0 && cleaned > cleanup, 'No actual child cleanup observed');
  const prematureReleaseCandidate = BigInt(observed.before) - BigInt(observed.after) ===
    BigInt(observed.executionCapacity) && cleanup > after;
  const executedArtifacts = artifacts(root, target, 'query_integration');
  const archives = {};
  mkdirSync(join(root, directory, 'binaries'), { recursive: true });
  for (const [path, digest] of Object.entries(executedArtifacts)) {
    const archive = `${directory}/binaries/${digest}`;
    if (!existsSync(join(root, archive))) copyFileSync(join(root, path), join(root, archive));
    assert.equal(hash(read(archive)), digest); archives[path] = archive;
  }
  const receipt = { version: 'actql-relation-custody/0.1', target, mode, toolchain, source, executedSource, command: ['moon', ...command],
    exit: result.status, inputVariable: variable, inputDigest: hash(JSON.stringify(input)),
    inputPath: `${prefix}.input.json`, fixturePath: `${prefix}.fixture.mbt`,
    logPath: `${prefix}.log`, logDigest: hash(log),
    overlays: Object.fromEntries(Object.entries({ ...generatedObservers, ...overlay }).map(([p, text]) => [p, hash(text)])),
    artifacts: executedArtifacts, archives, observation: observed,
    prematureReleaseCandidate,
    physicalGcCompletion: false, completeAllocationUpper: false };
  // Retain the executed artifact and receipt even when the admission assertion
  // exposes a product defect. A failed receipt is never accepted by the gate.
  writeFileSync(join(root, `${prefix}.receipt.json`), JSON.stringify(receipt, null, 2) + '\n');
  if (process.argv[3]) {
    assert.equal(prematureReleaseCandidate, false, 'Scratch credited before child cleanup');
    assert(cleanup > after, 'Settlement/disposal must not poll child cleanup');
    assert.equal(observed.after, observed.before, 'Settlement lost scratch before explicit cleanup');
    if (mode !== 'pending') assert(!log.includes('ACTQL_CUSTODY_RETRY:'));
    else {
      assert(cleaned > after, 'Pending child cleanup was not exercised');
      assert(log.includes('ACTQL_CUSTODY_RETRY:false') && log.includes('ACTQL_CUSTODY_RETRY:error'));
      assert.equal(observed.after, observed.before, 'Pending/error cleanup lost its existing reservation');
    }
    assert.equal(observed.workAfter, observed.workBefore, 'Dropping provider lost cumulative physical work');
  }
  if (process.argv[3]) auditCustody(receipt, target, mode, source, p => originals[p] ?? read(p));
  console.log(JSON.stringify({ path: `${prefix}.receipt.json`, observation: observed,
    prematureReleaseCandidate: receipt.prematureReleaseCandidate }));
} finally {
  for (const [p, text] of Object.entries(originals)) writeFileSync(join(root, p), text);
  if (ownsFixture) unlinkSync(join(root, fixture));
  restoreGeneratedObservers(root);
  assert.equal(snapshot(root).digest, source.digest, 'Custody diagnostic source restoration failed');
}
