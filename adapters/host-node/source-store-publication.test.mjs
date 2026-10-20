// The ordinary Host's publication projection, with an explicit Common port.
// These cases establish no installed target, Reference or physical write grant.
import assert from 'node:assert/strict';
import test from 'node:test';
import {sourceAliasPublication} from './source-alias-publication.mjs';

const cid = digit => 'sha256:' + digit.repeat(64);
const target = () => ({name:'local.files',targetRef:'connector://local/files',
  installationBindingCid:cid('a'),installationOwnerCid:cid('b')});
function fixture(validate = () => true) {
  const environment = Object.freeze({});
  const observed = [];
  const moon = {
    clientProgramCheckingEnvironmentCid(value) {
      assert.strictEqual(value,environment);
      return cid('c');
    },
    clientProgramSourcePublicationValid(value,wire) {
      assert.strictEqual(value,environment);
      observed.push(wire);
      return validate(JSON.parse(wire));
    },
  };
  return {moon,environment,observed};
}

test('ordinary publication owns STORE targets and forwards them to the same Common environment', () => {
  const {moon,environment,observed} = fixture();
  const targets = [target()];
  const publication = sourceAliasPublication(moon,environment,[],[],{storeTargets:targets});
  assert.deepEqual(JSON.parse(observed[0]),{environmentCid:cid('c'),aliases:[],storeTargets:[target()]});
  targets[0].targetRef = 'connector://foreign/files';
  targets.push(target());
  assert.deepEqual(publication.storeTargets,[target()]);
  assert(Object.isFrozen(publication));
  assert(Object.isFrozen(publication.storeTargets));
  assert(Object.isFrozen(publication.storeTargets[0]));
});

test('absent or empty STORE targets preserve the ordinary publication bytes', () => {
  const {moon,environment} = fixture();
  const original = sourceAliasPublication(moon,environment);
  assert.equal(JSON.stringify(original),JSON.stringify({environmentCid:cid('c'),aliases:[]}));
  assert.deepEqual(sourceAliasPublication(moon,environment,[],[],{storeTargets:[]}),original);
  assert.equal(Object.hasOwn(original,'storeTargets'),false);
});

test('malformed or unadmitted STORE targets cannot bypass the existing Common publication validator', () => {
  const {moon,environment} = fixture();
  for (const storeTargets of [null,{},Array(1025).fill(target()),[null],
    [{...target(),name:''}],[{...target(),targetRef:''}],
    [{...target(),installationBindingCid:'not-a-cid'}],
    [{...target(),installationOwnerCid:undefined}],
    [{...target(),mappingRef:'mapping:foreign'}],
    [{...target(),name:'x'.repeat(1025)}],
    [{...target(),targetRef:'\ud800'}]]) {
    assert.throws(() => sourceAliasPublication(moon,environment,[],[],{storeTargets}),
      {message:'InvalidPublicStoreTargetPublication'});
  }
  const refusing = fixture(() => false);
  assert.throws(() => sourceAliasPublication(refusing.moon,refusing.environment,[],[],
    {storeTargets:[target()]}),{message:'InvalidPublicSourcePublication'});
  assert.throws(() => sourceAliasPublication({...moon,clientProgramSourcePublicationValid:undefined},
    environment,[],[],{storeTargets:[target()]}),{message:'InvalidPublicSourcePublication'});
});
