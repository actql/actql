import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,open,lstat,writeFile,rm,link} from 'node:fs/promises';
import {readFileSync,constants} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {compileFunction} from 'node:vm';
import {createHash} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {parse} from 'acorn';
import {PublicationStoreError} from '../store-local/publication-store.mjs';
import {openDeliveryAttemptIndex} from '../store-local/delivery-attempt-index.mjs';
import {createLocalResultReadWorkspace} from './local-result-read-workspace.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import * as access from '../host-common/result-access.mjs';
import {createResultDeliveryFixture} from '../../scripts/fixtures/result-delivery-acceptance.mjs';
const raw = await import(process.env.ACTQL_RESULT_READ_COMMON_MODULE ??
  new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href);
const cid = value => 'sha256:'+value.repeat(64);
function owner(bytes=16*1024*1024) {
  const parents=[];
  const runtime=Object.freeze({...raw,clientProgramBeginRequestPreparation(...args) {
    const result=Reflect.apply(raw.clientProgramBeginRequestPreparation,raw,args);
    parents.push(runtimeField(result,0));return result;
  }});
  const workspace=createLocalResultReadWorkspace({runtime,requestMemory:Object.freeze({retainedBytes:bytes,executionBytes:bytes}),assertCurrent(){}});
  const request=Object.freeze({result:'answer',attempt:'metadata'});
  const reserved=()=>{const value=raw.clientProgramRequestPreparationAccounting(parents[0]);return [runtimeField(value,0),runtimeField(value,1)];};
  return {workspace,request,reserved};
}
const source=readFileSync(new URL('../store-local/publication-store.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const reader=ast.body.find(node=>node.type==='FunctionDeclaration'&&node.id.name==='readBounded');
const originalExpression=name=>{
  const declaration=ast.body.filter(node=>node.type==='VariableDeclaration').flatMap(node=>node.declarations)
    .find(node=>node.id.name===name);
  assert(declaration);return source.slice(declaration.init.start,declaration.init.end);
};
// Execute the exact existing private FD reader body with real filesystem ports,
// not a second reader algorithm or an exported test-only production helper.
function fdReader(onAllocate,openOriginal=open) {
  const fail=compileFunction('return ('+originalExpression('fail')+');',['PublicationStoreError'])(PublicationStoreError);
  const quantity=compileFunction('return ('+originalExpression('quantity')+');',[])();
  return compileFunction('return ('+source.slice(reader.start,reader.end)+');',
    ['quantity','fail','open','constants','lstat','Buffer','originalApply'])(quantity,fail,openOriginal,constants,lstat,
    {allocUnsafeSlow(bytes){onAllocate(bytes);return Buffer.allocUnsafeSlow(bytes);}},Reflect.apply);
}
async function directory(t,beforeRemove=()=>{}) {const dir=await mkdtemp(join(tmpdir(),'actql-read-metadata-'));t.after(async()=>{await beforeRemove();await rm(dir,{recursive:true,force:true});});return dir;}

test('metadata SAME FD extent reserves actual bytes before buffer construction and JSON admission',async t=>{
  const dir=await directory(t),path=join(dir,'schema.json');await writeFile(path,'{"é":7}');
  const o=owner();o.workspace.begin(o.request);const before=o.reserved(),demand=[],alloc=[];
  const read=fdReader(bytes=>{alloc.push(bytes);assert.equal(o.reserved()[0]-before[0],1392n);});
  const bytes=await read(path,1024,undefined,undefined,false,extent=>{demand.push(extent);o.workspace.metadata(o.request,extent);});
  assert.deepEqual(demand,[8]);assert.deepEqual(alloc,[8,1]);assert.equal(bytes.toString(),'{"é":7}');
  assert.deepEqual(JSON.parse(bytes),{'é':7});o.workspace.metadataFinish(o.request);
  assert.deepEqual(o.reserved(),before);o.workspace.close(o.request);
  assert.deepEqual(o.reserved(),[0n,0n]);assert.deepEqual(await o.workspace.closeAll(),{pending:false});
});

test('metadata refusal precedes allocation and retains SAME real FD until original close acknowledgement',async t=>{
  let fd,closeCalls=0,alloc=0;
  const dir=await directory(t,()=>{assert(fd===undefined||fd.fd===-1,'a pending original FD keeps its fixture');}),path=join(dir,'schema.json');await writeFile(path,'x'.repeat(16384));
  const o=owner(256*1024);o.workspace.begin(o.request);const before=o.reserved();
  const read=fdReader(()=>{alloc++;},async(...args)=>{
    fd=await open(...args);return {stat:fd.stat.bind(fd),read:fd.read.bind(fd),async close(){if(++closeCalls===1)return false;return fd.close();}};
  });
  let failure;await assert.rejects(read(path,65536,undefined,undefined,false,extent=>o.workspace.metadata(o.request,extent)),error=>{failure=error;return error.code==='MoonBitHostFailure';});
  assert.equal(alloc,0);assert.equal(closeCalls,1);assert(fd.fd>=0);
  o.workspace.close(o.request,failure);assert.deepEqual(o.reserved(),before);
  assert.deepEqual(await o.workspace.closeAll(),{pending:false});
  assert.equal(closeCalls,2);assert.equal(fd.fd,-1);assert.deepEqual(o.reserved(),[0n,0n]);
});

async function indexFixture(t) {
  let index,db;
  const dir=await directory(t,()=>{db?.close();index?.close();}),path=join(dir,'index.sqlite3');
  index=await openDeliveryAttemptIndex(path,{create:true,maxEntries:16,maxWireBytes:65536});index.migrate([]);
  db=new DatabaseSync(path);
  const row={semantic_cid:cid('a'),name:'invocation',wire:'{"é":7}',byte_count:8};
  index.putPublicationContracts([row],{objects:1,bytes:8});
  return {index,db,row};
}

test('metadata Native scalar extents fund publication contract index and inventory before full text handoff',async t=>{
  const {index,db,row}=await indexFixture(t),o=owner();o.workspace.begin(o.request);const before=o.reserved(),demands=[];
  const demand=bytes=>{demands.push(bytes);o.workspace.metadata(o.request,bytes);
    assert.equal(o.reserved()[0]-before[0],174n*BigInt(bytes));};
  assert.deepEqual(index.publicationContract(row.semantic_cid,demand),row);o.workspace.metadataFinish(o.request);
  assert.equal(index.contract(row.semantic_cid,demand).wire,row.wire);o.workspace.metadataFinish(o.request);
  const attempt={logical_key:'one',attempt_cid:cid('1'),grant_cid:cid('2'),run_cid:cid('3'),attempt_wire:'{"attempt":1}',grant_wire:'{"grant":1}'};
  index.claim(attempt,1,'{"initial":1}',cid('8'));
  assert.equal(index.contract(attempt.attempt_cid,demand).wire,attempt.attempt_wire);o.workspace.metadataFinish(o.request);
  const body={semantic_cid:cid('b'),name:'public_index_entry',wire:'{}',byte_count:2};index.putPublicationContracts([body],{objects:2,bytes:10});
  db.prepare('INSERT INTO native_publication_inventories VALUES(?,?)').run(body.semantic_cid,'{}');
  db.prepare('UPDATE native_publication_inventory_usage SET entries=1,ack_revision=ack_revision+1 WHERE id=1').run();
  db.prepare('INSERT INTO native_publication_indexes VALUES(?,?,?,?,?,1)').run('f'.repeat(64),'namespace',cid('4'),cid('3'),body.semantic_cid);
  assert.equal(index.nativePublicationIndex('f'.repeat(64),demand).body.wire,'{}');o.workspace.metadataFinish(o.request);
  assert.equal(index.nativePublicationInventory(body.semantic_cid,demand).inventory_wire,'{}');o.workspace.metadataFinish(o.request);
  // Independent lengths: key64 + namespace9 + three CID71 + name18 + wire2.
  const indexBytes=64+9+71+71+71+18+2;
  assert.deepEqual(demands,[89,89,29,indexBytes,73]);
  assert.deepEqual(o.reserved(),before, 'ended Native handoff scratch is reused, not cumulative');o.workspace.close(o.request);assert.deepEqual(o.reserved(),[0n,0n]);
});

test('metadata Native rejected capacity never runs its variable text selection',async t=>{
  const {index,db,row}=await indexFixture(t);const wire='x'.repeat(16384);
  db.prepare('UPDATE publication_contracts SET wire=?,byte_count=? WHERE semantic_cid=?').run(wire,16384,row.semantic_cid);
  const prepare=DatabaseSync.prototype.prepare;let fullText=0;
  t.mock.method(DatabaseSync.prototype,'prepare',function(sql,...rest){
    const statement=Reflect.apply(prepare,this,[sql,...rest]);
    if(sql.startsWith('SELECT * FROM (SELECT * FROM publication_contracts')) {
      const get=statement.get;statement.get=function(...args){fullText++;return Reflect.apply(get,statement,args);};
    }
    return statement;
  });
  const o=owner(256*1024);o.workspace.begin(o.request);const before=o.reserved();
  assert.throws(()=>index.publicationContract(row.semantic_cid,bytes=>o.workspace.metadata(o.request,bytes)),{code:'MoonBitHostFailure'});
  assert.equal(fullText,0);assert.deepEqual(o.reserved(),before);o.workspace.close(o.request);assert.deepEqual(o.reserved(),[0n,0n]);
});

test('metadata changed selected row refuses without Native miss while sibling changes preserve the original selection',async t=>{
  const {index,db,row}=await indexFixture(t),o=owner();o.workspace.begin(o.request);
  assert.throws(()=>index.publicationContract(row.semantic_cid,bytes=>{
    o.workspace.metadata(o.request,bytes);
    db.prepare('UPDATE publication_contracts SET wire=?,byte_count=? WHERE semantic_cid=?').run('{"é":77}',9,row.semantic_cid);
  }),{code:'InvalidDeliveryAttemptIndex'});
  o.workspace.close(o.request);assert.deepEqual(o.reserved(),[0n,0n]);
  const separate=owner();separate.workspace.begin(separate.request);
  db.prepare('UPDATE publication_contracts SET wire=?,byte_count=? WHERE semantic_cid=?').run(row.wire,8,row.semantic_cid);
  const sibling={semantic_cid:cid('c'),name:'invocation',wire:'{}',byte_count:2};index.putPublicationContracts([sibling],{objects:2,bytes:10});
  const selected=index.publicationContract(row.semantic_cid,bytes=>{
    separate.workspace.metadata(separate.request,bytes);
    db.prepare('UPDATE publication_contracts SET wire=?,byte_count=? WHERE semantic_cid=?').run('{"x":1}',7,sibling.semantic_cid);
  });
  assert.deepEqual(selected,row);separate.workspace.metadataFinish(separate.request);
  separate.workspace.close(separate.request);assert.deepEqual(separate.reserved(),[0n,0n]);
});

test('metadata normal Result service forwards one SAME request demand through initial reads and row reader',async()=>{
  const o=owner(),f=createResultDeliveryFixture(access,runtimeCore(raw).publicationControl,{readWorkspace:o.workspace});
  const captured=[],originals={...f.store};let same;
  for(const [name,index] of [['confirmCommittedIndex',1],['readPublicationContract',2],['withCommittedResultRows',7]]) {
    f.store[name]=async function(...args){
      assert.equal(this,f.store);const demand=args[index];assert.equal(typeof demand,'function');
      same??=demand;assert.equal(demand,same);captured.push(name);
      return Reflect.apply(originals[name],this,args);
    };
  }
  await f.deliver();assert(captured.includes('confirmCommittedIndex')&&captured.includes('readPublicationContract')&&captured.includes('withCommittedResultRows'));
  assert.deepEqual(o.reserved(),[0n,0n]);
});


test('metadata actual semantic schema FD reader reserves before stream backing and returns the original digest',async t=>{
  const dir=await directory(t),path=join(dir,'schema-original'),object=join(dir,'physical-original');
  const wire='{"é":7}';await writeFile(path,wire);await link(path,object);
  const identity='sha256:'+createHash('sha256').update(wire).digest('hex');
  const declarations=[];
  function visit(node) {
    if(node===null||typeof node!=='object')return;
    if(node.type==='VariableDeclarator'&&node.id.name==='readSemanticOriginal')declarations.push(node);
    for(const child of Object.values(node))if(Array.isArray(child))child.forEach(visit);
    else if(child!==null&&typeof child==='object')visit(child);
  }
  visit(ast);assert.equal(declarations.length,1);
  const node=declarations[0],quantity=compileFunction('return ('+originalExpression('quantity')+');',[])();
  const fail=compileFunction('return ('+originalExpression('fail')+');',['PublicationStoreError'])(PublicationStoreError);
  const readers=new Set(),o=owner();o.workspace.begin(o.request);const before=o.reserved(),alloc=[];
  const unused=()=>assert.fail('the original schema reader must not select Native contract admission');
  const ports={contractPath:cid=>{assert.equal(cid,identity);return path;},active(){},deliveryIndex:undefined,
    admitOriginalContract:unused,admitNativeContract:native=>{assert.equal(native,undefined);},
    Buffer:{allocUnsafeSlow(bytes){alloc.push(bytes);assert.equal(o.reserved()[0]-before[0],1392n);return Buffer.allocUnsafeSlow(bytes);}},
    activeSemanticReaders:readers,open,constants,configuration:{maxObjectBytes:1024},createHash,
    quantity,fail,lstat,objectPath:cid=>{assert.equal(cid,identity);return object;},cidHex:cid=>cid.slice(7),physicalContentReadWindowBytes:65536};
  const original=compileFunction('return ('+source.slice(node.init.start,node.init.end)+');',Object.keys(ports))(...Object.values(ports));
  const value=await original(identity,false,false,undefined,bytes=>{assert.equal(readers.size,1);assert.equal(bytes,8);o.workspace.metadata(o.request,bytes);});
  assert.equal(value.physicalCid,identity);assert.equal(value.bytes.toString(),wire);assert.deepEqual(alloc,[8]);
  assert.equal(readers.size,0);o.workspace.metadataFinish(o.request);assert.deepEqual(o.reserved(),before);
  o.workspace.close(o.request);assert.deepEqual(o.reserved(),[0n,0n]);
});
