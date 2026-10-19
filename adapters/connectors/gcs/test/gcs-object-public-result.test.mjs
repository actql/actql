// Repository Common/RowRun/SQLite/encrypted Store/SDK boundary. The Source is
// the real GCS declaration and object-page reader, with explicit Credential
// Site and HTTP controls. This is not pristine package, service or normal
// numerical funding acceptance.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {connectEmbeddedLocal} from '../../../host-node/embedded-local.mjs';
import {createInstalledConnectorTable} from '../../../host-node/installed-connectors.mjs';
import {createInstalledRowSource, installRowSourceAuthorization, rowSourceCheckEnvironment}
  from '../../../host-node/installed-row-source.mjs';
import {canonical, token} from '../../../host-node/fixtures/file-listing-source.fixture.mjs';
import {restoreGcsSourceDeclaration} from '../host/gcs-source-declaration.mjs';
import {readGcsObjects} from '../site/gcs-object-listing.mjs';
import {GCS_FILE_LIST_OPERATION} from '../site/gcs-file-listing.mjs';

// Provider text, expected rows and expected contracts are independent of the
// product projection. Values exceed binary64's exact integer range; the final
// result must keep the signed64 domain, not a Decimal/String/Number alias.
const fields = ['name', 'size', 'generation', 'metageneration', 'updated', 'metadata'];
const objects = [
  {bucket: 'actql-fixture', name: 'in/a-e\u0301%2F.csv',
    generation: '9007199254740993', metageneration: '9223372036854775807',
    size: '9223372036854775807', updated: '2026-10-17T00:00:00Z',
    metadata: {'actql-request': 'private-protocol-marker', '$json': 'user',
      'e\u0301': 'e\u0301\r\n%2F'}},
  {bucket: 'actql-fixture', name: 'in/b-empty.csv', generation: '2',
    metageneration: '1', size: '0', metadata: {}},
  {bucket: 'actql-fixture', name: 'in/c-null.csv', generation: '3',
    metageneration: '1', size: '1'},
];
const expected = [
  {name: 'in/a-e\u0301%2F.csv', size: '9223372036854775807',
    generation: '9007199254740993', metageneration: '9223372036854775807',
    updated: '2026-10-17T00:00:00.000Z',
    metadata: {$json: {'$json': 'user', 'e\u0301': 'e\u0301\r\n%2F'}}},
  {name: 'in/b-empty.csv', size: '0', generation: '2', metageneration: '1',
    updated: null, metadata: {$json: {}}},
  {name: 'in/c-null.csv', size: '1', generation: '3', metageneration: '1',
    updated: null, metadata: null},
];
const integer = {type: 'int64', nullable: false};
const columns = [
  {name: 'name', contract: {type: 'string', nullable: false}},
  ...['size', 'generation', 'metageneration'].map(name => ({name, contract: integer})),
  {name: 'updated', contract: {type: 'timestamp', nullable: true}},
  {name: 'metadata', contract: {type: 'json', nullable: true}},
];

for (const captureSort of [false, true]) {
test(`public GCS Named Result preserves exact signed64 and JSON across same-Run reopening (${captureSort ? 'capture assertion and sort' : 'capture assertion'})`, async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../../../_build/', import.meta.url).pathname,
    prefix: 'gcs-public-typed-result-', label: 'GCS public typed Result'});
  const owner = userInfo().username;
  const account = canonical({version: 'actql-execution-account-config/0.1',
    account_id: 'gcs-public-result', entries: [{entry_id: 'component-read-write', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['read', 'write']}, exclusions: []}]});
  const profile = {version: 'actql-installed-gcs-source/0.1', connectorId: 'storage',
    project: 'fixture-project', bucket: 'actql-fixture', prefix: 'in/', mediaType: 'text/csv',
    siteProfilePath: '/fixture/site.json', accountConfigurationWire: account,
    limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
      maxListingBytes: 32768, maxDurationMs: 10000, maxPathBytes: 1024,
      maxPageBytes: 8192, maxPageItems: 3, maxRequestBytes: 4096, maxContentBytes: 4096}};
  const {declaration, declared} = restoreGcsSourceDeclaration(moon, profile, undefined, {includeObjects: true});
  const environment = rowSourceCheckEnvironment((await readFile(new URL(
    '../../../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd(), declared);
  const resources = new Map(objects.map((object, index) => [object.name,
    {$actql_ref: 'resource', version: 'actql-resource-ref/0.1', provider_namespace: 'gcs',
      resource_kind: 'file', provider_identity_cid: token('a'), authority_scope_cid: token('b'),
      boundary_cid: token('c'), identity_cid: token(String(index + 1))}]));
  const profileVersion = 'actql-installed-gcs-public-result-fixture/0.1';
  const events = [];
  let calls = 0, acquisitions = 0, referenceChecks = 0, client;
  let allowRead = true;
  const connectorTable = createInstalledConnectorTable([{name: 'gcs', registration: 'gcs', revision: 'gcs/0.1',
    source: {profileVersion, load: async () => ({check: value => value, identityParts: value => [value],
      async load(_profile, options) {
        const authorization = await installRowSourceAuthorization({accountConfiguration: account,
          principalId: owner, root: options.root, connectorRegistration: 'gcs'});
        const scope = Object.freeze({operation: GCS_FILE_LIST_OPERATION,
          resourceOrigin: 'https://storage.googleapis.com', siteGeneration: 1,
          issuerAuthority: 'fixture', principal: owner, namespaceId: 'fixture', environment: 'fixture',
          siteKey: 'fixture', runtimeBundleCid: token('e'), connectorRegistration: 'gcs',
          connectorRevision: 'gcs/0.1', runInvocationCid: token('f'), taskAttempt: 1,
          dispatchRequestCid: token('0')});
        const referenceIssuer = moon.clientProgramResourceReferenceIssuer((kind, wire) => {
          referenceChecks++;
          return kind === 'file' && [...resources.values()].some(value => canonical(value) === wire);
        }, () => true);
        const adapter = await createInstalledRowSource({moon, declaration, declared, environmentWire: environment.wire,
          connectorId: 'storage', connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1',
          referenceIssuer, bindingCid: token('1'), authorization,
          readOperation: {objects: GCS_FILE_LIST_OPERATION, files: GCS_FILE_LIST_OPERATION,
            contents: 'gcs:file:read'},
          site: {connection: 'gcs:fixture-project/actql-fixture',
            issueReadGrant: () => ({grant: {}, scope}), close: () => authorization.close()},
          physicalTarget: (resource, selected) => ({resource, fields: selected}),
          limits: {maxPages: 4, maxPageBytes: 8192, maxPageRows: 3, maxCaptureRows: 3},
          async readPages(options) {
            assert.ok(allowRead, 'same original published Run must not reacquire GCS');
            acquisitions++;
            return readGcsObjects({...options, moon: provider,
              target: {bucket: profile.bucket, prefix: profile.prefix},
              limits: {maxPageBytes: 8192, maxPageItems: 3, maxRequestBytes: 4096,
                maxTimeMs: 1000, maxPages: 4, maxRows: 3}, credential: {journal: {fixture: true}},
              resourceFor: target => {
                assert.equal(target.bucket, profile.bucket);
                return resources.get(target.objectName);
              }, callResource: async call => {
                calls++;
                assert.deepEqual([...call.operations.keys()], [GCS_FILE_LIST_OPERATION]);
                const operation = call.operations.get(GCS_FILE_LIST_OPERATION);
                assert.equal(operation.method, 'GET');
                assert.equal(operation.path,
                  '/storage/v1/b/actql-fixture/o?prefix=in%2F&maxResults=3&projection=noAcl' +
                  (calls === 1 ? '' : '&pageToken=next'));
                // Independent provider order is not the final Result order.
                const page = calls === 1 ? {kind: 'storage#objects', nextPageToken: 'next'}
                  : {kind: 'storage#objects', items: [objects[2], objects[0], objects[1]]};
                return {accepted: true, statusCode: 200, headers: [], body: Buffer.from(JSON.stringify(page))};
              }});
          }});
        return adapter;
      }})}}]);
  const sourceProfilePath = join(scratch.path, 'source.json');
  await writeFile(sourceProfilePath, canonical({version: profileVersion}));
  const keys = generateKeyPairSync('ed25519');
  const installation = {directory: join(scratch.path, 'host'), connectorTable, sourceProfilePath,
    authorization: {accountConfiguration: account,
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: owner,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      observe: (event, detail) => events.push({event, detail})}};
  const open = () => connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable', installation});
  t.after(async () => { await client?.close(); });
  client = await open();
  const program = {version: 'actql/0.1', id: 'gcs-public-typed-result', stages: [{id: 'scan',
    inputs: {objects: {connector: 'storage', resource: 'objects', view: 'records', request: {prefix: null}}},
    steps: [{from: 'objects', filter: 'true', as: 'listed'},
      {from: 'listed', select: fields, as: 'rows'},
      {from: 'rows', assert_rows: {unique_by: ['name']}, as: 'unique_names'},
      ...(captureSort ? [{from: 'unique_names', sort: [{name: 'asc'}], as: 'ordered_capture'}] : [])],
    results: {r: {from: captureSort ? 'ordered_capture' : 'unique_names', fields}}}, {id: 'compute',
    inputs: {rows: {result: {stage: 'scan', result: 'r'}}},
    steps: [captureSort ? {from: 'rows', select: fields, as: 'ordered'}
      : {from: 'rows', sort: [{name: 'asc'}], as: 'ordered'}],
    results: {r: {from: 'ordered', fields}}}], results: {r: {from: {stage: 'compute', result: 'r'}}}};
  const checkedEnvironment = moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(checkedEnvironment);
  const preparation = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(program),
    'json', checkedEnvironment, undefined);
  assert.ok(moon.clientProgramPreparationReady(preparation),
    inspect(moon.clientProgramPreparationIssue(preparation), {depth: 12, maxArrayLength: 0}));
  checked(moon.clientProgramCompileLocalTasks(moon.clientProgramPreparationReady(preparation)));
  const run = await client.startSource(JSON.stringify(program), {format: 'json',
    submissionRef: client.newSubmission({nonce: 'gcs-public-original'})});
  const state = await run.wait({signal: AbortSignal.timeout(15000)});
  assert.equal(state.status, 'succeeded', inspect({state, events},
    {depth: 12, maxArrayLength: 8, maxStringLength: 200}).slice(0, 12000));
  const description = await run.result('r').describe();
  assert.deepEqual(description.columns, columns);
  assert.deepEqual(await run.result('r').all(), expected);
  assert.equal(acquisitions, 1);
  assert.equal(calls, 2, 'the empty continuation is not an end-of-stream');
  assert.ok(referenceChecks >= 3, 'actual Source Resource admission is not bypassed');
  const originalRef = run.ref;
  await client.close();
  client = undefined;
  allowRead = false;
  client = await open();
  const attached = await client.attach(originalRef);
  assert.deepEqual(attached.ref, originalRef);
  assert.deepEqual(await attached.result('r').describe(), description);
  assert.deepEqual(await attached.result('r').all(), expected);
  const reopenedState = await attached.status();
  assert.equal(reopenedState.status, 'succeeded');
  // Terminal publication may precede the dispatch cleanup observation.
  // Require its real stop confirmation only after the original Host close.
  assert.equal(reopenedState.control.physical_stop, 'confirmed');
  assert.equal(acquisitions, 1);
  assert.equal(calls, 2, 'reopening reads the original committed Result, never a new provider generation');
  await client.close();
  client = undefined;
  scratch.passed();
});
}
