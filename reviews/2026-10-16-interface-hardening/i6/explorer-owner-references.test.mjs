import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {projectOwnerSources} from '../../../scripts/interface-owner-source-projection.mjs';
import {interfaceOwnerCoverage} from '../../../scripts/interface-owner-coverage.mjs';

test('reviewed Explorer references cover exact authored operations without granting Host or Run authority', () => {
  const owner = JSON.parse(readFileSync('scripts/interface-owners/explorer/interface-boundaries.json'));
  const actual = projectOwnerSources(process.cwd(), {source: owner.source, base: owner.source,
    paths: owner.declarations.map(value => value.module), all: true});
  assert.equal(actual.modules.length, 32);
  const result = interfaceOwnerCoverage({root: process.cwd(), modules: actual.modules,
    owners: [{id: 'original Explorer and SDK boundary', ...owner}], generated: []});
  assert.equal(result.complete, true);
  assert.equal(result.covered, 32);
});
