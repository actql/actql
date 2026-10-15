import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';
import {Duplex} from 'node:stream';
import {setImmediate as turn} from 'node:timers/promises';

// Actual pinned Undici/parser and Node queue; the connector/socket producer
// is a controlled physical double. This is not original Host funding or TLS.
const require=createRequire(import.meta.url);
const undici=require('undici'),originalConnector=undici.buildConnector;
let selectedSocket,connections=0;
undici.buildConnector=()=> (_options,callback)=>{
  const socket=selectedSocket;connections++;
  queueMicrotask(()=>callback(null,socket));
  return socket;
};
let transport;
try {transport=await import('./_internal/original-undici-transport.mjs');}
finally {undici.buildConnector=originalConnector;}
const extent=512;
const endpoint='http://fixture.invalid/chat/completions';
const responseLimits={maxBytes:8192,maxChunkBytes:extent,maxChunks:32,
  maxHeaderBytes:4096,observedHeaders:[]};
const physicalAcquisitionLimits={maxPlaintextBytes:65536,maxBorrowedBackingBytes:131072,maxReads:64};
async function until(read,accept){
  for(let i=0;i<500;i++){const value=read();if(accept(value))return value;await turn();}
  assert.fail('Finite same original Socket observation unavailable');
}
function fixture(t,wire,{deferClose=false,headerBytes=4096,synchronousProducer=false}={}){
  const original=Buffer.allocUnsafeSlow(Buffer.byteLength(wire));original.write(wire);
  const packets=[];
  for(let offset=0;offset<original.length;offset+=extent)packets.push(original.subarray(offset,offset+extent));
  let queued=false,finishClose,closes=0;
  const enqueue=()=>{if(queued)return;queued=true;for(const packet of packets)socket.push(packet);};
  const socket=new Duplex({read(){if(synchronousProducer)enqueue();},write(_bytes,_encoding,callback){
    callback();if(!synchronousProducer)queueMicrotask(enqueue);
  },destroy(error,callback){
    const finish=()=>callback(error);
    if(deferClose)finishClose=finish;else finish();
  }});
  socket.on('error',()=>{});socket.once('close',()=>{closes++;});
  const read=socket.read,reads=[];
  socket.read=function(...args){
    const before={available:this.readableLength,destroyed:this.destroyed,size:args[0]};
    const chunk=Reflect.apply(read,this,args);
    reads.push({...before,bytes:chunk?.byteLength??null});
    return chunk;
  };
  selectedSocket=socket;
  const selected=transport.createOriginalUndiciFetch({endpoint,
    requestLimits:{maxBytes:64,maxHeaderBytes:128,maxHeaders:4},
    responseLimits:{...responseLimits,maxHeaderBytes:headerBytes},physicalAcquisitionLimits});
  const call=transport.prepareOriginalUndiciFetch(selected,endpoint,
    {method:'POST',body:'{}',headers:[],redirect:'error',signal:new AbortController().signal},
    {...responseLimits,maxHeaderBytes:headerBytes});
  t.after(async()=>{finishClose?.();assert.equal(await call.cleanup(),true);assert.equal(closes,1);});
  return{socket,call,reads,original,finish:()=>finishClose?.(),closes:()=>closes};
}

test('original parser consumes queued input in its fixed extent without waiting for a whole response',async t=>{
  const payload='x'.repeat(1024);
  const wire=`HTTP/1.1 200 OK\r\nContent-Length: 1024\r\nConnection: close\r\n\r\n${payload}`;
  const before=connections,f=fixture(t,wire);
  const response=await f.call.invoke(),reader=response.body.getReader(),parts=[];
  for(;;){const next=await reader.read();if(next.done)break;parts.push(next.value);}
  reader.releaseLock();
  assert.equal(Buffer.concat(parts).toString(),payload);
  assert.ok(f.reads.some(value=>value.available>extent),'actual multi-entry queue must be exercised');
  assert.ok(f.reads.filter(value=>value.bytes!==null).every(value=>value.bytes<=extent),
    'original read must select its extent BEFORE Node fromList concatenation');
  assert.ok(f.reads.filter(value=>value.available===0).every(value=>value.size===0&&value.bytes===null),
    'empty read drives the producer without accepting its synchronous unbounded payload');
  assert.equal(connections,before+1);
  assert.equal(await f.call.cleanup(),true);
  assert.equal(f.closes(),1);
  assert.throws(()=>f.call.invoke(),{code:'UndiciOriginalTransportRetired'});
});

test('original header refusal stops subsequent queued reads but retains delayed close custody',async t=>{
  const wire='HTTP/1.1 200 OK\r\nX-Long: '+ 'x'.repeat(4096)+'\r\nContent-Length: 0\r\n\r\n';
  const before=connections,f=fixture(t,wire,{deferClose:true,headerBytes:256});
  const result=f.call.invoke().then(()=>({response:true}),error=>({error:error.code}));
  await until(()=>f.socket.destroyed,Boolean);
  let retired=false;
  const cleanup=f.call.cleanup().then(value=>{retired=value;return value;});
  try{
    await turn();
    assert.equal(f.socket.closed,false);
    assert.equal(retired,false,'destroy request is not the original close ACK');
    assert.equal(f.closes(),0);
    assert.ok(f.reads.filter(value=>value.bytes!==null).every(value=>value.bytes<=extent));
    assert.equal(f.reads.filter(value=>value.destroyed).length,0,
      'destroyed Node streams can still return queued input; do not read it');
    assert.ok(f.socket.readableLength>0,'unread original queue remains owned until physical close');
  }finally{f.finish();await cleanup;}
  assert.deepEqual(await result,{error:'UND_ERR_HEADERS_OVERFLOW'});
  assert.equal(retired,true);assert.equal(f.closes(),1);
  assert.equal(connections,before+1);
  assert.throws(()=>f.call.invoke(),{code:'UndiciOriginalTransportRetired'});
});

test('original empty read does not absorb a synchronous producer burst as one parser chunk',async t=>{
  const payload='x'.repeat(1536);
  const f=fixture(t,`HTTP/1.1 200 OK\r\nContent-Length: 1536\r\n\r\n${payload}`,{synchronousProducer:true});
  const response=await f.call.invoke(),reader=response.body.getReader(),parts=[];
  for(;;){const next=await reader.read();if(next.done)break;parts.push(next.value);}
  reader.releaseLock();
  assert.equal(Buffer.concat(parts).toString(),payload);
  assert.ok(f.reads.some(value=>value.available===0&&value.size===0&&value.bytes===null),
    'same original empty read must drive _read without accepting its synchronous burst');
  assert.ok(f.reads.filter(value=>value.bytes!==null).every(value=>value.bytes<=extent));
  assert.equal(await f.call.cleanup(),true);
});

test('original short response is read before physical EOF without waiting for a fixed extent',async t=>{
  const f=fixture(t,'HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: keep-alive\r\n\r\nabc');
  let response,error;
  const pending=f.call.invoke().then(value=>{response=value;},cause=>{error=cause;});
  await until(()=>response??error,value=>value!==undefined);
  await pending;
  assert.equal(error,undefined);
  assert.notEqual(response,undefined);
  assert.ok(f.reads.some(value=>value.available>0&&value.available<extent&&value.size===value.available));
  assert.equal(f.socket.readableEnded,false,'fixture never sent EOF to complete a fixed-size read');
  const reader=response.body.getReader(),first=await reader.read();
  assert.equal(Buffer.from(first.value).toString(),'abc');
  assert.equal((await reader.read()).done,true);
  reader.releaseLock();
  assert.equal(await f.call.cleanup(),true);
});
