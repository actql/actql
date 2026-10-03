import test from 'node:test';
import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { minimalRepository, runDriver, successful } from './fixtures/execution-driver.mjs';

// Reuse the current bound-fixture/compiler transport. The executor, physical
// fixture ownership, receipt persistence and live child handoff remain real.
function workspace(t) {
  const root = minimalRepository(t);
  const finish = 'proofs/relation-pipeline/capacity/finish.mjs';
  mkdirSync(dirname(join(root, finish)), { recursive: true });
  copyFileSync(fileURLToPath(new URL('./capacity/finish.mjs', import.meta.url)), join(root, finish));
  mkdirSync(join(root, '.artifacts/relation-pipeline/capacity'), { recursive: true });
  return root;
}

const handoff = String.raw`
const { spawnSync } = await import('node:child_process');
const { pathToFileURL } = await import('node:url');
const { finishCapacityCampaign } = await import(pathToFileURL(join(root, 'proofs/relation-pipeline/capacity/finish.mjs')));
execute([makeCase()], registry, 'js', false, 'capacity-parent-lifecycle');
const receipt = executions.at(-1), fixtureBytes = readFileSync(join(root, fixture));
assert.deepEqual(JSON.parse(readFileSync(join(root, receipt.path))), receipt.receipt);
const childSource = [
  'import {execute,closeExecutor} from ' + JSON.stringify(pathToFileURL(join(root, 'proofs/relation-pipeline/execute.mjs')).href) + ';',
  'import {take} from ' + JSON.stringify(pathToFileURL(join(root, 'proofs/relation-pipeline/take.mjs')).href) + ';',
  'execute(' + JSON.stringify([makeCase('child')]) + ',[take],"js",false,"capacity-child-lifecycle"); closeExecutor();',
].join('\n');
const child = () => spawnSync(process.execPath, ['--input-type=module', '-e', childSource], {
  cwd: root, env: process.env, encoding: 'utf8', timeout: 10000,
});
const blocked = child(); assert.notEqual(blocked.status, 0);
assert.match(blocked.stderr, /Another pipeline batch owns the temporary fixture/);
assert(existsSync(join(root, fixture)));
finishCapacityCampaign({ kind: 'mock transport lifecycle regression' }, ['js', 'wasm', 'native']);
assert(!existsSync(join(root, fixture)), 'capacity finish left owned fixture live');
assert.throws(() => execute([makeCase()], registry, 'js'), /Execution workspace is closed/);
assert.deepEqual(readFileSync(join(root, receipt.receipt.fixturePath)), fixtureBytes);
assert.deepEqual(JSON.parse(readFileSync(join(root, '.artifacts/relation-pipeline/capacity/all.json'))).executions, executions);
const admitted = child(); assert.equal(admitted.status, 0, admitted.stderr);
assert(!existsSync(join(root, fixture)));
closeExecutor(); closeExecutor();
`;

test('capacity executor saves receipts and closes before a child probe in the same live checkout', t => {
  successful(runDriver(workspace(t), handoff));
});

test('identical fixture bytes do not confer ownership', t => {
  successful(runDriver(workspace(t), String.raw`
execute([makeCase()], registry, 'js');
const path = join(root, fixture), bytes = readFileSync(path);
closeExecutor();
writeFileSync(path, bytes);
const other = createExecutor();
assert.throws(() => other.execute([makeCase()], registry, 'js'), /Another pipeline batch owns the temporary fixture/);
other.close(); closeExecutor();
assert.deepEqual(readFileSync(path), bytes);
unlinkSync(path);
`));
});

test('changed owned fixture is preserved and rejected', t => {
  successful(runDriver(workspace(t), String.raw`
execute([makeCase()], registry, 'js');
const path = join(root, fixture), bytes = readFileSync(path);
writeFileSync(path, Buffer.concat([bytes, Buffer.from('\n')]));
assert.throws(closeExecutor, /Owned fixture was changed/);
assert(existsSync(path));
writeFileSync(path, bytes); closeExecutor();
`));
});

test('same-byte replacement is preserved and rejected before close', t => {
  successful(runDriver(workspace(t), String.raw`
execute([makeCase()], registry, 'js');
const path = join(root, fixture), saved = join(root, '.original-owned-fixture'), bytes = readFileSync(path);
renameSync(path, saved); writeFileSync(path, bytes);
assert.throws(closeExecutor, /Owned fixture was replaced/);
assert.deepEqual(readFileSync(path), bytes);
unlinkSync(path); renameSync(saved, path); closeExecutor();
`));
});

test('handoff regression detects omitting the campaign executor close', t => {
  const root = workspace(t), path = join(root, 'proofs/relation-pipeline/capacity/finish.mjs');
  const source = readFileSync(path, 'utf8');
  assert.equal(source.split('  closeExecutor();').length, 2);
  writeFileSync(path, source.replace('  closeExecutor();', '  // Deliberately omit owner release.'));
  const result = runDriver(root, handoff);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /capacity finish left owned fixture live/);
});
