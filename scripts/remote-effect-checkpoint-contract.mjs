import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const schema = properties => ({$schema: 'https://json-schema.org/draft/2020-12/schema',
  type: 'object', additionalProperties: false, required: Object.keys(properties), properties});
export const effectCheckpointSchemas = {
  poll_effect_resume: schema({delivery_json: {type: 'string', minLength: 1},
    dispatch_request_cid: cid, request_json: {type: 'string', minLength: 1},
    version: {const: 'actql-remote-poll-effect-resume/0.1'}}),
  effect_resume_delivery: schema({checkpoint_cid: cid,
    claimant: {type: 'string', minLength: 1, maxLength: 256},
    dispatch_request_cid: cid, generation: {type: 'string', pattern: '^[1-9][0-9]*$'},
    report_cid: cid, resolution_cid: cid, resolution_wire: {type: 'string', minLength: 1},
    resume_intent_id: {type: 'string', minLength: 1},
    version: {const: 'actql-remote-effect-resume-delivery/0.1'}}),
  effect_checkpoint_report: schema({checkpoint_wire: {type: 'string', minLength: 1},
    dispatch_request_cid: cid, version: {const: 'actql-remote-effect-checkpoint-report/0.1'}}),
  effect_checkpoint_reply: schema({checkpoint_cid: cid, dispatch_request_cid: cid,
    outcome: {type: 'string', enum: ['accepted', 'refused']},
    reason: {type: 'string', enum: ['', 'authorization_denied', 'scope_mismatch', 'report_conflict']},
    report_cid: cid, version: {const: 'actql-remote-effect-checkpoint-reply/0.1'}}),
};
export function withEffectCheckpointContract(registry) {
  const next = structuredClone(registry);
  for (const [name, schema] of Object.entries(effectCheckpointSchemas)) {
    next.schemas[name] = structuredClone(schema);
    next.schema_cids[name] = machineCid(schema);
  }
  return next;
}
export function checkEffectCheckpointContract(registry) {
  assert.deepEqual(registry, withEffectCheckpointContract(registry), 'Effect Checkpoint report contracts are stale');
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'spec/contracts/actql-remote-site-wire.json';
  let registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    registry = withEffectCheckpointContract(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkEffectCheckpointContract(registry);
}
