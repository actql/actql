import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Independently authored finite-binary64 expectations, not a live BigQuery
// comparison or values obtained from the product comparator or Math.min/max.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#greatest
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#least
// The supported subset is finite Number only. Eager ordered child demand,
// canonical positive zero and resource ownership are ActQL's local contract.
const literal = value => ({literal: value});
const number = (name, text, expression, expected, nullable = false) =>
  ({name, text, expression, expected, contract: {type: 'number', nullable}});
const formats = ['sql', 'aql-text', 'json'];
const batches = [
  {id: 'finite', cases: [
    number('maximum', 'GREATEST(-2, 7, 3, 7)',
      {greatest: [literal(-2), literal(7), literal(3), literal(7)]}, 7),
    number('minimum', 'LEAST(7, -2, 3, -2)',
      {least: [literal(7), literal(-2), literal(3), literal(-2)]}, -2),
    number('singleton_max', 'greatest(4503599627370497)',
      {greatest: [literal(4503599627370497)]}, 4503599627370497),
    number('singleton_min', '`LeAsT`(-4503599627370497)',
      {least: [literal(-4503599627370497)]}, -4503599627370497),
    number('adjacent_max', 'GREATEST(1, 1.0000000000000002, 1)',
      {greatest: [literal(1), literal(1.0000000000000002), literal(1)]}, 1.0000000000000002),
    number('adjacent_min', 'LEAST(1.0000000000000002, 1, 1.0000000000000002)',
      {least: [literal(1.0000000000000002), literal(1), literal(1.0000000000000002)]}, 1),
    number('largest', 'GREATEST(-1.7976931348623157e308, 1.7976931348623157e308)',
      {greatest: [literal(-1.7976931348623157e308), literal(1.7976931348623157e308)]}, 1.7976931348623157e308),
    number('smallest', 'LEAST(1.7976931348623157e308, -1.7976931348623157e308)',
      {least: [literal(1.7976931348623157e308), literal(-1.7976931348623157e308)]}, -1.7976931348623157e308),
  ]},
  {id: 'subnormal_zero', cases: [
    number('subnormal_max', 'GREATEST(5e-324, 1e-323, 5e-324)',
      {greatest: [literal(5e-324), literal(1e-323), literal(5e-324)]}, 1e-323),
    number('subnormal_min', 'LEAST(1e-323, 5e-324, 1e-323)',
      {least: [literal(1e-323), literal(5e-324), literal(1e-323)]}, 5e-324),
    number('signed_tiny_max', 'GREATEST(-5e-324, 0, 5e-324)',
      {greatest: [literal(-5e-324), literal(0), literal(5e-324)]}, 5e-324),
    number('signed_tiny_min', 'LEAST(5e-324, 0, -5e-324)',
      {least: [literal(5e-324), literal(0), literal(-5e-324)]}, -5e-324),
    // Negative-zero source literals are outside the source grammar. Exercise
    // zero-producing operations here; direct signed-zero inputs have Core vectors.
    number('zero_max', 'GREATEST(SAFE_NEGATE(0), 0, SAFE_NEGATE(0))',
      {greatest: [{safe_negate: literal(0)}, literal(0), {safe_negate: literal(0)}]}, 0),
    number('zero_min', 'LEAST(0, SAFE_NEGATE(0), 0)',
      {least: [literal(0), {safe_negate: literal(0)}, literal(0)]}, 0),
    number('singleton_zero_max', 'GREATEST(SAFE_NEGATE(0))',
      {greatest: [{safe_negate: literal(0)}]}, 0),
    number('singleton_zero_min', 'LEAST(SAFE_NEGATE(0))',
      {least: [{safe_negate: literal(0)}]}, 0),
  ]},
  {id: 'null', cases: [
    number('singleton_null_max', 'GREATEST(NULL)', {greatest: [literal(null)]}, null, true),
    number('singleton_null_min', 'LEAST(NULL)', {least: [literal(null)]}, null, true),
    number('all_null_max', 'GREATEST(NULL, NULL)',
      {greatest: [literal(null), literal(null)]}, null, true),
    number('all_null_min', 'LEAST(NULL, NULL)',
      {least: [literal(null), literal(null)]}, null, true),
    number('first_null', 'GREATEST(NULL, 7, -2)',
      {greatest: [literal(null), literal(7), literal(-2)]}, null, true),
    number('last_null', 'LEAST(7, -2, NULL)',
      {least: [literal(7), literal(-2), literal(null)]}, null, true),
  ]},
];

function program(id, cases, params, empty = false) {
  const names = cases.map(item => item.name);
  return {version: 'actql/0.1', id, ...(params ? {params} : {}), stages: [{
    id: 'main', inputs: {}, steps: [
      {values: {schema: {unit: {type: 'boolean', nullable: false}},
        rows: empty ? [] : [{unit: true}]}, as: 'seed'},
      {from: 'seed', derive: Object.fromEntries(cases.map(item =>
        [item.name, item.expression])), as: 'derived'},
      {select: names, as: 'out'},
    ], results: {rows: {from: 'out', fields: names}},
  }], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}

function sourceFor(format, id, cases, params, empty = false) {
  if (format === 'json') return JSON.stringify(program(id, cases, params, empty));
  const select = 'SELECT ' + cases.map(item => `${item.text} AS ${item.name}`).join(', ');
  return format === 'aql-text'
    ? 'SELECT TRUE AS unit |> ' + (empty ? 'WHERE FALSE |> ' : '') + select
    : select + (empty ? ' WHERE FALSE' : '');
}

async function fixture(t, {onAdvance, onComputed} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-number-extrema-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'number-extrema',
        entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true}, operation: {all: true},
          exclusions: []}],
      }),
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      observe(name, detail) {
        if (name === 'computed') { computed = detail; onComputed?.(detail); }
      },
      async faultInjection(name, detail) {
        if (name === 'dispatch_reserved') dispatches++;
        if (name === 'local_compute_advanced' && BigInt(detail.work) > 0n) {
          advances++;
          await onAdvance?.(advances, detail);
        }
      },
    },
  }});
  return {client, dispatches: () => dispatches, advances: () => advances,
    computed: () => computed};
}

async function assertPublished(f, source, options, cases, empty = false) {
  const beforeAdvances = f.advances();
  const run = await f.client.startSource(source, options);
  const state = await run.wait({signal: AbortSignal.timeout(15_000)});
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const expected = empty ? [] : [Object.fromEntries(cases.map(item => [item.name, item.expected]))];
  const columns = cases.map(item => ({name: item.name, contract: item.contract}));
  const actual = await run.result('answer').all();
  assert.deepEqual(actual, expected);
  for (const row of actual) for (const value of Object.values(row)) {
    if (value !== null) {
      assert.ok(Number.isFinite(value));
      assert.ok(!Object.is(value, -0), 'published zero is canonical');
    }
  }
  assert.deepEqual((await run.result('answer').describe()).columns, columns);
  if (!empty) assert.ok(f.advances() > beforeAdvances,
    'ordinary execution must make charged Local progress');
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

test('public number extrema publish exact SQL Pipe JSON values and retained schemas',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    for (const batch of batches) for (const format of formats) {
      await assertPublished(f, sourceFor(format, 'extrema_' + batch.id, batch.cases),
        {format, submissionRef: f.client.newSubmission({nonce: batch.id + '-' + format})}, batch.cases);
    }
  });

test('public number extrema retain nullable and required parameter contracts',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p: {type: 'number', nullable: true},
      q: {type: 'number', nullable: false}};
    for (const [id, parameters, greatest, least] of [
      ['value', {p: -2.5, q: 7}, 7, -2.5],
      ['null', {p: null, q: 7}, null, null],
    ]) {
      const cases = [
        number('nullable_max', 'GREATEST(@p, @q, @p)',
          {greatest: [{$param: 'p'}, {$param: 'q'}, {$param: 'p'}]}, greatest, true),
        number('nullable_min', 'LEAST(@q, @p, @q)',
          {least: [{$param: 'q'}, {$param: 'p'}, {$param: 'q'}]}, least, true),
        number('required_max', 'GREATEST(@q, 1)',
          {greatest: [{$param: 'q'}, literal(1)]}, 7),
        number('required_min', 'LEAST(1, @q)',
          {least: [literal(1), {$param: 'q'}]}, 1),
      ];
      for (const format of formats) await assertPublished(f,
        sourceFor(format, 'extrema_parameters', cases, parameterDeclarations),
        {format, parameters, ...(format === 'json' ? {} : {parameterDeclarations}),
          submissionRef: f.client.newSubmission({nonce: id + '-' + format})}, cases);
    }
  });

test('public number extrema reject unsupported domains and malformed shapes before dispatch',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    for (const op of ['greatest', 'least']) {
      const name = op.toUpperCase();
      const invalid = [
        {text: `${name}()`, expression: {[op]: []}},
        {text: `${name}('a', 'b')`, expression: {[op]: [literal('a'), literal('b')]}},
        {text: `${name}(NULL, '2')`, expression: {[op]: [literal(null), literal('2')]}},
        {text: `${name}(1, TRUE)`, expression: {[op]: [literal(1), literal(true)]}},
        {text: `${name}(1, CAST('2' AS DECIMAL(2,0)))`,
          expression: {[op]: [literal(1), {cast: {
            target: {type: 'decimal', precision: 2, scale: 0}, value: literal('2')}}]}},
      ];
      for (const [index, item] of invalid.entries()) for (const format of formats) {
        await assertRefused(f, sourceFor(format, 'extrema_invalid', [{name: 'value', ...item}]),
          {format, submissionRef: f.client.newSubmission({nonce: `${op}-${index}-${format}`})});
      }
      for (const [index, body] of [null, {}, literal(7)].entries()) {
        await assertRefused(f, sourceFor('json', 'extrema_shape',
          [{name: 'value', expression: {[op]: body}}]),
        {format: 'json', submissionRef: f.client.newSubmission({nonce: `${op}-shape-${index}`})});
      }
      // JSON.stringify(Infinity) would hide the nonfinite value as NULL.
      for (const format of formats) {
        const source = format === 'json'
          ? sourceFor(format, 'extrema_nonfinite', [{name: 'value',
            expression: {[op]: [literal(1), literal('NONFINITE_TOKEN')]}}])
            .replace('"NONFINITE_TOKEN"', '1e309')
          : sourceFor(format, 'extrema_nonfinite', [{name: 'value', text: `${name}(1, 1e309)`}]);
        await assertRefused(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: op + '-nonfinite-' + format})});
      }
    }
    assert.equal(f.dispatches(), 0, 'invalid extrema must fail before dispatch');
    assert.equal(f.advances(), 0, 'invalid extrema must not start Local evaluation');
  });

test('public number extrema preserve demanded failures before and after NULL and failed rereads',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const divide = {divide: [literal(1), literal(0)]};
    for (const op of ['greatest', 'least']) {
      const cases = [
        {text: `${op.toUpperCase()}(7, NULL, 1 / 0)`,
          expression: {[op]: [literal(7), literal(null), divide]}},
        {text: `${op.toUpperCase()}(1 / 0, NULL, 7)`,
          expression: {[op]: [divide, literal(null), literal(7)]}},
      ];
      for (const [index, item] of cases.entries()) for (const format of formats) {
        const source = sourceFor(format, 'extrema_failure', [{name: 'value', ...item}]);
        const options = {format,
          submissionRef: f.client.newSubmission({nonce: `${op}-${index}-${format}`})};
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

test('public number extrema preserve outer IF and inner branch laziness',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const divide = {divide: [literal(1), literal(0)]};
    const cases = [
      number('outer_max', 'IF(FALSE, GREATEST(NULL, 1 / 0), 7)',
        {if: [literal(false), {greatest: [literal(null), divide]}, literal(7)]}, 7, true),
      number('outer_min', 'IF(TRUE, 7, LEAST(1 / 0, NULL))',
        {if: [literal(true), literal(7), {least: [divide, literal(null)]}]}, 7, true),
      number('inner_max', 'GREATEST(7, IF(TRUE, 2, 1 / 0))',
        {greatest: [literal(7), {if: [literal(true), literal(2), divide]}]}, 7),
      number('inner_min', 'LEAST(IF(FALSE, 1 / 0, 2), 7)',
        {least: [{if: [literal(false), divide, literal(2)]}, literal(7)]}, 2),
    ];
    for (const format of formats) await assertPublished(f,
      sourceFor(format, 'extrema_lazy', cases),
      {format, submissionRef: f.client.newSubmission({nonce: 'lazy-' + format})}, cases);
  });

test('public number extrema retain complete result schemas on empty relations',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const cases = [
      number('required', 'GREATEST(1, 2)', {greatest: [literal(1), literal(2)]}, 2),
      number('nullable', 'LEAST(1, NULL)', {least: [literal(1), literal(null)]}, null, true),
    ];
    for (const format of formats) await assertPublished(f,
      sourceFor(format, 'extrema_empty', cases, undefined, true),
      {format, submissionRef: f.client.newSubmission({nonce: 'empty-' + format})}, cases, true);
  });

async function boundedBarrier(promise) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('no charged extrema cancellation boundary')), 15_000);
    })]);
  } finally {
    clearTimeout(timer);
  }
}

for (const op of ['greatest', 'least']) test(`public ${op} cancellation stops after charged derivation progress`,
  {timeout: 60_000}, async t => {
    const reached = Promise.withResolvers();
    const resume = Promise.withResolvers();
    let completions = 0;
    t.after(() => resume.resolve());
    const f = await fixture(t, {
      onComputed() { completions++; reached.resolve(null); },
      async onAdvance(_count, detail) {
        if (detail.task === 1 && BigInt(detail.progress) > 0n) {
          reached.resolve(detail);
          await resume.promise;
        }
      },
    });
    // Keep the inherited 100-row Values ceiling and ordinary Host limits.
    // A separate consumer task identifies charged extrema derivation progress;
    // repeated field operands exercise the existing variadic continuation.
    const source = JSON.stringify({version: 'actql/0.1', id: op + '_cancel', stages: [{
      id: 'seed', inputs: {}, steps: [
        {values: {schema: {x: {type: 'number', nullable: false}},
          rows: Array.from({length: 100}, () => ({x: 5e-324}))}, as: 'out'},
      ], results: {rows: {from: 'out', fields: ['x']}},
    }, {
      id: 'main', inputs: {rows: {result: {stage: 'seed', result: 'rows'}}}, steps: [
        {from: 'rows', derive: {value: {[op]: Array.from({length: 17}, () => ({field: 'x'}))}}, as: 'derived'},
        {select: ['value'], as: 'out'},
      ], results: {rows: {from: 'out', fields: ['value']}},
    }], results: {answer: {from: {stage: 'main', result: 'rows'}}}});
    const options = {format: 'json', submissionRef: f.client.newSubmission({nonce: op + '-cancel'})};
    let run;
    let before;
    try {
      run = await f.client.startSource(source, options);
      const barrier = await boundedBarrier(reached.promise);
      assert.ok(barrier, 'extrema must not publish before the cancellation boundary');
      assert.equal(barrier.task, 1);
      assert.ok(BigInt(barrier.work) > 0n);
      assert.ok(BigInt(barrier.progress) > 0n);
      before = f.advances();
      await run.cancel();
      const pending = await run.status();
      assert.equal(pending.control.cancellation_requested, true);
      assert.notEqual(pending.control.physical_stop, 'confirmed');
      assert.notEqual(pending.status, 'cancelled');
      assert.equal(completions, 0);
    } finally {
      resume.resolve();
    }
    const stopped = await run.wait({signal: AbortSignal.timeout(15_000)});
    assert.equal(stopped.status, 'cancelled', JSON.stringify(stopped));
    assert.equal(stopped.control.physical_stop, 'confirmed');
    assert.equal(stopped.result_availability.answer.state, 'unavailable');
    await assert.rejects(run.result('answer').all());
    await assert.rejects(run.result('answer').describe());
    assert.equal(completions, 0);
    assert.equal(f.advances(), before, 'cancelled derivation must not resume charged work');
    assert.equal(f.dispatches(), 1);
    assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
    const attached = await f.client.attach(run.ref);
    assert.equal((await attached.status()).status, 'cancelled');
    await assert.rejects(attached.result('answer').all());
    await assert.rejects(attached.result('answer').describe());
    assert.equal(f.dispatches(), 1, 'cancelled resend and reread must not dispatch again');
  });
