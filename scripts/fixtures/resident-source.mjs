import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {canonicalText} from '../check-canonical-json.mjs';

export const sourceProgram = JSON.stringify({version: 'actql/0.1',
  id: 'fixture.resident-source', stages: [{id: 'acquire',
    inputs: {source: {connector: 'crm/main', resource: 'r'}},
    steps: [{filter: 'id > 1', as: 'filtered'},
      {select: ['id'], as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['id']}}}],
  results: {answer: {from: {stage: 'acquire', result: 'rows'}}}});

export const sourceRows = Object.freeze([{id: 2}, {id: 3}]);
// Independent two-task Program and expectation. The consumer's input is a
// checked Result edge, never a second Source acquisition.
export const retainedSourceProgram = JSON.stringify({version: 'actql/0.1',
  id: 'retained-source-compute', stages: [{id: 'acquire',
    inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{filter: 'id > 0', as: 'filtered'},
      {select: ['id'], as: 'captured'}],
    results: {rows: {from: 'captured', fields: ['id']}}},
  {id: 'compute', inputs: {input: {result: {stage: 'acquire', result: 'rows'}}},
    steps: [{filter: 'id > 2', as: 'filtered'},
      {select: ['id'], as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['id']}}}],
  results: {answer: {from: {stage: 'compute', result: 'rows'}}}});
export const retainedSourceRows = Object.freeze([{id: 3}]);
export const retainedSourceSchemaCid =
  'sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513';
export const sourceRef = 'connector://crm/main/r#v';
export const sourceContractCid =
  'sha256:1f5ce9a50072a24f9cf0673d174f4f0639a216cc5537277e15299fef59db921f';

// Reuse the independently authored Catalog and capability members used by
// Native acquisition tests. Adding admitted evidence members changes the
// environment CID; no provenance pin or expected output is rewritten.
export async function residentSourceEnvironment(repository) {
  const text = await readFile(join(repository,
    'src/query_integration/query_program_catalog_wbtest.mbt'), 'utf8');
  const match = text.match(/let wire = ("(?:[^"\\]|\\.)*")/u);
  assert.ok(match, 'Source Catalog fixture missing');
  const body = JSON.parse(JSON.parse(match[1]));
  const proof = await readFile(join(repository,
    'src/query_integration/resident_native_source_wbtest.mbt'), 'utf8');
  const snapshots = proof.match(/let snapshot =\s*#\|([^\n]+)/u);
  const capabilities = proof.match(/let capabilities =\s*#\|([^\n]+)/u);
  assert.ok(snapshots && capabilities, 'Source evidence members missing');
  body.schema_snapshots = JSON.parse(snapshots[1]);
  body.connector_capabilities = JSON.parse(capabilities[1]);
  delete body.evidence_bundle_cid;
  const cid = `sha256:${createHash('sha256').update(canonicalText(body)).digest('hex')}`;
  return {wire: canonicalText({...body, evidence_bundle_cid: cid}), cid};
}
