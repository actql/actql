import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {selectReleaseCalendarQueryCases} from '../../scripts/release-calendar-query-cases.mjs';
export function auditCalendarTransport(report) {
  const {successes,refusals}=selectReleaseCalendarQueryCases();
  assert(['local','https'].includes(report.mode));assert.equal(report.suite,'calendar');
  assert.equal(report.complete,true);assert.equal(report.actualNormal,6);assert.equal(report.actualRefusal,0);
  const names=successes.map(v=>v.name);assert.deepEqual(report.expectedSuccessNames,names);
  assert.deepEqual(report.successNames,names);assert.deepEqual(report.completed.map(v=>v.name),names);
  assert.deepEqual(report.refusalNames,[]);assert.deepEqual(report.completedRefusals,refusals);
  assert.deepEqual(report.providerObservation,{forbiddenProcesses:0,forbiddenFetches:0,sourceSecrets:0});
  let rows=0;
  for(const [index,actual] of report.completed.entries()) {
    assert(actual.ref&&Object.keys(actual.ref).length);assert(actual.submissionRef&&Object.keys(actual.submissionRef).length);
    assert.deepEqual(actual.observedResults,successes[index].results);
    assert.equal(actual.beforeSubmit.acceptedRuns,index);assert.equal(actual.beforeRead.acceptedRuns,index+1);
    for(const key of ['sourceIo','sourceReads','sourceReadSessions']) {
      assert.equal(actual.beforeSubmit[key],0);assert.equal(actual.beforeRead[key],0);
    }
    assert.deepEqual(actual.afterReplay,actual.beforeRead);
    rows+=actual.observedResults.answer.rows.length;
  }
  assert.equal(rows,12);return {mode:report.mode,normal:6,refusal:0,namedResults:6,rows,complete:true};
}
if(process.argv[1]!==undefined&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const receipt=JSON.parse(await readFile(process.argv[2],'utf8'));
  assert.equal(receipt.suite,'calendar');assert.equal(receipt.complete,true);
  assert.deepEqual(receipt.transports.map(v=>v.mode),['local','https']);assert.equal(receipt.artifacts.length,4);
  assert.equal(receipt.records.length,4);for(const r of receipt.records){assert.equal(r.code,0);assert.equal(r.signal,null);}
  console.log(JSON.stringify({complete:true,transports:receipt.transports.map(auditCalendarTransport)}));
}
