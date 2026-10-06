import assert from 'node:assert/strict';
import {X509Certificate, createPrivateKey} from 'node:crypto';
import {copyFile, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';

test('TLS test certificates prepare outside a checkout without a compiled runtime', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-test-certificates-'));
  t.after(() => rm(root, {recursive:true, force:true}));
  // A standalone copy has no checkout, dependencies or _build path to import.
  const helper = join(root, 'certificates.mjs');
  await copyFile(new URL('./https-test-certificates.mjs', import.meta.url), helper);
  const {certificates} = await import(pathToFileURL(helper));
  const material = await certificates(root);
  const ca = new X509Certificate(material.ca);
  const site = new X509Certificate(material.siteCertificate);
  const coordinator = new X509Certificate(material.coordinatorCertificate);
  const foreign = new X509Certificate(material.foreignCertificate);
  assert.equal(Object.isFrozen(material), true);
  assert.equal(ca.subject, 'CN=ActQL Remote Test CA');
  assert.equal(ca.verify(ca.publicKey), true);
  assert.equal(site.checkHost('localhost'), 'localhost');
  assert.equal(site.checkIP('127.0.0.1'), '127.0.0.1');
  for (const certificate of [site, coordinator, foreign]) {
    assert.equal(certificate.verify(ca.publicKey), true);
  }
  assert.equal(coordinator.subject, 'CN=coordinator-a');
  assert.equal(foreign.subject, 'CN=foreign-coordinator');
  assert.equal(material.coordinatorFingerprint, coordinator.fingerprint256);
  assert.notEqual(coordinator.fingerprint256, foreign.fingerprint256);
  for (const [certificate, key] of [
    [site, material.siteKey], [coordinator, material.coordinatorKey], [foreign, material.foreignKey],
  ]) {
    assert.equal(certificate.checkPrivateKey(createPrivateKey(key)), true);
  }
});
