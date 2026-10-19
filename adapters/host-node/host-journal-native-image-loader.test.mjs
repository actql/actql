// Matching-artifact mechanism diagnostic, not an operational admission. No
// compiler, Common runtime, installed Host or historical state is involved.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {closeSync, constants, fstatSync, fsyncSync, mkdirSync, openSync,
  readFileSync, unlinkSync, writeSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

test('private native image entry exposes one frozen operation without loading a native image', () => {
  const child = spawnSync(process.execPath, ['--input-type=commonjs', '-e', `
    const assert = require('node:assert/strict');
    const original = Object.getOwnPropertyDescriptor(process, 'dlopen');
    const entry = require(process.argv[1]);
    assert.deepEqual(Object.keys(entry), ['loadHostJournalDirectoryNative']);
    assert.equal(typeof entry.loadHostJournalDirectoryNative, 'function');
    assert.equal(Object.isFrozen(entry), true);
    assert.deepEqual(Object.getOwnPropertyDescriptor(process, 'dlopen'), original);
  `, fileURLToPath(new URL('./host-journal-native-image.cjs', import.meta.url))],
  {cwd: root, encoding: 'utf8', timeout: 10000});
  assert.equal(child.status, 0, child.stderr);
  assert.equal(child.signal, null);
});

test('selected Darwin Node initializes a private named image before unlinking its retained original', async () => {
  assert.equal(process.platform, 'darwin'); assert.equal(process.versions.node, '22.22.0');
  const selected = process.env.ACTQL_DIRECTORY_NATIVE_DIAGNOSTIC_ROOT;
  assert.ok(selected, 'select the already qualified native artifact; do not build another one');
  const original = JSON.parse(readFileSync(join(resolve(selected), '_build/native/directory-original.json')));
  assert.equal(original.node, process.versions.node); assert.equal(original.arch, process.arch);
  assert.equal(original.moduleAbi, process.versions.modules); assert.equal(original.napi, 8);
  assert.equal(original.source.sha256, sha(readFileSync(join(root, original.source.path))));
  const bytes = readFileSync(join(resolve(selected), original.binary.path));
  assert.equal(bytes.length, original.binary.bytes); assert.equal(sha(bytes), original.binary.sha256);
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'directory-native-fd-', label: 'selected native same-FD loader diagnostic'});
  const path = join(scratch.path, 'original.node');
  let writer, reader;
  try {
    writer = openSync(path, constants.O_CREAT | constants.O_EXCL | constants.O_RDWR |
      constants.O_NOFOLLOW | constants.O_CLOEXEC, 0o600);
    let offset = 0;
    while (offset < bytes.length) {
      const count = writeSync(writer, bytes, offset, bytes.length - offset, null);
      assert.ok(count > 0); offset += count;
    }
    fsyncSync(writer);
    reader = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_CLOEXEC);
    const first = fstatSync(writer, {bigint: true}), second = fstatSync(reader, {bigint: true});
    assert.equal(first.dev, second.dev); assert.equal(first.ino, second.ino);
    assert.equal(second.size, BigInt(bytes.length));
    assert.equal(closeSync(writer), undefined); writer = undefined;
    assert.equal(fstatSync(reader, {bigint: true}).nlink, 1n);
    const module = {exports: {}};
    // The ordinary named-image path is required by this platform's loader.
    // No OS policy, signature or protection setting is changed.
    process.dlopen(module, path);
    unlinkSync(path);
    assert.deepEqual(Object.keys(module.exports).sort(), ['close', 'current', 'next', 'open']);
    const directory = join(scratch.path, 'empty'); mkdirSync(directory);
    const handle = module.exports.open(directory, 1, 1024, 1024);
    assert.equal(module.exports.current(handle), undefined); assert.equal(module.exports.next(handle), null);
    assert.deepEqual(module.exports.close(handle), {outcome: 'closed', errno: 0});
    const after = fstatSync(reader, {bigint: true});
    assert.equal(after.dev, second.dev); assert.equal(after.ino, second.ino); assert.equal(after.nlink, 0n);
  } finally {
    if (writer !== undefined) closeSync(writer);
    if (reader !== undefined) closeSync(reader);
  }
  // Loaded module/image lifetime is separate from these successfully closed
  // temporary file descriptors and is not retired by this fixture cleanup.
  scratch.passed();
});

test('private image custody retains one actual native instance and fences detected loader replacement', () => {
  const selected = process.env.ACTQL_DIRECTORY_NATIVE_DIAGNOSTIC_ROOT;
  const expected = JSON.parse(readFileSync(join(selected, '_build/native/directory-original.json'))).binary;
  const {loadHostJournalDirectoryNative: load} = createRequire(import.meta.url)('./host-journal-native-image.cjs');
  const current = () => {};
  const limits = {maxImageBytes: expected.bytes, temporaryDirectory: tmpdir()};
  const image = load(selected, expected, limits, current);
  assert.equal(image.assertCurrent(), undefined);
  assert.equal(load(selected, expected, limits, current), image);
  assert.deepEqual(Object.keys(image.operations).sort(), ['close', 'current', 'next', 'open']);
  assert.throws(() => load(selected + '-foreign', expected, limits, current), {code: 'HostJournalNativeImageForeign'});
  assert.throws(() => load(selected, expected, {...limits, maxImageBytes: expected.bytes - 1}, current),
    {code: 'HostJournalNativeImageUnavailable'});
  let traps = 0;
  assert.throws(() => load(selected, new Proxy(expected, {getOwnPropertyDescriptor() {traps++;}}), limits, current),
    {code: 'HostJournalNativeImageUnavailable'});
  assert.equal(traps, 0);
  const dlopen = process.dlopen;
  try {
    process.dlopen = () => assert.fail('replacement loader must not run');
    assert.throws(() => image.assertCurrent(), {code: 'HostJournalNativeImageChanged'});
  } finally { process.dlopen = dlopen; }
  assert.throws(() => image.assertCurrent(), {code: 'HostJournalNativeImageChanged'});
});

function child(source) {
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', source,
    process.env.ACTQL_DIRECTORY_NATIVE_DIAGNOSTIC_ROOT,
    fileURLToPath(new URL('./host-journal-native-image.cjs', import.meta.url))],
  {encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024});
  assert.equal(result.status, 0, result.stdout + result.stderr);
  return JSON.parse(result.stdout.trim());
}
const prelude = `
  import fs from 'node:fs'; import assert from 'node:assert/strict';
  import {createRequire} from 'node:module'; import {join} from 'node:path'; import {tmpdir} from 'node:os';
  const root=process.argv[1]; const expected=JSON.parse(fs.readFileSync(join(root,'_build/native/directory-original.json'))).binary;
  const current=()=>{}; const limits={maxImageBytes:expected.bytes,temporaryDirectory:tmpdir()};
`;

test('actual source-FD consumed-close uncertainty prevents loading and is never retried', () => {
  const observed = child(prelude + `
    let closes=0, loads=0; const close=fs.closeSync, dlopen=process.dlopen;
    const refusal=new Error('InjectedConsumedSourceClose');
    fs.closeSync=function(fd){closes++;close(fd);throw refusal;};
    process.dlopen=function(...args){loads++;return Reflect.apply(dlopen,process,args);};
    const {loadHostJournalDirectoryNative:load}=createRequire(import.meta.url)(process.argv[2]);
    let failure; try{load(root,expected,limits,current);}catch(error){failure=error;}
    assert.equal(failure.code,'HostJournalNativeImageCleanupPending');
    assert.equal(failure.cleanupHandle.retry().pending,true);
    assert.equal(failure.cleanupHandle.retry().pending,true);
    assert.throws(()=>load(root,expected,limits,current),error=>error===failure);
    assert.equal(closes,1);assert.equal(loads,0);
    fs.closeSync=close;process.dlopen=dlopen;
    console.log(JSON.stringify({closes,loads,pending:failure.cleanupHandle.status().pending}));
  `);
  assert.deepEqual(observed, {closes: 1, loads: 0, pending: true});
});

test('an error after actual native initialization keeps that original attempt without a replacement load', () => {
  const observed = child(prelude + `
    let loads=0; const dlopen=process.dlopen; const refusal=new Error('InjectedAfterNativeInitialization');
    process.dlopen=function(...args){loads++;Reflect.apply(dlopen,process,args);throw refusal;};
    const {loadHostJournalDirectoryNative:load}=createRequire(import.meta.url)(process.argv[2]);
    assert.throws(()=>load(root,expected,limits,current),error=>error===refusal);
    assert.throws(()=>load(root,expected,limits,current),error=>error===refusal);
    assert.equal(loads,1);process.dlopen=dlopen;
    console.log(JSON.stringify({loads,originalFailure:true}));
  `);
  assert.deepEqual(observed, {loads: 1, originalFailure: true});
});

test('initial current reentry observes the original initialization without a second load', () => {
  const observed = child(prelude + `
    let loads=0,entered=false; const dlopen=process.dlopen;
    process.dlopen=function(...args){loads++;return Reflect.apply(dlopen,process,args);};
    const {loadHostJournalDirectoryNative:load}=createRequire(import.meta.url)(process.argv[2]);
    const originalCurrent=()=>{if(!entered){entered=true;assert.throws(()=>load(root,expected,limits,originalCurrent),
      {code:'HostJournalNativeImagePending'});}};
    const image=load(root,expected,limits,originalCurrent);image.assertCurrent();
    assert.equal(loads,1);process.dlopen=dlopen;
    console.log(JSON.stringify({loads,entered}));
  `);
  assert.deepEqual(observed, {loads: 1, entered: true});
});

test('even an undefined current throw remains the original failed attempt before image acquisition', () => {
  const observed = child(prelude + `
    let loads=0,failures=0; const dlopen=process.dlopen;
    process.dlopen=function(...args){loads++;return Reflect.apply(dlopen,process,args);};
    const {loadHostJournalDirectoryNative:load}=createRequire(import.meta.url)(process.argv[2]);
    const stopped=()=>{throw undefined;};
    for(let i=0;i<2;i++){try{load(root,expected,limits,stopped);}catch(error){assert.equal(error,undefined);failures++;}}
    assert.equal(failures,2);assert.equal(loads,0);process.dlopen=dlopen;
    console.log(JSON.stringify({loads,failures}));
  `);
  assert.deepEqual(observed, {loads: 0, failures: 2});
});
