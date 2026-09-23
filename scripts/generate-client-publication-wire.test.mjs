import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {buildClientPublicationWire} from
  './generate-client-publication-wire.mjs';

const runPath = 'spec/contracts/actql-run-publication.json';
const protocolPath = 'spec/contracts/actql-protocol-schemas.json';
const registries = {
  [runPath]: JSON.parse(await readFile(runPath, 'utf8')),
  [protocolPath]: JSON.parse(await readFile(protocolPath, 'utf8')),
};

test('publication wire bindings match their registered schema owners',
  async () => {
    const output = buildClientPublicationWire(registries);
    assert.equal(output.module, await readFile(
      'packages/client-wire/publication.generated.js', 'utf8'));
    assert.equal(output.types, await readFile(
      'packages/client-wire/publication.generated.d.ts', 'utf8'));
  });

test('owner schema changes invalidate generated Client bindings', () => {
  const changed = structuredClone(registries);
  changed[runPath].schemas.delivery_attempt.properties.result_name.minLength = 2;
  assert.notEqual(buildClientPublicationWire(changed).module,
    buildClientPublicationWire(registries).module);
  changed[runPath].schemas.delivery_attempt.properties.result_name.newRule =
    true;
  assert.throws(() => buildClientPublicationWire(changed),
    /UnsupportedPublicationSchema:newRule/u);
});
