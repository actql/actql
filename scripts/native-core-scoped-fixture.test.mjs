import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {closeSync, fstatSync, mkdirSync, mkdtempSync, openSync, readSync,
  readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {nativeProjectConfigurationFixture} from './native-project-configuration-fixture.mjs';
import {nativeCoreOrdinaryProcessFixture, nativeCoreScopedFixture, nativeRelationFileCaptureFixture, nativeCoreModelFrameFixture} from './native-core-scoped-fixture.mjs';
import {nativeRelationCaptureTestFiles, nativeScopedTestFiles, nativeCoreScopedAllocationProfile} from './native-core-test-selection.mjs';

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-scoped-case-fixture-')));
  t.after(() => rmSync(root, {recursive:true, force:true}));
  return root;
}
const libraries = {cryptoLibrary: '/actual/crypto.dylib', sqliteLibrary: '/usr/lib/libsqlite3.dylib'};

test('Model frame fixtures retain real private backings without selecting unused components', t => {
  const root = fixture(t), environment = nativeCoreModelFrameFixture(root);
  const path = join(root, 'installed-process');
  assert.deepEqual(environment, {ACTQL_TEST_INSTALLED_PROCESS_ROOT: path});
  assert.deepEqual(readdirSync(path).sort(), ['source-frame-left.backing',
    'source-frame-original.backing', 'source-frame-right.backing']);
  const page = Number(execFileSync('/usr/bin/getconf', ['PAGESIZE'], {encoding: 'utf8'}).trim());
  for (const name of readdirSync(path)) {
    const fd = openSync(join(path, name), 2);
    try {
      assert.equal(fstatSync(fd).mode & 0o777, 0o600);
      assert.equal(fstatSync(fd).size, 64 * page);
      const original = Buffer.alloc(128, 1);
      assert.equal(readSync(fd, original, 0, original.length, 0), original.length);
      assert.deepEqual(original, Buffer.alloc(128));
    } finally {closeSync(fd);}
  }
  assert.throws(() => nativeCoreModelFrameFixture(root), {code: 'EEXIST'});
});

test('selected physical case inputs use actual pages, exact private backing sizes and original library selections', t => {
  const root = fixture(t);
  const page = Number(execFileSync('/usr/bin/getconf', ['PAGESIZE'], {encoding:'utf8'}).trim());
  for (const backingPages of [256, 8192]) {
    const namespace = join(root, String(backingPages));mkdirSync(namespace, {mode:0o700});
    const env = nativeCoreScopedFixture(namespace, {...libraries, backingPages});
    assert.deepEqual(env, {
      ACTQL_TEST_INSTALLED_PROCESS_ROOT:join(namespace, 'installed-process'),
      ACTQL_TEST_CRYPTO_COMPONENT:libraries.cryptoLibrary,
      ACTQL_TEST_SQLITE_COMPONENT:libraries.sqliteLibrary,
    });
    const path = env.ACTQL_TEST_INSTALLED_PROCESS_ROOT;
    assert.equal(statSync(path).mode & 0o777, 0o700);
    const expected = new Map([
      ['backing',backingPages],['backing-0',256],['backing-3',256],['backing-4',256],
      ['extent-backing-0',256],['extent-backing-1',256],['extent-backing-2',256],
      ['initialization-original.backing',64],['initialization-budget-refused.backing',64],
      ['request-original.backing',64],['request-run-transfer.backing',64],['request-unstarted.backing',64],
      ['common-request-entrance.backing',64],
      ['source-frame-original.backing',64],['source-frame-left.backing',64],['source-frame-right.backing',64],
      ['consumer-current.backing',64],['consumer-managed-graph.backing',64],
      ['consumer-alias.backing',64],['consumer-usage-alias.backing',64],
      ['consumer-serial.backing',64],['consumer-entry-first.backing',64],
      ['consumer-entry-second.backing',64],['consumer-leave-refused.backing',64],
      ['consumer-serial-alias.backing',64],['consumer-working-growth.backing',64],['root-binding-first.backing',64],['root-binding-second.backing',64],
    ]);
    assert.deepEqual(readdirSync(path).sort(), [...expected.keys(),'store'].sort());
    assert.equal(statSync(join(path, 'store')).mode & 0o777, 0o700);
    assert.deepEqual(readdirSync(join(path, 'store')), []);
    for (const [name,pages] of expected) {
      // The original cases use open(path,O_RDWR), not O_CREAT. Verify that
      // exact entrance, its private descriptor and the fresh zero header.
      const fd = openSync(join(path,name),2);
      try {
        assert.equal(fstatSync(fd).mode & 0o777,0o600);
        assert.equal(fstatSync(fd).size,pages*page);
        const header=Buffer.alloc(128,1);
        assert.equal(readSync(fd,header,0,header.length,0),header.length);
        assert.deepEqual(header,Buffer.alloc(128));
      } finally {closeSync(fd);}
    }
  }
});

test('case fixture refuses to adopt or reset initialized backing and refuses an unauthored size', t => {
  const root=fixture(t), options={...libraries,backingPages:256};
  const env=nativeCoreScopedFixture(root,options);
  const file=join(env.ACTQL_TEST_INSTALLED_PROCESS_ROOT,'backing');
  writeFileSync(file,Buffer.from('same original initialized fixture'));
  const before=statSync(file);
  assert.throws(()=>nativeCoreScopedFixture(root,options),{code:'EEXIST'});
  assert.equal(statSync(file).ino,before.ino);
  assert.equal(statSync(file).size,before.size);
  for(const backingPages of [undefined,0,64,257,8193]) {
    assert.throws(()=>nativeCoreScopedFixture(root,{...libraries,backingPages}),/exact authored/u);
  }
  for(const cryptoLibrary of ['', 'relative', '/invalid\0library']) {
    assert.throws(()=>nativeCoreScopedFixture(root,{...options,cryptoLibrary}),/absolute component/u);
  }
});

test('relation capture has independent exact real-file inputs and never resets an existing namespace', t => {
  assert.deepEqual(nativeRelationCaptureTestFiles, [
    'src/platform_native/row_source/capture_physical_scoped_wbtest.mbt',
    'src/platform_native/row_source/listing_capture_physical_scoped_wbtest.mbt',
  ]);
  for (const source of nativeRelationCaptureTestFiles) {
    assert(nativeScopedTestFiles.includes(source));
    assert.equal(nativeCoreScopedAllocationProfile(source), 'scoped-review-values');
  }
  const namespace = fixture(t), env = nativeRelationFileCaptureFixture(namespace);
  const root = join(namespace, 'installed-process');
  assert.deepEqual(env, {ACTQL_TEST_INSTALLED_PROCESS_ROOT: root});
  assert.equal(statSync(root).mode & 0o777, 0o700);
  const sizes = {'row-source-input':62, 'row-source-large-input':70062, 'row-source-files':242, 'row-source-malformed':10,
    'row-source-oversized':8193, 'row-source-backing':384*1024**2};
  assert.deepEqual(readdirSync(root).sort(), Object.keys(sizes).sort());
  for (const [name, size] of Object.entries(sizes)) {
    const stat = statSync(join(root,name));
    assert(stat.isFile());assert.equal(stat.nlink,1);
    assert.equal(stat.mode & 0o777,0o600);assert.equal(stat.size,size);
  }
  assert.equal(readFileSync(join(root,'row-source-input'),'utf8'),
    '{"items":[{"id":"first","value":1},{"id":"second","value":2}]}');
  const large = readFileSync(join(root,'row-source-large-input'));
  assert.deepEqual(large.subarray(0,62), readFileSync(join(root,'row-source-input')));
  assert(large.subarray(62).every(byte => byte === 0x20));
  assert.deepEqual(JSON.parse(large.toString('utf8')),
    {items:[{id:'first',value:1},{id:'second',value:2}]});
  assert.deepEqual(JSON.parse(readFileSync(join(root,'row-source-files'),'utf8')), {items:[
    {id:'first',name:'Acme🌱',version:'label',media_type:'text/plain',body:'first\nnotes',path:null},
    {id:'second',name:'Globex',version:'label',media_type:'text/plain',body:'second notes',path:'notes/globex'},
  ]});
  assert.equal(readFileSync(join(root,'row-source-malformed'),'utf8'), '{"items":[');
  const backing = join(root,'row-source-backing');
  const fd = openSync(backing,2);
  try {
    const header=Buffer.alloc(128,1);
    assert.equal(readSync(fd,header,0,header.length,0),header.length);
    assert.deepEqual(header,Buffer.alloc(128));
  } finally {closeSync(fd);}
  writeFileSync(backing, 'initialized owner');
  const before=statSync(backing);
  assert.throws(()=>nativeRelationFileCaptureFixture(namespace),{code:'EEXIST'});
  assert.equal(statSync(backing).ino,before.ino);
  assert.equal(readFileSync(backing,'utf8'),'initialized owner');
});

test('ordinary installed process inputs retain exact authored backings without selecting a provider or slot', t => {
  const root=fixture(t), env=nativeCoreOrdinaryProcessFixture(root);
  assert.deepEqual(env,{ACTQL_TEST_INSTALLED_PROCESS_ROOT:join(root,'installed-process')});
  const path=env.ACTQL_TEST_INSTALLED_PROCESS_ROOT;
  const names=['initial-domain','installed-process-prepared','installed-process-closing',
    'installed-process-foreign','installed-process-small-envelope','installed-process-capture-refusal',
    'installed-process-known-spawn-refusal','installed-process-captured-descriptor',
    'installed-process-stopped-child','installed-child-byte-transport','installed-child-stop-request','installed-child-stop-preflight','installed-child-fd4','installed-child-known-failure','installed-child-preflight'];
  assert.equal(statSync(path).mode & 0o777,0o700);
  assert.deepEqual(readdirSync(path).sort(),names.map(name=>name+'.backing').sort());
  const page=Number(execFileSync('/usr/bin/getconf',['PAGESIZE'],{encoding:'utf8'}).trim());
  for(const name of names) {
    const fd=openSync(join(path,name+'.backing'),2);
    try {
      assert.equal(fstatSync(fd).mode & 0o777,0o600);
      assert.equal(fstatSync(fd).size,64*page);
      const header=Buffer.alloc(128,1);
      assert.equal(readSync(fd,header,0,header.length,0),header.length);
      assert.deepEqual(header,Buffer.alloc(128));
    } finally {closeSync(fd);}
    assert.equal(readdirSync(path).includes(name+'.slot'),false);
  }
  const file=join(path,names[0]+'.backing');
  writeFileSync(file,'same initialized original');
  const before=statSync(file);
  assert.throws(()=>nativeCoreOrdinaryProcessFixture(root),{code:'EEXIST'});
  assert.equal(statSync(file).ino,before.ino);
  assert.equal(statSync(file).size,before.size);
});


test('canonical Project fixture supplies the original File-facts consumer oracle without payload data', t => {
  const root = fixture(t), environment = nativeProjectConfigurationFixture(root);
  const project = join(environment.ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT, 'deal-review-missing');
  assert.throws(() => statSync(join(project, 'mock/data.json')), {code: 'ENOENT'});
  const catalog = readFileSync(join(project, 'mock/catalog.json'), 'utf8');
  // Explicit ASCII-key canonical preimage, independent of the Native product.
  const preimage = '{"catalog":' + JSON.stringify(catalog) + ',"connection":"drive","connector":"drive","dataPath":' +
    JSON.stringify(join(project, 'mock/data.json')) + '}';
  assert.equal(environment.ACTQL_TEST_NATIVE_MOCK_DRIVE_SCOPE_CID,
    'sha256:' + createHash('sha256').update(preimage).digest('hex'));
  assert.equal(environment.ACTQL_TEST_NATIVE_MOCK_FILE_DATA,
    readFileSync(join(environment.ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT, 'deal-review/mock/data.json'), 'utf8'));
  assert.deepEqual(JSON.parse(environment.ACTQL_TEST_NATIVE_MOCK_FILE_DATA).drive.files.rows.map(row => row.id),
    ['file-acme-notes', 'file-globex-notes']);
  const identity = '{"collection":"files","identity":"file-acme-notes","scope":' +
    JSON.stringify(environment.ACTQL_TEST_NATIVE_MOCK_DRIVE_SCOPE_CID) + '}';
  assert.equal(environment.ACTQL_TEST_NATIVE_MOCK_FIRST_RESOURCE_CID,
    'sha256:' + createHash('sha256').update(identity).digest('hex'));
  assert.throws(() => statSync(join(project, 'mock/data.json')), {code: 'ENOENT'});
});
