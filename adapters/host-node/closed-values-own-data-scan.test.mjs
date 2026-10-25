import test from 'node:test';
import assert from 'node:assert/strict';
import {types} from 'node:util';
import {scanClosedValuesOwnDataAscii,scanClosedValuesOwnData,closedValuesOwnDataScanControlInventory,probeClosedValuesOwnDataHeader,closedValuesOwnDataHeaderFields,closedValuesOwnDataHeaderRows,closedValuesOwnDataScanWorkUpper,retireClosedValuesOwnDataHeader} from './closed-values-own-data-scan.mjs';
function program(width=10,count=990) {
 const fields=Array.from({length:width},(_,i)=>'c'+i);
 return {version:'actql/0.1',id:'own-data',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{
  schema:Object.fromEntries(fields.map(name=>[name,{type:'number',nullable:false}])),
  rows:Array.from({length:count},(_,r)=>Object.fromEntries(fields.map((name,c)=>[name,r*width+c]))),
 }}],results:{rows:{from:'v',fields}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
}
function phase(limit=Number.MAX_SAFE_INTEGER) {
 // Test-only stand-in; production must use the original Root reservation.
 return {used:0,spendWork(n){if(n>limit-this.used)throw Object.assign(new Error('ScanWorkUnavailable'),{code:'ScanWorkUnavailable'});this.used+=n;}};
}
test('usual plain object 9900-cell Values is measured before any JSON copy',()=>{
 const input=program(),owner=phase();const facts=scanClosedValuesOwnData(input,undefined,owner);
 assert(facts);assert.equal(facts.rowCount,990);assert.equal(facts.fieldCount,10);
 assert.equal(facts.inspectionWork,owner.used);
 const actual=Buffer.byteLength(JSON.stringify(input));assert.ok(actual>65536);assert.ok(facts.inputBytesUpper>=actual);
 assert.equal(facts.depthUpper,8);assert.ok(Object.isFrozen(facts));
 console.log(JSON.stringify({actualInputBytes:actual,...facts,scanControl:closedValuesOwnDataScanControlInventory}));
});
test('original work debit exact succeeds and one-short refuses, not fallback',()=>{
 const input=program(2,3),observed=scanClosedValuesOwnData(input,undefined,phase());
 assert.deepEqual(scanClosedValuesOwnData(input,undefined,phase(observed.inspectionWork)),observed);
 assert.throws(()=>scanClosedValuesOwnData(input,undefined,phase(observed.inspectionWork-1)),{code:'ScanWorkUnavailable'});
});
test('live/revoked proxies decline without invoking any trap',()=>{
 let traps=0;const live=new Proxy({}, {ownKeys(){traps++;throw Error('trap');},getOwnPropertyDescriptor(){traps++;throw Error('trap');},getPrototypeOf(){traps++;throw Error('trap');}});
 const revoked=Proxy.revocable({},{});revoked.revoke();
 assert(types.isProxy(live));assert(types.isProxy(revoked.proxy));
 for(const value of [live,revoked.proxy])assert.equal(scanClosedValuesOwnData(value,undefined,phase()),undefined);
 const input=program(1,1);input.stages[0].steps[0].values.rows[0]=live;
 assert.equal(scanClosedValuesOwnData(input,undefined,phase()),undefined);assert.equal(traps,0);
});
test('getters/toJSON and custom prototypes decline without execution',()=>{
 for(const kind of ['getter','toJSON','prototype']){
  const input=program(1,1);let calls=0;const row=input.stages[0].steps[0].values.rows[0];
  if(kind==='getter')Object.defineProperty(row,'c0',{enumerable:true,get(){calls++;return 1;}});
  if(kind==='toJSON')Object.defineProperty(row,'toJSON',{value(){calls++;return {c0:1};}});
  if(kind==='prototype')Object.setPrototypeOf(row,{get toJSON(){calls++;return ()=>({c0:1});}});
  assert.equal(scanClosedValuesOwnData(input,undefined,phase()),undefined);assert.equal(calls,0);
 }
});
test('no ignored extras, mismatched schema, duplicate fields, sparse arrays or nonfinite values',()=>{
 for(const change of [p=>p.extra=true,p=>p.stages[0].steps[0].values.schema.extra={type:'number',nullable:false},
  p=>p.stages[0].steps[0].values.rows[0].extra=1,p=>p.stages[0].results.rows.fields[1]='c0',
  p=>delete p.stages[0].steps[0].values.rows[0].c0,p=>delete p.stages[0].steps[0].values.rows[0],
  p=>p.stages[0].steps[0].values.rows[0].c0=Infinity]){
  const input=program(2,1);change(input);assert.equal(scanClosedValuesOwnData(input,undefined,phase()),undefined);
 }
});
test('caller map/iterator overrides are not invoked; old nonproof paths remain unmodified',()=>{
 const input=program(1,2);let calls=0;
 for(const a of [input.stages,input.stages[0].steps,input.stages[0].steps[0].values.rows,input.stages[0].results.rows.fields]){
  a.map=()=>{calls++;throw Error('map');};a[Symbol.iterator]=()=>{calls++;throw Error('iterator');};
 }
 assert(scanClosedValuesOwnData(input,undefined,phase()));assert.equal(calls,0);
 assert.equal(scanClosedValuesOwnData(input,{parameters:{}},phase()),undefined);
 const unicode=program(1,1);unicode.id='日本';const unicodeFacts=scanClosedValuesOwnData(unicode,undefined,phase());assert(unicodeFacts);assert.ok(unicodeFacts.inputBytesUpper>=Buffer.byteLength(JSON.stringify(unicode)));
 assert.equal(unicode.id,'日本');
});

test('bounded numeric boundary matrix preserves JSON byte and lexical upper facts',()=>{
 const values=[0,-0,Number.MIN_VALUE,Number.MAX_VALUE,Number.EPSILON,1e-7,1e21,-1e-7,-Number.MAX_VALUE,9007199254740991];
 let cases=0;
 for(const width of [1,2,10])for(const rows of [0,1,3]){
  const input=program(width,rows),table=input.stages[0].steps[0].values.rows;
  for(let r=0;r<rows;r++)for(let c=0;c<width;c++)table[r]['c'+c]=values[(r*width+c)%values.length];
  const facts=scanClosedValuesOwnData(input,undefined,phase());assert(facts);
  const wire=JSON.stringify(input);assert.ok(Buffer.byteLength(wire)<=facts.inputBytesUpper);
  let objects=0,arrays=0,fields=0,quotes=0,quotedUnits=0,maxQuoted=0,depth=0,maxDepth=0,inString=false,units=0;
  for(const ch of wire){if(inString){if(ch==='"'){inString=false;maxQuoted=Math.max(maxQuoted,units);}else{units++;quotedUnits++;}}
   else if(ch==='"'){inString=true;units=0;quotes++;}else if(ch==='{'||ch==='['){if(ch==='{')objects++;else arrays++;depth++;maxDepth=Math.max(maxDepth,depth);}
   else if(ch==='}'||ch===']')depth--;else if(ch===':')fields++;}
  assert.equal(facts.objects,objects);assert.equal(facts.arrays,arrays);assert.equal(facts.fieldsUpper,fields);
  assert.equal(facts.quotedTokens,quotes);assert.equal(facts.quotedUtf16Units,quotedUnits);assert.equal(facts.longestQuotedUtf16,maxQuoted);assert.equal(facts.depthUpper,maxDepth);cases++;
 }
 assert.equal(cases,9);
});


test('fixed header binds exact input/field/row originals; derived fullscan work is exact',()=>{
 for(const [f,r] of [[1,0],[2,3],[10,990],[99,100]]){
  const input=program(f,r),owner=phase(),header=probeClosedValuesOwnDataHeader(input,undefined,owner);
  assert(header);assert.equal(owner.used,48);assert.equal(closedValuesOwnDataHeaderFields(header,input),f);assert.equal(closedValuesOwnDataHeaderRows(header,input),r);
  const upper=closedValuesOwnDataScanWorkUpper(header,input);assert.equal(upper,140+f*f+19*f+r*(4+6*f));
  const facts=scanClosedValuesOwnData(input,undefined,phase(upper),header);assert(facts);assert.equal(facts.inspectionWork,upper);
  assert.equal(closedValuesOwnDataHeaderFields(header,input),undefined);assert.equal(scanClosedValuesOwnData(input,undefined,phase(),header),undefined);
  const retry=probeClosedValuesOwnDataHeader(input,undefined,phase());assert.throws(()=>scanClosedValuesOwnData(input,undefined,phase(upper-1),retry),{code:'ScanWorkUnavailable'});
 }
});
test('header cannot be copied or reconstructed and does not survive replacement/retirement',()=>{
 const input=program(2,2),header=probeClosedValuesOwnDataHeader(input,undefined,phase());
 assert.equal(closedValuesOwnDataScanWorkUpper({...header},input),undefined);
 assert.equal(closedValuesOwnDataScanWorkUpper(header,program(2,2)),undefined);
 assert.throws(()=>new header.constructor({},input,[],[],2,2));
 assert.throws(()=>Object.getPrototypeOf(header).fields=()=>100,TypeError);
 input.stages[0].steps[0].values.rows=[...input.stages[0].steps[0].values.rows];
 assert.equal(scanClosedValuesOwnData(input,undefined,phase(),header),undefined);
 const next=probeClosedValuesOwnDataHeader(input,undefined,phase());retireClosedValuesOwnDataHeader(next,input);assert.equal(closedValuesOwnDataHeaderRows(next,input),undefined);
});
test('invalid fullscan branches stay within original F/R envelope; header visits stay bounded',()=>{
 for(const mutate of [p=>p.extra=true,p=>p.stages[0].inputs.x=1,p=>p.stages[0].results.rows.extra=1,
  p=>p.stages[0].steps[0].values.schema.extra={type:'number',nullable:false},p=>p.stages[0].steps[0].values.rows[1].extra=1,
  p=>delete p.stages[0].steps[0].values.rows[1].c0,p=>delete p.stages[0].steps[0].values.rows[1],
  p=>p.stages[0].results.rows.fields[1]='c0']){
  const input=program(2,2),header=probeClosedValuesOwnDataHeader(input,undefined,phase()),upper=closedValuesOwnDataScanWorkUpper(header,input);mutate(input);
  const owner=phase(upper);assert.equal(scanClosedValuesOwnData(input,undefined,owner,header),undefined);assert.ok(owner.used<=upper);
 }
 const input=program(1,1);input.stages[0].results.other={from:'v',fields:['c0']};const owner=phase(50);assert.equal(probeClosedValuesOwnDataHeader(input,undefined,owner),undefined);assert.ok(owner.used<=50);
 assert.throws(()=>probeClosedValuesOwnDataHeader(program(1,1),undefined,phase(47)),{code:'ScanWorkUnavailable'});
});

test('inherited enumerable keys decline within F/R work instead of unbounded traversal',()=>{
 const input=program(1,0),header=probeClosedValuesOwnDataHeader(input,undefined,phase()),upper=closedValuesOwnDataScanWorkUpper(header,input);
 try {for(let i=0;i<200;i++)Object.defineProperty(Object.prototype,'__scanInherited'+i,{value:1,enumerable:true,configurable:true});
 const owner=phase(upper);assert.equal(scanClosedValuesOwnData(input,undefined,owner,header),undefined);assert.ok(owner.used<=upper);
 }finally{for(let i=0;i<200;i++)delete Object.prototype['__scanInherited'+i];}
});

test('owned-control tariff excludes fixed frames; exact416 and one-short415',()=>{
 const v=closedValuesOwnDataScanControlInventory;
 assert.deepEqual(v,{recordHeaders:5,referenceSlots:8,scalarWords:34,ownedUtf16Units:0,ownedWireBytes:0});
 const cost=16*v.recordHeaders+8*v.referenceSlots+8*v.scalarWords;assert.equal(cost,416);
 // Test-only logical tariff admission, NOT the original Core grant.
 const admit=available=>{if(available<cost)throw new Error('ControlUnavailable');return available-cost;};
 assert.equal(admit(416),0);assert.throws(()=>admit(415),/ControlUnavailable/);
});


test('funded ASCII eligibility costs original structural work plus exact quoted units before clone',()=>{
 const input=program(100,99),facts=scanClosedValuesOwnData(input,undefined,phase());
 const bound=facts.inspectionWork+facts.quotedUtf16Units;
 const owner=phase(bound),eligible=scanClosedValuesOwnDataAscii(input,undefined,owner);
 assert(eligible);assert.equal(owner.used,bound);
 assert.throws(()=>scanClosedValuesOwnDataAscii(input,undefined,phase(bound-1)),{code:'ScanWorkUnavailable'});
 for(const text of ['日本','quote"','slash\\','line\n','😀']){
  const candidate=program(1,1);candidate.id=text;
  const original=scanClosedValuesOwnData(candidate,undefined,phase());assert(original);
  assert.equal(scanClosedValuesOwnDataAscii(candidate,undefined,phase(original.inspectionWork+original.quotedUtf16Units)),undefined);
  assert.equal(candidate.id,text);
 }
});
