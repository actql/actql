import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Independent finite-binary64, unary-only expectations, not live BigQuery.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#round
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#trunc
// ROUND uses nearest integer with ties away from zero; TRUNC moves toward zero.
// SQL/Pipe operands, common JSON expressions, results, and schema contracts are
// authored directly. No host Math function or product output supplies an oracle.
// Decimal, nonfinite inputs, optional N, and rounding_mode are not supported.
const literal = value => ({literal: value});
const number = (name, text, expression, expected, nullable = false) =>
  ({name, text, expression, expected, contract: {type: 'number', nullable}});

const batches = [
  {id: 'halves', cases: [
    number('round_positive_half', 'ROUND(2.5)', {round: literal(2.5)}, 3),
    number('round_negative_half', 'ROUND(-2.5)', {round: literal(-2.5)}, -3),
    number('trunc_positive_half', 'TRUNC(2.5)', {trunc: literal(2.5)}, 2),
    number('trunc_negative_half', 'TRUNC(-2.5)', {trunc: literal(-2.5)}, -2),
    number('round_positive', 'round(2.3)', {round: literal(2.3)}, 2),
    number('round_negative', '`RoUnD`(-2.8)', {round: literal(-2.8)}, -3),
    number('trunc_positive', 'trunc(2.8)', {trunc: literal(2.8)}, 2),
    number('trunc_negative', '`TrUnC`(-2.8)', {trunc: literal(-2.8)}, -2),
  ]},
  {id: 'adjacent_half', cases: [
    number('below_positive', 'ROUND(2.4999999999999996)',
      {round: literal(2.4999999999999996)}, 2),
    number('above_positive', 'ROUND(2.5000000000000004)',
      {round: literal(2.5000000000000004)}, 3),
    number('below_negative', 'ROUND(-2.4999999999999996)',
      {round: literal(-2.4999999999999996)}, -2),
    number('above_negative', 'ROUND(-2.5000000000000004)',
      {round: literal(-2.5000000000000004)}, -3),
    number('below_unit_positive', 'ROUND(0.49999999999999994)',
      {round: literal(0.49999999999999994)}, 0),
    number('above_unit_positive', 'ROUND(0.5000000000000001)',
      {round: literal(0.5000000000000001)}, 1),
    number('below_unit_negative', 'ROUND(-0.49999999999999994)',
      {round: literal(-0.49999999999999994)}, 0),
    number('above_unit_negative', 'ROUND(-0.5000000000000001)',
      {round: literal(-0.5000000000000001)}, -1),
  ]},
  {id: 'binary64_boundary', cases: [
    number('round_large_half', 'ROUND(4503599627370495.5)',
      {round: literal(4503599627370495.5)}, 4503599627370496),
    number('round_large_negative_half', 'ROUND(-4503599627370495.5)',
      {round: literal(-4503599627370495.5)}, -4503599627370496),
    number('trunc_large_half', 'TRUNC(4503599627370495.5)',
      {trunc: literal(4503599627370495.5)}, 4503599627370495),
    number('trunc_large_negative_half', 'TRUNC(-4503599627370495.5)',
      {trunc: literal(-4503599627370495.5)}, -4503599627370495),
    // Already-integral odd values above 2^52 must not be perturbed by x + 0.5.
    number('round_large_integer', 'ROUND(4503599627370497.0)',
      {round: literal(4503599627370497)}, 4503599627370497),
    number('round_large_negative_integer', 'ROUND(-4503599627370497.0)',
      {round: literal(-4503599627370497)}, -4503599627370497),
    number('trunc_large_integer', 'TRUNC(4503599627370497.0)',
      {trunc: literal(4503599627370497)}, 4503599627370497),
    number('trunc_large_negative_integer', 'TRUNC(-4503599627370497.0)',
      {trunc: literal(-4503599627370497)}, -4503599627370497),
  ]},
  {id: 'extremes', cases: [
    number('round_largest', 'ROUND(1.7976931348623157e308)',
      {round: literal(1.7976931348623157e308)}, 1.7976931348623157e308),
    number('round_smallest', 'ROUND(-1.7976931348623157e308)',
      {round: literal(-1.7976931348623157e308)}, -1.7976931348623157e308),
    number('trunc_largest', 'TRUNC(1.7976931348623157e308)',
      {trunc: literal(1.7976931348623157e308)}, 1.7976931348623157e308),
    number('trunc_smallest', 'TRUNC(-1.7976931348623157e308)',
      {trunc: literal(-1.7976931348623157e308)}, -1.7976931348623157e308),
    number('round_tiny', 'ROUND(5e-324)', {round: literal(5e-324)}, 0),
    number('round_tiny_negative', 'ROUND(-5e-324)', {round: literal(-5e-324)}, 0),
    number('trunc_tiny', 'TRUNC(5e-324)', {trunc: literal(5e-324)}, 0),
    number('trunc_tiny_negative', 'TRUNC(-5e-324)', {trunc: literal(-5e-324)}, 0),
  ]},
  {id: 'zero_null', cases: [
    number('round_null', 'ROUND(NULL)', {round: literal(null)}, null, true),
    number('trunc_null', 'TRUNC(NULL)', {trunc: literal(null)}, null, true),
    number('round_zero', 'ROUND(0)', {round: literal(0)}, 0),
    number('trunc_zero', 'TRUNC(0)', {trunc: literal(0)}, 0),
    number('round_to_zero', 'ROUND(-0.1)', {round: literal(-0.1)}, 0),
    number('trunc_to_zero', 'TRUNC(-0.9)', {trunc: literal(-0.9)}, 0),
    // Negative-zero source literals are outside the admitted source grammar.
    number('round_operation_zero', 'ROUND(0.0 * -1.0)',
      {round: {multiply: [literal(0), literal(-1)]}}, 0),
    number('trunc_operation_zero', 'TRUNC(0.0 * -1.0)',
      {trunc: {multiply: [literal(0), literal(-1)]}}, 0),
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
  const directory = await mkdtemp(join(tmpdir(), 'actql-round-trunc-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'round-trunc',
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

test('public SQL, Pipe, and independent JSON publish unary ROUND and TRUNC vectors',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    for (const batch of batches) {
      for (const format of ['sql', 'aql-text', 'json']) {
        const source = sourceFor(format, 'round_trunc_' + batch.id, batch.cases);
        await assertPublished(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `${batch.id}-${format}`})}, batch.cases);
      }
    }
  });

test('public ROUND and TRUNC preserve nullable and nonnullable parameter schemas',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p: {type: 'number', nullable: true},
      q: {type: 'number', nullable: false}};
    for (const [id, parameters, rounded, truncated] of [
      ['value', {p: -2.5, q: 2.5}, -3, -2],
      ['null', {p: null, q: 2.5}, null, null],
    ]) {
      const cases = [
        number('nullable_round', 'ROUND(@p)', {round: {$param: 'p'}}, rounded, true),
        number('nullable_trunc', 'TRUNC(@p)', {trunc: {$param: 'p'}}, truncated, true),
        number('required_round', 'ROUND(@q)', {round: {$param: 'q'}}, 3),
        number('required_trunc', 'TRUNC(@q)', {trunc: {$param: 'q'}}, 2),
      ];
      for (const format of ['sql', 'aql-text', 'json']) {
        const source = sourceFor(format, 'round_trunc_nullable', cases, parameterDeclarations);
        await assertPublished(f, source, {format, parameters,
          ...(format !== 'json' ? {parameterDeclarations} : {}),
          submissionRef: f.client.newSubmission({nonce: `${id}-${format}`})}, cases);
      }
    }
  });

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

test('public unary ROUND and TRUNC reject malformed, optional, and wrong-type calls before dispatch',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const decimal = {cast: {target: {type: 'decimal', precision: 8, scale: 3}, value: literal('1.25')}};
    for (const op of ['round', 'trunc']) {
      const name = op.toUpperCase();
      const invalid = [
        {text: `${name}()`, expression: {[op]: []}},
        {text: `${name}(2.5, 0)`, expression: {[op]: [literal(2.5), literal(0)]}},
        {text: `${name}(2.5, 0, 'ROUND_HALF_EVEN')`,
          expression: {[op]: [literal(2.5), literal(0), literal('ROUND_HALF_EVEN')]}},
        {text: `${name}('😀é')`, expression: {[op]: literal('😀é')}},
        {text: `${name}(TRUE)`, expression: {[op]: literal(true)}},
        {text: `${name}(CAST('1.25' AS DECIMAL(8,3)))`, expression: {[op]: decimal}},
      ];
      for (const [index, item] of invalid.entries()) {
        for (const format of ['sql', 'aql-text', 'json']) {
          const source = sourceFor(format, 'round_trunc_invalid', [{name: 'value', ...item}]);
          await assertRefused(f, source, {format,
            submissionRef: f.client.newSubmission({nonce: `${op}-${index}-${format}`})});
        }
      }
      // A one-item list is still malformed: the common unary body is an Expr.
      for (const [index, body] of [null, {}, [literal(2.5)],
        {value: literal(2.5), n: literal(0)},
        {value: literal(2.5), rounding_mode: literal('ROUND_HALF_EVEN')}].entries()) {
        const source = sourceFor('json', 'round_trunc_malformed',
          [{name: 'value', expression: {[op]: body}}]);
        await assertRefused(f, source, {format: 'json',
          submissionRef: f.client.newSubmission({nonce: `malformed-${op}-${index}`})});
      }
      // Use an authored nonfinite token: JSON.stringify(Infinity) would become NULL.
      for (const format of ['sql', 'aql-text', 'json']) {
        const source = format === 'json'
          ? sourceFor(format, 'round_trunc_nonfinite', [{name: 'value',
            expression: {[op]: literal('NONFINITE_TOKEN')}}])
            .replace('"NONFINITE_TOKEN"', '1e309')
          : sourceFor(format, 'round_trunc_nonfinite', [{name: 'value', text: `${name}(1e309)`}]);
        await assertRefused(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `nonfinite-${op}-${format}`})});
      }
    }
    assert.equal(f.dispatches(), 0, 'invalid arity, shape, and types must fail before dispatch');
    assert.equal(f.advances(), 0, 'invalid source must not start Local evaluation');
  });

test('public ROUND and TRUNC refuse invalid parameter bindings before dispatch',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p: {type: 'number', nullable: true},
      q: {type: 'number', nullable: false}};
    const cases = [
      {name: 'rounded', text: 'ROUND(@p)', expression: {round: {$param: 'p'}}},
      {name: 'truncated', text: 'TRUNC(@q)', expression: {trunc: {$param: 'q'}}},
    ];
    for (const [index, parameters] of [
      {p: '😀é', q: 1}, {p: 1, q: '😀é'}, {p: true, q: 1},
      {p: 1, q: false}, {p: 1, q: null},
    ].entries()) {
      for (const format of ['sql', 'aql-text', 'json']) {
        const source = sourceFor(format, 'round_trunc_wrong_parameter', cases, parameterDeclarations);
        await assertRefused(f, source, {format, parameters,
          ...(format !== 'json' ? {parameterDeclarations} : {}),
          submissionRef: f.client.newSubmission({nonce: `parameter-${index}-${format}`})});
      }
    }
    assert.equal(f.dispatches(), 0, 'bad bindings must fail before dispatch');
    assert.equal(f.advances(), 0, 'bad bindings must not start Local evaluation');
  });

test('public ROUND and TRUNC preserve demanded division failures and failed rereads',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    for (const op of ['round', 'trunc']) {
      for (const format of ['sql', 'aql-text', 'json']) {
        const cases = [{name: 'value', text: `${op.toUpperCase()}(1 / 0)`,
          expression: {[op]: {divide: [literal(1), literal(0)]}}}];
        const source = sourceFor(format, 'round_trunc_demanded_' + op, cases);
        const options = {format,
          submissionRef: f.client.newSubmission({nonce: `demanded-${op}-${format}`})};
        const beforeDispatches = f.dispatches();
        const run = await f.client.startSource(source, options);
        const state = await run.wait({signal: AbortSignal.timeout(15_000)});
        assert.equal(state.status, 'failed', JSON.stringify(state));
        assert.ok(f.dispatches() > beforeDispatches, 'demanded child failure is an execution failure');
        assert.equal(state.result_availability.answer.state, 'unavailable');
        await assert.rejects(run.result('answer').all());
        await assert.rejects(run.result('answer').describe());
        const before = f.dispatches();
        assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
        const attached = await f.client.attach(run.ref);
        assert.equal((await attached.status()).status, 'failed');
        await assert.rejects(attached.result('answer').all());
        await assert.rejects(attached.result('answer').describe());
        assert.equal(f.dispatches(), before, 'failed resend and reread must not dispatch again');
      }
    }
  });

test('public ROUND and TRUNC keep skipped branches lazy inside and outside the call',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const divide = {divide: [literal(1), literal(0)]};
    const cases = [
      number('inside_round', 'ROUND(IF(TRUE, -2.5, 1 / 0))',
        {round: {if: [literal(true), literal(-2.5), divide]}}, -3),
      number('inside_trunc', 'TRUNC(IF(FALSE, 1 / 0, -2.5))',
        {trunc: {if: [literal(false), divide, literal(-2.5)]}}, -2),
      number('outside_round', 'IF(FALSE, ROUND(1 / 0), 7)',
        {if: [literal(false), {round: divide}, literal(7)]}, 7),
      number('outside_trunc', 'IF(TRUE, 7, TRUNC(1 / 0))',
        {if: [literal(true), literal(7), {trunc: divide}]}, 7),
    ];
    for (const format of ['sql', 'aql-text', 'json']) {
      const source = sourceFor(format, 'round_trunc_lazy', cases);
      await assertPublished(f, source, {format,
        submissionRef: f.client.newSubmission({nonce: 'lazy-' + format})}, cases);
    }
  });
