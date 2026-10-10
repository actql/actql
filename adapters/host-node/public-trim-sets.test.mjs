import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Independent code-point-set expectations from the STRING TRIM contract.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#trim
// No host trim or live-service output supplies these expected rows/schemas.
const literal = value => ({literal: value});
const string = (name, text, expression, expected, nullable = false) =>
  ({name, text, expression, expected, contract: {type: 'string', nullable}});
const formats = ['sql', 'aql-text', 'json'];
const operators = [{tag: 'trim', call: 'TRIM'}, {tag: 'ltrim', call: 'LTRIM'}, {tag: 'rtrim', call: 'RTRIM'}];

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
  const directory = await mkdtemp(join(tmpdir(), 'actql-trim-set-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'trim-set',
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

const vectors = [
  ['set_not_substring', "'xzxapplexxy'", "'xyz'", 'xzxapplexxy', 'xyz', 'apple', 'applexxy', 'xzxapple'],
  ['duplicate_reordered', "'xyxappleyxx'", "'yxxy'", 'xyxappleyxx', 'yxxy', 'apple', 'appleyxx', 'xyxapple'],
  ['explicit_no_whitespace', "'  x  '", "'x'", '  x  ', 'x', '  x  ', '  x  ', '  x  '],
  ['empty_set', "' 😀 '", "''", ' 😀 ', '', ' 😀 ', ' 😀 ', ' 😀 '],
  ['empty_input', "''", "'abc'", '', 'abc', '', '', ''],
  ['all_members', "'ababab'", "'ba'", 'ababab', 'ba', '', '', ''],
  ['astral', "'😀😁a😁😀'", "'😀'", '😀😁a😁😀', '😀', '😁a😁', '😁a😁😀', '😀😁a😁'],
  ['astral_pair', "'😀😁a😁😀'", "'😁😀'", '😀😁a😁😀', '😁😀', 'a', 'a😁😀', '😀😁a'],
  ['combining_tail', "'abaW̊'", "'Y̊'", 'abaW̊', 'Y̊', 'abaW', 'abaW̊', 'abaW'],
  ['combining_head', "'W̊aba'", "'Y̊'", 'W̊aba', 'Y̊', 'W̊aba', 'W̊aba', 'W̊aba'],
  ['combining_scalars', "'́é'", "'́'", '́é', '́', 'e', 'é', '́e'],
  ['composed', "'éxé'", "'é'", 'éxé', 'é', 'éxé', 'éxé', 'éxé'],
  ['decomposed', "'éxé'", "'é'", 'éxé', 'é', 'éxé', 'éxé', 'éxé'],
  ['nul', "'\\u0000x\\u0000'", "'\\u0000'", '\u0000x\u0000', '\u0000', 'x', 'x\u0000', '\u0000x'],
  ['explicit_bom', "'\\uFEFFx\\u200B'", "'\\u200B\\uFEFF'", '\uFEFFx\u200B', '\u200B\uFEFF', 'x', 'x\u200B', '\uFEFFx'],
  ['line_breaks', "'\\r\\nx\\n\\r'", "'\\r\\n'", '\r\nx\n\r', '\r\n', 'x', 'x\n\r', '\r\nx'],
];

test('public STRING trim sets preserve exact independent scalar-set rows and schemas in SQL Pipe and JSON', {timeout: 120_000}, async t => {
  const f = await fixture(t);
  for (let index = 0; index < vectors.length; index += 2) {
    const cases = vectors.slice(index, index + 2).flatMap(([name, inputText, setText, input, set, ...expected]) =>
      operators.map(({tag, call}, i) => string(tag + '_' + name, `${call}(${inputText}, ${setText})`,
        {[tag]: [literal(input), literal(set)]}, expected[i])));
    for (const format of formats) {
      await assertPublished(f, sourceFor(format, 'trim_sets_' + index, cases), {format,
        submissionRef: f.client.newSubmission({nonce: `${index}-${format}`})}, cases);
    }
  }
});

test('public trim sets preserve nullable operand schemas strict NULL and empty relations', {timeout: 90_000}, async t => {
  const f = await fixture(t);
  const parameterDeclarations = {p: {type: 'string', nullable: true}, q: {type: 'string', nullable: true}};
  for (const [id, parameters, expected, empty] of [
    ['value', {p: 'xyax', q: 'xy'}, ['a', 'ax', 'xya'], false],
    ['left_null', {p: null, q: 'xy'}, [null, null, null], false],
    ['right_null', {p: 'xyax', q: null}, [null, null, null], false],
    ['both_null', {p: null, q: null}, [null, null, null], false],
    ['empty_set', {p: 'xyax', q: ''}, ['xyax', 'xyax', 'xyax'], false],
    ['empty_relation', {p: null, q: null}, [null, null, null], true],
  ]) {
    const cases = operators.map(({tag, call}, i) => string(tag, `${call}(@p, @q)`,
      {[tag]: [{$param: 'p'}, {$param: 'q'}]}, expected[i], true));
    for (const format of formats) {
      await assertPublished(f, sourceFor(format, 'trim_set_parameters', cases, parameterDeclarations, empty),
        {format, parameters, ...(format !== 'json' ? {parameterDeclarations} : {}),
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

test('public explicit trim sets refuse malformed pairs types and excluded overloads before dispatch', {timeout: 90_000}, async t => {
  const f = await fixture(t);
  for (const {tag, call} of operators) {
    const invalid = [
      {text: `${call}('a', 1)`, expression: {[tag]: [literal('a'), literal(1)]}},
      {text: `${call}(TRUE, 'a')`, expression: {[tag]: [literal(true), literal('a')]}},
      {text: `${call}('a', 'b', 'c')`, expression: {[tag]: [literal('a'), literal('b'), literal('c')]}},
      {text: `${call}('a', COLLATE('a', 'und:ci'))`, expression: {[tag]: [literal('a'), {collate: [literal('a'), literal('und:ci')]}]}, unsupportedText: true},
    ];
    for (const [index, item] of invalid.entries()) {
      for (const format of formats) {
        await assertRefused(f, sourceFor(format, 'trim_set_invalid', [{name: 'value', ...item}]), {format,
          submissionRef: f.client.newSubmission({nonce: `${tag}-${index}-${format}`})},
        item.unsupportedText && format !== 'json' ? 'ClientProgramImplementationLimit' : 'ClientProgramInvalidInput');
      }
    }
    for (const [index, body] of [[literal('a')], [], {value: literal('a'), characters: literal('a')}].entries()) {
      await assertRefused(f, sourceFor('json', 'trim_set_shape', [{name: 'value', expression: {[tag]: body}}]),
        {format: 'json', submissionRef: f.client.newSubmission({nonce: `${tag}-shape-${index}`})});
    }
    for (const format of ['sql', 'aql-text']) {
      await assertRefused(f, sourceFor(format, 'trim_set_bytes', [{name: 'value', text: `${call}(b'a', b'a')`}]),
        {format, submissionRef: f.client.newSubmission({nonce: `${tag}-bytes-${format}`})});
    }
  }
  assert.equal(f.dispatches(), 0);
  assert.equal(f.advances(), 0);
});

test('public trim sets demand the second child after NULL while preserving lazy branches', {timeout: 90_000}, async t => {
  const f = await fixture(t);
  const fail = {if: [{eq: [{divide: [literal(1), literal(0)]}, literal(0)]}, literal('x'), literal('y')]};
  for (const {tag, call} of operators) {
    const cases = [
      string('skip', `IF(FALSE, ${call}(NULL, IF(1 / 0 = 0, 'x', 'y')), 'safe')`,
        {if: [literal(false), {[tag]: [literal(null), fail]}, literal('safe')]}, 'safe', true),
      string('unary', `${call}(' x ')`, {[tag]: literal(' x ')}, tag === 'trim' ? 'x' : tag === 'ltrim' ? 'x ' : ' x'),
    ];
    for (const format of formats) {
      await assertPublished(f, sourceFor(format, 'trim_set_lazy', cases), {format,
        submissionRef: f.client.newSubmission({nonce: `${tag}-lazy-${format}`})}, cases);
      const demanded = [{name: 'value', text: `${call}(NULL, IF(1 / 0 = 0, 'x', 'y'))`, expression: {[tag]: [literal(null), fail]}}];
      const source = sourceFor(format, 'trim_set_demanded', demanded);
      const options = {format, submissionRef: f.client.newSubmission({nonce: `${tag}-demanded-${format}`})};
      const before = f.dispatches();
      const run = await f.client.startSource(source, options);
      const state = await run.wait({signal: AbortSignal.timeout(15_000)});
      assert.equal(state.status, 'failed', JSON.stringify(state));
      assert.ok(f.dispatches() > before);
      assert.equal(state.result_availability.answer.state, 'unavailable');
      await assert.rejects(run.result('answer').all());
      const dispatched = f.dispatches();
      assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
      const attached = await f.client.attach(run.ref);
      assert.equal((await attached.status()).status, 'failed');
      await assert.rejects(attached.result('answer').all());
      assert.equal(f.dispatches(), dispatched);
    }
  }
});
for (const {tag, call} of operators) {
  test(`public ${call} explicit-set cancellation stops after charged progress without publishing a result`,
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
          {from: 'seed', derive: {value: {[tag]: [{field: 'payload'}, literal('z'.repeat(128) + '\u2003\u3000')]}}, as: 'derived'},
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
