// Actual encrypted Store and original continuation port. The contract-control
// fixture is not Common Model admission, original Ledger restoration or send
// authority. On-disk fault injection does not prove a public Program exploit.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {openContinuationEvidence} from './local-continuation-evidence.mjs';

const wire = '{"rows":[["e\u0301",null],["é",7]],"absent":{}}';
const firstRequest = `sha256:${'1'.repeat(64)}`;
const secondRequest = `sha256:${'2'.repeat(64)}`;
const keyId = `sha256:${'3'.repeat(64)}`;

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-original-binding-'));
  const configuration = {
    stateDirectory: directory, key: Buffer.alloc(32, 7), keyId,
    contractControl: createPublicationContractControlFixture(),
    preparation: () => ({status: 'run_created', runStatus: 'needs_reconciliation'}),
    isTerminalRunOutcome: () => false,
    store: {maxObjects: 8, capacityBytes: 1024 * 1024, maxObjectBytes: 4096},
  };
  let evidence = openContinuationEvidence(configuration);
  t.after(async () => {
    await evidence.close();
    await rm(directory, {recursive: true, force: true});
  });
  const [cid] = await evidence.hold('first-original', firstRequest,
    [{name: 'captured_input', wire}]);
  const [secondCid] = await evidence.hold('second-original', secondRequest,
    [{name: 'captured_input', wire}]);
  assert.equal(cid, secondCid, 'same payload may legitimately share backing');
  const path = join(directory, 'attempts', 'first-original.json');
  const secondPath = join(directory, 'attempts', 'second-original.json');
  const original = JSON.parse(await readFile(path, 'utf8'));
  const second = JSON.parse(await readFile(secondPath, 'utf8'));
  assert.notEqual(original.holdings[0].holding_cid, second.holdings[0].holding_cid,
    'the two original continuation holdings are not the same custody');
  return {directory, evidence, path, original, second, cid,
    async restart() {
      await evidence.close();
      evidence = openContinuationEvidence(configuration);
      return evidence;
    }};
}

async function withoutStoreRead(directory, work) {
  const open = fs.promises.open;
  let storeOpens = 0;
  fs.promises.open = async (...args) => {
    if (String(args[0]).startsWith(join(directory, 'private-store'))) storeOpens++;
    return open(...args);
  };
  syncBuiltinESMExports();
  try {
    await work();
    assert.equal(storeOpens, 0, 'refuse before opening physical Store custody');
  } finally {
    fs.promises.open = open;
    syncBuiltinESMExports();
  }
}

test('current continuation read rejects a changed original request before Store I/O',
  async t => {
    const {directory, evidence, path, original, cid} = await fixture(t);
    const opened = await evidence.open('first-original');
    assert.equal(opened.requestCid, firstRequest);
    await writeFile(path, JSON.stringify({...original, request_cid: secondRequest}));
    await withoutStoreRead(directory, async () => {
      await assert.rejects(opened.bytes('captured_input', cid),
        {code: 'ContinuationRequestMismatch'});
    });
  });

test('current continuation read rechecks the original installation key before Store I/O',
  async t => {
    const {directory, evidence, path, original, cid} = await fixture(t);
    const opened = await evidence.open('first-original');
    await writeFile(path, JSON.stringify({...original,
      key_id: `sha256:${'4'.repeat(64)}`}));
    await withoutStoreRead(directory, async () => {
      await assert.rejects(opened.bytes('captured_input', cid),
        {code: 'PrivateEvidenceKeyMismatch'});
    });
  });

for (const openBeforeChange of [true, false]) {
  test(`foreign same-payload holding refuses ${openBeforeChange ? 'after' : 'before'} opening the original facade`,
    async t => {
      const {directory, evidence, path, original, second, cid} = await fixture(t);
      let opened = openBeforeChange ? await evidence.open('first-original') : undefined;
      // Same name, bytes, semantic CID, key and original request remain. Only
      // the physical custody was transplanted from another continuation.
      original.holdings[0].holding_cid = second.holdings[0].holding_cid;
      await writeFile(path, JSON.stringify(original));
      opened ??= await evidence.open('first-original');
      assert.deepEqual(opened.held('captured_input'), [cid]);
      await withoutStoreRead(directory, async () => {
        await assert.rejects(opened.bytes('captured_input', cid),
          {code: 'ContinuationEvidenceNotHeld'});
      });
    });
}

test('original shared payload survives Store reopen without merging holding identities or unknown custody',
  async t => {
    const value = await fixture(t);
    const reopened = await value.restart();
    for (const [id, request] of [
      ['first-original', firstRequest], ['second-original', secondRequest],
    ]) {
      const opened = await reopened.open(id);
      assert.equal(opened.requestCid, request);
      assert.deepEqual(opened.held('captured_input'), [value.cid]);
      assert.deepEqual(await opened.bytes('captured_input', value.cid,
        {maxBytes: 128}), Buffer.from(wire, 'utf8'));
    }
    assert.deepEqual(await reopened.settle(), {retired: [], pending: []});
    const current = JSON.parse(await readFile(value.path, 'utf8'));
    assert.equal(current.holdings[0].state, 'held');
    assert.equal(current.holdings[0].holding_cid, value.original.holdings[0].holding_cid);
  });

test('current retirement still refuses without returning or deleting original bytes',
  async t => {
    const {directory, evidence, path, original, cid} = await fixture(t);
    const opened = await evidence.open('first-original');
    original.holdings[0].state = 'retiring';
    await writeFile(path, JSON.stringify(original));
    await withoutStoreRead(directory, async () => {
      await assert.rejects(opened.bytes('captured_input', cid),
        {code: 'ContinuationEvidenceRetired'});
    });
    original.holdings[0].state = 'held';
    await writeFile(path, JSON.stringify(original));
    assert.deepEqual(await opened.bytes('captured_input', cid), Buffer.from(wire, 'utf8'));
  });
