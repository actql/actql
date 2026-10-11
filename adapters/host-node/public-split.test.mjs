import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Fixed independently authored STRING SPLIT outputs. Neither String.split,
// compiler output nor the evaluator computes expected parts. Empty input has
// one empty part, including with an empty delimiter. Empty delimiters otherwise
// split Unicode scalars, not UTF-16 units or grapheme clusters. No normalization.
const formats = ['sql', 'aql-text', 'json'];
const literal = value => ({literal: value});
const split = (value, delimiter) => ({split: [value,
  ...(delimiter === undefined ? [] : [delimiter])]});
const arrayContract = (nullable = false, input) => ({type: 'array', nullable,
  ...(typeof input === 'string' ? {max_items: Buffer.byteLength(input) + 1} : {}),
  items: {type: 'string', nullable: false,
    ...(typeof input === 'string' ? {max_utf8_bytes: Buffer.byteLength(input)} : {})}});
const valueCase = (name, text, expression, expected, contract) =>
  ({name, text, expression, expected, contract});
// Encode authored source literals only. This helper never derives expected data.
const sqlString = value => "'" + value.replace(/[\\'\u0000-\u001f]/gu, character => {
  if (character === '\\' || character === "'") return '\\' + character;
  return '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0');
}) + "'";
const literalCase = (name, input, delimiter, expected) => valueCase(name,
  `SPLIT(${sqlString(input)}${delimiter === undefined ? '' : ',' + sqlString(delimiter)})`,
  split(literal(input), delimiter === undefined ? undefined : literal(delimiter)),
  expected, arrayContract(false, input));
const literalCases = [
  literalCase('default_parts', 'red,,blue,', undefined, ['red', '', 'blue', '']),
  literalCase('leading', ',a', ',', ['', 'a']),
  literalCase('only_separators', ',,,', ',', ['', '', '', '']),
  literalCase('nonoverlap', 'aaa', 'aa', ['', 'a']),
  literalCase('repeated_prefix', 'aaabaaab', 'aab', ['a', 'a', '']),
  literalCase('literal_not_regex', 'a.*b.*', '.*', ['a', 'b', '']),
  literalCase('delimiter_longer', 'ab', 'abcd', ['ab']),
  literalCase('no_match', 'abc', 'x', ['abc']),
  literalCase('empty_default', '', undefined, ['']),
  literalCase('empty_nonempty', '', '::', ['']),
  literalCase('empty_empty', '', '', ['']),
  literalCase('unicode_scalars', '😀e\u0301x', '', ['😀', 'e', '\u0301', 'x']),
  literalCase('unicode_separator', 'x😀e\u0301y😀e\u0301', '😀e\u0301', ['x', 'y', '']),
  literalCase('not_normalized', 'ée\u0301', 'é', ['', 'e\u0301']),
  literalCase('nul_separator', 'a\u0000b\u0000', '\u0000', ['a', 'b', '']),
  literalCase('control_scalars', '\u0000\r\n', '', ['\u0000', '\r', '\n']),
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

// Same real installed Local Host path as the public ROUND/TRUNC boundary tests.
// All state is private to this test. No cap or execution-policy override.
async function fixture(t, {onAdvance, onComputed} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-public-split-'));
  const keys = generateKeyPairSync('ed25519');
  let client, computed;
  let dispatches = 0, advances = 0;
  t.after(async () => {
    await client?.close();
    await rm(directory, {recursive: true, force: true});
  });
  client = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation: {
    directory, retainedRelationOutput: true, authorization: {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1', account_id: 'public-split',
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
          advances++; await onAdvance?.(advances, detail);
        }
      },
    },
  }});
  return {client, dispatches: () => dispatches, advances: () => advances,
    computed: () => computed};
}

async function published(f, source, options, cases, expectedRows) {
  const beforeAdvances = f.advances();
  const run = await f.client.startSource(source, options);
  const state = await run.wait({signal: AbortSignal.timeout(15_000)});
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const expected = expectedRows ?? [Object.fromEntries(cases.map(item =>
    [item.name, item.expected]))];
  assert.deepEqual(await run.result('answer').all(), expected);
  const description = await run.result('answer').describe();
  assert.deepEqual(description.columns,
    cases.map(item => ({name: item.name, contract: item.contract})));
  if (expected.length !== 0) {
    assert.ok(f.advances() > beforeAdvances, 'nonempty execution must make charged Local progress');
  }
  assert.ok(f.computed().outputRepresentations.some(item => item.representation === 'retained-file'));
  const before = f.dispatches();
  assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
  const attached = await f.client.attach(run.ref);
  assert.deepEqual(await attached.result('answer').all(), expected);
  const retained = await attached.result('answer').describe();
  assert.deepEqual(retained.columns, description.columns);
  for (const key of ['programDefinitionCid', 'resultDefinitionCid',
    'resultArtifactCid', 'resultSchemaCid']) assert.equal(retained[key], description[key]);
  assert.equal(f.dispatches(), before, 'resend and retained reread must not redispatch');
  return {run, description};
}

async function refused(f, source, options) {
  await assert.rejects(f.client.startSource(source, options), error => {
    assert.equal(error.code, 'SubmissionNotAccepted');
    const outcome = getSubmissionOutcome(error);
    assert.equal(outcome.kind, 'not_accepted');
    assert.deepEqual(outcome.submissionRef, options.submissionRef);
    assert.equal(outcome.problem.code, 'ClientProgramInvalidInput');
    return true;
  });
}

test('public SPLIT publishes independent literal Unicode and control vectors in SQL Pipe JSON',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    // Keep the installed ten-field Result ceiling unchanged. Both fixed
    // eight-field batches retain every independently authored vector.
    for (const [batch, cases] of [literalCases.slice(0, 8), literalCases.slice(8)].entries()) {
      for (const format of formats) await published(f,
        sourceFor(format, 'split_literals_' + batch, cases),
        {format, submissionRef: f.client.newSubmission({nonce: batch + '-' + format})}, cases);
    }
  });

test('public SPLIT preserves strict NULL and nonnullable String element contracts',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const cases = [
      valueCase('omitted', 'SPLIT(NULL)', split(literal(null)), null, arrayContract(true)),
      valueCase('left_null', "SPLIT(NULL, ':')", split(literal(null), literal(':')), null, arrayContract(true)),
      valueCase('right_null', "SPLIT('a:b', NULL)", split(literal('a:b'), literal(null)), null, arrayContract(true, 'a:b')),
      valueCase('both_null', 'SPLIT(NULL, NULL)', split(literal(null), literal(null)), null, arrayContract(true)),
    ];
    for (const format of formats) await published(f, sourceFor(format, 'split_null', cases),
      {format, submissionRef: f.client.newSubmission({nonce: format})}, cases);
  });

test('public SPLIT admits runtime String delimiters and nullable operand parameters',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const declarations = {s: {type: 'string', nullable: true}, d: {type: 'string', nullable: true}};
    // Both expected columns are literal data, independently of the supplied delimiter.
    const rows = [
      {id: 'double', s: 'red::blue::', d: '::', parts: ['red', 'blue', ''], defaults: ['red::blue::']},
      {id: 'empty', s: '😀e\u0301', d: '', parts: ['😀', 'e', '\u0301'], defaults: ['😀e\u0301']},
      {id: 'comma', s: ',a,,', d: ',', parts: ['', 'a', '', ''], defaults: ['', 'a', '', '']},
      {id: 'null_value', s: null, d: ':', parts: null, defaults: null},
      {id: 'null_delimiter', s: 'a:b', d: null, parts: null, defaults: ['a:b']},
    ];
    for (const row of rows) {
      const cases = [
        valueCase('parts', 'SPLIT(@s, @d)', split({$param: 's'}, {$param: 'd'}), row.parts, arrayContract(true)),
        valueCase('defaults', 'SPLIT(@s)', split({$param: 's'}), row.defaults, arrayContract(true)),
      ];
      for (const format of formats) await published(f,
        sourceFor(format, 'split_parameters', cases, declarations),
        {format, parameters: {s: row.s, d: row.d},
          ...(format === 'json' ? {} : {parameterDeclarations: declarations}),
          submissionRef: f.client.newSubmission({nonce: row.id + '-' + format})}, cases);
    }
  });

test('public SPLIT refuses invalid arity types and named bodies before dispatch',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const invalid = [
      {text: 'SPLIT()', expression: {split: []}},
      {text: "SPLIT('a', ',', 'extra')", expression: {split: [literal('a'), literal(','), literal('extra')]}},
      {text: 'SPLIT(7)', expression: split(literal(7))},
      {text: "SPLIT('a', TRUE)", expression: split(literal('a'), literal(true))},
      {text: 'SPLIT(NULL, 7)', expression: split(literal(null), literal(7))},
    ];
    for (const [i, item] of invalid.entries()) for (const format of formats) {
      await refused(f, sourceFor(format, 'split_refused', [{name: 'value', ...item}]),
        {format, submissionRef: f.client.newSubmission({nonce: i + '-' + format})});
    }
    await refused(f, sourceFor('json', 'split_named_body', [{name: 'value',
      expression: {split: {value: literal('a,b'), delimiter: literal(',')}}}]),
      {format: 'json', submissionRef: f.client.newSubmission({nonce: 'named-body'})});
    assert.equal(f.dispatches(), 0); assert.equal(f.advances(), 0);
  });

test('public SPLIT demands both supplied operands even beside NULL and retains failures',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const failure = {cast: {target: {type: 'string'}, value: {divide: [literal(1), literal(0)]}}};
    const cases = [
      {text: 'SPLIT(NULL, CAST(1 / 0 AS STRING))', expression: split(literal(null), failure)},
      {text: 'SPLIT(CAST(1 / 0 AS STRING), NULL)', expression: split(failure, literal(null))},
    ];
    for (const [i, item] of cases.entries()) for (const format of formats) {
      const source = sourceFor(format, 'split_eager_failure', [{name: 'value', ...item}]);
      const options = {format, submissionRef: f.client.newSubmission({nonce: i + '-' + format})};
      const run = await f.client.startSource(source, options);
      const state = await run.wait({signal: AbortSignal.timeout(15_000)});
      assert.equal(state.status, 'failed', JSON.stringify(state));
      assert.equal(state.result_availability.answer.state, 'unavailable');
      await assert.rejects(run.result('answer').all());
      const before = f.dispatches();
      assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
      const attached = await f.client.attach(run.ref);
      assert.equal((await attached.status()).status, 'failed');
      await assert.rejects(attached.result('answer').all());
      assert.equal(f.dispatches(), before);
    }
  });

test('public SPLIT preserves enclosing and operand-local lazy IF demand',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const failure = {cast: {target: {type: 'string'}, value: {divide: [literal(1), literal(0)]}}};
    const cases = [
      valueCase('outer', "IF(FALSE, SPLIT(CAST(1 / 0 AS STRING)), SPLIT('safe'))",
        {if: [literal(false), split(failure), split(literal('safe'))]}, ['safe'], arrayContract()),
      valueCase('input_if', "SPLIT(IF(TRUE, 'x:y', CAST(1 / 0 AS STRING)), ':')",
        split({if: [literal(true), literal('x:y'), failure]}, literal(':')), ['x', 'y'], arrayContract()),
      valueCase('delimiter_if', "SPLIT('x:y', IF(TRUE, ':', CAST(1 / 0 AS STRING)))",
        split(literal('x:y'), {if: [literal(true), literal(':'), failure]}), ['x', 'y'], arrayContract(false, 'x:y')),
    ];
    for (const format of formats) await published(f, sourceFor(format, 'split_lazy', cases),
      {format, submissionRef: f.client.newSubmission({nonce: format})}, cases);
  });

test('public SPLIT retains complete Array contracts for empty relations',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const cases = [literalCase('required', 'a,b', ',', ['a', 'b']),
      valueCase('nullable', "SPLIT('a,b', NULL)", split(literal('a,b'), literal(null)), null, arrayContract(true, 'a,b'))];
    for (const format of formats) await published(f,
      sourceFor(format, 'split_empty_relation', cases, undefined, true),
      {format, submissionRef: f.client.newSubmission({nonce: format})}, cases, []);
  });

test('public SPLIT keeps field and prior-slot runtime delimiter references in ordered derive',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const source = JSON.stringify({version: 'actql/0.1', id: 'split_ordered_fields', stages: [{
      id: 'main', inputs: {}, steps: [
        {values: {schema: {s: {type: 'string', nullable: true}, d: {type: 'string', nullable: true}},
          rows: [{s: 'axbx', d: 'X'}, {s: '😀e\u0301', d: ''}, {s: null, d: ','}, {s: 'abc', d: null}]}, as: 'seed'},
        {from: 'seed', derive: [{d: {lower: {field: 'd'}}},
          {parts: split({field: 's'}, {field: 'd'})}, {echo: {field: 'parts'}}], as: 'derived'},
        {select: ['parts', 'echo'], as: 'out'}], results: {rows: {from: 'out', fields: ['parts', 'echo']}}}],
      results: {answer: {from: {stage: 'main', result: 'rows'}}}});
    const expected = [{parts: ['a', 'b', ''], echo: ['a', 'b', '']},
      {parts: ['😀', 'e', '\u0301'], echo: ['😀', 'e', '\u0301']},
      {parts: null, echo: null}, {parts: null, echo: null}];
    await published(f, source, {format: 'json', submissionRef: f.client.newSubmission({nonce: 'fields'})},
      ['parts', 'echo'].map(name => ({name, contract: arrayContract(true)})), expected);
  });

test('public SPLIT retained delivery identity preserves Array order duplicates and empty parts',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    // Local retained-file execution need not perform a relation snapshot roundtrip.
    // The public DeliveryAttempt receipt binds these exact JSONL payload bytes
    // to the retained Result artifact. Its transport terminator is not payload.
    const vectors = [
      {input: 'z,a,z,', rowArrayWire: '[{"value":["z","a","z",""]}]',
        rowArraySha256: '0300ed03e4712d0aeab90eae5ef4b272198a5ca085e2d76f797af8c2371b2fee', expected: ['z', 'a', 'z', ''],
        wire: '{"value":["z","a","z",""]}\n', bytes: 27,
        sha256: '4dee72c1a78d503fdb517de232322f6aaa49aecb856170e92303e1070584b669',
        counterexamples: [
          {kind: 'reordered', wire: '{"value":["a","z","z",""]}\n',
            sha256: 'b7d7dcf3199ecbc086fc5749af5fb663ece3bbc2b0eab8c7933af1c804f02550'},
          {kind: 'deduplicated', wire: '{"value":["z","a",""]}\n',
            sha256: '27ac7070ad80170d6830b43b42c0da004873b97d84391e241dcd002cbb686eaf'},
          {kind: 'empty_part_removed', wire: '{"value":["z","a","z"]}\n',
            sha256: '4b59a0c21cf78542ee3b52af9a653be2e07df30d1c6194de9611cd26a9a580d4'},
        ]},
      {input: 'a,z,z,', rowArrayWire: '[{"value":["a","z","z",""]}]',
        rowArraySha256: '1dd23c19ba376f50d1f094bee7824fb763837d4f0e87bc777f47ab524d1a147e', expected: ['a', 'z', 'z', ''],
        wire: '{"value":["a","z","z",""]}\n', bytes: 27,
        sha256: 'b7d7dcf3199ecbc086fc5749af5fb663ece3bbc2b0eab8c7933af1c804f02550',
        counterexamples: [
          {kind: 'reordered', wire: '{"value":["z","a","z",""]}\n',
            sha256: '4dee72c1a78d503fdb517de232322f6aaa49aecb856170e92303e1070584b669'},
          {kind: 'deduplicated', wire: '{"value":["a","z",""]}\n',
            sha256: 'b860d2668d7e71cfe2fecfe688d886a761b1d6ed32cbd0a2fd1b4843813f4c92'},
          {kind: 'empty_part_removed', wire: '{"value":["a","z","z"]}\n',
            sha256: '863c990792d6f8cfb619b829a9731089b42f963ef4a6559dc495429246b9fa3f'},
        ]},
    ];
    const hash = wire => createHash('sha256').update(wire).digest('hex');
    assert.notEqual(vectors[0].sha256, vectors[1].sha256);
    for (const [i, item] of vectors.entries()) {
      // Keep the original ordered-row Array preimages as independent authored controls.
      // Only the JSONL digest below is exposed by the public delivery owner.
      assert.equal(hash(item.rowArrayWire), item.rowArraySha256);
      assert.deepEqual(JSON.parse(item.rowArrayWire), [{value:item.expected}]);
      assert.equal(Buffer.byteLength(item.wire), item.bytes);
      assert.equal(hash(item.wire), item.sha256);
      for (const counterexample of item.counterexamples) {
        assert.equal(hash(counterexample.wire), counterexample.sha256);
        assert.notEqual(counterexample.sha256, item.sha256, counterexample.kind);
      }
      const cases = [literalCase('value', item.input, ',', item.expected)];
      const {run, description} = await published(f,
        sourceFor('json', 'split_array_identity', cases),
        {format: 'json', submissionRef: f.client.newSubmission({nonce: 'array-' + i})}, cases);
      async function verifyRetainedDelivery(result) {
        const reader = result.rows();
        const rows = [];
        for await (const row of reader) rows.push(row);
        assert.deepEqual(rows, [{value: item.expected}]);
        assert.equal(reader.state(), 'complete');
        const lookup = await result.deliveryAttempt(reader.attemptId);
        assert.equal(lookup.kind, 'found');
        assert.equal(lookup.record.state, 'succeeded');
        const receipt = lookup.hostReleaseReceipt;
        assert.equal(receipt.result_artifact_cid, description.resultArtifactCid);
        assert.equal(receipt.run_definition_cid, run.ref.runDefinitionCid);
        assert.equal(receipt.result_name, 'answer');
        assert.equal(receipt.serialization_contract_cid, description.serialization.contractCid);
        assert.equal(receipt.delivered_byte_count, item.bytes);
        assert.equal(receipt.delivered_sha256, item.sha256);
        for (const counterexample of item.counterexamples) {
          assert.notEqual(receipt.delivered_sha256, counterexample.sha256, counterexample.kind);
        }
        return {attemptId: reader.attemptId, receipt};
      }
      const before = f.dispatches();
      const first = await verifyRetainedDelivery(run.result('answer'));
      const attached = await f.client.attach(run.ref);
      const retained = await attached.result('answer').describe();
      assert.equal(retained.resultArtifactCid, description.resultArtifactCid);
      assert.equal(retained.resultSchemaCid, description.resultSchemaCid);
      const reread = await verifyRetainedDelivery(attached.result('answer'));
      assert.notEqual(reread.attemptId, first.attemptId);
      assert.equal(reread.receipt.result_artifact_cid, first.receipt.result_artifact_cid);
      assert.equal(reread.receipt.delivered_sha256, first.receipt.delivered_sha256);
      assert.equal(f.dispatches(), before, 'retained delivery identity checks must not redispatch');
    }
  });

test('public SPLIT omitted and explicit default delimiters retain distinct authored identities',
  {timeout: 60_000}, async t => {
    const f = await fixture(t); const descriptions = [];
    for (const [i, delimiter] of [undefined, ','].entries()) {
      const cases = [literalCase('value', 'a,b', delimiter, ['a', 'b'])];
      const result = await published(f, sourceFor('json', 'split_authored_arity', cases),
        {format: 'json', submissionRef: f.client.newSubmission({nonce: 'arity-' + i})}, cases);
      descriptions.push(result.description);
    }
    assert.equal(descriptions[0].resultSchemaCid, descriptions[1].resultSchemaCid);
    assert.notEqual(descriptions[0].programDefinitionCid, descriptions[1].programDefinitionCid,
      'omitted default is not an invented authored comma child');
  });

for (const delimiter of [',', '']) test(
  `public SPLIT ${delimiter === '' ? 'scalar' : 'separator'} mode cancels after charged consumer progress`,
  {timeout: 60_000}, async t => {
    const reached = Promise.withResolvers(), resume = Promise.withResolvers();
    let completions = 0;
    // Release the barrier before the fixture's close hook can wait for cleanup.
    t.after(() => resume.resolve());
    const f = await fixture(t, {
      onComputed() { completions++; reached.reject(new Error('completed before cancellation boundary')); },
      async onAdvance(_count, detail) {
        if (detail.task === 1 && BigInt(detail.progress) > 0n) {
          reached.resolve(detail); await resume.promise;
        }
      },
    });
    const input = 'a'.repeat(128) + ',' + '😀e\u0301'.repeat(32);
    // Retain the inherited 100-row Values ceiling and use a separate consumer
    // task so positive progress belongs to the task containing SPLIT.
    const source = JSON.stringify({version: 'actql/0.1', id: 'split_cancel', stages: [{
      id: 'seed', inputs: {}, steps: [{values: {schema: {s: {type: 'string', nullable: false}},
        rows: Array.from({length: 100}, () => ({s: input}))}, as: 'out'}],
      results: {rows: {from: 'out', fields: ['s']}}}, {
      id: 'main', inputs: {rows: {result: {stage: 'seed', result: 'rows'}}}, steps: [
        {from: 'rows', derive: {value: split({field: 's'}, literal(delimiter))}, as: 'derived'},
        {select: ['value'], as: 'out'}], results: {rows: {from: 'out', fields: ['value']}}}],
      results: {answer: {from: {stage: 'main', result: 'rows'}}}});
    const options = {format: 'json', submissionRef: f.client.newSubmission({nonce: delimiter === '' ? 'scalar' : 'separator'})};
    const run = await f.client.startSource(source, options);
    const barrier = await reached.promise;
    assert.equal(barrier.task, 1);
    assert.ok(BigInt(barrier.work) > 0n); assert.ok(BigInt(barrier.progress) > 0n);
    const before = f.advances();
    try {
      await run.cancel();
      const pending = await run.status();
      assert.equal(pending.control.cancellation_requested, true);
      assert.notEqual(pending.control.physical_stop, 'confirmed');
      assert.notEqual(pending.status, 'cancelled'); assert.equal(completions, 0);
    } finally { resume.resolve(); }
    const stopped = await run.wait({signal: AbortSignal.timeout(15_000)});
    assert.equal(stopped.status, 'cancelled', JSON.stringify(stopped));
    assert.equal(stopped.control.physical_stop, 'confirmed');
    assert.equal(stopped.result_availability.answer.state, 'unavailable');
    await assert.rejects(run.result('answer').all());
    await assert.rejects(run.result('answer').describe());
    assert.equal(completions, 0); assert.equal(f.advances(), before); assert.equal(f.dispatches(), 1);
    assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
    const attached = await f.client.attach(run.ref);
    assert.equal((await attached.status()).status, 'cancelled');
    await assert.rejects(attached.result('answer').all());
    assert.equal(f.dispatches(), 1);
  });
