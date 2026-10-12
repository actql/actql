// Actual compiled common generation/issuance and actual physical Store. This
// is a component integration test, not public Program dispatch or Model/Effect
// acceptance. Empty input needs no caller-supplied fake completion or values.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {issueStoredGeneratedContent} from './generated-content-holding.mjs';
import {createGeneratedContentFixture, generatedContentFixtureControl as control}
  from './fixtures/generated-content.fixture.mjs';

const token = byte => `sha256:${byte.repeat(64)}`;
const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const limits = {maxBytes: 4096, maxNodes: 100, maxDepth: 8, maxTextUnits: 4096};
const runtime = runtimeCore(moon);
const environmentWire = (await readFile(new URL('../../spec/local-check-environment.json',
  import.meta.url), 'utf8')).trim();
const environment = moon.clientProgramCheckEnvironment(environmentWire,
  JSON.parse(environmentWire).evidence_bundle_cid,
  false, false, true, false, false, false, false);
assert.ok(environment);

const setup = createGeneratedContentFixture;
test('saved generated Content reopens exact physical custody in a separate process', async t => {
  const value = await setup(t);
  await value.store.commitPhysicalHolding(value.holding, [value.physical.prepared]);
  const descriptor = {configuration: value.configuration, wire: value.description.wire,
    binding: value.binding, holding: value.holding, limits};
  const path = join(value.configuration.directory, 'recovery-test.json');
  await writeFile(path, JSON.stringify(descriptor), {flag: 'wx'});
  await value.store.close();
  const {stdout} = await promisify(execFile)(process.execPath,
    [new URL('./fixtures/stored-generated-content-recovery.fixture.mjs', import.meta.url).pathname, path],
    {timeout: 30000, maxBuffer: 65536});
  const recovered = JSON.parse(stdout);
  assert.deepEqual(recovered.description, value.description);
  assert.equal(recovered.bytes, 'id\n');
  assert.equal(recovered.checks, 1);
  assert.equal(recovered.storedBytes, 3);
  // Another process reopening the same immutable holding has the same Ref and
  // does not prepare/upload another object. This is component recovery only.
  const second = await promisify(execFile)(process.execPath,
    [new URL('./fixtures/stored-generated-content-recovery.fixture.mjs', import.meta.url).pathname, path],
    {timeout: 30000, maxBuffer: 65536});
  assert.deepEqual(JSON.parse(second.stdout), recovered);
});

test('saved generated Content uses current authority and cannot redirect its holding', async t => {
  const value = await setup(t);
  await value.store.commitPhysicalHolding(value.holding, [value.physical.prepared]);
  const candidate = control.recoveryCandidate(value.description.wire, value.binding, limits);
  assert.deepEqual(control.inspect(candidate), value.description);
  assert.ok(await value.issue({candidate}));
  value.revoke();
  await assert.rejects(value.issue({candidate}), {code: 'MoonBitHostFailure'});
  await assert.rejects(value.issue({candidate, holdingCid: hash('other generation')}),
    {code: 'GeneratedContentHoldingMismatch'});
  for (const field of ['content_store_cid', 'workspace_scope_cid',
    'effective_data_policy_cid', 'availability_evidence_cid', 'issuer_contract_cid']) {
    assert.throws(() => control.recoveryCandidate(value.description.wire,
      {...value.binding, [field]: token('7')}, limits), {code: 'MoonBitHostFailure'});
  }
  assert.equal(value.store.status().storedBytes, 3);
  await value.store.retirePhysicalHolding(value.holding.holding_cid);
  assert.equal(value.store.status().storedBytes, 0);
  await assert.rejects(value.issue({candidate}), {code: 'GeneratedContentHoldingMismatch'});
});

test('generated Content is issued only after exact physical custody is durable', async t => {
  const value = await setup(t);
  await assert.rejects(value.issue(), {code: 'GeneratedContentHoldingMismatch'});
  assert.equal(value.authorityChecks(), 0);
  assert.equal(value.physical.prepared.status().pending, true);
  await value.store.commitPhysicalHolding(value.holding, [value.physical.prepared]);
  assert.ok(await value.issue());
  assert.equal(value.authorityChecks(), 1);
  const chunks = [];
  await value.store.consumePhysicalHolding(value.holding.holding_cid, 0,
    chunk => chunks.push(Buffer.from(chunk)));
  assert.equal(Buffer.concat(chunks).toString(), 'id\n');
  value.revoke();
  await assert.rejects(value.issue(), {code: 'MoonBitHostFailure'});
  assert.equal(value.store.status().storedBytes, 3);
  value.invalidate();
  await assert.rejects(value.issue(), {code: 'GeneratedContentHoldingUnavailable'});
  await value.store.retirePhysicalHolding(value.holding.holding_cid);
  assert.equal(value.store.status().storedBytes, 0);
});

test('generated Content rejects wrong scope policy and holding without discarding custody', async t => {
  const value = await setup(t);
  await value.store.commitPhysicalHolding(value.holding, [value.physical.prepared]);
  for (const overrides of [
    {workspaceScopeCid: token('7')}, {effectiveDataPolicyCid: token('7')},
    {holdingCid: hash('another holding')},
  ]) {
    await assert.rejects(value.issue(overrides), error =>
      ['GeneratedContentBindingMismatch', 'GeneratedContentHoldingMismatch'].includes(error.code));
    assert.equal(value.authorityChecks(), 0);
    assert.equal(value.store.status().storedBytes, 3);
  }
  assert.throws(() => control.inspect({}), /Foreign Content candidate/u);
  assert.throws(() => control.candidate(value.encoder,
    {...value.binding, extra: true}, limits), {code: 'MoonBitHostFailure'});
  assert.throws(() => control.candidate(value.encoder,
    {...value.binding, expires_at: null}, limits), {code: 'MoonBitHostFailure'});
  await value.store.retirePhysicalHolding(value.holding.holding_cid);
});

test('generated Content reconciles a lost holding commit response before issuance', async t => {
  let failSync = false;
  const value = await setup(t, {durability: directory => ({
    async syncDirectory(path) {
      if (failSync && path === join(directory, 'physical-holdings')) {
        failSync = false;
        throw Object.assign(new Error('lost holding durability response'), {code: 'EIO'});
      }
      const file = await open(path, 'r');
      try { await file.sync(); } finally { await file.close(); }
    },
  })});
  // Store startup may sync the holding directory. Arm the fault for commit.
  failSync = true;
  await assert.rejects(value.store.commitPhysicalHolding(value.holding,
    [value.physical.prepared]), {code: 'EIO'});
  assert.equal(value.physical.prepared.status().pending, true);
  assert.equal(value.authorityChecks(), 0);
  assert.ok(await value.issue());
  assert.equal(value.physical.prepared.status().pending, false);
  assert.equal(value.store.status().objectCount, 1);
  await value.store.retirePhysicalHolding(value.holding.holding_cid);
  assert.equal(value.store.status().storedBytes, 0);
});

test('generated Content failure reports consumed work and cannot issue a candidate', async t => {
  const value = await setup(t);
  try {
    const encoder = control.encoder(value.barrier, {maxRows: 1, maxBytes: 2,
      maxValueNodes: 100, maxValueDepth: 8, maxFrames: 20});
    const failed = control.advance(encoder, 64);
    assert.equal(failed.ready, false);
    assert.notEqual(failed.issue, undefined);
    assert.ok(failed.work > 0 && failed.work <= 64);
    assert.throws(() => control.finish(encoder), {code: 'MoonBitHostFailure'});
    assert.throws(() => control.candidate(encoder, value.binding, limits),
      {code: 'MoonBitHostFailure'});
    assert.equal(value.authorityChecks(), 0);
    // The failing encoder does not refund another generation's prepared bytes
    // or turn its provisional candidate into an issued reference.
    assert.equal(value.physical.prepared.status().pending, true);
    assert.equal(value.store.status().storedBytes, 3);
  } finally {
    await value.physical.prepared.release();
  }
  assert.equal(value.store.status().storedBytes, 0);
});

test('generated Content rechecks holding authority after awaited Store confirmation', async t => {
  let afterSync;
  const value = await setup(t, {durability: directory => ({
    async syncDirectory(path) {
      const file = await open(path, 'r');
      try { await file.sync(); } finally { await file.close(); }
      if (path === join(directory, 'physical-holdings')) afterSync?.();
    },
  })});
  await value.store.commitPhysicalHolding(value.holding, [value.physical.prepared]);
  afterSync = value.invalidate;
  await assert.rejects(value.issue(), {code: 'GeneratedContentHoldingUnavailable'});
  assert.equal(value.authorityChecks(), 0);
  assert.equal(value.store.status().storedBytes, 3);
  afterSync = undefined;
  await value.store.retirePhysicalHolding(value.holding.holding_cid);
  assert.equal(value.store.status().storedBytes, 0);
});
