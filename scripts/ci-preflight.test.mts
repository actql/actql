import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';
import {assertCurrentRevision, readRef, revisionToCheck} from './ci-preflight.mjs';
import {gateJobs, selectTargets, verifyGate} from './ci-targets.mjs';

type WorkflowStep = {name?: string; uses?: string; run?: string; if?: string;
  with: Record<string, string | number | boolean>; 'continue-on-error'?: boolean};
type Workflow = {permissions: unknown; jobs: Record<string, {needs: string[]; if: string; steps: WorkflowStep[];
  'continue-on-error'?: boolean}>};
type EventPayload = NonNullable<Parameters<typeof assertCurrentRevision>[1]>;
type MainFixture = {context: NodeJS.ProcessEnv; body: EventPayload};
type Outcome = NonNullable<Parameters<typeof verifyGate>[1][string]>;

const head = 'a'.repeat(40), merge = 'b'.repeat(40), newer = 'c'.repeat(40);
const env = {GITHUB_SHA: merge, GITHUB_REPOSITORY: 'actql/actql', GITHUB_EVENT_NAME: 'pull_request'};
const payload = {number: 123, pull_request: {head: {sha: head}}};
const {jobs, permissions}: Workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const commands = (name: string) => jobs[name].steps.filter(step => step.run).map(step => step.run!);

test('PR admission compares current head with event head, not the synthetic tested merge', async () => {
  assert.deepEqual(revisionToCheck(env, payload), {ref: 'pull/123/head', expected: head});
  assert.deepEqual(await assertCurrentRevision(env, payload, async (repo, ref) => {
    assert.equal(repo, 'actql/actql'); assert.equal(ref, 'pull/123/head'); return head;
  }, {checkoutRevision: merge}), {ref: 'pull/123/head', revision: head});
  await assert.rejects(assertCurrentRevision(env, payload, async () => newer, {checkoutRevision: merge}), /superseded/u);
});
test('main-only advance does not invalidate an unchanged PR head', async () => {
  const calls: string[] = [];
  const result = await assertCurrentRevision(env,
    {...payload, pull_request: {...payload.pull_request, base: {sha: newer}}} as EventPayload,
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
    await assert.rejects(assertCurrentRevision(env, payload, async () => current as string));
  }
  await assert.rejects(assertCurrentRevision(env, payload, async () => { throw Error('offline'); }, {checkoutRevision: merge}), /offline/u);
  for (const invalid of [{}, {number: 0}, {number: 123, pull_request: {head: {sha: 'bad'}}}]) {
    assert.throws(() => revisionToCheck(env, invalid));
  }
});
test('read-only ref lookup verifies exact ref/type and never follows token-bearing redirects', async () => {
  const body = {ref: 'refs/pull/123/head', object: {type: 'commit', sha: head}};
  const fetchImpl: typeof fetch = async (url, options) => {
    assert.equal((url as URL).href, 'https://api.github.com/repos/actql/actql/git/ref/pull/123/head');
    assert.equal(options!.redirect, 'error');
    assert.equal(options!.method, undefined);
    assert(options!.signal instanceof AbortSignal);
    return {ok: true, json: async () => body} as Response;
  };
  assert.equal(await readRef('actql/actql', 'pull/123/head', {token: 'fixture', fetchImpl}), head);
  for (const result of [{ok: false, status: 403}, {ok: true, json: async () => ({...body, ref: 'refs/heads/main'})},
    {ok: true, json: async () => ({...body, object: {type: 'tag', sha: head}})}]) {
    await assert.rejects(readRef('actql/actql', 'pull/123/head',
      {token: 'fixture', fetchImpl: async () => result as unknown as Response}));
  }
});
test('preflight remains mandatory at the final gate without delaying independent jobs', () => {
  const heavy = ['core-js', 'core-common', 'core-darwin', 'host', 'client-packages', 'client-supported-versions', 'client-distribution', 'client-distribution-callers',
    'client-distribution-mutations', 'client-distribution-packed', 'client-packed', 'client-packed-composition', 'client-salesforce', 'client-readme-packed', 'client-direct-model',
    'native-cli-installed', 'native-cli-linux-local', 'native-cli-linux-local-installed', 'native-cli-linux-local-mock', 'native-workloads', 'native-http', 'session-evidence', 'session-controls', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants', 'pipeline-validation', 'native-macos-workloads',
    'native-separated-network', 'workers', 'connector-addition', 'duckdb-node'];
  for (const name of [...heavy, 'lint', 'spec']) {
    assert(!jobs[name].needs.includes('preflight'), name);
    assert(!jobs[name].needs.includes('spec'), name);
    if (name === 'core-darwin') {
      assert.deepEqual(jobs[name].needs, ['select-targets']);
      assert(jobs[name].if.includes("always() && !cancelled() && needs.select-targets.result == 'success'"));
      assert(!jobs[name].if.includes('needs.lint') && !jobs[name].if.includes('needs.core-js'));
    } else if (name === 'native-cli-linux-local') {
      assert.deepEqual(jobs[name].needs, ['select-targets']);
      const condition = jobs[name].if.slice(3, -3)
        .replaceAll('needs.select-targets', "needs['select-targets']");
      const enabled = ({event = 'pull_request', result = 'success', profile = 'full',
        manual = false, cancelled = false, privateRepo = false} = {}) => runInNewContext(condition, {
        github: {event_name: event, event: {repository: {
          visibility: privateRepo ? 'private' : 'public', private: privateRepo,
        }}},
        needs: {'select-targets': {result, outputs: {profile}}},
        inputs: {native_shared_remote_linux: manual},
        always: () => true, cancelled: () => cancelled, toJSON: JSON.stringify,
      }, {timeout: 100});
      for (const event of ['pull_request', 'push']) {
        assert.equal(enabled({event}), true);
        for (const result of ['failure', 'cancelled', 'skipped'])
          assert.equal(enabled({event, result}), false);
        assert.equal(enabled({event, profile: 'draft'}), false);
        assert.equal(enabled({event, privateRepo: true}), false);
        assert.equal(enabled({event, cancelled: true}), false);
        assert.equal(enabled({event, result: 'skipped', manual: true}), false);
      }
      const dispatch = {event: 'workflow_dispatch', result: 'skipped', manual: true};
      assert.equal(enabled(dispatch), true);
      for (const refusal of [{manual: false}, {result: 'failure'}, {result: 'cancelled'},
        {cancelled: true}, {privateRepo: true}])
        assert.equal(enabled({...dispatch, ...refusal}), false);
    } else assert(!/always\(|failure\(|cancelled\(/u.test(jobs[name].if), `${name} must retain implicit success()`);
    assert.equal(jobs[name]['continue-on-error'], undefined);
  }
  for (const [name, job] of Object.entries(jobs)) {
    if (name === 'check') assert.equal(job.needs.filter(value => value === 'preflight').length, 1);
    else assert(!job.needs?.includes('preflight'), name);
  }
  assert.deepEqual(jobs['native-http-macos'].needs,
    ['select-targets', 'native-macos-workloads', 'native-http', 'core']);
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
  assert.match(step.run!, /releases\/download\/v1\.7\.12\/actionlint_1\.7\.12_linux_amd64\.tar\.gz/u);
  assert(step.run!.includes('8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8'));
  assert.match(step.run!, /sha256sum --check --strict/u);
  assert.match(step.run!, /"\$tool\/actionlint" -oneline -shellcheck= -pyflakes=\s*$/u);
  assert(!/--ignore|\|\| true/u.test(step.run!));
});


test('mandatory validators execute once and the complete local spec command is preserved', () => {
  for (const [owner, command] of [['select-targets', 'npm run check:contract-versions'],
    ...['moon fmt --check', 'node scripts/check-moonbit-api.mjs', 'npm run check:metadata']
      .map(command => ['preflight', command])]) {
    const selected = Object.entries(jobs).filter(([, job]) => job.steps)
      .flatMap(([name]) => commands(name).filter(value => value === command).map(() => name));
    assert.deepEqual(selected, [owner], command);
  }
  const {scripts}: {scripts: Record<string, string>} = JSON.parse(
    readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  const local = scripts['check:spec'].split('&&').map(command => command.trim());
  for (const recipe of ['check:interfaces', 'check:contract-versions', 'check:spec-after-preflight'])
    assert.equal(local.filter(command => command === `npm run ${recipe}`).length, 1, recipe);
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
  assert(preflight.indexOf('npm ci') >= 0 && preflight.indexOf('npm ci') < preflight.indexOf(command));
  // Keep the original semantic checks and local command intact. This early
  // replay rejects invalid inputs; it is not a successful reduced profile.
  const {scripts}: {scripts: Record<string, string>} = JSON.parse(
    readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert(scripts['check:aoa'].includes('scripts/pure-operation-inventory.test.mjs'));
  assert(commands('spec').includes('npm run check:spec-after-preflight'));
  const selection = selectTargets([
    'docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json',
    'src/program_check/check.mbt',
  ]);
  assert.equal(selection.profile, 'full');
  assert.deepEqual(selection.targets, ['js', 'wasm', 'native']);
  assert.equal(selection.macos, false);
  const results: Record<string, Outcome> = Object.fromEntries(gateJobs.map(name =>
    [name, {result: ['focused-tests', 'health-quick', 'native-macos'].includes(name) ? 'skipped' : 'success'}]));
  results['python-wheels'].outputs = {'linux-x64': merge};
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
  const results: Record<string, Outcome> = Object.fromEntries(gateJobs.map(name => [name, {result: ['focused-tests', 'health-quick'].includes(name) ? 'skipped' : 'success'}]));
  results['python-wheels'].outputs = {'linux-x64': merge, 'darwin-arm64': merge};
  const plan = {sourceRevision: merge, selection};
  const context = {sourceRevision: merge, event: 'pull_request'};
  verifyGate(plan, results, context);
  for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
    assert.throws(() => verifyGate(plan, {...results, preflight: {result}}, context), /preflight/u);
  }
  delete results.preflight;
  assert.throws(() => verifyGate(plan, results, context), /inventory/u);
});

function mainFixture(event = 'push'): MainFixture {
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
    f => { f.body.repository!.id = 13; }, f => { f.body.repository!.full_name = 'fork/actql'; },
    f => { delete f.body.repository; }, f => { f.context.GITHUB_REPOSITORY_ID = ''; },
    f => { f.context.GITHUB_WORKFLOW_REF = 'actql/actql/.github/workflows/ci.yml@refs/heads/feature'; },
    f => { f.body.repository!.private = true; }, f => { delete f.body.repository!.visibility; },
    f => { f.body.inputs = {performance_matrix: true}; },
    f => { f.body.inputs = {packed_query_evidence_probe: 'true'}; },
  ] satisfies ((f: MainFixture) => void)[]) {
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
    f => { f.body.repository!.id = 13; },
    f => { f.body.repository!.private = true; },
  ] satisfies ((f: MainFixture) => void)[]) {
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
    assert.deepEqual((setup!.with['cache-dependency-path'] as string).trim().split(/\s+/u),
      ['package-lock.json', lock]);
  }
});
