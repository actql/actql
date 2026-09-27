// Test support: read a completed run's Named Result through the existing
// publication export, which reads managed and captured outputs alike, and
// return its rows in order. The temporary publication Store is removed.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {openLocalPublicationStore} from
  '../adapters/store-local/publication-store.mjs';

const hash = value =>
  `sha256:${createHash('sha256').update(JSON.stringify(value)).digest('hex')}`;

export async function readPublishedResultRows(
  runtime, execution, result, outputLimits, parentDirectory,
) {
  const directory = await mkdtemp(join(parentDirectory, 'result-read-'));
  const store = await openLocalPublicationStore({
    directory,
    storeAuthorityCid: hash('result-read-store'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: outputLimits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: 10000,
    maxContractDepth: 64,
  }, runtime.publicationControl);
  try {
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
    const seal = (kind, value) =>
      runtime.publicationControl.seal(kind, JSON.stringify(value), limits);
    const policy = hash('result-read-policy');
    const stored = await execution.storePublicationResult(result, store, {
      outputLimits,
      contractLimits: limits,
      runDefinition: seal('run_definition', {
        version: 'actql-run-definition/0.1',
        scope_id: 'result-read-scope',
        run_id: 'result-read-run',
        compiled_plan_cid: hash('compiled-plan'),
        invocation_template_cid: hash('invocation-template'),
        authorization_context_cid: hash('authorization-context'),
        input_artifact_set_cid: hash('input-artifact-set'),
        created_at: '2026-09-18T00:00:00.000Z',
        valid_until: '2026-09-18T04:00:00.000Z',
      }),
      invocation: seal('run_invocation', {
        version: 'actql-run-invocation/0.1',
        invocation_template_cid: hash('invocation-template'),
        observation_set_cid: hash('observation-set'),
      }),
      retention: seal('result_retention_policy', {
        version: 'actql-result-retention-policy/0.1',
        retention_contract_cid: hash('retention-contract'),
        effective_data_policy_cid: policy,
        available_until: '2026-09-18T01:00:00.000Z',
        delete_by: '2026-09-18T02:00:00.000Z',
        extension_ceiling_at: '2026-09-18T03:00:00.000Z',
        metadata_retention_policy_cid: hash('metadata-retention'),
        metadata_delete_by: '2026-09-18T04:00:00.000Z',
        clock_contract_cid: hash('clock-contract'),
      }),
      evidenceContext: {
        computationContractCid: hash('checked-computation'),
        inputRelationCids: [],
        scopeCid: hash('result-scope'),
        effectiveDataPolicyCid: policy,
        authorityScopeCid: hash('authority-scope'),
      },
    });
    const payload = [];
    try {
      await store.consumeObject(stored.physical.cid,
        chunk => payload.push(Buffer.from(chunk)));
    } finally {
      assert.equal(await stored.prepared.release(), true);
    }
    return JSON.parse(Buffer.concat(payload).toString('utf8'));
  } finally {
    await store.close();
    await rm(directory, {recursive: true, force: true});
  }
}
