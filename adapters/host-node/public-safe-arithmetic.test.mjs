import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Independent finite-binary64 vectors from the GoogleSQL SAFE arithmetic
// and floating-point overflow contracts. The ordinary 5+4, 5-4, 20*4,
// 20/4, zero-divisor and +/-1 examples mirror the documented examples; the
// remaining binary64 boundaries are independently derived. No live BigQuery or host arithmetic
// provides expectations. INT64/NUMERIC/BIGNUMERIC and nonfinite are excluded.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#safe_divide
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types#floating_point_semantics
const literal = value => ({literal: value});
const number = (name, text, expression, expected, nullable = true) =>
  ({name, text, expression, expected, contract: {type: 'number', nullable}});
const binaryOps = ['safe_add', 'safe_subtract', 'safe_multiply', 'safe_divide'];
const allOps = [...binaryOps, 'safe_negate'];
const batches = [
  {id: 'ordinary', cases: [
    number('addition', 'SAFE_ADD(5, 4)', {safe_add: [literal(5), literal(4)]}, 9),
    number('subtraction', 'SAFE_SUBTRACT(5, 4)', {safe_subtract: [literal(5), literal(4)]}, 1),
    number('multiplication', 'SAFE_MULTIPLY(20, 4)', {safe_multiply: [literal(20), literal(4)]}, 80),
    number('division', 'SAFE_DIVIDE(20, 4)', {safe_divide: [literal(20), literal(4)]}, 5),
    number('signed_division', '`SaFe_DiViDe`(1, -2)', {safe_divide: [literal(1), literal(-2)]}, -0.5),
    number('negation', 'SAFE_NEGATE(-1)', {safe_negate: literal(-1)}, 1, false),
    number('rounding', 'SAFE_ADD(9007199254740992.0, 1)', {safe_add: [literal(9007199254740992), literal(1)]}, 9007199254740992),
  ]},
  {id: 'overflow', cases: [
    number('add_overflow', 'SAFE_ADD(1.7976931348623157e308, 1.7976931348623157e308)', {safe_add: [literal(1.7976931348623157e308), literal(1.7976931348623157e308)]}, null),
    number('subtract_overflow', 'SAFE_SUBTRACT(-1.7976931348623157e308, 1.7976931348623157e308)', {safe_subtract: [literal(-1.7976931348623157e308), literal(1.7976931348623157e308)]}, null),
    number('multiply_overflow', 'SAFE_MULTIPLY(1.7976931348623157e308, -2)', {safe_multiply: [literal(1.7976931348623157e308), literal(-2)]}, null),
    number('divide_overflow', 'SAFE_DIVIDE(1.7976931348623157e308, 0.5)', {safe_divide: [literal(1.7976931348623157e308), literal(0.5)]}, null),
    number('divide_subnormal', 'SAFE_DIVIDE(1, 5e-324)', {safe_divide: [literal(1), literal(5e-324)]}, null),
    number('divide_zero', 'SAFE_DIVIDE(20, 0)', {safe_divide: [literal(20), literal(0)]}, null),
    number('zero_by_zero', 'SAFE_DIVIDE(0, 0)', {safe_divide: [literal(0), literal(0)]}, null),
  ]},
  {id: 'extremes', cases: [
    number('add_max', 'SAFE_ADD(1.7976931348623157e308, 0)', {safe_add: [literal(1.7976931348623157e308), literal(0)]}, 1.7976931348623157e308),
    number('multiply_max', 'SAFE_MULTIPLY(1.7976931348623157e308, -1)', {safe_multiply: [literal(1.7976931348623157e308), literal(-1)]}, -1.7976931348623157e308),
    number('negate_max', 'SAFE_NEGATE(1.7976931348623157e308)', {safe_negate: literal(1.7976931348623157e308)}, -1.7976931348623157e308, false),
    number('negate_min', 'SAFE_NEGATE(-1.7976931348623157e308)', {safe_negate: literal(-1.7976931348623157e308)}, 1.7976931348623157e308, false),
    number('tiny', 'SAFE_ADD(5e-324, 5e-324)', {safe_add: [literal(5e-324), literal(5e-324)]}, 1e-323),
    number('underflow', 'SAFE_DIVIDE(-5e-324, 2)', {safe_divide: [literal(-5e-324), literal(2)]}, 0),
    number('multiply_underflow', 'SAFE_MULTIPLY(-5e-324, 0.5)', {safe_multiply: [literal(-5e-324), literal(0.5)]}, 0),
    number('negate_zero', 'SAFE_NEGATE(0)', {safe_negate: literal(0)}, 0, false),
  ]},
  {id: 'null', cases: [
    number('add_null', 'SAFE_ADD(NULL, 1)', {safe_add: [literal(null), literal(1)]}, null),
    number('subtract_null', 'SAFE_SUBTRACT(1, NULL)', {safe_subtract: [literal(1), literal(null)]}, null),
    number('multiply_null', 'SAFE_MULTIPLY(NULL, NULL)', {safe_multiply: [literal(null), literal(null)]}, null),
    number('divide_null', 'SAFE_DIVIDE(NULL, 0)', {safe_divide: [literal(null), literal(0)]}, null),
    number('negate_null', 'SAFE_NEGATE(NULL)', {safe_negate: literal(null)}, null),
  ]},
];

function program(id, cases, params) {
  const names = cases.map(item => item.name);
  return {version: 'actql/0.1', id, ...(params ? {params} : {}), stages: [{
    id: 'main', inputs: {}, steps: [
      {values: {schema: {unit: {type: 'boolean', nullable: false}},
        rows: [{unit: true}]}, as: 'seed'},
      {from: 'seed', derive: Object.fromEntries(cases.map(item =>
        [item.name, item.expression])), as: 'derived'},
      {select: names, as: 'out'},
    ], results: {rows: {from: 'out', fields: names}},
  }], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}

function sourceFor(format, id, cases, params) {
  if (format === 'json') return JSON.stringify(program(id, cases, params));
  const select = 'SELECT ' + cases.map(item => `${item.text} AS ${item.name}`).join(', ');
  return format === 'aql-text' ? 'SELECT TRUE AS unit |> ' + select : select;
}

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-safe-arithmetic-'));
  const keys = generateKeyPairSync('ed25519');
  let client;
  let dispatches = 0;
  let advances = 0;
  let computed;
  t.after(async () => {
    await client?.close();
    await rm(directory, {recursive: true, force: true});
  });
  client = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation: {
    directory, retainedRelationOutput: true, authorization: {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1', account_id: 'safe-arithmetic',
        entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true}, operation: {all: true},
          exclusions: []}],
      }),
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      observe(name, detail) { if (name === 'computed') computed = detail; },
      faultInjection(name) {
        if (name === 'dispatch_reserved') dispatches++;
        if (name === 'local_compute_advanced') advances++;
      },
    },
  }});
  return {client, dispatches: () => dispatches, advances: () => advances,
    computed: () => computed};
}

async function assertPublished(f, source, options, cases) {
  const beforeAdvances = f.advances();
  const run = await f.client.startSource(source, options);
  const state = await run.wait({signal: AbortSignal.timeout(15_000)});
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const expected = [Object.fromEntries(cases.map(item => [item.name, item.expected]))];
  const columns = cases.map(item => ({name: item.name, contract: item.contract}));
  const actual = await run.result('answer').all();
  assert.deepEqual(actual, expected);
  for (const value of Object.values(actual[0])) {
    if (value !== null) {
      assert.ok(Number.isFinite(value));
      assert.ok(!Object.is(value, -0), 'published zero is canonical');
    }
  }
  assert.deepEqual((await run.result('answer').describe()).columns, columns);
  assert.ok(f.advances() > beforeAdvances, 'ordinary execution must make charged Local progress');
  assert.ok(f.computed().outputRepresentations.some(entry => entry.representation === 'retained-file'));
  const before = f.dispatches();
  assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
  const attached = await f.client.attach(run.ref);
  assert.deepEqual(await attached.result('answer').all(), expected);
  assert.deepEqual((await attached.result('answer').describe()).columns, columns);
  assert.equal(f.dispatches(), before, 'resend and retained reread must not dispatch again');
}

async function assertRefused(f, source, options) {
  await assert.rejects(f.client.startSource(source, options), error => {
    assert.equal(error.code, 'SubmissionNotAccepted');
    const outcome = getSubmissionOutcome(error);
    assert.equal(outcome.kind, 'not_accepted');
    assert.deepEqual(outcome.submissionRef, options.submissionRef);
    assert.equal(outcome.problem.code, 'ClientProgramInvalidInput');
    return true;
  });
}


test('public SQL Pipe and independent JSON publish SAFE arithmetic with complete schemas',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    for (const batch of batches) for (const format of ['sql', 'aql-text', 'json']) {
      const source = sourceFor(format, 'safe_arithmetic_' + batch.id, batch.cases);
      await assertPublished(f, source, {format,
        submissionRef: f.client.newSubmission({nonce: `${batch.id}-${format}`})}, batch.cases);
    }
  });

test('public SAFE arithmetic parameters preserve always-nullable binary and precise unary schemas',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p: {type: 'number', nullable: true}, q: {type: 'number', nullable: false}};
    for (const [id, parameters, negated] of [['value', {p: -2, q: 2}, 2], ['null', {p: null, q: 2}, null]]) {
      const cases = [
        number('nullable_negate', 'SAFE_NEGATE(@p)', {safe_negate: {$param: 'p'}}, negated),
        number('required_negate', 'SAFE_NEGATE(@q)', {safe_negate: {$param: 'q'}}, -2, false),
        number('required_add', 'SAFE_ADD(@q, 1)', {safe_add: [{$param: 'q'}, literal(1)]}, 3),
        number('nullable_divide', 'SAFE_DIVIDE(@p, 0)', {safe_divide: [{$param: 'p'}, literal(0)]}, null),
      ];
      for (const format of ['sql', 'aql-text', 'json']) {
        await assertPublished(f, sourceFor(format, 'safe_parameters', cases, parameterDeclarations),
          {format, parameters, ...(format !== 'json' ? {parameterDeclarations} : {}),
            submissionRef: f.client.newSubmission({nonce: `${id}-${format}`})}, cases);
      }
    }
  });

test('public SAFE arithmetic rejects malformed arities wrong domains and nonfinite before dispatch',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const decimal = {cast: {target: {type: 'decimal', precision: 8, scale: 3}, value: literal('1.25')}};
    for (const op of allOps) {
      const unary = op === 'safe_negate';
      const invalid = [
        {text: `${op}()`, expression: {[op]: []}},
        {text: `${op}(1, 2, 3)`, expression: {[op]: [literal(1), literal(2), literal(3)]}},
        {text: unary ? `${op}(1, 2)` : `${op}(1)`, expression: {[op]: unary ? [literal(1), literal(2)] : [literal(1)]}},
      ];
      for (const [text, value] of [["'2'", literal('2')], ['TRUE', literal(true)], ["CAST('1.25' AS DECIMAL(8,3))", decimal]]) {
        invalid.push({text: `${op}(${unary ? text : '1, ' + text})`, expression: {[op]: unary ? value : [literal(1), value]}});
      }
      for (const [index, item] of invalid.entries()) for (const format of ['sql', 'aql-text', 'json']) {
        await assertRefused(f, sourceFor(format, 'safe_invalid', [{name: 'value', ...item}]),
          {format, submissionRef: f.client.newSubmission({nonce: `${op}-${index}-${format}`})});
      }
      for (const format of ['sql', 'aql-text', 'json']) {
        const expression = {[op]: unary ? literal('NONFINITE_TOKEN') : [literal(1), literal('NONFINITE_TOKEN')]};
        const source = format === 'json' ? sourceFor(format, 'safe_nonfinite', [{name: 'value', expression}]).replace('"NONFINITE_TOKEN"', '1e309')
          : sourceFor(format, 'safe_nonfinite', [{name: 'value', text: `${op}(${unary ? '1e309' : '1, 1e309'})`}]);
        await assertRefused(f, source, {format, submissionRef: f.client.newSubmission({nonce: `nonfinite-${op}-${format}`})});
      }
    }
    assert.equal(f.dispatches(), 0);
    assert.equal(f.advances(), 0);
  });

test('public SAFE arithmetic preserves demanded child failures and failed rereads',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    for (const op of allOps) for (const format of ['sql', 'aql-text', 'json']) {
      const unary = op === 'safe_negate';
      const divide = {divide: [literal(1), literal(0)]};
      // NULL left still demands the failed right operand.
      const cases = [{name: 'value', text: `${op}(${unary ? '1 / 0' : 'NULL, 1 / 0'})`, expression: {[op]: unary ? divide : [literal(null), divide]}}];
      const source = sourceFor(format, 'safe_demanded_' + op, cases);
      const options = {format, submissionRef: f.client.newSubmission({nonce: `demanded-${op}-${format}`})};
      const beforeDispatches = f.dispatches();
      const run = await f.client.startSource(source, options);
      const state = await run.wait({signal: AbortSignal.timeout(15_000)});
      assert.equal(state.status, 'failed', JSON.stringify(state));
      assert.ok(f.dispatches() > beforeDispatches);
      assert.equal(state.result_availability.answer.state, 'unavailable');
      await assert.rejects(run.result('answer').all());
      await assert.rejects(run.result('answer').describe());
      const before = f.dispatches();
      assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
      const attached = await f.client.attach(run.ref);
      assert.equal((await attached.status()).status, 'failed');
      await assert.rejects(attached.result('answer').all());
      await assert.rejects(attached.result('answer').describe());
      assert.equal(f.dispatches(), before);
    }
  });

test('public SAFE arithmetic preserves lazy branches and nested overflow recovery',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const divide = {divide: [literal(1), literal(0)]};
    const cases = [
      number('inside', 'SAFE_ADD(IF(TRUE, 1, 1 / 0), 2)', {safe_add: [{if: [literal(true), literal(1), divide]}, literal(2)]}, 3),
      number('outside', 'IF(FALSE, SAFE_DIVIDE(NULL, 1 / 0), 7)', {if: [literal(false), {safe_divide: [literal(null), divide]}, literal(7)]}, 7),
      number('coalesced', 'COALESCE(SAFE_MULTIPLY(1.7976931348623157e308, 2), 7)', {coalesce: [{safe_multiply: [literal(1.7976931348623157e308), literal(2)]}, literal(7)]}, 7, false),
      number('nested', 'SAFE_DIVIDE(1, SAFE_SUBTRACT(1, 1))', {safe_divide: [literal(1), {safe_subtract: [literal(1), literal(1)]}]}, null),
      number('lazy_negate', 'IF(FALSE, SAFE_NEGATE(1 / 0), 7)', {if: [literal(false), {safe_negate: divide}, literal(7)]}, 7, false),
    ];
    for (const format of ['sql', 'aql-text', 'json']) await assertPublished(f, sourceFor(format, 'safe_lazy', cases),
      {format, submissionRef: f.client.newSubmission({nonce: 'lazy-' + format})}, cases);
  });

test('public SAFE arithmetic empty relations still publish complete nullable schemas',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const cases = [
      number('safe_value', 'SAFE_DIVIDE(1, 0)', {safe_divide: [literal(1), literal(0)]}, null),
      number('negated', 'SAFE_NEGATE(1)', {safe_negate: literal(1)}, -1, false),
    ];
    const source = program('safe_empty', cases);
    source.stages[0].steps[0].values.rows = [];
    const run = await f.client.startSource(JSON.stringify(source), {format: 'json', submissionRef: f.client.newSubmission({nonce: 'empty'})});
    assert.equal((await run.wait({signal: AbortSignal.timeout(15_000)})).status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), []);
    assert.deepEqual((await run.result('answer').describe()).columns, cases.map(item => ({name: item.name, contract: item.contract})));
  });

test('public SAFE arithmetic ordered derive preserves input fields and earlier binding slots',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const cases = [
      number('sum', '', {safe_add: [{field: 'original'}, {field: 'right'}]}, 6),
      number('difference', '', {safe_subtract: [{field: 'sum'}, {field: 'right'}]}, 4),
      number('product', '', {safe_multiply: [{field: 'difference'}, {field: 'right'}]}, 8),
      number('quotient', '', {safe_divide: [{field: 'product'}, {field: 'right'}]}, 4),
      number('negated', '', {safe_negate: {field: 'quotient'}}, -4),
    ];
    const source = program('safe_ordered_fields', cases);
    source.stages[0].steps[0].values = {
      schema: {left: {type: 'number', nullable: false}, right: {type: 'number', nullable: false}},
      rows: [{left: 4, right: 2}],
    };
    source.stages[0].steps[1].derive = [{original: {field: 'left'}},
      ...cases.map(item => ({[item.name]: item.expression}))];
    await assertPublished(f, JSON.stringify(source), {format: 'json',
      submissionRef: f.client.newSubmission({nonce: 'ordered-fields'})}, cases);
  });
