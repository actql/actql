import assert from 'node:assert/strict';
import {hash} from '../../inventory.mjs';
import {auditCurrentChain} from './current-audit.mjs';
import {encodeCoreBound,retainedParentCoreBound} from './bounds.mjs';
export const directory='.artifacts/relation-pipeline/capacity/parent-control-probe';
export function auditParentStartup(report,current,read) {
  const result=auditCurrentChain(report,current,read);
  const {receiptPath,...model}=report.model;
  assert.equal(receiptPath,`${directory}/models/${hash(JSON.stringify(model))}.json`);
  assert.deepEqual(JSON.parse(read(receiptPath)),model,'Changed independent model receipt');
  assert.deepEqual(model.command,['node','proofs/relation-pipeline/capacity/parent-control/check.mjs']);
  assert.equal(model.exit,0);assert.equal(model.sourceDigest,current.digest);
  assert.equal(model.logPath,`${directory}/models/${model.logDigest}.log`);
  const log=read(model.logPath);assert.equal(hash(log),model.logDigest);
  assert(log.toString().includes('3 conditional retained parent-core propositions checked'));
  assert(log.toString().includes('2 conditional provider-construction propositions checked'));
  assert(log.toString().includes('2 conditional preparation-array propositions checked'));
  const recipe=encodeCoreBound(retainedParentCoreBound(2));
  assert.deepEqual(report.retainedCore,recipe,'Changed conditional core recipe');
  assert.deepEqual(report.providerConstruction,result.providerConstruction,'Changed independent candidate-construction recipe');
  return {...result,retainedCore:recipe};
}
