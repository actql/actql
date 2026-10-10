import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Independent STRING/unary TRIM vectors, not live BigQuery results.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#trim
// https://www.unicode.org/Public/16.0.0/ucd/PropList.txt
// The pinned White_Space set has 25 code points. SQL source, common expressions,
// expected strings, and contracts are authored independently of product output.
const literal = value => ({literal: value});
const string = (name, text, expression, expected, nullable = false) =>
  ({name, text, expression, expected, contract: {type: 'string', nullable}});
const formats = ['sql', 'aql-text', 'json'];

const batches = [
  {id: 'whitespace', cases: [
    string('documented', "TRIM('   apple   ')", {trim: literal('   apple   ')}, 'apple'),
    string('all_edges',
      "TRIM('\\u0009\\u000A\\u000B\\u000C\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000x\\u0009\\u000A\\u000B\\u000C\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000')",
      {trim: literal('\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000x\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000')}, 'x'),
    string('all_whitespace',
      "TRIM('\\u0009\\u000A\\u000B\\u000C\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000')",
      {trim: literal('\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000')}, ''),
    string('interior', "trim(' \\u3000a\\u0009\\u0085\\u00A0\\u2003\\u2028\\u202Fb\\u3000 ')",
      {trim: literal(' \u3000a\u0009\u0085\u00A0\u2003\u2028\u202Fb\u3000 ')},
      'a\u0009\u0085\u00A0\u2003\u2028\u202Fb'),
    string('empty', "`TrIm`('')", {trim: literal('')}, ''),
    string('null_value', 'TRIM(NULL)', {trim: literal(null)}, null, true),
  ]},
  {id: 'preserved', cases: [
    string('bom', "TRIM(' \\uFEFF x \\uFEFF ')",
      {trim: literal(' \uFEFF x \uFEFF ')}, '\uFEFF x \uFEFF'),
    string('zero_width', "TRIM(' \\u200B x \\u200B ')",
      {trim: literal(' \u200B x \u200B ')}, '\u200B x \u200B'),
    string('mongolian', "TRIM(' \\u180E x \\u180E ')",
      {trim: literal(' \u180E x \u180E ')}, '\u180E x \u180E'),
    string('control_neighbors', "TRIM(' \\u0008\\u000E\\u001C\\u001F\\u0084\\u0086 \\u0086\\u0084\\u001F\\u001C\\u000E\\u0008 ')",
      {trim: literal(' \u0008\u000E\u001C\u001F\u0084\u0086 \u0086\u0084\u001F\u001C\u000E\u0008 ')},
      '\u0008\u000E\u001C\u001F\u0084\u0086 \u0086\u0084\u001F\u001C\u000E\u0008'),
    string('unicode_neighbors', "TRIM(' \\u009F\\u00A1\\u167F\\u1681\\u1FFF\\u200B\\u2027\\u202A\\u202E\\u2030\\u205E\\u2060\\u2FFF\\u3001 \\u3001\\u2FFF\\u2060\\u205E\\u2030\\u202E\\u202A\\u2027\\u200B\\u1FFF\\u1681\\u167F\\u00A1\\u009F ')",
      {trim: literal(' \u009F\u00A1\u167F\u1681\u1FFF\u200B\u2027\u202A\u202E\u2030\u205E\u2060\u2FFF\u3001 \u3001\u2FFF\u2060\u205E\u2030\u202E\u202A\u2027\u200B\u1FFF\u1681\u167F\u00A1\u009F ')},
      '\u009F\u00A1\u167F\u1681\u1FFF\u200B\u2027\u202A\u202E\u2030\u205E\u2060\u2FFF\u3001 \u3001\u2FFF\u2060\u205E\u2030\u202E\u202A\u2027\u200B\u1FFF\u1681\u167F\u00A1\u009F'),
    string('astral_decomposed', "TRIM('\\u2003😀e\\u0301😀\\u00A0')",
      {trim: literal('\u2003😀e\u0301😀\u00A0')}, '😀e\u0301😀'),
    string('combining_edges', "TRIM(' \\u0301e\\u0301 ')",
      {trim: literal(' \u0301e\u0301 ')}, '\u0301e\u0301'),
    string('nul_edges', "TRIM(' \\u0000x\\u0000 ')",
      {trim: literal(' \u0000x\u0000 ')}, '\u0000x\u0000'),
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
  const directory = await mkdtemp(join(tmpdir(), 'actql-trim-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'trim',
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

test('public SQL, Pipe, and independent JSON trim the pinned Unicode White_Space set',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    for (const batch of batches) {
      for (const format of formats) {
        const source = sourceFor(format, 'trim_' + batch.id, batch.cases);
        await assertPublished(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `${batch.id}-${format}`})}, batch.cases);
      }
    }
  });

test('public TRIM retains nullable STRING schemas for values, NULL, and empty relations',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p: {type: 'string', nullable: true},
      q: {type: 'string', nullable: false}};
    for (const [id, parameters, expected, empty] of [
      ['value', {p: '\u0085😀e\u0301\u3000', q: '  fixed  '}, '😀e\u0301', false],
      ['null', {p: null, q: '  fixed  '}, null, false],
      ['empty', {p: null, q: '  fixed  '}, null, true],
    ]) {
      const cases = [
        string('nullable_value', 'TRIM(@p)', {trim: {$param: 'p'}}, expected, true),
        string('nonnull_value', 'TRIM(@q)', {trim: {$param: 'q'}}, 'fixed'),
      ];
      for (const format of formats) {
        const source = sourceFor(format, 'trim_parameters', cases, parameterDeclarations, empty);
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

test('public TRIM refuses wrong arity, types, bindings, and excluded overloads before dispatch',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const invalid = [
      {text: 'TRIM()', expression: {trim: []}},
      {text: "TRIM(' a ', ' ')", expression: {trim: [literal(' a '), literal(' ')]}},
      {text: "TRIM('a', 'b', 'c')", expression: {trim: [literal('a'), literal('b'), literal('c')]}},
      {text: 'TRIM(1)', expression: {trim: literal(1)}},
      {text: 'TRIM(TRUE)', expression: {trim: literal(true)}},
      // Side-specific unary trims are admitted; explicit character sets remain excluded.
      {text: "LTRIM(' a ', ' ')", expression: {ltrim: [literal(' a '), literal(' ')]}},
      {text: "RTRIM(' a ', ' ')", expression: {rtrim: [literal(' a '), literal(' ')]}},
    ];
    for (const [index, item] of invalid.entries()) {
      for (const format of formats) {
        const source = sourceFor(format, 'trim_invalid', [{name: 'value', ...item}]);
        await assertRefused(f, source, {format,
          submissionRef: f.client.newSubmission({nonce: `invalid-${index}-${format}`})},
        item.unsupportedText && format !== 'json'
          ? 'ClientProgramImplementationLimit' : 'ClientProgramInvalidInput');
      }
    }
    // BYTES has no common-expression counterpart in this STRING-only surface.
    for (const format of ['sql', 'aql-text']) {
      const source = sourceFor(format, 'trim_bytes', [{name: 'value', text: "TRIM(b' a ')"}]);
      await assertRefused(f, source, {format,
        submissionRef: f.client.newSubmission({nonce: 'bytes-' + format})});
    }
    const parameterDeclarations = {p: {type: 'string', nullable: false}};
    const cases = [{name: 'value', text: 'TRIM(@p)', expression: {trim: {$param: 'p'}}}];
    for (const [index, p] of [1, true, null].entries()) {
      for (const format of formats) {
        const source = sourceFor(format, 'trim_bad_binding', cases, parameterDeclarations);
        await assertRefused(f, source, {format, parameters: {p},
          ...(format !== 'json' ? {parameterDeclarations} : {}),
          submissionRef: f.client.newSubmission({nonce: `binding-${index}-${format}`})});
      }
    }
    assert.equal(f.dispatches(), 0, 'invalid source and bindings must fail before dispatch');
    assert.equal(f.advances(), 0, 'invalid input must not start Local evaluation');
  });

test('public TRIM propagates demanded child errors and respects lazy IF branches',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    // https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions
    const demandedText = {if: [{eq: [{divide: [literal(1), literal(0)]}, literal(0)]},
      literal(' x '), literal(' y ')]};
    const demanded = [{name: 'value', text: "TRIM(IF(1 / 0 = 0, ' x ', ' y '))",
      expression: {trim: demandedText}}];
    const lazy = [
      string('skip_then', "IF(FALSE, TRIM(IF(1 / 0 = 0, ' x ', ' y ')), ' safe ')",
        {if: [literal(false), {trim: demandedText}, literal(' safe ')]}, ' safe '),
      string('skip_else', "IF(TRUE, ' safe ', TRIM(IF(1 / 0 = 0, ' x ', ' y ')))",
        {if: [literal(true), literal(' safe '), {trim: demandedText}]}, ' safe '),
      string('inner_branch', "TRIM(IF(TRUE, ' x ', IF(1 / 0 = 0, ' y ', ' z ')))",
        {trim: {if: [literal(true), literal(' x '),
          {if: [{eq: [{divide: [literal(1), literal(0)]}, literal(0)]},
            literal(' y '), literal(' z ')]}]}}, 'x'),
    ];
    for (const format of formats) {
      const source = sourceFor(format, 'trim_demanded_error', demanded);
      const options = {format,
        submissionRef: f.client.newSubmission({nonce: 'demanded-' + format})};
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
      await assertPublished(f, sourceFor(format, 'trim_lazy', lazy), {format,
        submissionRef: f.client.newSubmission({nonce: 'lazy-' + format})}, lazy);
    }
  });

test('public TRIM cancellation stops after charged progress without publishing a result',
  {timeout: 60_000}, async t => {
    const reached = Promise.withResolvers();
    const resume = Promise.withResolvers();
    let completions = 0;
    t.after(() => resume.resolve());
    const f = await fixture(t, {
      onComputed() {
        completions++;
        reached.reject(new Error('TRIM completed before the charged progress barrier'));
      },
      async onAdvance(count) {
        if (count === 10) {
          reached.resolve();
          await resume.promise;
        }
      },
    });
    // Match the existing Text cancellation fixture's 4096-byte Values cell
    // and isolate bounded execution cancellation through a field operand.
    const payload = '\u2003'.repeat(682) + '😀' + '\u3000'.repeat(682);
    assert.equal(Buffer.byteLength(payload), 4096);
    const source = JSON.stringify({version: 'actql/0.1', id: 'trim_cancel', stages: [{
      id: 'main', inputs: {}, steps: [
        {values: {schema: {payload: {type: 'string', nullable: false}},
          rows: [{payload}]}, as: 'seed'},
        {from: 'seed', derive: {value: {trim: {field: 'payload'}}}, as: 'derived'},
        {select: ['value'], as: 'out'},
      ], results: {rows: {from: 'out', fields: ['value']}},
    }], results: {answer: {from: {stage: 'main', result: 'rows'}}}});
    const options = {format: 'json',
      submissionRef: f.client.newSubmission({nonce: 'trim-cancel'})};
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
    assert.equal(f.dispatches(), 1, 'cancelled resend and reread must not dispatch again');
  });
