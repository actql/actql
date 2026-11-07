import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, rmSync, writeFileSync, chmodSync, symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {parse} from 'yaml';
import {pullRequestDraft, readChanges, selectTargets, validateSelection, verifyGate, maintenanceFiles, gateJobs, pythonWheelAcceptanceRequired, deepProofRequired, gateJobRequired, readPushChanges} from './ci-targets.mjs';
import {occurrences} from './check-owned-contract-versions.mjs';
import {prepareNativeRuntimeBundle} from './native-runtime-bundle-fixture.mjs';
const all = ['js', 'wasm', 'native'];
const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const {jobs} = workflow;

function nativeScratchSourceFixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-scratch-source-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const repository = join(root, 'checkout'), runner = join(root, 'runner-temp');
  mkdirSync(repository);mkdirSync(runner);
  const git = args => {
    const result = spawnSync('git', args, {cwd: repository, encoding: 'utf8', timeout: 5000});
    assert.equal(result.error, undefined);assert.equal(result.status, 0, result.stderr);
    return result.stdout;
  };
  git(['init', '--quiet']);
  writeFileSync(join(repository, 'source.txt'), 'Original tracked Source\n');
  git(['add', 'source.txt']);
  git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
    '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'Original Source']);
  const afterSourceAdmission = new Error('Source admitted before compiler selection');
  const prepare = () => prepareNativeRuntimeBundle(repository, join(root, 'bundle'), {
    platform: 'linux', arch: 'x64', moonHome: root,
    execute(command, args) {
      if (command === 'git') return git(args);
      assert.equal(command, 'sh');assert.deepEqual(args, ['-c', 'command -v clang']);
      // Stop before any compiler, producer, prepared artifact or Native Runtime.
      throw afterSourceAdmission;
    },
  });
  return {repository, runner, git, prepare, afterSourceAdmission};
}

test('Linux Native scratch output leaves Source clean for delayed bundle admission', t => {
  const f = nativeScratchSourceFixture(t);
  const step = jobs.native.steps.find(row => row.name === 'Test Node-free native storage publication and control');
  const scratch = step.env.ACTQL_TEST_SCRATCH_ROOT
    .replaceAll('${{ github.workspace }}', f.repository)
    .replaceAll('${{ runner.temp }}', f.runner);
  mkdirSync(scratch, {recursive: true});
  const original = mkdtempSync(join(scratch, 'native-http-'));
  writeFileSync(join(original, 'original-fixture-output.txt'), 'Retained original output\n');
  assert.throws(f.prepare, error => error === f.afterSourceAdmission);
  assert.equal(f.git(['status', '--porcelain']), '');
  assert.equal(readFileSync(join(original, 'original-fixture-output.txt'), 'utf8'), 'Retained original output\n');
});

test('Native bundle Source admission still refuses untracked checkout scratch output', t => {
  const f = nativeScratchSourceFixture(t);
  mkdirSync(join(f.repository, '.native-tests'));
  writeFileSync(join(f.repository, '.native-tests', 'original-output.txt'), 'Retained output\n');
  assert.throws(f.prepare, /Clean fixed bundle build Source required/u);
  assert.equal(f.git(['status', '--porcelain']), '?? .native-tests/\n');
});

test('preflight checks Native counter assignments before the build toolchain', () => {
  const steps = jobs.preflight.steps;
  const index = steps.findIndex(row =>
    row.name === 'Check Native diagnostic counter assignments before fan-out');
  assert.ok(index >= 0);
  assert.equal(steps[index].run, 'python3 scripts/test_native_timings.py CommandCounterMap');
  assert.ok(index < steps.findIndex(row => row.name === 'Install pinned MoonBit'));
  assert.ok(jobs.native.needs.includes('preflight'));
});

test('Linux Native profile compilers retain their commands and existing stack prerequisite', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-profile-stack-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const npm = join(root, 'npm');
  writeFileSync(npm, '#!/bin/sh\nprintf "%s:%s\\n" "$ACTQL_FIXTURE_STACK_KIB" "$*"\nexit "$ACTQL_FIXTURE_NPM_EXIT"\n');
  chmodSync(npm, 0o755);
  writeFileSync(join(root, 'node'), readFileSync(npm));
  chmodSync(join(root, 'node'), 0o755);
  for (const [job, name, command] of [
    ['native', 'Test Node-free native storage publication and control', 'scripts/test-native-http-client.mjs'],
    ['native-separated-network', 'Verify native direct and outbound-only Store profiles', 'check:native-separated-network'],
  ]) {
    assert.equal(jobs[job]['runs-on'], 'ubuntu-24.04');
    const step = jobs[job].steps.find(row => row.name === name);
    assert.ok(step);
    assert.equal(step.if, job === 'native' ? "${{ !cancelled() && steps.native-preparation.outcome == 'success' }}" : undefined);
    assert.equal(step['continue-on-error'], undefined);
    assert.match(step.run, /ulimit -S -s 65536\s+?(?:node |npm run )/u);
    // Observe exact shell ordering and child inheritance without starting a
    // Native compiler or changing the host shell's hard resource limit.
    const observe = 'ulimit() { test "$*" = "-S -s 65536" || return 93; ' +
      'export ACTQL_FIXTURE_STACK_KIB="$3"; }\n';
    for (const status of [0, 7]) {
      const result = spawnSync('bash', ['-eo', 'pipefail', '-c', observe + step.run], {
        cwd: root, encoding: 'utf8', timeout: 5000,
        env: {...process.env, PATH: root + ':' + process.env.PATH,
          ACTQL_FIXTURE_NPM_EXIT: String(status)},
      });
      assert.equal(result.error, undefined);
      assert.equal(result.signal, null);
      assert.equal(result.status, status, result.stderr);
      assert.equal(result.stdout.trim(), `65536:${job === 'native' ? command : `run ${command}`}`);
    }
  }
});

test('Native consumers keep all original commands and collect independent failures after preparation', t => {
  const manifest = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  const expected = manifest.scripts['check:native-http-client'].split(' && ');
  const condition = "${{ !cancelled() && steps.native-preparation.outcome == 'success' }}";
  const root = mkdtempSync(join(tmpdir(), 'actql-native-independent-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const log = join(root, 'calls');
  writeFileSync(join(root, 'node'), '#!/bin/sh\nprintf "%s\\n" "$*" >> "$ACTQL_CALL_LOG"\n' +
    'exit "$ACTQL_FIXTURE_EXIT"\n');
  chmodSync(join(root, 'node'), 0o755);
  for (const name of ['native', 'native-macos']) {
    const steps = jobs[name].steps.filter(step => step.id?.startsWith('native-') &&
      step.id !== 'native-preparation');
    assert.deepEqual(steps.map(step => step.run.trim().split('\n').at(-1)), expected);
    assert.equal(new Set(steps.map(step => step.env.ACTQL_TEST_SCRATCH_ROOT)).size, expected.length);
    const results = steps.map((step, index) => {
      assert.equal(step.if, condition);
      assert.equal(step['continue-on-error'], undefined, 'a failed case must still fail the job');
      return spawnSync('bash', ['-eo', 'pipefail', '-c',
        (name === 'native' ? 'ulimit() { test \"$*\" = \"-S -s 65536\"; }\n' : '') + step.run], {
        cwd: root, encoding: 'utf8', timeout: 5000,
        env: {...process.env, PATH: root + ':' + process.env.PATH,
          ACTQL_CALL_LOG: log, ACTQL_FIXTURE_EXIT: index === 0 ? '7' : '0'},
      });
    });
    assert.equal(results[0].status, 7, results[0].stderr);
    assert(results.slice(1).every(result => result.status === 0));
    assert(jobs[name].steps.find(step => step.id === 'native-preparation').run
      .includes('prepare-native-runtime-bundle-fixture.mjs'));
  }
  assert.equal(readFileSync(log, 'utf8').trim().split('\n').length, expected.length * 2);
  for (const id of ['packed-materials', 'packed-redelivery', 'packed-output-report'])
    assert.equal(jobs.native.steps.find(step => step.id === id).if, condition);
});

test('Native retained verification builds exactly its checked release module inventory', () => {
  const step = jobs.native.steps.find(step => step.name === 'Verify registered Native retained product path');
  assert(step);
  const source = readFileSync(new URL('../benchmarks/retained-results/release-artifacts.mjs', import.meta.url), 'utf8');
  const inventory = /const modules = Object\.freeze\((\[[\s\S]*?\])\);/u.exec(source);
  assert(inventory, 'the original checked release inventory must remain explicit');
  const modules = Array.from(runInNewContext(inventory[1]));
  assert(modules.length > 0);
  const targets = modules.map(path => 'src/' + path.slice(0, path.lastIndexOf('/')));
  assert.equal(new Set(targets).size, targets.length);
  const commands = step.run.replace(/\\\n\s*/gu, ' ').trim().split('\n').map(line => line.trim().replace(/\s+/gu, ' '));
  assert.deepEqual(commands[0].split(/\s+/u), ['moon', 'build', '--target', 'js', '--release', ...targets]);
  assert.equal(step.if, "${{ !cancelled() && steps.native-preparation.outcome == 'success' }}");
  assert.deepEqual(commands.slice(1), [
    'moon build src/cmd/native_retained_case_probe --target native --release',
    'node benchmarks/retained-results/native-case-probe.mjs native-acquisition-full-validation-low-selectivity/narrow/100',
    'node benchmarks/retained-results/native-case-probe.mjs fixed-join-count-shrinking-intermediate/narrow/1000',
    'node benchmarks/retained-results/native-estimate-calibration.mjs native-acquisition-full-validation-low-selectivity/narrow/1000 native-acquisition-full-validation-low-selectivity/narrow/100 "$RUNNER_TEMP/native-retained-calibration.json"',
    'ACTQL_NATIVE_CALIBRATION_PROFILE="$RUNNER_TEMP/native-retained-calibration.json" node scripts/test-native-direct-pair.mjs',
  ]);
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
  assert.equal(observed.run, 'node --test adapters/host-node/authorization-account-current.test.mjs adapters/host-node/local-account-current.test.mjs adapters/host-node/local-run-authorization.test.mjs adapters/host-node/client-run-state-revision.test.mjs adapters/host-node/client-run-observation-reuse.test.mjs adapters/host-common/run-state-clock-order.test.mjs adapters/host-node/client-run-stop-observation.test.mjs adapters/host-node/embedded-managed-compute-projection.test.mjs adapters/host-node/mock-effect-host-original.test.mjs adapters/host-node/embedded-managed-compute-lifecycle.test.mjs adapters/host-node/installed-managed-source.test.mjs adapters/host-node/embedded-source-environment-scope.test.mjs adapters/host-node/client-original-submitted-intent.test.mjs adapters/host-common/observation.test.mjs adapters/host-node/in-process-result-observation.test.mjs');
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
  assert.equal(steps[index].if, "${{ !cancelled() && steps.cold-runtime-preparation.outcome == 'success' }}");
  assert.equal(steps[index]['continue-on-error'], undefined);
  // These cases use actual Core/Resource/registration and temporary SQLite,
  // not live provider credentials or another runtime build/cleanup substitute.
});

test('Host collection retains original command bodies and their actual build prerequisites', () => {
  const {scripts} = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  const steps = jobs.host.steps;
  const step = name => {
    const found = steps.filter(row => row.name === name);
    assert.equal(found.length, 1, name);
    return found[0];
  };
  const commands = name => scripts[name].split(' && ');
  const retained = commands('check:retained-boundary');
  const publication = commands('check:publication-runtime');
  assert.equal(retained[0], publication[0]);
  assert.equal(step('Prepare the shared Host runtime').run, retained[0]);
  assert.equal(step('Test bounded retained storage and process lifecycle').run, retained[1]);
  assert.equal(step('Test prepared holder cleanup owner').run, retained[2]);
  assert.equal(step('Test portable publication control with the durable Store').run, publication[1]);
  assert.equal(step('Test original publication owned extents').run, publication[2]);
  const ownedHost = commands('check:publication-owned-host');
  assert.deepEqual(ownedHost.length, 2);
  assert.equal(publication[3], 'npm run check:publication-owned-host');
  assert.equal(step('Test original publication Host extents').run, ownedHost[0]);
  assert.equal(step('Test original publication Host callers').run, ownedHost[1]);
  const remote = commands('check:remote-site-runtime');
  assert.equal(remote.length, 4);
  assert.equal(step('Prepare the Remote Site runtime').run, remote.slice(0, 2).join('\n') + '\n');
  assert.equal(step('Test durable Remote Site dispatch admission').run, remote[2]);
  assert.equal(step('Test packed Remote coordinator').run, remote[3]);
  assert.equal(step('Test original holder terminal facade').run,
    'node --test packages/coordinator-core/holder-terminal.test.mjs');
  const runHost = commands('check:run-host-core');
  assert.equal(runHost.length, 4);
  assert.equal(step('Prepare the Run Host runtime').run, runHost[0]);
  assert.equal(step('Check Run Host types').run, runHost[1]);
  assert.equal(step('Test portable Run Host compilation package').run, runHost[2]);
  assert.equal(step('Test packed Run Host compilation package').run, runHost[3]);
  assert.equal(step('Test original Local result authorization').run,
    'node --test adapters/host-node/local-result-authorization.test.mjs');
  assert.equal(steps.filter(row => row.run === retained[0]).length, 1,
    'the two identical Common build prefixes are shared, without another build');
});

test('Host independent failures are collected while failed prerequisites and cancellation stop consumers', () => {
  const steps = jobs.host.steps;
  const prerequisites = {
    'host-toolchain': new Set(['host-runtime-preparation']),
    'remote-site-preparation': new Set(['Test durable Remote Site dispatch admission',
      'Test packed Remote coordinator', 'Test original holder terminal facade']),
    'run-host-preparation': new Set(['Check Run Host types',
      'Test portable Run Host compilation package', 'Test packed Run Host compilation package',
      'Test original Local result authorization']),
    'cold-runtime-preparation': new Set(['Test actual bound connector initialization and cleanup']),
  };
  const setup = steps.find(row => row.id === 'host-toolchain');
  assert.equal(setup.uses, './.github/actions/setup-toolchain');
  assert.equal(setup.if, undefined);
  for (const row of steps.filter(row => row.run)) {
    const preparation = Object.entries(prerequisites).find(([, names]) =>
      names.has(row.id) || names.has(row.name))?.[0] ?? 'host-runtime-preparation';
    assert.equal(row.if, '${{ !cancelled() && steps.' + preparation + ".outcome == 'success' }}", row.name);
    assert.equal(row['continue-on-error'], undefined, row.name);
    const expression = row.if.slice(3, -3).replace(/steps\.([a-z][a-z0-9-]*)/gu,
      (_, name) => `steps[${JSON.stringify(name)}]`);
    const admitted = (outcome, cancelled = false) => Function('steps', 'cancelled',
      `return (${expression});`)({[preparation]: {outcome}, 'earlier-independent-test': {outcome: 'failure'}},
      () => cancelled);
    assert.equal(admitted('success'), true, 'a failed sibling cannot suppress this original case');
    for (const outcome of ['failure', 'cancelled', 'skipped', undefined])
      assert.equal(admitted(outcome), false, `${row.name}: ${outcome}`);
    assert.equal(admitted('success', true), false, 'workflow cancellation remains authoritative');
    assert(steps.findIndex(item => item.id === preparation) < steps.indexOf(row), row.name);
  }
  assert.equal(jobs.host['timeout-minutes'], 30);
  assert.equal(jobs.host.strategy, undefined, 'collect serially without new shared-state concurrency');
  assert.equal(jobs.host['continue-on-error'], undefined);
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
    assert.match(result.reason, /full targets run on main integration; optional macOS can be requested manually/u);
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
test('read-only PR lifecycle, main pushes and explicit dispatch trigger CI', () => {
  assert.deepEqual(Object.keys(workflow.on).sort(), ['pull_request', 'push', 'schedule', 'workflow_dispatch']);
  assert.deepEqual(workflow.on.push.branches, ['main']);
  assert.deepEqual(workflow.on.pull_request.types, ['opened', 'synchronize', 'reopened', 'ready_for_review', 'converted_to_draft']);
  assert.equal(workflow.on.pull_request_target, undefined);
  assert.deepEqual(workflow.on.schedule, [{cron: '23 3 * * 1'}]);
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
  assert.equal(Object.hasOwn(selection, 'mainBaseline'), false);
  const results = Object.fromEntries(gateJobs.map(name => [name, {result: 'success'}]));
  results['main-performance'] = {result: 'skipped'};
  results['health-quick'] = {result: 'skipped'};
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
for (const [name, entries, producerCount, residentSeconds, remainingMinutes] of [
  ['native', 'all', 4, 900, 45],
  ['native-macos', 'all', 4, 1200, 45],
  ['native-separated-network', 'bundle', 2, 900, 25],
]) {
  test(`Native preparation outer budgets retain every producer and consumer window (${name})`, () => {
    const job = jobs[name];
    assert.equal(job['runs-on'], name === 'native-macos' ? 'macos-15' : 'ubuntu-24.04');
    const preparation = job.steps.find(step =>
      step.name === 'Prepare exact-source scoped Native commands and components once');
    assert.equal(preparation.run, 'node scripts/prepare-native-runtime-bundle-fixture.mjs ' +
      '--destination "${{ runner.temp }}/native-scoped-preparation" --entries ' + entries + ' --seconds 900' +
      (entries === 'all' ? ' --http-jobs 2' : '') +
      (residentSeconds === 900 ? '' : ' --resident-seconds ' + residentSeconds));
    assert.equal(preparation.if, undefined);
    assert.equal(preparation['continue-on-error'], undefined);
    // Only the macOS Resident cold build selects 1200 seconds; all other
    // producers retain 900 seconds. Each has its own 30-second
    // enclosing-call allowance. Keep three minutes for metadata and cleanup,
    // rounded up to a finite five-minute workflow window. This is not a
    // runtime capacity, a runtime test timeout, or a cleanup acknowledgment.
    const producerSeconds = producerCount * 900 + (entries === 'all' ? residentSeconds - 900 : 0);
    const preparationMinutes = Math.ceil((producerSeconds + producerCount * 30 + 180) / 300) * 5;
    assert.equal(preparation['timeout-minutes'], preparationMinutes);
    assert.equal(job['timeout-minutes'], preparationMinutes + remainingMinutes,
      'the existing non-preparation window survives the outer scheduling correction');
  });
}

test('ordinary Read activation regressions run on the selected Native toolchain', () => {
  const steps = jobs.native.steps;
  const setup = steps.findIndex(step => step.uses === './.github/actions/setup-toolchain');
  const process = steps.findIndex(step => step.name ===
    'Test selected Linux x64 process-provider ABI and original physical custody');
  const index = steps.findIndex(step => step.name ===
    'Test original Read slab activation custody on selected Linux x64');
  assert.ok(setup >= 0 && setup < process && process < index);
  assert.equal(steps[index].run, 'python3 -B scripts/test_native_read_activation.py');
  assert.equal(steps[index]['timeout-minutes'], 3);
  assert.equal(steps[index].if, undefined);
  assert.equal(steps[index]['continue-on-error'], undefined);
  assert.equal(steps[index].env, undefined, 'inherit the original selected compiler and MoonBit');
  const retained = steps.find(step => step.name ===
    'Retain Linux x64 process-provider original controls');
  assert.equal(retained.if, 'always()');
  assert.deepEqual(retained.with.path.trim().split('\n'),
    ['_build/linux-x64-owned-process/', '_build/native-read-activation/',
      '_build/native-prepared-controls/', '_build/native-working-origin/']);
});

for (const [name, driver, output] of [
  ['prepared constructor cohorts', 'test_native_prepared_controls.py', '_build/native-prepared-controls/'],
  ['working carrier custody', 'test_native_working_origin.py', '_build/native-working-origin/'],
]) {
  test(`original ${name} execute on selected Native toolchain and retain failed diagnostics`, () => {
    const steps = jobs.native.steps;
    const setup = steps.findIndex(step => step.uses === './.github/actions/setup-toolchain');
    const read = steps.findIndex(step => step.run === 'python3 -B scripts/test_native_read_activation.py');
    const index = steps.findIndex(step => step.run === `python3 -B scripts/${driver}`);
    assert.ok(setup >= 0 && setup < read && read < index);
    assert.equal(steps[index]['timeout-minutes'], 3);
    assert.equal(steps[index].if, undefined);
    assert.equal(steps[index]['continue-on-error'], undefined);
    assert.equal(steps[index].env, undefined, 'inherit selected compiler and MoonBit');
    const retained = steps.find(step => step.name ===
      'Retain Linux x64 process-provider original controls');
    assert.equal(retained.if, 'always()');
    assert.ok(retained.with.path.trim().split('\n').includes(output));
  });
}

test('whole-family scheduling retains the core matrix and complete selected proof campaigns', () => {
  assert.equal(jobs['session-evidence']['timeout-minutes'], 60);
  assert.deepEqual(jobs.core.needs, ['select-targets', 'preflight']);
  assert.equal(jobs.core.strategy['fail-fast'], false);
  for (const target of ['js', 'wasm', 'native']) {
    assert.equal(runInNewContext(jobs.core['timeout-minutes'].slice(3, -2),
      {matrix: {target}}, {timeout: 100}), target === 'native' ? 90 : 30);
  }
  assert.equal(jobs.core.strategy.matrix.target, '${{ fromJSON(needs.select-targets.outputs.targets) }}');
  assert.deepEqual(jobs['native-macos'].needs, ['select-targets', 'preflight']);
  assert.equal(jobs['native-macos']['timeout-minutes'], 115);
  assert.equal(jobs.native['timeout-minutes'], 110);
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
  gateJobRequired(selection, name) ? 'success' : 'skipped'}]));
const changes = paths => paths.map(path => ({path, before: {mode: '100644', object: 'c'.repeat(40)},
  after: {mode: '100644', object: 'd'.repeat(40)}}));
const maintenanceSelection = paths => selectTargets(paths, {maintenanceChanges: changes(paths)});

test('required aggregate rejects failed, cancelled, skipped and missing selected jobs', () => {
  const selection = selectTargets(['src/unregistered/engine.mbt']);
  assert.equal(verifyGate(plan(selection), results(selection), context).length, gateJobs.length);
  for (const name of gateJobs.filter(name => gateJobRequired(selection, name))) {
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


test('reviewed evaluation test modifications retain the existing light gate', () => {
  const paths = ['examples/infer-evaluation/evaluate.test.mjs',
    'examples/infer-evaluation/compare-source-instructions.test.mjs'];
  for (const path of paths) {
    assert(readFileSync(new URL('../' + path, import.meta.url), 'utf8').includes('test('));
    const value = validateSelection(maintenanceSelection([path]));
    assert.equal(value.profile, 'maintenance', path);
    assert.equal(deepProofRequired(value), false);
    assert.equal(verifyGate(plan(value), results(value), context).length, gateJobs.length);
  }
  assert.equal(maintenanceSelection([...paths, 'docs/development.md']).profile, 'maintenance');
  for (const input of ['examples/infer-evaluation/evaluate.mjs',
    'examples/infer-evaluation/compare-source-instructions.mjs',
    'examples/infer-evaluation/evidence-reference.mjs',
    'packages/sdk/host-port.mjs', 'src/client_local_host/moon.pkg',
    'package.json', 'toolchain.json', '.github/workflows/ci.yml',
    'proofs/relation-pipeline/inventory.mjs', 'examples/infer-evaluation/new.test.mjs']) {
    const value = maintenanceSelection([paths[0], input]);
    assert.equal(value.profile, 'full', input);
    assert.equal(deepProofRequired(value), true, input);
  }
});

test('actual evaluation Source Git changes reject additions deletions renames and shared inputs', t => {
  const checkout = mkdtempSync(join(tmpdir(), 'actql-ci-evaluation-'));
  t.after(() => rmSync(checkout, {recursive: true, force: true}));
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  Object.assign(env, {GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null'});
  const git = args => {
    const result = spawnSync('git', args, {cwd: checkout, env, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr); return result.stdout;
  };
  const reviewed = ['examples/infer-evaluation/evaluate.test.mjs',
    'examples/infer-evaluation/compare-source-instructions.test.mjs'];
  const shared = ['examples/infer-evaluation/evaluate.mjs', 'packages/sdk/host-port.mjs',
    'src/client_local_host/source_capture.mbt', 'package.json', 'toolchain.json',
    '.github/workflows/ci.yml', 'proofs/relation-pipeline/inventory.mjs'];
  for (const file of [...reviewed, ...shared, 'docs/development.md']) {
    const target = join(checkout, file); mkdirSync(dirname(target), {recursive: true});
    writeFileSync(target, readFileSync(new URL('../' + file, import.meta.url)));
  }
  git(['init', '--quiet']); git(['config', 'user.name', 'Evaluation Source Fixture']);
  git(['config', 'user.email', 'evaluation@example.invalid']); git(['config', 'commit.gpgsign', 'false']);
  git(['config', 'core.filemode', 'true']); git(['add', '.']); git(['commit', '--quiet', '-m', 'Actual original Source inputs']);
  const base = git(['rev-parse', 'HEAD']).trim();
  const edit = file => writeFileSync(join(checkout, file), readFileSync(join(checkout, file), 'utf8') + '\n');
  const inspect = (before = base) => {
    git(['add', '--all']); git(['commit', '--quiet', '-m', 'Independent fixture change']);
    const read = readChanges({pull_request: {base: {sha: before}}}, git);
    return validateSelection(selectTargets(read.paths, read));
  };
  for (const file of reviewed) {
    git(['reset', '--hard', base]); edit(file);
    const value = inspect(); assert.equal(value.profile, 'maintenance', file);
    const revision = git(['rev-parse', 'HEAD']).trim();
    const envelope = {sourceRevision: revision, selection: value};
    assert.equal(verifyGate(envelope, results(value), {event: 'pull_request', sourceRevision: revision}).length, gateJobs.length);
  }
  git(['reset', '--hard', base]);
  for (const file of [...reviewed, 'docs/development.md']) edit(file);
  assert.equal(inspect().profile, 'maintenance', 'known independent regions keep the same required union');
  for (const file of shared) {
    git(['reset', '--hard', base]); edit(reviewed[0]); edit(file);
    assert.equal(inspect().profile, 'full', file);
  }
  git(['reset', '--hard', base]); git(['rm', reviewed[0]]); assert.equal(inspect().profile, 'full');
  git(['reset', '--hard', base]); git(['rm', reviewed[1]]); git(['mv', reviewed[0], reviewed[1]]);
  assert.equal(inspect().profile, 'full', 'a rename between two reviewed names still exposes the deletion');
  git(['reset', '--hard', base]); chmodSync(join(checkout, reviewed[0]), 0o755);
  assert.equal(inspect().profile, 'full');
  git(['reset', '--hard', base]); git(['rm', reviewed[0]]); git(['commit', '--quiet', '-m', 'Absent reviewed file']);
  const absent = git(['rev-parse', 'HEAD']).trim();
  writeFileSync(join(checkout, reviewed[0]), readFileSync(new URL('../' + reviewed[0], import.meta.url)));
  assert.equal(inspect(absent).profile, 'full', 'a reviewed pathname is not permission for a new file');
});

test('maintenance inventory is exact and every existing reviewed modification qualifies', () => {
  assert.equal(maintenanceFiles.length, 19);
  assert.equal(new Set(maintenanceFiles).size, 19);
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
const scheduled = (name, needs, inputs = {}, isCancelled = false) => {
  const expression = jobs[name].if.slice(3, -3).replace(/needs\.([a-z][a-z0-9-]*)/gu, (_, name) => `needs[${JSON.stringify(name)}]`);
  return Function('needs', 'inputs', 'always', 'cancelled', 'vars', 'github', 'toJSON', `return (${expression});`)(needs, inputs, () => true, () => isCancelled,
    {}, {event: {repository: {visibility: 'public', private: false}}}, JSON.stringify);
};
test('pipeline evidence aggregates dependency failures but stops on workflow cancellation', () => {
  const names = jobs['pipeline-evidence'].needs;
  const healthy = Object.fromEntries(names.map(name => [name, {result: 'success'}]));
  for (const result of ['success', 'failure', 'cancelled', 'skipped', undefined]) {
    const needs = {...healthy, 'pipeline-capacity': {result}};
    assert.equal(scheduled('pipeline-evidence', needs), true, `dependency ${result} must be aggregated`);
    assert.equal(scheduled('pipeline-evidence', needs, {}, true), false,
      `workflow cancellation must stop evidence work after dependency ${result}`);
  }
  const selection = selectTargets(['src/unregistered/engine.mbt']);
  for (const result of ['failure', 'cancelled', 'skipped']) {
    const candidate = results(selection);
    candidate['pipeline-evidence'] = {result};
    assert.throws(() => verifyGate(plan(selection), candidate, context), /pipeline-evidence/u);
  }
});
test('aggregate workflow expressions run on mixed failures and skip only wholly unselected families', () => {
  for (const [name, groups] of [['client', ['client-packages', 'client-distribution', 'client-distribution-callers', 'client-distribution-mutations', 'client-distribution-packed', 'client-distribution-native', 'client-packed', 'client-packed-composition', 'client-salesforce']],
    ['pipeline-evidence', ['pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants', 'pipeline-validation']]]) {
    assert.deepEqual(jobs[name].needs, groups);
    assert.match(jobs[name].if, /always\(\)/u);
    const skipped = Object.fromEntries(groups.map(group => [group, {result: 'skipped'}]));
    assert.equal(scheduled(name, skipped), false);
    for (const group of groups.filter(group => group !== 'pipeline-validation')) for (const result of ['success', 'failure', 'cancelled', undefined]) {
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
  const heavy = ['core', 'host', 'client-packages', 'client-distribution', 'client-distribution-callers',
    'client-distribution-mutations', 'client-distribution-packed', 'client-distribution-native', 'client-packed', 'client-packed-composition', 'client-salesforce',
    'native-cli-installed', 'native-cli-linux-local', 'native', 'session-evidence', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants', 'pipeline-validation', 'native-macos', 'python-wheels',
    'native-separated-network', 'workers', 'connector-addition', 'duckdb-node'];
  for (const name of heavy) {
    assert(jobs[name].needs.includes('select-targets'));
    assert.equal(scheduled(name, {'select-targets': {outputs: {profile: 'maintenance', macos: 'false'}}}), false);
    assert.equal(scheduled(name, {'select-targets': {outputs: {profile: 'full', python_wheels: 'true', deep_proofs: 'true', macos: 'true'}}}), true);
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

test('full integration cannot skip, omit or fail either actual CLI acceptance job', () => {
  const selection = selectTargets(['README.md'], {event: 'workflow_dispatch', mainIntegration: true, nativeMacos: false});
  for (const name of ['native-cli-installed', 'native-cli-linux-local']) {
    for (const result of ['missing', 'failure', 'cancelled', 'skipped']) {
      const needs = results(selection);
      if (result === 'missing') delete needs[name];
      else needs[name].result = result;
      assert.throws(() => verifyGate(plan(selection), needs, {...context, event: 'workflow_dispatch'}), new RegExp(name));
    }
  }
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

test('main cumulative product changes retain all backend coverage even for portable PR paths', () => {
  for (const paths of [['proofs/relation-pipeline/new-record.json', 'src/source_span/span.mbt'], ['src/source_span/span.mbt'], ['README.md']]) {
    const selected = validateSelection(selectTargets(paths, {event: 'push', mainIntegration: false}));
    assert.equal(selected.profile, 'full'); assert.deepEqual(selected.targets, all); assert.equal(selected.macos, true);
  }
});
test('normal selection needs no Actions token or history API permission', () => {
  assert.deepEqual(workflow.permissions, {contents: 'read'});
  assert.deepEqual(jobs['select-targets'].permissions, {contents: 'read'});
  const select = jobs['select-targets'].steps.find(step => step.id === 'select');
  assert.equal(select.env.GITHUB_TOKEN, undefined);
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

test('Unrelated Draft cannot start product, packed, proof or backend jobs; final gate still runs', () => {
  const heavy = ['core', 'host', 'client-packages', 'client-distribution', 'client-distribution-callers',
    'client-distribution-mutations', 'client-distribution-packed', 'client-distribution-native', 'client-packed', 'client-packed-composition', 'client-salesforce',
    'native-cli-installed', 'native-cli-linux-local', 'native', 'session-evidence', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity',
    'pipeline-capacity-mutants', 'pipeline-validation', 'native-macos', 'python-wheels', 'native-separated-network',
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
  // The pinned standalone workflow checker is also mandatory during Draft preparation.
  // Its exact version, digest and all-workflow/fatal contract are checked by ci-preflight.test.mjs.
  const workflowLint = jobs.preflight.steps.find(step => step.name === 'Check all workflows with pinned actionlint');
  assert(workflowLint);
  assert.equal(workflowLint.if, undefined);
  assert.equal(workflowLint['continue-on-error'], undefined);
  assert.deepEqual(preflight.filter(command => !command.includes('setup-moonbit')), [
    workflowLint.run,
    'node --test scripts/pure-operation-inventory.test.mjs',
    'python3 scripts/test_native_timings.py CommandCounterMap', 'npm ci',
    `node --input-type=module -e 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("node",["--test-name-pattern","^check:.* retains its exact registered commands", "scripts/build-runtime-packages.test.mjs"],{cwd:process.cwd()});'`,
    'node --test proofs/relation-pipeline/ci-artifacts.test.mjs', 'npm run check:contract-versions',
    'npm run check:metadata', 'moon fmt --check', 'git diff --exit-code', 'node scripts/ci-preflight.mjs']);
  assert.deepEqual(commands('lint'), ['npm ci', 'npm run check:client-types',
    'node --test scripts/source-read-current-control.test.mjs',
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

test('public jobs do not require an activation variable; private and unknown repositories stay excluded', () => {
  const guard = "github.event.repository.visibility == 'public' && toJSON(github.event.repository.private) == 'false'";
  const workflows = ['ci', 'performance-matrix', 'packed-query-evidence-probe', 'health-monitor']
    .map(name => parse(readFileSync(new URL(`../.github/workflows/${name}.yml`, import.meta.url), 'utf8')));
  for (const workflow of workflows) for (const [name, job] of Object.entries(workflow.jobs)) {
    assert(job.if.startsWith('${{ ' + guard), name);
    assert(!job.if.includes('vars.'), name);
    const expression = job.if.slice(4, 4 + guard.length);
    for (const [visibility, privateFlag, expected] of [
      ['public', false, true], ['private', true, false], ['public', true, false],
      [undefined, false, false], ['public', undefined, false], ['public', null, false],
      ['public', 0, false], ['public', 'false', false],
    ]) {
      assert.equal(runInNewContext(expression, {
        github: {event: {repository: {visibility, private: privateFlag}}}, toJSON: JSON.stringify}, {timeout: 100}), expected, name);
    }
  }
  for (const name of ['check', 'client', 'pipeline-evidence']) assert(jobs[name].if.includes('always()'), name);
});

test('automatic main integration remains full without cumulative evidence', () => {
  const cases = [
    {paths: ['proofs/relation-pipeline/new-record.json']},
    {paths: ['docs/development.md'], maintenanceChanges: changes(['docs/development.md'])},
    {paths: []},
  ];
  for (const inputs of cases) {
    const selected = validateSelection(selectTargets(inputs.paths, {...inputs, event: 'push'}));
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
  "adapters/host-node/metadata-capacity-public.test.mjs",
  "adapters/host-node/installed-duckdb-source-owner.test.mjs",
  "adapters/host-node/table-owned-site-retirement.test.mjs",
  "adapters/host-node/table-original-metadata.test.mjs",
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


test('main CLI selects full checks from a fresh checkout without API token or previous run history', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-ci-main-direct-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const command = (args) => {
    const result = spawnSync('git', args, {cwd: root, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  };
  command(['init', '-q']); command(['config', 'user.name', 'CI fixture']);
  command(['config', 'user.email', 'fixture@example.invalid']);
  writeFileSync(join(root, 'fixture.txt'), 'current source\n');
  command(['add', 'fixture.txt']); command(['commit', '-qm', 'fixture']);
  const revision = command(['rev-parse', 'HEAD']);
  const payloadPath = join(root, 'event.json'), output = join(root, 'output');
  writeFileSync(payloadPath, JSON.stringify({ref: 'refs/heads/main', after: revision}));
  const result = spawnSync(process.execPath, [new URL('./ci-targets.mjs', import.meta.url).pathname], {
    cwd: root, encoding: 'utf8', env: {...process.env, GITHUB_EVENT_NAME: 'push',
      GITHUB_REF: 'refs/heads/main', GITHUB_SHA: revision, GITHUB_EVENT_PATH: payloadPath,
      GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: '', GITHUB_TOKEN: '', GH_TOKEN: ''},
  });
  assert.equal(result.status, 0, result.stderr);
  const plan = JSON.parse(readFileSync(output, 'utf8').split('\n').find(row => row.startsWith('plan=')).slice(5));
  assert.equal(plan.sourceRevision, revision);
  assert.match(readFileSync(output, 'utf8'), /^python_wheels=true$/mu);
  assert.equal(plan.selection.profile, 'full');
  assert.deepEqual(plan.selection.targets, ['js', 'wasm', 'native']);
  assert.equal(plan.selection.macos, true);
  assert.equal(Object.hasOwn(plan.selection, 'mainBaseline'), false);
  assert.deepEqual(plan.selection.paths, []);
});

test('normal Python wheels are mandatory for full profiles independently of optional native macOS', () => {
  const job = jobs['python-wheels'];
  assert.equal(job['runs-on'], 'macos-15');
  assert.deepEqual(job.needs, ['select-targets', 'preflight']);
  assert.equal(scheduled('python-wheels', {'select-targets': {outputs: {profile: 'full', python_wheels: 'true', macos: 'false'}}}), true);
  assert(job.steps.some(step => step.run?.includes('test "$(uname -m)" = arm64')));
  assert(job.steps.some(step => step.run === 'python3 -B scripts/ci-python-wheels.py --destination "$RUNNER_TEMP/python-wheel-acceptance"'));
  assert(jobs.lint.steps.some(step => step.run === 'python3 -B scripts/test_ci_python_wheels.py'));
  const selection = selectTargets(['README.md'], {event: 'workflow_dispatch', mainIntegration: true, nativeMacos: false});
  for (const result of ['failure', 'cancelled', 'skipped']) {
    const needs = results(selection); needs['python-wheels'].result = result;
    assert.throws(() => verifyGate(plan(selection), needs, {...context, event: 'workflow_dispatch'}), /python-wheels/);
  }
});

test('Draft normal Python and CI changes automatically select real wheel acceptance without Ready', () => {
  for (const path of ['.github/workflows/ci.yml', '.github/actions/setup-toolchain/action.yml',
    'scripts/ci-targets.mjs', 'scripts/ci-preflight.mjs', 'scripts/ci-focused-tests.mjs',
    'scripts/ci-python-wheels.py', 'scripts/test_ci_python_wheels.py',
    'scripts/fixtures/ci-python-installed-audit.py', 'scripts/fixtures/ci-python-installed-health.py',
    'scripts/fixtures/ci-python-installed-run.py',
    'scripts/fixtures/python-product-installed.py', 'scripts/fixtures/python-local-duckdb-physical.py',
    'scripts/build-python-product-wheels.py', 'scripts/produce-python-local-runtime.py',
    'scripts/compile-python-local-image.py', 'scripts/prepare-python-local-runtime.py',
    'scripts/python_release_cohort.py', 'scripts/python_interface_inventory.py',
    'scripts/generate-local-wasm-abi.py', 'scripts/release-version.mjs',
    'toolchain.json', 'moon.mod', 'package.json', 'package-lock.json',
    'packages/python-sdk/src/example.py', 'packages/python-product/pyproject.toml',
    'packages/python-local-runtime/new.py']) {
    const selection = selectTargets([path], {draft: true});
    assert.equal(pythonWheelAcceptanceRequired(selection), true, path);
    assert.equal(scheduled('python-wheels', {'select-targets': {outputs: {
      profile: 'draft', python_wheels: String(pythonWheelAcceptanceRequired(selection)), macos: 'false'}}}), true);
    assert.throws(() => verifyGate(plan(selection), results(selection), {...context, draft: true}), /awaiting ready_for_review/);
    for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
      const needs = results(selection); needs['python-wheels'].result = result;
      assert.throws(() => verifyGate(plan(selection), needs, {...context, draft: true}), /python-wheels: expected success/);
    }
  }
  for (const path of ['README.md', 'docs/development.md', 'src/source_span/span.mbt',
    'packages/node-sdk/index.mjs', 'scripts/unrelated.mjs', 'packages/python-sdk-other/test.py']) {
    assert.equal(pythonWheelAcceptanceRequired(selectTargets([path], {draft: true})), false, path);
  }
  for (const paths of [[], null, ['../invalid']]) {
    assert.equal(pythonWheelAcceptanceRequired(selectTargets(paths, {draft: true})), true);
  }
  assert.equal(pythonWheelAcceptanceRequired(maintenanceSelection(['docs/development.md'])), false);
});

test('deleted or renamed Python inputs remain in the tested merge diff and select acceptance', () => {
  for (const paths of [['scripts/ci-python-wheels.py'],
    ['scripts/ci-python-wheels.py', 'scripts/renamed-wheel-acceptance.py'],
    ['scripts/old.py', 'packages/python-sdk/new.py']]) {
    const git = args => {
      if (args[0] === 'rev-parse') return head;
      assert(args.includes('--no-renames'));
      return args.includes('--name-only') ? paths.join('\0') + '\0' : '-deleted old input\n+new input\n';
    };
    const changed = readChanges({pull_request: {base: {sha: 'a'.repeat(40)}}}, git);
    assert.deepEqual(changed.paths, paths);
    assert.equal(pythonWheelAcceptanceRequired(selectTargets(changed.paths, {draft: true})), true);
  }
});

test('deep proof scheduling covers its complete snapshot and safety inputs without narrowing runtime', async () => {
  const {snapshotDirectories, snapshotFiles} = await import('../proofs/relation-pipeline/inventory.mjs');
  for (const path of [...snapshotFiles, ...snapshotDirectories.map(root => `${root}/new-input`),
    'adapters/store-local/new-owner.mjs', 'packages/sdk/resource-control.mjs',
    'proofs/ci-evidence/receipts.mjs', 'scripts/new-tool.mjs', 'unknown/config']) {
    assert.equal(deepProofRequired(selectTargets([path])), true, path);
  }
  for (const path of ['README.md', 'LICENSE', 'CONTRIBUTING.md']) {
    const selection = selectTargets([path], {event: 'push'});
    assert.equal(selection.profile, 'full'); assert.deepEqual(selection.targets, all);
    assert.equal(deepProofRequired(selection), false, path);
    assert.equal(gateJobRequired(selection, 'pipeline-validation'), true);
    assert.equal(gateJobRequired(selection, 'main-performance'), true);
  }
  for (const options of [{failure: 'unavailable'}, {event: 'schedule'}, {event: 'workflow_dispatch'}])
    assert.equal(deepProofRequired(selectTargets(['README.md'], options)), true);
  assert.equal(deepProofRequired(selectTargets([])), true);
});

test('unclassified adapter and package safety inputs retain deep campaigns', () => {
  const duckdbWitness = 'adapters/connectors/duckdb/node/test/standard-host.test.mjs';
  const nest = JSON.parse(readFileSync(new URL('../proofs/bounded-session/nest-obligations.json', import.meta.url), 'utf8'));
  assert(nest.retainedSuites.includes(duckdbWitness), 'Use the actual retained Nest proof input');
  for (const path of [
    'adapters/host-node/infer-original-installation.mjs',
    'packages/python-sdk/src/actql_sdk/_local_core.py',
    'adapters/workers/wrangler.toml',
    'packages/sdk/tsconfig.json',
    duckdbWitness,
    'packages/sdk/format.mjs',
    'adapters/connectors/rest/format.test.mjs',
  ]) for (const event of ['pull_request', 'push']) {
    const selection = selectTargets([path], {event});
    assert.equal(selection.profile, 'full', path);
    assert.deepEqual(selection.targets, all, path);
    assert.equal(selection.macos, true, path);
    assert.equal(deepProofRequired(selection), true, `${event}/${path}`);
  }
});

test('unclassified safety changes require proof success while reviewed shallow changes require skips', () => {
  for (const event of ['pull_request', 'push']) for (const [path, deep] of [
    ['adapters/host-node/infer-original-installation.mjs', true],
    ['README.md', false],
  ]) {
    const selection = selectTargets([path], {event});
    const needs = results(selection);
    for (const name of ['session-evidence', 'pipeline-evidence']) needs[name].result = deep ? 'success' : 'skipped';
    const lines = verifyGate(plan(selection), needs, {...context, event});
    for (const name of ['session-evidence', 'pipeline-evidence']) {
      assert(lines.some(line => line.startsWith(`${deep ? 'PASS' : 'NOT APPLICABLE'} ${name}:`)));
      assert.throws(() => verifyGate(plan(selection), {...needs,
        [name]: {result: deep ? 'skipped' : 'success'}}, {...context, event}), undefined, `${event}/${path}/${name}`);
    }
    const scheduleNeeds = {'select-targets': {outputs: {profile: 'full', deep_proofs: String(deepProofRequired(selection))}}};
    for (const name of ['session-evidence', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants']) {
      assert.equal(scheduled(name, scheduleNeeds), deep, `${event}/${path}/${name}`);
    }
  }
});

test('shallow and deep aggregate expectations reject every wrong status, including cheap validation', () => {
  for (const event of ['pull_request', 'push', 'schedule', 'workflow_dispatch']) {
    for (const paths of [['README.md'], ['src/bounded_execution/session.mbt'], []]) {
      const selection = selectTargets(paths, {event});
      const env = {...context, event};
      assert.doesNotThrow(() => verifyGate(plan(selection), results(selection), env));
      for (const name of gateJobs) {
        const correct = gateJobRequired(selection, name) ? 'success' : 'skipped';
        for (const wrong of ['success', 'skipped', 'failure', 'cancelled', undefined].filter(value => value !== correct)) {
          const candidate = results(selection); candidate[name] = {result: wrong};
          assert.throws(() => verifyGate(plan(selection), candidate, env), undefined, `${event}/${name}/${wrong}`);
        }
      }
    }
  }
  const needs = Object.fromEntries(jobs['pipeline-evidence'].needs.map(name => [name, {result: 'skipped'}]));
  needs['pipeline-validation'].result = 'success';
  assert.equal(scheduled('pipeline-evidence', needs), false, 'cheap checks alone do not start deep assembly');
});

test('existing push-only health result is required by the same aggregate that schedules it', () => {
  assert(jobs.check.needs.includes('health-quick'));
  assert(gateJobs.includes('health-quick'));
  assert.equal(jobs['health-quick'].uses, './.github/workflows/health-monitor.yml');
  const runs = (event, ref = 'refs/heads/main', inputs = {}) => runInNewContext(
    jobs['health-quick'].if.slice(3, -3), {inputs, always: () => true, toJSON: JSON.stringify,
      github: {event_name: event, ref, event: {repository: {visibility: 'public', private: false}}}});
  for (const event of ['push', 'pull_request', 'schedule', 'workflow_dispatch']) {
    const selection = selectTargets(['README.md'], {event});
    const required = event === 'push';
    assert.equal(runs(event), required, event);
    assert.equal(gateJobRequired(selection, 'health-quick'), required, event);
    const env = {...context, event};
    verifyGate(plan(selection), results(selection), env);
    for (const result of required ? ['failure', 'cancelled', 'skipped', undefined] : ['success']) {
      assert.throws(() => verifyGate(plan(selection),
        {...results(selection), 'health-quick': {result}}, env), /health-quick/);
    }
  }
  assert.equal(runs('push', 'refs/heads/feature'), false);
  for (const mode of ['performance_matrix', 'packed_query_evidence_probe'])
    assert.equal(runs('push', 'refs/heads/main', {[mode]: true}), false);
});

test('push applicability reads only exact authenticated endpoints and keeps deleted/renamed paths', () => {
  const before = 'c'.repeat(40), payload = {ref: 'refs/heads/main', before, after: head};
  const calls = [];
  const git = args => { calls.push(args); return args[0] === 'rev-parse' ? head : 'src/deleted.mbt\0packages/sdk/renamed.mjs\0'; };
  assert.deepEqual(readPushChanges(payload, head, git).paths, ['src/deleted.mbt', 'packages/sdk/renamed.mjs']);
  assert.deepEqual(calls, [['rev-parse', 'HEAD'], ['diff', '--no-renames', '--name-only', '-z', before, head, '--']]);
  for (const patch of [{before: null}, {before: '0'.repeat(40)}, {before: 'bad'}, {after: before}, {ref: 'refs/heads/other'}])
    assert.throws(() => readPushChanges({...payload, ...patch}, head, git));
  assert.throws(() => readPushChanges(payload, head, args => args[0] === 'rev-parse' ? head : 'truncated'));
  assert.throws(() => readPushChanges(payload, head, () => { throw Error('missing base object'); }));
});

test('same-environment duplicate checks retain one explicit owner without weakening platform evidence', () => {
  const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert(pkg.scripts['check:retained-boundary'].includes('adapters/store-local/publication-commit-owner.test.mjs'));
  assert(!jobs.host.steps.some(step => step.run?.startsWith('node --test adapters/store-local/publication-commit-owner.test.mjs')));
  assert(pkg.scripts['check:distribution-client'].includes('scripts/owned-scratch.test.mjs'));
  const scratch = jobs.lint.steps.find(step => step.run === 'node --test scripts/owned-scratch.test.mjs');
  assert.equal(scratch.if, "${{ !startsWith(needs.select-targets.outputs.profile, 'draft') }}");
  assert.deepEqual(Object.entries(jobs).flatMap(([name, job]) =>
    job.steps?.filter(step => step.run?.split(/\s+/u).includes('scripts/owned-scratch.test.mjs'))
      .map(() => name) ?? []), ['lint'], 'normal scratch checks have one runtime-independent owner');
  assert(jobs.lint.steps.some(step => step.run === 'node --test scripts/dependency-isolation-scratch.test.mjs'));
  // Operation inventory remains fail-fast before fan-out: deleting that safety
  // admission is not justified merely because spec also checks the inventory.
  assert(jobs.preflight.steps.some(step => step.run === 'node --test scripts/pure-operation-inventory.test.mjs' && !step.if));
});
