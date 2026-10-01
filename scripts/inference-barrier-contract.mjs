import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid, documentCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-production-profile-schemas.json';
const read = file => JSON.parse(readFileSync(file, 'utf8'));

// The declared inference barrier closes the existing model-outcome Plan.
// It adds the adjacent pure fragment identity, not a future model value.
export function inferenceBarrierSchema() {
  const stage = read('spec/contracts/actql-stage-contracts.json');
  const plan = stage.schemas.inference_plan;
  const cid = plan.properties.model_task_contract_cid;
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-inference-barrier-0.1.json',
    type: 'object', additionalProperties: false,
    required: [...plan.required.filter(key => key !== 'self_cid'),
      'input_fragment_cid', 'barrier_cid'],
    properties: {
      ...Object.fromEntries(Object.entries(plan.properties)
        .filter(([key]) => key !== 'self_cid')),
      version: {const: 'actql-inference-barrier/0.1'},
      input_fragment_cid: cid,
      barrier_cid: cid,
    },
  };
}

export function verifyInferenceBarrierSchema(write = false) {
  const registry = read(path);
  const schema = inferenceBarrierSchema();
  const cid = machineCid(schema);
  if (write) {
    registry.schemas.inference_barrier = schema;
    registry.schema_cids.inference_barrier = cid;
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
    // Document imports bind exact bytes. Refresh their derived pins after
    // the normative owner and its schema reference have been reviewed.
    const familyPath = 'spec/spec-family.json';
    const family = read(familyPath);
    const documents = new Map(family.documents.map(document => [
      document.spec_id, documentCid(readFileSync(document.path, 'utf8')),
    ]));
    for (const document of family.documents) {
      for (const imported of document.normative_imports ?? []) {
        assert.ok(documents.has(imported.owner));
        imported.document_cid = documents.get(imported.owner);
      }
    }
    writeFileSync(familyPath, JSON.stringify(family, null, 2) + '\n');
  }
  assert.deepEqual(registry.schemas.inference_barrier, schema,
    'Stale inference barrier schema');
  assert.equal(registry.schema_cids.inference_barrier, cid,
    'Stale inference barrier contract identity');
  return {schema, cid};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(JSON.stringify(verifyInferenceBarrierSchema(
    process.argv.includes('--write'))));
}
