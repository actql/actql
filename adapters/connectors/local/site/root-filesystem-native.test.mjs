import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, readFileSync, renameSync, symlinkSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {openLocalFileRoot} from './root-filesystem.mjs';
import {prepareLocalFileWrite} from './root-file-writer.mjs';
import {prepareLocalStoredContentWrite} from './root-stored-content-writer.mjs';
import {openLocalPublicationStore} from '../../../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from '../../../host-common/publication-contract-control.fixture.mjs';
import {consumeStoredContentOriginal, closeStoredContentReaders} from '../../../host-node/generated-content-holding.mjs';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const require=createRequire(import.meta.url);
let scratch, native, fault;
const closed={outcome:'closed',errno:0};
test.before(async()=>{
  assert(['darwin','linux'].includes(process.platform));assert.equal(process.versions.node,'22.22.0');
  scratch=await createOwnedScratch({parent:join(root,'_build'),prefix:'local-files-native-',
    label:'Local descriptor-relative filesystem boundary',digests:()=>['original.node','fault.node']});
  const command=(file,args)=>{
    const result=spawnSync(file,args,{encoding:'utf8',timeout:120000});
    assert.equal(result.error,undefined);assert.equal(result.signal,null);
    assert.equal(result.status,0,JSON.stringify({file,args,stdout:result.stdout,stderr:result.stderr}));
    return result.stdout.trim();
  };
  const darwin=process.platform==='darwin';
  const compiler=darwin?command('xcrun',['--find','clang']):'/usr/bin/gcc';
  const platformArgs=darwin?['-D_DARWIN_C_SOURCE','-isysroot',command('xcrun',['--show-sdk-path']),
    '-bundle','-undefined','dynamic_lookup']:['-D_GNU_SOURCE','-shared','-fPIC'];
  function build(source,name){
    const output=join(scratch.path,name+'.node');
    command(compiler,['-std=c11','-Wall','-Wextra','-Werror','-O0','-g',
      ...platformArgs,'-DNAPI_VERSION=8','-DNODE_GYP_MODULE_NAME=actql_directory',
      '-I',resolve(dirname(process.execPath),'../include/node'),
      join(root,'adapters/host-node/native',source),'-o',output]);
    return require(output);
  }
  native=build(darwin?'directory-darwin.c':'local-files-linux.c','original');
  fault=build('fixtures/directory-close-fault.c','fault');
});
test.after(()=>{scratch?.passed();});
const directory=name=>{const path=join(scratch.path,name);mkdirSync(path);return path;};

// Actual Store/FD/native writer, with an explicit Run/Content selection fixture.
// These cases do not issue a Common Reference, Account decision or Effect claim.
async function storedWriteFixture(t, name, bytes, {beforeChunk, afterRead} = {}) {
  const path = directory(name);
  const digest = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
  const store = await openLocalPublicationStore({directory: join(path,'store'),
    storeAuthorityCid: digest(name), capacityBytes: 1048576, maxObjectBytes: 262144,
    maxObjects: 8, maxContractNodes: 256, maxContractDepth: 32},
  createPublicationContractControlFixture());
  const writer = store.createPreparedObjectWriter(bytes.length);
  await writer.append(bytes);
  const physical = await writer.seal(digest(bytes));
  const holding = {version:'actql-local-physical-holding/0.1',namespace:'content',
    holding_cid:digest(name+' holding'),manifest_cid:digest(name+' reference'),
    objects:[{cid:physical.cid,byte_count:bytes.length}]};
  await store.commitPhysicalHolding(holding,[physical.prepared]);
  const original = Object.freeze({holding,storeAuthorityCid:store.storeAuthorityCid});
  const binding = Object.freeze({}), readers = new Set();
  let live = true, child, chunks = 0;
  const content = Object.freeze({binding,current:()=>live});
  const select = value => live && value===binding ? original : undefined;
  const contentOwner = Object.freeze({storageForContent:select,
    storageCurrentForContent:(value,key)=>value===original && select(key)===original,
    async consumeContent(key,accept) {
      assert.strictEqual(select(key),original);
      const result = await consumeStoredContentOriginal({store,original,readers,accept:async chunk=>{
        await beforeChunk?.({chunk,index:chunks++,path});
        await accept(chunk);
      },assertCurrent(){assert.strictEqual(select(key),original);}});
      await afterRead?.({path});
      return result;
    }});
  t.after(async()=>{
    if(child!==undefined)assert.equal((await child.close()).pending,false);
    assert.equal(await closeStoredContentReaders(readers),true);
    await store.close();
  });
  return {path,store,readers,content,contentOwner,
    retire(){live=false;},
    prepare(options={}) {
      child=prepareLocalStoredContentWrite({native,rootPath:path,path:'result',
        temporaryName:'.stage',maxBytes:bytes.length,contentOwner,content,
        assertCurrent(){},...options});
      return child;
    }};
}

test('actual Local stored Content writes original Store pieces before publishing only the verified whole',async t=>{
  const bytes=Buffer.alloc(131073,0x61);bytes[65536]=0;bytes[131072]=0xff;
  let pieces=0;
  const f=await storedWriteFixture(t,'stored-content-original',bytes,{
    beforeChunk({chunk,path}) {
      pieces++;assert(chunk.length<=65536);assert.equal(existsSync(join(path,'result')),false);
    },afterRead({path}) {assert.equal(existsSync(join(path,'result')),false);}});
  const child=f.prepare();
  assert.equal(existsSync(join(f.path,'.stage')),false,'factory acquires no target FD');
  assert.deepEqual(await child.execute(),{path:'result',bytes:bytes.length});
  assert.equal(pieces,3);assert.deepEqual(readFileSync(join(f.path,'result')),bytes);
  assert.equal(f.readers.size,0);assert.equal((await child.close()).pending,false);
});

test('actual Local stored Content refuses retired or foreign original before file acquisition',async t=>{
  const f=await storedWriteFixture(t,'stored-content-foreign',Buffer.from('private bytes'));
  const child=f.prepare({content:{...f.content,binding:{...f.content.binding}}});
  await assert.rejects(child.execute(),{code:'OriginalEffectContentUnavailable'});
  assert.equal(existsSync(join(f.path,'.stage')),false);
  assert.equal(existsSync(join(f.path,'result')),false);
  assert.equal((await child.close()).pending,false);
  assert.throws(()=>child.execute(),{code:'LocalFileWriteAlreadyAttempted'});
});

test('actual Local stored Content close stays pending during original read and never publishes its prefix',async t=>{
  let enter,release;
  const entered=new Promise(resolve=>{enter=resolve;}),barrier=new Promise(resolve=>{release=resolve;});
  const f=await storedWriteFixture(t,'stored-content-stopping',Buffer.alloc(131073,0x62),{
    async beforeChunk(){enter();await barrier;}});
  const child=f.prepare(),flight=child.execute();
  const outcome=flight.then(()=>({ok:true}),error=>({error}));
  await entered;
  assert.equal((await child.close()).pending,true);
  assert.equal(await closeStoredContentReaders(f.readers),false);
  assert.equal(f.readers.size,1);
  release();
  assert.equal((await outcome).error?.code,'LocalFileWriteClosing');
  assert.equal(f.readers.size,0);
  assert.equal(existsSync(join(f.path,'result')),false);
  assert.equal((await child.close()).pending,false);
  assert.equal(existsSync(join(f.path,'.stage')),false);
});

test('actual Local write child defers acquisition, streams exact bytes and closes every original FD',()=>{
  const path=directory('writer-child');mkdirSync(join(path,'nested'));let checks=0;
  const bytes=Buffer.from('exact e\u0301\n');
  const child=prepareLocalFileWrite({native,rootPath:path,path:'nested/result.txt',
    temporaryName:'.stage',maxBytes:bytes.length,assertCurrent(){checks++;}});
  assert.deepEqual(child.status(),{pending:true});assert.equal(checks,0,'no covered I/O at factory time');
  child.start();child.write(bytes.subarray(0,3));child.write(bytes.subarray(3));
  assert.deepEqual(child.publish(),{path:'nested/result.txt',bytes:bytes.length});
  assert.deepEqual(readFileSync(join(path,'nested/result.txt')),bytes);
  assert.equal(child.close().pending,false);assert.equal(child.status().pending,false);
  assert.throws(()=>child.write(bytes),{code:'LocalFileWriteClosing'});
  assert.throws(()=>child.start(),{code:'LocalFileWriteAlreadyAttempted'});
});

test('actual Local write child keeps acquired cleanup before current refusal and never retries publish',()=>{
  const path=directory('writer-child-current');let checks=0;
  const stopped=Object.assign(new Error('current retired'),{code:'TestCurrentRetired'});
  const child=prepareLocalFileWrite({native,rootPath:path,path:'result',temporaryName:'.stage',
    maxBytes:8,assertCurrent(){if(++checks===5)throw stopped;}});
  assert.throws(()=>child.start(),error=>error===stopped);
  assert.equal(child.close().pending,false);assert.equal(existsSync(join(path,'.stage')),false);
  let publishes=0;
  const observedNative={...native,fileRootPublish(...args){publishes++;return native.fileRootPublish(...args);}};
  const pending=prepareLocalFileWrite({native:observedNative,rootPath:path,path:'result',temporaryName:'.again',
    maxBytes:8,assertCurrent(){}});
  pending.start();pending.write(Buffer.from('one'));writeFileSync(join(path,'result'),'keep');
  assert.throws(()=>pending.publish(),{code:'LocalFileDestinationExists'});
  assert.throws(()=>pending.publish(),{code:'LocalFileDestinationExists'});
  assert.equal(publishes,1,'the original failed publication is never attempted again');
  assert.equal(readFileSync(join(path,'result'),'utf8'),'keep');assert.equal(pending.close().pending,false);
});

test('actual Local write child retains exact POSIX names and rejects concurrently mutable byte backing',()=>{
  const path=directory('writer-child-exact'),name='exact\\e\u0301.txt';
  const child=prepareLocalFileWrite({native,rootPath:path,path:name,temporaryName:'.stage',
    maxBytes:3,assertCurrent(){}});
  child.start();child.write(Buffer.from('one'));assert.deepEqual(child.publish(),{path:name,bytes:3});
  assert.equal(child.close().pending,false);assert.equal(readFileSync(join(path,name),'utf8'),'one');
  const shared=prepareLocalFileWrite({native,rootPath:path,path:'never',temporaryName:'.shared',
    maxBytes:3,assertCurrent(){}});
  shared.start();
  assert.throws(()=>shared.write(Buffer.from(new SharedArrayBuffer(3))),{code:'InvalidLocalFileWriteBytes'});
  assert.equal(shared.close().pending,false);assert.equal(existsSync(join(path,'never')),false);
});

test('actual Local file write stages exact bounded bytes and atomically publishes only once',()=>{
  const path=directory('write'),sub=join(path,'sub');mkdirSync(sub);
  const root=native.openFileRoot(path),parent=native.openFileDirectory(root,'sub',1);
  const writer=native.openRootFileWriter(parent,'.original-stage','result.txt',8);
  assert.equal(native.fileRootCurrent(writer),undefined);
  assert.equal(existsSync(join(sub,'result.txt')),false,'staging does not publish a target');
  native.fileRootWrite(writer,Buffer.from('exact'));
  native.fileRootWrite(writer,Buffer.from('\n'));
  assert.throws(()=>native.fileRootWrite(writer,Buffer.from('more')),{code:'LocalFileWriteUnavailable'});
  assert.equal(native.fileRootStat(writer).size,6n);
  native.fileRootPublish(writer,false);
  assert.equal(existsSync(join(sub,'.original-stage')),false);
  assert.deepEqual(readFileSync(join(sub,'result.txt')),Buffer.from('exact\n'));
  assert.throws(()=>native.fileRootPublish(writer,false),{code:'LocalFileWriteUnavailable'});
  assert.throws(()=>native.fileRootWrite(writer,Buffer.from('!')),{code:'LocalFileWriteUnavailable'});
  assert.deepEqual(native.fileRootClose(writer),closed);
  assert.deepEqual(native.fileRootClose(parent),closed);
  assert.deepEqual(native.fileRootClose(root),closed);
});

test('actual Local create refuses an existing destination, abort removes only its original staging file',()=>{
  const path=directory('create-only');writeFileSync(join(path,'result'),'old');
  const root=native.openFileRoot(path),writer=native.openRootFileWriter(root,'.stage','result',4);
  native.fileRootWrite(writer,Buffer.from('new'));
  assert.throws(()=>native.fileRootPublish(writer,false),{code:'LocalFileDestinationExists'});
  assert.equal(readFileSync(join(path,'result'),'utf8'),'old');
  assert.deepEqual(native.fileRootClose(root),{outcome:'pending',errno:0});
  // Parent stopping blocks more work, not cleanup of its same acquired child.
  assert.deepEqual(native.fileRootClose(writer),closed);
  assert.equal(existsSync(join(path,'.stage')),false);
  assert.deepEqual(native.fileRootClose(root),closed);
});

test('actual Local abort and explicit replacement preserve original directory and symlink boundaries',()=>{
  const path=directory('replace'),outside=directory('write-outside');
  writeFileSync(join(outside,'keep'),'outside');symlinkSync(join(outside,'keep'),join(path,'result'));
  const root=native.openFileRoot(path);
  const abort=native.openRootFileWriter(root,'.aborted','unused',4);
  native.fileRootWrite(abort,Buffer.from('temp'));
  assert.deepEqual(native.fileRootClose(abort),closed);
  assert.equal(existsSync(join(path,'.aborted')),false);assert.equal(existsSync(join(path,'unused')),false);
  const writer=native.openRootFileWriter(root,'.stage','result',4);
  native.fileRootWrite(writer,Buffer.from('new'));native.fileRootPublish(writer,true);
  assert.deepEqual(native.fileRootClose(writer),closed);
  assert.equal(readFileSync(join(path,'result'),'utf8'),'new');
  assert.equal(readFileSync(join(outside,'keep'),'utf8'),'outside','rename replaces an entry, never follows it');
  assert.deepEqual(native.fileRootClose(root),closed);
});

test('actual Local writer retains failed-open cleanup and serializes same-root writers',()=>{
  const path=directory('writer-custody'),root=native.openFileRoot(path);
  const first=native.openRootFileWriter(root,'.first','one',4);
  const independent=native.openFileRoot(path);
  const foreignLock=native.openRootFileWriter(independent,'.other-host','other',4);
  assert.throws(()=>native.fileRootCurrent(foreignLock),{code:'LocalFileOriginalChanged'});
  assert.equal(existsSync(join(path,'.other-host')),false);
  assert.deepEqual(native.fileRootClose(foreignLock),closed);
  assert.deepEqual(native.fileRootClose(independent),closed);
  const blocked=native.openRootFileWriter(root,'.second','two',4);
  assert.throws(()=>native.fileRootCurrent(blocked),{code:'LocalFileOriginalChanged'});
  assert.equal(existsSync(join(path,'.second')),false);
  assert.deepEqual(native.fileRootClose(blocked),closed);
  assert.deepEqual(native.fileRootClose(first),closed);
  writeFileSync(join(path,'.collision'),'keep');
  const collision=native.openRootFileWriter(root,'.collision','three',4);
  assert.throws(()=>native.fileRootCurrent(collision),{code:'LocalFileOriginalChanged'});
  assert.deepEqual(native.fileRootClose(collision),closed);
  assert.equal(readFileSync(join(path,'.collision'),'utf8'),'keep');
  const empty=native.openRootFileWriter(root,'.empty','empty',1);
  native.fileRootPublish(empty,false);assert.equal(readFileSync(join(path,'empty')).length,0);
  assert.deepEqual(native.fileRootClose(empty),closed);
  for(const candidate of [{...root},Object.create(root)])
    assert.throws(()=>native.openRootFileWriter(candidate,'.copy','copy',1),{code:'ForeignLocalFileRoot'});
  for(const name of ['../escape','/escape','..','.','bad\0name'])
    assert.throws(()=>native.openRootFileWriter(root,'.bad',name,1),{code:'InvalidLocalFileWrite'});
  assert.deepEqual(native.fileRootClose(root),closed);
});

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
