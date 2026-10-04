import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openRowSourceCredentialSite} from './installed-row-source.mjs';

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
