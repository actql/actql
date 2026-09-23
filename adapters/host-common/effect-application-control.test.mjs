import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
import {canonicalJson} from './publication-contract-control.fixture.mjs';

const effect = runtimeCore(moon).effectApplicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;

test('standard Host bridge uses the portable logical Effect identities', () => {
  const scope = effect.logicalRequestScope(cid('a'), 'request-1', 32);
  assert.equal(effect.logicalRequestScopeCid(scope),
    'sha256:caf2d10a1c26dfe7d79caf9a0d51645d5b29ad6c73fb2c6e036a3c2b04bf02c3');
  const key = effect.dispatchKey(scope, cid('b'), '"row-1"', 32, 8, 3);
  assert.equal(effect.dispatchKeyCid(key),
    'sha256:753d888dba41f4ce14250676698394baa4a7a84c73eb301b35a86fc406de1e72');
  const locator = effect.logicalItemLocator(scope, 'program-1', 'node-1',
    'WriteOne', '{"row":"record-1"}', 64, 128, 8, 3);
  assert.equal(effect.logicalItemLocatorCid(locator),
    'sha256:520a95693be3ea215833d19ee217dee53afbc614c3a0accf594e80eed2a38ade');
  const apply = effect.applyKey(scope, cid('b'), 'WriteOne', cid('c'), 64);
  assert.equal(effect.applyKeyCid(apply),
    'sha256:6991293dfeef8207f1bc472049ceabd4ffdf4b33afea9ca8d8bb9fb31bfcc961');
  assert.equal(effect.recoveryAction(locator, cid('d'), key, cid('c'),
    '', '', '', '', -1, false), 0);
  assert.equal(effect.recoveryAction(locator, cid('d'), key, cid('c'),
    effect.logicalItemLocatorCid(locator), cid('d'),
    effect.dispatchKeyCid(key), cid('c'), 1, false), 3);
  assert.equal(effect.recoveryAction(locator, cid('d'), key, cid('e'),
    effect.logicalItemLocatorCid(locator), cid('d'),
    effect.dispatchKeyCid(key), cid('c'), 2, false), 8);
  assert.equal(effect.recoveryAction(locator, cid('e'), key, cid('c'),
    effect.logicalItemLocatorCid(locator), cid('d'),
    effect.dispatchKeyCid(key), cid('c'), 2, false), 8);
});

test('Effect Set frontier keeps member order independent of row halt', () => {
  const frontier = effect.setFrontier(
    ['first', 'second'],
    [0, 1],
    [[2, 4, 0], [5, 0]],
    2, 5, 24,
  );
  assert.equal(effect.setFrontierOutcome(frontier), 0);
  assert.equal(effect.setFrontierReadyCount(frontier), 1);
  assert.equal(effect.setFrontierReadyMember(frontier, 0), 1);
  assert.equal(effect.setFrontierReadyRow(frontier, 0), 1);
});

test('Host bridge distinguishes halted rows from one in-flight collection', () => {
  for (const later of [1, 2, 3, 4, 5]) {
    assert.throws(() => effect.setFrontier(
      ['first'], [0], [[1, later]], 1, 2, 8,
    ));
  }
  for (const later of [1, 2, 3, 4, 5]) {
    const pending = effect.setFrontier(
      ['first', 'second'], [1, 0], [[1, later, 0], [0]],
      2, 4, 16,
    );
    assert.equal(effect.setFrontierOutcome(pending), 0);
    assert.equal(effect.setFrontierReadyCount(pending), 1);
    assert.equal(effect.setFrontierReadyMember(pending, 0), 1);
  }
  assert.throws(() => effect.setFrontier(
    ['first'], [1], [[0, 1]], 1, 2, 8,
  ));
  const valid = effect.setFrontier(
    ['first'], [1], [[5, 1, 0]], 1, 3, 8,
  );
  assert.equal(effect.setFrontierReadyCount(valid), 0);
  assert.equal(effect.setFrontierOutcome(valid), 0);
});

test('Host bridge rejects conflicting Effect members before mutation', () => {
  const input = (targets, kinds = [0, 0], boundaries = [cid('a'), cid('a')]) => [
    ['first', 'second'], kinds,
    ['provider', 'provider'], boundaries,
    [cid('b'), cid('b')], ['Record', 'Record'], targets,
    2, 2, 20,
  ];
  assert.equal(effect.checkSetFootprintConflicts(...input([[cid('1')], [cid('2')]])),
    true);
  assert.throws(() => effect.checkSetFootprintConflicts(...input([
    [cid('1')], [cid('1')],
  ])));
  assert.throws(() => effect.checkSetFootprintConflicts(...input([
    [], [cid('2')],
  ], [1, 0])));
  assert.equal(effect.checkSetFootprintConflicts(...input([
    [], [cid('2')],
  ], [1, 0], [cid('a'), cid('c')])), true);
});

test('Host derives set conflicts from the closed private Preview shape', () => {
  const member = (effectId, target) => ({
    effect_id: effectId,
    effect_kind: 'update',
    target: 'Object',
    mapping: 'mapping:fixture',
    resolved_mapping_contract_cid: cid('a'),
    effect_identity_cid: cid('a'),
    preview_strength: 'full_diff',
    source_binding_cid: cid('a'),
    capability_evidence_cid: cid('a'),
    authority_scope_cid: cid('a'),
    write_footprint: {
      kind: 'exact_targets',
      resource_identity_scheme_cid: cid('a'),
      provider_namespace: 'provider',
      provider_boundary_cid: cid('a'),
      resource_kind: 'Object',
      provider_object_identity_cids: [target],
    },
    count: 0,
    max_items: 1,
    required_permissions: ['write'],
    approval: 'none',
    on_item_failure: 'halt',
    changes: [],
    row_order: [],
    effect_member_preview_cid: cid('a'),
    executed: false,
  });
  const preview = effects => canonicalJson({
    version: 'actql-effect-preview/0.1',
    sensitivity: 'private',
    retention_class: 'authority-evidence',
    encryption_required: true,
    program_semantics_cid: cid('a'),
    program_definition_cid: cid('a'),
    invocation_cid: cid('a'),
    run_identity_cid: cid('a'),
    compiled_plan_cid: cid('a'),
    check_environment_cid: cid('a'),
    authoring_context: {
      version: 'actql-authoring-context/0.1',
      program_definition_cid: cid('a'),
      annotations: [],
      authoring_context_cid: cid('a'),
    },
    barrier_provenance_cids: [],
    model_derived: false,
    model_task_contract_cids: [],
    model_invocation_evidence_cids: [],
    model_response_artifact_cids: [],
    effects,
    executed: false,
    effect_preview_cid: cid('a'),
  });
  const inventory = [['second', 'first'], [1, 0], [cid('a'), cid('a')]];
  const second = {...member('second', cid('2')), on_item_failure: 'continue'};
  const limits = [8192, 256, 12, 2, 2, 100];
  assert.equal(effect.checkPreviewFootprintConflicts(preview([
    member('first', cid('1')), second,
  ]), ...inventory, ...limits), true);
  assert.throws(() => effect.checkPreviewFootprintConflicts(preview([
    member('first', cid('1')),
    {...member('second', cid('1')), on_item_failure: 'continue'},
  ]), ...inventory, ...limits));
  assert.throws(() => effect.checkPreviewFootprintConflicts(preview([
    member('first', cid('1')), {...second, executed: true},
  ]), ...inventory, ...limits));
  assert.throws(() => effect.checkPreviewFootprintConflicts(preview([
    member('first', cid('1')), second,
  ]), ['first', 'foreign'], [0, 1], [cid('a'), cid('a')], ...limits));
  assert.throws(() => effect.checkPreviewFootprintConflicts(preview([
    member('first', cid('1')), second,
  ]), ['first', 'second'], [0, 0], [cid('a'), cid('a')], ...limits));
  assert.throws(() => effect.checkPreviewFootprintConflicts(preview([
    member('first', cid('1')),
    {...second, effect_identity_cid: cid('b')},
  ]), ...inventory, ...limits));
});

test('Host bridge admits Effect Preview identity and exact apply key', () => {
  const scope = effect.logicalRequestScope(cid('a'), 'request-1', 32);
  const authoring = 'sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a';
  const member = {
    effect_id: 'write', effect_kind: 'update', target: 'Object',
    mapping: 'mapping:fixture', resolved_mapping_contract_cid: cid('a'),
    effect_identity_cid: cid('a'), preview_strength: 'full_diff',
    source_binding_cid: cid('a'), capability_evidence_cid: cid('a'),
    authority_scope_cid: cid('a'),
    write_footprint: {
      kind: 'exact_targets', resource_identity_scheme_cid: cid('a'),
      provider_namespace: 'provider', provider_boundary_cid: cid('a'),
      resource_kind: 'Object', provider_object_identity_cids: [cid('1')],
    },
    count: 1, max_items: 1, required_permissions: ['write'],
    approval: 'none', on_item_failure: 'halt',
    changes: [{
      target_row_identity: 'row-1', before: {state: 'present', value: {}},
      after: {state: 'present', value: {}}, row_preview_cid: cid('3'),
      row_idempotency_key: cid('4'),
    }],
    row_order: [cid('3')], effect_member_preview_cid: cid('a'),
    executed: false,
  };
  const preview = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: cid('a'), program_definition_cid: cid('a'),
    invocation_cid: cid('a'), run_identity_cid: cid('a'),
    compiled_plan_cid: cid('a'), check_environment_cid: cid('a'),
    authoring_context: {
      version: 'actql-authoring-context/0.1', program_definition_cid: cid('a'),
      annotations: [], authoring_context_cid: authoring,
    },
    barrier_provenance_cids: [], model_derived: false,
    model_task_contract_cids: [], model_invocation_evidence_cids: [],
    model_response_artifact_cids: [], effects: [member], executed: false,
    effect_preview_cid: cid('a'),
  };
  const identities = effect.derivePreviewIdentities(canonicalJson(preview),
    8192, 256, 12);
  member.effect_member_preview_cid = identities[1];
  preview.effect_preview_cid = effect.derivePreviewIdentities(
    canonicalJson(preview), 8192, 256, 12)[0];
  const key = effect.dispatchKey(scope, preview.effect_preview_cid,
    '"row-1"', 128, 8, 3);
  member.changes[0].row_idempotency_key = effect.dispatchKeyCid(key);
  const wire = canonicalJson(preview);
  assert.equal(effect.admitPreviewApplyIdentity(wire, cid('a'), authoring,
    scope, [[key]], 8192, 256, 12), preview.effect_preview_cid);
  member.changes[0].row_idempotency_key = cid('5');
  assert.throws(() => effect.admitPreviewApplyIdentity(canonicalJson(preview),
    cid('a'), authoring, scope, [[key]], 8192, 256, 12));
  member.changes[0].row_idempotency_key = effect.dispatchKeyCid(key);
  preview.run_identity_cid = cid('6');
  assert.throws(() => effect.admitPreviewApplyIdentity(canonicalJson(preview),
    cid('a'), authoring, scope, [[key]], 8192, 256, 12));
});

test('Host bridge issues the same typed Effect ledger chain as MoonBit', () => {
  const scope = effect.logicalRequestScope(cid('a'), 'request-1', 32);
  const key = effect.dispatchKey(scope, cid('b'), '"row-1"', 32, 8, 3);
  const locator = effect.logicalItemLocator(scope, 'program-1', 'node-1',
    'WriteOne', '{"row":"record-1"}', 64, 128, 8, 3);
  const basis = effect.ledgerBasis(scope, locator, key,
    cid('c'), cid('d'), cid('e'), cid('f'), cid('0'), 'unavailable',
    cid('1'), cid('2'));
  const prepared = effect.issuePreparedLedgerEntry(basis, 4096, 64, 3);
  assert.equal(effect.ledgerEntryCid(prepared),
    'sha256:09517d06658bcea4c679a029de58d0cb4dbd512eb4d06473b2502acecd009dca');
  assert.equal(effect.ledgerEntryFollows(undefined, prepared), true);
  assert.equal(effect.ledgerEntryWire(prepared).includes('"self_cid"'), true);
  const dispatching = effect.issueNextLedgerEntry(prepared, 'dispatching',
    '', 4096, 64, 3);
  assert.equal(effect.ledgerEntryFollows(prepared, dispatching), true);
  assert.throws(() => effect.issueNextLedgerEntry(prepared, 'applied',
    cid('3'), 4096, 64, 3));
});
