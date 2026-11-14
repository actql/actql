import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { minimalRepository, runDriver, successful } from './fixtures/execution-driver.mjs';

const targets = ['js', 'wasm', 'native'];
const fixture = 'src/query_integration/relation_pipeline_batch_wbtest.mbt';

test('opt-in phase timing preserves JS calls, observations and canonical receipts', t => {
  const results = [];
  for (const enabled of [false, true]) {
    const result = runDriver(minimalRepository(t), String.raw`
const executor = createExecutor(undefined, {targets: ['js'], jobs: 1});
const values = [executor.execute([makeCase()], registry, 'js', false, 'normal')[0],
  executor.execute([makeCase('never-log-this-case-id', -2, 2)], registry, 'js', true, 'changed')[0]];
assert.equal(calls().length, 2);
assert.deepEqual(calls().map(call => call.compiled), [true, false]);
for (const entry of executions) {
  assert.deepEqual(readFileSync(join(root, entry.path)), Buffer.from(JSON.stringify(entry.receipt) + '\n'));
  assert.equal(digest(JSON.stringify(entry.receipt)), entry.digest);
}
executor.close();
const directory = join(root, '.artifacts/pipeline-execution-timing');
const records = existsSync(directory) ? readdirSync(directory).map(name => {
  const text = readFileSync(join(directory, name), 'utf8');
  assert(Buffer.byteLength(text) < 2048);
  assert(!text.includes(root) && !text.includes('never-log-this-case-id'));
  return JSON.parse(text);
}).sort((a, b) => a.sequence - b.sequence) : [];
if (${enabled}) {
  assert.equal(records.length, 2);
  assert.deepEqual(records.map(record => record.returned), [true, true]);
  assert.deepEqual(records.map(record => record.counts.priorArtifactChecks), [0, 1]);
  assert.deepEqual(records.map(record => record.counts.archivedFiles), [1, 0]);
  for (const record of records) {
    assert.equal(record.version, 'actql-pipeline-execution-phase-timing/0.1');
    assert.equal(record.target, 'js');
    assert.equal(record.lastPhase, 'receiptIO');
    assert.equal(record.counts.cases, 1);
    assert.equal(record.counts.observations, 1);
    assert(record.counts.toolFiles > 0 && record.counts.toolBytes > 0);
    assert(record.counts.inputBytes > 0 && record.counts.outputBytes > 0);
    assert.deepEqual(Object.keys(record.milliseconds), ['workspaceBefore', 'toolsBefore',
      'fixturePreparation', 'priorArtifacts', 'inputEvidenceIO', 'spawnBuildRun', 'outputIO',
      'toolsAfter', 'observations', 'workspaceAfter', 'finalArtifacts', 'archive', 'receiptIO']);
    for (const value of Object.values(record.milliseconds)) assert(Number.isFinite(value) && value >= 0);
    assert(record.totalMilliseconds >= Object.values(record.milliseconds).reduce((sum, n) => sum + n, 0));
  }
} else assert.equal(existsSync(directory), false);
// Owners and compiled identities stay independent between these runs. Compare
// only underlying commands/inputs and observations, never relabel receipts.
report({records, work: calls().map(call => ({target: call.target, args: call.args,
  inputs: call.inputs.map(({source, steps, correspondence}) => ({source, steps, correspondence}))})),
  values: values.map(({rows, checked, registered, observedCorrespondence}) =>
    ({rows, checked, registered, observedCorrespondence}))});
`, {ACTQL_PIPELINE_PHASE_TIMING: enabled ? '1' : ''});
    const data = successful(result);
    const summaries = result.stdout.split('\n').filter(line => line.startsWith('ACTQL_PIPELINE_PHASE_TIMING:'))
      .map(line => JSON.parse(line.slice('ACTQL_PIPELINE_PHASE_TIMING:'.length)));
    assert.deepEqual(summaries, data.records);
    results.push(data);
  }
  assert.deepEqual(results[0].work, results[1].work);
  assert.deepEqual(results[0].values, results[1].values);
});

test('opt-in phase timing preserves JS failures and a failed diagnostic write', t => {
  const result = runDriver(minimalRepository(t), String.raw`
const originalWorkspace = workspaceIdentity(root, 'normal');
let failWorkspace = false, workspaceCalls = 0;
const workspace = {...originalWorkspace, check() {
  assert.equal(this, workspace);
  workspaceCalls++;
  if (failWorkspace) throw undefined;
  return originalWorkspace.check();
}};
const executor = createExecutor(workspace, {targets: ['js'], jobs: 1});
configure({mode: 'compile-failure'});
assert.throws(() => executor.execute([makeCase()], registry, 'js'), /Generated observation execution failed/);
assert.equal(calls().length, 1);
assert.equal(executions.length, 0);
failWorkspace = true;
let caught = false;
try { executor.execute([makeCase()], registry, 'js'); }
catch (error) { caught = true; assert.equal(error, undefined); }
assert.equal(caught, true, 'the original thrown undefined must remain a failure');
assert.equal(calls().length, 1);
assert.equal(executions.length, 0);
failWorkspace = false;
configure({});
assert.deepEqual(executor.execute([makeCase()], registry, 'js')[0].rows, [[1, null, 1]]);
const directory = join(root, '.artifacts/pipeline-execution-timing');
const files = readdirSync(directory);
const records = files.map(name => JSON.parse(readFileSync(join(directory, name), 'utf8')))
  .sort((a, b) => a.sequence - b.sequence);
assert.deepEqual(records.map(record => record.returned), [false, false, true]);
assert.deepEqual(records.map(record => record.lastPhase), ['outputIO', 'workspaceBefore', 'receiptIO']);
assert.equal(records[1].counts.toolFiles, 0);
assert.equal(records[1].milliseconds.spawnBuildRun, 0);
const occupied = join(directory, files.find(name => name.endsWith('-0.json')).replace(/-0\.json$/, '-3.json'));
writeFileSync(occupied, 'original-diagnostic-file');
assert.deepEqual(executor.execute([makeCase()], registry, 'js')[0].rows, [[1, null, 1]]);
assert.equal(readFileSync(occupied, 'utf8'), 'original-diagnostic-file');
assert.equal(calls().length, 3);
assert.equal(executions.length, 2);
assert.equal(workspaceCalls, 6);
executor.close();
report({records, calls: calls().map(({target, args}) => ({target, args})), receipts: executions.length});
`, {ACTQL_PIPELINE_PHASE_TIMING: '1'});
  const data = successful(result);
  const summaries = result.stdout.split('\n').filter(line => line.startsWith('ACTQL_PIPELINE_PHASE_TIMING:'))
    .map(line => JSON.parse(line.slice('ACTQL_PIPELINE_PHASE_TIMING:'.length)));
  assert.equal(summaries.length, 4);
  assert.deepEqual(summaries.slice(0, 3), data.records);
  assert.equal(summaries[3].returned, true, 'a failed diagnostic write cannot replace the result');
  assert.equal(data.calls.length, 3);
  assert.equal(data.receipts, 2);
});

test('executor writes compact canonical receipts without changing observation or digest identity', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const executor = createExecutor(undefined, {targets: ['js'], jobs: 1});
executor.execute([makeCase()], registry, 'js');
const recorded = executions[0];
const bytes = readFileSync(join(root, recorded.path));
assert.deepEqual(bytes, Buffer.from(JSON.stringify(recorded.receipt) + '\n'));
assert.deepEqual(JSON.parse(bytes), recorded.receipt);
assert.equal(digest(JSON.stringify(JSON.parse(bytes))), recorded.digest);
assert.equal(recorded.receipt.cases.length, 1);
assert.equal(calls().length, 1);
executor.close();
`));
});

test('an internal toolchain directory alias retains actual file and resolved-path identity', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const release = join(root, '.fake-moon/lib/core/_build/js/release');
for (const name of ['build', 'same-bytes']) {
  mkdirSync(join(release, name), {recursive: true});
  writeFileSync(join(release, name, 'current.core'), 'original compiled input\n');
}
const alias = join(release, 'bundle');
symlinkSync('build', alias);
const executor = createExecutor(undefined, {targets: ['js'], jobs: 1});
executor.execute([makeCase()], registry, 'js');
assert.equal(calls().length, 1);
unlinkSync(alias);
symlinkSync('same-bytes', alias);
assert.throws(() => executor.execute([makeCase()], registry, 'js'), /Execution toolchain changed/);
assert.equal(calls().length, 1, 'a changed resolved input is refused before another process');
executor.close();
`));
});

test('an empty internal toolchain directory alias retains its canonical target', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const core = join(root, '.fake-moon/lib/core');
for (const name of ['empty', 'other-empty']) mkdirSync(join(core, name));
const alias = join(core, 'empty-alias');
symlinkSync('empty', alias);
const executor = createExecutor(undefined, {targets: ['js'], jobs: 1});
executor.execute([makeCase()], registry, 'js');
unlinkSync(alias);
symlinkSync('other-empty', alias);
assert.throws(() => executor.execute([makeCase()], registry, 'js'), /Execution toolchain changed/);
assert.equal(calls().length, 1);
executor.close();
`));
});

for (const [name, target, expected] of [
  ['external directory', '../../../vendor/native/include', /External or directory-linked Moon toolchain input/],
  ['ancestor cycle', '..', /Cyclic Moon toolchain directory input/],
]) {
  test(`a toolchain directory alias refuses ${name} before execution`, t => {
    successful(runDriver(minimalRepository(t), String.raw`
symlinkSync(${JSON.stringify(target)}, join(root, '.fake-moon/lib/core/refused'));
assert.throws(() => createExecutor(undefined, {targets: ['js'], jobs: 1}), ${expected});
assert.equal(calls().length, 0);
`));
  });
}

test('an explicit positive compiler job cap reaches the process and exact compiled boundary once', t => {
  successful(runDriver(minimalRepository(t), String.raw`
for (const jobs of [0, -1, 1.5, Infinity, NaN, '1', null])
  assert.throws(() => createExecutor(undefined, {targets: ['js'], jobs}), /Invalid execution jobs/);
assert.equal(calls().length, 0);
const executor = createExecutor(undefined, {targets: ['js'], jobs: 1});
executor.execute([makeCase()], registry, 'js');
const receipt = executions[0].receipt;
assert.deepEqual(receipt.command, ['moon', 'test', 'src/query_integration/relation_pipeline_batch_wbtest.mbt',
  '--target', 'js', '--jobs', '1', '--deny-warn']);
assert.deepEqual(receipt.boundary.command, receipt.command);
assert.deepEqual(calls()[0].args, receipt.command.slice(1));
assert.equal(receipt.buildIdentity, digest(JSON.stringify(receipt.boundary)));
assert.equal(calls()[0].buildIdentity, receipt.buildIdentity);
assert.equal(calls().length, 1);
assert.equal(executions.length, 1);
executor.close();
`));
});

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

test('an explicit JS owner needs no Native tools and refuses Native before execution', t => {
  successful(runDriver(minimalRepository(t), String.raw`
for (const name of ['cc', 'c++']) unlinkSync(join(root, '.fake-moon/bin', name));
const executor = createExecutor(undefined, {targets: ['js']});
assert.throws(() => executor.execute([makeCase()], registry, 'native'), /outside owner scope/);
assert.equal(calls().length, 0);
assert.equal(executions.length, 0);
assert.equal(executor.execute([makeCase()], registry, 'js')[0].rows[0][0], 1);
assert.equal(calls().length, 1);
assert.equal(executions.length, 1);
executor.close();
assert.throws(() => createExecutor(), /Missing execution tool cc/);
`, {PATH: ''}));
});

test('the default owner still binds Native tools and catches their replacement', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const executor = createExecutor();
writeFileSync(join(root, '.fake-moon/bin/cc'), '// swapped Native compiler\n');
assert.throws(() => executor.execute([makeCase()], registry, 'native'), /Execution toolchain changed/);
assert.equal(calls().length, 0);
assert.equal(executions.length, 0);
executor.close();
`));
});

test('target scope is copied and invalid/empty/duplicate target declarations are refused', t => {
  successful(runDriver(minimalRepository(t), String.raw`
for (const targets of [[], ['js', 'js'], ['unknown'], null])
  assert.throws(() => createExecutor(undefined, {targets}), /Invalid execution target scope/);
const targets = ['js'];
const executor = createExecutor(undefined, {targets});
targets.push('native');
assert.throws(() => executor.execute([makeCase()], registry, 'native'), /outside owner scope/);
assert.equal(calls().length, 0);
executor.close();
`));
});

test('closing the unstarted default owner remains terminal without discovering Native tools', t => {
  successful(runDriver(minimalRepository(t), String.raw`
unlinkSync(join(root, '.fake-moon/bin/cc'));
closeExecutor(); closeExecutor();
assert.throws(() => execute([makeCase()], registry, 'js'), /Execution workspace is closed/);
assert.equal(calls().length, 0);
assert.equal(executions.length, 0);
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
assert.throws(() => executor.execute([makeCase()], registry, 'js'), /Owned fixture was changed/);
assert.equal(executions.length, 0);
const directory = join(root, '.artifacts/relation-pipeline');
const archived = readdirSync(directory).find(path => path.endsWith('.fixture.mbt'));
copyFileSync(join(directory, archived), join(root, fixture));
executor.close();
`));
});

test('default close alias is terminal, idempotent and preserves archived evidence', t => {
  const root = minimalRepository(t);
  successful(runDriver(root, `
    execute([makeCase()], registry, 'js');
    const receipt = executions.at(-1);
    const fixtureBytes = readFileSync(join(root, fixture));
    closeExecutor(); closeExecutor();
    assert(!existsSync(join(root, fixture)));
    assert.deepEqual(JSON.parse(readFileSync(join(root, receipt.path))), receipt.receipt);
    assert.deepEqual(readFileSync(join(root, receipt.receipt.fixturePath)), fixtureBytes);
    assert.throws(() => execute([makeCase()], registry, 'js'), /Execution workspace is closed/);
    writeFileSync(join(root, fixture), fixtureBytes);
    closeExecutor();
    assert.deepEqual(readFileSync(join(root, fixture)), fixtureBytes, 'Closed executor never adopts a new foreign fixture');
  `));
});
for (const operation of ['execute', 'close']) test(`same-byte fixture replacement is preserved and rejected by ${operation}`, t => {
  const root = minimalRepository(t);
  successful(runDriver(root, `
    const executor = createExecutor();
    executor.execute([makeCase()], registry, 'js');
    const path = join(root, fixture), saved = join(root, '.saved-owned-fixture');
    const bytes = readFileSync(path);
    renameSync(path, saved); writeFileSync(path, bytes);
    const count = calls().length;
    assert.throws(() => ${operation === 'execute' ? "executor.execute([makeCase()], registry, 'js')" : 'executor.close()'}, /Owned fixture was replaced/);
    assert.equal(calls().length, count);
    assert.deepEqual(readFileSync(path), bytes);
    unlinkSync(path); renameSync(saved, path); executor.close();
  `));
});
test('same-byte replacement during execution cannot publish a receipt', t => {
  const root = minimalRepository(t);
  successful(runDriver(root, `
    const executor = createExecutor();
    configure({ replaceFixture: true });
    assert.throws(() => executor.execute([makeCase()], registry, 'js'), /Owned fixture was replaced/);
    assert.equal(executions.length, 0);
    const path = join(root, fixture);
    assert(existsSync(path)); unlinkSync(path);
    renameSync(join(root, '.saved-owned-fixture'), path); executor.close();
  `));
});
