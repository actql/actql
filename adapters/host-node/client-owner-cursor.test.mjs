import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId:'namespace-e\u0301', authorityScopeCid:cid('a'), runDefinitionCid:cid('b')};
const owner = {kind:'effect', scopeCid:cid('c'), streamCid:cid('d')};
const position = {generation:cid('1'), revision:2, entryCid:cid('2')};
const keys = generateKeyPairSync('ed25519');
const open = async () => {
  const {createClientOwnerCursorCodec} = await import('./client-owner-cursor.mjs');
  return createClientOwnerCursorCodec({privateKey:keys.privateKey, publicKey:keys.publicKey});
};

test('Owner cursor preserves the original scoped prefix across codec recreation', async () => {
  const first = await open();
  const cursor = first.issue({ref, owner, position});
  const restarted = await open();
  assert.deepEqual(restarted.read(cursor, {ref, owner}), {kind:'matched', position});
  assert.deepEqual(restarted.read(cursor, {ref, owner}), {kind:'matched', position});
});

for (const alteration of ['run', 'authority', 'namespace', 'owner', 'stream', 'scope']) {
  test(`Owner cursor ${alteration} mismatch cannot replay a different history`, async () => {
    const codec = await open();
    const cursor = codec.issue({ref, owner, position});
    const requested = {ref:{...ref}, owner:{...owner}};
    if (alteration === 'run') requested.ref.runDefinitionCid = cid('e');
    if (alteration === 'authority') requested.ref.authorityScopeCid = cid('e');
    if (alteration === 'namespace') requested.ref.namespaceId = 'namespace-é';
    if (alteration === 'owner') requested.owner.kind = 'delivery';
    if (alteration === 'stream') requested.owner.streamCid = cid('e');
    if (alteration === 'scope') requested.owner.scopeCid = cid('e');
    assert.deepEqual(codec.read(cursor, requested), {kind:'cursor_mismatch'});
  });
}

test('unsigned, modified and oversized cursors cannot acquire a history prefix', async () => {
  const codec = await open();
  const cursor = codec.issue({ref, owner, position});
  const [body, signature] = cursor.split('.');
  const altered = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  altered.position.revision = 1;
  for (const value of [body, `${Buffer.from(JSON.stringify(altered)).toString('base64url')}.${signature}`,
    cursor+'x', 'x'.repeat(8193)]) {
    assert.deepEqual(codec.read(value, {ref, owner}), {kind:'cursor_mismatch'});
  }
});

test('a changed signing installation cannot adopt an old cursor', async () => {
  const codec = await open();
  const cursor = codec.issue({ref, owner, position});
  const changed = generateKeyPairSync('ed25519');
  const {createClientOwnerCursorCodec} = await import('./client-owner-cursor.mjs');
  const other = createClientOwnerCursorCodec({privateKey:changed.privateKey, publicKey:changed.publicKey});
  assert.deepEqual(other.read(cursor, {ref, owner}), {kind:'cursor_mismatch'});
});

test('a signed cursor expiry is distinct from mismatch and Owner retention expiry', async () => {
  const {createClientOwnerCursorCodec} = await import('./client-owner-cursor.mjs');
  let clock=1000;
  const codec=createClientOwnerCursorCodec({...keys,now:()=>clock,maxAgeMs:50});
  const cursor=codec.issue({ref,owner,position});
  clock=1049;
  assert.deepEqual(codec.read(cursor,{ref,owner}),{kind:'matched',position});
  clock=1050;
  assert.deepEqual(codec.read(cursor,{ref,owner}),{kind:'cursor_expired'});
  // A foreign scope is still a mismatch; expiry is not an existence oracle.
  assert.deepEqual(codec.read(cursor,{ref:{...ref,runDefinitionCid:cid('e')},owner}),{kind:'cursor_mismatch'});
  const restarted=createClientOwnerCursorCodec({...keys,now:()=>clock,maxAgeMs:50});
  assert.deepEqual(restarted.read(cursor,{ref,owner}),{kind:'cursor_expired'});
});
