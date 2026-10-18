import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {databaseSnapshot} from './database-row-reader.fixture.mjs';

const limits=[131072,16384,32];
test('original database snapshot inventory enters one Common namespace with both exact Source aliases',()=>{
  const snapshots=[databaseSnapshot(),databaseSnapshot()];
  const specification=checked(provider.notionDatabaseReadSnapshotsRelationSpecification(
    ['tasks','accounts'],snapshots,...limits,2,1000));
  const views=JSON.parse(specification).views;assert.deepEqual(views.map(x=>x.resource),['tasks','accounts']);
  assert(views.every(x=>!Object.hasOwn(x,'facts_wire')&&!Object.hasOwn(x,'acquisition_wire')));
  const declaration=checked(common.clientProgramRowSourceRestoreRelationDeclaration('original-notion','notion','notion/0.1',specification,undefined));
  const declared=JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));assert.equal(declared.views.length,2);
  const environment=rowSourceCheckEnvironment(readFileSync(new URL('../../../../spec/local-check-environment.json',import.meta.url),'utf8'),declared);
  const check=common.clientProgramCheckEnvironment(environment.wire,environment.evidenceCid,false,false,true,false,false,false,false);assert.ok(check);
  const publication=JSON.stringify({environmentCid:environment.evidenceCid,aliases:declared.views.map(view=>({
    name:'notion.'+view.resource,sourceRef:view.source_ref,sourceViewContractCid:view.view_cid,schemaContractCid:view.carrier_schema_cid}))});
  for(const[format,text]of[['sql','SELECT id, title, amount FROM notion.tasks'],['aql','FROM notion.accounts |> SELECT id, title, amount']]){
    const outcome=common.clientProgramPrepareSourceWithParameters(text,format,check,publication,undefined,undefined);
    assert.ok(common.clientProgramPreparationReady(outcome),common.clientProgramPreparationIssueCode(outcome));
  }
  for(const snapshot of snapshots)assert.equal(checked(provider.notionDatabaseReadSnapshotWire(snapshot)).includes('"system_columns":true'),true);
});

test('database snapshot inventory empty legacy and refused original paths stay DATA only',()=>{
  const snapshot=databaseSnapshot();
  assert.equal(checked(provider.notionDatabaseReadSnapshotsRelationSpecification([],[],...limits,0,0)),'{"views":[]}');
  assert.equal(checked(provider.notionDatabaseReadSnapshotsRelationSpecification(['tasks'],[snapshot],...limits,1,6)),
    checked(provider.notionDatabaseReadSnapshotRelationSpecification(snapshot,'tasks',...limits)));
  for(const[resources,snapshots,count,work]of[
    [['tasks','other'],[snapshot,snapshot],1,23],
    [['tasks','other'],[snapshot,snapshot],2,22],
    [['tasks','tasks'],[snapshot,snapshot],2,23],
    [['tasks'],[{...snapshot}],1,6],
    [['tasks'],[],1,6],
  ])assert.throws(()=>checked(provider.notionDatabaseReadSnapshotsRelationSpecification(resources,snapshots,...limits,count,work)),{code:'MoonBitHostFailure'});
});
