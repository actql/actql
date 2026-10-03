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
// Reintroduce each actual premature retirement condition separately. JS
// mutation detection is distinct from normal correspondence on every target.
const site = 'src/physical_strategy/task_execution.mbt';
const original = readFileSync(join(root, site));
const variants = [
  { name: 'drop-installed-scratch-release-condition', mode: 'normal',
    before: '(execution.hooks.unwrap().scratch_released)()',
    after: 'physical_equal(execution, execution)' },
  { name: 'settle-success-before-scratch-release', mode: 'success',
    before: 'if task_execution_scratch_released(execution) {', after: 'if true {' },
];
const mutations = [];
for (const variant of variants) {
  assert.equal(original.toString().split(variant.before).length, 2, 'Ambiguous custody mutation site');
  try {
    writeFileSync(join(root, site), original.toString().replace(variant.before, variant.after));
    const source = snapshot(root);
    const run = spawnSync(process.execPath,
      ['proofs/relation-pipeline/capacity/parent-control/custody-run.mjs', 'js', '--expect-fixed', variant.mode],
      { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
    const log = `${run.stdout ?? ''}${run.stderr ?? ''}`;
    assert.notEqual(run.status, 0, 'Premature scratch retirement was not detected');
    assert(log.includes('Scratch credited before child cleanup'), 'Mutation failed for a different reason');
    const logPath = `${custodyDirectory}/mutation-${source.digest}.log`;
    mkdirSync(join(root, custodyDirectory), { recursive: true });
    writeFileSync(join(root, logPath), log);
    mutations.push({ name: variant.name, mode: variant.mode, target: 'js',
      site, beforeDigest: hash(original), source, exit: run.status, logPath, logDigest: hash(log) });
  } finally {
    writeFileSync(join(root, site), original);
    assert.equal(snapshot(root).digest, current.digest, 'Custody mutation source restoration failed');
  }
}
for (const target of targets) for (const mode of ['normal', 'pending', 'success']) {
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
writeFileSync(join(root, custodyDirectory, `${requested}.json`), JSON.stringify({ source: current, mutations, records }, null, 2) + '\n');
