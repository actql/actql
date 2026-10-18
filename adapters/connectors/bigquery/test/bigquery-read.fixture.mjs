// Actual same-runtime Common caller with explicit private test units and a
// stop-observer double. This fixture establishes no HTTP, installed supplier,
// normal funding or physical cleanup beyond that explicit observer.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
const repo = new URL('../../../../', import.meta.url).pathname;
const read = name => readFile(join(repo, name), 'utf8');
export {moon};
export const decimal38 = '99999999999999999999999999999999999999';
export const fields = Object.freeze([
 {name:'ACCOUNT_ID',type:'STRING',mode:'REQUIRED'},
 {name:'ACTIVE_USERS',type:'BIGNUMERIC',mode:'REQUIRED',precision:'38',scale:'0'},
 {name:'TREND',type:'STRING',mode:'NULLABLE'},
]);
export function metadataBody(selectedFields = fields) {
 return Buffer.from(JSON.stringify({kind:'bigquery#table',etag:'original-metadata',type:'TABLE',
  tableReference:{projectId:'acme-project',datasetId:'product',tableId:'usage'},schema:{fields:selectedFields}}));
}
export function queryLimits() {
 return moon.clientProgramBigQueryQueryLimits(
  moon.clientProgramBigQueryDescriptionLimits(4096,1000,16,16,4096,4096),2,2n,1000,4096,1024,256);
}
export const statement = 'SELECT `ACCOUNT_ID`, `ACTIVE_USERS`, `TREND` FROM `acme-project`.`product`.`usage`';
export function jobBody(jobId,{state='DONE',foreign=false,failed=false}={}) {
 return Buffer.from(JSON.stringify({kind:'bigquery#job',
  jobReference:{projectId:'acme-project',jobId:foreign?'foreign':jobId,location:'EU'},
  configuration:{query:{query:statement,maximumBytesBilled:'1000000',useLegacySql:false}},
  status:{state,...(failed?{errorResult:{reason:'invalidQuery'}}:{})}}));
}
export function resultBody(jobId,{rows=[['a1',decimal38,'down'],['a2','0',null]],token,total='2',selectedFields=fields}={}) {
 return Buffer.from(JSON.stringify({kind:'bigquery#getQueryResultsResponse',
  jobReference:{projectId:'acme-project',jobId,location:'EU'},jobComplete:true,
  schema:{fields:selectedFields},totalRows:total,rows:rows.map(row=>({f:row.map(v=>({v}))})),
  ...(token===undefined?{}:{pageToken:token})}));
}

export async function originalBigQueryRowOwner({selectedFields = fields} = {}) {
  const descriptionLimits = moon.clientProgramBigQueryDescriptionLimits(4096, 1000,
    16, 16, 4096, 4096);
  const declarationLimits = moon.clientProgramBigQueryDeclarationLimits(200000,
    20000, 32, 1, 3);
  const description = checked(moon.clientProgramBigQueryDescribeTable('acme-project',
    'product', 'usage', metadataBody(selectedFields), descriptionLimits));
  const declaration = checked(moon.clientProgramBigQueryGenerateReadDeclaration(
    description, 'usage_30d', 'bigquery', 'bigquery/0.1', descriptionLimits, declarationLimits));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(), declared);
  const check = moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(check);
  const view = declared.views[0];
  const publication = JSON.stringify({environmentCid: environment.evidenceCid,
    aliases: [{name: 'bigquery.usage_30d', sourceRef: view.source_ref,
      sourceViewContractCid: view.view_cid, schemaContractCid: view.carrier_schema_cid}]});
  const outcome = moon.clientProgramPrepareSourceWithParameters(
    'SELECT ACCOUNT_ID, ACTIVE_USERS, TREND FROM bigquery.usage_30d',
    'sql', check, publication, undefined, undefined);
  const program = moon.clientProgramPreparationReady(outcome);
  assert.ok(program, `ordinary SQL must prepare the original declared input: ${
    moon.clientProgramPreparationIssueCode(outcome)}`);
  const [registry, aoa, query, evidence] = await Promise.all([
    read('spec/dependencies/aoa-pipeline-registry.json'),
    read('spec/contracts/actql-aoa.json').then(JSON.parse),
    read('spec/contracts/actql-query-acquisition.json'),
    read('spec/contracts/actql-query-process-evidence.json')]);
  const requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(
    program, 0, 0, registry, JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
  const prepared = checked(moon.clientProgramBigQueryPrepareRead(description,
    declaration, requirement, query, evidence, descriptionLimits, declarationLimits));
  const acquisition = moon.clientProgramBigQueryReadAcquisition(prepared);
  // Explicit test units, not normal product prices. This is the same ledger
  // and original run consumed by the physical driver, never a second root.
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1, 24000n,
    100000000n, 100000000n, 0));
  const requestId = randomUUID();
  const run = checked(moon.clientProgramRowSourceStartAccounted(acquisition,
    requestId, () => true, ledger, 24000n, 4096n));
  checked(moon.clientProgramRowSourceBegin(run, 4096, 2, 2, undefined));
  return {prepared, acquisition, run, ledger, requestId, requirement,
    originals: {description, declaration, declared, environment, program,
      descriptionLimits, declarationLimits, registry,
      values: JSON.stringify(aoa.execution_contracts['REL.values']),
      fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])},
    usage: () => moon.clientProgramMultiCapturedLedgerUsage(ledger),
    assertNoCapture: () => assert.throws(() => checked(moon.clientProgramRowSourceCapture(run)),
      {code: 'MoonBitHostFailure'}),
    captureRows() {
      checked(moon.clientProgramRowSourceFinish(run));
      const captured = checked(moon.clientProgramRowSourceCapture(run));
      const source = checked(moon.clientProgramRowSourceCaptureSource(captured));
      const exported = checked(moon.clientProgramExportSourceCapture(source,
        requirement, 'bigquery-original-row-test'));
      return moon.clientProgramSourceCaptureExportRows(exported);
    },
    close: () => checked(moon.clientProgramRowSourceCloseAccounted(run))};
}

