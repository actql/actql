import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {open} from '../../packages/node/index.mjs';
const fixture=JSON.parse(await readFile(new URL('./fixtures/audited-capabilities-42.json',import.meta.url)));
function program(expr){return{version:'actql/0.1',id:'scalar-structured',stages:[{id:'main',inputs:{},steps:[{as:'seed',values:{schema:{n:{type:'number',nullable:false}},rows:[{n:1}]}},{from:'seed',derive:{v:expr},as:'computed'}],results:{rows:{from:'computed',fields:['v']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}}}
test('all 42 independently expected audited capabilities execute through public Local',async()=>{
 assert.equal(fixture.cases.length,42);const stateDir=await mkdtemp('/tmp/actql-audited42-');const client=await open({stateDir});
 try{for(const c of fixture.cases){let actual;if(c.kind==='sql')actual=await client.sql(c.input).all();else if(c.kind==='aql')actual=await client.aql(c.input).all();else{const run=await client.start(c.kind==='program'?c.input:program(c.input));assert.equal((await run.wait()).status,'succeeded',c.name);actual=await run.result('answer').all();}assert.deepEqual(actual,c.expected,c.name);}}
 finally{await client.close();await rm(stateDir,{recursive:true,force:true});}
});
