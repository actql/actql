import assert from 'node:assert/strict';
import test from 'node:test';
import {checkedLocalOutputLimits} from './local-values-plan.mjs';

test('checked publication ABI maps distinct sentinels to independently named fields',()=>{
  const original=Object.freeze({});
  const holder=Object.freeze({});
  const actual=checkedLocalOutputLimits({clientProgramPreparedLocalPublicationLimits(actualHolder,prepared,bytes){
    assert.equal(actualHolder,holder);
    assert.equal(prepared,original);assert.equal(bytes,536870912);
    return Array.from({length:22},(_,i)=>101+i);
  }},original,{kind:'preparation',value:holder});
  assert.deepEqual(actual,{
    maxResultFields:101,maxResultMappingWork:102,maxResultOrderWork:103,maxResultWorkspaceEntries:104,
    maxRows:105,maxValueNodes:106,maxValueTextBytes:107,maxValueDepth:108,maxValueWork:109,
    maxWireBytes:110,maxWireNodes:111,maxWireDepth:112,maxColumns:113,maxOrderWork:114,
    maxLogicalWireBytes:115,maxLogicalWireNodes:116,maxLogicalWireDepth:117,
    maxSchemaFields:118,maxSchemaBytes:119,maxSchemaNodes:120,maxSchemaDepth:121,maxBatchBytes:122,
  });
  assert.equal(Object.isFrozen(actual),true);
});
test('checked publication ABI rejects missing extra unsafe or negative fields',()=>{
  const valid=Array.from({length:22},(_,i)=>101+i);
  for(const values of [undefined,{},valid.slice(1),[...valid,123],
    ...[-1,NaN,Infinity,1.5,Number.MAX_SAFE_INTEGER+1,'1'].map(value=>valid.with(9,value))]){
    assert.throws(()=>checkedLocalOutputLimits({clientProgramPreparedLocalPublicationLimits(){return values;}},{},{kind:'preparation',value:{}}),
      {name:'TypeError',message:'InvalidCheckedLocalPublicationLimits'});
  }
});
