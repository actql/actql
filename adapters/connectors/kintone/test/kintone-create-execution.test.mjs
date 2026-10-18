import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeIsError} from '../../../host-common/compiler-binding.generated.mjs';
import {prepareMappedKintoneCreate, sendMappedKintoneCreate} from '../site/kintone-create-execution.mjs';
import {projectKintoneWriteObservation} from '../site/kintone-record-write.mjs';
import {writeFixture} from './kintone-record-write.fixture.mjs';
import {originalForm as readForm} from './installed-kintone.fixture.mjs';

const formDocument = {...readForm, properties: {...readForm.properties,
  Subject: {...readForm.properties.Subject, expression: '', required: true},
  Tags: {...readForm.properties.Tags, required: false}}};
const values = Buffer.from(JSON.stringify(Array.from({length: 2}, () =>
  ({Subject: 'next 東京', Tags: ['東京', 'red', '東京']}))));

async function fixture(t, options = {}) {
  const f = await writeFixture(t, {...options, kind: 'create', formDocument});
  const moon = f.common;
  const bound = moon.clientProgramKintoneDeclarationLimits(200000, 20000, 20, 16, 16);
  const declare = () => checked(moon.clientProgramKintoneDeclareRecords(f.catalog, undefined,
    ['Subject', 'Tags'], 'kintone', 'kintone/0.1', 'inquiries',
    moon.clientProgramKintoneValueLimits(8, 512, 2000, 20, 8192), bound));
  const declaration = declare();
  const mapping = checked(moon.clientProgramKintonePrepareCreateMapping(declaration,
    'inquiries', [{target: 'Subject', field: 'subject', null_behavior: 'reject'},
      {target: 'Tags', field: 'tags', null_behavior: 'omit'}], 'required', bound));
  const prepare = (bytes = values, changes = {}) => prepareMappedKintoneCreate({moon,
    declaration, mapping, bytes, limits: f.options.limits, ...changes});
  const request = prepare();
  const send = async (changes = {}) => {
    assert.equal(f.state.active, false); f.state.active = true;
    try {return await sendMappedKintoneCreate({...f.options, declaration, mapping, request, ...changes});}
    finally {f.state.active = false;}
  };
  return {...f, declare, declaration, mapping, prepare, mappedRequest: request, sendMapped: send};
}

test('original mapped CREATE reaches the unchanged two-record native TLS oracle and response custody', async t => {
  const f = await fixture(t);
  assert.equal(checked(f.common.clientProgramKintoneCreateValuesJson(f.mappedRequest,
    8192, 2000, 20)), values.toString());
  const raw = await f.sendMapped();
  assert.equal(f.state.writes, 1); assert.equal(f.tls.seen().length, 2);
  assert.equal(f.state.charges, 2); assert.equal(f.state.consumed, 2);
  assert.deepEqual(f.state.fixtureFailures, []);
  assert.equal(f.journal.recover().filter(row => row.outcome === 'succeeded').length, 2);
  const typed = projectKintoneWriteObservation({moon: f.common, kind: 'create', request: f.mappedRequest,
    observation: raw.observation, limits: f.options.limits});
  assert.equal(typed.kind, 'typed-create-response');
  assert.equal(f.common.clientProgramKintoneCreateResponseRequest(typed.response), f.mappedRequest);
  assert.equal(typed.observation, raw.observation); f.row.assertNoCapture();
});

test('copied Mapping, foreign declaration, unmapped and missing required values refuse before any I/O', async t => {
  const f = await fixture(t);
  const copied = {...f.mapping};
  assert.equal(f.common.clientProgramKintoneCreateMappingMatchesDeclaration(copied, f.declaration), false);
  assert.equal(runtimeIsError(f.common.clientProgramKintoneCreateMappingBody(copied)), true);
  for (const changes of [{mapping: copied}, {declaration: f.declare()}]) {
    assert.throws(() => f.prepare(values, changes), {code: 'ForeignKintoneCreateMapping'});
    await assert.rejects(f.sendMapped(changes), {code: 'ForeignKintoneCreateMapping'});
  }
  for (const bytes of [Buffer.from('[{"Tags":[]}]'),
    Buffer.from('[{"Subject":"x","RecordNumber":"1"}]'), Buffer.from('[{"Subject":1}]')]) {
    assert.throws(() => f.prepare(bytes), {code: 'MoonBitHostFailure'});
  }
  assert.equal(f.tls.seen().length, 0); assert.equal(f.state.resolutions, 0);
  assert.equal(f.state.writes, 0); assert.equal(f.journal.recover().length, 0);
});

test('mapped CREATE keeps actual Account refusal and original credential rotation fences', async t => {
  for (const change of ['deny', 'rotate']) {
    const f = await fixture(t, change === 'deny' ? {effect: 'deny'} : {});
    await assert.rejects(f.sendMapped(change === 'rotate' ? {consumeObservation: charge => {
      f.options.consumeObservation(charge); f.state.secret = 'replacement-account-token';
    }} : {}), {code: change === 'deny' ? 'ExecutionAuthorizationDenied' : 'RemoteCredentialBindingChanged'});
    assert.equal(f.state.writes, 0); assert.equal(f.tls.seen().length, 1);
    if (change === 'rotate') {
      const resolutions = f.state.resolutions;
      await assert.rejects(f.sendMapped(), {code: 'RemoteCredentialBindingChanged'});
      assert.equal(f.state.resolutions, resolutions);
    }
  }
});

test('mapped CREATE lost response preserves the original Unknown and never resends', async t => {
  const f = await fixture(t, {faults: [{method: 'POST', bodyIncludes: '"value":"next 東京"',
    kind: 'apply-then-lose-reply'}]});
  await assert.rejects(f.sendMapped(), {code: 'ECONNRESET'});
  assert.equal(f.state.writes, 1);
  assert.equal(f.journal.recover().filter(row => row.outcome === 'unknown').length, 1);
  await assert.rejects(f.sendMapped());
  assert.equal(f.state.writes, 1); assert.equal(f.tls.seen().length, 2);
});

test('mapped CREATE retains actual response bytes after current authorization is revoked', async t => {
  const f = await fixture(t);
  f.state.reply = async () => {await f.writeAccount('deny'); return {body: {original: 'received'}};};
  await assert.rejects(f.sendMapped(), error => {
    assert.equal(error.code, 'AuthorizationCurrentAccountChanged');
    assert.equal(error.observations.length, 2);
    assert.equal(error.observations[1].body.toString(), '{"original":"received"}'); return true;
  });
  assert.equal(f.state.writes, 1); assert.equal(f.state.charges, 2); f.row.assertNoCapture();
});
