import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Spec-derived expectations, not live BigQuery results. This bounded surface
// covers STRING/default comparison and finite number/FLOAT64 only.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#sign
// SQL text, common expressions, values, and contracts are authored separately;
// no compiler output or execution result constructs an expected value.
const literal = value => ({literal: value});
const boolean = (name, text, expression, expected, nullable = false) =>
  ({name, text, expression, expected, contract: {type: 'boolean', nullable}});
const number = (name, text, expression, expected, nullable = false) =>
  ({name, text, expression, expected, contract: {type: 'number', nullable}});

const batches = [
  {id: 'exact', cases: [
    boolean('prefix', "STARTS_WITH('bar', 'b')",
      {starts_with: [literal('bar'), literal('b')]}, true),
    boolean('suffix', "ENDS_WITH('apple', 'e')",
      {ends_with: [literal('apple'), literal('e')]}, true),
    boolean('whole_prefix', "STARTS_WITH('abc', 'abc')",
      {starts_with: [literal('abc'), literal('abc')]}, true),
    boolean('whole_suffix', "ENDS_WITH('abc', 'abc')",
      {ends_with: [literal('abc'), literal('abc')]}, true),
    boolean('internal_prefix', "STARTS_WITH('abc', 'b')",
      {starts_with: [literal('abc'), literal('b')]}, false),
    boolean('internal_suffix', "ENDS_WITH('abc', 'b')",
      {ends_with: [literal('abc'), literal('b')]}, false),
    boolean('long_prefix', "STARTS_WITH('a', 'ab')",
      {starts_with: [literal('a'), literal('ab')]}, false),
    boolean('long_suffix', "ENDS_WITH('a', 'ba')",
      {ends_with: [literal('a'), literal('ba')]}, false),
  ]},
  {id: 'empty', cases: [
    boolean('empty_prefix', "STARTS_WITH('', '')",
      {starts_with: [literal(''), literal('')]}, true),
    boolean('empty_suffix', "ENDS_WITH('', '')",
      {ends_with: [literal(''), literal('')]}, true),
    boolean('nonempty_prefix', "STARTS_WITH('a', '')",
      {starts_with: [literal('a'), literal('')]}, true),
    boolean('nonempty_suffix', "ENDS_WITH('a', '')",
      {ends_with: [literal('a'), literal('')]}, true),
    boolean('missing_prefix', "STARTS_WITH('', 'a')",
      {starts_with: [literal(''), literal('a')]}, false),
    boolean('missing_suffix', "ENDS_WITH('', 'a')",
      {ends_with: [literal(''), literal('a')]}, false),
  ]},
  {id: 'unicode', cases: [
    boolean('astral_prefix', "STARTS_WITH('😀é😀', '😀')",
      {starts_with: [literal('😀é😀'), literal('😀')]}, true),
    boolean('astral_suffix', "ENDS_WITH('😀é😀', '😀')",
      {ends_with: [literal('😀é😀'), literal('😀')]}, true),
    boolean('exact_combining', "STARTS_WITH('éx', 'é')",
      {starts_with: [literal('éx'), literal('é')]}, true),
    boolean('combining_suffix', "ENDS_WITH('é', '\\u0301')",
      {ends_with: [literal('é'), literal('\u0301')]}, true),
    boolean('unnormalized_prefix', "STARTS_WITH('éx', 'é')",
      {starts_with: [literal('éx'), literal('é')]}, false),
    boolean('unnormalized_suffix', "ENDS_WITH('xé', 'é')",
      {ends_with: [literal('xé'), literal('é')]}, false),
    boolean('case_prefix', "STARTS_WITH('Abc', 'a')",
      {starts_with: [literal('Abc'), literal('a')]}, false),
    boolean('case_suffix', "ENDS_WITH('abC', 'c')",
      {ends_with: [literal('abC'), literal('c')]}, false),
  ]},
  {id: 'sign', cases: [
    number('negative', 'SIGN(-25.5)', {sign: literal(-25.5)}, -1),
    number('zero', 'SIGN(0)', {sign: literal(0)}, 0),
    // Use operation-produced zero; negative-zero source literals stay refused.
    number('operation_zero', 'SIGN(0.0 * -1.0)',
      {sign: {multiply: [literal(0), literal(-1)]}}, 0),
    number('positive', 'SIGN(25.5)', {sign: literal(25.5)}, 1),
    number('tiny_negative', 'SIGN(-5e-324)', {sign: literal(-5e-324)}, -1),
    number('tiny_positive', 'SIGN(5e-324)', {sign: literal(5e-324)}, 1),
    number('largest_negative', 'SIGN(-1.7976931348623157e308)',
      {sign: literal(-1.7976931348623157e308)}, -1),
    number('largest_positive', 'SIGN(1.7976931348623157e308)',
      {sign: literal(1.7976931348623157e308)}, 1),
  ]},
  {id: 'null', cases: [
    boolean('null_prefix_value', "STARTS_WITH(NULL, '')",
      {starts_with: [literal(null), literal('')]}, null, true),
    boolean('null_prefix', "STARTS_WITH('', NULL)",
      {starts_with: [literal(''), literal(null)]}, null, true),
    boolean('null_suffix_value', "ENDS_WITH(NULL, '')",
      {ends_with: [literal(null), literal('')]}, null, true),
    boolean('null_suffix', "ENDS_WITH('', NULL)",
      {ends_with: [literal(''), literal(null)]}, null, true),
    boolean('both_null', 'STARTS_WITH(NULL, NULL)',
      {starts_with: [literal(null), literal(null)]}, null, true),
    number('null_sign', 'SIGN(NULL)', {sign: literal(null)}, null, true),
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

function sql(cases) {
  return 'SELECT ' + cases.map(item => `${item.text} AS ${item.name}`).join(', ');
}

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-google-scalars-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'google-scalars',
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
  assert.deepEqual(await run.result('answer').all(), expected);
  assert.deepEqual((await run.result('answer').describe()).columns, columns);
  assert.ok(f.advances() > beforeAdvances, 'ordinary execution must make charged Local progress');
  assert.ok(f.computed().outputRepresentations.some(entry => entry.representation === 'retained-file'));
  const before = f.dispatches();
  assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
  const attached = await f.client.attach(run.ref);
  assert.deepEqual(await attached.result('answer').all(), expected);
  assert.deepEqual((await attached.result('answer').describe()).columns, columns);
  assert.equal(f.dispatches(), before, 'same-request resend and retained reread must not dispatch again');
}

test('public SQL and independent JSON execute spec-derived Google scalar vectors',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    for (const batch of batches) {
      for (const format of ['sql', 'json']) {
        const source = format === 'sql' ? sql(batch.cases)
          : JSON.stringify(program('google_' + batch.id, batch.cases));
        await assertPublished(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `${batch.id}-${format}`})}, batch.cases);
      }
    }
  });

test('public Google scalar schemas retain declared operand nullability',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p: {type: 'string', nullable: true},
      q: {type: 'string', nullable: false}, n: {type: 'number', nullable: true}};
    const cases = [
      boolean('starts', 'STARTS_WITH(@p, @q)',
        {starts_with: [{$param: 'p'}, {$param: 'q'}]}, true, true),
      boolean('ends', 'ENDS_WITH(@q, @p)',
        {ends_with: [{$param: 'q'}, {$param: 'p'}]}, false, true),
      number('direction', 'SIGN(@n)', {sign: {$param: 'n'}}, -1, true),
    ];
    for (const format of ['sql', 'json']) {
      const source = format === 'sql' ? sql(cases)
        : JSON.stringify(program('google_nullable', cases, parameterDeclarations));
      await assertPublished(f, source, {format, parameters: {p: 'abc', q: 'a', n: -2.3},
        ...(format === 'sql' ? {parameterDeclarations} : {}),
        submissionRef: f.client.newSubmission({nonce: 'nullable-' + format})}, cases);
    }
  });

test('public Google scalar refusals and eager NULL arguments preserve failure boundaries',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    for (const [index, expression] of [
      "STARTS_WITH('a')", "ENDS_WITH('a', 'b', 'c')", 'SIGN(1, 2)',
      'STARTS_WITH(NULL, 1)', 'ENDS_WITH(TRUE, NULL)', "SIGN('1')",
      "SIGN(CAST('1.25' AS DECIMAL(8,3)))",
    ].entries()) {
      const submissionRef = f.client.newSubmission({nonce: 'invalid-' + index});
      await assert.rejects(f.client.startSource('SELECT ' + expression + ' AS value',
        {format: 'sql', submissionRef}), error => {
        assert.equal(error.code, 'SubmissionNotAccepted');
        const outcome = getSubmissionOutcome(error);
        assert.equal(outcome.kind, 'not_accepted');
        assert.deepEqual(outcome.submissionRef, submissionRef);
        assert.equal(outcome.problem.code, 'ClientProgramInvalidInput');
        return true;
      });
    }
    assert.equal(f.dispatches(), 0, 'invalid arity and types must fail before dispatch');

    // GoogleSQL regular calls evaluate all arguments before applying the call.
    // A NULL operand therefore cannot conceal the demanded division error.
    // https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions
    const demandedText = {if: [{eq: [{divide: [literal(1), literal(0)]}, literal(0)]},
      literal('x'), literal('y')]};
    const eagerCases = [
      {name: 'prefix', text: "STARTS_WITH(NULL, IF(1 / 0 = 0, 'x', 'y'))",
        expression: {starts_with: [literal(null), demandedText]}},
      {name: 'suffix', text: "ENDS_WITH(IF(1 / 0 = 0, 'x', 'y'), NULL)",
        expression: {ends_with: [demandedText, literal(null)]}},
    ];
    for (const item of eagerCases) {
      for (const format of ['sql', 'json']) {
        const source = format === 'sql' ? sql([item])
          : JSON.stringify(program('google_eager_' + item.name, [item]));
        const options = {format,
          submissionRef: f.client.newSubmission({nonce: `eager-${item.name}-${format}`})};
        const run = await f.client.startSource(source, options);
        const state = await run.wait({signal: AbortSignal.timeout(15_000)});
        assert.equal(state.status, 'failed', JSON.stringify(state));
        assert.equal(state.result_availability.answer.state, 'unavailable');
        await assert.rejects(run.result('answer').all());
        await assert.rejects(run.result('answer').describe());
        const before = f.dispatches();
        assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
        assert.equal((await (await f.client.attach(run.ref)).status()).status, 'failed');
        assert.equal(f.dispatches(), before, 'failed resubmission must not dispatch again');
      }
    }
  });
