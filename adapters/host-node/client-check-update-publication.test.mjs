import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientCheck} from './client-check.mjs';

const cid = digit => 'sha256:' + digit.repeat(64);
const target = Object.freeze({name: 'salesforce.Account',
  targetRef: 'connector://salesforce/Account',
  installationBindingCid: cid('1'), installationOwnerCid: cid('2')});

// Explicit routing doubles: these do not issue an Environment, installation,
// disclosure decision or executable Effect. Common owns the actual checker.
function setup(disclose, targets = [target]) {
  const calls = [];
  const moon = {
    clientProgramCheckingEnvironmentCid: () => cid('3'),
    clientProgramCheckCompilerIdentity: () => '{}',
    clientProgramCheckContextIdentity: () => '{}',
    clientProgramCheckSourceNamespace() {},
    clientProgramCheckSourceSelectorNamespace() {},
    clientProgramCheckUnavailable: () => '{}',
    clientProgramCheckSource(...args) {
      calls.push({kind: 'text', publication: JSON.parse(args[3]), context: args[6]});
      return '{}';
    },
    clientProgramCheckProgram(...args) {
      calls.push({kind: 'program', publication: JSON.parse(args[2]), context: args[4]});
      return '{}';
    },
  };
  const disclosure = disclose === undefined ? undefined : {
    async visibleFor(request) { return disclose.call(this, request); },
  };
  return {calls, disclosure, check: installNodeClientCheck({moon, environment: {},
    publication: Object.freeze({environmentCid: cid('3'), aliases: [],
      updateTargets: Object.freeze(targets)}),
    updateTargetDisclosure: disclosure, contextKey: Buffer.alloc(32, 7)})};
}

const request = kind => ({principalId: 'reader', kind, scope: 'bound_input',
  input: kind === 'text' ? {format: 'sql', text: 'UPDATE salesforce.Account'} : {},
  parameters: null});

for (const kind of ['text', 'program']) {
  test(`${kind} checking retains only the original disclosed UPDATE publication`, async () => {
    let observed;
    const selected = setup(function (value) { observed = {receiver: this, value}; return [target]; });
    await selected.check(request(kind));
    assert.equal(observed.receiver, selected.disclosure);
    assert.equal(observed.value.principalId, 'reader');
    assert.deepEqual(selected.calls[0].publication.updateTargets, [target]);
  });
}

test('missing, copied and failed target disclosure does not expose UPDATE metadata', async () => {
  for (const disclose of [undefined, () => [], () => [{...target}],
    () => [target, target], () => { throw Error('unavailable'); }]) {
    const selected = setup(disclose);
    await selected.check(request('text'));
    assert.equal(selected.calls[0].publication.updateTargets, undefined);
  }
});

test('visible UPDATE originals bind the checking context; hidden originals do not', async () => {
  const visible = setup(() => [target]);
  const hidden = setup(() => []);
  const absent = setup(undefined, []);
  for (const value of [visible, hidden, absent]) await value.check(request('text'));
  assert.notEqual(visible.calls[0].context, hidden.calls[0].context);
  assert.equal(hidden.calls[0].context, absent.calls[0].context);
});

test('abort after the original disclosure await precedes Common checking', async () => {
  const controller = new AbortController();
  const selected = setup(() => { controller.abort(); return [target]; });
  await assert.rejects(selected.check({...request('text'), signal: controller.signal}),
    {name: 'AbortError'});
  assert.equal(selected.calls.length, 0);
});

test('installation captures the original disclosure callback and receiver once', async () => {
  let calls = 0;
  const selected = setup(function () {
    assert.equal(this, selected.disclosure);
    calls++;
    return [target];
  });
  selected.disclosure.visibleFor = () => { throw Error('replacement'); };
  await selected.check(request('text'));
  assert.equal(calls, 1);
  assert.deepEqual(selected.calls[0].publication.updateTargets, [target]);
});
