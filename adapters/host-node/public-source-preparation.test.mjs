import './client-preparation-disclosure.test.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientProgramPreparation, checkedRequestProgramPreparation} from
  './client-program-preparation.mjs';
import {installNodePublicSourcePreparation} from './public-source-preparation.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const environment = Object.freeze({generation: cid('a')});
const publication = Object.freeze({environmentCid: cid('a'), aliases: [{
  name: 'records', sourceRef: 'connector://local/records#snapshot',
  sourceViewContractCid: cid('b'), schemaContractCid: cid('c'),
}]});

// Explicit Common outcome ports, not a compiler or a funded Request issuer.
function installation() {
  const calls = [], admissions = [], prepared = {};
  const originals = new WeakMap();
  const moon = {
    clientProgramCheckingEnvironmentCid: value => value.generation,
    clientProgramPreparePublicSourceEnvironment: (owner, wire) => {
      const original = Object.freeze({}); originals.set(original, owner);
      admissions.push({owner, wire, original}); return original;
    },
    clientProgramPublicSourceEnvironmentMatches: (original, owner) => originals.get(original) === owner,
    clientProgramPrepareSourceComputationInPublicEnvironment: (...args) => {
      calls.push({kind: 'source', args}); return {pure: {prepared}};
    },
    clientProgramSourceComputationPure: outcome => outcome.pure,
    clientProgramSourceComputationEffect: outcome => outcome.effect,
    clientProgramPrepareSourceComputationWithParameters() {assert.fail('No historical answer recipe');},
    clientProgramPrepareEffectComputationWithParameters() {assert.fail('No text resubmission');},
  };
  return {moon, calls, prepared, admissions};
}

test('source preparation carries one published generation and separate values', () => {
  const {moon, calls, prepared, admissions} = installation();
  const prepare = installNodePublicSourcePreparation({moon, environment, publication});
  const first = prepare.prepare({document: 'SELECT id FROM records WHERE id = @p', format: 'sql',
    declarations: '{"p":{"type":"number"}}', supplied: '{"p":2}'});
  const second = prepare.prepare({document: 'FROM records |> SELECT id', format: 'aql-text'});
  const third = prepare.prepare({document: 'FROM records |> SELECT id', format: 'aql',
    declarations: '{"p":{"type":"number"}}', supplied: '{"p":2}'});
  for (const outcome of [first, second, third]) {
    assert.equal(outcome.kind, 'effect_free'); assert.strictEqual(outcome.outcome.prepared, prepared);
  }
  assert.equal(calls.length, 3); assert.equal(calls[0].kind, 'source');
  assert.equal(calls[0].args[0], 'SELECT id FROM records WHERE id = @p');
  assert.equal(calls[0].args[1], 'sql'); assert.strictEqual(calls[0].args[2], environment);
  assert.equal(admissions.length, 1); assert.strictEqual(admissions[0].owner, environment);
  assert.deepEqual(JSON.parse(admissions[0].wire), publication);
  assert(calls.every(call => call.args[3] === admissions[0].original));
  assert.deepEqual(JSON.parse(calls[0].args[4]), {p: {type: 'number'}});
  assert.deepEqual(JSON.parse(calls[0].args[5]), {p: 2});
  assert.equal(calls[1].args[4], undefined); assert.equal(calls[1].args[5], undefined);
  assert.equal(calls[2].args[1], 'aql');
  assert.deepEqual(JSON.parse(calls[2].args[4]), {p: {type: 'number'}});
  assert.deepEqual(JSON.parse(calls[2].args[5]), {p: 2});
});

test('JSON Program keeps its existing preparation route', async () => {
  const prepared = {}, issue = {}, refused = {$tag: 0, _0: issue}, calls = [];
  const request = {kind: 'aql', input: {text: '{}', format: 'json'}, parameters: {p: 1}};
  const invalid = {kind: 'aql', input: {text: '{}', format: 'json',
    parameterDeclarations: {p: {type: 'number'}}}, parameters: null};
  const original = {kind: 'effect_free', prepared,
    originalInputs: {environment, parameters: '{"p":1}'}};
  const moon = {clientProgramRequestPreparationIssueCode(result) {
    assert.strictEqual(result, refused); return 'invalid_format';
  }};
  const prepare = installNodeClientProgramPreparation({moon, environment,
    async getFundedPreparation(actual, owner) {
      assert.strictEqual(owner, environment); calls.push(actual);
      if (actual === request) return original;
      assert.strictEqual(actual, invalid); return checkedRequestProgramPreparation(moon, refused);
    }});
  assert.strictEqual(await prepare(request), prepared);
  assert.equal(prepare.kindOf(prepared), 'effect_free');
  assert.equal(prepare.originalInputs(prepared).parameters, '{"p":1}');
  await assert.rejects(prepare(invalid), error => {
    assert.equal(error.code, 'ClientProgramInvalidInput'); assert.strictEqual(error.cause, issue); return true;
  });
  assert.deepEqual(calls, [request, invalid]);
});

test('new public Source never silently substitutes the historical answer recipe', () => {
  const {moon} = installation(); delete moon.clientProgramPrepareSourceComputationInPublicEnvironment;
  const prepare = installNodePublicSourcePreparation({moon, environment});
  assert.throws(() => prepare.prepare({document: 'SELECT 1', format: 'sql'}),
    {code: 'ClientProgramUnsupported'});
});

test('text preparation retains explicitly published write bindings under the common validator', () => {
  const {moon, calls, prepared, admissions} = installation();
  const writes = {...publication, tableWrites: [{name: 'analytics.report',
    targetRef: 'connector://local/report', mappingRef: 'mapping:local.report.v1',
    mappingCid: cid('d'), capabilityCid: cid('e'), installationBindingCid: cid('f'),
    action: 'create', expectedTable: null}]};
  const prepare = installNodePublicSourcePreparation({moon, environment, publication: writes});
  const outcome = prepare.prepare({document: 'CREATE TABLE analytics.report AS SELECT 1 AS id', format: 'sql'});
  assert.strictEqual(outcome.outcome.prepared, prepared);
  assert.deepEqual(admissions.map(({owner, wire}) => ({owner, wire})),
    [{owner: environment, wire: JSON.stringify(writes)}]);
  assert.equal(moon.clientProgramPublicSourceEnvironmentMatches(calls[0].args[3], environment), true);
  moon.clientProgramPreparePublicSourceEnvironment = () => undefined;
  assert.throws(() => installNodePublicSourcePreparation({moon, environment, publication: writes}),
    {name: 'TypeError', message: 'InvalidPublicSourcePublication'});
  assert.equal(calls.length, 1, 'Invalid write metadata never reaches lowering');
});

test('lowered text Effect goes directly to its existing owner without resubmitting text', async () => {
  const {moon, calls} = installation(); const preparedEffect = {}, evidence = [{}];
  moon.clientProgramPrepareSourceComputationInPublicEnvironment = (...args) => {
    calls.push({kind: 'source', args}); return {effect: {preparedEffect}};
  };
  const source = installNodePublicSourcePreparation({moon, environment, publication,
    allowEffects: true, effectEvidence: evidence}); evidence.push({foreign: true});
  const text = 'frontend-authored Effect source';
  const lowered = source.prepare({document: text, format: 'aql-text',
    declarations: '{"p":{"type":"string"}}', supplied: '{"p":"é\\r\\n"}'});
  assert.equal(lowered.kind, 'effectful'); assert.strictEqual(lowered.outcome.preparedEffect, preparedEffect);
  const preparedEnvironment = calls[0].args[3];
  assert.equal(moon.clientProgramPublicSourceEnvironmentMatches(preparedEnvironment, environment), true);
  assert.deepEqual(calls, [{kind: 'source', args: [text, 'aql-text', environment,
    preparedEnvironment, '{"p":{"type":"string"}}', '{"p":"é\\r\\n"}', true, [evidence[0]]]}]);
  const request = {}, original = {kind: 'effectful', prepared: preparedEffect, originalInputs: {environment}};
  const prepare = installNodeClientProgramPreparation({moon, environment, allowEffects: true,
    async getFundedPreparation(actual, owner) {
      assert.strictEqual(actual, request); assert.strictEqual(owner, environment); return original;
    }});
  assert.strictEqual(await prepare(request), preparedEffect);
  assert.equal(prepare.kindOf(preparedEffect), 'effectful');
  assert.throws(() => prepare.assertOwned({}), TypeError);
  assert.equal(calls.length, 1, 'The Request wrapper never resubmits lowered text');
});

test('text Effect closure refusal is preserved without retrying original source', async () => {
  const {moon, calls} = installation(); const issue = {kind: 'foreign_mapping'};
  const refused = {issue, code: 'effect_mapping_rejected'};
  moon.clientProgramPrepareSourceComputationInPublicEnvironment = (...args) => {
    calls.push({kind: 'source', args}); return {effect: refused};
  };
  const prepare = installNodePublicSourcePreparation({moon, environment, publication, allowEffects: true});
  const outcome = prepare.prepare({document: 'frontend-authored Effect source', format: 'aql-text'});
  assert.equal(outcome.kind, 'effectful'); assert.strictEqual(outcome.outcome, refused);
  assert.strictEqual(outcome.outcome.issue, issue); assert.equal(outcome.outcome.code, 'effect_mapping_rejected');
  const result = {$tag: 0, _0: issue}, request = {}; let fundedCalls = 0;
  moon.clientProgramRequestPreparationIssueCode = original => {
    assert.strictEqual(original, result); return 'effect_mapping_rejected';
  };
  const owned = installNodeClientProgramPreparation({moon, environment, allowEffects: true,
    async getFundedPreparation(actual, owner) {
      assert.strictEqual(actual, request); assert.strictEqual(owner, environment); fundedCalls++;
      return checkedRequestProgramPreparation(moon, result);
    }});
  await assert.rejects(owned(request), error => {
    assert.equal(error.code, 'ClientProgramRejected'); assert.strictEqual(error.cause, issue); return true;
  });
  assert.equal(fundedCalls, 1);
  assert.equal(calls.length, 1);
});

test('contradictory source computation branches cannot issue an owned preparation', async () => {
  const {moon, prepared} = installation();
  for (const outcome of [{}, {pure: {prepared}, effect: {preparedEffect: {}}}]) {
    moon.clientProgramPrepareSourceComputationInPublicEnvironment = () => outcome;
    const prepare = installNodePublicSourcePreparation({moon, environment, publication});
    let failure;
    assert.throws(() => prepare.prepare({document: 'SELECT 1', format: 'sql'}), error => {
      assert.equal(error.name, 'TypeError'); assert.equal(error.message, 'InvalidClientSourceComputationOutcome');
      failure = error; return true;
    });
    const request = {}, owned = installNodeClientProgramPreparation({moon, environment,
      async getFundedPreparation(actual, owner) {
        assert.strictEqual(actual, request); assert.strictEqual(owner, environment); throw failure;
      }});
    await assert.rejects(owned(request), error => {
      assert.strictEqual(error, failure); return true;
    });
    assert.throws(() => owned.assertOwned(prepared), TypeError);
  }
});

test('mismatched or malformed alias publication cannot be installed', () => {
  const {moon, calls, admissions} = installation();
  for (const selected of [{...publication, environmentCid: cid('d')},
    {...publication, aliases: [{...publication.aliases[0], schemaContractCid: 'not-a-cid'}]},
    {...publication, aliases: [{...publication.aliases[0], extra: true}]}]) {
    assert.throws(() => installNodePublicSourcePreparation({moon, environment, publication: selected}), TypeError);
  }
  assert.equal(calls.length, 0); assert.equal(admissions.length, 0);
});

test('source input is typed unsupported until the shared MoonBit bridge exists', () => {
  const {moon} = installation(); delete moon.clientProgramPrepareSourceComputationInPublicEnvironment;
  const prepare = installNodePublicSourcePreparation({moon, environment});
  assert.throws(() => prepare.prepare({document: 'SELECT 1', format: 'sql'}), {code: 'ClientProgramUnsupported'});
});

test('confirmed Frontend refusal keeps a typed input error', async () => {
  const issue = {kind: 'unknown_alias'}, refused = {$tag: 0, _0: issue}, request = {};
  let calls = 0;
  const moon = {clientProgramRequestPreparationIssueCode(original) {
    assert.strictEqual(original, refused); return 'source_rejected';
  }};
  const prepare = installNodeClientProgramPreparation({moon, environment,
    async getFundedPreparation(actual, owner) {
      assert.strictEqual(actual, request); assert.strictEqual(owner, environment); calls++;
      return checkedRequestProgramPreparation(moon, refused);
    }});
  await assert.rejects(prepare(request), error => {
    assert.equal(error.code, 'ClientProgramRejected'); assert.strictEqual(error.cause, issue); return true;
  });
  assert.equal(calls, 1);
});
