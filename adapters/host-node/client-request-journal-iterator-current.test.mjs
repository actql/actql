// Native SQLite's iterate entry reads these two JS originals. This is a
// selected facility/currentness diagnostic, not a Journal admission or grant.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {parse} from 'acorn';
import test from 'node:test';

const prefix = readFileSync(new URL('./node-public-initial-control-bootstrap.cjs', import.meta.url), 'utf8');
const capture = parse(prefix, {ecmaVersion: 'latest', sourceType: 'script'}).body
  .filter(node => node.type === 'FunctionDeclaration' && node.id.name === 'captureJournalNativeBindings');
assert.equal(capture.length, 1);
const captureBody = prefix.slice(capture[0].start, capture[0].end);
const setup = `
  import assert from 'node:assert/strict';
  import fs from 'node:fs';import crypto from 'node:crypto';
  import {DatabaseSync,StatementSync} from 'node:sqlite';
  import {types} from 'node:util';import {compileFunction} from 'node:vm';
  import journalFacilityFields from ${JSON.stringify(new URL('./host-journal-facility-fields.cjs', import.meta.url).href)};
  import {assertOriginalClientRequestJournalFacilityCurrent as current}
    from ${JSON.stringify(new URL('./client-request-journal.mjs', import.meta.url).href)};
  const descriptor=Object.getOwnPropertyDescriptor,freeze=Object.freeze;
  const field=(value,name)=>{const p=value===undefined?undefined:descriptor(value,name);
    if(p===undefined||!Object.hasOwn(p,'value'))throw Object.assign(new Error('Unavailable'),
      {code:'NodeInitialControlAdmissionUnavailable'});return p.value;};
  const make=compileFunction(${JSON.stringify(captureBody + '\nreturn captureJournalNativeBindings;')},
    ['descriptor','field','freeze','isProxy','journalFacilityFields','unavailable']);
  const capture=make(descriptor,field,freeze,types.isProxy,journalFacilityFields,
    ()=>{throw Object.assign(new Error('Unavailable'),{code:'NodeInitialControlAdmissionUnavailable'});});
  const original=descriptor(globalThis,'Iterator');
  assert.equal(typeof original?.value,'function');
  const held=capture(fs,crypto,fs.promises);
  current(DatabaseSync,StatementSync,held);
`;
function child(body) {
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', setup + body],
    {cwd: fileURLToPath(new URL('../../', import.meta.url)), encoding: 'utf8', timeout: 15000});
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.signal, null);
}

test('selected native Iterator getter is refused before invocation and restoration cannot revive currentness', () => {
  child(`
    // First establish the selected native call's actual global lookup in an
    // explicitly unaccounted in-memory diagnostic, then restore its original.
    const db=new DatabaseSync(':memory:');let reads=0;
    Object.defineProperty(globalThis,'Iterator',{configurable:true,enumerable:original.enumerable,
      get(){reads++;return original.value;}});
    try {const row=db.prepare('SELECT 1 AS value').iterate().next();
      assert.equal(row.value.value,1);assert.equal(reads,1);}
    finally {Object.defineProperty(globalThis,'Iterator',original);db.close();}
    current(DatabaseSync,StatementSync,held);reads=0;
    try {
      Object.defineProperty(globalThis,'Iterator',{configurable:true,enumerable:original.enumerable,
        get(){reads++;return original.value;}});
      assert.throws(()=>current(DatabaseSync,StatementSync,held),
        {code:'ClientRequestJournalFacilityUnavailable'});
      assert.equal(reads,0);
    } finally {Object.defineProperty(globalThis,'Iterator',original);}
    assert.throws(()=>current(DatabaseSync,StatementSync,held),
      {code:'ClientRequestJournalFacilityUnavailable'});
  `);
});

test('early native Iterator capture refuses accessor and Proxy without prototype traps', () => {
  child(`
    let reads=0;
    try {
      Object.defineProperty(globalThis,'Iterator',{configurable:true,enumerable:original.enumerable,
        get(){reads++;throw Error('MustNotCallGetter');}});
      assert.throws(()=>capture(fs,crypto,fs.promises),
        {code:'NodeInitialControlAdmissionUnavailable'});
      Object.defineProperty(globalThis,'Iterator',{...original,value:new Proxy(original.value,{
        getOwnPropertyDescriptor(){reads++;throw Error('MustNotCallPrototypeTrap');},
        get(){reads++;throw Error('MustNotReadPrototype');}})});
      assert.throws(()=>capture(fs,crypto,fs.promises),
        {code:'NodeInitialControlAdmissionUnavailable'});
      assert.equal(reads,0);
    } finally {Object.defineProperty(globalThis,'Iterator',original);}
  `);
});

test('same earlier native Iterator constructor and prototype are required independently of table shape', () => {
  child(`
    for(const foreign of [
      {...held,iteratorGlobal:{Iterator:function Iterator(){}}},
      {...held,iteratorConstructor:{prototype:{}}},
    ])assert.throws(()=>current(DatabaseSync,StatementSync,foreign),
      {code:'ClientRequestJournalFacilityUnavailable'});
    // A foreign receipt cannot poison the real original's currentness.
    assert.equal(current(DatabaseSync,StatementSync,held),undefined);
    const db=new DatabaseSync(':memory:');
    try {assert.equal(db.prepare('SELECT 2 AS value').iterate().next().value.value,2);}
    finally {db.close();}
  `);
});
