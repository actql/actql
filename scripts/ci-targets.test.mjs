import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, rmSync, writeFileSync, chmodSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {parse} from 'yaml';
import {readChanges, selectTargets, validateSelection, verifyGate, maintenanceFiles, gateJobs} from './ci-targets.mjs';
import {occurrences} from './check-owned-contract-versions.mjs';
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
  for (const path of ['README.md', 'src/source_span/span.mbt', 'scripts/worktree-inventory.mjs']) {
    const result = validateSelection(selectTargets([path]));
    assert.deepEqual(result.targets, ['js'], path); assert.equal(result.macos, false, path);
    assert.match(result.reason, /full targets and macOS selected on main/u);
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
test('push+PR duplication is removed without workflow-level path filtering', () => {
  assert.deepEqual(workflow.on.push.branches, ['main']);
  assert(Object.hasOwn(workflow.on, 'pull_request'));
  assert.equal(workflow.on.pull_request, null);
  assert.equal(workflow.on.push.paths, undefined);
  assert.equal(workflow.on.push['paths-ignore'], undefined);
  assert.equal(workflow.concurrency['cancel-in-progress'], '${{ !inputs.performance_matrix }}');
});
test('whole-family scheduling retains the core matrix and complete selected proof campaigns', () => {
  assert.deepEqual(jobs.core.needs, ['select-targets']);
  assert.equal(jobs.core.strategy['fail-fast'], false);
  assert.equal(jobs.core.strategy.matrix.target, '${{ fromJSON(needs.select-targets.outputs.targets) }}');
  assert.deepEqual(jobs['native-macos'].needs, ['select-targets']);
  assert.match(jobs['native-macos'].if, /needs\.select-targets\.outputs\.macos == 'true'/u);
  for (const name of ['session-evidence', 'pipeline-mutations', 'pipeline-capacity']) {
    assert.match(jobs[name].if, /needs\.select-targets\.outputs\.profile == 'full'/u);
    assert.deepEqual(jobs[name].needs, ['select-targets']);
  }
  assert.deepEqual(jobs['pipeline-evidence'].needs, ['pipeline-mutations', 'pipeline-capacity']);
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
  ['select-targets', 'lint', 'spec'].includes(name) || selection.profile === 'full' &&
    (name !== 'native-macos' || selection.macos) ? 'success' : 'skipped'}]));
const changes = paths => paths.map(path => ({path, before: {mode: '100644', object: 'c'.repeat(40)},
  after: {mode: '100644', object: 'd'.repeat(40)}}));
const maintenanceSelection = paths => selectTargets(paths, {maintenanceChanges: changes(paths)});

test('required aggregate rejects failed, cancelled, skipped and missing selected jobs', () => {
  const selection = selectTargets(['src/unregistered/engine.mbt']);
  assert.equal(verifyGate(plan(selection), results(selection), context).length, gateJobs.length);
  for (const name of gateJobs) {
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
    'scripts/ci-review.config.json', 'scripts/new-reporter.mjs']) {
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
  return Function('needs', 'inputs', 'always', `return (${expression});`)(needs, inputs, () => true);
};
test('aggregate workflow expressions run on mixed failures and skip only wholly unselected families', () => {
  for (const [name, groups] of [['client', ['client-packages', 'client-distribution', 'client-packed', 'client-salesforce']],
    ['pipeline-evidence', ['pipeline-mutations', 'pipeline-capacity']]]) {
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
  assert.equal(evidence.steps.find(step => step.name === 'Require successful producers and exact immutable artifact identities').env.PIPELINE_NEEDS,
    '${{ toJSON(needs) }}');
  assert.equal(evidence.steps.find(step => step.run === 'node proofs/relation-pipeline/ci-artifacts.mjs join').env.PIPELINE_NEEDS,
    '${{ toJSON(needs) }}');
});

test('every heavy primitive is selected as one complete job and lint/spec always retain their tests', () => {
  const heavy = ['core', 'host', 'client-packages', 'client-distribution', 'client-packed', 'client-salesforce',
    'native', 'session-evidence', 'pipeline-mutations', 'pipeline-capacity', 'native-macos',
    'native-separated-network', 'workers', 'connector-addition', 'duckdb-node'];
  for (const name of heavy) {
    assert(jobs[name].needs.includes('select-targets'));
    assert.equal(scheduled(name, {'select-targets': {outputs: {profile: 'maintenance', macos: 'false'}}}), false);
    assert.equal(scheduled(name, {'select-targets': {outputs: {profile: 'full', macos: 'true'}}}), true);
    assert.equal(scheduled(name, {'select-targets': {outputs: {profile: '', macos: 'true'}}}), false);
  }
  assert.deepEqual(jobs.check.needs, gateJobs);
  for (const name of ['lint', 'spec']) assert.equal(jobs[name].needs, undefined);
  const lint = jobs.lint.steps.map(step => step.run ?? '');
  assert(lint.includes('node --test scripts/ci-evidence.test.mjs'));
  assert(lint.includes('node --test scripts/worktree-inventory.test.mjs'));
  const reporter = readFileSync(new URL('./ci-evidence.test.mjs', import.meta.url), 'utf8');
  for (const file of ['ci-artifact-reader.test.mjs', 'ci-artifacts.test.mjs', 'verification-actions.test.mjs']) {
    assert(reporter.includes(`import './${file}';`), `Missing retained reporter suite ${file}`);
  }
  assert(jobs.spec.steps.some(step => step.run?.includes('npm run check:spec')));
});

test('actual final gate command fails closed for missing or corrupted plans', () => {
  const selection = maintenanceSelection(['docs/development.md']);
  const script = jobs.check.steps.find(step => step.run).run;
  const run = value => spawnSync('bash', ['-eo', 'pipefail', '-c', script], {cwd: new URL('../', import.meta.url),
    encoding: 'utf8', env: {...process.env, CI_PLAN: value, RESULTS: JSON.stringify(results(selection)),
      GITHUB_SHA: head, GITHUB_EVENT_NAME: 'pull_request', GITHUB_STEP_SUMMARY: ''}});
  const good = run(JSON.stringify(plan(selection)));
  assert.equal(good.status, 0, good.stderr);
  assert.match(good.stdout, /NOT APPLICABLE pipeline-evidence/u);
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
