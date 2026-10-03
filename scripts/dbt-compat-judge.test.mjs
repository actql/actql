import {compatibilityReport, expectedObservations, packageIdentity,
  textIdentity} from './fixtures/dbt-compat-judge.mjs';
import {spawnSync} from 'node:child_process';
import {cp, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

import assert from 'node:assert/strict';
import test from 'node:test';
import {judge, probeStatus, sameRows} from
  './fixtures/dbt-compat-judge.mjs';

const columns = [
  {name: 'id', contract: {type: 'number', nullable: false}},
  {name: 'amount', contract: {type: 'number', nullable: true}},
];
const rows = [{id: 3, amount: 30}, {id: 3, amount: 30}, {id: 5, amount: null}];
const named = (all, extra = {}) => ({stage: 'named-result', all,
  streamed: all, streamState: 'complete', columns, ...extra});
const refused = {stage: 'actql-submission-refused',
  code: 'ClientProgramInvalidInput'};
const runFailed = {stage: 'actql-run-failed', state: {status: 'failed'}};
const observe = {expect: 'observe'};
const control = {expect: 'rows', rows, order: 'unordered'};

test('a submission refusal is a finding only for an observed case', () => {
  assert.equal(judge(observe, refused, columns).verdict, 'unsupported');
  assert.equal(judge(control, refused, columns).verdict, 'baseline-failed');
});

test('an admitted Run that fails is a failure whatever the case expects',
  () => {
    assert.equal(judge(observe, runFailed, columns).verdict, 'run-failed');
    assert.equal(judge(control, runFailed, columns).verdict, 'run-failed');
    for (const item of [observe, control]) {
      const outcome = {case: 'x', ...runFailed,
        ...judge(item, runFailed, columns)};
      assert.equal(probeStatus({outcomes: [outcome]}).status, 'failed');
    }
  });

test('a positive control checks rows, duplicates, schema and stream', () => {
  assert.equal(judge(control, named(rows), columns).verdict, 'passed');
  assert.equal(judge(control, named(rows.slice(1)), columns).verdict,
    'wrong-result');
  assert.equal(judge(control, named([...rows].reverse()), columns).verdict,
    'passed');
  assert.equal(judge({...control, order: 'listed'},
    named([...rows].reverse()), columns).verdict, 'wrong-result');
  assert.equal(judge(control, named(rows, {streamState: 'prefix'}),
    columns).verdict, 'wrong-result');
  assert.equal(judge(control, named(rows, {streamed: rows.slice(1)}),
    columns).verdict, 'wrong-result');
  assert.equal(judge(control, named(rows, {columns: [columns[0]]}),
    columns).verdict, 'wrong-result');
  assert.equal(judge({...control, columns: [columns[0]]},
    named(rows, {columns: [columns[0]]}), columns).verdict, 'passed');
  assert.equal(judge({expect: 'rows'}, named(rows), columns).verdict,
    'wrong-result');
});

test('the probe passes only without failures, compile problems or faults',
  () => {
    const passed = {case: 'a', verdict: 'passed'};
    const unsupported = {case: 'b', verdict: 'unsupported'};
    assert.equal(probeStatus({outcomes: [passed, unsupported]}).status,
      'passed');
    assert.equal(probeStatus({outcomes: [passed, {case: 'c'}]}).status,
      'failed');
    assert.equal(probeStatus({outcomes: [passed],
      compileProblems: [['project', {}]]}).status, 'failed');
    assert.equal(probeStatus({outcomes: [passed],
      fault: {message: 'x'}}).status, 'failed');
  });

test('row comparison keeps duplicate counts', () => {
  assert.equal(sameRows([{a: 1}, {a: 1}], [{a: 1}], 'unordered'), false);
  assert.equal(sameRows([{a: 1}, {a: 2}], [{a: 2}, {a: 1}], 'unordered'),
    true);
});

// Synthetic evidence exercises reporting only. Rows are authored here rather
// than copied from a runtime response or another SQL implementation.
const sql = 'SELECT id, amount FROM orders';
function evidenceFixture() {
  const source = {revision: 'a'.repeat(40), clean: true};
  const installed = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node']
    .map(name => ({name: `@actql/${name}`, version: '0.0.0-development',
      files: 2, contentsSha256: 'b'.repeat(64)}));
  return {
    specification: {source: {columns}, cases: [{name: 'orders',
      project: 'project', format: 'sql', expect: 'rows', order: 'unordered',
      rows: [{id: 2, amount: 20}]}]},
    compiled: {orders: sql},
    commands: ['versions', 'dbt-compile', 'install', 'acceptance'].map(
      (kind, index) => ({id: String(index), kind, project: 'project',
        status: 0, signal: null, error: null})),
    versions: {python: '3.13.11', 'dbt-core': '1.11.15',
      'dbt-duckdb': '1.11.0', 'dbt-adapters': '1.24.5',
      'dbt-common': '1.39.0', duckdb: '1.5.6'},
    source: {before: {...source}, after: {...source}},
    installed, packages: installed.map(item => ({...item,
      revision: source.revision, sha256: 'c'.repeat(64)})),
    compileChecks: {project: {connectionOpens: 0, duckdbFiles: [], userFile: false}},
    outcomes: ['local', 'http'].map(transport => ({case: 'orders', transport,
      entry: '@actql/node:client.aql', module: 'node_modules/@actql/node/index.mjs',
      format: 'sql', input: textIdentity(sql), stage: 'named-result',
      all: [{id: 2, amount: 20}], streamed: [{id: 2, amount: 20}],
      streamState: 'complete', columns, verdict: 'passed',
      assertions: {runSucceeded: true, expectedRows: true,
        expectedColumns: true, streamedRows: true, streamComplete: true}})),
  };
}


test('compile/query acceptance never implies dbt run, materialization or catalog updates', () => {
  const report = compatibilityReport(evidenceFixture());
  assert.equal(report.status, 'passed');
  assert.deepEqual(report.problems, []);
  assert.equal(report.scope.dbtCompile.status, 'tested');
  assert.equal(report.scope.dbtCompile.outcome, 'passed');
  assert.equal(report.scope.queryExecution.outcome, 'passed');
  for (const scope of ['dbtRun', 'materialization', 'catalogUpdates']) {
    assert.equal(report.scope[scope].status, 'not-attempted');
  }
});

for (const kind of ['versions', 'dbt-compile', 'install', 'acceptance']) {
  test(`reject missing, nonzero and missing-executable ${kind} evidence`, () => {
    for (const mutation of ['missing', 'exit', 'error', 'signal']) {
      const evidence = evidenceFixture();
      const command = evidence.commands.find(item => item.kind === kind);
      if (mutation === 'missing') evidence.commands.splice(
        evidence.commands.indexOf(command), 1);
      if (mutation === 'exit') command.status = 1;
      if (mutation === 'error') Object.assign(command, {status: null, error: 'ENOENT'});
      if (mutation === 'signal') Object.assign(command, {status: null, signal: 'SIGKILL'});
      const report = compatibilityReport(evidence);
      assert.equal(report.status, 'failed', mutation);
      assert.notEqual(report.scope.queryExecution.outcome, 'passed');
      if (['versions', 'dbt-compile'].includes(kind)) {
        assert.notEqual(report.scope.dbtCompile.outcome, 'passed');
      }
    }
  });
}

test('reject empty, partial, duplicate and unexpected observations', () => {
  assert.equal(probeStatus({outcomes: []}).status, 'failed');
  for (const count of [0, 1, 3]) {
    const evidence = evidenceFixture();
    evidence.outcomes = count === 3 ? [...evidence.outcomes, evidence.outcomes[0]]
      : evidence.outcomes.slice(0, count);
    const report = compatibilityReport(evidence);
    assert.equal(report.status, 'failed');
    assert.notEqual(report.scope.queryExecution.outcome, 'passed');
  }
  const evidence = evidenceFixture();
  evidence.outcomes[0].case = 'not-in-probe';
  const report = compatibilityReport(evidence);
  assert.equal(report.status, 'failed');
  assert.notEqual(report.scope.queryExecution.outcome, 'passed');
});

test('reject rewritten SQL, wrong format, missing entry and stale package identity', () => {
  for (const alter of [
    item => { item.outcomes[0].input = textIdentity(`${sql}\n`); },
    item => { item.outcomes[0].input.bytes += 1; },
    item => { item.outcomes[0].format = 'aql-text'; },
    item => { delete item.outcomes[0].entry; },
    item => { item.outcomes[0].module = '../checkout/packages/node/index.mjs'; },
    item => { item.source.after.revision = 'd'.repeat(40); },
    item => { item.source.before.clean = false; },
    item => { item.packages[0].revision = 'd'.repeat(40); },
    item => { item.installed[0].version = 'old'; },
    item => { item.installed[0].contentsSha256 = 'd'.repeat(64); },
    item => { item.installed.pop(); },
    item => { delete item.versions['dbt-core']; },
  ]) {
    const evidence = evidenceFixture();
    alter(evidence);
    const report = compatibilityReport(evidence);
    assert.equal(report.status, 'failed');
    assert.notEqual(report.scope.queryExecution.outcome, 'passed');
  }
});

test('report rejudges independent expectations instead of trusting claimed verdicts', () => {
  for (const alter of [
    item => { item.outcomes[0].all[0].amount = 999; },
    item => { item.outcomes[0].assertions = {}; },
    item => { item.outcomes[0].streamState = 'prefix'; },
    item => { item.outcomes[0].columns = []; },
    item => { item.outcomes[0].verdict = 'invented-success'; },
  ]) {
    const evidence = evidenceFixture();
    alter(evidence);
    const report = compatibilityReport(evidence);
    assert.equal(report.status, 'failed');
    assert.notEqual(report.scope.queryExecution.outcome, 'passed');
  }
});

test('a witnessed unsupported query is scoped to its case and transport', () => {
  const evidence = evidenceFixture();
  evidence.specification.cases[0].expect = 'observe';
  evidence.outcomes = evidence.outcomes.map(item => ({...item, ...refused,
    ...judge(observe, refused, columns)}));
  const report = compatibilityReport(evidence);
  assert.equal(report.status, 'passed');
  assert.deepEqual(report.scope.queryExecution.unsupported, ['local', 'http']
    .map(transport => ({case: 'orders', transport, code: 'ClientProgramInvalidInput'})));
  assert.equal(report.scope.materialization.status, 'not-attempted');
});

test('all expected variants retain independently authored rows and input identity', () => {
  const fixture = evidenceFixture();
  fixture.specification.cases[0].program = 'programs/a.json';
  fixture.specification.cases[0].emptySource = true;
  fixture.specification.reproductions = [{name: 'control', text: 'FROM orders',
    format: 'aql-text', expect: 'rows', rows: []}];
  const expected = expectedObservations(fixture.specification, fixture.compiled,
    {'programs/a.json': '{"query":"orders"}'});
  assert.deepEqual(expected.map(item => item.kind), ['dbt-compiled',
    'json-comparison', 'dbt-compiled-empty-source', 'handwritten']);
  assert.deepEqual(expected[1].item.rows, [{id: 2, amount: 20}]);
  assert.deepEqual(expected[2].item.rows, []);
  assert.notDeepEqual(expected[1].input, expected[0].input);
});

test('package identity covers installed code bytes, not just unchanged package.json', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'dbt-package-'));
  try {
    await writeFile(join(directory, 'package.json'), '{"name":"@actql/node","version":"same"}');
    await writeFile(join(directory, 'index.mjs'), 'export const answer = 1;');
    const before = await packageIdentity(directory);
    await writeFile(join(directory, 'index.mjs'), 'export const answer = 2;');
    const after = await packageIdentity(directory);
    assert.equal(before.version, after.version);
    assert.notEqual(before.contentsSha256, after.contentsSha256);
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test('missing Python retains a failed machine-readable report and raw exit evidence', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'dbt-report-'));
  const repository = fileURLToPath(new URL('../', import.meta.url));
  try {
    for (const file of ['scripts/probe-dbt-compat.mjs', 'scripts/owned-scratch.mjs',
      'scripts/packed-client-packages.mjs', 'scripts/fixtures/dbt-compat-judge.mjs',
      'probes/dbt-compat/cases.json', 'probes/dbt-compat/requirements.txt']) {
      const destination = join(directory, file);
      await mkdir(join(destination, '..'), {recursive: true});
      await cp(join(repository, file), destination);
    }
    await cp(join(repository, 'probes/dbt-compat/programs'),
      join(directory, 'probes/dbt-compat/programs'), {recursive: true});
    for (const args of [['init', '-q'], ['add', '.'], ['-c', 'user.name=Probe fixture',
      '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture']]) {
      assert.equal(spawnSync('git', args, {cwd: directory}).status, 0);
    }
    const run = spawnSync(process.execPath, ['scripts/probe-dbt-compat.mjs'],
      {cwd: directory, encoding: 'utf8', env: {...process.env,
        ACTQL_PROBE_PYTHON: join(directory, 'missing-python')}, timeout: 30_000});
    assert.equal(run.status, 1, run.stderr);
    const path = run.stdout.match(/dbt compatibility probe evidence: (.+)/u)[1];
    const report = JSON.parse(await readFile(join(path, 'summary.json'), 'utf8'));
    assert.equal(report.status, 'failed');
    assert.equal(report.scope.dbtCompile.status, 'not-attempted');
    assert.equal(report.scope.queryExecution.status, 'not-attempted');
    assert.equal(report.commands[0].status, null);
    assert.equal(report.commands[0].error, 'ENOENT');
    assert.match(report.fault.message, /missing-python/u);
    assert.deepEqual(report.outcomes, []);
    assert.equal(await readFile(join(path, '001.stdout.log'), 'utf8'), '');
  } finally { await rm(directory, {recursive: true, force: true}); }
});


test('successful compile process is distinct from failed compile assertions', () => {
  const evidence = evidenceFixture();
  evidence.compileChecks.project.connectionOpens = 1;
  const report = compatibilityReport(evidence);
  assert.equal(report.status, 'failed');
  assert.equal(report.scope.dbtCompile.commandOutcome, 'passed');
  assert.equal(report.scope.dbtCompile.outcome, 'failed');
  assert.equal(report.scope.queryExecution.outcome, 'failed');
});
