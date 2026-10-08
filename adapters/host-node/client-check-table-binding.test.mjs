// Adapter visibility tests complement, rather than replace, the real common
// Checker and public Table execution acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {checkReasonSchemaCid, checkOutcomeSchemaCid} from '../../packages/client-wire/index.mjs';
import {installNodeClientCheck} from './client-check.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const table = Object.freeze({name: 'analytics.report',
  targetRef: 'connector://local/main/report', mappingRef: 'mapping://local/report',
  mappingCid: cid('1'), capabilityCid: cid('2'), installationBindingCid: cid('3'),
  action: 'create', expectedTable: null});
const alias = Object.freeze({name: 'records', sourceRef: 'connector://crm/main/r#v',
  schemaContractCid: cid('4'), sourceViewContractCid: cid('5')});

async function check({write = 'dispatch', read = 'dispatch', binding = table,
  failWrite = false, signal, kind = 'text'} = {}) {
  const decisions = [], analyzed = [];
  const authorization = kind => ({async authorize(...args) {
    decisions.push([kind, ...args]);
    if (kind === 'write' && failWrite) throw new Error('UnavailablePrivateWriter');
    return {action: kind === 'write' ? write : read};
  }});
  const respond = args => {
    analyzed.push(args);
    return JSON.stringify({version: 'actql-check-outcome/0.1', outcome: 'failed',
      correlation_ref: args.at(-2), problem: {code: 'check_internal'},
      reason_schema_cid: checkReasonSchemaCid, outcome_schema_cid: checkOutcomeSchemaCid});
  };
  const moon = {
    clientProgramCheckingEnvironmentCid: () => cid('6'),
    clientProgramCheckCompilerIdentity: () => '{}',
    clientProgramCheckContextIdentity: () => '{}',
    clientProgramCheckUnavailable: () => '{}',
    clientProgramCheckSource: (...args) => respond(args),
    clientProgramCheckProgram: (...args) => respond(args),
  };
  const owner = installNodeClientCheck({moon, environment: {},
    contextKey: new Uint8Array(32).fill(7),
    publication: {environmentCid: cid('6'), aliases: [alias], tableWrites: [binding]},
    sourceAccesses: [{authorization: authorization('read'), connection: 'source',
      resource: 'records', sourceRef: alias.sourceRef}],
    tableWriteAccesses: [{authorization: authorization('write'), connection: 'catalog',
      resource: 'report', capabilityCid: binding.capabilityCid}],
  });
  await owner({principalId: 'author', kind, scope: 'bound_input',
    input: kind === 'program' ? {version: 'actql/0.1', stages: [], results: {}}
      : {format: 'sql', text: 'CREATE TABLE analytics.report AS SELECT 1 AS id'},
    parameters: null, signal});
  return {decisions, publication: JSON.parse(analyzed[0][kind === 'program' ? 2 : 3]),
    context: analyzed[0][kind === 'program' ? 4 : 6]};
}

test('Table binding visibility uses its own write scope, never a Source read grant', async () => {
  const shown = await check({read: 'deny'});
  assert.deepEqual(shown.publication, {environmentCid: cid('6'), aliases: [], tableWrites: [table]});
  assert.equal(shown.decisions[1][1], 'preparation');
  assert.deepEqual(shown.decisions[1][2], {connection: 'catalog', resource: 'report', operation: 'write'});
  assert.equal(shown.decisions[1][3].subjectCid, table.capabilityCid);
  const denied = await check({write: 'deny'});
  assert.deepEqual(denied.publication, {environmentCid: cid('6'), aliases: [alias]});
  for (const write of ['waiting', 'failure', 'unsupported']) {
    const hidden = await check({write});
    assert.deepEqual(hidden.publication, denied.publication);
    assert.equal(hidden.context, denied.context);
  }
  const unavailable = await check({failWrite: true});
  assert.deepEqual(unavailable.publication, denied.publication);
  assert.equal(unavailable.context, denied.context);
});

test('check context binds selected operation, generation and physical Capability', async () => {
  const original = await check();
  for (const change of [{capabilityCid: cid('7')}, {installationBindingCid: cid('8')},
    {action: 'replace', expectedTable: {table_uuid: '12345678-1234-1234-1234-123456789abc',
      generation_cid: cid('9')}}]) {
    const changed = await check({binding: {...table, ...change}});
    assert.notEqual(changed.context, original.context);
    assert.deepEqual(changed.publication.tableWrites, [{...table, ...change}]);
  }
  assert.equal((await check()).context, original.context);
});

test('cancelled checks do not conceal cancellation as an inaccessible Table name', async () => {
  const controller = new AbortController();
  controller.abort(new Error('CheckCancelled'));
  await assert.rejects(check({signal: controller.signal}), /CheckCancelled/);
});

test('structured checking keeps its input binding and independent Table write disclosure', async () => {
  const shown = await check({kind: 'program', read: 'deny'});
  assert.deepEqual(shown.publication, {environmentCid: cid('6'), aliases: [], tableWrites: [table]});
  assert.notEqual(shown.context, (await check({read: 'deny'})).context);
  assert.equal(shown.context, (await check({kind: 'program', read: 'deny'})).context);
  const hidden = await check({kind: 'program', write: 'deny'});
  assert.deepEqual(hidden.publication, {environmentCid: cid('6'), aliases: [alias]});
  assert.notEqual(hidden.context, shown.context);
});
