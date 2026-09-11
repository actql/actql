import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {parameterPrograms} from './parameter-schema.mjs';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const scope = read('docs/design/pure-operation-checking.md');
const inventory = read('docs/design/pure-operation-test-inventory.md');
const rows = inventory.split('\n').filter(line => /^\| [a-z_]+(?:,| \|)/.test(line))
  .map(line => line.split('|').slice(1, -1).map(cell => cell.trim()));

test('acceptance evidence index covers the complete operation scope exactly once', () => {
  // Only the scope table defines this set, not the later out-of-scope prose.
  const tableNames = [...scope.split('Existing operation checking')[0].matchAll(/`([a-z_]+)`/g)]
    .map(match => match[1]);
  assert.equal(tableNames.length, 48);
  const actual = rows.flatMap(row => row[0].split(', '));
  assert.equal(new Set(actual).size, actual.length);
  assert.deepEqual(actual.toSorted(), tableNames.toSorted());
});

test('evidence paths exist and both embedded Program schemas contain each operation', () => {
  const registry = JSON.parse(read('spec/contracts/actql-protocol-schemas.json'));
  for (const [names, unit, pipeline, owner] of rows) {
    for (const path of [unit, pipeline]) {
      assert.match(path, /_test\.mbt$/);
      assert.match(read(path), /^test "/m, path);
    }
    assert.match(read(owner), /export function/, owner);
    for (const name of names.split(', ')) {
      for (const program of parameterPrograms(registry)) {
        assert.ok(Object.hasOwn(program.properties.steps.items.properties, name), name);
      }
    }
  }
});
