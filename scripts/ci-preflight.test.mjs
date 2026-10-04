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
  }), {ref: 'pull/123/head', revision: head});
  await assert.rejects(assertCurrentRevision(env, payload, async () => newer), /superseded/u);
});
test('main-only advance does not invalidate an unchanged PR head', async () => {
  const calls = [];
  const result = await assertCurrentRevision(env,
    {...payload, pull_request: {...payload.pull_request, base: {sha: newer}}},
    async (repo, ref) => { calls.push(ref); return head; });
  assert.equal(result.revision, head);
  assert.deepEqual(calls, ['pull/123/head']);
});
test('push and dispatch admission compare the exact ref with tested SHA', async () => {
  for (const event of ['push', 'workflow_dispatch']) {
    const context = {...env, GITHUB_EVENT_NAME: event, GITHUB_REF: 'refs/heads/main'};
    assert.deepEqual(revisionToCheck(context, {}), {ref: 'heads/main', expected: merge});
    await assertCurrentRevision(context, {}, async () => merge);
    await assert.rejects(assertCurrentRevision(context, {}, async () => newer), /superseded/u);
  }
});
test('unavailable, malformed or ambiguous latest revision fails closed', async () => {
  for (const current of [null, '', 'abc', [], {}, '0'.repeat(39)]) {
    await assert.rejects(assertCurrentRevision(env, payload, async () => current));
  }
  await assert.rejects(assertCurrentRevision(env, payload, async () => { throw Error('offline'); }), /offline/u);
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
  const heavy = ['core', 'host', 'client-packages', 'client-distribution', 'client-packed', 'client-salesforce',
    'native', 'session-evidence', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants', 'pipeline-validation', 'native-macos',
    'native-separated-network', 'workers', 'connector-addition', 'duckdb-node'];
  for (const name of [...heavy, 'lint', 'spec']) {
    assert(jobs[name].needs.includes('preflight'), name);
    assert(!jobs[name].needs.includes('spec'), name);
    assert(!/always\(|failure\(|cancelled\(/u.test(jobs[name].if), `${name} must retain implicit success()`);
    assert.equal(jobs[name]['continue-on-error'], undefined);
  }
  assert.deepEqual(permissions, {contents: 'read'});
  assert.equal(jobs.preflight.steps[0].with['fetch-depth'], 0);
  assert.equal(jobs.preflight.steps[0].with['persist-credentials'], false);
  const preflight = commands('preflight');
  assert(preflight.indexOf('node proofs/relation-pipeline/history.mjs --write') < preflight.findIndex(command => command.includes('setup-moonbit')));
  assert.equal(preflight.at(-1), 'node scripts/ci-preflight.mjs');
  assert(!preflight.some(command => /sleep|check:spec|run\.mjs all/u.test(command)));
});
test('moved validators execute exactly once before fan-out; complete local spec command is preserved', () => {
  const preflight = commands('preflight');
  for (const command of ['npm run check:contract-versions', 'moon fmt --check',
    'node scripts/check-moonbit-api.mjs', 'npm run check:metadata']) {
    assert.equal(preflight.filter(value => value === command).length, 1, command);
    assert(![...commands('lint'), ...commands('spec')].includes(command), command);
  }
  const {scripts} = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert.equal(scripts['check:spec'], 'npm run check:contract-versions && npm run check:spec-after-preflight');
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
  assert(preflight.indexOf('node proofs/relation-pipeline/history.mjs --write') < preflight.indexOf(command));
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
    [name, {result: name === 'focused-tests' ? 'skipped' : 'success'}]));
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
  const results = Object.fromEntries(gateJobs.map(name => [name, {result: name === 'focused-tests' ? 'skipped' : 'success'}]));
  const plan = {sourceRevision: merge, selection};
  const context = {sourceRevision: merge, event: 'pull_request'};
  verifyGate(plan, results, context);
  for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
    assert.throws(() => verifyGate(plan, {...results, preflight: {result}}, context), /preflight/u);
  }
  delete results.preflight;
  assert.throws(() => verifyGate(plan, results, context), /inventory/u);
});
