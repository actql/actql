import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {parameterPrograms} from './parameter-schema.mjs';
import {checkProjectionSchemas} from './carrier-projection-schema.mjs';

test('explicit carrier projections require true in both embedded programs', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkProjectionSchemas(registry);
  for (const index of [0, 1]) for (const operation of ['events', 'vectors']) {
    const copy = structuredClone(registry);
    parameterPrograms(copy)[index].properties.steps.items.properties[operation] = {};
    assert.throws(() => checkProjectionSchemas(copy));
  }
});
