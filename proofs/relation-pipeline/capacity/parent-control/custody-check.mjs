import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { snapshot, hash } from '../../inventory.mjs';
import { auditCustody, custodyDirectory } from './custody.mjs';
const root = fileURLToPath(new URL('../../../../', import.meta.url));
const requested = process.argv[2] ?? 'all';
assert(['js', 'all'].includes(requested));
const targets = requested === 'all' ? ['js', 'wasm', 'native'] : ['js'];
const current = snapshot(root), records = [];
// Reintroduce only the actual premature retirement condition. This is a JS
// mutation check, separate from normal finite correspondence on every target.
const site = 'src/physical_strategy/task_execution.mbt';
const original = readFileSync(join(root, site));
const before = 'scratch_released: @connector.prepared_managed_execution_scratch_release_condition(\n          prepared,\n        ),';
assert.equal(original.toString().split(before).length, 2, 'Ambiguous custody mutation site');
let mutation;
try {
  writeFileSync(join(root, site), original.toString().replace(before, 'scratch_released: None,'));
  const source = snapshot(root);
  const run = spawnSync(process.execPath,
    ['proofs/relation-pipeline/capacity/parent-control/custody-run.mjs', 'js', '--expect-fixed', 'normal'],
    { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  const log = `${run.stdout ?? ''}${run.stderr ?? ''}`;
  assert.notEqual(run.status, 0, 'Premature scratch retirement was not detected');
  assert(log.includes('Scratch credited before child cleanup'), 'Mutation failed for a different reason');
  const logPath = `${custodyDirectory}/mutation-${source.digest}.log`;
  mkdirSync(join(root, custodyDirectory), { recursive: true });
  writeFileSync(join(root, logPath), log);
  mutation = { name: 'drop-installed-scratch-release-condition', target: 'js',
    site, beforeDigest: hash(original), source, exit: run.status, logPath, logDigest: hash(log) };
} finally {
  writeFileSync(join(root, site), original);
  assert.equal(snapshot(root).digest, current.digest, 'Custody mutation source restoration failed');
}
for (const target of targets) for (const mode of ['normal', 'pending']) {
  const began = performance.now();
  const run = spawnSync(process.execPath,
    ['proofs/relation-pipeline/capacity/parent-control/custody-run.mjs', target, '--expect-fixed', mode],
    { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  process.stderr.write(run.stderr ?? '');
  assert.equal(run.status, 0, `Actual ${target}/${mode} custody regression failed`);
  const summary = JSON.parse(run.stdout.trim().split('\n').at(-1));
  const bytes = readFileSync(join(root, summary.path)), receipt = JSON.parse(bytes);
  auditCustody(receipt, target, mode, current, path => readFileSync(join(root, path)));
  records.push({ target, mode, path: summary.path, digest: hash(bytes), durationMs: performance.now() - began });
  console.log(`${target}/${mode}: actual chain reservation held until cleanup, cumulative work preserved`);
}
assert.equal(snapshot(root).digest, current.digest);
mkdirSync(join(root, custodyDirectory), { recursive: true });
writeFileSync(join(root, custodyDirectory, `${requested}.json`), JSON.stringify({ source: current, mutation, records }, null, 2) + '\n');
