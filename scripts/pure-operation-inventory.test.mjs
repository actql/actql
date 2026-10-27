import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {parameterPrograms} from './parameter-schema.mjs';
import {operationInventory} from './operation-inventory.mjs';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const scope = read('docs/design/pure-operation-checking.md');
const inventory = read('docs/design/pure-operation-test-inventory.md');
// Reuse the existing authoritative profile classification, not a second
// operation support list maintained by this navigation index.
const graphClassification = JSON.parse(read(
  'docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json',
)).current_graph_profile.classification;
const refused = name => graphClassification[name] === 'blocked';
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
  assert.deepEqual(Object.keys(graphClassification).filter(refused).toSorted(),
    [],
    'Current bounded Graph connections are partial, not completed coverage');
  for (const [names, unit, pipeline, owner] of rows) {
    const operations = names.split(', ');
    if (operations.some(refused)) {
      assert.ok(operations.every(refused), 'Do not mix refusal and execution evidence');
      assert.equal(pipeline, 'scripts/graph-public-host.test.mjs');
      const publicRefusal = read(pipeline);
      assert.ok(publicRefusal.includes('coverage.current_graph_profile.classification[entry.operation]'));
      // The epoch-bound API retains an exact non-acceptance outcome. A
      // missing legacy request ID cannot prove that no Run was admitted.
      const helper = publicRefusal.match(
        /async function assertRejectedSubmission\([^]*?\n\}/u)?.[0];
      assert.ok(helper, 'Missing public Submission refusal helper');
      for (const obligation of [
        "await assert.rejects(client.startSource(source, {format: 'json', submissionRef}), error => {",
        'assert.ok(error instanceof ClientError);',
        "assert.equal(error.code, 'SubmissionNotAccepted');",
        'outcome = getSubmissionOutcome(error);',
        "assert.equal(outcome.kind, 'not_accepted');",
        'assert.deepEqual(outcome.submissionRef, submissionRef);',
        'assert.equal(outcome.problem.code, code);',
        "assert.equal(Object.hasOwn(outcome, 'admission'), false);",
        'assert.deepEqual(await client.lookupSubmission(submissionRef), outcome);',
      ]) assert.ok(helper.includes(obligation), obligation);
      const refusal = publicRefusal.match(
        /if \(profile === 'graph'\) \{([^]*?)\n      t\.diagnostic/u)?.[1];
      assert.ok(refusal, 'Missing inventory-backed public Graph refusal cases');
      for (const obligation of [
        'for (const entry of unsupported) for (const externalInput of [false,true])',
        'const submissionRef = client.newSubmission({nonce: requestId});',
        "await assertRejectedSubmission(client, canonicalText(rejected), submissionRef, 'ClientProgramImplementationLimit');",
        'assert.deepEqual(physicalSteps.slice(before), [],',
        'assert.equal(snapshots.size, 0);',
      ]) assert.ok(refusal.includes(obligation), obligation);
    }
    for (const path of [unit, pipeline]) {
      if (path === 'scripts/graph-public-host.test.mjs') {
        assert.ok(operations.every(refused), 'Public refusal is not execution evidence');
        assert.match(read(path), /^\s*test\(/m, path);
      } else {
        assert.match(path, /_(?:wb)?test\.mbt$/);
        assert.match(read(path), /^test "/m, path);
      }
    }
    assert.match(read(owner), /export function/, owner);
    for (const name of operations) {
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
  // INFER and SERIALIZE are admitted by their checked acquisition/content
  // owners, not as pure operations. Source registration is preparation evidence;
  // it must not expand the pure execution acceptance inventory.
  const barriers = ['infer', 'serialize'];
  assert.deepEqual(members.toSorted(), [
    ...metadata, ...barriers,
    ...publicOperations.filter(name => !excluded.includes(name) && !refused(name)),
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
  for (const name of Object.keys(graphClassification).filter(refused)) {
    const changed = source.replace('| "sequence"', `| "sequence" | "${name}"`);
    assert.notEqual(changed, source);
    assert.throws(() => assertSourceGate(changed), `${name} must not silently re-enter the source gate`);
  }
  for (const name of ['infer', 'serialize']) {
    const changed = source.replace(`| "${name}"`, '');
    assert.notEqual(changed, source);
    assert.throws(() => assertSourceGate(changed), `${name} needs its explicit barrier registration`);
  }
});
