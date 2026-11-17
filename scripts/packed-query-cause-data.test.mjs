import assert from 'node:assert/strict';
import test from 'node:test';
import {collectPackedFailureData} from './fixtures/packed-query-transport-owner.mjs';

test('packed failure DATA collector bounds breadth, depth and cycles', () => {
  const wide = {}, queue = [wide];
  for (let index = 0; index < 40; index++) {
    const parent = queue[index];
    for (const key of ['_0', '_1', '_2']) queue.push(parent[key] = {});
  }
  assert.equal(collectPackedFailureData(wide).originalCauseTypes[0].length, 32);
  const deep = {}; let tail = deep;
  for (let index = 0; index < 24; index++) tail = tail.cause = {};
  assert.equal(collectPackedFailureData(deep).originalCauseTypes[0].length, 17);
  const cycle = {}; cycle.cause = cycle;
  assert.deepEqual(collectPackedFailureData(cycle).originalCauseTypes,
    [[{edge: 'original', type: 'Object'}]]);
});

test('packed failure DATA collector has independent reentrant observations and never grants a new code', () => {
  let nested;
  const original = Object.assign(new Error('private-original'), {code: 'EIO'});
  const proxy = new Proxy(original, {getOwnPropertyDescriptor(target, key) {
    if (key === 'code') nested = collectPackedFailureData({code: 'ClientPrivateNewFactory'});
    return Reflect.getOwnPropertyDescriptor(target, key);
  }});
  assert.deepEqual(collectPackedFailureData(proxy).originalCauseTypes,
    [[{edge: 'original', type: 'Error', code: 'EIO'}]]);
  assert.deepEqual(nested.originalCauseTypes,
    [[{edge: 'original', type: 'Object', codeOmitted: true, codeType: 'String'}]]);
  assert.doesNotMatch(JSON.stringify(nested), /ClientPrivateNewFactory/u);
});

test('packed failure DATA collector captures bounded original DATA without getters or enumeration', async t => {
  const reports = [];
  const original = Object.assign(new TypeError('private-message-never-reported'), {
    code: 'ClientProgramUnsupported', requestId: 'private-request-never-reported',
    cause: Object.assign(new Error('private-inner-never-reported'), {code:'ForeignRequestOriginal'}),
  });
  let reads = 0, enumerations = 0;
  Object.defineProperty(original, '_0', {get() {reads++; throw new Error('accessor invoked');}});
  Object.defineProperty(original, 'unrelatedPrivateField', {get() {reads++; throw new Error('private field read');}});
  const reflected = [];
  const primary = new Proxy(original, {
    ownKeys() {enumerations++; throw new Error('private fields enumerated');},
    getOwnPropertyDescriptor(target, key) {
      reflected.push(key);
      assert.ok(['code','cause','primaryFailure','_0','_1','_2'].includes(key));
      return Reflect.getOwnPropertyDescriptor(target, key);
    },
  });
  original.cause.primaryFailure = primary;
  reports.push(collectPackedFailureData(primary));
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes[0], [
    {edge:'original',type:'TypeError',code:'ClientProgramUnsupported'},
    {edge:'cause',type:'Error',code:'ForeignRequestOriginal'},
    {edge:'_0',type:'Accessor'},
  ]);
  assert.equal(reads, 0);
  assert.equal(enumerations, 0);
  assert.ok(reflected.length > 0);
  assert.ok(!reflected.includes('stack') && !reflected.includes('unrelatedPrivateField'));
  assert.doesNotMatch(JSON.stringify(reports), /private-|requestId|message|stack/u);
});

test('packed failure DATA collector inspection failure returns unavailable DATA', async t => {
  const reports = [];
  const primary = new Proxy(new Error('original'), {
    getOwnPropertyDescriptor() {throw new Error('descriptor inspection unavailable');},
  });
  reports.push(collectPackedFailureData(primary));
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, false);
});

test('packed failure DATA collector never sends a private inspection exception to Inspector formatting', async t => {
  const reports = [];
  let reads = 0;
  const privateFailure = new Error('private-inspection-failure');
  for (const name of ['stack', 'message', 'name']) Object.defineProperty(privateFailure, name,
    {get() {reads++;throw new Error('private-inspection-getter');}});
  const primary = new Proxy(new Error('original'), {
    getOwnPropertyDescriptor() {throw privateFailure;},
  });
  reports.push(collectPackedFailureData(primary));
  assert.equal(reads, 0, 'Reflection failure must stay inside the bounded inspection expression');
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, false);
  assert.deepEqual(reports[0].originalCauseTypes, []);
  assert.doesNotMatch(JSON.stringify(reports), /private-|message|stack/u);
});

test('packed failure DATA collector discards partial DATA when nested reflection fails', async t => {
  const reports = [];
  let reads = 0;
  const privateFailure = new Error('private-nested-inspection-failure');
  Object.defineProperty(privateFailure, 'stack', {get() {reads++;throw new Error('private-getter');}});
  const primary = Object.assign(new Error('original'), {code:'ClientProgramUnsupported',
    cause:new Proxy({}, {getOwnPropertyDescriptor() {throw privateFailure;}})});
  reports.push(collectPackedFailureData(primary));
  assert.equal(reads, 0);
  assert.equal(reports[0].available, false);
  assert.deepEqual(reports[0].originalCauseTypes, [], 'The earlier original row is not a complete observation');
  assert.doesNotMatch(JSON.stringify(reports), /private-|ClientProgramUnsupported|message|stack/u);
});

test('packed failure DATA collector retains a closed Node failure code without collecting its message', async t => {
  const reports = [];
  const primary = Object.assign(new Error('private-SQL-never-reported'), {code:'ERR_SQLITE_ERROR'});
  reports.push(collectPackedFailureData(primary));
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[{edge:'original',type:'Error',code:'ERR_SQLITE_ERROR'}]]);
  assert.doesNotMatch(JSON.stringify(reports), /private-SQL/u);
});

test('packed failure DATA collector omits a plausible private code and forged MoonBit constructor name', async t => {
  const reports = [];
  class _MPrivateInputSecret extends Error {}
  const primary = Object.assign(new _MPrivateInputSecret('private-message'), {code:'ClientPrivateInputSecret'});
  reports.push(collectPackedFailureData(primary));
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[{edge:'original',type:'MoonBit',codeOmitted:true,codeType:'String'}]]);
  assert.doesNotMatch(JSON.stringify(reports), /PrivateInputSecret|private-message/u);
});

test('packed failure DATA collector retains exact factory codes and primitive edge types without their values', async t => {
  const reports = [];
  const primary = Object.assign(new Error('private-factory-message'), {
    code:'MoonBitHostFailure', cause:9234567, _0:undefined, _1:null,
    _2:{code:'NodeManagedRunAdmissionUnavailable', cause:'private-primitive-string', primaryFailure:()=> 'private-function',
      _0:true, _1:9234568n, _2:Symbol('private-symbol')},
  });
  reports.push(collectPackedFailureData(primary));
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[
    {edge:'original',type:'Error',code:'MoonBitHostFailure'},
    {edge:'cause',type:'Number'}, {edge:'_0',type:'Undefined'}, {edge:'_1',type:'Null'},
    {edge:'_2',type:'Object',code:'NodeManagedRunAdmissionUnavailable'}, {edge:'cause',type:'String'},
    {edge:'primaryFailure',type:'Function'}, {edge:'_0',type:'Boolean'},
    {edge:'_1',type:'BigInt'}, {edge:'_2',type:'Symbol'},
  ]]);
  assert.doesNotMatch(JSON.stringify(reports), /9234567|9234568|private-/u);
});

test('packed failure DATA collector retains reviewed Local preparation factory codes with an undefined cause', async t => {
  const codes = ['RunHostCompilationRejected', 'RunHostTaskCompilationRejected',
    'RunHostAdmissionRejected', 'RunHostStaticPlanRejected', 'RunHostOriginalPlanRejected'];
  const reports = [];
  const error = code => Object.assign(new Error('private-factory-message'), {code, cause:undefined});
  const original = error(codes[0]);
  original.primaryFailure = error(codes[1]); original._0 = error(codes[2]);
  original._1 = error(codes[3]); original._2 = error(codes[4]);
  original._2.cause = error('RunHostPrivateInputSecret');
  reports.push(collectPackedFailureData(original));
  assert.equal(reports[0].available, true);
  const rows = reports[0].originalCauseTypes.flat();
  assert.deepEqual(rows.flatMap(row => row.code === undefined ? [] : [row.code]).sort(), [...codes].sort());
  assert.equal(rows.filter(row => row.type === 'Undefined').length, 5);
  assert(rows.some(row => row.type === 'Error' && row.codeOmitted === true));
  assert.doesNotMatch(JSON.stringify(reports), /PrivateInputSecret|private-factory-message|message|stack/u);
});

test('packed failure DATA collector retains closed compiled-Run submission factory codes', async t => {
  const codes = [
    'RunHostResultPolicyRejected', 'RunHostResultSelectionRejected',
    'RunHostTaskDefinitionRejected', 'RunHostSourceFreeDefinitionRejected',
    'RunHostSourceFreeAdmissionRejected', 'RunHostTaskInvocationRejected', 'RunHostInvocationRejected',
  ];
  const reports = [];
  const errors = codes.map(code => Object.assign(new Error('private-submit-boundary'),
    {code, cause:undefined}));
  for (let index = 1; index < errors.length; index++) errors[index - 1].primaryFailure = errors[index];
  let reads = 0;
  Object.defineProperty(errors.at(-1), '_0', {get() {reads++;throw new Error('private-getter');}});
  errors.at(-1)._1 = {code:'RunHostPrivateInputSecret'};
  reports.push(collectPackedFailureData(errors[0]));
  assert.equal(reads, 0);
  assert.equal(reports[0].available, true);
  const rows = reports[0].originalCauseTypes.flat();
  assert.deepEqual(rows.flatMap(row => row.code === undefined ? [] : [row.code]), codes);
  assert.equal(rows.filter(row => row.type === 'Undefined').length, codes.length);
  assert(rows.some(row => row.type === 'Accessor'));
  assert(rows.some(row => row.codeOmitted === true && row.codeType === 'String'));
  assert.doesNotMatch(JSON.stringify(reports), /PrivateInputSecret|private-|message|stack/u);
});

test('packed failure DATA collector classifies omitted code descriptors without getters or values', async t => {
  const reports = [];
  let reads = 0;
  const original = Object.assign(new Error('private-code-description'), {
    code:undefined, _0:{code:'PrivateCodeSecret'}, _1:{code:9234567}, _2:{code:{}},
    cause:Object.defineProperty({}, 'code', {get() {reads++;throw new Error('private-getter');}}),
  });
  reports.push(collectPackedFailureData(original));
  assert.equal(reads, 0);
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[
    {edge:'original',type:'Error',codeOmitted:true,codeType:'Undefined'},
    {edge:'cause',type:'Object',codeOmitted:true,codeType:'Accessor'},
    {edge:'_0',type:'Object',codeOmitted:true,codeType:'String'},
    {edge:'_1',type:'Object',codeOmitted:true,codeType:'Number'},
    {edge:'_2',type:'Object',codeOmitted:true,codeType:'Other'},
  ]]);
  assert.doesNotMatch(JSON.stringify(reports), /PrivateCodeSecret|9234567|private-|message|stack/u);
});

