import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as sdk from '../packages/provider-ai-sdk/index.mjs';
import * as http from '../packages/provider-http/index.mjs';
import {createInstalledHttpChatRegistration} from '../packages/provider-http/_internal/installed-http-chat.mjs';
import {createRegisteredSdkProvider, createRegisteredSdkProviders} from '../packages/provider-ai-sdk/_internal/normal-openai-chat.mjs';

test('optional entries expose registered SDKs and the independent HTTP assembler', () => {
  assert.deepEqual(Object.keys(sdk), ['createRegisteredSdkProvider', 'createRegisteredSdkProviders']);
  assert.deepEqual(Object.keys(http), ['createInstalledHttpChatRegistration']);
  assert.strictEqual(sdk.createRegisteredSdkProvider, createRegisteredSdkProvider);
  assert.strictEqual(sdk.createRegisteredSdkProviders, createRegisteredSdkProviders);
  assert.strictEqual(http.createInstalledHttpChatRegistration, createInstalledHttpChatRegistration);
  for (const entry of [sdk, http]) {
    assert.equal(entry.startSdkTransport, undefined);
    assert.equal(entry.createHttpChatPreflight, undefined);
    assert.equal(entry.prepareTypeSafeDecisionRequest, undefined);
  }
});

test('entry packages require normal source admission before packing', () => {
  for (const name of ['provider-ai-sdk', 'provider-http']) {
    const value = JSON.parse(readFileSync(new URL(`../packages/${name}/package.json`, import.meta.url)));
    assert.equal(value.private, true);
    assert.equal(value.version, '0.0.0-development');
    assert.equal(value.license, 'Apache-2.0');
    assert.deepEqual(value.exports, {'.': {types: './index.d.ts', default: './index.mjs'}});
    assert.equal(value.scripts.prepack.split(' && ').at(-1),
      `node ../../scripts/check-interface-owners.mjs --manifest packages/${name}/package.json`);
    assert.ok(value.files.includes('LICENSE'));
    assert.deepEqual(readFileSync(new URL(`../packages/${name}/LICENSE`, import.meta.url)),
      readFileSync(new URL('../LICENSE', import.meta.url)));
  }
  assert.deepEqual(JSON.parse(readFileSync(new URL('../packages/provider-http/package.json', import.meta.url))).dependencies, {});
});

test('external SDK shrinkwrap preserves the exact original dependency bytes', () => {
  const original = readFileSync(new URL('../packages/provider-ai-sdk/package-lock.json', import.meta.url));
  const shrinkwrap = readFileSync(new URL('../packages/provider-ai-sdk/npm-shrinkwrap.json', import.meta.url));
  assert.deepEqual(shrinkwrap, original);
  const lock = JSON.parse(original);
  assert.equal(lock.packages['node_modules/@ai-sdk/openai'].version, '4.0.91');
  assert.equal(lock.packages['node_modules/@ai-sdk/google'].version, '4.0.124');
  assert.equal(lock.packages['node_modules/@ai-sdk/typesafe-ai'].version, '3.0.13');
  assert.equal(lock.packages['node_modules/undici'].version, '7.30.0');
  assert.equal(lock.packages[''].dependencies.undici, '7.30.0');
  const manifest = JSON.parse(readFileSync(new URL('../packages/provider-ai-sdk/package.json', import.meta.url)));
  assert.equal(manifest.dependencies.undici, '7.30.0');
  assert.equal(manifest.dependencies['@ai-sdk/provider-utils'], '5.0.58');
  // The older support library is also a direct pin so npm preserves the same
  // shared physical placement for OpenAI and the root Provider utilities.
  assert.equal(manifest.dependencies['@ai-sdk/provider'], '4.0.26');
  assert.equal(lock.packages[''].dependencies['@ai-sdk/provider'], '4.0.26');
  assert.equal(lock.packages['node_modules/@ai-sdk/anthropic/node_modules/@ai-sdk/provider'].version, '4.0.39');
  assert.equal(lock.packages['node_modules/@ai-sdk/google/node_modules/@ai-sdk/provider'].version, '4.0.39');
  assert.equal(lock.packages[''].dependencies['@ai-sdk/provider-utils'], '5.0.58');
  assert.equal(lock.packages['node_modules/@ai-sdk/provider-utils'].version, '5.0.58');
  assert.deepEqual(manifest.peerDependencies, lock.packages[''].peerDependencies);
  const local = JSON.parse(readFileSync(new URL('../packages/local-node/package.json', import.meta.url)));
  assert.deepEqual(manifest.peerDependencies, {'@actql/local-node': local.version,
    zod: lock.packages['node_modules/zod'].version});
  for (const [name, entry] of Object.entries(lock.packages)) {
    if (name === '') continue;
    assert.match(entry.resolved, /^https:\/\/registry\.npmjs\.org\//u);
    assert.match(entry.integrity, /^sha512-/u);
    assert.equal(entry.link, undefined);
  }
});
