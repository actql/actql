import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {projectOwnerSources} from '../../../scripts/interface-owner-source-projection.mjs';
import {interfaceOwnerCoverage} from '../../../scripts/interface-owner-coverage.mjs';

test('reviewed Client facades retain exact original operations and independent Host custody references', () => {
  const owner = JSON.parse(readFileSync('scripts/interface-owners/client-facades/interface-boundaries.json'));
  const actual = projectOwnerSources(process.cwd(), {source: owner.source, base: owner.source,
    paths: owner.declarations.map(value => value.module), all: true});
  assert.equal(actual.modules.length, 43);
  const result = interfaceOwnerCoverage({root: process.cwd(), modules: actual.modules,
    owners: [{id: 'original Client facade and Host port boundary', ...owner}], generated: []});
  assert.equal(result.complete, true);
  assert.equal(result.covered, 43);
});
