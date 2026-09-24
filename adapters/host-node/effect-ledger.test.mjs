import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {canonicalJson} from
  '../host-common/publication-contract-control.fixture.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {captureClaimedEffectCollectionResponse,
  captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const authorityScopeCid = cid('a');
const scopeCid =
  'sha256:caf2d10a1c26dfe7d79caf9a0d51645d5b29ad6c73fb2c6e036a3c2b04bf02c3';
const canonical = value => JSON.stringify(Object.fromEntries(
  Object.entries(value).sort(([left], [right]) => left.localeCompare(right)),
));
const hash = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const entry = ({state = 'prepared', fence = 1, attempt = 0,
  prior = null, outcome = null, fingerprint = cid('4')} = {}) => {
  const body = {
    attempt_sequence: attempt,
    canonical_request_cid: cid('1'),
    capability: 'unavailable',
    dispatch_key: cid('2'),
    effect_preview_cid: cid('3'),
    fence,
    intent_fingerprint_cid: fingerprint,
    logical_item_locator_cid: cid('5'),
    logical_request_scope_cid: scopeCid,
    original_membership_cid: cid('7'),
    outcome_receipt_cid: outcome,
    prior_entry_cid: prior,
    recovery_contract_cid: cid('8'),
    reservation_evidence_cid: cid('9'),
    retention_contract_cid: cid('a'),
    state,
    unit_definition_cid: cid('b'),
    version: 'actql-logical-item-ledger-entry/0.1',
  };
  const entryCid = hash(canonical(body));
  return Object.freeze({cid: entryCid, wire: canonical({...body,
    self_cid: entryCid})});
};

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-ledger-control-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
}

const open = root => openEffectLedger({moon, root, authorityScopeCid,
  callerRequestId: 'request-1', maxEntryBytes: 4096});
const effect = runtimeCore(moon).effectApplicationControl;

test('logical request admission precedes durable Effect ledger creation',
  async t => {
    const root = await fixture(t);
    for (const callerRequestId of ['e\u0301', 'request\n1', 'x'.repeat(257)]) {
      assert.throws(() => openEffectLedger({moon, root, authorityScopeCid,
        callerRequestId}));
      assert.deepEqual(await readdir(root), []);
    }
    const ledger = openEffectLedger({moon, root, authorityScopeCid,
      callerRequestId: 'x'.repeat(256)});
    assert.equal(typeof ledger.scopeCid, 'string');
    ledger.close();
  });

function batchClaims() {
  const scope = effect.logicalRequestScope(authorityScopeCid,
    'request-1', 32);
  return ['row-1', 'row-2'].map(row => {
    const key = effect.dispatchKey(scope, cid('b'),
      JSON.stringify(row), 32, 8, 3);
    const locator = effect.logicalItemLocator(scope, 'program-1',
      'node-1', 'WriteOne', JSON.stringify({row}), 64, 128, 8, 3);
    const canonicalRequestCid = cid('f');
    const basis = effect.ledgerBasis(scope, locator, key,
      cid('c'), cid('d'), cid('e'), canonicalRequestCid, cid('0'),
      'unavailable', cid('1'), cid('2'));
    return {scope, locator, key, basis,
      intentFingerprintCid: cid('e'), canonicalRequestCid};
  });
}

function admittedProgressFixture(firstPolicy = 'continue') {
  const scope = effect.logicalRequestScope(authorityScopeCid,
    'request-1', 32);
  const authoring =
    'sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a';
  const rowSpecs = [
    {id: 'WriteOne', rows: ['row-1', 'row-2'], rowCids: [cid('3'), cid('4')],
      policy: firstPolicy, target: cid('1')},
    {id: 'WriteTwo', rows: ['row-3'], rowCids: [cid('5')],
      policy: 'halt', target: cid('2')},
  ];
  const effects = rowSpecs.map(({id, rows, rowCids, policy, target}) => ({
    effect_id: id, effect_kind: 'update', target: 'Object',
    mapping: 'mapping:fixture', resolved_mapping_contract_cid: cid('a'),
    effect_identity_cid: cid('a'), preview_strength: 'full_diff',
    source_binding_cid: cid('a'), capability_evidence_cid: cid('a'),
    authority_scope_cid: cid('a'),
    write_footprint: {kind: 'exact_targets',
      resource_identity_scheme_cid: cid('a'), provider_namespace: 'provider',
      provider_boundary_cid: cid('a'), resource_kind: 'Object',
      provider_object_identity_cids: [target]},
    count: rows.length, max_items: rows.length, required_permissions: ['write'],
    approval: 'none', on_item_failure: policy,
    changes: rows.map((row, index) => ({
      target_row_identity: row,
      target_guard: {state: 'version', version_cid: cid('a')},
      intended_changes: {state: 'present', value: {}},
      before: {state: 'present', value: {}},
      after: {state: 'present', value: {}},
      row_preview_cid: rowCids[index],
      row_idempotency_key: cid(String(index + (id === 'WriteOne' ? 6 : 8))),
    })),
    row_order: rowCids, effect_member_preview_cid: cid('a'), executed: false,
  }));
  const preview = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: cid('a'), program_definition_cid: cid('a'),
    invocation_cid: cid('a'), run_identity_cid: cid('a'),
    compiled_plan_cid: cid('a'), check_environment_cid: cid('a'),
    authoring_context: {version: 'actql-authoring-context/0.1',
      program_definition_cid: cid('a'), annotations: [],
      authoring_context_cid: authoring},
    barrier_provenance_cids: [], model_derived: false,
    model_task_contract_cids: [], model_invocation_evidence_cids: [],
    model_response_artifact_cids: [], effects, executed: false,
    effect_preview_cid: cid('a'),
  };
  const rowIdentities = effect.derivePreviewRowIdentities(
    canonicalJson(preview), 16384, 512, 12);
  for (let index = 0; index < effects.length; index++) {
    effects[index].row_order = rowIdentities[index];
    effects[index].changes.forEach((change, row) => {
      change.row_preview_cid = rowIdentities[index][row];
    });
  }
  const identities = effect.derivePreviewIdentities(
    canonicalJson(preview), 16384, 512, 12);
  for (let index = 0; index < effects.length; index++) {
    effects[index].effect_member_preview_cid = identities[index + 1];
  }
  preview.effect_preview_cid = effect.derivePreviewIdentities(
    canonicalJson(preview), 16384, 512, 12)[0];
  const claims = rowSpecs.map(({id, rows}) => rows.map(row => {
    const correlation = JSON.stringify(row);
    const key = effect.dispatchKey(scope, preview.effect_preview_cid,
      correlation, 32, 8, 3);
    const locator = effect.logicalItemLocator(scope, 'program-1',
      'node-1', id, correlation, 64, 128, 8, 3);
    const canonicalRequestCid = cid('f');
    const basis = effect.ledgerBasis(scope, locator, key,
      cid('c'), cid('d'), cid('e'), canonicalRequestCid, cid('0'),
      'unavailable', cid('1'), cid('2'));
    return {scope, locator, key, basis,
      intentFingerprintCid: cid('e'), canonicalRequestCid};
  }));
  for (let member = 0; member < claims.length; member++) {
    for (let row = 0; row < claims[member].length; row++) {
      effects[member].changes[row].row_idempotency_key =
        effect.dispatchKeyCid(claims[member][row].key);
    }
  }
  const admitted = effect.admitPreviewIdentity(
    canonicalJson(preview), cid('a'), authoring, scope,
    claims.map(rows => rows.map(claim => claim.key)), 16384, 512, 12);
  return {admitted, members: claims.map(rows => ({claims: rows})), claims};
}

test('saved response issues one exact terminal row Receipt before Ledger head',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    const {admitted, claims} = admittedProgressFixture();
    const claim = claims[0][0];
    const sent = await captureClaimedEffectResponse({
      ledger, claim, requestCid: claim.canonicalRequestCid,
      execute: async () => ({observation: {
        useCid: cid('4'), statusCode: 201,
        body: Buffer.from('{"success":true}'),
      }}),
    });
    assert.equal(ledger.readClaimedOutcome(claim), undefined);
    assert.throws(() => ledger.recordAdmittedRowOutcome({
      claim, preview: admitted, memberIndex: 0, previewRowIndex: 1,
      outcomeWire: '{"result":{"id":"a001"},"state":"applied"}',
    }), {code: 'MoonBitHostFailure'});
    const recorded = ledger.recordAdmittedRowOutcome({
      claim, preview: admitted, memberIndex: 0, previewRowIndex: 0,
      outcomeWire: '{"result":{"id":"a001"},"state":"applied"}',
    });
    assert.equal(recorded.custody.created, true);
    assert.equal(JSON.parse(recorded.receipt.wire).dispatch_entry_cid,
      effect.ledgerEntryCid(sent.ownership.dispatching));
    assert.equal(ledger.recordAdmittedRowOutcome({
      claim, preview: admitted, memberIndex: 0, previewRowIndex: 0,
      outcomeWire: '{"result":{"id":"a001"},"state":"applied"}',
    }).custody.created, false);
    const firstUnknown = effect.issueNextLedgerEntry(
      sent.ownership.dispatching, 'unknown', '', 4096, 64, 4);
    ledger.append(effect.ledgerEntryWire(firstUnknown));
    const secondUnknown = effect.issueNextLedgerEntry(
      firstUnknown, 'unknown', '', 4096, 64, 4);
    ledger.append(effect.ledgerEntryWire(secondUnknown));
    assert.equal(ledger.commitAdmittedRowOutcome({
      claim, preview: admitted, memberIndex: 0, previewRowIndex: 0,
    }).transition.created, true);
    assert.equal(ledger.commitAdmittedRowOutcome({
      claim, preview: admitted, memberIndex: 0, previewRowIndex: 0,
    }).transition.created, false);
    ledger.close();
    const restarted = open(root);
    t.after(() => restarted.close());
    assert.equal(restarted.readClaimedOutcome(claim).outcomeCid,
      recorded.receipt.identity);
    assert.equal(restarted.readClaimedOutcome(claim).outcomeJson,
      recorded.receipt.wire);
  });

test('durable row heads determine multi-member progress after restart',
  async t => {
    const root = await fixture(t);
    const first = open(root);
    t.after(() => first.close());
    const {admitted, members, claims} = admittedProgressFixture();
    const firstMember = claims[0];
    const ready = ledger => {
      const frontier = ledger.frontierFromDurableHeads(admitted, members, 48);
      return Array.from({length: effect.setFrontierReadyCount(frontier)},
        (_, index) => [effect.setFrontierReadyMember(frontier, index),
          effect.setFrontierReadyRow(frontier, index)]);
    };
    assert.deepEqual(ready(first), [[0, 0], [1, 0]]);
    const ownership = first.claimDispatch(firstMember[0]);
    assert.equal(ownership.claimed, true);
    // A durable claim alone is possible dispatch, not an active call.
    assert.deepEqual(ready(first), [[0, 1], [1, 0]]);
    const unknown = effect.issueNextLedgerEntry(ownership.dispatching,
      'unknown', '', 4096, 64, 4);
    first.append(effect.ledgerEntryWire(unknown));
    assert.deepEqual(ready(first), [[0, 1], [1, 0]]);
    first.close();
    const restarted = open(root);
    t.after(() => restarted.close());
    assert.deepEqual(ready(restarted), [[0, 1], [1, 0]]);
    const continued = restarted.frontierFromDurableHeads(
      admitted, members, 48);
    assert.deepEqual(Array.from({length: effect.setFrontierReadyCount(continued)},
      (_, index) => [effect.setFrontierReadyMember(continued, index),
        effect.setFrontierReadyRow(continued, index)]),
    [[0, 1], [1, 0]]);
    assert.equal(effect.setFrontierOutcome(continued), 0);
    const scope = firstMember[0].scope;
    const canonicalRequestCid = firstMember[0].canonicalRequestCid;
    const foreign = {...firstMember[0],
      basis: effect.ledgerBasis(scope, firstMember[0].locator,
        firstMember[0].key, cid('9'), cid('d'), cid('e'),
        canonicalRequestCid, cid('0'), 'unavailable', cid('1'), cid('2'))};
    assert.throws(() => restarted.frontierFromDurableHeads(admitted, [
      {claims: [foreign, firstMember[1]]}, members[1],
    ], 48), {code: 'MoonBitHostFailure'});
    assert.throws(() => restarted.frontierFromDurableHeads(admitted, [
      {claims: [firstMember[0], firstMember[0]]}, members[1],
    ], 48), {code: 'EffectProgressDuplicateLocator'});
    assert.throws(() => restarted.frontierFromDurableHeads(admitted, [
      members[1], members[0],
    ], 48), {code: 'MoonBitHostFailure'});
    assert.throws(() => restarted.frontierFromDurableHeads(admitted, [
      members[0],
    ], 48), {code: 'MoonBitHostFailure'});
  });

test('one Collections claim remains possible dispatch after restart',
  async t => {
    const root = await fixture(t);
    const first = open(root);
    t.after(() => first.close());
    const {admitted, members, claims} = admittedProgressFixture();
    const ownership = first.claimDispatchBatch(claims[0]);
    assert.equal(ownership.claimed, true);
    assert.equal(ownership.dispatching.length, 2);
    const progress = ledger => {
      const frontier = ledger.frontierFromDurableHeads(admitted, members, 48);
      return {outcome: effect.setFrontierOutcome(frontier),
        ready: Array.from({length: effect.setFrontierReadyCount(frontier)},
          (_, index) => [effect.setFrontierReadyMember(frontier, index),
            effect.setFrontierReadyRow(frontier, index)])};
    };
    assert.deepEqual(progress(first), {outcome: 0, ready: [[1, 0]]});
    first.close();
    const restarted = open(root);
    t.after(() => restarted.close());
    assert.deepEqual(progress(restarted), {outcome: 0, ready: [[1, 0]]});
    const retry = restarted.claimDispatchBatch(claims[0]);
    assert.equal(retry.claimed, false);
    assert.deepEqual(retry.actions, [3, 3]);
    assert.deepEqual(progress(restarted), {outcome: 0, ready: [[1, 0]]});
    const applied = effect.issueNextLedgerEntry(ownership.dispatching[0],
      'applied', cid('7'), 4096, 64, 4);
    restarted.append(effect.ledgerEntryWire(applied));
    assert.deepEqual(progress(restarted), {outcome: 0, ready: [[1, 0]]});
    const unknown = effect.issueNextLedgerEntry(ownership.dispatching[1],
      'unknown', '', 4096, 64, 4);
    restarted.append(effect.ledgerEntryWire(unknown));
    assert.deepEqual(progress(restarted), {outcome: 0, ready: [[1, 0]]});
    const independent = restarted.claimDispatch(claims[1][0]);
    assert.equal(independent.claimed, true);
    const completed = effect.issueNextLedgerEntry(independent.dispatching,
      'applied', cid('8'), 4096, 64, 4);
    restarted.append(effect.ledgerEntryWire(completed));
    assert.deepEqual(progress(restarted), {outcome: 3, ready: []});
  });

test('physical flight is distinct from durable possible-dispatch', async t => {
  const root = await fixture(t);
  const first = open(root);
  const other = open(root);
  t.after(() => first.close());
  t.after(() => other.close());
  const {admitted, members, claims} = admittedProgressFixture();
  const ready = ledger => {
    const frontier = ledger.frontierFromDurableHeads(admitted, members, 48);
    return Array.from({length: effect.setFrontierReadyCount(frontier)},
      (_, index) => [effect.setFrontierReadyMember(frontier, index),
        effect.setFrontierReadyRow(frontier, index)]);
  };
  let entered;
  let release;
  const started = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  const call = captureClaimedEffectResponse({
    ledger: first,
    claim: claims[0][0],
    requestCid: claims[0][0].canonicalRequestCid,
    execute: async () => {
      entered();
      await gate;
      throw new Error('response lost');
    },
  });
  await started;
  assert.deepEqual(ready(first), [[1, 0]]);
  assert.deepEqual(ready(other), [[1, 0]]);
  release();
  await assert.rejects(call, /response lost/);
  assert.deepEqual(ready(first), [[0, 1], [1, 0]]);
  first.close();
  const restarted = open(root);
  t.after(() => restarted.close());
  assert.deepEqual(ready(restarted), [[0, 1], [1, 0]]);
  const retry = restarted.claimDispatch(claims[0][0]);
  assert.equal(retry.claimed, false);
  assert.equal(retry.action, 3);
});

test('lost Collections reply preserves independent member progress', async t => {
  const root = await fixture(t);
  const ledger = open(root);
  t.after(() => ledger.close());
  const {admitted, members, claims} = admittedProgressFixture();
  const frontier = current =>
    current.frontierFromDurableHeads(admitted, members, 48);
  const ready = value => Array.from({
    length: effect.setFrontierReadyCount(value),
  }, (_, index) => [effect.setFrontierReadyMember(value, index),
    effect.setFrontierReadyRow(value, index)]);
  let entered;
  let release;
  const started = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  let sends = 0;
  const execute = async () => {
    sends += 1;
    entered();
    await gate;
    throw new Error('collection reply lost');
  };
  const call = captureClaimedEffectCollectionResponse({
    ledger, claims: claims[0],
    requestCid: claims[0][0].canonicalRequestCid,
    execute,
  });
  await started;
  assert.deepEqual(ready(frontier(ledger)), [[1, 0]]);
  assert.equal(sends, 1);
  release();
  await assert.rejects(call, /collection reply lost/);
  assert.deepEqual(ready(frontier(ledger)), [[1, 0]]);
  const independent = ledger.claimDispatch(claims[1][0]);
  assert.equal(independent.claimed, true);
  const applied = effect.issueNextLedgerEntry(independent.dispatching,
    'applied', cid('8'), 4096, 64, 4);
  ledger.append(effect.ledgerEntryWire(applied));
  assert.equal(effect.setFrontierOutcome(frontier(ledger)), 3);
  ledger.close();
  const restarted = open(root);
  t.after(() => restarted.close());
  assert.equal(effect.setFrontierOutcome(frontier(restarted)), 3);
  const retry = await captureClaimedEffectCollectionResponse({
    ledger: restarted, claims: claims[0],
    requestCid: claims[0][0].canonicalRequestCid,
    execute,
  });
  assert.equal(retry.claimed, false);
  assert.deepEqual(retry.ownership.actions, [3, 3]);
  assert.equal(sends, 1);
});

test('admitted Preview fixes halt policy and rejects foreign row bindings',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    const {admitted, members, claims} = admittedProgressFixture('halt');
    const ready = () => {
      const frontier = ledger.frontierFromDurableHeads(admitted, members, 48);
      return Array.from({length: effect.setFrontierReadyCount(frontier)},
        (_, index) => [effect.setFrontierReadyMember(frontier, index),
          effect.setFrontierReadyRow(frontier, index)]);
    };
    assert.deepEqual(ready(), [[0, 0], [1, 0]]);
    const ownership = ledger.claimDispatch(claims[0][0]);
    const unknown = effect.issueNextLedgerEntry(ownership.dispatching,
      'unknown', '', 4096, 64, 4);
    ledger.append(effect.ledgerEntryWire(unknown));
    assert.deepEqual(ready(), [[1, 0]]);
    const foreign = admittedProgressFixture('continue');
    assert.throws(() => ledger.frontierFromDurableHeads(
      foreign.admitted, members, 48), {code: 'MoonBitHostFailure'});
    assert.throws(() => ledger.frontierFromDurableHeads(
      admitted, [{claims: [claims[0][1], claims[0][0]]}, members[1]], 48),
    {code: 'MoonBitHostFailure'});
  });

test('one collection request claims every row before physical I/O',
  async t => {
    const root = await fixture(t);
    const first = open(root);
    const concurrent = open(root);
    t.after(() => first.close());
    t.after(() => concurrent.close());
    const claims = batchClaims();
    const ownership = first.claimDispatchBatch(claims);
    assert.equal(ownership.claimed, true);
    assert.deepEqual(ownership.actions, [0, 0]);
    for (let index = 0; index < claims.length; index++) {
      const claim = claims[index];
      const locatorCid = effect.logicalItemLocatorCid(claim.locator);
      assert.equal(first.current(locatorCid).revision, 2);
      assert.equal(effect.ledgerEntryAdmitsDispatch(
        ownership.dispatching[index], claim.scope, claim.locator,
        claim.key, claim.canonicalRequestCid), true);
    }
    const responseBytes = Buffer.from('[{"success":true},{"success":false}]');
    const observation = {claims, ownership, credentialUseCid: cid('4'),
      statusCode: 200, responseBytes};
    assert.equal(first.recordBatchResponse(observation).created, true);
    assert.equal(concurrent.recordBatchResponse(observation).created, false);
    assert.throws(() => first.recordBatchResponse({
      ...observation, responseBytes: Buffer.from('[]'),
    }), {code: 'EffectPhysicalResponseCollision'});
    const retry = concurrent.claimDispatchBatch(claims);
    assert.equal(retry.claimed, false);
    assert.deepEqual(retry.actions, [3, 3]);
    first.close();
    concurrent.close();
    const restarted = open(root);
    t.after(() => restarted.close());
    assert.deepEqual(restarted.claimDispatchBatch(claims).actions, [3, 3]);
    assert.deepEqual(claims.map(claim => restarted.history(
      effect.logicalItemLocatorCid(claim.locator), 2).length), [2, 2]);
    for (const dispatching of ownership.dispatching) {
      const saved = restarted.response(effect.ledgerEntryCid(dispatching));
      assert.deepEqual(saved.responseBytes, responseBytes);
      assert.equal(saved.credentialUseCid, cid('4'));
    }
  });

test('collection claim never leaves a partial send when one row conflicts',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    const claims = batchClaims();
    const foreignBasis = effect.ledgerBasis(
      claims[1].scope, claims[1].locator, claims[1].key,
      cid('9'), cid('d'), cid('e'), cid('f'), cid('0'),
      'unavailable', cid('1'), cid('2'));
    const foreign = effect.issuePreparedLedgerEntry(
      foreignBasis, 4096, 64, 4);
    ledger.append(effect.ledgerEntryWire(foreign));
    assert.throws(() => ledger.claimDispatchBatch(claims),
      {code: 'EffectLedgerIntentConflict'});
    assert.equal(ledger.current(
      effect.logicalItemLocatorCid(claims[0].locator)), undefined);
    assert.equal(ledger.current(
      effect.logicalItemLocatorCid(claims[1].locator)).revision, 1);
    assert.throws(() => ledger.claimDispatchBatch([
      claims[0], claims[0],
    ]), {code: 'EffectLedgerBatchBindingMismatch'});
    assert.throws(() => ledger.claimDispatchBatch([
      claims[0], {...claims[1], key: claims[0].key},
    ]), {code: 'EffectLedgerBatchBindingMismatch'});
    assert.equal(ledger.current(
      effect.logicalItemLocatorCid(claims[0].locator)), undefined);
  });

test('collection cannot combine rows from different Effect members',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    const claims = batchClaims();
    const second = claims[1];
    const foreignLocator = effect.logicalItemLocator(
      second.scope, 'program-1', 'node-1', 'WriteTwo',
      JSON.stringify({row: 'row-2'}), 64, 128, 8, 3);
    const foreignBasis = effect.ledgerBasis(
      second.scope, foreignLocator, second.key,
      cid('c'), cid('d'), cid('e'), second.canonicalRequestCid,
      cid('0'), 'unavailable', cid('1'), cid('2'));
    assert.throws(() => ledger.claimDispatchBatch([
      claims[0], {...second, locator: foreignLocator, basis: foreignBasis},
    ]), {code: 'EffectLedgerBatchBindingMismatch'});
    const foreignKey = effect.dispatchKey(
      second.scope, cid('8'), JSON.stringify('row-2'), 32, 8, 3);
    const foreignPreviewBasis = effect.ledgerBasis(
      second.scope, second.locator, foreignKey,
      cid('c'), cid('d'), cid('e'), second.canonicalRequestCid,
      cid('0'), 'unavailable', cid('1'), cid('2'));
    assert.throws(() => ledger.claimDispatchBatch([
      claims[0], {...second, key: foreignKey, basis: foreignPreviewBasis},
    ]), {code: 'EffectLedgerBatchBindingMismatch'});
    for (const claim of claims) {
      assert.equal(ledger.current(
        effect.logicalItemLocatorCid(claim.locator)), undefined);
    }
  });

test('a previously dispatched row prevents a partial collection retry',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    const claims = batchClaims();
    assert.equal(ledger.claimDispatch(claims[0]).claimed, true);
    assert.deepEqual(ledger.claimDispatchBatch(claims), {
      claimed: false, actions: [3, 0],
    });
    assert.equal(ledger.current(
      effect.logicalItemLocatorCid(claims[1].locator)), undefined);
  });

test('collection claim reserves aggregate entry capacity before any row',
  async t => {
    const root = await fixture(t);
    const ledger = openEffectLedger({moon, root, authorityScopeCid,
      callerRequestId: 'request-1', maxEntryBytes: 4096, maxEntries: 3});
    t.after(() => ledger.close());
    const claims = batchClaims();
    assert.throws(() => ledger.claimDispatchBatch(claims),
      {code: 'EffectLedgerCapacityExceeded'});
    for (const claim of claims) {
      assert.equal(ledger.current(
        effect.logicalItemLocatorCid(claim.locator)), undefined);
    }
    assert.equal(ledger.claimDispatchBatch([claims[0]]).claimed, true);
  });

test('MoonBit-issued prepared and dispatching entries are durable before use',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    const scope = effect.logicalRequestScope(authorityScopeCid,
      'request-1', 32);
    const key = effect.dispatchKey(scope, cid('b'), '"row-1"', 32, 8, 3);
    const locator = effect.logicalItemLocator(scope, 'program-1', 'node-1',
      'WriteOne', '{"row":"record-1"}', 64, 128, 8, 3);
    const basis = effect.ledgerBasis(scope, locator, key,
      cid('c'), cid('d'), cid('e'), cid('f'), cid('0'), 'unavailable',
      cid('1'), cid('2'));
    assert.equal(effect.recoveryActionFromEntry(
      locator, cid('e'), key, cid('f'),
      ledger.currentAdmitted(effect.logicalItemLocatorCid(locator)), false), 0);
    const prepared = effect.issuePreparedLedgerEntry(basis, 4096, 64, 3);
    assert.equal(ledger.append(effect.ledgerEntryWire(prepared)).created, true);
    assert.equal(effect.ledgerEntryAdmitsDispatch(prepared, scope, locator,
      key, cid('f')), false);
    const dispatching = effect.issueNextLedgerEntry(prepared, 'dispatching',
      '', 4096, 64, 3);
    assert.equal(ledger.append(effect.ledgerEntryWire(dispatching)).created,
      true);
    assert.equal(effect.ledgerEntryAdmitsDispatch(dispatching, scope, locator,
      key, cid('f')), true);
    assert.equal(effect.ledgerEntryAdmitsDispatch(dispatching, scope, locator,
      key, cid('9')), false);
    const response = {
      dispatching, scope, locator, key,
      canonicalRequestCid: cid('f'),
      credentialUseCid: cid('a'),
      statusCode: 201,
      responseBytes: Buffer.from('{"success":true}'),
    };
    assert.equal(ledger.recordResponse(response).created, true);
    assert.equal(ledger.recordResponse(response).created, false);
    assert.throws(() => ledger.recordResponse({
      ...response, canonicalRequestCid: cid('9'),
    }), {code: 'EffectDispatchBindingMismatch'});
    ledger.close();
    const restarted = open(root);
    t.after(() => restarted.close());
    assert.equal(restarted.current(effect.logicalItemLocatorCid(locator)).entryCid,
      effect.ledgerEntryCid(dispatching));
    assert.equal(effect.recoveryActionFromEntry(
      locator, cid('e'), key, cid('f'),
      restarted.currentAdmitted(effect.logicalItemLocatorCid(locator)), false),
    3);
    assert.deepEqual(restarted.response(effect.ledgerEntryCid(dispatching))
      .responseBytes, response.responseBytes);
  });

test('exact Effect dispatch claim sends once and restart requires reconciliation',
  async t => {
    const root = await fixture(t);
    const first = open(root);
    const second = open(root);
    t.after(() => first.close());
    t.after(() => second.close());
    const scope = effect.logicalRequestScope(authorityScopeCid,
      'request-1', 32);
    const key = effect.dispatchKey(scope, cid('b'), '"row-1"', 32, 8, 3);
    const locator = effect.logicalItemLocator(scope, 'program-1', 'node-1',
      'WriteOne', '{"row":"record-1"}', 64, 128, 8, 3);
    const basis = effect.ledgerBasis(scope, locator, key,
      cid('c'), cid('d'), cid('e'), cid('f'), cid('0'), 'unavailable',
      cid('1'), cid('2'));
    const claim = {
      scope, locator, key, basis,
      intentFingerprintCid: cid('e'),
      canonicalRequestCid: cid('f'),
    };
    const initial = first.claimDispatch(claim);
    assert.equal(initial.claimed, true);
    assert.equal(initial.action, 1);
    assert.equal(second.claimDispatch(claim).claimed, false);
    assert.equal(second.claimDispatch(claim).action, 3);
    assert.equal(first.current(effect.logicalItemLocatorCid(locator)).revision,
      2);
    const unknown = effect.issueNextLedgerEntry(initial.dispatching,
      'unknown', '', 4096, 64, 3);
    assert.equal(first.append(effect.ledgerEntryWire(unknown)).created, true);
    first.recordResponse({
      dispatching: initial.dispatching,
      scope, locator, key, canonicalRequestCid: cid('f'),
      credentialUseCid: cid('a'), statusCode: 201,
      responseBytes: Buffer.from('{"success":true}'),
    });
    first.close();
    const restarted = open(root);
    t.after(() => restarted.close());
    const afterRestart = restarted.claimDispatch(claim);
    assert.equal(afterRestart.claimed, false);
    assert.equal(afterRestart.action, 4);
    assert.deepEqual(restarted.response(
      effect.ledgerEntryCid(initial.dispatching)).responseBytes,
      Buffer.from('{"success":true}'));
    const changedBasis = effect.ledgerBasis(scope, locator, key,
      cid('9'), cid('d'), cid('e'), cid('f'), cid('0'), 'unavailable',
      cid('1'), cid('2'));
    assert.throws(() => restarted.claimDispatch({
      ...claim, basis: changedBasis,
    }), {code: 'EffectLedgerIntentConflict'});
  });

test('MoonBit-admitted Effect facts survive restart without duplicate send',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    assert.equal(ledger.scopeCid, scopeCid);
    const prepared = entry();
    const dispatching = entry({state: 'dispatching', fence: 2, attempt: 1,
      prior: prepared.cid});
    const applied = entry({state: 'applied', fence: 3, attempt: 1,
      prior: dispatching.cid, outcome: cid('c')});
    assert.equal(ledger.append(prepared.wire).created, true);
    assert.equal(ledger.append(prepared.wire).created, false);
    assert.equal(ledger.append(dispatching.wire).created, true);
    assert.equal(ledger.append(applied.wire).created, true);
    ledger.close();
    const reopened = open(root);
    t.after(() => reopened.close());
    assert.equal(reopened.current(cid('5')).entryCid, applied.cid);
    assert.deepEqual(reopened.history(cid('5'), 3).map(row => row.entryCid),
      [prepared.cid, dispatching.cid, applied.cid]);
    assert.equal(reopened.append(applied.wire).created, false);
    assert.throws(() => reopened.append(dispatching.wire), {
      code: 'EffectLedgerInvalidTransition',
    });
  });

test('Effect ledger rejects altered intent before CAS and preserves head',
  async t => {
    const root = await fixture(t);
    const ledger = open(root);
    t.after(() => ledger.close());
    const prepared = entry();
    ledger.append(prepared.wire);
    const changed = entry({state: 'dispatching', fence: 2, attempt: 1,
      prior: prepared.cid, fingerprint: cid('f')});
    assert.throws(() => ledger.append(changed.wire), {
      code: 'EffectLedgerInvalidTransition',
    });
    assert.equal(ledger.current(cid('5')).entryCid, prepared.cid);
    const malformed = prepared.wire.replace(cid('4'), cid('f'));
    assert.throws(() => ledger.append(malformed));
    assert.equal(ledger.current(cid('5')).entryCid, prepared.cid);
  });

test('one authority Store does not expose another logical request',
  async t => {
    const root = await fixture(t);
    const original = open(root);
    const other = openEffectLedger({moon, root, authorityScopeCid,
      callerRequestId: 'request-2', maxEntryBytes: 4096});
    t.after(() => original.close());
    t.after(() => other.close());
    const prepared = entry();
    original.append(prepared.wire);
    assert.throws(() => other.current(cid('5')), {
      code: 'EffectLedgerScopeMismatch',
    });
    assert.throws(() => other.append(prepared.wire), {
      code: 'EffectLedgerScopeMismatch',
    });
  });
