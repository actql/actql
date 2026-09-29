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
    clientProgramCheckEnvironmentCid: value => value.generation,
    clientProgramPrepareSourceWithParameters: (...args) => {
      calls.push({kind: 'source', args});
      return {prepared};
    },
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
    assert.equal(calls.length, 2);
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

test('mismatched or malformed alias publication cannot be installed', () => {
  const {moon} = installation();
  for (const sourcePublication of [
    {...publication, environmentCid: cid('d')},
    {...publication, aliases: [{...publication.aliases[0],
      schemaContractCid: 'not-a-cid'}]},
    {...publication, aliases: [{...publication.aliases[0],
      extra: true}]},
  ]) {
    assert.throws(() => installNodeClientProgramPreparation({moon,
      environment, sourcePublication}), TypeError);
  }
});

test('source input is typed unsupported until the shared MoonBit bridge exists',
  () => {
    const {moon} = installation();
    delete moon.clientProgramPrepareSourceWithParameters;
    const prepare = installNodeClientProgramPreparation({moon, environment});
    assert.throws(() => prepare({kind: 'aql', input: {
      text: 'SELECT 1', format: 'sql',
    }, parameters: null}), {code: 'ClientProgramUnsupported'});
  });

test('confirmed Frontend refusal keeps a typed input error', () => {
  const {moon} = installation();
  moon.clientProgramPrepareSourceWithParameters = () => ({
    code: 'source_rejected', issue: {kind: 'unknown_alias'},
  });
  const prepare = installNodeClientProgramPreparation({moon, environment,
    sourcePublication: publication});
  assert.throws(() => prepare({kind: 'aql', input: {
    text: 'SELECT id FROM unregistered', format: 'sql',
  }, parameters: null}), {code: 'ClientProgramRejected'});
});
