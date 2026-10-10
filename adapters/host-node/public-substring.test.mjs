import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Independent GoogleSQL STRING SUBSTR/SUBSTRING vectors, not live BigQuery.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#substr
// SQL text, common-expression operands, exact outputs, and result contracts are
// authored independently. No compiler output or runtime result is an oracle.
// Existing NUMBER admits finite numbers; this operator demands safe integers
// during execution. STRING positions and lengths count Unicode scalar values.
const literal = value => ({literal: value});
const formats = ['sql', 'aql-text', 'json'];
const string = (name, text, expression, expected, nullable = false, input) =>
  ({name, text, expression, expected, contract: {type: 'string', nullable,
    ...(typeof input === 'string' ? {max_utf8_bytes: Buffer.byteLength(input)} : {})}});
const substring = (name, text, value, start, length, expected, nullable = false) =>
  string(name, text, {substring: {value: literal(value), start: literal(start),
    ...(length === undefined ? {} : {length: literal(length)})}}, expected, nullable, value);

const batches = [
  {id: 'documented_positions', cases: [
    substring('documented', "SUBSTR('apple', 2, 2)", 'apple', 2, 2, 'pp'),
    substring('first', "SUBSTRING('banana', 1, 3)", 'banana', 1, 3, 'ban'),
    substring('omitted', "SUBSTR('abc', 2)", 'abc', 2, undefined, 'bc'),
    substring('zero_position', "SUBSTRING('abc', 0, 2)", 'abc', 0, 2, 'ab'),
    substring('negative_position', "SUBSTR('abc', -2, 1)", 'abc', -2, 1, 'b'),
    substring('negative_boundary', "SUBSTRING('abc', -3)", 'abc', -3, undefined, 'abc'),
    substring('negative_past_boundary', "SUBSTR('abc', -4, 2)", 'abc', -4, 2, 'ab'),
    substring('negative_omitted', "SUBSTRING('abc', -1)", 'abc', -1, undefined, 'c'),
  ]},
  {id: 'safe_integer_edges', cases: [
    substring('last', "SUBSTR('abc', 3, 1)", 'abc', 3, 1, 'c'),
    substring('past_end', "SUBSTRING('abc', 4)", 'abc', 4, undefined, ''),
    substring('huge_position', "SUBSTR('abc', 9007199254740991, 1)",
      'abc', 9007199254740991, 1, ''),
    substring('huge_negative_position', "SUBSTRING('abc', -9007199254740991, 2)",
      'abc', -9007199254740991, 2, 'ab'),
    substring('huge_length', "SUBSTR('abc', 2, 9007199254740991)",
      'abc', 2, 9007199254740991, 'bc'),
    substring('zero_length', "SUBSTRING('abc', 1, 0)", 'abc', 1, 0, ''),
    string('computed_zero_position', "SUBSTR('abc', 1 - 1, 2)",
      {substring:{value:literal('abc'),start:{subtract:[literal(1),literal(1)]},length:literal(2)}},'ab',false,'abc'),
    string('computed_zero_length', "SUBSTRING('abc', 1, 1 - 1)",
      {substring:{value:literal('abc'),start:literal(1),length:{subtract:[literal(1),literal(1)]}}},'',false,'abc'),
  ]},
  {id: 'unicode_scalars', cases: [
    substring('astral', "SUBSTR('a😀b😀', 2, 2)", 'a😀b😀', 2, 2, '😀b'),
    substring('astral_negative', "SUBSTRING('a😀b😀', -1)", 'a😀b😀', -1, undefined, '😀'),
    substring('combining', "SUBSTR('e\\u0301x', 2, 1)", 'e\u0301x', 2, 1, '\u0301'),
    substring('decomposed', "SUBSTRING('e\\u0301x', 1, 2)", 'e\u0301x', 1, 2, 'e\u0301'),
    substring('composed', "SUBSTR('éx', 1, 1)", 'éx', 1, 1, 'é'),
    substring('nul', "SUBSTRING('a\\u0000b', 2, 1)", 'a\u0000b', 2, 1, '\u0000'),
    substring('crlf', "SUBSTR('a\\u000D\\u000Ab', 2, 2)", 'a\r\nb', 2, 2, '\r\n'),
    substring('split_crlf', "SUBSTRING('a\\u000D\\u000Ab', -2, 1)", 'a\r\nb', -2, 1, '\n'),
  ]},
  {id: 'empty_and_spelling', cases: [
    substring('empty', "SUBSTR('', 1)", '', 1, undefined, ''),
    substring('empty_negative', "SUBSTRING('', -9007199254740991, 4)",
      '', -9007199254740991, 4, ''),
    substring('empty_zero', "SUBSTR('', 0, 0)", '', 0, 0, ''),
    substring('lowercase', "substr('😀e\\u0301', 2)", '😀e\u0301', 2, undefined, 'e\u0301'),
    substring('quoted_alias', "`SuBsTrInG`('😀e\\u0301', 2)", '😀e\u0301', 2, undefined, 'e\u0301'),
    substring('quoted_short', "`SuBsTr`('😀e\\u0301', 2, 1)", '😀e\u0301', 2, 1, 'e'),
    substring('mixed_alias', "sUbStRiNg('😀e\\u0301', 2, 1)", '😀e\u0301', 2, 1, 'e'),
  ]},
  {id: 'strict_null', cases: [
    substring('null_value_omitted', 'SUBSTR(NULL, 1)', null, 1, undefined, null, true),
    substring('null_value', 'SUBSTRING(NULL, 1, 2)', null, 1, 2, null, true),
    substring('null_start_omitted', "SUBSTR('abc', NULL)", 'abc', null, undefined, null, true),
    substring('null_start', "SUBSTRING('abc', NULL, 1)", 'abc', null, 1, null, true),
    substring('null_length', "SUBSTR('abc', 1, NULL)", 'abc', 1, null, null, true),
    substring('null_start_length', "SUBSTRING('abc', NULL, NULL)", 'abc', null, null, null, true),
    substring('all_null', 'SUBSTR(NULL, NULL, NULL)', null, null, null, null, true),
    substring('null_with_zero', 'SUBSTRING(NULL, 1, 0)', null, 1, 0, null, true),
  ]},
  {id: 'nested', cases: [
    string('nested_aliases', "SUBSTR(SUBSTRING('a😀e\\u0301z', 2, 3), 2, 2)",
      {substring: {value: {substring: {value: literal('a😀e\u0301z'), start: literal(2),
        length: literal(3)}}, start: literal(2), length: literal(2)}}, 'e\u0301', false, 'a😀e\u0301z'),
    string('nested_omitted', "SUBSTRING(SUBSTR('a😀e\\u0301z', -4), -2)",
      {substring: {value: {substring: {value: literal('a😀e\u0301z'), start: literal(-4)}},
        start: literal(-2)}}, '\u0301z', false, 'a😀e\u0301z'),
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
  if (format === 'aql-text') return 'SELECT TRUE AS unit |> ' +
    (empty ? 'WHERE FALSE |> ' : '') + select;
  return select + (empty ? ' WHERE FALSE' : '');
}

async function fixture(t, {onAdvance, onComputed} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-substring-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'substring',
        entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true}, operation: {all: true},
          exclusions: []}],
      }),
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      observe(name, detail) {
        if (name === 'computed') {
          computed = detail;
          onComputed?.(detail);
        }
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
  assert.deepEqual(await run.result('answer').all(), expected);
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

test('public SQL, Pipe, and independent JSON publish exact SUBSTR and SUBSTRING scalar slices',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    for (const batch of batches) {
      for (const format of formats) {
        const source = sourceFor(format, 'substring_' + batch.id, batch.cases);
        await assertPublished(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `${batch.id}-${format}`})}, batch.cases);
      }
    }
  });

test('public ordered derive resolves substring named children through input, shadow, and nested prior slots',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const cases = [
      {name: 'saved', expected: '😀e\u0301', contract: {type: 'string', nullable: false}},
      {name: 'payload', expected: 'e\u0301', contract: {type: 'string', nullable: false}},
      {name: 'value', expected: 'e', contract: {type: 'string', nullable: false}},
      {name: 'nested', expected: '😀', contract: {type: 'string', nullable: false}},
    ];
    const fields = ['saved', 'payload', 'value', 'nested'];
    const source = JSON.stringify({version: 'actql/0.1', id: 'substring_ordered_fields', stages: [{
      id: 'main', inputs: {}, steps: [
        {values: {schema: {
          payload: {type: 'string', nullable: false},
          position: {type: 'number', nullable: false},
          length: {type: 'number', nullable: false},
        }, rows: [{payload: 'a😀e\u0301z', position: 2, length: 3}]}, as: 'seed'},
        {from: 'seed', derive: [
          // Every named substring child initially refers to an input field.
          {saved: {substring: {value: {field: 'payload'}, start: {field: 'position'},
            length: {field: 'length'}}}},
          // The next three bindings shadow inputs using preceding slots or the
          // original input before its own replacement. Omitted length stays absent.
          {payload: {substring: {value: {field: 'saved'}, start: literal(2)}}},
          {position: {subtract: [{field: 'position'}, literal(1)]}},
          {length: {subtract: [{field: 'length'}, literal(2)]}},
          {value: {substring: {value: {field: 'payload'}, start: {field: 'position'},
            length: {field: 'length'}}}},
          // Named-child occurrence paths must also survive a nested value child.
          {nested: {substring: {value: {substring: {value: {field: 'saved'},
            start: {field: 'position'}, length: {field: 'length'}}}, start: literal(1)}}},
        ], as: 'derived'},
        {select: fields, as: 'out'},
      ], results: {rows: {from: 'out', fields}},
    }], results: {answer: {from: {stage: 'main', result: 'rows'}}}});
    await assertPublished(f, source, {format: 'json',
      submissionRef: f.client.newSubmission({nonce: 'ordered-fields'})}, cases);
  });

test('public substring schemas include NULL from every supplied parameter even for empty relations',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {
      p: {type: 'string', nullable: true}, q: {type: 'string', nullable: false},
      s: {type: 'number', nullable: true}, t: {type: 'number', nullable: false},
      n: {type: 'number', nullable: true}, m: {type: 'number', nullable: false},
    };
    for (const [id, parameters, nullableResult, nullableSuffix, empty] of [
      ['value', {p: 'a😀e\u0301z', q: 'a😀e\u0301z', s: 2, t: 2, n: 2, m: 2},
        '😀e', '😀e\u0301z', false],
      ['null', {p: null, q: 'a😀e\u0301z', s: null, t: 2, n: null, m: 2}, null, null, false],
      ['empty', {p: null, q: 'a😀e\u0301z', s: null, t: 2, n: null, m: 2}, null, null, true],
    ]) {
      const cases = [
        string('nullable_value', 'SUBSTR(@p, @t, @m)',
          {substring: {value: {$param: 'p'}, start: {$param: 't'}, length: {$param: 'm'}}},
          nullableResult, true),
        string('nullable_position', 'SUBSTRING(@q, @s, @m)',
          {substring: {value: {$param: 'q'}, start: {$param: 's'}, length: {$param: 'm'}}},
          nullableResult, true),
        string('nullable_length', 'SUBSTR(@q, @t, @n)',
          {substring: {value: {$param: 'q'}, start: {$param: 't'}, length: {$param: 'n'}}},
          nullableResult, true),
        string('nonnull', 'SUBSTRING(@q, @t, @m)',
          {substring: {value: {$param: 'q'}, start: {$param: 't'}, length: {$param: 'm'}}}, '😀e'),
        string('omitted_length', 'SUBSTR(@q, @t)',
          {substring: {value: {$param: 'q'}, start: {$param: 't'}}}, '😀e\u0301z'),
        string('nullable_omitted_length', 'SUBSTRING(@q, @s)',
          {substring: {value: {$param: 'q'}, start: {$param: 's'}}}, nullableSuffix, true),
      ];
      for (const format of formats) {
        const source = sourceFor(format, 'substring_parameters', cases, parameterDeclarations, empty);
        await assertPublished(f, source, {format, parameters,
          ...(format !== 'json' ? {parameterDeclarations} : {}),
          submissionRef: f.client.newSubmission({nonce: `${id}-${format}`})}, cases, empty);
      }
    }
  });

async function assertRefused(f, source, options, code = 'ClientProgramInvalidInput') {
  await assert.rejects(f.client.startSource(source, options), error => {
    assert.equal(error.code, 'SubmissionNotAccepted');
    const outcome = getSubmissionOutcome(error);
    assert.equal(outcome.kind, 'not_accepted');
    assert.deepEqual(outcome.submissionRef, options.submissionRef);
    assert.deepEqual(outcome.problem, {code, classification:
      code === 'ClientProgramImplementationLimit' ? 'implementation_limit' : 'invalid_input'}, source);
    return true;
  });
}

test('public SUBSTR and SUBSTRING reject wrong arity and excluded text overloads before dispatch',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    for (const call of ['SUBSTR', 'SUBSTRING']) {
      const invalid = [
        {text: `${call}()`},
        {text: `${call}('abc')`},
        {text: `${call}('abc', 1, 2, 3)`},
        {text: `${call}(b'abc', 1)`},
        {text: `${call}(COLLATE('abc', 'und:ci'), 1)`, unsupportedText: true},
      ];
      for (const [index, item] of invalid.entries()) {
        for (const format of ['sql', 'aql-text']) {
          const source = sourceFor(format, 'substring_invalid_text', [{name: 'value', ...item}]);
          await assertRefused(f, source, {format,
            submissionRef: f.client.newSubmission({nonce: `${call}-${index}-${format}`})},
          item.unsupportedText ? 'ClientProgramImplementationLimit' : 'ClientProgramInvalidInput');
        }
      }
    }
    assert.equal(f.dispatches(), 0, 'invalid text must fail before dispatch');
    assert.equal(f.advances(), 0, 'invalid text must not start Local evaluation');
  });

test('public substring rejects incompatible child types in every source format before dispatch',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const invalid = [
      {text: 'SUBSTR(1, 1)', expression: {substring: {value: literal(1), start: literal(1)}}},
      {text: 'SUBSTRING(TRUE, 1)', expression: {substring: {value: literal(true), start: literal(1)}}},
      {text: "SUBSTR('abc', '1')", expression: {substring: {value: literal('abc'), start: literal('1')}}},
      {text: "SUBSTRING('abc', TRUE)", expression: {substring: {value: literal('abc'), start: literal(true)}}},
      {text: "SUBSTR('abc', 1, '2')", expression: {substring: {
        value: literal('abc'), start: literal(1), length: literal('2')}}},
      {text: 'SUBSTRING(NULL, 1, TRUE)', expression: {substring: {
        value: literal(null), start: literal(1), length: literal(true)}}},
      {text: 'SUBSTR(NULL, FALSE, NULL)', expression: {substring: {
        value: literal(null), start: literal(false), length: literal(null)}}},
    ];
    for (const [index, item] of invalid.entries()) {
      for (const format of formats) {
        const source = sourceFor(format, 'substring_invalid_type', [{name: 'value', ...item}]);
        await assertRefused(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `types-${index}-${format}`})});
      }
    }
    assert.equal(f.dispatches(), 0, 'wrong child types must fail before dispatch');
    assert.equal(f.advances(), 0, 'wrong child types must not start Local evaluation');
  });

test('public JSON substring requires its closed structural payload and canonical tag',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const invalid = [
      {substring: []},
      {substring: [literal('abc'), literal(1)]},
      {substring: {}},
      {substring: {value: literal('abc')}},
      {substring: {start: literal(1)}},
      {substring: {value: literal('abc'), start: literal(1), end: literal(2)}},
      {substring: {value: literal('abc'), start: literal(1), length: literal(2), extra: false}},
      {substring: {value: literal('abc'), start: literal(1), length: null}},
      {substr: {value: literal('abc'), start: literal(1)}},
      {substring: {value: literal('abc'), start: literal(1)}, extra: literal(2)},
    ];
    for (const [index, expression] of invalid.entries()) {
      const source = sourceFor('json', 'substring_invalid_json', [{name: 'value', expression}]);
      await assertRefused(f, source, {format: 'json',
        submissionRef: f.client.newSubmission({nonce: `json-${index}`})});
    }
    assert.equal(f.dispatches(), 0, 'malformed structure must fail before dispatch');
    assert.equal(f.advances(), 0, 'malformed structure must not start Local evaluation');
  });

test('public substring rejects invalid parameter bindings before dispatch',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p: {type: 'string', nullable: false},
      s: {type: 'number', nullable: false}, n: {type: 'number', nullable: false}};
    const cases = [{name: 'value', text: 'SUBSTRING(@p, @s, @n)',
      expression: {substring: {value: {$param: 'p'}, start: {$param: 's'}, length: {$param: 'n'}}}}];
    for (const [index, parameters] of [
      {p: 1, s: 1, n: 1}, {p: null, s: 1, n: 1},
      {p: 'abc', s: '1', n: 1}, {p: 'abc', s: null, n: 1},
      {p: 'abc', s: 1, n: true}, {p: 'abc', s: 1, n: null},
    ].entries()) {
      for (const format of formats) {
        const source = sourceFor(format, 'substring_invalid_binding', cases, parameterDeclarations);
        await assertRefused(f, source, {format, parameters,
          ...(format !== 'json' ? {parameterDeclarations} : {}),
          submissionRef: f.client.newSubmission({nonce: `binding-${index}-${format}`})});
      }
    }
    assert.equal(f.dispatches(), 0, 'invalid bindings must fail before dispatch');
    assert.equal(f.advances(), 0, 'invalid bindings must not start Local evaluation');
  });

async function assertFailed(f, source, options) {
  const beforeDispatches = f.dispatches();
  const run = await f.client.startSource(source, options);
  const state = await run.wait({signal: AbortSignal.timeout(15_000)});
  assert.equal(state.status, 'failed', JSON.stringify(state));
  assert.ok(f.dispatches() > beforeDispatches, 'operand failure must occur during execution');
  assert.equal(state.result_availability.answer.state, 'unavailable');
  await assert.rejects(run.result('answer').all());
  await assert.rejects(run.result('answer').describe());
  const before = f.dispatches();
  assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
  const attached = await f.client.attach(run.ref);
  assert.equal((await attached.status()).status, 'failed');
  await assert.rejects(attached.result('answer').all());
  await assert.rejects(attached.result('answer').describe());
  assert.equal(f.dispatches(), before, 'failed resend and retained reread must not dispatch again');
}

const invalidNumbers = [
  {id: 'positions', cases: [
    {name: 'fraction', text: "SUBSTR('abc', 1.5)",
      expression: {substring: {value: literal('abc'), start: literal(1.5)}}},
    {name: 'negative_fraction', text: "SUBSTRING('abc', -1.5, 1)",
      expression: {substring: {value: literal('abc'), start: literal(-1.5), length: literal(1)}}},
    {name: 'unsafe_positive', text: "SUBSTR('abc', 9007199254740991 + 1, 1)",
      expression: {substring: {value: literal('abc'), start: {add:[literal(9007199254740991),literal(1)]}, length: literal(1)}}},
    {name: 'unsafe_negative', text: "SUBSTRING('abc', -9007199254740991 - 1)",
      expression: {substring: {value: literal('abc'), start: literal(-9007199254740991 - 1)}}},
  ]},
  {id: 'lengths', cases: [
    {name: 'negative', text: "SUBSTR('abc', 1, -1)",
      expression: {substring: {value: literal('abc'), start: literal(1), length: literal(-1)}}},
    {name: 'fraction', text: "SUBSTRING('abc', 1, 1.5)",
      expression: {substring: {value: literal('abc'), start: literal(1), length: literal(1.5)}}},
    {name: 'unsafe', text: "SUBSTR('abc', 1, 9007199254740991 + 1)",
      expression: {substring: {value: literal('abc'), start: literal(1), length: {add:[literal(9007199254740991),literal(1)]}}}},
    {name: 'empty_negative', text: "SUBSTRING('', 1, -1)",
      expression: {substring: {value: literal(''), start: literal(1), length: literal(-1)}}},
    {name: 'past_end_negative', text: "SUBSTR('abc', 4, -1)",
      expression: {substring: {value: literal('abc'), start: literal(4), length: literal(-1)}}},
  ]},
];
for (const batch of invalidNumbers) {
  test(`public substring invalid ${batch.id} fail during execution, not source admission`,
    {timeout: 90_000}, async t => {
      const f = await fixture(t);
      for (const item of batch.cases) {
        for (const format of formats) {
          await assertFailed(f, sourceFor(format, `substring_bad_${batch.id}_${item.name}`, [item]),
            {format, submissionRef: f.client.newSubmission({nonce: `${item.name}-${format}`})});
        }
      }
    });
}

test('public substring eagerly demands every supplied child even beside NULL or an empty slice',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    // Ordinary functions evaluate supplied children before NULL propagation;
    // IF evaluates only its selected branch.
    // https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions
    const failNumber = {divide: [literal(1), literal(0)]};
    const failString = {if: [{eq: [failNumber, literal(0)]}, literal('x'), literal('y')]};
    const cases = [
      {name: 'value_beside_null_start', text: "SUBSTR(IF(1 / 0 = 0, 'x', 'y'), NULL, 1)",
        expression: {substring: {value: failString, start: literal(null), length: literal(1)}}},
      {name: 'start_beside_null_value', text: 'SUBSTRING(NULL, 1 / 0)',
        expression: {substring: {value: literal(null), start: failNumber}}},
      {name: 'length_beside_null_value', text: 'SUBSTR(NULL, 1, 1 / 0)',
        expression: {substring: {value: literal(null), start: literal(1), length: failNumber}}},
      {name: 'length_beside_null_start', text: "SUBSTRING('abc', NULL, 1 / 0)",
        expression: {substring: {value: literal('abc'), start: literal(null), length: failNumber}}},
      {name: 'start_beside_null_length', text: "SUBSTR('abc', 1 / 0, NULL)",
        expression: {substring: {value: literal('abc'), start: failNumber, length: literal(null)}}},
      {name: 'value_beside_null_length', text: "SUBSTRING(IF(1 / 0 = 0, 'x', 'y'), 1, NULL)",
        expression: {substring: {value: failString, start: literal(1), length: literal(null)}}},
      {name: 'value_before_zero_length', text: "SUBSTR(IF(1 / 0 = 0, 'x', 'y'), 1, 0)",
        expression: {substring: {value: failString, start: literal(1), length: literal(0)}}},
      {name: 'length_beside_past_end', text: "SUBSTRING('abc', 4, 1 / 0)",
        expression: {substring: {value: literal('abc'), start: literal(4), length: failNumber}}},
    ];
    for (const item of cases) {
      for (const format of formats) {
        await assertFailed(f, sourceFor(format, 'substring_demanded_' + item.name, [item]),
          {format, submissionRef: f.client.newSubmission({nonce: `${item.name}-${format}`})});
      }
    }
  });

test('public substring respects lazy IF demand outside and inside the call',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p: {type: 'string', nullable: false}};
    const p = {$param: 'p'};
    const failNumber = {divide: [literal(1), literal(0)]};
    const failString = {if: [{eq: [failNumber, literal(0)]}, p, p]};
    const badSlice = {substring: {value: failString, start: literal(1)}};
    const cases = [
      string('skip_then', "IF(FALSE, SUBSTR(IF(1 / 0 = 0, @p, @p), 1), @p)",
        {if: [literal(false), badSlice, p]}, 'a😀b'),
      string('skip_else', "IF(TRUE, @p, SUBSTRING(IF(1 / 0 = 0, @p, @p), 1))",
        {if: [literal(true), p, badSlice]}, 'a😀b'),
      string('skip_invalid_length', 'IF(FALSE, SUBSTR(@p, 1, -1), @p)',
        {if: [literal(false), {substring: {value: p, start: literal(1), length: literal(-1)}}, p]}, 'a😀b'),
      string('value_branch', 'SUBSTRING(IF(TRUE, @p, IF(1 / 0 = 0, @p, @p)), 2, 1)',
        {substring: {value: {if: [literal(true), p, failString]}, start: literal(2), length: literal(1)}}, '😀'),
      string('start_branch', 'SUBSTR(@p, IF(TRUE, 2, 1 / 0), 1)',
        {substring: {value: p, start: {if: [literal(true), literal(2), failNumber]}, length: literal(1)}}, '😀'),
      string('length_branch', 'SUBSTRING(@p, 2, IF(FALSE, 1 / 0, 1))',
        {substring: {value: p, start: literal(2), length: {if: [literal(false), failNumber, literal(1)]}}}, '😀'),
    ];
    for (const format of formats) {
      const source = sourceFor(format, 'substring_lazy', cases, parameterDeclarations);
      await assertPublished(f, source, {format, parameters: {p: 'a😀b'},
        ...(format !== 'json' ? {parameterDeclarations} : {}),
        submissionRef: f.client.newSubmission({nonce: `lazy-${format}`})}, cases);
    }
  });

test('public substring cancellation stops after charged progress without publishing a result',
  {timeout: 60_000}, async t => {
    const reached = Promise.withResolvers();
    const resume = Promise.withResolvers();
    let completions = 0;
    t.after(() => resume.resolve());
    const f = await fixture(t, {
      onComputed() {
        completions++;
        reached.reject(new Error('SUBSTRING completed before the charged progress barrier'));
      },
      async onAdvance(count) {
        if (count === 10) {
          reached.resolve();
          await resume.promise;
        }
      },
    });
    // Preserve the established 4096-byte Values cell boundary. A field operand
    // exercises both the negative-position scalar scan and output copying.
    const payload = '😀'.repeat(1023) + 'a\u0000\r\n';
    assert.equal(Buffer.byteLength(payload), 4096);
    const source = JSON.stringify({version: 'actql/0.1', id: 'substring_cancel', stages: [{
      id: 'main', inputs: {}, steps: [
        {values: {schema: {payload: {type: 'string', nullable: false}},
          rows: [{payload}]}, as: 'seed'},
        {from: 'seed', derive: {value: {substring: {value: {field: 'payload'},
          start: literal(-1027), length: literal(1027)}}}, as: 'derived'},
        {select: ['value'], as: 'out'},
      ], results: {rows: {from: 'out', fields: ['value']}},
    }], results: {answer: {from: {stage: 'main', result: 'rows'}}}});
    const options = {format: 'json',
      submissionRef: f.client.newSubmission({nonce: 'substring-cancel'})};
    const run = await f.client.startSource(source, options);
    await reached.promise;
    const before = f.advances();
    try {
      await run.cancel();
      const pending = await run.status();
      assert.equal(pending.control.cancellation_requested, true);
      assert.notEqual(pending.control.physical_stop, 'confirmed');
      assert.notEqual(pending.status, 'cancelled');
      assert.equal(completions, 0);
    } finally { resume.resolve(); }
    const stopped = await run.wait({signal: AbortSignal.timeout(15_000)});
    assert.equal(stopped.status, 'cancelled', JSON.stringify(stopped));
    assert.equal(stopped.control.cancellation_requested, true);
    assert.equal(stopped.control.physical_stop, 'confirmed');
    assert.equal(stopped.result_availability.answer.state, 'unavailable');
    await assert.rejects(run.result('answer').all());
    await assert.rejects(run.result('answer').describe());
    assert.equal(completions, 0);
    assert.equal(f.advances(), before);
    assert.equal(f.dispatches(), 1);
    assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
    const attached = await f.client.attach(run.ref);
    assert.equal((await attached.status()).status, 'cancelled');
    await assert.rejects(attached.result('answer').all());
    await assert.rejects(attached.result('answer').describe());
    assert.equal(f.dispatches(), 1, 'cancelled resend and reread must not dispatch again');
  });
