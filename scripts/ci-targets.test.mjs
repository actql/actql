import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, rmSync, writeFileSync, chmodSync, symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {parse} from 'yaml';
import {pullRequestDraft, readChanges, selectTargets, validateSelection, verifyGate, maintenanceFiles, gateJobs} from './ci-targets.mjs';
import {policyPaths} from './ci-main-base.mjs';
import {occurrences} from './check-owned-contract-versions.mjs';
const all = ['js', 'wasm', 'native'];
const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const {jobs} = workflow;

test('preflight checks Native counter assignments before the build toolchain', () => {
  const steps = jobs.preflight.steps;
  const index = steps.findIndex(row =>
    row.name === 'Check Native diagnostic counter assignments before fan-out');
  assert.ok(index >= 0);
  assert.equal(steps[index].run, 'python3 scripts/test_native_timings.py CommandCounterMap');
  assert.ok(index < steps.findIndex(row => row.name === 'Install pinned MoonBit'));
  assert.ok(jobs.native.needs.includes('preflight'));
});

test('normal lint executes behavioral operation performance assessment tests', () => {
  const step = jobs.lint.steps.find(row =>
    row.name === 'Test ordinary operation performance assessment');
  assert.ok(step);
  assert.equal(step.run, 'node --test scripts/operation-performance.test.mjs scripts/benchmark-node-operations.test.mjs scripts/operation-performance-policy.test.mjs scripts/operation-performance-native-control.test.mjs scripts/benchmark-node-process-operations.test.mjs scripts/benchmark-node-sqlite.test.mjs scripts/benchmark-node-boundaries.test.mjs scripts/node-operation-fs-trace.test.mjs scripts/operation-performance-priority-transition.test.mjs scripts/operation-performance-transition-ci.test.mjs');
  assert.equal(step.if, "${{ !startsWith(needs.select-targets.outputs.profile, 'draft') }}");
  // These tests validate raw samples, frame counts, faults and incomplete
  // evidence. Running them is not an ordinary-package performance result.
  assert.ok(jobs.host.steps.some(row => row.run === 'npm run check:checkpoint-runtime'));
  const observed = jobs.host.steps.find(row =>
    row.name === 'Test operation authorization and unchanged Run observations');
  assert.equal(observed.run, 'node --test adapters/host-node/authorization-account-current.test.mjs adapters/host-node/local-account-current.test.mjs adapters/host-node/client-run-state-revision.test.mjs adapters/host-node/client-run-observation-reuse.test.mjs adapters/host-common/run-state-clock-order.test.mjs adapters/host-node/client-run-stop-observation.test.mjs adapters/host-node/embedded-managed-compute-projection.test.mjs adapters/host-node/mock-effect-host-original.test.mjs adapters/host-node/embedded-managed-compute-lifecycle.test.mjs adapters/host-node/installed-managed-source.test.mjs adapters/host-node/embedded-source-environment-scope.test.mjs adapters/host-node/client-original-submitted-intent.test.mjs adapters/host-common/observation.test.mjs adapters/host-node/in-process-result-observation.test.mjs');
  assert.ok(jobs.host.steps.indexOf(observed) > jobs.host.steps.findIndex(row =>
    row.run === 'npm run check:retained-boundary'));
});

test('normal lint executes ordinary process collector protocol tests', () => {
  const step = jobs.lint.steps.find(row =>
    row.name === 'Test ordinary process collector protocols');
  assert.ok(step);
  assert.equal(step.run, 'python3 -I -B scripts/benchmark-ordinary-processes.test.py');
  assert.equal(step.if, "${{ !startsWith(needs.select-targets.outputs.profile, 'draft') }}");
  assert.equal(step['continue-on-error'], undefined);
  // Process fixtures exercise the collector and package fence, not product speed.
});

test('normal Host CI executes bounded Journal preparation and cursor regressions', () => {
  const step = jobs.host.steps.find(row =>
    row.name === 'Test bounded Journal preparation and execution');
  assert.ok(step);
  assert.equal(step.run, 'node --test adapters/host-node/client-request-journal-sql-bounds.test.mjs adapters/host-node/client-request-journal-execution-bounds.test.mjs adapters/host-node/client-request-journal-wal-bounds.test.mjs adapters/host-node/client-request-journal-fresh-schema.test.mjs');
  assert.ok(jobs.host.steps.indexOf(step) > jobs.host.steps.findIndex(row =>
    row.run === 'npm run check:retained-boundary'));
});

test('normal Host CI checks real connector initialization after its ordinary runtime build', () => {
  const steps = jobs.host.steps;
  const build = steps.findIndex(row => row.name === 'Build runtime packages without prebuilt bundles');
  const index = steps.findIndex(row => row.name === 'Test actual bound connector initialization and cleanup');
  assert.ok(build >= 0 && index > build);
  assert.equal(steps[index].run, 'node --test adapters/host-node/installed-bound-construction.actual.test.mjs adapters/host-node/installed-bound-construction-failures.actual.test.mjs adapters/host-node/installed-source-construction-geometry.test.mjs');
  assert.equal(steps[index].if, undefined);
  assert.equal(steps[index]['continue-on-error'], undefined);
  // These cases use actual Core/Resource/registration and temporary SQLite,
  // not live provider credentials or another runtime build/cleanup substitute.
});

test('manual integration keeps full core and explicit macOS opt-in', () => {
  assert.deepEqual(selectTargets(['README.md'], {event: 'push'}).targets, all);
  assert.equal(selectTargets(['README.md'], {event: 'push'}).macos, true);
  assert.deepEqual(selectTargets([], {event: 'workflow_dispatch'}).targets, all);
  assert.equal(selectTargets([], {event: 'workflow_dispatch'}).macos, false);
  assert.equal(selectTargets([], {event: 'workflow_dispatch', nativeMacos: true}).macos, true);
});
test('portable PR paths choose JS and explain deferred macOS coverage', () => {
  for (const path of ['README.md', 'src/source_span/span.mbt', 'scripts/worktree-inventory.mjs']) {
    const result = validateSelection(selectTargets([path]));
    assert.deepEqual(result.targets, ['js'], path); assert.equal(result.macos, false, path);
    assert.match(result.reason, /full targets and optional macOS require a manual integration checkpoint/u);
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
  assert.throws(() => validateSelection({schema: 'actql-ci-targets/0.1', targets: ['wasm'], macos: false, reason: 'bad'}));
  assert.throws(() => validateSelection({schema: 'actql-ci-targets/0.1', targets: ['js'], macos: undefined, reason: 'bad'}));
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
test('only main pushes and explicit dispatch trigger CI; PRs stay local', () => {
  assert.deepEqual(Object.keys(workflow.on).sort(), ['push', 'workflow_dispatch']);
  assert.deepEqual(workflow.on.push.branches, ['main']);
  assert.equal(workflow.on.pull_request, undefined);
  assert.equal(workflow.on.schedule, undefined);
  assert.equal(workflow.on.workflow_run, undefined);
  assert.equal(workflow.on.merge_group, undefined);
  assert.equal(workflow.concurrency['cancel-in-progress'], "${{ !inputs.performance_matrix && github.ref != 'refs/heads/main' }}");
});
test('manual normal dispatch retains all full-family obligations, separate from probes', () => {
  const inputs = workflow.on.workflow_dispatch.inputs;
  assert.equal(inputs.performance_matrix.default, false);
  assert.equal(inputs.packed_query_evidence_probe.default, false);
  const selection = validateSelection(selectTargets([], {event: 'workflow_dispatch'}));
  assert.equal(selection.profile, 'full');
  assert.deepEqual(selection.targets, all);
  assert.equal(selection.mainBaseline, null);
  const results = Object.fromEntries(gateJobs.map(name => [name, {result: 'success'}]));
  results['focused-tests'] = {result: 'skipped'};
  results['native-macos'] = {result: 'skipped'};
  verifyGate({sourceRevision: 'a'.repeat(40), selection}, results, {event: 'workflow_dispatch', sourceRevision: 'a'.repeat(40)});
  for (const status of ['failure', 'skipped', undefined]) {
    assert.throws(() => verifyGate({sourceRevision: 'a'.repeat(40), selection},
      {...results, core: {result: status}}, {event: 'workflow_dispatch', sourceRevision: 'a'.repeat(40)}));
  }
});
test('active main finishes while pending work coalesces; branches and performance are separate', () => {
  assert.equal(workflow.concurrency.group, "${{ github.workflow }}-${{ github.ref }}-${{ inputs.packed_query_evidence_probe && 'evidence-probe' || inputs.performance_matrix && 'performance' || 'normal' }}");
  assert.equal(workflow.concurrency.queue, undefined);
  const expression = workflow.concurrency['cancel-in-progress'].slice(3, -2);
  for (const ref of ['refs/heads/main', 'refs/heads/feature']) {
    for (const performance of [false, undefined, true]) {
      assert.equal(runInNewContext(expression, {github: {ref}, inputs: {performance_matrix: performance}},
        {timeout: 100}), ref !== 'refs/heads/main' && !performance);
    }
  }
});
test('whole-family scheduling retains the core matrix and complete selected proof campaigns', () => {
  assert.deepEqual(jobs.core.needs, ['select-targets', 'preflight']);
  assert.equal(jobs.core.strategy['fail-fast'], false);
  assert.equal(jobs.core.strategy.matrix.target, '${{ fromJSON(needs.select-targets.outputs.targets) }}');
  assert.deepEqual(jobs['native-macos'].needs, ['select-targets', 'preflight']);
  assert.match(jobs['native-macos'].if, /needs\.select-targets\.outputs\.macos == 'true'/u);
  for (const name of ['session-evidence', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants', 'pipeline-validation']) {
    assert.match(jobs[name].if, /needs\.select-targets\.outputs\.profile == 'full'/u);
    assert.deepEqual(jobs[name].needs, ['select-targets', 'preflight']);
  }
  assert.deepEqual(jobs['pipeline-evidence'].needs, ['pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants', 'pipeline-validation']);
  const capacity = jobs['pipeline-capacity'].steps.map(step => step.run ?? '').join('\n');
  assert.match(capacity, /node proofs\/relation-pipeline\/capacity\/run\.mjs all/u);
  assert.match(capacity, /node proofs\/relation-pipeline\/run\.mjs all/u);
  const check = jobs.check;
  assert(check.needs.includes('select-targets'));
  assert.equal(check.steps.find(step => step.run).env.CI_PLAN, '${{ needs.select-targets.outputs.plan }}');
  assert.match(check.if, /always\(\)/u);
});
const head = 'b'.repeat(40);
const plan = selection => ({sourceRevision: head, selection});
const context = {event: 'pull_request', sourceRevision: head};
const results = selection => Object.fromEntries(gateJobs.map(name => [name, {result:
  ['select-targets', 'preflight', 'lint', 'spec'].includes(name) || selection.profile === 'full' && name !== 'focused-tests' &&
    (name !== 'native-macos' || selection.macos) ? 'success' : 'skipped'}]));
const changes = paths => paths.map(path => ({path, before: {mode: '100644', object: 'c'.repeat(40)},
  after: {mode: '100644', object: 'd'.repeat(40)}}));
const maintenanceSelection = paths => selectTargets(paths, {maintenanceChanges: changes(paths)});

test('required aggregate rejects failed, cancelled, skipped and missing selected jobs', () => {
  const selection = selectTargets(['src/unregistered/engine.mbt']);
  assert.equal(verifyGate(plan(selection), results(selection), context).length, gateJobs.length);
  for (const name of gateJobs.filter(name => name !== 'focused-tests')) {
    for (const result of ['failure', 'cancelled', 'skipped', 'in_progress', undefined]) {
      const candidate = results(selection); candidate[name] = {result};
      assert.throws(() => verifyGate(plan(selection), candidate, context), undefined, `${name}: ${result}`);
    }
    const candidate = results(selection); delete candidate[name];
    assert.throws(() => verifyGate(plan(selection), candidate, context), /dependency inventory/u);
  }
  assert.throws(() => verifyGate(plan(selection), {...results(selection), unknown: {result: 'success'}}, context));
  const portable = selectTargets(['README.md']);
  assert.doesNotThrow(() => verifyGate(plan(portable), results(portable), context));
  assert.throws(() => verifyGate(plan(selection), results(portable), context));
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

test('P1: unregistered runtime files and configuration cannot qualify by directory', () => {
  for (const path of [
    'adapters/new-engine/index.mjs',
    'adapters/workers/wrangler.toml',
    'packages/sdk/tsconfig.json',
    'src/source_frontend/lower.mbt',
  ]) {
    const selected = selectTargets([path], {targetSensitiveDiff: false});
    assert.deepEqual(selected.targets, all, path);
    assert.equal(selected.macos, true, path);
  }
});
test('an existing unregistered MoonBit file stays full even with portable contents', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40);
  const result = readChanges({pull_request: {base: {sha: base}}}, args =>
    args[0] === 'rev-parse' ? head : args[0] === 'show' ? 'fn add(a: Int, b: Int) -> Int { a + b }' :
      args.includes('--name-only') ? 'src/unregistered/arithmetic.mbt\0' : '+ a + b');
  assert.equal(result.targetSensitiveDiff, false);
  assert.deepEqual(selectTargets(result.paths, result).targets, all);
  assert.equal(selectTargets(result.paths, result).macos, true);
});
test('only the exact registered portable file qualifies, not siblings or configuration', () => {
  assert.deepEqual(selectTargets(['src/source_span/span.mbt']).targets, ['js']);
  for (const path of ['src/source_span/other.mbt', 'src/source_span/moon.pkg',
    'scripts/worktree-inventory.config.json', 'docs/new-engine.md',
    'packages/sdk/index.mjs', 'adapters/workers/runtime.mjs']) {
    assert.deepEqual(selectTargets([path]).targets, all, path);
  }
  assert.deepEqual(selectTargets(['src/source_span/span.mbt'], {targetSensitiveDiff: true}).targets, all);
});

test('registered files cannot hide type/mode changes or head-only target annotations', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40), path = 'src/source_span/span.mbt';
  const calls = [];
  const result = readChanges({pull_request: {base: {sha: base}}}, args => {
    if (args[0] === 'rev-parse') return head;
    if (args[0] === 'show') {
      calls.push(args[1]);
      return args[1].startsWith(base) ? 'pub struct Span { line : Int }' : '#cfg(target="js")\npub struct Span { line : Int }';
    }
    return args.includes('--name-only') ? path + '\0' : '+ line : Int';
  });
  assert.equal(result.targetSensitiveDiff, true);
  assert.deepEqual(calls, [`${base}:${path}`, `${head}:${path}`]);
  for (const header of ['old mode 100644\nnew mode 120000', 'new file mode 100644', 'deleted file mode 100644']) {
    const changed = readChanges({pull_request: {base: {sha: base}}}, args =>
      args[0] === 'rev-parse' ? head : args[0] === 'show' ? 'pub struct Span { line : Int }' :
        args.includes('--name-only') ? path + '\0' : header + '\n+ other-path');
    assert.equal(changed.targetSensitiveDiff, true, header);
    assert.deepEqual(selectTargets(changed.paths, changed).targets, all);
  }
});

test('CI selection follows the owned contract baseline without a legacy exception', () => {
  for (const path of ['README.md', 'src/unregistered/engine.mbt']) {
    assert.equal(validateSelection(selectTargets([path])).schema, 'actql-ci-targets/0.1');
  }
  const previous = ['actql-ci-targets', '1'].join('/');
  assert.throws(() => validateSelection({...selectTargets(['README.md']), schema: previous}));
  for (const file of ['ci-targets.mjs', 'ci-targets.test.mjs']) {
    assert.deepEqual(occurrences(readFileSync(new URL(file, import.meta.url), 'utf8'), `scripts/${file}`), []);
  }
});


test('maintenance inventory is exact and every existing reviewed modification qualifies', () => {
  assert.equal(maintenanceFiles.length, 15);
  assert.equal(new Set(maintenanceFiles).size, 15);
  for (const path of maintenanceFiles) {
    const selection = validateSelection(maintenanceSelection([path]));
    assert.equal(selection.profile, 'maintenance', path);
    const lines = verifyGate(plan(selection), results(selection), context);
    assert(lines.some(line => line.startsWith('NOT APPLICABLE pipeline-evidence')));
    assert(lines.some(line => line.startsWith('PASS lint')));
    assert(lines.some(line => line.startsWith('PASS spec')));
  }
  assert.equal(maintenanceSelection(maintenanceFiles).profile, 'maintenance');
  for (const path of ['README.md', 'src/source_span/span.mbt', 'packages/sdk/README.md',
    'docs/spec/language.md', 'docs/design/something.md', 'docs/reviews/report.json',
    'scripts/local-checks.mjs', 'proofs/relation-pipeline/ci-artifacts.mjs',
    'scripts/ci-review.config.json', 'scripts/new-reporter.mjs',
    'scripts/ci-artifact-reader.mjs', 'scripts/ci-artifact-reader.test.mjs']) {
    assert.equal(maintenanceSelection([path]).profile, 'full', path);
    assert.equal(maintenanceSelection([maintenanceFiles[0], path]).profile, 'full', path);
  }
  assert.equal(selectTargets(maintenanceFiles).profile, 'full', 'paths alone are not modification evidence');
});

test('raw Git classification rejects additions deletions renames modes and malformed inventories', () => {
  const path = 'scripts/worktree-inventory.mjs', base = 'a'.repeat(40);
  const raw = (status = 'M', before = '100644', after = '100644') =>
    `:${before} ${after} ${'c'.repeat(40)} ${'d'.repeat(40)} ${status}\0${path}\0`;
  const inspect = output => readChanges({pull_request: {base: {sha: base}}}, args =>
    args[0] === 'rev-parse' ? head : args.includes('--name-only') ? path + '\0' :
      args.includes('--raw') ? output : '+report hash and target text');
  const modified = inspect(raw());
  assert.equal(modified.targetSensitiveDiff, true, 'report terminology still triggers existing target scanner');
  assert.equal(selectTargets(modified.paths, modified).profile, 'maintenance');
  for (const output of [raw('A', '000000'), raw('D', '100644', '000000'), raw('R100'),
    raw('T', '100644', '120000'), raw('M', '100644', '100755'), raw('M', '120000', '120000')]) {
    const changed = inspect(output);
    assert.equal(selectTargets(changed.paths, changed).profile, 'full');
    assert.deepEqual(selectTargets(changed.paths, changed).targets, all);
  }
  for (const output of ['', raw().slice(0, -1), raw() + raw(), raw().replace(path, 'scripts/other.mjs'), 'malformed\0']) {
    assert.throws(() => inspect(output));
  }
});

test('maintenance plans reject inconsistent fields identities and input membership', () => {
  const selection = maintenanceSelection(['docs/development.md']);
  for (const mutate of [
    value => { value.profile = 'unknown'; }, value => { value.event = 'push'; },
    value => { value.macos = true; }, value => { value.targets = all; },
    value => { value.paths.push('unknown'); }, value => { value.paths.push(value.paths[0]); },
    value => { value.maintenanceChanges = null; }, value => { value.maintenanceChanges[0].path = 'unknown'; },
    value => { value.maintenanceChanges[0].before.mode = '120000'; },
    value => { value.maintenanceChanges[0].after.object = value.maintenanceChanges[0].before.object; },
    value => { value.maintenanceChanges[0].before.object = 'bad'; },
    value => { value.maintenanceChanges[0].before.object = '0'.repeat(40); },
    value => { value.maintenanceChanges[0].status = 'M'; }, value => { value.extra = true; },
    value => { delete value.profile; }, value => { value.reason = ''; },
  ]) {
    const invalid = structuredClone(selection); mutate(invalid);
    assert.throws(() => validateSelection(invalid));
  }
  assert.throws(() => verifyGate({...plan(selection), sourceRevision: 'a'.repeat(40)}, results(selection), context));
  assert.throws(() => verifyGate(plan(selection), results(selection), {...context, event: 'push'}));
  assert.throws(() => verifyGate({...plan(selection), extra: true}, results(selection), context));
  for (const event of ['push', 'workflow_dispatch', 'merge_group']) {
    const value = selectTargets(maintenanceFiles, {event, maintenanceChanges: changes(maintenanceFiles)});
    assert.equal(value.profile, 'full'); assert.deepEqual(value.targets, all);
    assert.throws(() => validateSelection({...value, targets: ['js']}));
    if (event !== 'workflow_dispatch') assert.throws(() => validateSelection({...value, macos: false}));
  }
});

test('maintenance N/A is explicit and cannot hide execution or selected check failures', () => {
  const selection = maintenanceSelection(['docs/development.md']);
  for (const name of gateJobs) {
    const candidate = results(selection);
    candidate[name] = {result: candidate[name].result === 'success' ? 'skipped' : 'success'};
    assert.throws(() => verifyGate(plan(selection), candidate, context), undefined, name);
    for (const result of ['failure', 'cancelled', undefined]) {
      candidate[name] = {result};
      assert.throws(() => verifyGate(plan(selection), candidate, context), undefined, name);
    }
  }
});

// Exercise the real GitHub job expressions, including always() behavior.
const scheduled = (name, needs, inputs = {}) => {
  const expression = jobs[name].if.slice(3, -3).replace(/needs\.([a-z][a-z0-9-]*)/gu, (_, name) => `needs[${JSON.stringify(name)}]`);
  return Function('needs', 'inputs', 'always', 'vars', 'github', 'toJSON', `return (${expression});`)(needs, inputs, () => true,
    {ACTQL_MAIN_CI_ENABLED: 'true'}, {event: {repository: {visibility: 'public', private: false}}}, JSON.stringify);
};
test('aggregate workflow expressions run on mixed failures and skip only wholly unselected families', () => {
  for (const [name, groups] of [['client', ['client-packages', 'client-distribution', 'client-packed', 'client-salesforce']],
    ['pipeline-evidence', ['pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants', 'pipeline-validation']]]) {
    assert.deepEqual(jobs[name].needs, groups);
    assert.match(jobs[name].if, /always\(\)/u);
    const skipped = Object.fromEntries(groups.map(group => [group, {result: 'skipped'}]));
    assert.equal(scheduled(name, skipped), false);
    for (const group of groups) for (const result of ['success', 'failure', 'cancelled', undefined]) {
      assert.equal(scheduled(name, {...skipped, [group]: {result}}), true, `${name}/${group}/${result}`);
    }
    assert.equal(scheduled(name, Object.fromEntries(groups.map(group => [group, {result: 'success'}]))), true);
    assert.equal(scheduled(name, skipped, {performance_matrix: true}), false);
  }
  const evidence = jobs['pipeline-evidence'];
  assert.equal(evidence.steps.find(step => step.name === 'Require all four producers and mandatory validation before transfer').env.PIPELINE_NEEDS,
    '${{ toJSON(needs) }}');
  assert.equal(evidence.steps.find(step => step.run === 'node proofs/relation-pipeline/ci-parts.mjs join').env.PIPELINE_NEEDS,
    '${{ toJSON(needs) }}');
});

test('every heavy primitive is selected as one complete job and lint/spec always retain their tests', () => {
  const heavy = ['core', 'host', 'client-packages', 'client-distribution', 'client-packed', 'client-salesforce',
    'native', 'session-evidence', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants', 'pipeline-validation', 'native-macos',
    'native-separated-network', 'workers', 'connector-addition', 'duckdb-node'];
  for (const name of heavy) {
    assert(jobs[name].needs.includes('select-targets'));
    assert.equal(scheduled(name, {'select-targets': {outputs: {profile: 'maintenance', macos: 'false'}}}), false);
    assert.equal(scheduled(name, {'select-targets': {outputs: {profile: 'full', macos: 'true'}}}), true);
    assert.equal(scheduled(name, {'select-targets': {outputs: {profile: '', macos: 'true'}}}), false);
  }
  assert.deepEqual(jobs.check.needs, gateJobs);
  for (const name of ['lint', 'spec']) assert.deepEqual(jobs[name].needs, ['select-targets', 'preflight']);
  const lint = jobs.lint.steps.map(step => step.run ?? '');
  assert(lint.includes('node --test scripts/ci-evidence.test.mjs'));
  assert(lint.includes('node --test scripts/worktree-inventory.test.mjs'));
  const reporter = readFileSync(new URL('./ci-evidence.test.mjs', import.meta.url), 'utf8');
  for (const file of ['ci-artifact-reader.test.mjs', 'ci-artifacts.test.mjs', 'verification-actions.test.mjs']) {
    assert(reporter.includes(`import './${file}';`), `Missing retained reporter suite ${file}`);
  }
  assert(jobs.spec.steps.some(step => step.run?.includes('npm run check:spec')));
});

test('actual final gate command fails closed for missing or corrupted plans', t => {
  const dir = mkdtempSync(join(tmpdir(), 'actql-pr-event-'));
  t.after(() => rmSync(dir, {recursive: true, force: true}));
  const eventPath = join(dir, 'event.json');
  writeFileSync(eventPath, JSON.stringify({action: 'synchronize', pull_request: {draft: false}}));
  const selection = maintenanceSelection(['docs/development.md']);
  const script = jobs.check.steps.find(step => step.run).run;
  const run = value => spawnSync('bash', ['-eo', 'pipefail', '-c', script], {cwd: new URL('../', import.meta.url),
    encoding: 'utf8', env: {...process.env, CI_PLAN: value, RESULTS: JSON.stringify(results(selection)),
      GITHUB_SHA: head, GITHUB_EVENT_NAME: 'pull_request', GITHUB_EVENT_PATH: eventPath, GITHUB_STEP_SUMMARY: ''}});
  const good = run(JSON.stringify(plan(selection)));
  assert.equal(good.status, 0, good.stderr);
  assert.match(good.stdout, /NOT APPLICABLE pipeline-evidence/u);
  writeFileSync(eventPath, JSON.stringify({action: 'converted_to_draft', pull_request: {draft: true}}));
  const draftAttempt = run(JSON.stringify(plan(selection)));
  assert.notEqual(draftAttempt.status, 0);
  assert.match(draftAttempt.stderr, /awaiting ready_for_review/u);
  writeFileSync(eventPath, JSON.stringify({action: 'ready_for_review', pull_request: {draft: false}}));
  assert.equal(run(JSON.stringify(plan(selection))).status, 0);
  for (const value of ['', 'undefined', '{}', JSON.stringify({...plan(selection), sourceRevision: 'a'.repeat(40)})]) {
    assert.notEqual(run(value).status, 0);
  }
});

test('real Git raw changes admit a regular modification and reject structural changes', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-ci-maintenance-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  Object.assign(env, {GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null'});
  const git = args => {
    const result = spawnSync('git', args, {cwd: root, env, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    return result.stdout;
  };
  git(['init', '--quiet']);
  git(['config', 'user.name', 'Maintenance Fixture']);
  git(['config', 'user.email', 'maintenance@example.invalid']);
  git(['config', 'commit.gpgsign', 'false']);
  git(['config', 'core.filemode', 'true']);
  mkdirSync(join(root, 'docs'));
  const path = join(root, 'docs/development.md');
  writeFileSync(path, 'Original developer instructions\n');
  git(['add', '.']); git(['commit', '--quiet', '-m', 'Original regular file']);
  const base = git(['rev-parse', 'HEAD']).trim();
  const inspect = () => {
    git(['add', '--all']); git(['commit', '--quiet', '-m', 'Fixture change']);
    const change = readChanges({pull_request: {base: {sha: base}}}, git);
    return selectTargets(change.paths, change);
  };
  writeFileSync(path, 'Changed developer instructions about hash reports\n');
  assert.equal(inspect().profile, 'maintenance');
  chmodSync(path, 0o755);
  assert.equal(inspect().profile, 'full');
  git(['reset', '--hard', base]);
  git(['mv', 'docs/development.md', 'docs/verification-actions.md']);
  assert.equal(inspect().profile, 'full');
  git(['reset', '--hard', base]);
  writeFileSync(join(root, 'docs/ci-artifact-analysis.md'), 'New documentation\n');
  assert.equal(inspect().profile, 'full');
  git(['reset', '--hard', base]);
  git(['rm', 'docs/development.md']);
  assert.equal(inspect().profile, 'full');
});


test('unclassified proof records retain full coverage without a historical declaration profile', () => {
  const path = 'proofs/relation-pipeline/new-record.json';
  const selected = validateSelection(selectTargets([path]));
  assert.equal(selected.profile, 'full');
  assert.deepEqual(selected.targets, all);
  assert.throws(() => validateSelection({...selected, profile: 'declaration'}), /Invalid selection profile/u);
  assert.throws(() => validateSelection({...selected, declarationChanges: []}), /Invalid selection fields/u);
});

test('normal workflow has no historical declaration admission or artifact requirement', () => {
  assert.deepEqual(jobs.preflight.needs, ['select-targets']);
  for (const job of Object.values(jobs)) {
    for (const step of job.steps ?? []) {
      assert(!step.run?.includes('proofs/relation-pipeline/history.mjs'));
      assert(!step.with?.path?.includes('current-foundation.json'));
      assert(!step.if?.includes("profile == 'declaration'"));
    }
  }
});

const checkpoint = () => ({baseSha: 'a'.repeat(40), testedSha: head, runId: 42, runAttempt: 1, workflowId: 7,
  policy: policyPaths.map(path => ({path, object: 'd'.repeat(40)})), reason: 'Verified full main checkpoint'});
test('main cumulative product changes retain all backend coverage even for portable PR paths', () => {
  for (const paths of [['proofs/relation-pipeline/new-record.json', 'src/source_span/span.mbt'], ['src/source_span/span.mbt'], ['README.md']]) {
    const selected = validateSelection(selectTargets(paths, {event: 'push', mainIntegration: false, mainBaseline: checkpoint()}));
    assert.equal(selected.profile, 'full'); assert.deepEqual(selected.targets, all); assert.equal(selected.macos, true);
  }
});
test('main uses verified base for every raw, text, mode and path diff, never push.before', () => {
  const calls = [], baseRevision = 'a'.repeat(40), before = 'c'.repeat(40);
  const changed = readChanges({before}, args => {
    calls.push(args); if (args[0] === 'rev-parse') return head;
    if (args.includes('--name-only')) return 'src/source_span/span.mbt\0';
    if (args[0] === 'show') return 'ordinary';
    return '+ordinary';
  }, {baseRevision});
  assert.deepEqual(changed.paths, ['src/source_span/span.mbt']);
  for (const args of calls.filter(args => args[0] === 'diff')) { assert(args.includes(baseRevision)); assert(!args.includes(before)); }
});
test('main API permission is read-only and scoped to selection with no persistent token', () => {
  assert.deepEqual(workflow.permissions, {contents: 'read'});
  assert.deepEqual(jobs['select-targets'].permissions, {contents: 'read', actions: 'read'});
  const select = jobs['select-targets'].steps.find(step => step.id === 'select');
  assert.equal(select.env.GITHUB_TOKEN, '${{ github.token }}');
  assert(jobs.lint.steps.some(step => step.run?.includes('scripts/ci-main-base.test.mjs')));
});


test('PR lifecycle uses current event Draft state; ready and later heads retain normal coverage', () => {
  const product = ['src/execution_relation/product.mbt'];
  for (const action of ['opened', 'synchronize', 'reopened', 'converted_to_draft']) {
    const draft = pullRequestDraft('pull_request', {action, pull_request: {draft: true}});
    const selection = validateSelection(selectTargets(product, {draft}));
    assert.equal(selection.profile, 'draft', action);
    assert.equal(selection.macos, false);
    assert.throws(() => verifyGate(plan(selection), results(selection), {...context, draft}), /awaiting ready_for_review/u);
  }
  for (const action of ['opened', 'synchronize', 'reopened', 'ready_for_review']) {
    const draft = pullRequestDraft('pull_request', {action, pull_request: {draft: false}});
    const selection = validateSelection(selectTargets(product, {draft}));
    assert.equal(selection.profile, 'full', action);
    assert.deepEqual(selection.targets, all);
    assert.equal(verifyGate(plan(selection), results(selection), {...context, draft}).length, gateJobs.length);
    assert.throws(() => verifyGate(plan(selection), results(selection), {...context, sourceRevision: 'a'.repeat(40), draft}), /another checkout/u);
  }
  for (const payload of [{}, {action: 'synchronize', pull_request: {draft: 'false'}},
    {action: 'ready_for_review', pull_request: {draft: true}},
    {action: 'converted_to_draft', pull_request: {draft: false}}]) {
    assert.throws(() => pullRequestDraft('pull_request', payload));
  }
  const ready = maintenanceSelection(['docs/development.md']);
  assert.equal(selectTargets(ready.paths, {draft: false, maintenanceChanges: ready.maintenanceChanges}).profile, 'maintenance');
  assert.throws(() => verifyGate(plan(ready), results(ready), {...context, draft: true}), /awaiting ready_for_review/u);
  assert.equal(pullRequestDraft('workflow_dispatch', {pull_request: {draft: true}}), null);
  assert.equal(selectTargets(product, {event: 'workflow_dispatch', draft: true}).profile, 'full');
});

test('Draft cannot start product, packed, proof or backend jobs; final gate still runs', () => {
  const heavy = ['core', 'host', 'client-packages', 'client-distribution', 'client-packed', 'client-salesforce',
    'native', 'session-evidence', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity',
    'pipeline-capacity-mutants', 'pipeline-validation', 'native-macos', 'native-separated-network',
    'workers', 'connector-addition', 'duckdb-node'];
  for (const profile of ['draft', 'draft-focused']) {
    const needs = {'select-targets': {outputs: {profile, macos: 'false'}}};
    for (const name of heavy) assert.equal(scheduled(name, needs), false, `${profile}/${name}`);
    assert.equal(scheduled('focused-tests', needs), profile === 'draft-focused');
    for (const name of ['preflight', 'lint', 'spec', 'check']) assert.equal(scheduled(name, needs), true, name);
  }
  // Converted-to-draft and ready events have the same PR ref/group. The existing
  // cancel-in-progress expression supersedes prior preparation/full attempts.
  assert(workflow.concurrency.group.includes('${{ github.ref }}'));
  assert.equal(workflow.concurrency['cancel-in-progress'], "${{ !inputs.performance_matrix && github.ref != 'refs/heads/main' }}");
});

function draftStepEnabled(step, profile) {
  if (!step.if) return true;
  const expression = step.if.replace(/^\$\{\{\s*|\s*\}\}$/gu, '')
    .replace(/needs\.([a-z][a-z0-9-]*)/gu, (_, name) => `needs[${JSON.stringify(name)}]`);
  return Function('needs', 'startsWith', `return (${expression});`)(
    {'select-targets': {outputs: {profile}}}, (value, prefix) => value.startsWith(prefix));
}
test('Draft cheap command inventory excludes compiler API generation and compound suites', () => {
  const commands = name => jobs[name].steps.filter(step => step.run && draftStepEnabled(step, 'draft')).map(step => step.run);
  const preflight = commands('preflight');
  assert.deepEqual(preflight.filter(command => !command.includes('setup-moonbit')), [
    'node --test scripts/pure-operation-inventory.test.mjs',
    'python3 scripts/test_native_timings.py CommandCounterMap', 'npm ci', 'node --test proofs/relation-pipeline/ci-artifacts.test.mjs', 'npm run check:contract-versions',
    'npm run check:metadata', 'moon fmt --check', 'git diff --exit-code', 'node scripts/ci-preflight.mjs']);
  assert.deepEqual(commands('lint'), ['npm ci', 'npm run check:client-types',
    'node --test scripts/ci-preflight.test.mjs', 'node --test scripts/ci-focused-tests.test.mjs',
    'node --test scripts/ci-targets.test.mjs scripts/ci-main-base.test.mjs']);
  assert.deepEqual(commands('spec'), ['npm ci', 'npm run check:links',
    'npm run check:local-resource-completion', 'npm run check:execution-authorization-vectors', 'git diff --exit-code']);
  for (const name of ['lint', 'spec']) {
    assert(!jobs[name].steps.some(step => draftStepEnabled(step, 'draft') &&
      (step.uses === './.github/actions/setup-toolchain' || step.uses?.startsWith('actions/setup-python@'))));
  }
  for (const profile of ['full', 'maintenance', 'focused-tests']) {
    assert(jobs.preflight.steps.filter(step => step.run === 'node scripts/check-moonbit-api.mjs').every(step => draftStepEnabled(step, profile)));
    assert(jobs.spec.steps.filter(step => step.run === 'npm run check:spec-after-preflight').every(step => draftStepEnabled(step, profile)));
  }
});

test('every job fails closed before runner allocation until public and explicitly enabled', () => {
  const guard = "vars.ACTQL_MAIN_CI_ENABLED == 'true' && github.event.repository.visibility == 'public' && toJSON(github.event.repository.private) == 'false'";
  const performance = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  const probe = parse(readFileSync(new URL('../.github/workflows/packed-query-evidence-probe.yml', import.meta.url), 'utf8'));
  assert.deepEqual(Object.keys(probe.on), ['workflow_call']);
  for (const [name, job] of Object.entries({...jobs, ...performance.jobs, ...probe.jobs})) {
    assert(job.if.startsWith('${{ ' + guard), name);
    // Evaluate the actual prefix, independently of job-specific applicability.
    const expression = job.if.slice(4, 4 + guard.length);
    for (const [enabled, visibility, privateFlag, expected] of [
      [undefined, 'public', false, false], ['', 'public', false, false],
      ['false', 'public', false, false], ['true', 'private', true, false],
      ['true', 'public', true, false], ['true', undefined, false, false],
      ['true', 'public', undefined, false], ['true', 'public', null, false],
      ['true', 'public', 0, false], ['true', 'public', 'false', false],
      ['true', 'public', false, true],
    ]) {
      assert.equal(runInNewContext(expression, {vars: {ACTQL_MAIN_CI_ENABLED: enabled},
        github: {event: {repository: {visibility, private: privateFlag}}}, toJSON: JSON.stringify}, {timeout: 100}), expected, name);
    }
  }
  for (const name of ['check', 'client', 'pipeline-evidence']) assert(jobs[name].if.includes('always()'), name);
});

test('automatic main integration remains full even with valid narrow cumulative evidence', () => {
  const cases = [
    {paths: ['proofs/relation-pipeline/new-record.json']},
    {paths: ['docs/development.md'], maintenanceChanges: changes(['docs/development.md'])},
    {paths: []},
  ];
  for (const inputs of cases) {
    const selected = validateSelection(selectTargets(inputs.paths, {...inputs, event: 'push', mainBaseline: checkpoint()}));
    assert.equal(selected.profile, 'full');
    assert.deepEqual(selected.targets, all); assert.equal(selected.macos, true);
    const lines = verifyGate(plan(selected), results(selected), {...context, event: 'push'});
    assert(!lines.some(line => line.startsWith('NOT APPLICABLE core')));
  }
});

test('normal distribution keeps original Request resource and cleanup regressions selected once', () => {
  const command = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'))
    .scripts['check:distribution-client'];
  const selected = command.split(/\s+/u);
  for (const file of [
  "adapters/host-node/content-pre-record-retirement.test.mjs",
  "adapters/host-node/effect-capture-connection.test.mjs",
  "adapters/host-node/effect-capture-resources.test.mjs",
  "adapters/host-node/request-content-graph-resources.test.mjs",
  "adapters/host-node/request-keyed-prefix-execution.test.mjs",
  "adapters/host-node/request-model-material-resources.test.mjs",
  "adapters/host-node/request-model-source-ledger.test.mjs",
  "adapters/store-local/private-evidence-consumer-lifetime.test.mjs",
  "adapters/host-node/request-domain-source-preflight.test.mjs",
  "adapters/host-node/content-execution-alias-retirement.test.mjs"
]) {
    assert.equal(selected.filter(value => value === file).length, 1, file);
  }
});
