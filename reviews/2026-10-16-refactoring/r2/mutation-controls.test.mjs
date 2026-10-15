// Source-qualified mutation experiment, deliberately separate from the durable
// architectural gate. Mutation targets describe this reviewed implementation;
// harmless future extraction must not become a CI failure in an experiment.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {parse} from 'acorn';
import {authorizationBoundary, cleanupBoundary, unknownCommitBoundary} from '../../../scripts/query-boundary-behavior.fixture.mjs';
import {hostApprovalBoundary, hostCompletionBoundary, hostPreflightCustodyBoundary} from '../../../scripts/query-host-boundary.fixture.mjs';
const sourceRoot = new URL('../../../scripts/', import.meta.url);
const reviewed = JSON.parse(readFileSync(new URL('./mutation-inputs.json', import.meta.url)));
for (const [path, expected] of Object.entries(reviewed.productInputs)) {
  assert.equal(createHash('sha256').update(readFileSync(new URL('../' + path, sourceRoot))).digest('hex'),
    expected, `Mutation experiment requires reviewed input: ${path}`);
}
const intended = message => error => error?.code === 'ERR_ASSERTION' && message.test(error.message);

// Private test copies only. Resolve real imports normally; no product API,
// runtime injection or replacement authority is introduced for mutation tests.
async function moduleCopy(path, change) {
  const original = readFileSync(new URL(path, sourceRoot), 'utf8');
  const changed = change(original);
  assert.notEqual(changed, original, 'mutation must actually change its target');
  const syntax = parse(changed, {ecmaVersion: 'latest', sourceType: 'module'});
  const edits = syntax.body.filter(node => node.source?.value?.startsWith('.'))
    .map(node => [node.source.start, node.source.end,
      JSON.stringify(new URL(node.source.value, new URL(path, sourceRoot)).href)]);
  let source = changed;
  for (const [start, end, replacement] of edits.reverse()) source = source.slice(0, start) + replacement + source.slice(end);
  return import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
}
const replace = (source, before, after) => {
  assert.equal(source.split(before).length, 2, 'mutation target must be unique');
  return source.replace(before, after);
};
const authorizationPath = '../adapters/host-common/authorization-gate.mjs';
const transactionPath = '../adapters/host-common/sqlite-transaction.mjs';

test('safe extraction and local rename preserve the same production authorization oracle', async () => {
  const copy = await moduleCopy(authorizationPath, source => replace(source,
    `  if (decision.action !== 'dispatch') {\n    throw new ExecutionAuthorizationError(decision);\n  }\n  return decision;`,
    `  return admittedDecision(decision);\n}\nfunction admittedDecision(admitted) {\n  if (admitted.action !== 'dispatch') {\n    throw new ExecutionAuthorizationError(admitted);\n  }\n  return admitted;`));
  await authorizationBoundary(copy);
});

test('allowing an unapproved dispatch fails the unchanged authorization oracle', async () => {
  const copy = await moduleCopy(authorizationPath, source => replace(source,
    "if (decision.action !== 'dispatch') {\n    throw new ExecutionAuthorizationError(decision);",
    "if (decision.action === 'dispatch') {\n    throw new ExecutionAuthorizationError(decision);"));
  await assert.rejects(authorizationBoundary(copy), intended(/authorization: every non-dispatch decision/u));
});

test('discarding a failed close owner fails the unchanged cleanup custody oracle', async () => {
  const copy = await moduleCopy(transactionPath, source => replace(source,
    'let pending = true;', 'let pending = false;'));
  assert.throws(() => cleanupBoundary(copy), intended(/cleanup custody: failed close/u));
});

test('turning a failed COMMIT into known failure fails the unchanged Unknown oracle', async () => {
  const copy = await moduleCopy(transactionPath, source => replace(source,
    "phase === 'commit' || state.active !== false ?", 'state.active !== false ?'));
  assert.throws(() => unknownCommitBoundary(copy), intended(/Unknown: a failed COMMIT/u));
});

test('bypassing Host activation approval fails before any completion oracle can mask it', async () => {
  const copy = await moduleCopy('../adapters/host-common/strategy.mjs', source => replace(source,
    "if (decision.action !== 'dispatch') {", "if (false) {"));
  await assert.rejects(hostApprovalBoundary(copy), intended(/Host approval: a refused activation/u));
});

test('dropping the Host preflight custody handoff fails its unchanged boundary oracle', async () => {
  const copy = await moduleCopy('../adapters/host-common/strategy.mjs', source => replace(source,
    'try { retainPreflightCleanup(owner); }', 'try { /* omit custody transfer */ }'));
  await assert.rejects(hostPreflightCustodyBoundary(copy), intended(/preflight custody: transfer the exact/u));
});

test('accepting callback success without Common completion fails the unchanged publication oracle', async () => {
  const copy = await moduleCopy('../adapters/host-common/strategy.mjs', source => replace(source,
    'core.completed(setup, index)', 'true'));
  await assert.rejects(hostCompletionBoundary(copy), intended(/Host completion: callback success/u));
});

test('choosing a registration by position fails the unchanged opaque identity oracle', async () => {
  const copy = await moduleCopy('../adapters/host-common/strategy.mjs', source => replace(source,
    'installed.get(core.registration(task))', '[...installed.values()][0]'));
  await assert.rejects(hostCompletionBoundary(copy), intended(/Host registration: equal names/u));
});
