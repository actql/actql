import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync, renameSync, symlinkSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {openLocalFileRoot} from './root-filesystem.mjs';

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

const limits=Object.freeze({maxEntries:16,maxDepth:4,maxPathBytes:256,maxFiles:8,
  maxFileBytes:131072,maxReadBytes:524288});
test('actual Local consumer lists original files and pins exact content version through its same Root',async()=>{
  const path=directory('consumer');mkdirSync(join(path,'inbound'));
  const bytes=Buffer.from('\uFEFForiginal e\u0301\n');writeFileSync(join(path,'inbound','one.txt'),bytes);
  writeFileSync(join(path,'empty.txt'),'');
  const outside=directory('consumer-outside');writeFileSync(join(outside,'secret'),'not in root');
  symlinkSync(outside,join(path,'not-a-descendant'));
  const filesystem=openLocalFileRoot({native,path,assertCurrent(){}});
  const listing=filesystem.openReader({limits,assertCurrent(){}}),rows=[];
  try {
    await listing.list({contentVersion:true,onFile(row){rows.push(row);}});
    assert.deepEqual(rows.map(row=>row.path).sort(),['empty.txt','inbound/one.txt']);
    const original=rows.find(row=>row.path==='inbound/one.txt');
    assert.equal(original.version,'sha256:'+createHash('sha256').update(bytes).digest('hex'));
    assert.equal(original.metadata.size,BigInt(bytes.length));
    assert.equal(listing.close().pending,false);
    const content=filesystem.openReader({limits,assertCurrent(){}});
    try {
      const observed=await content.read(original.path,{contentVersion:true,expectedVersion:original.version});
      assert.deepEqual(observed.bytes,bytes);assert.deepEqual(observed.metadata,original.metadata);
      assert.equal(content.close().pending,false);
      assert.deepEqual(observed.bytes,bytes,'copied returned data survives acknowledged physical Reader close');
    } finally {assert.equal(content.close().pending,false);}
  } finally {assert.equal(listing.close().pending,false);assert.equal(filesystem.close().pending,false);}
});

test('actual Local consumer keeps in-flight child pending and closes it after original callback settles',async()=>{
  const path=directory('consumer-pending');writeFileSync(join(path,'one'),'one');
  const filesystem=openLocalFileRoot({native,path,assertCurrent(){}});
  const reader=filesystem.openReader({limits,assertCurrent(){}});
  let enter,release;
  const entered=new Promise(resolve=>{enter=resolve;}),barrier=new Promise(resolve=>{release=resolve;});
  const flight=reader.list({async onFile(){enter();await barrier;}});
  const outcome=flight.then(()=>({ok:true}),error=>({error}));
  await entered;
  assert.equal(filesystem.close().pending,true);
  assert.equal(reader.status().pending,true);
  release();
  const stopped=await outcome;assert.equal(stopped.error?.code,'LocalFileRootClosing');
  assert.equal(reader.close().pending,false);assert.equal(filesystem.close().pending,false);
  assert.throws(()=>filesystem.openReader({limits,assertCurrent(){}}),{code:'LocalFileRootClosing'});
});

test('actual Local consumer refuses bounds and wrong versions without losing original cleanup',async()=>{
  const path=directory('consumer-refusal');writeFileSync(join(path,'one'),'one');
  const filesystem=openLocalFileRoot({native,path,assertCurrent(){}});
  for(const bad of [{...limits,maxFiles:0},Object.create(limits),{...limits,extra:1}])
    assert.throws(()=>filesystem.openReader({limits:bad,assertCurrent(){}}),{code:'InvalidLocalFileReadLimits'});
  const bounded=filesystem.openReader({limits:{...limits,maxFileBytes:2},assertCurrent(){}});
  await assert.rejects(bounded.read('one'),{code:'LocalFileBytesLimit'});
  assert.equal(bounded.close().pending,false);
  const stale=filesystem.openReader({limits,assertCurrent(){}});
  await assert.rejects(stale.read('one',{contentVersion:true,expectedVersion:'sha256:'+'0'.repeat(64)}),{code:'LocalFileVersionConflict'});
  assert.equal(stale.close().pending,false);assert.equal(filesystem.close().pending,false);
  const attempts=fault.attempts(),physicallyClosed=fault.physicallyClosed();let checks=0,carrier;
  assert.throws(()=>openLocalFileRoot({native:fault.operations,path,assertCurrent(){
    if(++checks===2)throw Object.assign(new Error('current changed'),{code:'TestCurrentChanged'});
  }}),error=>{carrier=error;return error.code==='LocalFileRootCleanupPending';});
  assert.equal(carrier.cause.code,'TestCurrentChanged');
  assert.equal(carrier.cleanupHandle.status().pending,true);
  for(let index=0;index<3;index++)assert.equal(carrier.cleanupHandle.retry().pending,true);
  assert.equal(fault.attempts(),attempts+1);assert.equal(fault.physicallyClosed(),physicallyClosed+1);
});
