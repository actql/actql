import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {stringify} from 'yaml';
import {parseCommands, inventory, compareActions, formatReport} from './verification-actions.mjs';

const script = fileURLToPath(new URL('./verification-actions.mjs', import.meta.url));
const job = (run, extra = {}) => ({'runs-on': 'ubuntu-24.04', steps: [{name: 'Check', run}], ...extra});
const build = (jobs, scripts = {}, extra = {}) => inventory({
  workflowText: stringify(JSON.parse(JSON.stringify({name: 'Fixture', jobs}))), packageText: JSON.stringify({scripts}, null, 2), ...extra,
});
const pair = report => compareActions(report.actions[0], report.actions[1]);

test('literal quoting and whitespace normalize argv without executing shell', () => {
  assert.deepEqual(parseCommands(" node 'scripts/check.mjs'  --case \"a b\" &&\nnode check.mjs\n").commands,
    [{argv: ['node', 'scripts/check.mjs', '--case', 'a b'], after: 'start', line: 1},
      {argv: ['node', 'check.mjs'], after: '&&', line: 2}]);
  assert.deepEqual(parseCommands("node check.mjs '$TOKEN'").commands[0].argv,
    ['node', 'check.mjs', '$TOKEN']);
  assert.deepEqual(parseCommands('node scripts/check.mjs \\\n --flag').commands[0].argv,
    ['node', 'scripts/check.mjs', '--flag']);
});

test('equal independently authored declarations are candidates, never proven equivalent or reusable', () => {
  const report = build({first: job('node scripts/check.mjs'), second: job("node 'scripts/check.mjs'")});
  const result = pair(report);
  assert.equal(result.invocationEquality, 'proven');
  assert.equal(result.equivalence, 'suspected');
  assert.equal(result.eligibleForReuse, false);
  assert.equal(report.actionIdentity.status, 'unavailable');
  assert.equal(report.eligibleForReuse, false);
  assert(!JSON.stringify(report).includes('actionKey'));
});

for (const [name, left, right, dimension] of [
  ['different inputs', 'node --test scripts/a.test.mjs scripts/left.test.mjs',
    'node --test scripts/a.test.mjs scripts/right.test.mjs', 'selectors'],
  ['different targets', 'moon check --target js src/foo', 'moon check --target wasm src/foo', 'target'],
  ['different flags', 'moon test --target js --deny-warn src/foo', 'moon test --target js src/foo', 'flags'],
  ['different failure-injection state', 'FAULT=before node scripts/check.mjs',
    'FAULT=after node scripts/check.mjs', 'environment'],
  ['different input order', 'node --test a.test.mjs b.test.mjs', 'node --test b.test.mjs a.test.mjs', 'argv'],
]) test(name, () => {
  const result = pair(build({left: job(left), right: job(right)}));
  assert.equal(result.equivalence, 'different');
  assert(result.differences.includes(dimension));
});

test('compiler setup, runner and working directory differences are retained', () => {
  const first = job('node scripts/check.mjs');
  first.steps.unshift({uses: 'actions/setup-node@aaa', with: {'node-version': '22'}});
  const second = job('node scripts/check.mjs');
  second.steps.unshift({uses: 'actions/setup-node@bbb', with: {'node-version': '24'}});
  assert(pair(build({first, second})).differences.includes('compiler'));
  const cwd = job('node scripts/check.mjs', {defaults: {run: {'working-directory': 'other'}}});
  assert(pair(build({first: job('node scripts/check.mjs'), cwd})).differences.includes('workingDirectory'));
  assert(pair(build({first: job('node scripts/check.mjs'), second: job('node scripts/check.mjs',
    {'runs-on': 'macos-14'})})).differences.includes('compiler'));
});

test('declared purpose, conditions and prior mutation/restoration prevent equivalence claims', () => {
  const report = build({proofs: {'runs-on': 'ubuntu-24.04', steps: [
    {name: 'Verify', run: 'node proofs/run.mjs all'},
    {name: 'Mutate', run: 'node proofs/mutations.mjs'},
    {name: 'Verify', run: 'node proofs/run.mjs all'},
  ]}});
  assert.equal(compareActions(report.actions[0], report.actions[2]).equivalence, 'unknown');
  const first = job('node scripts/check.mjs'), second = job('node scripts/check.mjs');
  second.steps[0].name = 'Restore after fault';
  assert.equal(pair(build({first, second})).equivalence, 'unknown');
  second.steps[0].name = 'Check'; second.steps[0].if = 'failure()';
  assert.equal(pair(build({first, second})).equivalence, 'unknown');
});

for (const source of [
  'node check.mjs "$INPUT"', 'node check.mjs $(cat input)', 'node check.mjs `cat input`',
  'node --test scripts/*.test.mjs', 'node check.mjs | tee output', 'node check.mjs > output',
  'for fault in before after; do node check.mjs "$fault"; done',
  'if true; then node check.mjs; fi', 'cd alternate\nnode check.mjs',
  'export FAULT=before\nnode check.mjs', 'node check.mjs; node other.mjs',
  'node check.mjs &&', 'node "unterminated', 'node check.mjs &',
]) test(`opaque shell refuses entire block: ${source}`, () => {
  const parsed = parseCommands(source);
  assert.equal(parsed.commands.length, 0);
  assert(parsed.reason);
  const report = build({a: job(source), b: job(source)});
  assert.equal(pair(report).equivalence, 'unknown');
});

test('empty blocks and comments do not invent verification', () => {
  assert.deepEqual(parseCommands('# comment\n\n').commands, []);
  assert.equal(build({a: job('# comment')}).actions.length, 0);
});

test('literal matrices expand separately, while dynamic/include matrices stay unknown', () => {
  const report = build({core: job('moon check --target "${{ matrix.target }}"',
    {strategy: {matrix: {target: ['js', 'wasm']}}})});
  assert.deepEqual(report.actions.map(item => item.invocation.target), ['js', 'wasm']);
  assert.equal(pair(report).equivalence, 'different');
  const fixedCommand = build({core: job('node --test fixed.test.mjs',
    {strategy: {matrix: {target: ['js', 'wasm']}}})});
  assert(pair(fixedCommand).differences.includes('matrix'));
  for (const matrix of ['${{ fromJSON(needs.plan.outputs.matrix) }}', {include: [{target: 'js'}]},
    {target: ['$(touch marker)']}]) {
    const candidate = build({core: job('node check.mjs', {strategy: {matrix}})});
    assert(candidate.actions[0].unresolved.length);
    assert.equal(compareActions(candidate.actions[0], candidate.actions[0]).eligibleForReuse, false);
  }
});

test('dynamic environment, shell and runner configuration remain unknown', () => {
  for (const extra of [{env: {FAULT: '${{ inputs.fault }}'}}, {'runs-on': '${{ inputs.runner }}'},
    {defaults: {run: {shell: 'pwsh'}}}]) {
    assert.equal(pair(build({a: job('node check.mjs', extra), b: job('node check.mjs', extra)})).equivalence, 'unknown');
  }
});

test('npm expansion includes pre/post hooks and preserves exact source chains and independent invocations', () => {
  const report = build({a: job('npm run check:one'), b: job('node check.mjs')}, {
    'precheck:one': 'node prepare.mjs', 'check:one': 'node check.mjs && node audit.mjs',
    'postcheck:one': 'node cleanup.mjs',
  });
  assert.deepEqual(report.actions.slice(0, 4).map(item => item.invocation.argv[1]),
    ['prepare.mjs', 'check.mjs', 'audit.mjs', 'cleanup.mjs']);
  assert.equal(report.actions[1].source[0].path, '.github/workflows/ci.yml');
  assert.equal(report.actions[1].source[1].definition, 'scripts.check:one');
  assert.equal(compareActions(report.actions[1], report.actions[4]).equivalence, 'unknown');
  assert.equal(report.actions.filter(item => item.origin === 'local-definition').length, 4);
});

test('npm cycles, missing scripts, prefix/dynamic calls are opaque; compiler objects do not alias', () => {
  const report = build({a: job('npm run check:a')}, {'check:a': 'npm run check:b', 'check:b': 'npm run check:a'});
  assert(report.actions.every(item => item.unresolved.length));
  for (const command of ['npm run missing', 'npm run check:a --prefix other', 'npm run "$SCRIPT"']) {
    assert(build({a: job(command)}).actions[0].unresolved.length);
  }
  const mixed = build({a: job('npm run check:one')}, {'check:one': 'node a.mjs && moon check --target js'});
  assert.deepEqual(mixed.actions.map(item => item.compiler.requestedExecutable), ['node', 'moon', 'node', 'moon']);
});

test('new Client group names require no hardcoded job registry and uses/reusable jobs remain opaque', () => {
  const report = build({
    'client-distribution': job('node scripts/check.mjs'), 'client-packed': job('node scripts/packed.mjs'),
    'client-salesforce': job('node scripts/salesforce.mjs'),
    reusable: {uses: './.github/workflows/another.yml'},
  });
  assert.deepEqual(report.actions.map(item => item.job), ['client-distribution', 'client-packed', 'client-salesforce']);
  assert.equal(report.omissions[0].reason, 'Reusable or unsupported job is opaque');
});

test('source locations, local runner limits and report interpretation are explicit', () => {
  const report = inventory({workflowText: 'jobs:\n  one:\n    runs-on: ubuntu-24.04\n    steps:\n      - name: Check\n        run: node check.mjs\n',
    packageText: '{"scripts":{}}', localRunnerText: "// .github/workflows/ci.yml\nthrow new Error('do not run')"});
  assert.equal(report.actions[0].source[0].line, 5);
  assert.deepEqual(report.localRunner.workflowReferenceLines, [1]);
  assert.equal(report.localRunner.status, 'unknown');
  assert.match(formatReport(report), /No equivalence proven/);
});

test('malformed YAML, duplicate keys, aliases and oversized matrices fail closed or remain unknown', () => {
  for (const workflowText of ['jobs: [', 'jobs: {}\njobs: {}', 'jobs: &jobs {}\nalias: *jobs']) {
    assert.throws(() => inventory({workflowText, packageText: '{"scripts":{}}'}));
  }
  const report = build({core: job('node check.mjs', {strategy: {matrix: {target: Array(65).fill('js')}}})});
  assert.match(report.actions[0].unresolved.join(' '), /64/);
});

test('CLI reads only explicit sources; no command/JavaScript execution or inherited secret serialization', () => {
  const root = mkdtempSync(join(tmpdir(), 'verification-actions-'));
  try {
    mkdirSync(join(root, '.github/workflows'), {recursive: true});
    mkdirSync(join(root, 'scripts'));
    writeFileSync(join(root, '.github/workflows/ci.yml'), stringify({jobs: {
      a: job('node -e "require(\'fs\').writeFileSync(\'marker\', \'bad\')"'),
    }}));
    writeFileSync(join(root, 'package.json'), '{"scripts": {"check:one": "touch marker"}}');
    writeFileSync(join(root, 'toolchain.json'), '{}');
    writeFileSync(join(root, 'scripts/local-checks.mjs'), 'throw new Error("must not import")');
    const child = spawnSync(process.execPath, [script, '--root', root, '--json'], {
      cwd: root, encoding: 'utf8', env: {...process.env, PRIVATE_TEST_SECRET: 'do-not-serialize-this'},
    });
    assert.equal(child.status, 0, child.stderr);
    assert.equal(JSON.parse(child.stdout).summary.occurrences, 2);
    assert(!child.stdout.includes('do-not-serialize-this'));
    assert.throws(() => readFileSync(join(root, 'marker')));
    assert.equal(spawnSync(process.execPath, [script, '--run'], {encoding: 'utf8'}).status, 1);
    rmSync(join(root, 'toolchain.json'));
    symlinkSync(join(root, 'package.json'), join(root, 'toolchain.json'));
    assert.equal(spawnSync(process.execPath, [script, '--root', root], {encoding: 'utf8'}).status, 1);
  } finally { rmSync(root, {recursive: true, force: true}); }
});

test('intra-block setup/reset predecessors distinguish otherwise identical test declarations', () => {
  const report = build({a: job('node setup.mjs\nnode --test a.mjs\nnode reset.mjs\nnode --test a.mjs')});
  const result = compareActions(report.actions[1], report.actions[3]);
  assert.equal(result.invocationEquality, 'proven');
  assert.equal(result.equivalence, 'unknown');
  assert.deepEqual(report.actions[3].state.priorCommands.map(item => item.occurrence),
    ['action-1', 'action-2', 'action-3']);
});

test('nested npm lifecycle state includes pre, main, post and caller effects in order', () => {
  const report = build({a: job('npm run check:one\nnode after.mjs')}, {
    'precheck:one': 'node mutate.mjs', 'check:one': 'npm run check:inner',
    'postcheck:one': 'node restore.mjs', 'check:inner': 'node check.mjs',
  });
  assert.deepEqual(report.actions.slice(0, 4).map(item => item.invocation.argv[1]),
    ['mutate.mjs', 'check.mjs', 'restore.mjs', 'after.mjs']);
  assert.deepEqual(report.actions[1].state.priorCommands.map(item => item.occurrence), ['action-1']);
  assert.deepEqual(report.actions[3].state.priorCommands.map(item => item.occurrence),
    ['action-1', 'action-2', 'action-3']);
});

test('human output escapes controls and preserves raw JSON strings', () => {
  const label = 'untrusted\x1b[2J\nforged';
  const report = build({[label]: job("node 'check\x1b.mjs'"), b: job("node 'check\x1b.mjs'")});
  assert.equal(report.actions[0].job, label);
  assert(!formatReport(report).includes('\x1b'));
  assert(formatReport(report).includes('\\u001b'));
  assert(formatReport(report).includes('\\u000a'));
});

test('package source locations support whitespace and avoid matching unrelated repeated keys', () => {
  const packageText = '{\n  "unrelated": {"check:one": "wrong"},\n  "scripts" : {\n    "check:one"   : "node check.mjs"\n  }\n}';
  const report = build({a: job('npm run check:one')}, {}, {packageText});
  assert.equal(report.actions[0].source[1].line, 4);
  assert.equal(report.actions[0].source[1].definition, 'scripts.check:one');
});

test('workflow expressions remain dynamic even inside single shell quotes', () => {
  const report = build({a: job("node check.mjs '${{ inputs.fault }}'"),
    b: job("node check.mjs '${{ inputs.fault }}'")});
  assert.equal(pair(report).equivalence, 'unknown');
  assert(report.actions[0].unresolved.includes('Unresolved workflow expression'));
});

test('literal environment names that match object prototypes are retained and compared', () => {
  const report = build({a: job('__proto__=before constructor=first node check.mjs'),
    b: job('__proto__=after constructor=second node check.mjs')});
  assert.deepEqual(report.actions.map(action => action.environment.__proto__), ['before', 'after']);
  assert.deepEqual(report.actions.map(action => action.environment.constructor), ['first', 'second']);
  assert.equal(pair(report).invocationEquality, 'proven');
  assert.equal(pair(report).equivalence, 'different');
  assert(pair(report).differences.includes('environment'));
});
