// Failure-port execution of the actual consumer body. Product imports alone
// are replaced by explicit ports; this is not installed/runtime acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {unionBudgetCases} from './fixtures/union-budget-source-input.mjs';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';

const source = await readFile(new URL('./fixtures/union-budget-public.mjs', import.meta.url), 'utf8');
const imports = source.match(/^import .*;$/gm);
assert.equal(imports.length, 6, 'Only the original explicit import ports may be substituted');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const consumer = new AsyncFunction('assert', 'mkdir', 'readFile', 'writeFile', 'resolve',
  'connect', 'unionBudgetCases', 'observeRecordApprovalDescriptors', 'process',
  source.replace(/^import .*;$/gm, line => ' '.repeat(line.length)));
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return {promise, resolve, reject};
};
async function failurePort(t, close) {
  const root = await mkdtemp(join(tmpdir(), 'actql-union-failure-port-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const primary = Object.assign(new Error('original wait failure'), {code: 'OriginalWaitFailure'});
  const originalRef = {authoredFailurePort: 'original'};
  const reportPath = join(root, 'union-budget-run.json');
  let closeCalls = 0;
  const client = {
    async check() { return {report: {verdict: 'invalid'}}; },
    newSubmission({nonce}) { return {nonce}; },
    async startSource() { return {ref: originalRef, async wait() { throw primary; }}; },
    async close() { closeCalls++; await close(reportPath); },
  };
  const running = consumer(assert, mkdir, readFile, writeFile,
    (...parts) => resolve(root, ...parts), async () => client,
    [unionBudgetCases[0]], async () => ({openPaths: []}),
    {argv: ['node', 'fixture', 'run', join(root, 'handoff.json')]});
  // Observe this same promise immediately; never retry or detach its failure.
  const outcome = running.then(value => ({value}), error => ({error}));
  return {primary, originalRef, reportPath, outcome, closeCalls: () => closeCalls};
}

test('original primary and reference are durable before the first close can hang', {timeout: 10000}, async t => {
  const entered = deferred(), release = deferred();
  t.after(() => release.resolve());
  const port = await failurePort(t, async reportPath => {
    try { entered.resolve(JSON.parse(await readFile(reportPath, 'utf8'))); }
    catch (error) { entered.reject(error); throw error; }
    await release.promise;
  });
  const pending = await entered.promise;
  assert.equal(pending.primary.code, 'OriginalWaitFailure');
  assert.equal(pending.firstClosePending, true);
  assert.equal(pending.firstCloseReturned, false);
  assert.equal(pending.complete, false);
  assert.equal(pending.normalPackageAcceptance, false);
  assert.deepEqual(pending.references[0].ref, port.originalRef);
  assert.equal(port.closeCalls(), 1);
  release.resolve();
  assert.equal((await port.outcome).error, port.primary);
  const final = JSON.parse(await readFile(port.reportPath, 'utf8'));
  assert.equal(final.firstClosePending, false);
  assert.equal(final.firstCloseReturned, true);
  assert.equal(final.complete, false, 'returning close cannot erase the original primary');
  assert.equal(final.primary.code, 'OriginalWaitFailure');
  assert.equal(port.closeCalls(), 1);
});

test('rejected first close preserves the original primary and unacknowledged close', async t => {
  const port = await failurePort(t, async reportPath => {
    const before = JSON.parse(await readFile(reportPath, 'utf8'));
    assert.equal(before.primary.code, 'OriginalWaitFailure');
    assert.equal(before.firstClosePending, true);
    throw Object.assign(new Error('close refusal'), {code: 'OriginalCloseFailure'});
  });
  assert.equal((await port.outcome).error, port.primary);
  const final = JSON.parse(await readFile(port.reportPath, 'utf8'));
  assert.equal(final.firstClosePending, true);
  assert.equal(final.firstCloseReturned, false);
  assert.equal(final.closeFailure.code, 'OriginalCloseFailure');
  assert.equal(final.primary.code, 'OriginalWaitFailure');
  assert.equal(final.normalPackageAcceptance, false);
  assert.equal(port.closeCalls(), 1);
});

test('finite parent retains the prewritten report after an actual child timeout', async t => {
  const parentSource = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const expression = /keepArtifacts: (.+)\},/u.exec(parentSource)[1];
  const selection = new Function('unionBudgetOnly', 'process', 'return ' + expression);
  assert.equal(selection(true, {argv: []}), true);
  assert.equal(selection(false, {argv: []}), false, 'other campaigns keep their original choice');
  assert.equal(selection(false, {argv: ['--keep-artifacts']}), true);
  const scratch = await mkdtemp(join(tmpdir(), 'actql-union-parent-timeout-'));
  t.after(() => rm(scratch, {recursive: true, force: true}));
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  let reportPath, directory;
  await assert.rejects(withPackedQueryEvidence({scratch, revision,
    keepArtifacts: selection(true, {argv: []})}, async owner => {
    directory = owner.directory;
    reportPath = join(owner.root, 'union-budget-run.json');
    await writeFile(reportPath, JSON.stringify({primary: {code: 'OriginalWaitFailure'},
      firstClosePending: true, firstCloseReturned: false, complete: false}));
    owner.run(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {timeout: 100});
  }), error => error.code === 'PackedQueryCommandFailed');
  const report = JSON.parse(await readFile(reportPath, 'utf8'));
  assert.equal(report.primary.code, 'OriginalWaitFailure');
  assert.equal(report.firstClosePending, true);
  assert.equal(report.firstCloseReturned, false);
  const summary = JSON.parse(await readFile(join(directory, 'summary.json'), 'utf8'));
  assert.equal(summary.status, 'failed');
  assert.equal(summary.complete, false);
  assert.equal(summary.keepArtifacts, true);
  assert.notEqual(summary.artifactsRemoved, true);
  assert.equal(summary.commands.at(-1).error.code, 'ETIMEDOUT');
});
