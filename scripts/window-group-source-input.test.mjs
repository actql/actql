import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {windowGroupSourceSuccesses as normal, windowGroupSourceRefusals as refused,
  windowGroupSourceRows} from './fixtures/window-group-source-input.mjs';
import {sequenceIdentityOracle} from './sequence-identity-oracle.mjs';
import {signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';

test('window group independent rows preserve duplicate contributions and aggregate-local filters', () => {
  assert.equal(normal.length, 9);
  assert.equal(refused.length, 9);
  assert.deepEqual(windowGroupSourceRows, [
    {id: 3, amount: 30}, {id: 1, amount: null},
    {id: 2, amount: 20}, {id: 3, amount: 30},
  ]);
  const field = normal.find(c => c.name === 'window-group-json-field');
  const expression = normal.find(c => c.name === 'window-group-json-expression-filter-distinct');
  assert.deepEqual(field.results.answer.rows, [
    {window_start: 0, window_end: 60000, cohort: 'a', n: 2, total: 20},
    {window_start: 0, window_end: 60000, cohort: 'b', n: 2, total: 60},
  ]);
  assert.deepEqual(expression.results.answer.rows.map(r => r.total), [21, 31]);
  const program = JSON.parse(expression.text);
  assert.equal(program.stages.length, 2);
  assert.deepEqual(program.stages[1].inputs, {records: {result: {stage: 'capture', result: 'source'}}});
  const grouped = program.stages[1].steps.find(s => s.window_group).window_group;
  assert.deepEqual(grouped.aggregates.n, {fn: 'count'});
  assert.deepEqual(grouped.aggregates.total, {fn: 'sum',
    expr: {add: [{coalesce: [{field: 'amount'}, {literal: 0}]}, {literal: 1}]},
    filter: {not: {is_null: {field: 'amount'}}}, distinct: true});
});

test('SQL AQL and JSON controls share full ordered schemas and one acquisition including empty inputs', () => {
  const expectedColumns = [
    {name: 'window_start', contract: {type: 'number', nullable: false}},
    {name: 'window_end', contract: {type: 'number', nullable: false}},
    {name: 'cohort', contract: {type: 'string', nullable: false, max_utf8_bytes: 1}},
    {name: 'n', contract: {type: 'number', nullable: false}},
    {name: 'total', contract: {type: 'number', nullable: true}},
  ];
  for (const variant of ['field', 'expression-filter-distinct', 'empty']) {
    const cases = normal.filter(c => c.name.endsWith('-' + variant));
    assert.equal(cases.length, 3);
    assert.deepEqual(cases.map(c => c.format), ['json', 'sql', 'aql-text']);
    for (const c of cases) {
      const resultName = c.format === 'json' ? 'answer' : 'main';
      assert.equal(c.sourceReadSessionCount, 1);
      assert.deepEqual(c.results[resultName].columns, expectedColumns);
      assert.deepEqual(c.results, {[resultName]: cases[0].results.answer});
      if (variant === 'empty') {
        assert.deepEqual(c.sourceRows, []);
        assert.deepEqual(c.results[resultName].rows, []);
      }
    }
  }
});

test('window group public matrix uses normal module delivery and completed-case observations', () => {
  const acceptance = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const consumer = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(acceptance.includes('scopeInputs.successes.push(...windowGroupSourceSuccesses)'));
  assert.ok(acceptance.includes('scopeInputs.refusals.push(...windowGroupSourceRefusals)'));
  assert.ok(consumer.includes('--window-group-only'));
  assert.ok(consumer.includes("['scripts/fixtures/window-group-source-input.mjs', 'window-group-source-input.mjs']"));
  assert.ok(consumer.includes('window-group-receipts.local.json'));
  assert.ok(acceptance.includes("if (item.name.startsWith('window-group-')) await windowGroupReceipts.record(item, mode)"));
  for (const c of refused) assert.equal(c.expectedCode, 'ClientProgramInvalidInput');
});

const windowSource = '76ad7a71f078a53db76965c33a6d9717c06254ed';
const windowHistory = path => JSON.parse(execFileSync('git', ['show', `${windowSource}:${path}`],
  {encoding: 'utf8', maxBuffer: 4 * 1024 * 1024}));

test('window group registration changes only its declared nine controls and nine refusals', () => {
  const before = JSON.parse(readFileSync('scripts/fixtures/pre-window-group-public-query-inventory.json', 'utf8'));
  // Exact submitted inventory from 76ad7a71f078a53db76965c33a6d9717c06254ed.
  // Later registrations belong to the independently checked current pin.
  const submitted = readFileSync('scripts/fixtures/submitted-window-group-public-query-inventory.json');
  assert.equal(createHash('sha256').update(submitted).digest('hex'),
    '0821f649f37a036e489e556ca27566a150bcb15777225b7504408b82b34eb97b');
  const after = JSON.parse(submitted);
  assert.equal(after.version, before.version);
  assert.equal(after.sourceBaseline, before.sourceBaseline);
  assert.equal(after.totalCases, before.totalCases + 18);
  assert.deepEqual(after.counts, {...before.counts,
    successes: before.counts.successes + 9, refusals: before.counts.refusals + 9});
  assert.deepEqual(after.profiles[0], {name: before.profiles[0].name,
    counts: {...before.profiles[0].counts,
      successes: before.profiles[0].counts.successes + 9,
      refusals: before.profiles[0].counts.refusals + 9}});
  assert.deepEqual(after.profiles.slice(1), before.profiles.slice(1));
  assert.deepEqual(after.repeatedFailures, before.repeatedFailures);
});

test('window group history does not replace the exact current full registration pin', async () => {
  const {version, sourceBaseline, ...expected} = JSON.parse(
    readFileSync('scripts/fixtures/public-query-inventory.json', 'utf8'));
  assert.equal(version, 'actql-public-query-fixture-inventory/0.1');
  assert.equal(sourceBaseline, '76916b2b57ca8e06d9e74099349b17c263ccb411');
  const {registeredPublicQueryInventory} = await import('./public-query-inventory.mjs');
  assert.deepEqual(await registeredPublicQueryInventory(), expected);
});

test('window source rules change containing grammar and Run identity without rewriting parent preimages', () => {
  const before = JSON.parse(readFileSync('reviews/2026-10-13-frontend-window-group-source/preimages/parent-values-identities.json', 'utf8'));
  const current = sequenceIdentityOracle();
  assert.deepEqual(current, JSON.parse(readFileSync('scripts/fixtures/current-sequence-values-identities.json', 'utf8')));
  assert.deepEqual(current.grammar, JSON.parse(readFileSync('spec/manifests/actql-grammar-0.1.json', 'utf8')));
  const after = windowHistory('scripts/fixtures/current-sequence-values-identities.json');
  assert.equal(signatureRoleCid((({grammar_manifest_cid, ...body}) => body)(before.grammar)), before.grammar.grammar_manifest_cid);
  assert.deepEqual(after.grammar, windowHistory('spec/manifests/actql-grammar-0.1.json'));
  assert.deepEqual(after.values_dependencies, before.values_dependencies);
  assert.deepEqual(after.program_identity, before.program_identity);
  assert.deepEqual(after.run_preimages.executable.resolved_limits, before.run_preimages.executable.resolved_limits);
  assert.notEqual(after.run_preimages.run.run_definition_cid, before.run_preimages.run.run_definition_cid);
  const profile = JSON.parse(readFileSync('spec/frontend/frontend-profile-r1.json', 'utf8'));
  assert.ok(profile.features.find(f => f.feature_id === 'query.cte').surface_forms.some(f => f.startsWith('|> window_group(')));
  assert.match(readFileSync('spec/grammar/actql-query-0.1.ebnf', 'utf8'), /"window_group"/u);
});
