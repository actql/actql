// Independently rebuilt diagnostic; no exact old-source identity is claimed.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Independent GoogleSQL STRING LEFT/RIGHT/LPAD/RPAD vectors, not live BigQuery.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#left
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#right
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#lpad
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#rpad
// SQL text, common-expression operands, exact outputs and result contracts are
// authored independently. No compiler output or runtime result is an oracle.
// The admitted STRING domain counts Unicode scalars. BYTES and collation are
// excluded; finite binary64 length values must be safe nonnegative integers.
const literal = value => ({literal: value});
const formats = ['sql', 'aql-text', 'json'];
const string = (name, text, expression, expected, nullable = false, input) =>
  ({name, text, expression, expected, contract: {type: 'string', nullable,
    ...(typeof input === 'string' ? {max_utf8_bytes: Buffer.byteLength(input)} : {})}});
const call = (name, text, tag, args, expected, nullable = false) =>
  string(name, text, {[tag]: args.map(literal)}, expected, nullable,
    tag === 'left' || tag === 'right' ? args[0] : undefined);

const batches = [
  {id: 'sides', cases: [
    call('left_documented', "LEFT('banana',3)", 'left', ['banana',3], 'ban'),
    call('right_documented', "RIGHT('apple',3)", 'right', ['apple',3], 'ple'),
    call('left_zero', "LEFT('abc',0)", 'left', ['abc',0], ''),
    call('right_zero', "RIGHT('abc',0)", 'right', ['abc',0], ''),
    call('left_oversize', "LEFT('abc',9007199254740991)", 'left', ['abc',9007199254740991], 'abc'),
    call('right_oversize', "RIGHT('abc',9007199254740991)", 'right', ['abc',9007199254740991], 'abc'),
    call('left_empty', "LEFT('',1)", 'left', ['',1], ''),
    call('right_empty', "RIGHT('',1)", 'right', ['',1], ''),
  ]},
  {id: 'padding', cases: [
    call('left_default', "LPAD('c',5)", 'lpad', ['c',5], '    c'),
    call('right_default', "RPAD('c',5)", 'rpad', ['c',5], 'c    '),
    call('left_repeat', "LPAD('abc',10,'ghd')", 'lpad', ['abc',10,'ghd'], 'ghdghdgabc'),
    call('right_repeat', "RPAD('abc',10,'ghd')", 'rpad', ['abc',10,'ghd'], 'abcghdghdg'),
    call('left_truncate', "LPAD('abc',2,'d')", 'lpad', ['abc',2,'d'], 'ab'),
    call('right_truncate', "RPAD('abc',2,'d')", 'rpad', ['abc',2,'d'], 'ab'),
    call('left_zero', "LPAD('abc',0)", 'lpad', ['abc',0], ''),
    call('right_zero', "RPAD('abc',0)", 'rpad', ['abc',0], ''),
  ]},
  {id: 'unicode_scalars', cases: [
    call('left_scalars', "LEFT('😀e\\u0301x',2)", 'left', ['😀e\u0301x',2], '😀e'),
    call('right_scalars', "RIGHT('😀e\\u0301x',2)", 'right', ['😀e\u0301x',2], '\u0301x'),
    call('left_pattern', "LPAD('X',6,'😀e\\u0301')", 'lpad', ['X',6,'😀e\u0301'], '😀e\u0301😀eX'),
    call('right_pattern', "RPAD('X',6,'😀e\\u0301')", 'rpad', ['X',6,'😀e\u0301'], 'X😀e\u0301😀e'),
    call('left_nul', "LPAD('x',4,'\\u0000b')", 'lpad', ['x',4,'\u0000b'], '\u0000b\u0000x'),
    call('right_nul', "RPAD('x',4,'\\u0000b')", 'rpad', ['x',4,'\u0000b'], 'x\u0000b\u0000'),
    call('left_crlf', "LEFT('a\\u000D\\u000Ab',2)", 'left', ['a\r\nb',2], 'a\r'),
    call('right_crlf', "RIGHT('a\\u000D\\u000Ab',2)", 'right', ['a\r\nb',2], '\nb'),
  ]},
  {id: 'null_and_spelling', cases: [
    call('left_null', 'LEFT(NULL,-1)', 'left', [null,-1], null, true),
    call('right_null', "RIGHT('abc',NULL)", 'right', ['abc',null], null, true),
    call('lpad_null', "LPAD(NULL,-1,'')", 'lpad', [null,-1,''], null, true),
    call('rpad_null', "RPAD('abc',-1,NULL)", 'rpad', ['abc',-1,null], null, true),
    call('null_length', "LPAD('abc',NULL,'')", 'lpad', ['abc',null,''], null, true),
    call('quoted_left', "\x60LeFt\x60('abc',2)", 'left', ['abc',2], 'ab'),
    call('mixed_right', "rIgHt('abc',2)", 'right', ['abc',2], 'bc'),
    call('quoted_pad', "\x60rPaD\x60('',3,'ab')", 'rpad', ['',3,'ab'], 'aba'),
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
  const directory = await mkdtemp(join(tmpdir(), 'actql-pad_sides-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'pad_sides',
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

test('public SQL, Pipe, and independent JSON publish exact padding and side slices',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    for (const batch of batches) {
      for (const format of formats) {
        await assertPublished(f, sourceFor(format, 'pad_sides_' + batch.id, batch.cases),
          {format, submissionRef: f.client.newSubmission({nonce: batch.id + '-' + format})},
          batch.cases);
      }
    }
  });

test('public padding and side contracts include nullable parameters and empty relations',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {
      p: {type: 'string', nullable: true}, q: {type: 'string', nullable: false},
      n: {type: 'number', nullable: true}, m: {type: 'number', nullable: false},
      r: {type: 'string', nullable: true},
    };
    for (const [id, parameters, nullableSide, nullablePad, empty] of [
      ['value', {p: 'ab', q: 'ab', n: 2, m: 5, r: 'xy'}, 'ab', 'xyxab', false],
      ['null', {p: null, q: 'ab', n: null, m: 5, r: null}, null, null, false],
      ['empty', {p: null, q: 'ab', n: null, m: 5, r: null}, null, null, true],
    ]) {
      const cases = [
        string('nullable_value', 'LEFT(@p,2)', {left:[{$param:'p'},literal(2)]}, nullableSide, true),
        string('nullable_length', 'RIGHT(@q,@n)', {right:[{$param:'q'},{$param:'n'}]}, nullableSide, true),
        string('nullable_pattern', 'LPAD(@q,@m,@r)', {lpad:[{$param:'q'},{$param:'m'},{$param:'r'}]}, nullablePad, true),
        string('nonnull', "RPAD(@q,@m,'x')", {rpad:[{$param:'q'},{$param:'m'},literal('x')]}, 'abxxx'),
        string('omitted_pattern', 'LPAD(@q,@m)', {lpad:[{$param:'q'},{$param:'m'}]}, '   ab'),
      ];
      for (const format of formats) {
        await assertPublished(f, sourceFor(format, 'pad_sides_parameters', cases, parameterDeclarations, empty),
          {format, parameters, ...(format !== 'json' ? {parameterDeclarations} : {}),
            submissionRef: f.client.newSubmission({nonce: id + '-' + format})}, cases, empty);
      }
    }
  });

test('public ordered padding uses dynamic patterns and shadowed prior slots',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const cases = [
      {name:'saved', expected:'ab', contract:{type:'string',nullable:false}},
      {name:'payload', expected:'b', contract:{type:'string',nullable:false}},
      {name:'value', expected:'xyzxb', contract:{type:'string',nullable:false}},
      {name:'nested', expected:'zab', contract:{type:'string',nullable:false}},
    ];
    const fields = cases.map(item => item.name);
    const source = JSON.stringify({version:'actql/0.1',id:'pad_sides_ordered_fields',stages:[{
      id:'main',inputs:{},steps:[
        {values:{schema:{payload:{type:'string',nullable:false},length:{type:'number',nullable:false},
          pattern:{type:'string',nullable:false}},rows:[{payload:'abcd',length:2,pattern:'xy'}]},as:'seed'},
        {from:'seed',derive:[
          {saved:{left:[{field:'payload'},{field:'length'}]}},
          {payload:{right:[{field:'saved'},literal(1)]}},
          {length:{add:[{field:'length'},literal(3)]}},
          {pattern:{rpad:[{field:'pattern'},literal(3),literal('z')]}},
          {value:{lpad:[{field:'payload'},{field:'length'},{field:'pattern'}]}},
          {nested:{right:[{lpad:[{field:'saved'},{field:'length'},{field:'pattern'}]},literal(3)]}},
        ],as:'derived'},
        {select:fields,as:'out'},
      ],results:{rows:{from:'out',fields}},
    }],results:{answer:{from:{stage:'main',result:'rows'}}}});
    await assertPublished(f, source, {format:'json',
      submissionRef:f.client.newSubmission({nonce:'ordered-fields'})}, cases);
  });

test('public padding and side calls reject wrong arity types and excluded overloads before dispatch',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    for (const tag of ['left','right','lpad','rpad']) {
      const name = tag.toUpperCase();
      const arity = [name + '()', name + "('abc')", name + "('abc',1,'x','y')",
        ...(tag.endsWith('pad') ? [] : [name + "('abc',1,'x')"])];
      for (const [index, text] of [...arity, name + "(b'abc',1)",
        name + "(COLLATE('abc','und:ci'),1)"].entries()) {
        for (const format of ['sql','aql-text']) {
          await assertRefused(f, sourceFor(format,'pad_sides_invalid_text',[{name:'value',text}]),
            {format,submissionRef:f.client.newSubmission({nonce:tag+'-arity-'+index+'-'+format})},
            text.includes('COLLATE') ? 'ClientProgramImplementationLimit' : 'ClientProgramInvalidInput');
        }
      }
      const badTypes = [
        {text:name+'(1,2)',expression:{[tag]:[literal(1),literal(2)]}},
        {text:name+"('abc','2')",expression:{[tag]:[literal('abc'),literal('2')]}},
        {text:name+'(NULL,TRUE)',expression:{[tag]:[literal(null),literal(true)]}},
        ...(tag.endsWith('pad') ?
          [{text:name+"('abc',2,1)",expression:{[tag]:[literal('abc'),literal(2),literal(1)]}}] : []),
      ];
      for (const [index,item] of badTypes.entries()) {
        for (const format of formats) {
          await assertRefused(f,sourceFor(format,'pad_sides_invalid_type',[{name:'value',...item}]),
            {format,submissionRef:f.client.newSubmission({nonce:tag+'-type-'+index+'-'+format})});
        }
      }
    }
    assert.equal(f.dispatches(),0);
    assert.equal(f.advances(),0);
  });

test('public JSON padding keeps closed ordered arguments and rejects invalid parameter bindings',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const invalid = [
      {left:[]},{right:[literal('abc')]},{left:[literal('abc'),literal(2),literal('x')]},
      {lpad:[literal('abc'),literal(2),literal('x'),literal('y')]},
      {rpad:{value:literal('abc'),length:literal(2)}},
      {LPAD:[literal('abc'),literal(2)]},{lpad:[literal('abc'),literal(2)],extra:false},
      {rpad:[literal('abc'),literal(2),null]},
    ];
    for (const [index,expression] of invalid.entries()) {
      await assertRefused(f,sourceFor('json','pad_sides_invalid_json',[{name:'value',expression}]),
        {format:'json',submissionRef:f.client.newSubmission({nonce:'json-'+index})});
    }
    const parameterDeclarations = {p:{type:'string',nullable:false},
      n:{type:'number',nullable:false},r:{type:'string',nullable:false}};
    const cases = [{name:'value',text:'LPAD(@p,@n,@r)',
      expression:{lpad:[{$param:'p'},{$param:'n'},{$param:'r'}]}}];
    for (const [index,parameters] of [
      {p:1,n:4,r:'x'},{p:null,n:4,r:'x'},{p:'ab',n:'4',r:'x'},
      {p:'ab',n:null,r:'x'},{p:'ab',n:4,r:true},{p:'ab',n:4,r:null},
    ].entries()) {
      for (const format of formats) {
        await assertRefused(f,sourceFor(format,'pad_sides_invalid_binding',cases,parameterDeclarations),
          {format,parameters,...(format!=='json'?{parameterDeclarations}:{}),
            submissionRef:f.client.newSubmission({nonce:'binding-'+index+'-'+format})});
      }
    }
    assert.equal(f.dispatches(),0);
    assert.equal(f.advances(),0);
  });

test('public padding and side domain errors fail during demanded execution',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    for (const tag of ['left','right','lpad','rpad']) {
      const name = tag.toUpperCase();
      const cases = [
        {name:'negative',text:name+"('abc',-1)",expression:{[tag]:[literal('abc'),literal(-1)]}},
        {name:'fraction',text:name+"('abc',0.5)",expression:{[tag]:[literal('abc'),literal(0.5)]}},
        {name:'unsafe',text:name+"('abc',9007199254740991+1)",
          expression:{[tag]:[literal('abc'),{add:[literal(9007199254740991),literal(1)]}]}},
        {name:'empty_negative',text:name+"('',-1)",expression:{[tag]:[literal(''),literal(-1)]}},
        ...(tag.endsWith('pad') ? [0,2,3,4].map(length => ({
          name:'empty_pattern_'+length,text:name+"('abc',"+length+",'')",
          expression:{[tag]:[literal('abc'),literal(length),literal('')]},
        })) : []),
      ];
      for (const item of cases) {
        for (const format of formats) {
          await assertFailed(f,sourceFor(format,'pad_sides_bad_'+tag+'_'+item.name,[item]),
            {format,submissionRef:f.client.newSubmission({nonce:tag+'-'+item.name+'-'+format})});
        }
      }
    }
  });

test('public padding eagerly demands children beside NULL and zero lengths',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    // Ordinary functions demand all supplied arguments before NULL propagation.
    // https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions
    const failNumber = {divide:[literal(1),literal(0)]};
    const failString = {if:[{eq:[failNumber,literal(0)]},literal('x'),literal('y')]};
    const cases = [
      {name:'left_null',text:'LEFT(NULL,1/0)',expression:{left:[literal(null),failNumber]}},
      {name:'right_null',text:'RIGHT(NULL,1/0)',expression:{right:[literal(null),failNumber]}},
      {name:'left_zero',text:"LEFT(IF(1/0=0,'x','y'),0)",expression:{left:[failString,literal(0)]}},
      {name:'right_zero',text:"RIGHT(IF(1/0=0,'x','y'),0)",expression:{right:[failString,literal(0)]}},
      {name:'lpad_pattern',text:"LPAD(NULL,-1,IF(1/0=0,'x','y'))",
        expression:{lpad:[literal(null),literal(-1),failString]}},
      {name:'rpad_pattern',text:"RPAD('abc',0,IF(1/0=0,'x','y'))",
        expression:{rpad:[literal('abc'),literal(0),failString]}},
      {name:'lpad_length',text:'LPAD(NULL,1/0,NULL)',
        expression:{lpad:[literal(null),failNumber,literal(null)]}},
      {name:'rpad_value',text:"RPAD(IF(1/0=0,'x','y'),NULL,NULL)",
        expression:{rpad:[failString,literal(null),literal(null)]}},
    ];
    for (const item of cases) {
      for (const format of formats) {
        await assertFailed(f,sourceFor(format,'pad_sides_demanded_'+item.name,[item]),
          {format,submissionRef:f.client.newSubmission({nonce:item.name+'-'+format})});
      }
    }
  });

test('public padding and side slices preserve lazy branches outside and within calls',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {p:{type:'string',nullable:false}};
    const p = {$param:'p'};
    const failNumber = {divide:[literal(1),literal(0)]};
    const failString = {if:[{eq:[failNumber,literal(0)]},p,p]};
    const cases = [
      string('skip_left','IF(FALSE,LEFT(@p,-1),@p)',
        {if:[literal(false),{left:[p,literal(-1)]},p]},'a😀b'),
      string('skip_right','IF(TRUE,@p,RIGHT(@p,1/0))',
        {if:[literal(true),p,{right:[p,failNumber]}]},'a😀b'),
      string('skip_pad',"IF(FALSE,LPAD(@p,1,''),@p)",
        {if:[literal(false),{lpad:[p,literal(1),literal('')]},p]},'a😀b'),
      string('value_branch',"LEFT(IF(TRUE,@p,IF(1/0=0,@p,@p)),2)",
        {left:[{if:[literal(true),p,failString]},literal(2)]},'a😀'),
      string('length_branch','RIGHT(@p,IF(TRUE,2,1/0))',
        {right:[p,{if:[literal(true),literal(2),failNumber]}]},'😀b'),
      string('pattern_branch',"RPAD(@p,IF(TRUE,5,1/0),IF(TRUE,'x',IF(1/0=0,@p,@p)))",
        {rpad:[p,{if:[literal(true),literal(5),failNumber]},
          {if:[literal(true),literal('x'),failString]}]},'a😀bxx'),
    ];
    for (const format of formats) {
      await assertPublished(f,sourceFor(format,'pad_sides_lazy',cases,parameterDeclarations),
        {format,parameters:{p:'a😀b'},...(format!=='json'?{parameterDeclarations}:{}),
          submissionRef:f.client.newSubmission({nonce:'lazy-'+format})},cases);
    }
  });

test('public pad_sides cancellation stops after charged progress without publishing a result',
  {timeout: 60_000}, async t => {
    const reached = Promise.withResolvers();
    const resume = Promise.withResolvers();
    let completions = 0;
    t.after(() => resume.resolve());
    const f = await fixture(t, {
      onComputed() {
        completions++;
        reached.reject(new Error('LPAD completed before the charged progress barrier'));
      },
      async onAdvance(count) {
        if (count === 10) {
          reached.resolve();
          await resume.promise;
        }
      },
    });
    // Preserve the established 4096-byte Values cell boundary. A field operand
    // exercises bounded input scanning and repeated-pattern output sizing.
    const payload = '😀'.repeat(1023) + 'a\u0000\r\n';
    assert.equal(Buffer.byteLength(payload), 4096);
    const source = JSON.stringify({version: 'actql/0.1', id: 'pad_sides_cancel', stages: [{
      id: 'main', inputs: {}, steps: [
        {values: {schema: {payload: {type: 'string', nullable: false}},
          rows: [{payload}]}, as: 'seed'},
        {from: 'seed', derive: {value: {lpad: [{field: 'payload'}, literal(8192), literal('😀x')]}}, as: 'derived'},
        {select: ['value'], as: 'out'},
      ], results: {rows: {from: 'out', fields: ['value']}},
    }], results: {answer: {from: {stage: 'main', result: 'rows'}}}});
    const options = {format: 'json',
      submissionRef: f.client.newSubmission({nonce: 'pad_sides-cancel'})};
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
