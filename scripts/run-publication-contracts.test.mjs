import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {
  correctedContracts,
  effectApplyReceiptSchema,
  effectReconciliationReceiptSchema,
  effectSetApplyReceiptSchema,
  effectSourceArtifactSchema,
  resultArtifactSchema,
  runStateSchema,
} from './run-publication-contracts.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';

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
    ['definition', 'local_result_definition'],
    ['invocation', 'local_computation'],
    ['manifest', 'local_manifest'],
    ['artifact', 'local_result_artifact'],
  ]) {
    assert.deepEqual(entry.properties[field], stage.schemas[schema]);
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
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const schema = effectSourceArtifactSchema();
  assert.deepEqual(schema.required.toSorted(),
    [...Object.keys(body), 'result_artifact_cid'].toSorted());
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
  const schema = registry.artifact_schemas.effect_row_outcome_receipt;
  assert.deepEqual(schema.required.toSorted(),
    [...Object.keys(body), 'receipt_cid'].toSorted());
  assert.equal(registry.artifact_schema_cids.effect_row_outcome_receipt,
    machineCid(schema));
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
        'sha256:8f308beba1e134bb0bbf013f961015a39301ab05dc24d54c0fbfbcddde6eeafa',
      run_receipt:
        'sha256:d5de76fb14e35a588d34bfa13d758b6e6b2e0a388645630b692de8cf1f27ba79',
      run_state:
        'sha256:e61cdac45a5af98ca5362ee945511d705c373613cd4e9dc42009e036eb9fcb84',
      captured_run:
        'sha256:d10eba96fc9983ffe709fee16faab30c9912af109d4310acad64fc675360b0c7',
    },
  );
});
