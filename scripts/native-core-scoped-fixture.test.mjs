import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {closeSync, fstatSync, mkdirSync, mkdtempSync, openSync, readSync,
  readdirSync, realpathSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {nativeCoreOrdinaryProcessFixture, nativeCoreScopedFixture} from './native-core-scoped-fixture.mjs';

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-scoped-case-fixture-')));
  t.after(() => rmSync(root, {recursive:true, force:true}));
  return root;
}
const libraries = {cryptoLibrary: '/actual/crypto.dylib', sqliteLibrary: '/usr/lib/libsqlite3.dylib'};

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
      ['initialization-original.backing',64],['initialization-budget-refused.backing',64],
      ['consumer-current.backing',64],['consumer-managed-graph.backing',64],
      ['consumer-alias.backing',64],['consumer-usage-alias.backing',64],
      ['consumer-serial.backing',64],['consumer-entry-first.backing',64],
      ['consumer-entry-second.backing',64],['consumer-leave-refused.backing',64],
      ['consumer-serial-alias.backing',64],['root-binding-first.backing',64],['root-binding-second.backing',64],
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


test('ordinary installed process inputs retain exact nine backings without selecting a provider or slot', t => {
  const root=fixture(t), env=nativeCoreOrdinaryProcessFixture(root);
  assert.deepEqual(env,{ACTQL_TEST_INSTALLED_PROCESS_ROOT:join(root,'installed-process')});
  const path=env.ACTQL_TEST_INSTALLED_PROCESS_ROOT;
  const names=['initial-domain','installed-process-prepared','installed-process-closing',
    'installed-process-foreign','installed-process-small-envelope','installed-process-capture-refusal',
    'installed-process-known-spawn-refusal','installed-process-captured-descriptor',
    'installed-process-stopped-child'];
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
