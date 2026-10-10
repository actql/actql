import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Independent unary STRING LTRIM/RTRIM expectations, not live BigQuery results.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#ltrim
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#rtrim
// https://www.unicode.org/Public/16.0.0/ucd/PropList.txt
// SQL literals, JSON values, exact outputs, and contracts are authored directly.
// The pinned 25-code-point White_Space set is shared with unary TRIM. Neither
// host trim routines nor product output computes any expected result here.
const literal = value => ({literal: value});
const string = (name, text, expression, expected, nullable = false) =>
  ({name, text, expression, expected, contract: {type: 'string', nullable}});
const formats = ['sql', 'aql-text', 'json'];
const operators = [{tag: 'ltrim', call: 'LTRIM'}, {tag: 'rtrim', call: 'RTRIM'}];
const pair = (name, text, value, left, right, nullable = false) => [
  string('left_' + name, `LTRIM(${text})`, {ltrim: literal(value)}, left, nullable),
  string('right_' + name, `RTRIM(${text})`, {rtrim: literal(value)}, right, nullable),
];

const batches = [
  {id: 'whitespace', cases: [
    ...pair('documented', "'   apple   '", '   apple   ', 'apple   ', '   apple'),
    ...pair('all_edges',
      "'\\u0009\\u000A\\u000B\\u000C\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000x\\u0009\\u000A\\u000B\\u000C\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000'",
      '\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000x\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000',
      'x\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000',
      '\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000x'),
    ...pair('all_whitespace',
      "'\\u0009\\u000A\\u000B\\u000C\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000'",
      '\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000', '', ''),
    ...pair('interior', "' \\u3000a\\u0009\\u0085\\u00A0\\u2003\\u2028\\u202Fb\\u3000 '",
      ' \u3000a\u0009\u0085\u00A0\u2003\u2028\u202Fb\u3000 ',
      'a\u0009\u0085\u00A0\u2003\u2028\u202Fb\u3000 ',
      ' \u3000a\u0009\u0085\u00A0\u2003\u2028\u202Fb'),
  ]},
  {id: 'excluded_whitespace', cases: [
    ...pair('bom', "' \\uFEFF x \\uFEFF '", ' \uFEFF x \uFEFF ',
      '\uFEFF x \uFEFF ', ' \uFEFF x \uFEFF'),
    ...pair('zero_width', "' \\u200B x \\u200B '", ' \u200B x \u200B ',
      '\u200B x \u200B ', ' \u200B x \u200B'),
    ...pair('mongolian', "' \\u180E x \\u180E '", ' \u180E x \u180E ',
      '\u180E x \u180E ', ' \u180E x \u180E'),
    ...pair('control_neighbors',
      "' \\u0008\\u000E\\u001C\\u001F\\u0084\\u0086 \\u0086\\u0084\\u001F\\u001C\\u000E\\u0008 '",
      ' \u0008\u000E\u001C\u001F\u0084\u0086 \u0086\u0084\u001F\u001C\u000E\u0008 ',
      '\u0008\u000E\u001C\u001F\u0084\u0086 \u0086\u0084\u001F\u001C\u000E\u0008 ',
      ' \u0008\u000E\u001C\u001F\u0084\u0086 \u0086\u0084\u001F\u001C\u000E\u0008'),
  ]},
  {id: 'preserved', cases: [
    ...pair('unicode_neighbors',
      "' \\u009F\\u00A1\\u167F\\u1681\\u1FFF\\u200B\\u2027\\u202A\\u202E\\u2030\\u205E\\u2060\\u2FFF\\u3001 \\u3001\\u2FFF\\u2060\\u205E\\u2030\\u202E\\u202A\\u2027\\u200B\\u1FFF\\u1681\\u167F\\u00A1\\u009F '",
      ' \u009F\u00A1\u167F\u1681\u1FFF\u200B\u2027\u202A\u202E\u2030\u205E\u2060\u2FFF\u3001 \u3001\u2FFF\u2060\u205E\u2030\u202E\u202A\u2027\u200B\u1FFF\u1681\u167F\u00A1\u009F ',
      '\u009F\u00A1\u167F\u1681\u1FFF\u200B\u2027\u202A\u202E\u2030\u205E\u2060\u2FFF\u3001 \u3001\u2FFF\u2060\u205E\u2030\u202E\u202A\u2027\u200B\u1FFF\u1681\u167F\u00A1\u009F ',
      ' \u009F\u00A1\u167F\u1681\u1FFF\u200B\u2027\u202A\u202E\u2030\u205E\u2060\u2FFF\u3001 \u3001\u2FFF\u2060\u205E\u2030\u202E\u202A\u2027\u200B\u1FFF\u1681\u167F\u00A1\u009F'),
    ...pair('astral_decomposed', "'\\u2003😀e\\u0301😀\\u00A0'", '\u2003😀e\u0301😀\u00A0',
      '😀e\u0301😀\u00A0', '\u2003😀e\u0301😀'),
    ...pair('combining_edges', "' \\u0301e\\u0301 '", ' \u0301e\u0301 ',
      '\u0301e\u0301 ', ' \u0301e\u0301'),
    ...pair('nul_edges', "' \\u0000x\\u0000 '", ' \u0000x\u0000 ',
      '\u0000x\u0000 ', ' \u0000x\u0000'),
  ]},
  {id: 'one_sided', cases: [
    ...pair('leading_only', "'\\u0085\\u3000x'", '\u0085\u3000x', 'x', '\u0085\u3000x'),
    ...pair('trailing_only', "'x\\u0085\\u3000'", 'x\u0085\u3000', 'x\u0085\u3000', 'x'),
    ...pair('unchanged', "'😀e\\u0301\\u0000x'", '😀e\u0301\u0000x',
      '😀e\u0301\u0000x', '😀e\u0301\u0000x'),
    ...pair('null_value', 'NULL', null, null, null, true),
  ]},
  {id: 'spelling_empty', cases: [
    string('left_empty', "ltrim('')", {ltrim: literal('')}, ''),
    string('right_empty', "rtrim('')", {rtrim: literal('')}, ''),
    string('left_quoted', "`LtRiM`(' x ')", {ltrim: literal(' x ')}, 'x '),
    string('right_quoted', "`RtRiM`(' x ')", {rtrim: literal(' x ')}, ' x'),
  ]},
];

// Put each adjacent non-member at the actual scan boundary in both directions;
// preservation as an interior character alone would not exercise membership.
const neighborCases = [
  ...pair('control_0008', "' \\u0008 '", ' \u0008 ', '\u0008 ', ' \u0008'),
  ...pair('control_000e', "' \\u000E '", ' \u000E ', '\u000E ', ' \u000E'),
  ...pair('control_001c', "' \\u001C '", ' \u001C ', '\u001C ', ' \u001C'),
  ...pair('control_001f', "' \\u001F '", ' \u001F ', '\u001F ', ' \u001F'),
  ...pair('control_0084', "' \\u0084 '", ' \u0084 ', '\u0084 ', ' \u0084'),
  ...pair('control_0086', "' \\u0086 '", ' \u0086 ', '\u0086 ', ' \u0086'),
  ...pair('boundary_009f', "' \\u009F '", ' \u009F ', '\u009F ', ' \u009F'),
  ...pair('boundary_00a1', "' \\u00A1 '", ' \u00A1 ', '\u00A1 ', ' \u00A1'),
  ...pair('boundary_167f', "' \\u167F '", ' \u167F ', '\u167F ', ' \u167F'),
  ...pair('boundary_1681', "' \\u1681 '", ' \u1681 ', '\u1681 ', ' \u1681'),
  ...pair('boundary_1fff', "' \\u1FFF '", ' \u1FFF ', '\u1FFF ', ' \u1FFF'),
  ...pair('boundary_200b', "' \\u200B '", ' \u200B ', '\u200B ', ' \u200B'),
  ...pair('boundary_2027', "' \\u2027 '", ' \u2027 ', '\u2027 ', ' \u2027'),
  ...pair('boundary_202a', "' \\u202A '", ' \u202A ', '\u202A ', ' \u202A'),
  ...pair('boundary_202e', "' \\u202E '", ' \u202E ', '\u202E ', ' \u202E'),
  ...pair('boundary_2030', "' \\u2030 '", ' \u2030 ', '\u2030 ', ' \u2030'),
  ...pair('boundary_205e', "' \\u205E '", ' \u205E ', '\u205E ', ' \u205E'),
  ...pair('boundary_2060', "' \\u2060 '", ' \u2060 ', '\u2060 ', ' \u2060'),
  ...pair('boundary_2fff', "' \\u2FFF '", ' \u2FFF ', '\u2FFF ', ' \u2FFF'),
  ...pair('boundary_3001', "' \\u3001 '", ' \u3001 ', '\u3001 ', ' \u3001'),
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
  const directory = await mkdtemp(join(tmpdir(), 'actql-side-trim-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'side-trim',
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

test('public SQL, Pipe, and independent JSON trim only the selected Unicode whitespace edge',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    for (const batch of batches) {
      for (const format of formats) {
        const source = sourceFor(format, 'side_trim_' + batch.id, batch.cases);
        await assertPublished(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `${batch.id}-${format}`})}, batch.cases);
      }
    }
  });

test('public side trims retain every selected non-whitespace neighbor at the scan boundary',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    for (let index = 0; index < neighborCases.length; index += 8) {
      const cases = neighborCases.slice(index, index + 8);
      for (const format of formats) {
        const source = sourceFor(format, 'side_trim_neighbors_' + index, cases);
        await assertPublished(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `neighbors-${index}-${format}`})}, cases);
      }
    }
  });

test('public LTRIM and RTRIM retain nullable STRING schemas for values, NULL, and empty relations',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p: {type: 'string', nullable: true},
      q: {type: 'string', nullable: false}};
    for (const [id, parameters, left, right, empty] of [
      ['value', {p: '\u0085😀e\u0301\u3000', q: '  fixed  '},
        '😀e\u0301\u3000', '\u0085😀e\u0301', false],
      ['null', {p: null, q: '  fixed  '}, null, null, false],
      ['empty', {p: null, q: '  fixed  '}, null, null, true],
    ]) {
      const cases = [
        string('nullable_left', 'LTRIM(@p)', {ltrim: {$param: 'p'}}, left, true),
        string('nullable_right', 'RTRIM(@p)', {rtrim: {$param: 'p'}}, right, true),
        string('nonnull_left', 'LTRIM(@q)', {ltrim: {$param: 'q'}}, 'fixed  '),
        string('nonnull_right', 'RTRIM(@q)', {rtrim: {$param: 'q'}}, '  fixed'),
      ];
      for (const format of formats) {
        const source = sourceFor(format, 'side_trim_parameters', cases, parameterDeclarations, empty);
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

test('public side trims refuse wrong arity, types, bindings, and excluded overloads before dispatch',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    for (const {tag, call} of operators) {
      const invalid = [
        {text: `${call}()`, expression: {[tag]: []}},
        {text: `${call}(' a ', 1)`, expression: {[tag]: [literal(' a '), literal(1)]}},
        {text: `${call}('a', 'b', 'c')`,
          expression: {[tag]: [literal('a'), literal('b'), literal('c')]}},
        {text: `${call}(1)`, expression: {[tag]: literal(1)}},
        {text: `${call}(TRUE)`, expression: {[tag]: literal(true)}},
        // Unknown text functions are implementation limits; unrecognized JSON
        // expression tags are invalid input under the closed common grammar.
        {text: `${call}(COLLATE(' a ', 'und:ci'))`,
          expression: {[tag]: {collate: [literal(' a '), literal('und:ci')]}},
          unsupportedText: true},
      ];
      for (const [index, item] of invalid.entries()) {
        for (const format of formats) {
          const source = sourceFor(format, 'side_trim_invalid', [{name: 'value', ...item}]);
          await assertRefused(f, source, {format,
            submissionRef: f.client.newSubmission({nonce: `${tag}-${index}-${format}`})},
          item.unsupportedText && format !== 'json'
            ? 'ClientProgramImplementationLimit' : 'ClientProgramInvalidInput');
        }
      }
      // BYTES has no common-expression counterpart in this STRING-only surface.
      for (const format of ['sql', 'aql-text']) {
        const source = sourceFor(format, 'side_trim_bytes',
          [{name: 'value', text: `${call}(b' a ')`}]);
        await assertRefused(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `${tag}-bytes-${format}`})});
      }
      const parameterDeclarations = {p: {type: 'string', nullable: false}};
      const cases = [{name: 'value', text: `${call}(@p)`, expression: {[tag]: {$param: 'p'}}}];
      for (const [index, p] of [1, true, null].entries()) {
        for (const format of formats) {
          const source = sourceFor(format, 'side_trim_bad_binding', cases, parameterDeclarations);
          await assertRefused(f, source, {format, parameters: {p},
            ...(format !== 'json' ? {parameterDeclarations} : {}),
            submissionRef: f.client.newSubmission({nonce: `${tag}-binding-${index}-${format}`})});
        }
      }
    }
    assert.equal(f.dispatches(), 0, 'invalid source and bindings must fail before dispatch');
    assert.equal(f.advances(), 0, 'invalid input must not start Local evaluation');
  });

test('public side trims propagate demanded child errors and respect lazy IF branches',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    // https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions
    const demandedText = {if: [{eq: [{divide: [literal(1), literal(0)]}, literal(0)]},
      literal(' x '), literal(' y ')]};
    for (const {tag, call} of operators) {
      const demanded = [{name: 'value', text: `${call}(IF(1 / 0 = 0, ' x ', ' y '))`,
        expression: {[tag]: demandedText}}];
      const lazy = [
        string('skip_then', `IF(FALSE, ${call}(IF(1 / 0 = 0, ' x ', ' y ')), ' safe ')`,
          {if: [literal(false), {[tag]: demandedText}, literal(' safe ')]}, ' safe '),
        string('skip_else', `IF(TRUE, ' safe ', ${call}(IF(1 / 0 = 0, ' x ', ' y ')))`,
          {if: [literal(true), literal(' safe '), {[tag]: demandedText}]}, ' safe '),
        string('inner_branch', `${call}(IF(TRUE, ' x ', IF(1 / 0 = 0, ' y ', ' z ')))`,
          {[tag]: {if: [literal(true), literal(' x '),
            {if: [{eq: [{divide: [literal(1), literal(0)]}, literal(0)]},
              literal(' y '), literal(' z ')]}]}}, tag === 'ltrim' ? 'x ' : ' x'),
      ];
      for (const format of formats) {
        const source = sourceFor(format, 'side_trim_demanded_error', demanded);
        const options = {format,
          submissionRef: f.client.newSubmission({nonce: `${tag}-demanded-${format}`})};
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
        await assertPublished(f, sourceFor(format, 'side_trim_lazy', lazy), {format,
          submissionRef: f.client.newSubmission({nonce: `${tag}-lazy-${format}`})}, lazy);
      }
    }
  });

for (const {tag, call} of operators) {
  test(`public ${call} cancellation stops after charged progress without publishing a result`,
    {timeout: 60_000}, async t => {
      const reached = Promise.withResolvers();
      const resume = Promise.withResolvers();
      let completions = 0;
      t.after(() => resume.resolve());
      const f = await fixture(t, {
        onComputed() {
          completions++;
          reached.reject(new Error(`${call} completed before the charged progress barrier`));
        },
        async onAdvance(count) {
          if (count === 10) {
            reached.resolve();
            await resume.promise;
          }
        },
      });
      // Keep the existing 4096-byte Values boundary and exercise a field operand.
      // Large expression literals have a separate pre-existing submission failure.
      const payload = '\u2003'.repeat(682) + '😀' + '\u3000'.repeat(682);
      assert.equal(Buffer.byteLength(payload), 4096);
      const source = JSON.stringify({version: 'actql/0.1', id: tag + '_cancel', stages: [{
        id: 'main', inputs: {}, steps: [
          {values: {schema: {payload: {type: 'string', nullable: false}},
            rows: [{payload}]}, as: 'seed'},
          {from: 'seed', derive: {value: {[tag]: {field: 'payload'}}}, as: 'derived'},
          {select: ['value'], as: 'out'},
        ], results: {rows: {from: 'out', fields: ['value']}},
      }], results: {answer: {from: {stage: 'main', result: 'rows'}}}});
      const options = {format: 'json',
        submissionRef: f.client.newSubmission({nonce: tag + '-cancel'})};
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
}
