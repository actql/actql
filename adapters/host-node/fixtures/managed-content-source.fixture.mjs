// The deterministic Content fixture answers HTTPS only. The installed Host's
// original Source initialization, Account, Credential, reader and RowRun own
// preparation, grants, response charging, currentness and cleanup.
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {checked} from '../../host-common/runtime-result.mjs';
import {fixtureCertificates} from '../../site-node/https-exchange-fixture.mjs';
import {captureInstalledSourceServices} from '../installed-host-services.mjs';
import {createInstalledRowSource} from '../installed-row-source.mjs';
import {retainInstalledHostInitializationFailure} from '../installed-host-cleanup.mjs';
import {installedJsonSourceReaderLimitNames} from '../installed-credential-source-reader.mjs';
import {restSourcePageReader} from '../rest-source-page.mjs';
import {canonical, token} from './file-listing-source.fixture.mjs';

export async function openManagedContentSourceFixture({scratch, keys, account,
  generated, destination, content, fixture, allowSourceRead, onRead}) {
  const directory = join(scratch.path, 'source-site');
  await mkdir(directory);
  const tls = await fixtureCertificates(directory);
  const credentialPrivateKeyPath = join(directory, 'credential.pem');
  await writeFile(credentialPrivateKeyPath, keys.privateKey.export({type: 'pkcs8', format: 'pem'}));
  const server = createServer({key: tls.key, cert: tls.cert}, async (request, response) => {
    try {
      assert.equal(request.method, 'GET');
      assert.equal(request.url, '/transfers');
      assert.equal(request.headers.authorization, 'Bearer content-source-fixture');
      assert.ok(allowSourceRead, 'recovery must not reacquire the Source');
      await generated.issue();
      onRead();
      const body = Buffer.from(canonical([{destination, content, name: 'approved.csv'}]));
      response.writeHead(200, {'content-type': 'application/json', 'content-length': body.length});
      response.end(body);
    } catch (cause) {response.destroy(cause);}
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const origin = `https://127.0.0.1:${server.address().port}`;
  const profile = Object.freeze({credentialPrivateKeyPath,
    credentialAuthorityId: 'content-fixture-authority', credentialKeyId: 'content-fixture-key',
    journalRoot: join(directory, 'credential-journal'), resourceOrigin: origin,
    namespaceId: 'content-fixture', environment: 'test', siteKey: 'content-fixture-site', siteGeneration: 0});
  return Object.freeze({origin,
    resolveSecret(scope) {
      assert.equal(scope.resourceOrigin, origin);
      assert.equal(scope.connectorRegistration, 'fixture');
      assert.equal(scope.operation, 'read');
      return 'content-source-fixture';
    },
    async load(_profile, options, referenceIssuer) {
      const {moon, installation, sourceInitialization} = options;
      const service = captureInstalledSourceServices(options.installationServices,
        () => {throw new Error('ContentFixtureInstallationServicesUnavailable');});
      const {declaration, declared, environment} = sourceInitialization.prepareDeclaration(fixture.declarationViewsWire);
      assert.equal(declared.catalog_cid, fixture.declared.catalog_cid);
      const policy = service('sourceReaderImplementationProfile', {installation,
        sourceInitialization, metadataResponses: 0, originUnits: origin.length});
      const limits = Object.freeze({maxPages: 1, maxPageBytes: 8192, maxPageRows: 1, maxCaptureRows: 1});
      // Every parsed JSON value occupies at least one original response byte.
      // The selected row array remains a span of that SAME response, without
      // an author transform or a second page. Preserve any tighter policy.
      const pageBounds = Object.freeze({maxNodes: Math.min(policy.maxNodes, limits.maxPageBytes),
        maxDepth: policy.maxDepth, maxCursorBytes: policy.maxCursorBytes});
      assert.ok(limits.maxPageBytes <= policy.maxResponseBytes);
      const implementationLimits = Object.freeze({...Object.fromEntries(
        [...installedJsonSourceReaderLimitNames, 'maxSecretBytes'].map(name => [name, policy[name]])),
        maxPages: limits.maxPages, maxResponseBytes: limits.maxPageBytes,
        maxTotalResponseBytes: Math.min(policy.maxTotalResponseBytes, limits.maxPages * limits.maxPageBytes),
        maxRowsWireBytes: Math.min(policy.maxRowsWireBytes, limits.maxPageBytes),
        maxRowsWireNodes: Math.min(policy.maxRowsWireNodes, limits.maxPageBytes),
        maxRows: limits.maxPageRows, maxTotalRows: limits.maxCaptureRows, ...pageBounds});
      const implementation = service('sourceReaderImplementation', {installation, sourceInitialization,
        limits: implementationLimits, columnCount: declared.views[0].fields.length});
      // The same native constructor reserves the complete target vector before
      // projection. These slots are DATA extents, not a replacement capacity.
      const targets = sourceInitialization.prepareReadTarget(Object.freeze({
        capacity: () => checked(moon.clientProgramInstalledSourceConstructionCapacity(8n, 0n, 0n, 8n, 0n, 0n)),
        project: () => Object.freeze([Object.freeze({resource: 'transfers',
          fields: Object.freeze([...declared.views[0].fields])})]),
      }));
      const ca = await options.configurationReader.readOriginalBytes(tls.caPath);
      const {site, authorization} = await service('openRowSite', {installation, sourceInitialization,
        accountConfiguration: account, connection: 'fixture:files', profile,
        resolveSecret: options.resolveSecret, ca, responseHeaders: [],
        runAcquisitionLimits: implementation.runAcquisitionLimits,
        admitsApprovalTarget: (value, resource) => resource === 'transfers' &&
          value !== null && typeof value === 'object' && value.resource === resource &&
          Array.isArray(value.fields) && value.fields.every(field => declared.views[0].fields.includes(field)),
      });
      let providerReader;
      try {
        const pages = restSourcePageReader({moon, source: {resource: 'transfers', read: {path: '/transfers'},
          fields: declared.views[0].fields.map(name => ({name})), pagination: {kind: 'none', items: []},
          limits: {...limits, maxRows: limits.maxCaptureRows, ...pageBounds}}});
        providerReader = service('createSourceReader', {installation, sourceInitialization,
          implementation, site, operation: 'read', preparePageReader(input, project) {
            assert.equal(input.resource, 'transfers');
            return pages(input, project);
          }});
        assert.equal(providerReader.capacity, implementation.capacity);
        return await createInstalledRowSource({moon, declaration, declared, environment, sourceInitialization,
          environmentWire: environment.wire, connectorId: 'content-fixture', connectorRegistration: 'fixture',
          connectorRevision: 'fixture/0.1', bindingCid: token('c'), referenceIssuer,
          authorization, site, readOperation: 'read', physicalTarget: targets, limits, providerReader});
      } catch (cause) {
        throw await retainInstalledHostInitializationFailure(cause,
          {sourceReader: providerReader, sourceProfile: site});
      }
    },
    async close() {
      server.closeAllConnections();
      await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    },
  });
}
