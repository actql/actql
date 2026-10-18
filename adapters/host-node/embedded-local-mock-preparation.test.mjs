import assert from 'node:assert/strict';
import test from 'node:test';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';

test('Mock preparation lookup is bound to one original Host/installation/generation', () => {
  const registry = createEmbeddedHostRegistry(() => false);
  const host = {}, installation = {}, view = Object.freeze({originalView: true});
  registry.registerPreparation(host, installation, host);
  registry.retainMockPreparation(host, installation, host, view);
  assert.equal(registry.mockPreparation(host, installation, host), view);
  assert.equal(registry.retainedMockPreparation(host, installation, host), view);
  for (const pair of [[{}, installation, host], [host, {...installation}, host],
    [host, installation, {}]]) {
    assert.throws(() => registry.mockPreparation(...pair), {code: 'InstalledHostPreparationChanged'});
    assert.throws(() => registry.retainedMockPreparation(...pair), {code: 'InstalledHostPreparationChanged'});
  }
  assert.throws(() => registry.retainMockPreparation(host, installation, host, view),
    {code: 'InstalledHostPreparationChanged'});
});

test('Mock preparation lookup never manufactures a missing or retired association', () => {
  const registry = createEmbeddedHostRegistry(() => false);
  const host = {}, installation = {};
  registry.registerPreparation(host, installation, host);
  assert.throws(() => registry.mockPreparation(host, installation, host),
    {code: 'InstalledHostPreparationChanged'});
  registry.retainMockPreparation(host, installation, host, Object.freeze({}));
  registry.retirePreparation(host, installation, host);
  assert.throws(() => registry.mockPreparation(host, installation, host),
    {code: 'InstalledHostPreparationChanged'});
});
