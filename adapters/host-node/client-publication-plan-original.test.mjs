import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {checkedLocalOutputLimits} from './local-values-plan.mjs';
import {resultOutputLimitFields} from '../host-common/result-output-limits.mjs';

function originalGetter(record) {
 const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
 const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
 let selected;
 function walk(node){if(!node||typeof node!=='object')return;if(node.type==='Property'&&node.key?.name==='managedComputePublicationOriginal')selected=node.value;for(const value of Object.values(node)){if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value);}}
 walk(ast);assert(selected);
 return new Function('record','clientOperationError',`return function(runtime,prepared)${source.slice(selected.body.start,selected.body.end)}`)(record,code=>Object.assign(new Error(code),{code}));
}

test('publication reads the same original before admission and after its move to the live Run',()=>{
 const runtime={},prepared={},original={},live={};
 const run={runtime,prepared,closed:false,preparedSequences:original};
 const record={computeRuns:new Map([[prepared,run]])},get=originalGetter(record);
 const before=get(runtime,prepared);assert.equal(before.kind,'preparation');assert.strictEqual(before.value,original);
 run.value=live;run.preparedSequences=undefined;
 const after=get(runtime,prepared);assert.equal(after.kind,'installed_run');assert.strictEqual(after.value,live);
 assert.equal(record.computeRuns.size,1);assert.equal(run.preparedSequences,undefined);
 run.closed=true;assert.throws(()=>get(runtime,prepared),{code:'NodeManagedRunRuntimeUnavailable'});
 run.closed=false;assert.throws(()=>get({},prepared),{code:'NodeManagedRunRuntimeUnavailable'});
 run.value=undefined;assert.throws(()=>get(runtime,prepared),{code:'NodeManagedRunRuntimeUnavailable'});
 assert.equal(get(runtime,{}),undefined); // Explicit unrelated legacy route.
});

test('publication phase dispatch preserves nominal owners and rejects invalid projection instead of legacy fallback',()=>{
 const prepared={},original={},live={},calls=[];
 const vector=resultOutputLimitFields.map(()=>1);
 const moon={
  clientProgramLocalPublicationLimits:(...args)=>{calls.push(['legacy',...args]);return vector;},
  clientProgramPreparedLocalPublicationLimits:(...args)=>{calls.push(['preparation',...args]);return vector;},
  clientProgramInstalledManagedPublicationLimits:(...args)=>{calls.push(['installed',...args]);return vector;},
 };
 checkedLocalOutputLimits(moon,prepared,{kind:'preparation',value:original});
 checkedLocalOutputLimits(moon,prepared,{kind:'installed_run',value:live});
 checkedLocalOutputLimits(moon,prepared);
 assert.strictEqual(calls[0][1],original);assert.strictEqual(calls[0][2],prepared);
 assert.strictEqual(calls[1][1],live);assert.strictEqual(calls[1][2],prepared);
 assert.deepEqual(calls.map(c=>c[0]),['preparation','installed','legacy']);
 moon.clientProgramInstalledManagedPublicationLimits=()=>[];
 assert.throws(()=>checkedLocalOutputLimits(moon,prepared,{kind:'installed_run',value:live}),/InvalidCheckedLocalPublicationLimits/);
 assert.equal(calls.length,3);
 assert.throws(()=>checkedLocalOutputLimits(moon,prepared,{kind:'other',value:live}),/InvalidCheckedLocalPublicationOriginal/);
});
