import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { minimalRepository, runDriver, successful } from './fixtures/execution-driver.mjs';

const targets = ['js', 'wasm', 'native'];
const fixture = 'src/query_integration/relation_pipeline_batch_wbtest.mbt';

test('real executor records fresh inputs and observations while unchanged builds stay fixed on three targets', t => {
  const root = minimalRepository(t);
  const result = runDriver(root, String.raw`
const executor = createExecutor();
for (const target of ['js', 'wasm', 'native']) {
  const first = executor.execute([makeCase()], registry, target, false, 'normal')[0];
  const before = executions.at(-1).receipt;
  const second = executor.execute([makeCase('changed', -2, 2)], registry, target, true, 'shrink')[0];
  const after = executions.at(-1).receipt;
  const repeated = executor.execute([makeCase('changed', -2, 2)], registry, target, true, 'repeated')[0];
  assert.deepEqual(first.rows, [[1, null, 1]]);
  assert.deepEqual(second.rows, [[-2, null, 1], [0, 2, -1]]);
  assert.deepEqual(repeated.rows, second.rows);
  assert.notEqual(first.id, second.id);
  assert.notEqual(second.id, repeated.id);
  assert.equal(first.observedCorrespondence, false);
  assert.equal(second.observedCorrespondence, true);
  assert.notEqual(first.observedSource, second.observedSource);
  assert.notEqual(first.observedSteps, second.observedSteps);
  assert.equal(before.buildIdentity, after.buildIdentity);
  assert.equal(before.fixtureDigest, after.fixtureDigest);
  assert.deepEqual(before.boundary, after.boundary);
  assert.deepEqual(before.artifacts, after.artifacts);
  assert.equal(readFileSync(join(root, before.fixturePath), 'utf8'), readFileSync(join(root, after.fixturePath), 'utf8'));
  assert.notEqual(before.inputDigest, after.inputDigest);
  assert.notEqual(after.inputDigest, executions.at(-1).receipt.inputDigest);
  assert.equal(digest(readFileSync(join(root, after.inputPath))), after.inputDigest);
  assert.deepEqual(JSON.parse(readFileSync(join(root, after.inputPath), 'utf8')).map(input => input.id), [second.id]);
  for (const [path, archive] of Object.entries(before.archives)) {
    assert.equal(digest(readFileSync(join(root, archive))), before.artifacts[path]);
  }
}
const paths = executions.map(entry => entry.path);
assert.equal(new Set(paths).size, 9);
assert.equal(new Set(executions.flatMap(entry => entry.receipt.cases.map(value => value.id))).size, 9);
for (const target of ['js', 'wasm', 'native']) {
  const actual = calls().filter(call => call.target === target);
  assert.equal(actual.length, 3, 'every observation must invoke the process');
  assert.deepEqual(actual.map(call => call.compiled), [true, false, false]);
}
executor.close();
report({ paths, calls: calls().length });
`);
  const report = successful(result);
  assert.equal(report.calls, 9);
  assert.equal(existsSync(join(root, fixture)), false);
  for (const path of report.paths) assert.equal(existsSync(join(root, path)), true);
});

test('exported default execute cleans its owned fixture on successful process exit', t => {
  const root = minimalRepository(t);
  successful(runDriver(root, String.raw`
assert.equal(execute([makeCase()], registry, 'js')[0].rows[0][0], 1);
report({ receipt: executions[0].path });
`));
  assert.equal(existsSync(join(root, fixture)), false);
});

for (const [settings, error] of [
  [{ mode: 'compile-failure' }, /Generated observation execution failed/],
  [{ mode: 'no-execution' }, /Executed binary\/source\/workspace identity mismatch/],
  [{ mode: 'no-observations' }, /Missing actual observations 0\/1/],
  [{ mode: 'no-test-summary' }, /Observation fixture did not pass exactly once/],
  [{ wrongId: true }, /Unbound execution event/],
  [{ unchecked: true }, /Execution identity mismatch/],
  [{ unregistered: true }, /Execution identity mismatch/],
]) {
  test(`execution failure cannot publish a receipt or mutation kill: ${JSON.stringify(settings)}`, t => {
    const root = minimalRepository(t);
    const result = runDriver(root, String.raw`
configure(${JSON.stringify(settings)});
const executor = createExecutor();
let killed = false;
process.on('exit', () => report({ receipts: executions.length, killed, calls: calls().length }));
executor.execute([makeCase()], registry, 'js');
killed = true;
executor.close();
`);
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, error);
    assert.deepEqual(result.reports.at(-1), { receipts: 0, killed: false, calls: 1 });
    assert.equal(existsSync(join(root, fixture)), false);
  });
}

for (const target of targets) {
  test(`source changes invalidate the compiled identity and reject a stale ${target} binary`, t => {
    successful(runDriver(minimalRepository(t), String.raw`
const executor = createExecutor();
executor.execute([makeCase()], registry, '${target}');
const first = executions[0].receipt;
writeFileSync(join(root, sourcePath), '// mutation\n');
configure({ stale: true });
assert.throws(() => executor.execute([makeCase()], registry, '${target}'), /Executed binary\/source\/workspace identity mismatch/);
assert.equal(executions.length, 1);
configure({});
const actual = executor.execute([makeCase()], registry, '${target}')[0];
const changed = executions.at(-1).receipt;
assert.equal(actual.compiledSource, '// mutation\n');
assert.notEqual(changed.sourceDigest, first.sourceDigest);
assert.notEqual(changed.buildIdentity, first.buildIdentity);
assert.notEqual(changed.fixtureDigest, first.fixtureDigest);
writeFileSync(join(root, sourcePath), original);
executor.close();
report({ receipts: executions.length });
`));
  });

  test(`a mutable ${target} binary cannot leak into the pristine workspace`, t => {
    successful(runDriver(minimalRepository(t), String.raw`
const workspaces = await mutationWorkspaces(root);
const mutable = createExecutor(workspaces.mutable), pristine = createExecutor(workspaces.pristine);
writeFileSync(join(workspaces.mutable.root, sourcePath), '// mutant\n');
mutable.execute([makeCase()], registry, '${target}');
const first = executions[0].receipt;
const binary = Object.keys(first.artifacts)[0];
configure({ binaryFrom: join(workspaces.mutable.root, binary) });
assert.throws(() => pristine.execute([makeCase()], registry, '${target}'), /Executed binary\/source\/workspace identity mismatch/);
assert.equal(executions.length, 1);
configure({});
assert.equal(pristine.execute([makeCase()], registry, '${target}')[0].compiledSource, original);
const healthy = executions.at(-1).receipt;
assert.notEqual(healthy.boundary.workspace, first.boundary.workspace);
assert.notEqual(healthy.boundary.root, first.boundary.root);
assert.notEqual(healthy.buildIdentity, first.buildIdentity);
writeFileSync(join(workspaces.mutable.root, sourcePath), original);
mutable.close(); pristine.close(); workspaces.passed();
`));
  });
}

test('same-source cross-workspace artifact replacement is rejected before spawning Moon', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const workspaces = await mutationWorkspaces(root);
const mutable = createExecutor(workspaces.mutable), pristine = createExecutor(workspaces.pristine);
mutable.execute([makeCase()], registry, 'js');
pristine.execute([makeCase()], registry, 'js');
const [left, right] = executions.map(entry => entry.receipt);
assert.equal(left.sourceDigest, right.sourceDigest);
assert.notEqual(left.buildIdentity, right.buildIdentity);
const path = Object.keys(left.artifacts)[0];
copyFileSync(join(workspaces.mutable.root, path), join(workspaces.pristine.root, path));
const before = calls().length;
assert.throws(() => pristine.execute([makeCase()], registry, 'js'), /Previously built execution artifacts changed/);
assert.equal(calls().length, before);
assert.equal(executions.length, 2);
mutable.close(); pristine.close(); workspaces.passed();
`));
});

test('source changes during execution fail before a success receipt is written', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const executor = createExecutor();
configure({ mutateSource: '// changed during execution\n' });
assert.throws(() => executor.execute([makeCase()], registry, 'js'), /Source changed during generated execution/);
assert.equal(executions.length, 0);
writeFileSync(join(root, sourcePath), original);
executor.close();
`));
});

test('a replaced compiler or runtime is rejected before execution', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const executor = createExecutor();
writeFileSync(join(root, '.fake-moon/bin/moonrun'), '// swapped runtime\n');
assert.throws(() => executor.execute([makeCase()], registry, 'js'), /Execution toolchain changed/);
assert.equal(calls().length, 0);
assert.equal(executions.length, 0);
executor.close();
`));
});

test('an unrelated temporary fixture is neither executed nor overwritten', t => {
  const root = minimalRepository(t);
  successful(runDriver(root, String.raw`
const executor = createExecutor();
writeFileSync(join(root, fixture), '// another owner\n');
assert.throws(() => executor.execute([makeCase()], registry, 'js'), /Another pipeline batch owns the temporary fixture/);
assert.equal(calls().length, 0);
executor.close();
`));
  assert.equal(readFileSync(join(root, fixture), 'utf8'), '// another owner\n');
});

for (const action of ['removed', 'changed']) {
  test(`a ${action} owned fixture fails process cleanup`, t => {
    const root = minimalRepository(t);
    const result = runDriver(root, String.raw`
execute([makeCase()], registry, 'js');
${action === 'removed' ? 'unlinkSync(join(root, fixture));' : "writeFileSync(join(root, fixture), '// different owner\\n');"}
`);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, new RegExp('Owned fixture was ' + action));
  });
}

test('fixture unlink failure makes an otherwise successful process fail', t => {
  const root = minimalRepository(t);
  const result = runDriver(root, String.raw`
execute([makeCase()], registry, 'js');
chmodSync(dirname(join(root, fixture)), 0o500);
`);
  if (!existsSync(join(root, fixture))) {
    t.skip('this user can unlink files in a read-only directory');
    return;
  }
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /EACCES|EPERM|cleanup failed/);
});

for (const target of ['wasm', 'native']) {
  test(`a JS binary cannot satisfy the first ${target} execution in the same workspace`, t => {
    successful(runDriver(minimalRepository(t), String.raw`
const executor = createExecutor();
executor.execute([makeCase()], registry, 'js');
const js = executions[0].receipt;
configure({ binaryFrom: join(root, Object.keys(js.artifacts)[0]) });
assert.throws(() => executor.execute([makeCase()], registry, '${target}'), /Executed binary\/source\/workspace identity mismatch/);
assert.equal(executions.length, 1);
configure({});
executor.execute([makeCase()], registry, '${target}');
const actual = executions.at(-1).receipt;
assert.notEqual(js.buildIdentity, actual.buildIdentity);
assert.equal(js.fixtureDigest, actual.fixtureDigest, 'switching targets must not rewrite the fixed fixture');
executor.close();
`));
  });
}

for (const path of ['lib/core/core.mi', 'lib/runtime/runtime.c', 'include/moonbit.h']) {
  test(`changed toolchain input is rejected: ${path}`, t => {
    successful(runDriver(minimalRepository(t), String.raw`
const executor = createExecutor();
writeFileSync(join(root, '.fake-moon', '${path}'), '// altered toolchain input\n');
assert.throws(() => executor.execute([makeCase()], registry, 'js'), /Execution toolchain changed/);
assert.equal(calls().length, 0);
assert.equal(executions.length, 0);
executor.close();
`));
  });
}

test('fixture source tampering during execution cannot publish a successful receipt', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const executor = createExecutor();
configure({ mutateFixture: true });
assert.throws(() => executor.execute([makeCase()], registry, 'js'), /Execution fixture changed/);
assert.equal(executions.length, 0);
const directory = join(root, '.artifacts/relation-pipeline');
const archived = readdirSync(directory).find(path => path.endsWith('.fixture.mbt'));
copyFileSync(join(directory, archived), join(root, fixture));
executor.close();
`));
});
