import assert from 'node:assert/strict';
import test from 'node:test';
import {checkInstalledGcsSourceProfile} from '../host/gcs-source-declaration.mjs';

const profile = prefix => ({version: 'actql-installed-gcs-source/0.1', connectorId: 'storage',
  project: 'fixture-project', bucket: 'actql-fixture', prefix,
  mediaType: 'application/pdf', siteProfilePath: '/fixture/site.json', accountConfigurationWire: '{}',
  limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
    maxListingBytes: 32768, maxDurationMs: 10000, maxPathBytes: 1024,
    maxPageBytes: 8192, maxPageItems: 9, maxRequestBytes: 4096, maxContentBytes: 4096}});

test('opaque prefix profile retains exact Unicode and control data without normalization', () => {
  for (const prefix of ['', 'test/e\u0301\t\0\u007f%2F/', 'test/é\t\0\u007f%2F/',
    'a'.repeat(1024), 'é'.repeat(512)]) {
    const input = profile(prefix), selected = checkInstalledGcsSourceProfile(input);
    input.prefix = 'foreign/';
    assert.equal(selected.prefix, prefix);
    assert.equal(Object.isFrozen(selected), true);
  }
});

test('opaque prefix profile keeps scalar and UTF8 ceilings and other profile checks', () => {
  for (const prefix of [undefined, null, 0, {}, 'x\ud800', 'a'.repeat(1025), 'é'.repeat(513)]) {
    assert.throws(() => checkInstalledGcsSourceProfile(profile(prefix)),
      {code: 'InvalidInstalledGcsSourceProfile'});
  }
  for (const field of ['connectorId', 'project', 'bucket', 'siteProfilePath']) {
    const input = profile('test/');
    input[field] += '\0';
    assert.throws(() => checkInstalledGcsSourceProfile(input),
      {code: 'InvalidInstalledGcsSourceProfile'});
  }
});
