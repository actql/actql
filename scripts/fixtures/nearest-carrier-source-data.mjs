// Original independent NEAREST inputs; this module never evaluates a query.
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
export const nearestCarrierFixtureDirectory = fileURLToPath(new URL('../../spec/frontend/fixtures/nearest-keep/', import.meta.url));
const program = JSON.parse(await readFile(new URL('../../spec/frontend/fixtures/nearest-keep/common-minimal.program.json', import.meta.url), 'utf8'));
const original = program.stages[0].steps.filter(step => step.values).map(step => step.values);
const freeze = value => {
  if (value !== null && typeof value === 'object') {
    for (const item of Object.values(value)) freeze(item);
    Object.freeze(value);
  }
  return value;
};
export const nearestCarrierSourceRows = freeze({queries: original[0].rows, candidates: original[1].rows});
// Checked Source contracts, independently authored from the original schema
// and the normative fixed f32 machine representation. Author schemas are kept.
export const nearestCarrierSourceSchemas = freeze({
  "queries": {
    "request_id": {
      "type": "string",
      "nullable": false
    },
    "embedding": {
      "type": "vector",
      "dimensions": 2,
      "nullable": false,
      "element_type": "f32"
    },
    "note": {
      "type": "string",
      "nullable": true
    }
  },
  "candidates": {
    "item_id": {
      "type": "string",
      "nullable": false
    },
    "embedding": {
      "type": "vector",
      "dimensions": 2,
      "nullable": false,
      "element_type": "f32"
    },
    "label": {
      "type": "string",
      "nullable": false
    }
  }
});
