import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync, renameSync, symlinkSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const require=createRequire(import.meta.url);
let scratch, native, fault;
const closed={outcome:'closed',errno:0};
test.before(async()=>{
  assert.equal(process.platform,'darwin');assert.equal(process.versions.node,'22.22.0');
  scratch=await createOwnedScratch({parent:join(root,'_build'),prefix:'local-files-native-',
    label:'Local descriptor-relative filesystem boundary',digests:()=>['original.node','fault.node']});
  const command=(file,args)=>{
    const result=spawnSync(file,args,{encoding:'utf8',timeout:120000});
    assert.equal(result.error,undefined);assert.equal(result.signal,null);
    assert.equal(result.status,0,JSON.stringify({file,args,stdout:result.stdout,stderr:result.stderr}));
    return result.stdout.trim();
  };
  const compiler=command('xcrun',['--find','clang']),sdk=command('xcrun',['--show-sdk-path']);
  function build(source,name){
    const output=join(scratch.path,name+'.node');
    command(compiler,['-std=c11','-D_DARWIN_C_SOURCE','-Wall','-Wextra','-Werror','-O0','-g',
      '-isysroot',sdk,'-DNAPI_VERSION=8','-DNODE_GYP_MODULE_NAME=actql_directory',
      '-bundle','-undefined','dynamic_lookup','-I',resolve(dirname(process.execPath),'../include/node'),
      join(root,'adapters/host-node/native',source),'-o',output]);
    return require(output);
  }
  native=build('directory-darwin.c','original');
  fault=build('fixtures/directory-close-fault.c','fault');
});
test.after(()=>{scratch?.passed();});
const directory=name=>{const path=join(scratch.path,name);mkdirSync(path);return path;};

test('actual root opens nested file by original directory FDs, returns exact metadata and copied chunks',()=>{
  const path=directory('nested'),child=join(path,'sub');mkdirSync(child);
  const bytes=Buffer.from('\uFEFFexact e\u0301\n');writeFileSync(join(child,'e\u0301.txt'),bytes);
  const original=native.openFileRoot(path),dir=native.openFileDirectory(original,'sub',4);
  assert.equal(native.fileRootCurrent(original),undefined);
  assert.deepEqual(native.fileRootNext(dir),Buffer.from('e\u0301.txt'));
  assert.equal(native.fileRootNext(dir),null);
  const file=native.openRootFile(dir,'e\u0301.txt');
  const before=native.fileRootStat(file);assert.equal(before.size,BigInt(bytes.length));
  for(const value of Object.values(before))assert.equal(typeof value,'bigint');
  assert(Object.isFrozen(before));
  const read=native.fileRootRead(file,0,65536);assert.deepEqual(read,bytes);
  assert.deepEqual(native.fileRootStat(file),before);
  assert.deepEqual(native.fileRootRead(file,bytes.length,1),Buffer.alloc(0));
  assert.deepEqual(native.fileRootClose(original),{outcome:'pending',errno:0});
  assert.throws(()=>native.openRootFile(original,'late'),{code:'LocalFileOriginalChanged'});
  assert.throws(()=>native.fileRootCurrent(file),{code:'LocalFileOriginalChanged'});
  assert.deepEqual(native.fileRootClose(dir),{outcome:'pending',errno:0});
  assert.deepEqual(native.fileRootClose(file),closed);
  assert.deepEqual(read,bytes,'returned chunks are copies, not outstanding reader borrows');
  assert.deepEqual(native.fileRootClose(file),closed);
  assert.deepEqual(native.fileRootClose(dir),closed);
  assert.deepEqual(native.fileRootClose(original),closed);
  assert.throws(()=>native.fileRootRead(file,0,1),{code:'LocalFileOriginalChanged'});
});

test('copied, foreign-namespace and invalid path or read inputs cannot select another original',()=>{
  const path=directory('foreign');writeFileSync(join(path,'a'),'abc');
  const original=native.openFileRoot(path),file=native.openRootFile(original,'a');
  for(const foreign of [{},{...original},Object.create(original)]) {
    assert.throws(()=>native.fileRootCurrent(foreign),{code:'LocalFileOriginalChanged'});
    assert.throws(()=>native.fileRootClose(foreign),{code:'ForeignLocalFileRoot'});
  }
  assert.throws(()=>fault.operations.fileRootCurrent(original),{code:'LocalFileOriginalChanged'});
  for(const name of ['../a','/a','.','..','a\0b','\ud800'])
    assert.throws(()=>native.openRootFile(original,name),{code:'InvalidLocalFileChild'});
  for(const [offset,length] of [[-1,1],[NaN,1],[0,0],[0,65537],[0,1.5],[2**53,1]])
    assert.throws(()=>native.fileRootRead(file,offset,length),{code:'InvalidLocalFileReadBounds'});
  assert.deepEqual(native.fileRootClose(file),closed);assert.deepEqual(native.fileRootClose(original),closed);
});

test('symlink and nonregular children refuse without escape and failed opens retain reachable cleanup',()=>{
  const path=directory('links'),outside=directory('outside');
  writeFileSync(join(outside,'secret'),'not in the root');
  symlinkSync(outside,join(path,'escape'));symlinkSync(join(outside,'secret'),join(path,'link'));
  for(const [name,directory] of [['escape',true],['link',false],['absent',false]]){
    // Parent cleanup intentionally stops this original. Each independent
    // refusal therefore uses a new Root, not another acquisition after close.
    const original=native.openFileRoot(path);
    let child;
    try {
      child=directory?native.openFileDirectory(original,name,2):native.openRootFile(original,name);
      assert.throws(()=>native.fileRootCurrent(child),{code:'LocalFileOriginalChanged'});
      assert.deepEqual(native.fileRootClose(original),{outcome:'pending',errno:0});
    } finally {
      if(child!==undefined)assert.deepEqual(native.fileRootClose(child),closed);
      assert.deepEqual(native.fileRootClose(original),closed);
    }
  }
  const symlinkRoot=native.openFileRoot(join(path,'escape'));
  assert.throws(()=>native.fileRootCurrent(symlinkRoot),{code:'LocalFileOriginalChanged'});
  assert.deepEqual(native.fileRootClose(symlinkRoot),closed);
});

test('replacement of a file or ancestor refuses the same retained original',()=>{
  const path=directory('replacement');mkdirSync(join(path,'sub'));writeFileSync(join(path,'sub','a'),'before');
  const original=native.openFileRoot(path),dir=native.openFileDirectory(original,'sub',3);
  const file=native.openRootFile(dir,'a');
  renameSync(join(path,'sub','a'),join(path,'sub','old'));writeFileSync(join(path,'sub','a'),'after');
  assert.throws(()=>native.fileRootRead(file,0,1),{code:'LocalFileOriginalChanged'});
  assert.deepEqual(native.fileRootClose(file),closed);
  renameSync(join(path,'sub'),join(path,'moved'));mkdirSync(join(path,'sub'));
  assert.throws(()=>native.fileRootNext(dir),{code:'LocalFileOriginalChanged'});
  assert.deepEqual(native.fileRootClose(dir),closed);assert.deepEqual(native.fileRootClose(original),closed);
});

test('directory entry overflow fails rather than publishing a truncated listing',()=>{
  const path=directory('bounded');writeFileSync(join(path,'a'),'a');writeFileSync(join(path,'b'),'b');
  const original=native.openFileRoot(path),dir=native.openFileDirectory(original,'',1);
  assert(Buffer.isBuffer(native.fileRootNext(dir)));
  assert.throws(()=>native.fileRootNext(dir),{code:'LocalDirectoryEntryLimit'});
  assert.throws(()=>native.fileRootCurrent(dir),{code:'LocalFileOriginalChanged'});
  assert.deepEqual(native.fileRootClose(dir),closed);assert.deepEqual(native.fileRootClose(original),closed);
});

test('consumed close failure remains Unknown and does not retry a possibly recycled descriptor',()=>{
  const path=directory('unknown'),operations=fault.operations;
  const original=operations.openFileRoot(path);
  assert.equal(operations.fileRootCurrent(original),undefined);
  assert.deepEqual(operations.fileRootClose(original),{outcome:'unknown',errno:5});
  for(let index=0;index<3;index++)assert.deepEqual(operations.fileRootClose(original),{outcome:'unknown',errno:5});
  assert.equal(fault.attempts(),1);assert.equal(fault.physicallyClosed(),1);
  assert.throws(()=>operations.fileRootCurrent(original),{code:'LocalFileOriginalChanged'});
});
