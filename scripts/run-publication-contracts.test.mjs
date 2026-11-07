import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {
  checkContracts,
  cliResultDeliveryReceiptFileSchema,
  cliOutputVerificationSchema,
  correctedContracts,
  effectApplyReceiptSchema,
  effectReconciliationReceiptSchema,
  effectSetApplyReceiptSchema,
  effectPreviewSchema,
  effectSourceArtifactSchema,
  resultArtifactSchema,
  runStateSchema,
} from './run-publication-contracts.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';

test('Run Definition selection projection is optional in its closed schema', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const schema = registry.artifact_schemas.run_definition;
  assert.equal(schema.additionalProperties, false);
  assert.ok(!schema.required.includes('effect_target_selections_cid'));
  assert.deepEqual(schema.properties.effect_target_selections_cid,
    {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'});
  assert.equal(machineCid(schema),
    'sha256:fa0af630d657a970ca5bba7fe82fa2adb97076dd9c8ae12ad8fdff87d52953b6');
  assert.equal(machineCid(schema), registry.artifact_schema_cids.run_definition);
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
});

test('independent Run vectors bind admitted compilation and original selection', () => {
  const vectors = read('portability/corpus/effect-target-selection-projection.json');
  const cases = vectors.cases.filter(item => item.kind === 'run_definition');
  for (const item of cases) {
    verifyIdentity(item.preimage, item.expected_cid, item.expected_canonical_bytes);
  }
  const selected = vectors.cases.find(item => item.id === 'selected Run');
  const compiled = vectors.cases.find(item => item.id === 'selected compilation');
  assert.equal(selected.preimage.compiled_plan_cid, compiled.expected_cid);
  assert.equal(selected.preimage.effect_target_selections_cid,
    vectors.selection_cid);
  assert.ok(!Object.hasOwn(cases[0].preimage, 'effect_target_selections_cid'));
  assert.equal(new Set(cases.map(item => item.expected_cid)).size, cases.length);
  // The separate binding matrix is input for Core admission tests; these
  // source identity checks alone do not execute start or captured Store reads.
});

test('Command Preview and review retain the closed ResourceRef target schema', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const preview = registry.artifact_schemas.effect_preview;
  const original = structuredClone(preview);
  const target = effectPreviewSchema(preview).properties.effects.items
    .properties.changes.items.properties.target_row_identity;
  const refs = target.oneOf.filter(branch =>
    branch.properties?.$actql_ref?.const === 'resource');
  assert.deepEqual(refs, [registry.schemas.resource_ref]);
  assert.equal(refs[0].additionalProperties, false);
  assert.ok(refs[0].required.includes('authority_scope_cid'));
  assert.ok(refs[0].required.includes('boundary_cid'));
  assert.ok(refs[0].required.includes('identity_cid'));
  assert.deepEqual(target.oneOf.slice(0, -1), original.properties.effects.items
    .properties.changes.items.properties.target_row_identity.oneOf.filter(branch =>
      branch.properties?.$actql_ref?.const !== 'resource'));
  const current = correctedContracts(registry,
    read('spec/contracts/actql-cli-run-response.schema.json')).registry;
  assert.deepEqual(current.artifact_schemas.review_projection.properties.displayed_rows
    .items.properties.target_row_identity, target);
  assert.deepEqual(preview, original, 'the supplied schema is not mutated');
  const member = preview.properties.effects.items;
  assert.deepEqual(member.properties.preview_strength.enum, ['full_diff', 'targeted']);
  assert.deepEqual(member.properties.target.oneOf.at(-1), registry.schemas.resource_ref);
  const review = registry.artifact_schemas.review_projection;
  const row = review.properties.displayed_rows.items;
  for (const field of ['preview_strength', 'target_guard', 'intended_changes']) {
    assert.deepEqual(row.properties[field], field === 'preview_strength'
      ? member.properties[field] : member.properties.changes.items.properties[field]);
    assert.ok(!row.required.includes(field));
  }
  assert.deepEqual(review.properties.displayed_scope.properties.effects.items
    .properties.target.oneOf.at(-1), registry.schemas.resource_ref);
  assert.deepEqual(effectPreviewSchema(effectPreviewSchema(preview)),
    effectPreviewSchema(preview));
});

test('private Table Preview source binding is exclusive and store-only', () => {
  const preview = read('spec/contracts/actql-protocol-schemas.json')
    .artifact_schemas.effect_preview;
  assert.deepEqual(preview, effectPreviewSchema(preview));
  const member = preview.properties.effects.items;
  assert.equal(member.additionalProperties, false);
  assert.deepEqual(member.properties.source_table_input,
    {type: 'string', minLength: 1});
  assert.deepEqual(member.allOf.at(-1), {oneOf: [
    {not: {anyOf: [
      {required: ['source_result']}, {required: ['source_table_input']},
      {required: ['result_artifact_cid']},
    ]}},
    {required: ['source_result', 'result_artifact_cid'],
      not: {required: ['source_table_input']}},
    {required: ['source_table_input', 'result_artifact_cid'],
      properties: {effect_kind: {const: 'store'}},
      not: {required: ['source_result']}},
  ]});
  // Existing command/Mapping selection remains a separate obligation.
  assert.equal(member.allOf[0].oneOf[0].properties.effect_kind.const,
    'command');
  const extra = {oneOf: [{required: ['source_table_input'],
    properties: {approval: {const: 'required'}}}]};
  const extended = structuredClone(preview);
  extended.properties.effects.items.allOf.push(extra);
  assert.deepEqual(effectPreviewSchema(extended)
    .properties.effects.items.allOf.at(-2), extra);
});

test('independent private Table Preview and member identity vectors', () => {
  const cid = digit => `sha256:${digit.repeat(64)}`;
  const hash = body => `sha256:${createHash('sha256')
    .update(canonicalText(body)).digest('hex')}`;
  // Authored preimages, not product-generated Preview bytes or expectations.
  const member = {
    effect_id: 'WriteOne', effect_kind: 'store', target: 'Object',
    mapping: 'mapping:fixture', resolved_mapping_contract_cid: cid('a'),
    effect_identity_cid: cid('a'), preview_strength: 'full_diff',
    source_binding_cid: cid('a'), capability_evidence_cid: cid('a'),
    authority_scope_cid: cid('a'),
    write_footprint: {kind: 'exact_targets',
      resource_identity_scheme_cid: cid('a'), provider_namespace: 'provider',
      provider_boundary_cid: cid('a'), resource_kind: 'Object',
      provider_object_identity_cids: [cid('1')]},
    count: 0, max_items: 1, required_permissions: ['write'], approval: 'none',
    on_item_failure: 'halt', changes: [], row_order: [], executed: false,
    source_table_input: 'answer', result_artifact_cid: cid('a'),
  };
  const memberCid = 'sha256:4a197b227fd3034f2f1114f6af987a63029c4098c690c9962a62c7a6e172ee28';
  assert.equal(hash({member, version: 'actql-effect-member-preview/0.1'}),
    memberCid);
  const preview = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: cid('a'), program_definition_cid: cid('a'),
    invocation_cid: cid('a'), compiled_plan_cid: cid('a'),
    check_environment_cid: cid('a'), barrier_provenance_cids: [],
    model_derived: false, model_task_contract_cids: [],
    model_invocation_evidence_cids: [], model_response_artifact_cids: [],
    effects: [{...member, effect_member_preview_cid: memberCid}], executed: false,
  };
  assert.equal(hash(preview),
    'sha256:41b64ea9c9fb869d5e628db520ea145ced63681487791e9516e1613178153aa8');
  const {source_table_input: name, ...rest} = member;
  assert.notEqual(hash({member: {...rest, source_result: name},
    version: 'actql-effect-member-preview/0.1'}), memberCid);
});

test('independent local Effect source inventory binds its Stage Result', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const stage = read('spec/contracts/actql-stage-contracts.json');
  const context = registry.artifact_schemas.captured_run
    .properties.effect_context;
  assert.ok(context.required.includes('effect_source_local_inventory'));
  assert.ok(context.required.includes('effect_dependency_inventory'));
  const dependencies = context.properties.effect_dependency_inventory;
  assert.equal(dependencies.type, 'array');
  assert.equal(dependencies.maxItems, 4096);
  assert.equal(dependencies.items.additionalProperties, false);
  assert.deepEqual([...dependencies.items.required].sort(),
    ['body', 'cid', 'kind']);
  assert.ok(dependencies.items.properties.kind.enum.includes(
    'result_import_observation'));
  const inventory = context.properties.effect_source_local_inventory;
  assert.equal(inventory.type, 'object');
  const entry = inventory.additionalProperties;
  assert.equal(entry.additionalProperties, false);
  assert.deepEqual(entry.required, [
    'artifact', 'definition', 'derivation', 'invocation', 'manifest',
    'ordering', 'retention',
  ]);
  for (const [field, schema] of [
    ['invocation', 'local_computation'],
    ['manifest', 'local_manifest'],
    ['artifact', 'local_result_artifact'],
  ]) {
    assert.deepEqual(entry.properties[field], stage.schemas[schema]);
  }
  assert.deepEqual(entry.properties.definition, {oneOf: [
    stage.schemas.local_result_definition, stage.schemas.local_table_input_definition,
  ]});
  for (const kind of ['local_table_input_definition', 'table_input_artifact',
    'table_input_derivation', 'table_input_ordering']) {
    assert.ok(dependencies.items.properties.kind.enum.includes(kind));
  }
  const definition = {
    version: 'actql-local-result-definition/0.1',
    unit_definition_cid: `sha256:${'1'.repeat(64)}`,
    result_name: 'rows',
  };
  const hash = body => `sha256:${createHash('sha256')
    .update(canonicalText(body)).digest('hex')}`;
  assert.equal(hash(definition),
    'sha256:11f4499c12a3a321755c1d23e74a849f0c11c3e314ed19c660a6d7eb8d41bd7d');
  assert.notEqual(hash({...definition, result_name: 'answer'}),
    hash(definition));
  assert.notEqual(hash({...definition,
    unit_definition_cid: `sha256:${'2'.repeat(64)}`}), hash(definition));
});

test('independent multi-row Effect receipt 0.1 vector and closed inventory', () => {
  const cid = digit => `sha256:${digit.repeat(64)}`;
  const hash = body => `sha256:${createHash('sha256')
    .update(canonicalText(body)).digest('hex')}`;
  const member = {
    version: 'actql-effect-apply-receipt/0.1',
    run_identity_cid: cid('1'), effect_preview_cid: cid('2'),
    effect_member_preview_cid: cid('3'),
    rows: [
      {row_index: 0, row_preview_cid: cid('4'), state: 'applied',
        dispatch_entry_cid: cid('6'), attempt_sequence: 1,
        outcome_receipt_cid: cid('8')},
      {row_index: 1, row_preview_cid: cid('5'), state: 'unknown',
        dispatch_entry_cid: cid('7'), attempt_sequence: 1,
        ledger_head_cid: cid('9')},
    ], status: 'unknown_outcome',
  };
  const expected = 'sha256:ac602de3d5d17923ef77bf9416b20bb9e9c230009a08384fa3bf7d0ec45a27a4';
  assert.equal(hash(member), expected);
  assert.notEqual(hash({...member, rows: [...member.rows].reverse()}), expected);
  assert.notEqual(hash({...member, run_identity_cid: cid('a')}), expected);
  assert.notEqual(hash({...member, rows: [member.rows[0],
    {...member.rows[1], ledger_head_cid: cid('a')}]}), expected);
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  assert.deepEqual(registry.artifact_schemas.effect_apply_receipt,
    effectApplyReceiptSchema());
  assert.equal(registry.artifact_schema_cids.effect_apply_receipt,
    machineCid(effectApplyReceiptSchema()));
  assert.deepEqual(registry.artifact_schemas.effect_set_apply_receipt,
    effectSetApplyReceiptSchema(registry.artifact_schemas.effect_set_apply_receipt));
  assert.ok(!('outcome' in registry.artifact_schemas.effect_set_apply_receipt
    .properties.effects.items.properties));
  const set = {
    version: 'actql-effect-set-apply-receipt/0.1',
    effect_preview_cid: cid('2'), apply_policy: 'attempt_all',
    effects: [{effect_id: 'WriteOne',
      effect_member_preview_cid: cid('3'), state: 'unknown',
      replayed: false, member_receipt_cid: expected}],
    status: 'unknown_outcome',
  };
  const setCid = 'sha256:ff1d2d85eb4e71ea996c6792e8c2669aee625dadaac8a625fa9cf1200b1ae0e4';
  assert.equal(hash(set), setCid);
  const reconciliation = {
    version: 'actql-effect-reconciliation-receipt/0.1',
    effect_id: 'WriteOne', effect_set_receipt_cid: setCid,
    prior_receipt_cid: expected, run_identity_cid: cid('1'),
    effect_preview_cid: cid('2'), effect_member_preview_cid: cid('3'),
    row_preview_cid: cid('5'), dispatch_entry_cid: cid('7'),
    dispatch_attempt_sequence: 1, prior_ledger_head_cid: cid('9'),
    attempt_sequence: 1, terminal: false,
    command_id: 'write-1', idempotency_key: 'key-1',
    outcome: {state: 'unknown', command_id: 'write-1',
      idempotency_key: 'key-1', reason: 'connection_lost',
      reconciliation_contract: {id: 'lookup', version: '0.1', cid: cid('a')}},
  };
  const reconciliationCid = 'sha256:1130effbaa2a6f852ecccaa1105aa8c7b5aeb154ef0a26e73efa84724930592b';
  assert.equal(hash(reconciliation), reconciliationCid);
  assert.notEqual(hash({...reconciliation, row_preview_cid: cid('4')}),
    reconciliationCid);
  assert.notEqual(hash({...reconciliation, prior_ledger_head_cid: cid('8')}),
    reconciliationCid);
  assert.deepEqual(registry.artifact_schemas.effect_reconciliation_receipt,
    effectReconciliationReceiptSchema(
      registry.artifact_schemas.effect_reconciliation_receipt));
});

test('independent Effect-source Artifact and holding 0.1 vectors', () => {
  const cid = digit => `sha256:${digit.repeat(64)}`;
  const hash = body => `sha256:${createHash('sha256')
    .update(JSON.stringify(body)).digest('hex')}`;
  const body = {
    actual_completeness: 'complete', actual_row_count: 2,
    effective_data_policy_cid: cid('1'),
    effective_retention_policy_cid: cid('2'),
    invocation_cid: cid('3'), logical_result_cid: cid('4'),
    provenance_evidence_cids: [], result_schema_cid: cid('5'),
    source_binding_cid: cid('6'), source_result: 'rows',
    store_authority_cid: cid('7'),
    version: 'actql-effect-source-artifact/0.1',
  };
  const artifactCid =
    'sha256:da81971101ba8f06a0255950099bd0328faada17ee200634ac6a27149052d0bc';
  assert.equal(hash(body), artifactCid);
  assert.notEqual(hash({...body, source_result: 'answer'}), artifactCid);
  assert.notEqual(hash({...body, source_binding_cid: cid('9')}), artifactCid);
  assert.notEqual(hash({...body, store_authority_cid: cid('9')}),
    artifactCid);
  const holdingBody = {
    effect_id: 'WriteOne', result_artifact_cid: artifactCid,
    run_identity_cid: cid('8'), store_authority_cid: cid('7'),
    version: 'actql-effect-source-holding/0.1',
  };
  assert.equal(hash(holdingBody),
    'sha256:9f02433c84d076d9e0ee3f99c347850248ac8632da29f411c1788ded9a40a073');
  assert.notEqual(hash({...holdingBody, run_identity_cid: cid('9')}),
    hash(holdingBody));
  const {source_result, ...common} = body;
  const privateBody = {...common, source_table_input: source_result};
  // Canonical field order differs from insertion order; this is an authored
  // preimage with fixed facts, independent of the MoonBit issuer's output.
  const privateCid = `sha256:${createHash('sha256')
    .update(canonicalText(privateBody)).digest('hex')}`;
  assert.equal(privateCid,
    'sha256:76a24711b5a15b32bcd38473ad1002de41635dd6576fdc51634de6f2ccb34d93');
  assert.notEqual(privateCid, artifactCid);
  assert.equal(hash({...holdingBody, result_artifact_cid: privateCid}),
    'sha256:cc4bcee73c59f409d982ddc39d2d882e5237b0011f12b556c46dc394cfa2645c');
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const schema = effectSourceArtifactSchema();
  assert.deepEqual(schema.required.toSorted(),
    [...Object.keys(body).filter(field => field !== 'source_result'),
      'result_artifact_cid'].toSorted());
  assert.deepEqual(schema.oneOf, [
    {required: ['source_result'], not: {required: ['source_table_input']}},
    {required: ['source_table_input'], not: {required: ['source_result']}},
  ]);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.properties.source_table_input,
    {type: 'string', minLength: 1});
  assert.equal(registry.artifact_schema_cids.effect_source_artifact,
    machineCid(schema));
});

test('independent Effect row Outcome Receipt 0.1 vector and schema pin', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const outcome = {result: {id: '001'}, state: 'applied'};
  const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
  const body = {
    credential_use_cid: `sha256:${'6'.repeat(64)}`,
    dispatch_entry_cid: `sha256:${'5'.repeat(64)}`,
    effect_member_preview_cid:
      'sha256:099721c928770511d95faed4eaeef3fef768c4b573c714fc0af16c0b5439b5b6',
    effect_preview_cid:
      'sha256:2fe7f8e93988fcf4d7804e86b69a72d00e1c7bfd946c8fa29d6e91c706593409',
    http_status_code: 201,
    response_byte_count: 2,
    response_physical_sha256:
      '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a',
    row_preview_cid:
      'sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8',
    typed_outcome: outcome,
    typed_outcome_cid:
      'sha256:851bf9a054b70fc0435dd57569b77d0d21f16e090254b19b212602b00f171df0',
    version: 'actql-effect-row-outcome-receipt/0.1',
  };
  assert.equal(hash(JSON.stringify(outcome)), body.typed_outcome_cid);
  assert.equal(hash('{}').slice(7), body.response_physical_sha256);
  assert.equal(hash(JSON.stringify(body)),
    'sha256:0b54f40a3e03a7840f08737b5efd2380f006aea8c4161a6ffeea0af461fe076f');
  const union = registry.artifact_schemas.effect_row_outcome_receipt;
  const schema = union.oneOf[0];
  assert.equal(machineCid(schema),
    'sha256:e239b0d9b9229efdc67095bbea81ff8bccc0873a6bc277de7857c7955d8719fd');
  assert.deepEqual(schema.required.toSorted(),
    [...Object.keys(body), 'receipt_cid'].toSorted());
  assert.equal(registry.artifact_schema_cids.effect_row_outcome_receipt,
    machineCid(union));
});

const read = path => JSON.parse(readFileSync(path, 'utf8'));

test('Compiled Plan normative preimage matches its registered body', () => {
  const document = readFileSync('docs/spec/protocols/contracts.md', 'utf8');
  const section = document.match(
    /<!-- requirement-block: compilation-identities\.actql-compiled-plan -->\s*<!-- normative-code: envelope -->\s*```text\s*\{version: "actql-compiled-plan\/0\.1",([^}]+)\}/u,
  );
  assert.ok(section, 'Compiled Plan normative envelope is present');
  const declared = section[1].match(/[a-z_]+/gu);
  const registered = read('spec/contracts/actql-run-publication.json')
    .schemas.compiled_plan.required.filter(field =>
      field !== 'version' && field !== 'compiled_plan_cid');
  assert.deepEqual(declared, registered);
});

test('every Run-bound Result Artifact embedding uses the normative 12 fields', () => {
  const artifact = resultArtifactSchema();
  assert.deepEqual(artifact.required, [
    'version',
    'result_definition_cid',
    'invocation_cid',
    'logical_result_cid',
    'result_schema_cid',
    'ordering_evidence_cid',
    'actual_row_count',
    'actual_completeness',
    'effective_data_policy_cid',
    'effective_retention_policy_cid',
    'provenance_evidence_cids',
    'result_artifact_cid',
  ]);
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const localArtifact = read('spec/contracts/actql-stage-contracts.json')
    .schemas.local_result_artifact;
  const visit = (value, path = []) => {
    if (!value || typeof value !== 'object') return;
    if (value.properties?.version?.const === 'actql-result-artifact/0.1') {
      assert.deepEqual(value,
        path.includes('effect_source_local_inventory') ?
          localArtifact : artifact);
    }
    for (const [key, child] of Object.entries(value)) {
      visit(child, [...path, key]);
    }
  };
  visit(registry.artifact_schemas);
});

test('Run Receipt versions are mandatory in every embedded receipt', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  let receipts = 0;
  const visit = value => {
    if (!value || typeof value !== 'object') return;
    if (value.properties?.version?.const === 'actql-run-receipt/0.1') {
      receipts++;
      assert.ok(value.required.includes('compiler_version'));
      assert.ok(value.required.includes('aoa_ir_version'));
    }
    for (const child of Object.values(value)) visit(child);
  };
  visit(registry.artifact_schemas);
  assert.ok(receipts >= 2);
});

test('Run state separates terminal outcome from per-Result availability', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const state = registry.artifact_schemas.run_state;
  assert.deepEqual(state, runStateSchema(state));
  assert.ok(state.required.includes('result_availability'));
  assert.equal(state.properties.result_availability.minProperties, undefined);
  assert.ok(state.allOf.some(rule => rule.if?.properties?.result_availability?.maxProperties === 0 &&
    rule.then?.properties?.result_available?.const === false));
  const succeeded = state.allOf.find(
    rule => rule.if?.properties?.status?.const === 'succeeded',
  );
  assert.deepEqual(succeeded.then, {
    not: {required: ['checkpoint']},
    properties: {
      next_action: {
        type: 'object',
        required: ['kind'],
        properties: {
          kind: {
            enum: ['read_result', 'refresh_availability', 'none'],
          },
        },
      },
    },
  });
  const actions = state.properties.next_action.oneOf.map(
    action => action.properties.kind.const,
  );
  assert.deepEqual(actions, [
    'resolve_checkpoint',
    'reconcile',
    'read_result',
    'refresh_availability',
    'none',
    'reconcile_run',
  ]);
});

test('correction is idempotent and updates the CLI embedding', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const cli = read('spec/contracts/actql-cli-run-response.schema.json');
  const next = correctedContracts(registry, cli);
  assert.deepEqual(next.registry, registry);
  assert.deepEqual(next.cli, cli);
  assert.deepEqual(cli.properties.run, registry.artifact_schemas.run_state);
});

for (const omission of ['state revision', 'state revision property', 'applied upsert identity comment']) {
  test(`full publication check refuses a rehashed omitted ${omission}`, () => {
    const registry = read('spec/contracts/actql-protocol-schemas.json');
    const cli = read('spec/contracts/actql-cli-run-response.schema.json');
    if (omission.startsWith('state revision')) {
      if (omission === 'state revision property') delete registry.artifact_schemas.run_state.properties.revision;
      else registry.artifact_schemas.run_state.required = registry.artifact_schemas.run_state
        .required.filter(name => name !== 'revision');
      cli.properties.run = structuredClone(registry.artifact_schemas.run_state);
    } else {
      const applied = registry.artifact_schemas.effect_row_outcome_receipt.oneOf[0].properties
        .typed_outcome.oneOf.find(branch => branch.properties.state.const === 'applied');
      delete applied.$comment;
    }
    for (const [name, schema] of Object.entries(registry.artifact_schemas)) {
      registry.artifact_schema_cids[name] = machineCid(schema);
    }
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    assert.throws(() => checkContracts(registry, cli), /Run publication schemas are stale/);
  });
}

test('corrected schemas have independently fixed canonical identities', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  assert.equal(
    machineCid(resultArtifactSchema()),
    'sha256:ec1397e639fed3270a6ba4ada02f87ba3a3e07aafee3a5ba16a056ec9a35c4ac',
  );
  assert.deepEqual(
    Object.fromEntries(
      ['result_manifest', 'run_receipt', 'run_state', 'captured_run'].map(
        name => [name, registry.artifact_schema_cids[name]],
      ),
    ),
    {
      result_manifest:
        'sha256:bd718c411677e83cdf33258176d09c6dd690789b3cc7bb897cbff2b629290e02',
      run_receipt:
        'sha256:62f9011e9e702f3d620f70513eac6260a21b980687b7574c1bdce55984b1aba8',
      run_state:
        'sha256:3fbfc2cc5a79449fd05fce58e0fad25f6eef0ecde8314a222417a2e233db28c2',
      captured_run:
        'sha256:a37894cfc6919e1562be6b44293871f349085e6b94e27281eec26b7af8d0514c',
    },
  );
});

test('CLI receipt containers embed only the unchanged closed delivery object', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const before = structuredClone(registry);
  const container = cliResultDeliveryReceiptFileSchema(registry);
  const receipt = registry.artifact_schemas.result_delivery_receipt;
  assert.deepEqual(container.oneOf, [receipt, {type: 'array', maxItems: 16, items: receipt}]);
  assert.equal(receipt.additionalProperties, false);
  assert.deepEqual(read('spec/contracts/actql-cli-result-delivery-receipts.schema.json'), container);
  assert.deepEqual(registry, before);
  assert.equal(Object.hasOwn(container, 'properties'), false);
});

test('CLI verification reports a bounded complete identity set for one explicit output', () => {
  const report = cliOutputVerificationSchema();
  assert.deepEqual(read('spec/contracts/actql-cli-output-verification.schema.json'), report);
  assert.equal(report.properties.receipt_cids.uniqueItems, true);
  assert.equal(report.properties.receipt_cids.maxItems, 16);
  assert.equal(report.properties.verified.const, true);
  assert.equal(report.additionalProperties, false);
  assert.equal(Object.hasOwn(report.properties, 'result_name'), false);
});


test('independent CLI receipt vectors retain singleton bytes and every equal-byte identity', () => {
  const vector = read('portability/corpus/cli-result-delivery-receipts.json');
  const old = JSON.parse(vector.legacy_singleton_canonical);
  assert.equal(canonicalText(old), vector.legacy_singleton_canonical);
  assert.equal(old.result_delivery_receipt_cid,
    'sha256:1b672f923a8f34e603d8246a3541922ccb1eedb4be8d1691f9a290d14fe1e2ea');
  for (const complete of [old, ...vector.members]) {
    const {result_delivery_receipt_cid: identity, ...body} = complete;
    assert.equal(machineCid(body), identity);
  }
  const output = Buffer.from(vector.output_hex, 'hex');
  assert.equal(createHash('sha256').update(output).digest('hex'), vector.output_sha256);
  const matches = vector.members.filter(receipt => receipt.delivered_byte_count === output.length
    && receipt.delivered_sha256 === vector.output_sha256);
  assert.deepEqual([...new Set(matches.map(receipt => receipt.result_delivery_receipt_cid))],
    vector.expected_matching_identities);
  assert.equal(vector.expected_matching_identities.length, 2);
  for (const [name, identity] of Object.entries(vector.schema_pins)) {
    assert.equal(machineCid(read(`spec/contracts/${name}`)), identity);
  }
});

test('Command Preview approval is forbidden absence while Mapping still requires its legacy field', () => {
  const existing = read('spec/contracts/actql-protocol-schemas.json').artifact_schemas.effect_preview;
  const schema = effectPreviewSchema(existing), member = schema.properties.effects.items;
  assert.equal(member.required.includes('approval'), false);
  const selection = member.allOf.find(rule => rule.oneOf?.some(branch => branch.properties?.effect_kind?.const === 'command'));
  const command = selection.oneOf.find(branch => branch.properties?.effect_kind?.const === 'command');
  const mapping = selection.oneOf.find(branch => branch.properties?.effect_kind?.enum);
  assert.deepEqual(command.not, {required: ['approval']});
  assert.equal(command.required.includes('approval'), false);
  assert.equal(mapping.required.includes('approval'), true);
  assert.deepEqual(member.properties.approval, {enum: ['none', 'required']});
  assert.deepEqual(effectPreviewSchema(schema), schema);
});
