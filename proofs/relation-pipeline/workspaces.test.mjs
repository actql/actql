import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { minimalRepository, runDriver, successful } from './fixtures/execution-driver.mjs';

// Subprocesses exercise the actual owned-scratch exit hook. Generic scratch
// lifecycle permutations remain in scripts/owned-scratch.test.mjs.
test('materialization copies exact source bytes and executable mode without dirty outputs or shared builds', t => {
  const root = minimalRepository(t);
  const result = runDriver(root, String.raw`
for (const path of ['_build/js/debug/test/query_integration/dirty.js', '.artifacts/old-result.json', 'node_modules/dirty/index.js']) {
  mkdirSync(dirname(join(root, path)), { recursive: true });
  writeFileSync(join(root, path), 'do not copy this');
}
const source = snapshot(root);
const workspaces = await mutationWorkspaces(root);
assert.notEqual(workspaces.pristine.root, workspaces.mutable.root);
assert.notEqual(workspaces.pristine.id, workspaces.mutable.id);
for (const workspace of [workspaces.pristine, workspaces.mutable]) {
  assert.deepEqual(workspace.check(), source);
  for (const path of Object.keys(source.sources)) {
    assert.deepEqual(readFileSync(join(workspace.root, path)), readFileSync(join(root, path)), path);
    assert.notEqual(statSync(join(workspace.root, path)).ino, statSync(join(root, path)).ino, 'sources must not be hard links');
  }
  for (const directory of ['_build', '.artifacts', 'node_modules']) assert.equal(existsSync(join(workspace.root, directory)), false);
  assert.equal(statSync(join(workspace.root, 'scripts/native-cxx-link-driver.sh')).mode & 0o777, 0o755);
  mkdirSync(join(workspace.root, '_build'));
  writeFileSync(join(workspace.root, '_build/probe'), workspace.role);
}
assert.notEqual(statSync(join(workspaces.pristine.root, '_build')).ino, statSync(join(workspaces.mutable.root, '_build')).ino);
assert.equal(readFileSync(join(workspaces.pristine.root, '_build/probe'), 'utf8'), 'pristine');
assert.equal(readFileSync(join(workspaces.mutable.root, '_build/probe'), 'utf8'), 'mutable');
const path = join(workspaces.mutable.root, sourcePath);
const bytes = readFileSync(path);
writeFileSync(path, '// mutation\n');
assert.equal(readFileSync(join(workspaces.pristine.root, sourcePath), 'utf8'), original);
assert.equal(readFileSync(join(root, sourcePath), 'utf8'), original);
writeFileSync(path, bytes);
report({ evidence: workspaces.evidence, source: workspaces.source });
workspaces.passed();
`);
  const report = successful(result);
  assert.equal(existsSync(dirname(report.evidence.pristine.root)), false);
  assert.match(result.stdout, /relation-pipeline workspaces: removed/);
  assert.equal(readFileSync(join(root, '_build/js/debug/test/query_integration/dirty.js'), 'utf8'), 'do not copy this');
  assert.equal(readFileSync(join(root, '.artifacts/old-result.json'), 'utf8'), 'do not copy this');
  assert.equal(readFileSync(join(root, 'node_modules/dirty/index.js'), 'utf8'), 'do not copy this');
});

for (const role of ['pristine', 'mutable']) {
  test(`a changed ${role} source cannot confirm success and its evidence is retained`, t => {
    const root = minimalRepository(t);
    const result = runDriver(root, String.raw`
const workspaces = await mutationWorkspaces(root);
report(workspaces.evidence);
writeFileSync(join(workspaces.${role}.root, sourcePath), '// failed restoration\n');
workspaces.passed();
`);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, role === 'pristine' ? /Pristine execution source changed/ : /Mutable source not restored exactly/);
    assert.match(result.stderr, /test failed; scratch kept:/);
    const evidence = result.reports[0];
    assert.equal(existsSync(evidence[role].root), true);
    assert.equal(readFileSync(join(evidence[role].root, 'src/query_integration/source.mbt'), 'utf8'), '// failed restoration\n');
    assert.equal(readFileSync(join(root, 'src/query_integration/source.mbt'), 'utf8'), '// pristine source\n');
  });
}

test('compiler failure retains both isolated workspaces and the actual failed execution log', t => {
  const root = minimalRepository(t);
  const result = runDriver(root, String.raw`
const workspaces = await mutationWorkspaces(root);
const executor = createExecutor(workspaces.mutable);
configure({ mode: 'compile-failure' });
report(workspaces.evidence);
try { executor.execute([makeCase()], registry, 'native'); }
finally { executor.close(); }
workspaces.passed();
`);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /simulated compiler failure/);
  assert.match(result.stderr, /test failed; scratch kept:/);
  for (const workspace of Object.values(result.reports[0])) assert.equal(existsSync(workspace.root), true);
  // Inputs, generated fixture and log survive beside the retained source trees.
  const directory = join(root, '.artifacts/relation-pipeline');
  const files = readdirSync(directory);
  const log = files.find(path => path.endsWith('.log'));
  assert.match(readFileSync(join(directory, log), 'utf8'), /simulated compiler failure/);
  assert(files.some(path => path.endsWith('.inputs.json')));
  assert(files.some(path => path.endsWith('.fixture.mbt')));
  assert.equal(files.filter(path => path.endsWith('.json') && !path.endsWith('.inputs.json')).length, 0);
  const calls = readFileSync(join(root, '.execution-calls.jsonl'), 'utf8').trim().split('\n').map(line => JSON.parse(line));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].target, 'native');
  assert.equal(calls[0].mode, 'compile-failure');
  assert.equal(existsSync(join(result.reports[0].mutable.root, 'src/query_integration/relation_pipeline_batch_wbtest.mbt')), false);
});

test('a replaced workspace is rejected even if its pathname is unchanged', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const workspaces = await mutationWorkspaces(root);
const workspace = workspaces.mutable;
const executor = createExecutor(workspace);
const saved = workspace.root + '-saved';
renameSync(workspace.root, saved);
mkdirSync(workspace.root);
assert.throws(() => executor.execute([makeCase()], registry, 'js'), /Execution workspace was replaced/);
assert.equal(calls().length, 0);
assert.equal(executions.length, 0);
rmSync(workspace.root, { recursive: true });
renameSync(saved, workspace.root);
executor.close();
workspaces.passed();
`));
});

test('shared, removed and replaced build roots are rejected without touching another workspace', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const workspaces = await mutationWorkspaces(root);
const workspace = workspaces.mutable;
const build = join(workspace.root, '_build');
const other = join(workspaces.pristine.root, '_build');
mkdirSync(build); mkdirSync(other);
writeFileSync(join(other, 'evidence'), 'pristine build');
workspace.check();
renameSync(build, build + '-saved');
assert.throws(() => workspace.check(), /Execution build workspace was removed/);
mkdirSync(build);
assert.throws(() => workspace.check(), /Execution build workspace was replaced/);
rmSync(build, { recursive: true });
symlinkSync(other, build, 'dir');
assert.throws(() => workspace.check(), /Linked source or build path is not isolated/);
unlinkSync(build);
renameSync(build + '-saved', build);
assert.equal(readFileSync(join(other, 'evidence'), 'utf8'), 'pristine build');
workspaces.passed();
`));
});

test('links inside an otherwise private build tree or source tree fail closed', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const workspaces = await mutationWorkspaces(root);
const workspace = workspaces.mutable;
mkdirSync(join(workspace.root, '_build'));
const target = join(workspaces.pristine.root, sourcePath);
for (const path of [join(workspace.root, '_build/linked.js'), join(workspace.root, 'src/query_integration/linked.mbt')]) {
  symlinkSync(target, path);
  assert.throws(() => workspace.check(), /Linked source or build path is not isolated/);
  unlinkSync(path);
}
workspaces.passed();
`));
});

test('ancestor links cannot join mutable native inputs to the pristine workspace', t => {
  const root = minimalRepository(t);
  const result = runDriver(root, `
    const spaces = await mutationWorkspaces(root);
    rmSync(join(spaces.mutable.root, 'scripts'), { recursive: true });
    symlinkSync(join(spaces.pristine.root, 'scripts'), join(spaces.mutable.root, 'scripts'), 'dir');
    assert.throws(() => spaces.mutable.check(), /Linked inventoried source input/);
    // The deliberately compromised workspace cannot be marked passed.
    report({ retained: spaces.mutable.root });
    process.exitCode = 1;
  `);
  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stderr, /scratch kept/);
});

test('each check reinspects shared ancestors and new inventoried source members', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const spaces = await mutationWorkspaces(root);
const workspace = spaces.mutable;
const before = workspace.check();
const added = join(workspace.root, 'src/query_integration/added.mbt');
writeFileSync(added, '// new inventoried member\n');
const changed = workspace.check();
assert.notEqual(changed.digest, before.digest);
assert(Object.hasOwn(changed.sources, 'src/query_integration/added.mbt'));
unlinkSync(added);
assert.deepEqual(workspace.check(), before);
// These roots are outside the recursively inspected source directories.
// A prior successful prefix check must not mask a later ancestor replacement.
for (const directory of ['scripts', 'docs/spec']) {
  const path = join(workspace.root, directory), saved = path + '-saved';
  renameSync(path, saved);
  symlinkSync(join(spaces.pristine.root, directory), path, 'dir');
  assert.throws(() => workspace.check(), /Linked inventoried source input/);
  unlinkSync(path);
  renameSync(saved, path);
  assert.deepEqual(workspace.check(), before);
}
assert.equal(calls().length, 0);
spaces.passed();
`));
});
