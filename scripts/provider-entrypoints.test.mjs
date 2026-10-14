import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as sdk from '../packages/provider-ai-sdk/index.mjs';
import * as http from '../packages/provider-http/index.mjs';
import {createInstalledOpenAIChatRegistration} from '../packages/provider-ai-sdk/_internal/installed-openai-chat.mjs';
import {createInstalledHttpChatRegistration} from '../packages/provider-http/_internal/installed-http-chat.mjs';

test('optional entries expose the original Host assemblers only', () => {
  assert.deepEqual(Object.keys(sdk), ['createInstalledOpenAIChatRegistration']);
  assert.deepEqual(Object.keys(http), ['createInstalledHttpChatRegistration']);
  assert.strictEqual(sdk.createInstalledOpenAIChatRegistration, createInstalledOpenAIChatRegistration);
  assert.strictEqual(http.createInstalledHttpChatRegistration, createInstalledHttpChatRegistration);
  for (const entry of [sdk, http]) {
    assert.equal(entry.startSdkTransport, undefined);
    assert.equal(entry.createHttpChatPreflight, undefined);
    assert.equal(entry.prepareTypeSafeDecisionRequest, undefined);
  }
});

test('entry packages retain development status and contain no runtime builder', () => {
  for (const name of ['provider-ai-sdk', 'provider-http']) {
    const value = JSON.parse(readFileSync(new URL(`../packages/${name}/package.json`, import.meta.url)));
    assert.equal(value.private, true);
    assert.equal(value.version, '0.0.0-development');
    assert.equal(value.license, 'Apache-2.0');
    assert.deepEqual(value.exports, {'.': {types: './index.d.ts', default: './index.mjs'}});
    assert.equal(value.scripts, undefined);
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
  assert.equal(lock.packages['node_modules/@ai-sdk/typesafe-ai'].version, '3.0.13');
  const manifest = JSON.parse(readFileSync(new URL('../packages/provider-ai-sdk/package.json', import.meta.url)));
  assert.deepEqual(manifest.peerDependencies, {zod: lock.packages['node_modules/zod'].version});
  for (const [name, entry] of Object.entries(lock.packages)) {
    if (name === '') continue;
    assert.match(entry.resolved, /^https:\/\/registry\.npmjs\.org\//u);
    assert.match(entry.integrity, /^sha512-/u);
    assert.equal(entry.link, undefined);
  }
});
