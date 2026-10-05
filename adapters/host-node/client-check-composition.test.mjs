// Adapter-only checks: the common checker is a recording seam, not a second
// checker. Public Local/HTTP verdict expectations live in client-check.test.
import assert from 'node:assert/strict';
import test from 'node:test';
import {checkReasonSchemaCid} from '../../packages/client-wire/index.mjs';
import {installNodeClientCheck} from './client-check.mjs';

const environment = Object.freeze({});
const environmentCid = `sha256:${'1'.repeat(64)}`;
const aliases = ['A', 'B'].map(name => Object.freeze({name,
  sourceRef: `connector://fixture/${name}/r#v`,
  sourceViewContractCid: `sha256:${'2'.repeat(64)}`,
  schemaContractCid: `sha256:${'3'.repeat(64)}`}));
const request = (principalId = 'owner', text = 'SELECT 1 AS n') => ({
  principalId, input: {text, format: 'sql'}, parameters: null});

function fixture(states = [], publication = aliases) {
  const calls = [], checked = [];
  const moon = {
    clientProgramCheckingEnvironmentCid: value => {
      assert.equal(value, environment); return environmentCid;
    },
    clientProgramCheckCompilerIdentity: () => '{"compiler":"fixture"}',
    clientProgramCheckContextIdentity: value => {
      assert.equal(value, environment);
      return '{"host_policy_profile":{},"model_task_contract_cids":[],"profiles":{}}';
    },
    clientProgramCheckUnavailable: correlation_ref => JSON.stringify({
      version: 'actql-check-outcome/0.1', reason_schema_cid: checkReasonSchemaCid, outcome: 'unavailable',
      problem: {code: 'check_unavailable'}, correlation_ref}),
    clientProgramCheckSource: (...args) => {
      checked.push(args);
      return JSON.stringify({version: 'actql-check-outcome/0.1', reason_schema_cid: checkReasonSchemaCid,
        outcome: 'completed', report: {context_ref: args[6], inputs: [{document_id: 'source', revision: args[7], kind: 'text', byte_length: Buffer.byteLength(args[0])}],
          requirements: [], scope: {kind: 'bound_input'}, verdict: 'verified', reasons: [],
          coverage: {limits: [], unresolved: []}}});
    },
  };
  const sourceAccesses = states.map(state => ({
    sourceRef: (publication[state.index] ?? aliases[state.index]).sourceRef,
    connection: `connection-${state.index}`, resource: state.noReadTuple ? undefined : `resource-${state.index}`,
    authorization: {authorize: async (boundary, tuple, options) => {
      calls.push(state.index);
      assert.equal(boundary, 'acquisition');
      assert.deepEqual(tuple, {connection: `connection-${state.index}`,
        resource: state.noReadTuple ? undefined : `resource-${state.index}`, operation: 'read'});
      assert.equal(options.subjectCid, environmentCid);
      if (state.action === 'throw') throw new Error('private owner failure');
      return {action: state.action};
    }},
  }));
  const check = installNodeClientCheck({moon, environment, sourceAccesses,
    publication: {environmentCid, aliases: publication},
    contextKey: new Uint8Array(32).fill(7)});
  return {check, calls, checked, visible: () =>
    JSON.parse(checked.at(-1)[3]).aliases};
}

test('composition: zero, one and two owners check source-free input once', async () => {
  for (const states of [[], [{index: 0, action: 'dispatch'}],
    [{index: 0, action: 'dispatch'}, {index: 1, action: 'dispatch'}]]) {
    const f = fixture(states);
    assert.equal((await f.check(request())).outcome, 'completed');
    assert.deepEqual(f.calls, states.map(state => state.index));
    assert.equal(f.checked.length, 1);
    assert.deepEqual(f.visible(), states.map(state => aliases[state.index]));
  }
});

test('composition: each source uses its own decision in either order', async () => {
  for (const action of ['deny', 'held', 'failed', undefined, 'throw']) {
    for (const reverse of [false, true]) {
      const states = [{index: 0, action: 'dispatch'}, {index: 1, action}];
      if (reverse) states.reverse();
      const f = fixture(states);
      const outcome = await f.check(request('owner', 'SELECT id FROM A'));
      assert.equal(outcome.outcome, 'completed');
      assert.deepEqual(f.visible(), [aliases[0]]);
      assert.deepEqual(f.calls, states.map(state => state.index));
      const absent = fixture(states, [aliases[0]]);
      assert.deepEqual(outcome, await absent.check(request('owner', 'SELECT id FROM A')));
    }
  }
});

test('composition: every declared view uses its own read decision', async () => {
  const third = {...aliases[0], name: 'C',
    sourceRef: 'connector://fixture/C/r#v'};
  const publication = [...aliases, third];
  const f = fixture([{index: 0, action: 'dispatch'},
    {index: 1, action: 'deny'}, {index: 2, action: 'dispatch'}], publication);
  assert.equal((await f.check(request())).outcome, 'completed');
  assert.deepEqual(f.calls, [0, 1, 2]);
  assert.deepEqual(f.visible(), [aliases[0], third]);
});

test('composition: unusable read owners hide only their own names', async () => {
  for (const states of [[{index: 0, action: 'throw'}],
    [{index: 0, action: 'throw'}, {index: 1, action: 'throw'}]]) {
    for (const publication of [[], aliases]) {
      const f = fixture(states, publication);
      assert.deepEqual(await f.check(request()), await fixture([], []).check(request()));
      assert.equal(f.checked.length, 1);
      assert.deepEqual(f.visible(), []);
      assert.deepEqual(f.calls, states.map(state => state.index));
    }
  }
  for (const states of [[{index: 0, action: 'deny'}, {index: 1, action: 'throw'}],
    [{index: 1, action: 'throw'}, {index: 0, action: 'held'}]]) {
    const f = fixture(states);
    assert.equal((await f.check(request())).outcome, 'completed');
    assert.deepEqual(f.visible(), []);
  }
});

test('composition: context follows current visibility, caller and exact input', async () => {
  const states = [{index: 1, action: 'deny'}, {index: 0, action: 'dispatch'}];
  const f = fixture(states);
  const initial = await f.check(request());
  assert.deepEqual(await f.check(request()), initial);
  const same = fixture([...states].reverse());
  assert.deepEqual(await same.check(request()), initial);
  states[1].action = 'deny';
  const hidden = await f.check(request());
  assert.notEqual(hidden.report.context_ref, initial.report.context_ref);
  states[0].action = 'dispatch';
  const otherSource = await f.check(request());
  assert.notEqual(otherSource.report.context_ref, initial.report.context_ref);
  assert.notEqual((await f.check(request('other'))).report.context_ref,
    otherSource.report.context_ref);
  assert.notEqual((await f.check(request('owner', 'SELECT 2 AS n'))).report.context_ref,
    otherSource.report.context_ref);
  assert.deepEqual(f.visible(), [aliases[1]]);
});

test('composition: abort propagates without consulting later owners or checking', async () => {
  const f = fixture([{index: 0, action: 'dispatch'}]);
  const controller = new AbortController(); controller.abort();
  await assert.rejects(f.check({...request(), signal: controller.signal}),
    {name: 'AbortError'});
  assert.deepEqual(f.calls, []);
  assert.deepEqual(f.checked, []);
});


test('composition: missing read tuples and failed read owners preserve checking', async () => {
  const absentTuple = {index: 0, action: 'throw', noReadTuple: true};
  const none = fixture([absentTuple]);
  assert.equal((await none.check(request())).outcome, 'completed');
  assert.deepEqual(none.calls, []);
  assert.deepEqual(none.visible(), []);
  const failedOwner = fixture([absentTuple, {index: 1, action: 'throw'}]);
  assert.deepEqual(await failedOwner.check(request()), await none.check(request()));
  assert.deepEqual(failedOwner.calls, [1]);
  assert.deepEqual(failedOwner.visible(), []);
});

// Fixed HMAC vectors derived independently with Python's JSON serialization
// and hmac/sha256, the fixture's 32 bytes of 0x07, and literal context fields.
// No product canonicalizer or returned context is used to build expectations.
// The preimages include the registered actql-check-reason/0.1 schema CID.
test('composition: exact Unicode source and received-input fallback have fixed references',
  async () => {
    const texts = ["SELECT 'caf\u00e9' AS label", "SELECT 'cafe\u0301' AS label"];
    const vectors = [{parameterDeclarations: undefined, refs: [
      'ctx:b688efeac5fdb3a6480367d40f7cff274fa5ee31dd045bd3a05d92d465e812cd',
      'ctx:82035b93fdd84ba385d60aebfb667d9dc6d5943bb8467693fb5b2adf08cff5cd',
    ]}, {parameterDeclarations: {'\u00e9': {type: 'string'}, 'e\u0301': {type: 'string'}},
      refs: [
        'ctx:7e4ba10cf976f40066129e276437865b2151b527b3ec6b4eb29eb5e0f30423db',
        'ctx:969d27be66378436d0726b132ebe248cb0666b990a95e9ead7fa584f84e47f52',
      ]}];
    const f = fixture([], []);
    for (const {parameterDeclarations, refs} of vectors) {
      for (const [index, text] of texts.entries()) {
        const input = {text, format: 'sql',
          ...(parameterDeclarations === undefined ? {} : {parameterDeclarations})};
        const call = {principalId: 'owner', input, parameters: null};
        const outcome = await f.check(call);
        assert.equal(outcome.report.context_ref, refs[index]);
        assert.deepEqual(await f.check(call), outcome);
        assert.equal(f.checked.at(-1)[0], text, 'checker receives the authored spelling');
      }
    }
  });
