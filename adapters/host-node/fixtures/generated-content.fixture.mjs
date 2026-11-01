// Reusable actual common generation/issuance and physical Store fixture.
// The independent empty CSV bytes are authored here, not read from an encoder.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, open, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as moon from '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {openLocalPublicationStore} from '../../store-local/publication-store.mjs';
import {issueStoredGeneratedContent} from '../generated-content-holding.mjs';

const token = byte => `sha256:${byte.repeat(64)}`;
const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const limits = {maxBytes: 4096, maxNodes: 100, maxDepth: 8, maxTextUnits: 4096};
const runtime = runtimeCore(moon);
export const generatedContentFixtureControl = runtime.contentGenerationControl;
const control = generatedContentFixtureControl;
const environmentWire = (await readFile(new URL('../../../spec/local-check-environment.json',
  import.meta.url), 'utf8')).trim();
const environment = moon.clientProgramCheckEnvironment(environmentWire,
  JSON.parse(environmentWire).evidence_bundle_cid,
  false, false, true, false, false, false, false);
assert.ok(environment);

export async function createGeneratedContentFixture(t, options = {}) {
  const directory = options.directory ?? await mkdtemp(join(tmpdir(), 'actql-generated-content-'));
  if (options.directory !== undefined) await mkdir(directory, {recursive: true});
  const configuration = {directory, storeAuthorityCid: token('1'),
    capacityBytes: 65536, maxObjectBytes: options.maxObjectBytes ?? 8192, maxObjects: 20,
    maxContractNodes: 1000, maxContractDepth: 32};
  const store = await openLocalPublicationStore(configuration,
    runtime.publicationControl, options.durability?.(directory));
  t.after(async () => {
    // Erasing the ownership record first is not successful release. Keep the
    // actual fixture/custody on failed close instead of hiding false cleanup.
    assert.equal(await store.close(), true);
    if (options.directory === undefined && process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') {
      await rm(directory, {recursive: true, force: true});
    }
  });
  const program = {version: 'actql/0.1', id: 'empty-content',
    stages: [{id: 'main', inputs: {}, steps: [
      {values: {schema: {id: {type: 'number', nullable: false}}, rows: []}, as: 'seed'},
      {serialize: {format: 'csv', fields: ['id'], name: 'empty.csv',
        header: true, null_marker: '\\N', preserve_order: true,
        bounds: {max_rows: 1, max_bytes: 32}}, as: 'file'},
    ], results: {file: {from: 'file', fields: ['name', 'content', 'media_type',
      'size_bytes', 'row_count']}}}],
    results: {file: {from: {stage: 'main', result: 'file'}}}};
  const preparation = moon.clientProgramPrepareEffectFreeWithParameters(
    JSON.stringify(program), 'json', environment, undefined);
  const prepared = moon.clientProgramPreparationReady(preparation);
  assert.ok(prepared, moon.clientProgramPreparationIssueCode(preparation));
  const barrier = control.prepare(prepared, 0, 1, 3);
  const encoder = control.encoder(barrier, {maxRows: 10, maxBytes: 32,
    maxValueNodes: 100, maxValueDepth: 8, maxFrames: 20});
  const writer = store.createPreparedObjectWriter(32);
  const pieces = [];
  let totalWork = 0;
  for (let poll = 0; poll < 100; poll++) {
    const next = control.advance(encoder, 1);
    totalWork += next.work;
    assert.equal(next.issue, undefined);
    pieces.push(next.piece);
    await writer.append(next.piece);
    if (next.ready) break;
    assert.notEqual(poll, 99);
  }
  assert.ok(totalWork > 0);
  assert.equal(pieces.join(''), 'id\n');
  const completed = control.finish(encoder);
  assert.deepEqual(completed, {name: 'empty.csv', mediaType: 'text/csv',
    contentCid: hash('id\n'), sizeBytes: 3, rowCount: 0});
  const binding = {content_store_id: 'fixture', content_store_cid: token('1'),
    workspace_scope_cid: token('2'), storage_scope: 'workspace',
    retention_class: 'fixture', availability_evidence_cid: token('3'),
    effective_data_policy_cid: token('4'), data_classification: 'internal',
    issuer_contract_cid: token('5'), capture_authority_cid: token('6'),
    ...(options.expiresAt === undefined ? {} : {expires_at: options.expiresAt})};
  const candidate = control.candidate(encoder, binding, limits);
  const description = control.inspect(candidate);
  const physical = await writer.seal(completed.contentCid);
  const holding = {version: 'actql-local-physical-holding/0.1', namespace: 'content',
    holding_cid: hash('common Content Store fixture'), manifest_cid: description.identity,
    objects: [{cid: physical.cid, byte_count: physical.bytes}]};
  let available = true;
  let allowed = true;
  let authorityChecks = 0;
  const issue = (overrides = {}) => issueStoredGeneratedContent({store, control,
    candidate, holdingCid: holding.holding_cid, workspaceScopeCid: token('2'),
    effectiveDataPolicyCid: token('4'), available: () => available,
    authorize: () => { authorityChecks++; return allowed; }, limits, ...overrides});
  return {store, configuration, barrier, encoder, binding, holding, physical, candidate, description, issue,
    admitsContent: (media, wire) => available && store.status().closed === false &&
      media === description.mediaType && wire === description.wire,
    authorizesReference: wire => available && allowed && store.status().closed === false &&
      wire === description.wire,
    invalidate: () => { available = false; },
    revoke: () => { allowed = false; },
    authorityChecks: () => authorityChecks};
}

