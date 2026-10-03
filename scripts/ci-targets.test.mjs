import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {parse} from 'yaml';
import {readChanges, selectTargets, validateSelection} from './ci-targets.mjs';
const all = ['js', 'wasm', 'native'];
const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const {jobs} = workflow;

test('main keeps full core and macOS, manual keeps explicit macOS opt-in', () => {
  assert.deepEqual(selectTargets(['README.md'], {event: 'push'}).targets, all);
  assert.equal(selectTargets(['README.md'], {event: 'push'}).macos, true);
  assert.deepEqual(selectTargets([], {event: 'workflow_dispatch'}).targets, all);
  assert.equal(selectTargets([], {event: 'workflow_dispatch'}).macos, false);
  assert.equal(selectTargets([], {event: 'workflow_dispatch', nativeMacos: true}).macos, true);
});
test('portable PR paths choose JS and explain deferred macOS coverage', () => {
  for (const path of ['README.md', 'docs/development.md', 'src/source_frontend/parse.mbt',
    'packages/sdk/index.mjs', 'adapters/workers/index.mjs', 'scripts/ci-evidence.test.mjs']) {
    const result = validateSelection(selectTargets([path]));
    assert.deepEqual(result.targets, ['js'], path); assert.equal(result.macos, false, path);
    assert.match(result.reason, /full targets and macOS run on main/u);
  }
});
test('platform, per-file target, runtime ownership, identities and build retain every target', () => {
  for (const path of ['src/platform_native/sqlite/moon.pkg', 'src/platform_native/executor_slot/moon.pkg',
    'src/cmd/native_client/main.mbt', 'src/something/backend_js.mbt', 'src/a/ffi.mbt',
    'src/managed_record_runtime/read.mbt', 'src/execution_relation/rows.mbt',
    'src/connectors/local/driver.mbt', 'src/canonical_json/read.mbt', 'src/sha256/hash.mbt',
    'adapters/host-node/completion-custody.test.mjs', 'scripts/owned-scratch.mjs',
    'src/a/moon.pkg', 'adapters/workers/build.mjs', 'packages/sdk/package.json',
    'adapters/store-local/publication-commit-owner.mjs', 'src/a/native.c', 'src/a/memory.mbt', 'src/value_contract/cid.mbt',
    '.github/workflows/ci.yml', 'toolchain.json', 'moon.mod', 'package-lock.json',
    'spec/contracts/pin.json', 'docs/spec/language.md', 'docs/reviews/runtime.json',
    'src/random/new.S', 'src/encode_core/value.mbt', 'src/decode_scalar/value.mbt', 'src/a/pkg.generated.mbti', 'packages/new-runtime/index.mjs', 'portability/corpus/value.json', 'proofs/relation-pipeline/run.mjs',
    'vendor/runtime/code.mbt']) {
    const result = selectTargets([path]);
    assert.deepEqual(result.targets, all, path); assert.equal(result.macos, true, path);
  }
});
test('unknown, unavailable, malformed and empty diff cannot omit target coverage', () => {
  for (const paths of [[], null, ['README.md', 'new-tool/config.json'], ['../src/a.mbt'],
    ['src/a\nb.mbt'], ['/tmp/a'], ['src//a'], ['src/a\0b']]) {
    assert.deepEqual(selectTargets(paths).targets, all, JSON.stringify(paths));
  }
  assert.equal(selectTargets(['README.md'], {failure: 'Git object unavailable'}).macos, true);
  assert.equal(selectTargets(['src/a/ordinary.mbt'], {targetSensitiveDiff: true}).macos, true);
  assert.throws(() => validateSelection({schema: 'actql-ci-targets/1', targets: ['wasm'], macos: false, reason: 'bad'}));
  assert.throws(() => validateSelection({schema: 'actql-ci-targets/1', targets: ['js'], macos: undefined, reason: 'bad'}));
});
test('diff uses exact merge checkout, NUL paths, no rename hiding and no 300-file limit', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40), calls = [];
  const paths = [...Array.from({length: 350}, (_, i) => `docs/file-${i}.md`), 'src/platform_native/old.mbt'];
  const result = readChanges({pull_request: {base: {sha: base}}}, args => {
    calls.push(args);
    if (args[0] === 'rev-parse') return head + '\n';
    return args.includes('--name-only') ? paths.join('\0') + '\0' : '+ordinary source\n';
  });
  assert.deepEqual(result.paths, paths);
  assert.deepEqual(calls[1], ['diff', '--no-renames', '--name-only', '-z', base, head, '--']);
  assert.deepEqual(selectTargets(result.paths).targets, all);
  assert.throws(() => readChanges({}), /Missing PR base/u);
  assert.throws(() => readChanges({pull_request: {base: {sha: base}}}, () => {throw new Error('missing base');}), /missing base/u);
  assert.throws(() => readChanges({pull_request: {base: {sha: base}}}, args => args[0] === 'rev-parse' ? head : 'README.md'), /Truncated/u);
});
test('ordinary filename cannot hide target-specific syntax changes', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40);
  for (const line of ['+extern "C"', '-supported_targets = "native"', '+unsafe fn f()', '+malloc(12)', '+#cfg(target="js")', '+#borrow(value)', '+#owned(value)']) {
    const result = readChanges({pull_request: {base: {sha: base}}}, args =>
      args[0] === 'rev-parse' ? head : args.includes('--name-only') ? 'src/a/plain.mbt\0' : line);
    assert.equal(result.targetSensitiveDiff, true, line);
  }
});
test('push+PR duplication is removed without workflow-level path filtering', () => {
  assert.deepEqual(workflow.on.push.branches, ['main']);
  assert(Object.hasOwn(workflow.on, 'pull_request'));
  assert.equal(workflow.on.pull_request, null);
  assert.equal(workflow.on.push.paths, undefined);
  assert.equal(workflow.on.push['paths-ignore'], undefined);
  assert.equal(workflow.concurrency['cancel-in-progress'], '${{ !inputs.performance_matrix }}');
});
test('core and macOS depend on one successful selector; no evidence jobs are narrowed', () => {
  assert.deepEqual(jobs.core.needs, ['select-targets']);
  assert.equal(jobs.core.strategy['fail-fast'], false);
  assert.equal(jobs.core.strategy.matrix.target, '${{ fromJSON(needs.select-targets.outputs.targets) }}');
  assert.deepEqual(jobs['native-macos'].needs, ['select-targets']);
  assert.match(jobs['native-macos'].if, /needs\.select-targets\.outputs\.macos == 'true'/u);
  const normal = '${{ !inputs.performance_matrix && !inputs.packed_query_evidence_probe }}';
  for (const name of ['session-evidence', 'pipeline-mutations', 'pipeline-capacity']) {
    assert.equal(jobs[name].if, normal); assert.equal(jobs[name].needs, undefined);
  }
  assert.deepEqual(jobs['pipeline-evidence'].needs, ['pipeline-mutations', 'pipeline-capacity']);
  const capacity = jobs['pipeline-capacity'].steps.map(step => step.run ?? '').join('\n');
  assert.match(capacity, /node proofs\/relation-pipeline\/capacity\/run\.mjs all/u);
  assert.match(capacity, /node proofs\/relation-pipeline\/run\.mjs all/u);
  const check = jobs.check;
  assert(check.needs.includes('select-targets'));
  assert.equal(check.steps[0].env.MACOS_SCHEDULED, '${{ needs.select-targets.outputs.macos }}');
  assert.match(check.if, /always\(\)/u);
});
test('required aggregate rejects failed or skipped selection and scheduled macOS omissions', () => {
  const script = jobs.check.steps[0].run;
  const results = Object.fromEntries(jobs.check.needs.map(name => [name, {result: 'success'}]));
  const run = (candidate, macos) => spawnSync('bash', ['-eo', 'pipefail', '-c', script], {
    encoding: 'utf8', env: {...process.env, RESULTS: JSON.stringify(candidate), MACOS_SCHEDULED: macos},
  }).status;
  assert.equal(run(results, 'true'), 0);
  for (const value of ['', 'invalid', 'undefined']) assert.equal(run(results, value), 1);
  const missing = {...results}; delete missing['select-targets'];
  assert.equal(run(missing, 'false'), 1);
  assert.equal(run({...results, 'native-macos': {result: 'skipped'}}, 'false'), 0);
  assert.equal(run({...results, 'native-macos': {result: 'skipped'}}, 'true'), 1);
  for (const result of ['failure', 'cancelled', 'skipped']) {
    assert.equal(run({...results, 'select-targets': {result}}, 'false'), 1);
    assert.equal(run({...results, core: {result}}, 'false'), 1);
  }
});

// The unchanged annotation can be far outside the edited hunk.
test('whole source versions retain target and ownership annotation context', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40);
  const result = readChanges({pull_request: {base: {sha: base}}}, args =>
    args[0] === 'rev-parse' ? head : args[0] === 'show' ? '#cfg(target="js")\nfn f() { 2 }' :
      args.includes('--name-only') ? 'src/a/plain.mbt\0' : '+ 2');
  assert.equal(result.targetSensitiveDiff, true);
  const added = readChanges({pull_request: {base: {sha: base}}}, args => {
    if (args[0] === 'show') throw new Error('new source has no base object');
    return args[0] === 'rev-parse' ? head : args.includes('--name-only') ? 'src/a/new.mbt\0' : '+ 2';
  });
  assert.equal(added.targetSensitiveDiff, true);
});

test('canonical identities in otherwise portable source files retain all targets', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40);
  for (const token of ['law_cid', '@sha256.hash(text)', 'canonical_value', 'preimage', 'hash_value']) {
    const result = readChanges({pull_request: {base: {sha: base}}}, args =>
      args[0] === 'rev-parse' ? head : args[0] === 'show' ? token :
        args.includes('--name-only') ? 'src/graph_contract/contract.mbt\0' : '+ordinary edit');
    assert.equal(result.targetSensitiveDiff, true, token);
    assert.deepEqual(selectTargets(result.paths, result).targets, all, token);
  }
});
