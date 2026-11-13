import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'yaml';
import {assertCurrentRevision, readRef, revisionToCheck} from './ci-preflight.mjs';
import {gateJobs, selectTargets, verifyGate} from './ci-targets.mjs';

const head = 'a'.repeat(40), merge = 'b'.repeat(40), newer = 'c'.repeat(40);
const env = {GITHUB_SHA: merge, GITHUB_REPOSITORY: 'actql/actql', GITHUB_EVENT_NAME: 'pull_request'};
const payload = {number: 123, pull_request: {head: {sha: head}}};
const {jobs, permissions} = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const commands = name => jobs[name].steps.filter(step => step.run).map(step => step.run);

test('PR admission compares current head with event head, not the synthetic tested merge', async () => {
  assert.deepEqual(revisionToCheck(env, payload), {ref: 'pull/123/head', expected: head});
  assert.deepEqual(await assertCurrentRevision(env, payload, async (repo, ref) => {
    assert.equal(repo, 'actql/actql'); assert.equal(ref, 'pull/123/head'); return head;
  }, {checkoutRevision: merge}), {ref: 'pull/123/head', revision: head});
  await assert.rejects(assertCurrentRevision(env, payload, async () => newer, {checkoutRevision: merge}), /superseded/u);
});
test('main-only advance does not invalidate an unchanged PR head', async () => {
  const calls = [];
  const result = await assertCurrentRevision(env,
    {...payload, pull_request: {...payload.pull_request, base: {sha: newer}}},
    async (repo, ref) => { calls.push(ref); return head; }, {checkoutRevision: merge});
  assert.equal(result.revision, head);
  assert.deepEqual(calls, ['pull/123/head']);
});
test('working-branch push and dispatch admission retain the latest-ref guard', async () => {
  for (const event of ['push', 'workflow_dispatch']) {
    const context = {...env, GITHUB_EVENT_NAME: event, GITHUB_REF: 'refs/heads/feature'};
    assert.deepEqual(revisionToCheck(context, {}), {ref: 'heads/feature', expected: merge});
    await assertCurrentRevision(context, {}, async () => merge, {checkoutRevision: merge});
    await assert.rejects(assertCurrentRevision(context, {}, async () => newer, {checkoutRevision: merge}), /superseded/u);
  }
});
test('unavailable, malformed or ambiguous latest revision fails closed', async () => {
  for (const current of [null, '', 'abc', [], {}, '0'.repeat(39)]) {
    await assert.rejects(assertCurrentRevision(env, payload, async () => current));
  }
  await assert.rejects(assertCurrentRevision(env, payload, async () => { throw Error('offline'); }, {checkoutRevision: merge}), /offline/u);
  for (const invalid of [{}, {number: 0}, {number: 123, pull_request: {head: {sha: 'bad'}}}]) {
    assert.throws(() => revisionToCheck(env, invalid));
  }
});
test('read-only ref lookup verifies exact ref/type and never follows token-bearing redirects', async () => {
  const body = {ref: 'refs/pull/123/head', object: {type: 'commit', sha: head}};
  const fetchImpl = async (url, options) => {
    assert.equal(url.href, 'https://api.github.com/repos/actql/actql/git/ref/pull/123/head');
    assert.equal(options.redirect, 'error');
    assert.equal(options.method, undefined);
    assert(options.signal instanceof AbortSignal);
    return {ok: true, json: async () => body};
  };
  assert.equal(await readRef('actql/actql', 'pull/123/head', {token: 'fixture', fetchImpl}), head);
  for (const result of [{ok: false, status: 403}, {ok: true, json: async () => ({...body, ref: 'refs/heads/main'})},
    {ok: true, json: async () => ({...body, object: {type: 'tag', sha: head}})}]) {
    await assert.rejects(readRef('actql/actql', 'pull/123/head', {token: 'fixture', fetchImpl: async () => result}));
  }
});
test('mandatory preflight admits every normal heavy primitive and does not serialize the compound spec suite', () => {
  const heavy = ['core-common', 'core-darwin', 'host', 'client-packages', 'client-supported-versions', 'client-distribution', 'client-distribution-callers',
    'client-distribution-mutations', 'client-distribution-packed', 'client-packed', 'client-packed-composition', 'client-salesforce', 'client-readme-packed',
    'native-cli-installed', 'native-cli-linux-local', 'native-workloads', 'native-http', 'session-evidence', 'session-controls', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants', 'pipeline-validation', 'native-macos-workloads',
    'native-separated-network', 'workers', 'connector-addition', 'duckdb-node'];
  for (const name of [...heavy, 'lint', 'spec']) {
    assert(jobs[name].needs.includes('preflight'), name);
    assert(!jobs[name].needs.includes('spec'), name);
    assert(!/always\(|failure\(|cancelled\(/u.test(jobs[name].if), `${name} must retain implicit success()`);
    assert.equal(jobs[name]['continue-on-error'], undefined);
  }
  assert.deepEqual(jobs['native-http-macos'].needs,
    ['select-targets', 'preflight', 'native-macos-workloads', 'native-http', 'core']);
  assert.match(jobs['native-http-macos'].if, /always\(\)/u, 'The lightweight join must report a failed or missing original consumer');
  assert.equal(jobs['native-http-macos']['continue-on-error'], undefined);
  assert.deepEqual(permissions, {contents: 'read'});
  assert.equal(jobs.preflight.steps[0].with['fetch-depth'], 0);
  assert.equal(jobs.preflight.steps[0].with['persist-credentials'], false);
  const preflight = commands('preflight');
  assert(!preflight.some(command => command.includes('proofs/relation-pipeline/history.mjs')));
  assert.equal(preflight.at(-1), 'node scripts/ci-preflight.mjs');
  assert(!preflight.some(command => /sleep|check:spec|run\.mjs all/u.test(command)));
});
test('pinned actionlint checks every workflow before expensive fan-out', () => {
  const steps = jobs.preflight.steps;
  const step = steps.find(step => step.name === 'Check all workflows with pinned actionlint');
  assert(step);
  assert.equal(step.if, undefined);
  assert.equal(step['continue-on-error'], undefined);
  assert(steps.indexOf(step) < steps.findIndex(step => step.name === 'Install pinned MoonBit'));
  assert.match(step.run, /releases\/download\/v1\.7\.12\/actionlint_1\.7\.12_linux_amd64\.tar\.gz/u);
  assert(step.run.includes('8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8'));
  assert.match(step.run, /sha256sum --check --strict/u);
  assert.match(step.run, /"\$tool\/actionlint" -oneline -shellcheck= -pyflakes=\s*$/u);
  assert(!/--ignore|\|\| true/u.test(step.run));
});

test('runtime command inventory fails before expensive fan-out with nonzero execution required', () => {
  const steps = jobs.preflight.steps;
  const index = steps.findIndex(step => step.name === 'Check runtime command inventory before fan-out');
  assert(index > steps.findIndex(step => step.run === 'npm ci'));
  assert(index < steps.findIndex(step => step.name === 'Install pinned MoonBit'));
  const command = steps[index].run;
  assert(command.includes('runFocusedTests("node"'));
  assert(command.includes('^check:.* retains its exact registered commands'));
  assert(command.includes('scripts/build-runtime-packages.test.mjs'));
  assert.equal(steps[index]['continue-on-error'], undefined);
});

test('moved validators execute exactly once before fan-out; complete local spec command is preserved', () => {
  const preflight = commands('preflight');
  for (const command of ['npm run check:contract-versions', 'moon fmt --check',
    'node scripts/check-moonbit-api.mjs', 'npm run check:metadata']) {
    assert.equal(preflight.filter(value => value === command).length, 1, command);
    assert(![...commands('lint'), ...commands('spec')].includes(command), command);
  }
  const {scripts} = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert.equal(scripts['check:spec'], 'npm run check:interfaces && npm run check:contract-versions && npm run check:spec-after-preflight');
  assert(!scripts['check:spec-after-preflight'].includes('check:contract-versions'));
  assert(commands('spec').includes('npm run check:spec-after-preflight'));
});
test('operation evidence consistency is mandatory admission without changing the full plan', () => {
  const command = 'node --test scripts/pure-operation-inventory.test.mjs';
  const steps = jobs.preflight.steps.filter(step => step.run === command);
  assert.equal(steps.length, 1);
  assert.equal(steps[0].if, undefined, 'the complete inventory is checked for every normal admission');
  assert.equal(steps[0]['continue-on-error'], undefined);
  const preflight = commands('preflight');
  assert(preflight.indexOf(command) < preflight.indexOf('npm ci'));
  // Keep the original semantic checks and local command intact. This early
  // replay rejects invalid inputs; it is not a successful reduced profile.
  const {scripts} = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert(scripts['check:aoa'].includes('scripts/pure-operation-inventory.test.mjs'));
  assert(commands('spec').includes('npm run check:spec-after-preflight'));
  const selection = selectTargets([
    'docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json',
    'src/program_check/check.mbt',
  ]);
  assert.equal(selection.profile, 'full');
  assert.deepEqual(selection.targets, ['js', 'wasm', 'native']);
  assert.equal(selection.macos, true);
  const results = Object.fromEntries(gateJobs.map(name =>
    [name, {result: ['focused-tests', 'main-performance', 'health-quick'].includes(name) ? 'skipped' : 'success'}]));
  const plan = {sourceRevision: merge, selection};
  const context = {sourceRevision: merge, event: 'pull_request'};
  verifyGate(plan, results, context);
  const rejected = Object.fromEntries(gateJobs.map(name => [name, {
    result: name === 'select-targets' ? 'success' : name === 'preflight' ? 'failure' : 'skipped',
  }]));
  assert.throws(() => verifyGate(plan, rejected, context), /preflight: expected success/u);
});
test('failed, skipped, cancelled or missing preflight cannot become a passing final gate', () => {
  const selection = selectTargets(['.github/workflows/ci.yml']);
  const results = Object.fromEntries(gateJobs.map(name => [name, {result: ['focused-tests', 'main-performance', 'health-quick'].includes(name) ? 'skipped' : 'success'}]));
  const plan = {sourceRevision: merge, selection};
  const context = {sourceRevision: merge, event: 'pull_request'};
  verifyGate(plan, results, context);
  for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
    assert.throws(() => verifyGate(plan, {...results, preflight: {result}}, context), /preflight/u);
  }
  delete results.preflight;
  assert.throws(() => verifyGate(plan, results, context), /inventory/u);
});

function mainFixture(event = 'push') {
  return {context: {...env, GITHUB_EVENT_NAME: event, GITHUB_REF: 'refs/heads/main',
    GITHUB_REPOSITORY_ID: '12', GITHUB_WORKFLOW_SHA: merge, GITHUB_WORKFLOW_REF: 'actql/actql/.github/workflows/ci.yml@refs/heads/main'},
  body: {ref: 'refs/heads/main', after: merge, deleted: false,
    repository: {id: 12, full_name: 'actql/actql', visibility: 'public', private: false}}};
}
test('authenticated fixed main push and dispatch finish despite later main advancement', async () => {
  for (const event of ['push', 'workflow_dispatch', 'schedule']) {
    const {context, body} = mainFixture(event);
    let lookups = 0;
    assert.deepEqual(await assertCurrentRevision(context, body, async () => { lookups++; return newer; },
      {checkoutRevision: merge}), {ref: 'heads/main', revision: merge});
    assert.equal(lookups, 0, 'moving main must not invalidate this immutable event checkout');
  }
});
test('fixed main exception rejects missing or conflicting event, repository, workflow and checkout identities', async () => {
  for (const mutate of [
    f => { f.body.after = newer; }, f => { f.context.GITHUB_WORKFLOW_SHA = newer; }, f => { f.body.ref = 'refs/heads/feature'; },
    f => { f.body.deleted = true; }, f => { delete f.body.deleted; },
    f => { f.body.repository.id = 13; }, f => { f.body.repository.full_name = 'fork/actql'; },
    f => { delete f.body.repository; }, f => { f.context.GITHUB_REPOSITORY_ID = ''; },
    f => { f.context.GITHUB_WORKFLOW_REF = 'actql/actql/.github/workflows/ci.yml@refs/heads/feature'; },
    f => { f.body.repository.private = true; }, f => { delete f.body.repository.visibility; },
    f => { f.body.inputs = {performance_matrix: true}; },
    f => { f.body.inputs = {packed_query_evidence_probe: 'true'}; },
  ]) {
    const f = mainFixture(); mutate(f);
    await assert.rejects(assertCurrentRevision(f.context, f.body, async () => merge, {checkoutRevision: merge}));
  }
  const {context, body} = mainFixture();
  for (const checkoutRevision of [null, newer, 'invalid']) {
    await assert.rejects(assertCurrentRevision(context, body, async () => merge, {checkoutRevision}));
  }
});


test('PR admission requires the tested merge checkout while retaining its distinct head identity', async () => {
  for (const checkoutRevision of [null, head, newer]) {
    await assert.rejects(assertCurrentRevision(env, payload, async () => head,
      {checkoutRevision}), /Checkout differs/u);
  }
  const forkPayload = {...payload, pull_request: {...payload.pull_request,
    head: {...payload.pull_request.head, repo: {full_name: 'contributor/actql'}},
    base: {sha: newer, repo: {full_name: 'actql/actql'}}}};
  const checked = await assertCurrentRevision(env, forkPayload, async (repository, ref) => {
    assert.equal(repository, 'actql/actql');
    assert.equal(ref, 'pull/123/head');
    return head;
  }, {checkoutRevision: merge});
  assert.equal(checked.revision, head);
});

test('scheduled deep validation is pinned to authenticated main and cannot admit a working branch', async () => {
  const f = mainFixture('schedule');
  await assertCurrentRevision(f.context, f.body, () => { throw Error('must not query moving main'); }, {checkoutRevision: merge});
  for (const mutate of [
    f => { f.context.GITHUB_REF = 'refs/heads/feature'; },
    f => { f.context.GITHUB_WORKFLOW_SHA = newer; },
    f => { f.body.repository.id = 13; },
    f => { f.body.repository.private = true; },
  ]) {
    const f = mainFixture('schedule'); mutate(f);
    await assert.rejects(assertCurrentRevision(f.context, f.body, async () => merge, {checkoutRevision: merge}));
  }
});

// These runners do not use setup-toolchain: their tests and bundle generators
// still import the root's pinned parser and build dependencies.
test('isolated connector jobs install their own exact root verification dependencies', () => {
  for (const [name, command, lock] of [
    ['connector-addition', 'npm run check:connector-addition', 'adapters/connectors/duckdb/node/package-lock.json'],
    ['duckdb-node', 'npm test --prefix adapters/connectors/duckdb/node', 'adapters/connectors/duckdb/node/package-lock.json'],
    ['workers', 'node scripts/workers-fixtures.mjs', 'adapters/workers/package-lock.json'],
  ]) {
    const steps = jobs[name].steps;
    const install = steps.findIndex(step => step.run === 'npm ci');
    assert(install >= 0, `${name} must install root dependencies in its own checkout`);
    const consumer = steps.findIndex(step => step.run === command);
    assert(consumer > install, `${name} must install before consuming root tools`);
    const setup = steps.find(step => step.uses?.startsWith('actions/setup-node@'));
    assert.deepEqual(setup.with['cache-dependency-path'].trim().split(/\s+/u),
      ['package-lock.json', lock]);
  }
});
