import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Independent, spec-derived STRING/default-binary vectors, not live BigQuery.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#strpos
// https://github.com/google/googlesql/blob/81c15b796138185c046aefe852321011fdf96615/googlesql/compliance/functions_testlib_string_2.cc#L398-L413
// BigQuery returns INT64. ActQL uses its existing finite-number contract;
// bounded character positions here are exact integers in that representation.
// SQL operands, common expressions, expected values, and contracts are authored
// independently. No compiler output or runtime result constructs an oracle.
const literal = value => ({literal: value});
const position = (name, text, expression, expected, nullable = false) =>
  ({name, text, expression, expected, contract: {type: 'number', nullable}});

const batches = [
  {id: 'first', cases: [
    position('documented', "STRPOS('foo@example.com', '@')",
      {strpos: [literal('foo@example.com'), literal('@')]}, 4),
    position('first_match', "STRPOS('banana', 'ana')",
      {strpos: [literal('banana'), literal('ana')]}, 2),
    position('overlap', "strpos('aaaaa', 'aaa')",
      {strpos: [literal('aaaaa'), literal('aaa')]}, 1),
    position('last_position', "`StRpOs`('abc', 'c')",
      {strpos: [literal('abc'), literal('c')]}, 3),
    position('whole', "STRPOS('abc', 'abc')",
      {strpos: [literal('abc'), literal('abc')]}, 1),
    position('missing', "STRPOS('abc', 'z')",
      {strpos: [literal('abc'), literal('z')]}, 0),
    position('longer_needle', "STRPOS('a', 'aa')",
      {strpos: [literal('a'), literal('aa')]}, 0),
    position('case_sensitive', "STRPOS('AbC', 'a')",
      {strpos: [literal('AbC'), literal('a')]}, 0),
  ]},
  {id: 'unicode', cases: [
    position('astral_before', "STRPOS('😀a', 'a')",
      {strpos: [literal('😀a'), literal('a')]}, 2),
    position('astral_match', "STRPOS('a😀b😀', '😀')",
      {strpos: [literal('a😀b😀'), literal('😀')]}, 2),
    position('combining_before', "STRPOS('e\\u0301x', 'x')",
      {strpos: [literal('e\u0301x'), literal('x')]}, 3),
    position('combining_match', "STRPOS('e\\u0301x', '\\u0301')",
      {strpos: [literal('e\u0301x'), literal('\u0301')]}, 2),
    position('composed', "STRPOS('é', 'e\\u0301')",
      {strpos: [literal('é'), literal('e\u0301')]}, 0),
    position('decomposed', "STRPOS('e\\u0301', 'é')",
      {strpos: [literal('e\u0301'), literal('é')]}, 0),
    position('nul_match', "STRPOS('a\\u0000b', '\\u0000b')",
      {strpos: [literal('a\u0000b'), literal('\u0000b')]}, 2),
    position('after_nul', "STRPOS('😀\\u0000b', 'b')",
      {strpos: [literal('😀\u0000b'), literal('b')]}, 3),
  ]},
  {id: 'empty_null', cases: [
    position('empty_both', "STRPOS('', '')",
      {strpos: [literal(''), literal('')]}, 1),
    position('empty_needle', "STRPOS('abc', '')",
      {strpos: [literal('abc'), literal('')]}, 1),
    position('empty_haystack', "STRPOS('', 'a')",
      {strpos: [literal(''), literal('a')]}, 0),
    position('null_left', "STRPOS(NULL, '')",
      {strpos: [literal(null), literal('')]}, null, true),
    position('null_right', "STRPOS('', NULL)",
      {strpos: [literal(''), literal(null)]}, null, true),
    position('null_both', 'STRPOS(NULL, NULL)',
      {strpos: [literal(null), literal(null)]}, null, true),
  ]},
  {id: 'long_prefix', cases: [
    position('prefix_backtrack', `STRPOS('${'a'.repeat(256)}b', '${'a'.repeat(128)}b')`,
      {strpos: [literal('a'.repeat(256) + 'b'), literal('a'.repeat(128) + 'b')]}, 129),
    position('prefix_miss', `STRPOS('${'a'.repeat(256)}b', '${'a'.repeat(128)}c')`,
      {strpos: [literal('a'.repeat(256) + 'b'), literal('a'.repeat(128) + 'c')]}, 0),
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
  const directory = await mkdtemp(join(tmpdir(), 'actql-strpos-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'strpos',
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
    if (value !== null) assert.ok(Number.isSafeInteger(value) && value >= 0);
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

test('public SQL, Pipe, and independent JSON publish exact STRPOS positions',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    for (const batch of batches) {
      for (const format of ['sql', 'aql-text', 'json']) {
        const source = sourceFor(format, 'strpos_' + batch.id, batch.cases);
        await assertPublished(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `${batch.id}-${format}`})}, batch.cases);
      }
    }
  });

test('public STRPOS parameters retain nullable numeric schemas with and without NULL',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p: {type: 'string', nullable: true},
      q: {type: 'string', nullable: false}};
    for (const [id, parameters, forward, reverse] of [
      ['value', {p: '😀a', q: 'a'}, 2, 0],
      ['null', {p: null, q: ''}, null, null],
    ]) {
      const cases = [
        position('forward_position', 'STRPOS(@p, @q)',
          {strpos: [{$param: 'p'}, {$param: 'q'}]}, forward, true),
        position('reverse_position', 'STRPOS(@q, @p)',
          {strpos: [{$param: 'q'}, {$param: 'p'}]}, reverse, true),
      ];
      for (const format of ['sql', 'aql-text', 'json']) {
        const source = sourceFor(format, 'strpos_nullable', cases, parameterDeclarations);
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

test('public STRPOS arity and type refusals dispatch nothing across source formats',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const invalid = [
      {text: 'STRPOS()', expression: {strpos: []}},
      {text: "STRPOS('a')", expression: {strpos: [literal('a')]}},
      {text: "STRPOS('a', 'b', 'c')", expression: {strpos: [literal('a'), literal('b'), literal('c')]}},
      {text: "STRPOS(1, '1')", expression: {strpos: [literal(1), literal('1')]}},
      {text: "STRPOS('1', 1)", expression: {strpos: [literal('1'), literal(1)]}},
      {text: 'STRPOS(NULL, TRUE)', expression: {strpos: [literal(null), literal(true)]}},
      {text: 'STRPOS(TRUE, NULL)', expression: {strpos: [literal(true), literal(null)]}},
    ];
    for (const [index, item] of invalid.entries()) {
      for (const format of ['sql', 'aql-text', 'json']) {
        const source = sourceFor(format, 'strpos_invalid', [{name: 'value', ...item}]);
        await assertRefused(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `invalid-${index}-${format}`})});
      }
    }
    assert.equal(f.dispatches(), 0, 'invalid arity and types must fail before dispatch');
    assert.equal(f.advances(), 0, 'invalid source must not start Local evaluation');
  });

test('public STRPOS rejects invalid parameter bindings before dispatch',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p: {type: 'string', nullable: true},
      q: {type: 'string', nullable: false}};
    const cases = [{name: 'value', text: 'STRPOS(@p, @q)',
      expression: {strpos: [{$param: 'p'}, {$param: 'q'}]}}];
    for (const [index, parameters] of [
      {p: 1, q: ''}, {p: '', q: true}, {p: '', q: null},
    ].entries()) {
      for (const format of ['sql', 'aql-text', 'json']) {
        const source = sourceFor(format, 'strpos_wrong_parameter', cases, parameterDeclarations);
        await assertRefused(f, source, {format, parameters,
          ...(format !== 'json' ? {parameterDeclarations} : {}),
          submissionRef: f.client.newSubmission({nonce: `parameter-${index}-${format}`})});
      }
    }
    assert.equal(f.dispatches(), 0, 'bad bindings must fail before dispatch');
    assert.equal(f.advances(), 0, 'bad bindings must not start Local evaluation');
  });

test('public STRPOS eagerly demands both children even beside NULL',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    // Ordinary calls evaluate demanded arguments before their NULL result.
    // https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions
    const demandedText = {if: [{eq: [{divide: [literal(1), literal(0)]}, literal(0)]},
      literal('x'), literal('y')]};
    const cases = [
      {name: 'left_null', text: "STRPOS(NULL, IF(1 / 0 = 0, 'x', 'y'))",
        expression: {strpos: [literal(null), demandedText]}},
      {name: 'right_null', text: "STRPOS(IF(1 / 0 = 0, 'x', 'y'), NULL)",
        expression: {strpos: [demandedText, literal(null)]}},
    ];
    for (const item of cases) {
      for (const format of ['sql', 'aql-text', 'json']) {
        const source = sourceFor(format, 'strpos_eager_' + item.name, [item]);
        const options = {format,
          submissionRef: f.client.newSubmission({nonce: `eager-${item.name}-${format}`})};
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
        assert.equal(f.dispatches(), before, 'failed resend and reread must not dispatch again');
      }
    }
  });
