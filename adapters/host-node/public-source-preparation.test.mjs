import './client-preparation-disclosure.test.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const environment = Object.freeze({generation: cid('a')});
const publication = Object.freeze({environmentCid: cid('a'), aliases: [{
  name: 'records', sourceRef: 'connector://local/records#snapshot',
  sourceViewContractCid: cid('b'), schemaContractCid: cid('c'),
}]});

function installation() {
  const calls = [];
  const prepared = {};
  const moon = {
    clientProgramCheckingEnvironmentCid: value => value.generation,
    clientProgramPrepareSourceWithParameters: (...args) => {
      calls.push({kind: 'source', args});
      return {prepared};
    },
    clientProgramPreparePublicSourceComputationWithParameters: (...args) => {
      calls.push({kind: 'source', args});
      return {pure: {prepared}};
    },
    clientProgramSourceComputationPure: outcome => outcome.pure,
    clientProgramSourceComputationEffect: outcome => outcome.effect,
    clientProgramPrepareEffectFreeWithParameters: (...args) => {
      calls.push({kind: 'program', args});
      return {prepared};
    },
    clientProgramPreparationReady: outcome => outcome.prepared,
    clientProgramPreparationIssue: outcome => outcome.issue,
    clientProgramPreparationIssueCode: outcome => outcome.code,
  };
  return {moon, calls, prepared};
}

test('source preparation carries one published generation and separate values',
  () => {
    const {moon, calls, prepared} = installation();
    const prepare = installNodeClientProgramPreparation({moon, environment,
      sourcePublication: publication});
    assert.equal(prepare({kind: 'aql', input: {
      text: 'SELECT id FROM records WHERE id = @p', format: 'sql',
      parameterDeclarations: {p: {type: 'number'}},
    }, parameters: {p: 2}}), prepared);
    assert.equal(prepare({kind: 'aql', input: {
      text: 'FROM records |> SELECT id', format: 'aql-text',
    }, parameters: null}), prepared);
    assert.equal(prepare({kind: 'aql', input: {
      text: 'FROM records |> SELECT id', format: 'aql',
      parameterDeclarations: {p: {type: 'number'}},
    }, parameters: {p: 2}}), prepared);
    assert.equal(calls.length, 3);
    assert.equal(calls[0].kind, 'source');
    assert.equal(calls[0].args[0],
      'SELECT id FROM records WHERE id = @p');
    assert.equal(calls[0].args[1], 'sql');
    assert.equal(calls[0].args[2], environment);
    assert.deepEqual(JSON.parse(calls[0].args[3]), publication);
    assert.deepEqual(JSON.parse(calls[0].args[4]),
      {p: {type: 'number'}});
    assert.deepEqual(JSON.parse(calls[0].args[5]), {p: 2});
    assert.equal(calls[1].args[4], undefined);
    assert.equal(calls[1].args[5], undefined);
    assert.equal(calls[2].args[1], 'aql');
    assert.deepEqual(JSON.parse(calls[2].args[4]), {p: {type: 'number'}});
    assert.deepEqual(JSON.parse(calls[2].args[5]), {p: 2});
    assert.equal(prepare.kindOf(prepared), 'effect_free');
  });

test('JSON Program keeps its existing preparation route', () => {
  const {moon, calls} = installation();
  const prepare = installNodeClientProgramPreparation({moon, environment});
  prepare({kind: 'aql', input: {text: '{}', format: 'json'},
    parameters: {p: 1}});
  assert.equal(calls[0].kind, 'program');
  assert.deepEqual(calls[0].args, ['{}', 'json', environment, '{"p":1}']);
  assert.throws(() => prepare({kind: 'aql', input: {
    text: '{}', format: 'json', parameterDeclarations: {p: {type: 'number'}},
  }, parameters: null}), {code: 'ClientProgramInvalidInput'});
});

test('new public Source never silently substitutes the historical answer recipe', () => {
  const {moon} = installation();
  delete moon.clientProgramPreparePublicSourceComputationWithParameters;
  moon.clientProgramPrepareSourceComputationWithParameters = () => {
    assert.fail('an old answer bridge is not the new public primary recipe');
  };
  const prepare = installNodeClientProgramPreparation({moon, environment});
  assert.throws(() => prepare({kind: 'aql', input: {text: 'SELECT 1', format: 'sql'},
    parameters: null}), {code: 'ClientProgramUnsupported'});
});

test('text preparation retains explicitly published write bindings under the common validator', () => {
  const {moon, calls, prepared} = installation();
  const writes = {...publication, tableWrites: [{name: 'analytics.report',
    targetRef: 'connector://local/report', mappingRef: 'mapping:local.report.v1',
    mappingCid: cid('d'), capabilityCid: cid('e'), installationBindingCid: cid('f'),
    action: 'create', expectedTable: null}]};
  const validated = [];
  moon.clientProgramSourcePublicationValid = (owner, wire) => {
    validated.push({owner, wire}); return true;
  };
  const prepare = installNodeClientProgramPreparation({moon, environment, sourcePublication: writes});
  assert.equal(prepare({kind: 'aql', input: {
    text: 'CREATE TABLE analytics.report AS SELECT 1 AS id', format: 'sql'}, parameters: null}), prepared);
  assert.deepEqual(validated, [{owner: environment, wire: JSON.stringify(writes)}]);
  assert.deepEqual(JSON.parse(calls[0].args[3]), writes);
  moon.clientProgramSourcePublicationValid = () => false;
  const refused = installNodeClientProgramPreparation({moon, environment, sourcePublication: writes});
  assert.throws(() => refused({kind: 'aql', input: {text: 'SELECT 1', format: 'sql'}, parameters: null}),
    {name: 'TypeError', message: 'InvalidPublicSourcePublication'});
  assert.equal(calls.length, 1, 'Invalid write metadata never reaches lowering');
});

test('lowered text Effect goes directly to its existing owner without resubmitting text', () => {
  const {moon, calls} = installation();
  const preparedEffect = {};
  const evidence = [{}];
  moon.clientProgramPrepareSourceWithParameters = () => ({
    code: 'effect_not_supported', issue: {kind: 'effect'},
  });
  moon.clientProgramPreparePublicSourceComputationWithParameters = (...args) => {
    calls.push({kind: 'source', args});
    return {effect: {preparedEffect}};
  };
  moon.clientProgramPrepareEffectComputationWithParameters = (...args) => {
    calls.push({kind: 'original-effect-document', args});
    return {code: 'invalid_format', issue: {kind: 'text_is_not_json'}};
  };
  moon.clientProgramEffectPreparationReady = outcome => outcome.preparedEffect;
  moon.clientProgramEffectPreparationIssue = outcome => outcome.issue;
  moon.clientProgramEffectPreparationIssueCode = outcome => outcome.code;
  const prepare = installNodeClientProgramPreparation({moon, environment,
    sourcePublication: publication, allowEffects: true, effectEvidence: evidence});
  evidence.push({foreign: true});
  const text = 'frontend-authored Effect source';
  assert.equal(prepare({kind: 'aql', input: {text, format: 'aql-text',
    parameterDeclarations: {p: {type: 'string'}}}, parameters: {p: 'e\u0301\r\n'}}),
  preparedEffect);
  assert.equal(prepare.kindOf(preparedEffect), 'effectful');
  assert.deepEqual(calls, [{kind: 'source', args: [text, 'aql-text', environment,
    JSON.stringify(publication), '{"p":{"type":"string"}}', '{"p":"é\\r\\n"}',
    true, [evidence[0]]]}]);
  assert.throws(() => prepare.assertOwned({}), TypeError);
});

test('text Effect closure refusal is preserved without retrying original source', () => {
  const {moon, calls} = installation();
  const issue = {kind: 'foreign_mapping'};
  moon.clientProgramPreparePublicSourceComputationWithParameters = (...args) => {
    calls.push({kind: 'source', args});
    return {effect: {issue, code: 'effect_mapping_rejected'}};
  };
  moon.clientProgramPrepareEffectComputationWithParameters = () => {
    throw new Error('SourceMustNotBeResubmitted');
  };
  moon.clientProgramEffectPreparationReady = () => undefined;
  moon.clientProgramEffectPreparationIssue = outcome => outcome.issue;
  moon.clientProgramEffectPreparationIssueCode = outcome => outcome.code;
  const prepare = installNodeClientProgramPreparation({moon, environment,
    sourcePublication: publication, allowEffects: true});
  assert.throws(() => prepare({kind: 'aql', input: {text: 'frontend-authored Effect source',
    format: 'aql-text'}, parameters: null}), error => {
    assert.equal(error.code, 'ClientProgramRejected');
    assert.equal(error.cause, issue);
    return true;
  });
  assert.equal(calls.length, 1);
});

test('contradictory source computation branches cannot issue an owned preparation', () => {
  const {moon, prepared} = installation();
  for (const outcome of [{}, {pure: {prepared}, effect: {preparedEffect: {}}}]) {
    moon.clientProgramPreparePublicSourceComputationWithParameters = () => outcome;
    const prepare = installNodeClientProgramPreparation({moon, environment,
      sourcePublication: publication});
    assert.throws(() => prepare({kind: 'aql', input: {text: 'SELECT 1', format: 'sql'},
      parameters: null}), {name: 'TypeError', message: 'InvalidClientSourceComputationOutcome'});
    assert.throws(() => prepare.assertOwned(prepared), TypeError);
  }
});

test('mismatched or malformed alias publication cannot be installed', () => {
  const {moon} = installation();
  for (const sourcePublication of [
    {...publication, environmentCid: cid('d')},
    {...publication, aliases: [{...publication.aliases[0],
      schemaContractCid: 'not-a-cid'}]},
    {...publication, aliases: [{...publication.aliases[0],
      extra: true}]},
  ]) {
    const prepare = installNodeClientProgramPreparation({moon,
      environment, sourcePublication});
    assert.throws(() => prepare({kind: 'aql', input: {
      text: 'SELECT id FROM records', format: 'sql',
    }, parameters: null}), TypeError);
  }
});

test('source input is typed unsupported until the shared MoonBit bridge exists',
  () => {
    const {moon} = installation();
    delete moon.clientProgramPreparePublicSourceComputationWithParameters;
    const prepare = installNodeClientProgramPreparation({moon, environment});
    assert.throws(() => prepare({kind: 'aql', input: {
      text: 'SELECT 1', format: 'sql',
    }, parameters: null}), {code: 'ClientProgramUnsupported'});
  });

test('confirmed Frontend refusal keeps a typed input error', () => {
  const {moon} = installation();
  moon.clientProgramPreparePublicSourceComputationWithParameters = () => ({pure: {
    code: 'source_rejected', issue: {kind: 'unknown_alias'},
  },
  });
  const prepare = installNodeClientProgramPreparation({moon, environment,
    sourcePublication: publication});
  assert.throws(() => prepare({kind: 'aql', input: {
    text: 'SELECT id FROM unregistered', format: 'sql',
  }, parameters: null}), {code: 'ClientProgramRejected'});
});
