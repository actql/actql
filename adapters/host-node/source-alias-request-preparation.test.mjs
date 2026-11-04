import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodePublicSourcePreparation} from './public-source-preparation.mjs';

const cid = digit => 'sha256:' + digit.repeat(64);
const environment = Object.freeze({generation: cid('a')});
const alias = Object.freeze({name: 'records', sourceRef: 'connector://local/records#snapshot',
  sourceViewContractCid: cid('b'), schemaContractCid: cid('c')});
function fixture() {
  const admissions = [], originals = new WeakMap();
  const moon = {
    clientProgramCheckingEnvironmentCid: owner => owner.generation,
    clientProgramPreparePublicSourceEnvironment(owner, wire) {
      const original = Object.freeze({}); originals.set(original, owner);
      admissions.push({owner, wire}); return original;
    },
    clientProgramPublicSourceEnvironmentMatches: (original, owner) => originals.get(original) === owner,
  };
  const install = request => installNodePublicSourcePreparation({moon, environment,
    publication: {environmentCid: environment.generation, aliases: [{...alias, request}]}});
  return {admissions, install};
}

test('fallback public preparation preserves explicit request DATA without filling omitted fields', () => {
  for (const request of [{}, {paths: null, glob: null}, {filter: {nested: {$param: 'business'}}}]) {
    const f = fixture(); f.install(request);
    assert.deepEqual(JSON.parse(f.admissions[0].wire).aliases[0].request, request);
  }
});

test('fallback public preparation refuses executable direct request slots before admission', () => {
  for (const request of [null, [], {x: {$param: 'p'}}, {x: {$binding: 1}},
    {get x() {assert.fail('No request getter');}}]) {
    const f = fixture();
    assert.throws(() => f.install(request), /InvalidPublicSourcePublication/);
    assert.equal(f.admissions.length, 0);
  }
});
