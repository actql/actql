import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';
import {createResultFactory} from '../../packages/sdk/internal/result-read.mjs';
import {localResourceResultReadLimits} from './installed-host-policy.mjs';
import recipe from './host-result-service-recipe.cjs';

// Execute the installed Host's actual policy and authority callbacks without
// importing a compiled Host. The reader below is an explicit delivery double;
// this is SDK/Host policy coverage, not Store, Core grant or physical evidence.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declarations = new Map();
function visit(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'VariableDeclarator' && ['negotiate', 'resultAuthority', 'resultReadLimits'].includes(node.id.name)) {
    assert.equal(declarations.has(node.id.name), false);
    declarations.set(node.id.name, node.init);
  }
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value !== null && typeof value === 'object') visit(value);
  }
}
visit(ast);
function original(name, bindings) {
  const node = declarations.get(name);
  assert(node, `Missing installed ${name}`);
  return compileFunction(`return (${source.slice(node.start, node.end)});`, Object.keys(bindings))(
    ...Object.values(bindings));
}

async function fixture(lengths, {deny = false, revokeAt, cleanupFails = false, requestMemory} = {}) {
  const policy = Object.freeze({});
  const moon = {
    clientLocalResourcePolicyOriginal: () => policy,
    clientLocalPreparationResourceLimits(value, selectedRetained, selectedExecution) {
      assert.equal(value, policy);
      assert.equal(selectedRetained, requestMemory === undefined ? undefined : BigInt(requestMemory.retainedBytes));
      assert.equal(selectedExecution, requestMemory === undefined ? undefined : BigInt(requestMemory.executionBytes));
      return [100000n, 100000n, 100000n, 100000000000n, selectedRetained ?? 536870912n, selectedExecution ?? 536870912n];
    },
    clientLocalResourcePolicyRowCeiling(value) {assert.equal(value, policy); return 2097152;},
  };
  const resultReadLimits = original('resultReadLimits', {moon, localResourceResultReadLimits, requestMemory});
  const limits = (await original('negotiate', {mode: 'local', workspaceId: undefined,
    authorityScopeCid: 'scope', hostConnection: () => false, resultReadLimits})({connection: {}})).limits;
  let allowed = !deny, opened = 0, stopped = 0, closed = 0, produced = 0, bytes = 0;
  const authority = original('resultAuthority', {
    installResultAccessAuthority: value => value,
    authorizeLocalResult: async () => allowed,
    cid: () => `sha256:${'a'.repeat(64)}`, now: () => '2026-11-09T00:00:00.000Z',
    plus: value => value,
    // The old publication default is intentionally independent of read policy.
    localOutputLimits: {maxWireBytes: 10000000},
    resultReadLimits,
  });
  const activeReaders = new Set(), readerCleanups = new Set();
  let grant;
  const result = createResultFactory({ref: {}, limits, lookupContext: {}, typedRows: true}, {
    async runRequest(operation, {attemptId}, signal) {
      assert.equal(operation, 'read');
      grant = await authority.admitResultRead({attemptId}, Object.freeze({}));
      opened++;
      return {kind: 'rows', frames: {
        async *[Symbol.asyncIterator]() {
          try {
            for (const length of lengths) {
              signal.throwIfAborted();
              if (produced === revokeAt) allowed = false;
              if (await authority.authorizeResultRead({}) !== true) {
                throw Object.assign(new Error('ResultAccessDenied'), {code: 'ResultAccessDenied'});
              }
              if (bytes + length > grant.maxBytes) {
                throw Object.assign(new Error('ResultReadLimit'), {code: 'ResultReadLimit'});
              }
              // One bounded row at a time; no whole-result collection/backing.
              const value = {value: 'x'.repeat(length - 12)};
              assert.equal(Buffer.byteLength(JSON.stringify(value)), length);
              bytes += length; produced++;
              yield {value, byteLength: length};
            }
          } finally { stopped++; }
        },
      }, async close() {
        closed++;
        if (cleanupFails) throw new Error('OriginalReaderCleanupPending');
      }};
    },
  }, {activeReaders, readerCleanups}, () => undefined)('answer');
  return {result, limits, activeReaders, readerCleanups,
    counts: () => ({opened, stopped, closed, produced, bytes}), grant: () => grant};
}
async function drain(reader) {
  let count = 0;
  for await (const row of reader) { assert.equal(typeof row.value, 'string'); count++; }
  return count;
}
function retired(f) {
  assert.equal(f.activeReaders.size, 0);
  assert.equal(f.readerCleanups.size, 0);
  assert.equal(f.counts().stopped, 1);
  assert.equal(f.counts().closed, 1);
}

test('installed read initializer binds omitted small and large memory pairs before negotiation', async () => {
  for (const requestMemory of [undefined,
    {retainedBytes: 8192, executionBytes: 16384},
    {retainedBytes: 1073741824, executionBytes: 2147483648}]) {
    const f = await fixture([32], {requestMemory});
    assert.equal(f.limits.maxRetainedValueBytes, requestMemory?.retainedBytes ?? 536870912);
    assert.deepEqual(await f.result.all(), [{value: 'x'.repeat(20)}]);
    retired(f);
  }
});

test('installed read grant covers the negotiated stream beyond the publication default', async () => {
  const f = await fixture(Array(200).fill(52000));
  assert.equal(await drain(f.result.rows()), 200);
  assert.equal(f.counts().bytes, 10400000);
  assert.equal(f.grant().maxBytes, f.limits.maxReadWireBytes);
  assert.equal(f.grant().maxUses, 1);
  assert.equal(f.limits.maxReadWireBytes, 10 * 1024 * 1024);
  assert.equal(f.limits.maxRowWireBytes, 1024 * 1024);
  const control = {}, recipeLimits = recipe.declareHostResultServiceRecipe(control,
    {sharedControl: control}, {}, {}).result;
  assert.equal(recipeLimits.maxReadWireBytes, f.limits.maxReadWireBytes);
  assert.equal(recipeLimits.maxRowWireBytes, f.limits.maxRowWireBytes);
  retired(f);
});

test('selected read ceiling and client tightening still refuse with the same reader cleanup', async () => {
  const exact = await fixture([...Array(201).fill(52000), 33760]);
  assert.equal(await drain(exact.result.rows()), 202);
  assert.equal(exact.counts().bytes, exact.limits.maxReadWireBytes);
  retired(exact);
  const beyond = await fixture([...Array(201).fill(52000), 33761]);
  await assert.rejects(drain(beyond.result.rows()), {code: 'ResultReadLimit'});
  retired(beyond);
  const tighter = await fixture(Array(200).fill(52000));
  await assert.rejects(drain(tighter.result.rows({maxWireBytes: 10000000})), {code: 'ResultWireLimit'});
  retired(tighter);
  assert.throws(() => tighter.result.rows({maxWireBytes: tighter.limits.maxReadWireBytes + 1}),
    {code: 'InvalidReadLimit'});
});

test('read authorization remains required before opening and during delivery', async () => {
  const denied = await fixture([52000], {deny: true});
  await assert.rejects(drain(denied.result.rows()), {code: 'ResultAccessDenied'});
  assert.deepEqual(denied.counts(), {opened: 0, stopped: 0, closed: 0, produced: 0, bytes: 0});
  assert.equal(denied.activeReaders.size, 0);
  const revoked = await fixture(Array(200).fill(52000), {revokeAt: 3});
  await assert.rejects(drain(revoked.result.rows()), {code: 'ResultAccessDenied'});
  assert.equal(revoked.counts().produced, 3);
  retired(revoked);
});

test('streaming does not relax explicit collection or per-row bounds', async () => {
  const collection = await fixture(Array(200).fill(52000));
  await assert.rejects(collection.result.all({maxRows: 2}), {code: 'ResultRetainedLimit'});
  assert.equal(collection.limits.maxRows, 2097152);
  assert.equal(collection.limits.maxRetainedValueBytes, 536870912);
  retired(collection);
  const row = await fixture([1024 * 1024 + 1]);
  await assert.rejects(drain(row.result.rows()), {code: 'ResultRowWireLimit'});
  retired(row);
});

test('early return retires the original reader and failed cleanup remains pending', async () => {
  const early = await fixture(Array(200).fill(52000));
  for await (const row of early.result.rows()) { assert.equal(typeof row.value, 'string'); break; }
  assert.equal(early.counts().produced, 1);
  retired(early);
  const pending = await fixture([52000], {cleanupFails: true});
  await assert.rejects(drain(pending.result.rows()), error => error.code === 'ResultReadCleanupUnknown');
  assert.equal(pending.counts().closed, 1);
  assert.equal(pending.activeReaders.size, 0);
  assert.equal(pending.readerCleanups.size, 1);
});
