import assert from 'node:assert/strict';
import test from 'node:test';
import {verifyPackedGcsObservations, packedGcsRowsDigest} from './packed-gcs-content-observations.mjs';

function fixture() {
  const objects = ['a', 'b'].map((name, index) => ({name: `test/${name}.csv`,
    mediaType: 'text/csv', contentCid: `sha256:${String(index + 1).repeat(64)}`, sizeBytes: index + 2}));
  const rows = objects.map(object => ({name: object.name, content: {$actql_ref: 'content', media_type: 'text/csv',
    metadata: {content_cid: object.contentCid, size_bytes: object.sizeBytes, truncated: false,
      issuer_evidence: {issuer_kind: 'connector_capture'}}}}));
  const description = {columns: [{name: 'name', contract: {type: 'string'}},
    {name: 'content', contract: {type: 'content_ref'}}]};
  const runRefs = [{runDefinitionCid: 'one'}, {runDefinitionCid: 'empty'}];
  return {entrance: 'Local', manifest: {expectedObjects: objects,
    limits: {maxRequests: 20, maxResponseBytes: 32768}}, phases: [
    {phase: 'capture', entrance: 'Local', complete: true, pid: 1,
      cases: [{name: 'capture', runRef: runRefs[0], rows, description},
        {name: 'empty', runRef: runRefs[1], rows: [], description}],
      credential: {credentialResolutions: 6, reservedResponseBytes: 16000, tokenMints: 1}},
    {phase: 'read', entrance: 'Local', complete: true, pid: 2,
      cases: [{name: 'capture', runRef: runRefs[0], rows: 2, orderedRowsSha256: packedGcsRowsDigest(rows)},
        {name: 'empty', runRef: runRefs[1], rows: 0, orderedRowsSha256: packedGcsRowsDigest([])}],
      credential: {credentialResolutions: 0, tokenMints: 0}},
  ]};
}
test('matching observations are accepted; the detector does not execute product code', () => {
  verifyPackedGcsObservations(fixture());
});
for (const [name, mutate] of [
  ['reordered rows', value => { value.phases[0].cases[0].rows.reverse(); }],
  ['wrong content digest', value => { value.phases[0].cases[0].rows[0].content.metadata.content_cid = 'other'; }],
  ['wrong byte size', value => { value.phases[0].cases[0].rows[0].content.metadata.size_bytes++; }],
  ['wrong media type', value => { value.phases[0].cases[0].rows[0].content.media_type = 'application/json'; }],
  ['empty schema dropped', value => { value.phases[0].cases[1].description = {columns: []}; }],
  ['different recovered Run', value => { value.phases[1].cases[0].runRef = {runDefinitionCid: 'other'}; }],
  ['same process used', value => { value.phases[1].pid = value.phases[0].pid; }],
  ['reread metadata changed', value => { value.phases[1].cases[0].orderedRowsSha256 = 'other'; }],
  ['reacquisition after restart', value => { value.phases[1].credential.credentialResolutions = 1; }],
  ['request ceiling exceeded', value => { value.phases[0].credential.credentialResolutions = 11; }],
  ['response ceiling exceeded', value => { value.phases[0].credential.reservedResponseBytes = 16385; }],
]) test(`detector refuses ${name}`, () => {
  const value = structuredClone(fixture());
  mutate(value);
  assert.throws(() => verifyPackedGcsObservations(value));
});
