import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {buildClientHostWire} from './generate-client-host-wire.mjs';

const registry = JSON.parse(await readFile(new URL(
  '../spec/contracts/actql-client-host.json', import.meta.url), 'utf8'));
const protocol = JSON.parse(await readFile(new URL(
  '../spec/contracts/actql-protocol-schemas.json', import.meta.url), 'utf8'));

test('generated Client–Host guards and types match the machine contract',
  async () => {
    const outputs = buildClientHostWire(registry, protocol);
    assert.equal(outputs.module, await readFile(new URL(
      '../packages/client-wire/client-host.generated.js', import.meta.url),
    'utf8'));
    assert.equal(outputs.types, await readFile(new URL(
      '../packages/client-wire/client-host.generated.d.ts', import.meta.url),
    'utf8'));
  });

test('schema and operation mutations invalidate generated Client–Host wire',
  () => {
    const original = buildClientHostWire(registry, protocol);
    const changed = structuredClone(registry);
    changed.schemas.profile.properties.limits.properties.maxRows.minimum = 2;
    assert.notEqual(buildClientHostWire(changed, protocol).module,
      original.module);
    changed.operations.connect.push('nonce');
    assert.notEqual(buildClientHostWire(changed, protocol).module,
      original.module);
    changed.schemas.profile.properties.limits.properties.maxRows.type = 'number';
    assert.throws(() => buildClientHostWire(changed, protocol),
      /UnsupportedPublicationType/);
    const changedState = structuredClone(protocol);
    changedState.artifact_schemas.run_state.properties.run_id.minLength = 2;
    assert.notEqual(buildClientHostWire(registry, changedState).module,
      original.module);
  });
