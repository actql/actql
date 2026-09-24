import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {
  correctedContracts,
  resultArtifactSchema,
  runStateSchema,
} from './run-publication-contracts.mjs';
import {machineCid} from './actql-spec-family.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));

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
  const visit = value => {
    if (!value || typeof value !== 'object') return;
    if (value.properties?.version?.const === 'actql-result-artifact/0.1') {
      assert.deepEqual(value, artifact);
    }
    for (const child of Object.values(value)) visit(child);
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
        'sha256:d017cd0e95bce341edd4fabf859fc521588ee8d12eadfa9fd2704d8d8a94f526',
      run_state:
        'sha256:11f4930151996e513da6da627a101504ac0ff7aee1a9ae077219c126b39aab1c',
      captured_run:
        'sha256:281c623866f1dfb4e2d44ed8d9d91e88b3afec3e9f10392703d4dd87dd661422',
    },
  );
});
