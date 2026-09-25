import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { DuckDBInstance } from '@duckdb/node-api';
import { prepareExampleText, runExample } from '../examples/physical-strategy.mjs';
import { checked } from '../runtime-result.mjs';
import { runInstalledStrategy } from '../../../../host-common/strategy.mjs';
import { runtimeCore } from '../../../../host-common/runtime-core.mjs';
import { installStrategyContributions } from
  '../../../../connectors-builtin/strategy.generated.mjs';
import {
  accountEntry,
  fixtureAuthorization,
  sqliteDeferral,
} from '../../../../host-node/authorization-fixture.mjs';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
// The MoonBit start boundary's own refusal, found in the raised cause chain.
const activationRefused = cause => {
  for (let value = cause, depth = 0; value != null && depth < 8; value = value._0, depth++) {
    if (value.constructor?.name?.endsWith('RunIssue23ActivationNotAuthorized')) return true;
  }
  return false;
};
// The standard Host's default single in-process Site.
const SITE = 'in-process-default';

async function exampleInput(t) {
  const exec = promisify(execFile);
  for (const target of ['src/connectors/duckdb/host_node', 'src/connectors_builtin_node',
    'src/physical_strategy_example']) {
    await exec('moon', ['build', '--target', 'js', '--release', target], { cwd: root });
  }
  const catalogs = await readFile(join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const catalog = catalogs.slice(catalogs.indexOf('fn query_amount_nullable_catalog'))
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/);
  assert(catalog);
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'activation-authorization-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const database = join(directory, 'source.duckdb');
  const db = await DuckDBInstance.create(database);
  const connection = await db.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    await connection.run('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  } finally { connection.closeSync(); db.closeSync(); }
  const environment = join(directory, 'environment.json');
  const program = join(directory, 'program.json');
  const parameters = join(directory, 'parameters.json');
  await Promise.all([
    writeFile(environment, JSON.parse(catalog[1])),
    writeFile(program, await readFile(join(root,
      'adapters/connectors/duckdb/node/examples/program.json'), 'utf8')),
    writeFile(parameters, '{"minimum":1}'),
  ]);
  return { directory, database, environment, program, parameters,
    environmentCid: catalog[2], nativeMilliseconds: '5' };
}

// Account entries for this example Host: read the source (preparation
// capture and acquisition are both reads); the activation entry decides
// protected-Site compute activation, a write of captured inputs to that Site.
const entries = (input, activation) => [
  accountEntry('example-source', 'allow', {
    connection: input.database, resource: 'main.records', operation: 'read',
  }),
  ...(activation === undefined ? [] : [accountEntry('site-compute', activation, {
    connection: SITE, operation: 'write',
  })]),
];

async function run(input, gate) {
  const result = await runExample({ ...input, authorization: gate });
  const report = result.report;
  const usage = result.execution.usage();
  await result.close();
  return { report, usage };
}

test('covered in-process compute activates every task with no Host call or extra pass', async t => {
  const input = await exampleInput(t);
  let hostCalls = 0;
  const gate = await fixtureAuthorization(entries(input), {
    decide: () => { hostCalls++; }, answeringAuthorities: ['reviewer'],
  });
  const { report } = await run(input, gate);
  assert.equal(report.status, 'host-tasks-completed');
  assert.equal(report.completed.length, 3);
  const counts = gate.counters();
  // Preparation + Acquisition are the only evaluations; the three activations
  // are covered by a local check with no evaluation and no Host call.
  assert.equal(counts.evaluations, 2);
  assert.equal(counts.coveredOperations, 3);
  assert.equal(counts.hostDecisionCalls, 0);
  assert.equal(counts.checkpointsPersisted, 0);
  assert.equal(hostCalls, 0);
});

test('protected Site activation: allow and delegate permit dispatch under the MoonBit grant', async t => {
  const input = await exampleInput(t);
  const allow = await fixtureAuthorization(entries(input, 'allow'), {
    protectedSites: [SITE],
  });
  const allowed = await run(input, allow);
  assert.equal(allowed.report.status, 'host-tasks-completed');
  assert.equal(allowed.report.completed.length, 3);
  assert.equal(allow.counters().hostDecisionCalls, 0);
  assert.equal(allow.counters().checkpointsPersisted, 0);

  const seen = [];
  const delegate = await fixtureAuthorization(entries(input, 'delegate'), {
    protectedSites: [SITE],
    decide: view => {
      seen.push(view.tuple.resource);
      return { decision: 'permit', subject: view.subject, authority: 'reviewer' };
    },
    answeringAuthorities: ['reviewer'],
  });
  const permitted = await run(input, delegate);
  assert.equal(permitted.report.status, 'host-tasks-completed');
  assert.equal(permitted.report.completed.length, 3);
  // One Host decision per exact (Site, realization) scope in this Run; later
  // activations of the same scope reuse it.
  assert.deepEqual([...new Set(seen)].sort(), seen.slice().sort());
  assert.equal(delegate.counters().hostDecisionCalls, seen.length);
  assert(seen.length < 3);
  assert.equal(delegate.counters().reusedDecisions, 3 - seen.length);
});

test('protected Site activation refusals start no task and keep prior facts', async t => {
  const input = await exampleInput(t);
  const deferral = await sqliteDeferral(join(input.directory, 'journal'));
  t.after(() => deferral.journal.close());
  const permit = view => ({ decision: 'permit', subject: view.subject, authority: 'reviewer' });
  const cases = [
    ['explicit deny', entries(input, 'deny'), {}, 'ExecutionAuthorizationDenied'],
    ['no-match deny', entries(input), {}, 'ExecutionAuthorizationDenied'],
    ['reject', entries(input, 'delegate'), {
      decide: view => ({ decision: 'reject', subject: view.subject, authority: 'reviewer' }),
    }, 'ExecutionAuthorizationDenied'],
    ['throw', entries(input, 'delegate'), {
      decide: () => { throw new Error('DecisionServiceDown'); },
    }, 'ExecutionAuthorizationDecisionFailed'],
    ['wrong authority', entries(input, 'delegate'), {
      decide: view => ({ ...permit(view), authority: 'mallory' }),
    }, 'ExecutionAuthorizationDecisionFailed'],
    ['defer with journal', entries(input, 'delegate'), {
      decide: view => ({ decision: 'defer', subject: view.subject }), deferral,
    }, 'ExecutionAuthorizationWaiting'],
    ['defer without journal', entries(input, 'delegate'), {
      decide: view => ({ decision: 'defer', subject: view.subject }),
    }, 'ExecutionAuthorizationDeferralUnsupported'],
  ];
  const baseline = await run(input, await fixtureAuthorization(entries(input)));
  for (const [label, configured, options, code] of cases) {
    let hostCalls = 0;
    const decide = options.decide === undefined ? undefined
      : view => { hostCalls++; return options.decide(view); };
    const gate = await fixtureAuthorization(configured, {
      ...options, decide, answeringAuthorities: ['reviewer'], protectedSites: [SITE],
    });
    const { report, usage } = await run(input, gate);
    assert.equal(report.status, 'host-tasks-failed', label);
    assert.equal(report.failure, code, label);
    assert.equal(report.completed.length, 0, label);
    // The acquisition already happened and keeps its evidence; no task
    // reserved or started beyond it.
    assert.equal(report.acquisition_evidence.receipts.length, 2, label);
    assert(usage.attempts < baseline.usage.attempts, label);
    assert.equal(hostCalls, decide === undefined ? 0 : 1, label);
    assert.equal(gate.counters().coveredOperations, 0, label);
    if (label === 'defer with journal') {
      assert.equal(gate.counters().checkpointsPersisted, 1);
      assert.equal(deferral.journal.listPending().length, 1);
    }
    if (label === 'reject') assert.equal(gate.counters().hostRejections, 1);
    if (label === 'throw' || label === 'wrong authority') {
      assert.equal(gate.counters().decisionFailures, 1);
      assert.equal(gate.counters().hostRejections, 0);
    }
  }
});

test('the captured Run refuses every realization start that the Host did not grant', async t => {
  const input = await exampleInput(t);
  const moon = await import(new URL('_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
    `file://${root}/`).href);
  const [programText, environmentText, parameterText, adoptedText, query, evidence, receipts] =
    await Promise.all([input.program, input.environment, input.parameters,
      join(root, 'adapters/connectors/duckdb/node/contracts/adopted-relation.json'),
      join(root, 'spec/contracts/actql-query-acquisition.json'),
      join(root, 'spec/contracts/actql-query-process-evidence.json'),
      join(root, 'spec/contracts/actql-query-two-receipt.json')].map(path => readFile(path, 'utf8')));
  // DuckDB-only, Local-only and mixed realizations.
  for (const nativeMilliseconds of ['1', '20', '5']) {
    const plan = await prepareExampleText({ database: input.database,
      environmentCid: input.environmentCid, programText, environmentText, parameterText,
      adoptedText, query, evidence, receipts, nativeMilliseconds });
    const opened = await plan.open();
    try {
      assert.equal(moon.strategyHostConfigureManagedIdentity(opened.setup, true, false, false, false), true);
      const installed = await installStrategyContributions(moon, opened.setup, checked,
        opened.configurations);
      let starts = 0;
      // A Host loop that claims coverage without installing the MoonBit grant.
      const core = { ...runtimeCore(moon), coverActivation: () => { starts++; return true; } };
      const result = await runInstalledStrategy(opened.setup, core, installed);
      assert.equal(result.status, 'host-tasks-failed', nativeMilliseconds);
      assert(activationRefused(result.failure?.cause), nativeMilliseconds);
      assert.equal(result.completed.length, 0, nativeMilliseconds);
      assert.equal(starts, 1, nativeMilliseconds);
      assert.equal(moon.strategyHostTaskCompleted(opened.setup, 1), false);
      await result.close();
    } finally { await opened.close(); }
  }
});

test('preparation is authorized before any Program path read or source access', async t => {
  const input = await exampleInput(t);
  let hostCalls = 0;
  // The account reads another table only: the source tuple is a no-match.
  const gate = await fixtureAuthorization([accountEntry('other-table', 'allow', {
    connection: input.database, resource: 'main.other', operation: 'read',
  })], { decide: () => { hostCalls++; }, answeringAuthorities: ['reviewer'] });
  await assert.rejects(runExample({ ...input, program: join(input.directory, 'absent.json'),
    authorization: gate }), error => error.code === 'ExecutionAuthorizationDenied' &&
    error.authorization.boundary === 'preparation' &&
    error.authorization.reason === 'no_match');
  assert.equal(hostCalls, 0);
  assert.equal(gate.counters().evaluations, 1);
});
