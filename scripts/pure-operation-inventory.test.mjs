import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {parameterPrograms} from './parameter-schema.mjs';
import {operationInventory} from './bound-transfer-laws.mjs';

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

function assertSourceGate(source) {
  const publicOperations = operationInventory(read('docs/spec/language.md'));
  const excluded = ['infer', 'search_candidates', 'serialize'];
  const exclusionParagraph = scope.split('\n\n').find(paragraph => paragraph.startsWith('No evaluator,'));
  assert.ok(exclusionParagraph, 'Missing explicit scope exclusions');
  for (const name of excluded) {
    assert.ok(publicOperations.includes(name), name);
    assert.ok(exclusionParagraph.includes('`' + name + '`'),
      `${name} must remain an explicit scope exclusion`);
  }
  const gate = source.match(/fn check_supported_source\([\s\S]*?match key \{([\s\S]*?)=> \(\)\s*_ => raise UnitBuildFailure::UnsupportedStaticPath\(step\)/);
  assert.ok(gate, 'Expected an explicit closed source gate with rejection fallback');
  const members = [...gate[1].matchAll(/"([a-z_]+)"/g)].map(match => match[1]);
  assert.equal(new Set(members).size, members.length, 'Duplicate source gate member');
  const metadata = ['from', 'as', 'meta'];
  // INFER is admitted by its checked ModelTask owner, not by the pure-operation
  // checker. Its registration must not expand the pure acceptance inventory.
  const barriers = ['infer'];
  assert.deepEqual(members.toSorted(), [
    ...metadata, ...barriers,
    ...publicOperations.filter(name => !excluded.includes(name)),
  ].toSorted());
  // This checks dispatch completeness only. It cannot replace the formal-entry
  // tests for Carrier alternatives, ownership, evidence and runtime obligations.
}

test('formal Program source gate covers the agreed operation domain without implicit omissions', () => {
  assertSourceGate(read('src/program_check/check.mbt'));
});

test('source gate audit detects omissions, unsupported additions and duplicate registrations', () => {
  const source = read('src/program_check/check.mbt');
  for (const replacement of ['', '| "serialize"', '| "sequence" | "sequence"']) {
    const changed = source.replace('| "sequence"', replacement);
    assert.notEqual(changed, source);
    assert.throws(() => assertSourceGate(changed));
  }
});
