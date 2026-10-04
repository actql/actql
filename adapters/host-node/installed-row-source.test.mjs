import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {createInstalledRowSource, openRowSourceCredentialSite} from
  './installed-row-source.mjs';
import {installedSourceReadAccesses, installedSourceReadBindings} from
  './installed-source.mjs';

test('row source exposes exact read tuples for every declared view', async () => {
  const authorization = {authorize: async () => ({action: 'dispatch'}),
    accountConfiguration: '{}', context: {contextCid: 'context'}};
  const views = [{resource: 'issues', resource_kind: 'issue', fields:
    [{name: 'id', type: 'number', nullable: false}]},
  {resource: 'comments', resource_kind: 'comment', fields:
    [{name: 'id', type: 'number', nullable: false}]}];
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    'fixture', 'fixture', 'fixture/0.1', JSON.stringify({views}), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(
    declaration));
  const adapter = await createInstalledRowSource({moon, declaration,
    declared, environmentWire: '{}', connectorId: 'fixture',
    connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
    site: {connection: 'example:connection', close() {}}, authorization,
    readOperation: 'read', physicalTarget: () => ({}),
    readPages: async () => {}, bindingCid: `sha256:${'a'.repeat(64)}`,
    limits: {maxPages: 1, maxPageBytes: 1024, maxPageRows: 10,
      maxCaptureRows: 10}});
  assert.equal(adapter.sourceAccess.sourceRef, undefined);
  assert.deepEqual(installedSourceReadAccesses(adapter).map(access => ({
    sourceRef: access.sourceRef, resource: access.resource,
    connection: access.connection,
  })), declared.views.map(view => ({sourceRef: view.source_ref,
    resource: view.resource, connection: 'example:connection'})));
  assert.ok(installedSourceReadAccesses(adapter).every(access =>
    access.authorization === adapter.sourceAccess.authorization &&
    adapter.admitsSource(access.sourceRef)));
  assert.deepEqual(installedSourceReadBindings(adapter),
    declared.views.map(view => view.source_ref));
  assert.throws(() => installedSourceReadAccesses({sourceReadAccesses: []}),
    {message: 'InvalidInstalledSourceReadAccesses'});
  assert.throws(() => installedSourceReadBindings({...adapter,
    sourceReadAccesses: [adapter.sourceReadAccesses[0],
      adapter.sourceReadAccesses[0]]}),
  {message: 'InvalidInstalledSourceReadAccesses'});
  assert.throws(() => installedSourceReadBindings({...adapter,
    sourceReadAccesses: [{...adapter.sourceReadAccesses[0],
      sourceRef: 'connector://foreign/r#v'}]}),
  {message: 'InvalidInstalledSourceReadAccesses'});
});

test('the row source Site refuses an undeclared response header before any credential use',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-row-site-'));
    const key = generateKeyPairSync('ed25519');
    await writeFile(join(root, 'credential.key'), key.privateKey.export({
      type: 'pkcs8', format: 'pem'}));
    let resolved = 0;
    const site = await openRowSourceCredentialSite({
      profile: {credentialPrivateKeyPath: join(root, 'credential.key'),
        credentialAuthorityId: 'authority-a', credentialKeyId: 'key-a',
        journalRoot: join(root, 'journal'),
        resourceOrigin: 'https://api.example.test', namespaceId: 'namespace-a',
        environment: 'test', siteKey: 'site-a', siteGeneration: 1},
      principalId: 'principal-a',
      authorization: {issued: () => false, context: {contextCid: 'context'}},
      connection: 'example:connection', connectorRegistration: 'example',
      connectorRevision: 'example/0.1', runtimeBundleCid: `sha256:${'a'.repeat(64)}`,
      commonMoon: moon, resolveSecret: async () => { resolved++; return 'x'; },
      admitsApprovalTarget: () => false, responseHeaders: ['link']});
    // Close the Site before its directory is removed.
    t.after(async () => {
      site.close();
      await rm(root, {recursive: true, force: true});
    });
    assert.throws(() => site.callResource({operations: new Map([['op',
      {method: 'GET', path: '/x', responseHeaders: ['link', 'x-secret']}]])}),
    {code: 'UndeclaredResponseHeader'});
    assert.equal(resolved, 0);
    assert.deepEqual(site.credential.journal.recover(), []);
    await assert.rejects(openRowSourceCredentialSite({profile: {},
      responseHeaders: 'link'}), {code: 'InvalidRowSourceCredentialSite'});
  });
