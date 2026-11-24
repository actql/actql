// Actual Common/Local Result and original vendor DATA with explicit fixture
// admission and capacity. This issues no installed target, Account permission,
// authenticated publication, approved write, Provider send or normal funding.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {inspect} from 'node:util';
import {canonicalText} from '../../../../scripts/check-canonical-json.mjs';
import {runCapturedEffectComputation} from '../../../host-node/entry.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

import type {contentGenerationControl} from '../../../host-common/content-generation-control.mjs';
import type {exportPinnedEffectLocalResult} from '../../../host-node/effect-input-export.mjs';

type EffectExport = Parameters<typeof exportPinnedEffectLocalResult>[0];
type Execution = Awaited<ReturnType<typeof runCapturedEffectComputation>> & EffectExport['execution'];
type OwnedEffect = Parameters<typeof runCapturedEffectComputation>[0];
type PublicationEvidence = [template:unknown, invocation:unknown, authorization:unknown, plan:unknown];
type ExportLimits = Pick<Parameters<typeof contentGenerationControl>[0],'clientProgramEffectInputExportLimits'>;
type Common = EffectExport['moon'] & ExportLimits & {
  clientProgramNotionDatabaseLimits(bytes:number,nodes:number,depth:number,dataSources:number,
    properties:number,identityBytes:number,nameBytes:number):unknown;
  clientProgramNotionProjectDatabase(body:Uint8Array,limits:unknown):unknown;
  clientProgramNotionProjectDataSource(database:unknown,index:number,body:Uint8Array,limits:unknown):unknown;
  clientProgramNotionPropertyWriteLimits(bytes:number,nodes:number,depth:number,properties:number,
    items:number,textUnits:number,work:number):unknown;
  clientProgramCheckEnvironment(wire:string,cid:string,textTime:boolean,veca:boolean,
    rela:boolean,sga:boolean,tea:boolean,calendar:boolean,textRank:boolean):unknown;
  clientProgramPrepareEffectComputationWithParameters(program:string,format:string,environment:unknown,
    parameters:string|undefined,proofs:readonly unknown[]):unknown;
  clientProgramEffectPreparationReady(outcome:unknown):unknown;
  clientProgramEffectPreparationIssue(outcome:unknown):unknown;
  clientProgramAdmitEffectPublication(prepared:unknown,...evidence:PublicationEvidence):unknown;
  strategyIssueRunDefinition(admission:unknown,scope:string,run:string,artifacts:string,
    created:string,expires:string,bytes:number,nodes:number,depth:number):unknown;
  clientProgramBindEffectRun(prepared:unknown,admission:unknown,definition:unknown):unknown;
  clientPrepareInstalledSequenceContracts(registry:string,values:string,fragment:string,ordered:string):unknown;
  clientProgramOpenSourceFreeLocalEffectHost(bound:unknown,contracts:unknown,values:string,
    runs:bigint,transfer:bigint,retained:bigint,execution:bigint,fragment:string,ordered:string):OwnedEffect|undefined;
  clientProgramPinEffectSources(owned:OwnedEffect,maxInputs:number):unknown;
  clientProgramEffectLocalResultCount(inputs:unknown):number;
  clientProgramEffectLocalResultMatchesMember(inputs:unknown,index:number,member:number):boolean;
  clientProgramReleaseEffectInputs(inputs:unknown):unknown;
  clientProgramEffectProposalBegin(inputs:unknown,member:number,rows:number,work:number):unknown;
  clientProgramEffectCheckedProposalRow(plan:unknown,exported:unknown,original:unknown,
    fields:number,work:number,nodes:number,depth:number,text:number):unknown;
  clientProgramEffectProposalFinish(plan:unknown,rows:number):unknown;
  clientProgramEffectProposalCancel(plan:unknown):unknown;
  clientProgramEffectNotionPropertyWrite(row:unknown,field:number,catalog:unknown,property:number,limits:unknown):unknown;
  clientProgramEffectNotionWritesJson(row:unknown,catalog:unknown,writes:readonly unknown[],limits:unknown):unknown;
  clientProgramEffectCheckedProposalRowRetire(row:unknown):unknown;
};

const {moon, publicationEvidence}:{
  moon:Common;publicationEvidence(prepared:unknown):PublicationEvidence;
}=await import(new URL('../../../host-node/fixtures/command-original-key.fixture.mjs',import.meta.url).href);

export {moon};
const cid = (value:unknown) => `sha256:${createHash('sha256').update(canonicalText(value)).digest('hex')}`;
const ref = (digit:string) => `sha256:${digit.repeat(64)}`;
export const propertyWriteLimits = Object.freeze({maxBytes: 65536, maxNodes: 4096,
  maxDepth: 16, maxProperties: 4, maxItems: 100, maxTextUnits: 10000, maxWork: 100000});
export const originalRowLimits = Object.freeze({maxRows: 2, maxFields: 10, maxWork: 100000,
  maxNodes: 100, maxDepth: 16, maxTextBytes: 1000});

export function originalNotionCatalog() {
  const limits = moon.clientProgramNotionDatabaseLimits(8192, 512, 16, 8, 8, 128, 128);
  const database = checked(moon.clientProgramNotionProjectDatabase(Buffer.from(
    '{"object":"database","id":"db","data_sources":[{"id":"other","name":"Main"},{"id":"selected","name":"Main"}]}'), limits));
  const source = checked(moon.clientProgramNotionProjectDataSource(database, 1, Buffer.from(
    '{"object":"data_source","id":"selected","parent":{"type":"database_id","database_id":"db"},"properties":{"Budget":{"id":"amount%3Aid","name":"Budget","type":"number","number":{}},"Period":{"id":"date%3Aid","name":"Period","type":"date","date":{}},"Notes":{"id":"text%3Aid","name":"Notes","type":"rich_text","rich_text":{}}}}'), limits));
  return source;
}

export function writeLimits() {
  const p = propertyWriteLimits;
  return moon.clientProgramNotionPropertyWriteLimits(p.maxBytes, p.maxNodes, p.maxDepth,
    p.maxProperties, p.maxItems, p.maxTextUnits, p.maxWork);
}

export async function originalNotionEffectValuesFixture() {
  const base = JSON.parse(await readFile(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8')) as Record<string,unknown>;
  const manifest = {version: 'actql-connectors/0.1', connectors: [
    {connector: 'notion', connector_id: 'notion', connector_version: 'fixture'}]};
  const catalogBody = {schema: 'actql.connector_catalog/0.1', connector_id: 'notion',
    connector_version: 'fixture', commands: [], contracts: [], source_views: []};
  const catalog = {...catalogBody, catalog_cid: cid(catalogBody)};
  const fields = {
    Amount: {type: 'decimal', precision: 20, scale: 2, nullable: false},
    End: {type: 'date', nullable: true}, Id: {type: 'string', nullable: false},
    Plain: {type: 'string', nullable: false}, Start: {type: 'date', nullable: false},
  };
  const targetSchema = {type: 'object', nullable: false, additional_properties: false, fields};
  const names = ['Amount', 'End', 'Plain', 'Start'];
  const mappingBody = {schema: 'actql.mapping_contract/0.1', version: 'fixture',
    connector_manifest_cid: cid(manifest.connectors[0]), conversions: [], mapping_ref: 'mapping:notion.fixture.v1',
    minimum_approval: 'none', primary_identity: 'Id', required_fields: [], required_permissions: [],
    resource_identity_cid: ref('b'), target_ref: 'connector://notion/pages',
    permission_rules: [{effect_kind: 'update', permissions: ['scope:write'], selector_class: 'id', write_fields: names}],
    row_mapping: {Amount: {field: 'amount', null_behavior: 'reject'},
      End: {field: 'end', null_behavior: 'write_null'}, Plain: {field: 'plain', null_behavior: 'reject'},
      Start: {field: 'start', null_behavior: 'reject'}},
    target_schema: targetSchema, target_schema_identity: cid(targetSchema), writable_fields: names};
  const body:Record<string,unknown> = {...base, connector_manifest: manifest, connector_catalogs: [catalog],
    mapping_contracts: [{...mappingBody, mapping_contract_cid: cid(mappingBody)}]};
  delete body.evidence_bundle_cid;
  const environmentCid = cid(body);
  const environment = moon.clientProgramCheckEnvironment(
    canonicalText({...body, evidence_bundle_cid: environmentCid}), environmentCid,
    false, false, true, false, false, false, false);
  assert(environment, 'independently authored original Mapping environment');
  const program = {version: 'actql/0.1', id: 'notion-original-property-values', stages: [{id: 'values',
    inputs: {}, steps: [{values: {schema: {
      id: {type: 'string', nullable: false}, amount: fields.Amount,
      end: fields.End, plain: fields.Plain, start: fields.Start,
    }, rows: [
      {id: 'one', amount: '9007199254740993.25', start: '2024-02-29', end: null, plain: '2024-02-29'},
      {id: 'two', amount: '-9007199254740993.25', start: '2024-03-01', end: '2024-03-02', plain: '2024-03-01'},
    ]}, as: 'selected'}],
    results: {out: {from: 'selected', fields: ['plain', 'end', 'id', 'start', 'amount']}},
    effects: {save: {update: {target: 'connector://notion/pages', mapping: 'mapping:notion.fixture.v1',
      from: {result: 'out'}, id: 'id', set: {Amount: {field: 'amount'}, End: {field: 'end'},
        Plain: {field: 'plain'}, Start: {field: 'start'}}}}},
  }], results: {published: {from: {stage: 'values', result: 'out'}}}};
  const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
    canonicalText(program), 'json', environment, undefined, []);
  const prepared = moon.clientProgramEffectPreparationReady(outcome);
  assert(prepared, inspect(moon.clientProgramEffectPreparationIssue(outcome), {depth: 12}));
  const admission = moon.clientProgramAdmitEffectPublication(prepared, ...publicationEvidence(prepared));
  assert(admission, 'explicit fixture publication metadata');
  const definition = checked(moon.strategyIssueRunDefinition(admission, 'notion-codec-fixture-scope',
    'notion-codec-fixture', ref('c'), '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z', 100000, 10000, 64));
  const bound = moon.clientProgramBindEffectRun(prepared, admission, definition);
  assert(bound);
  const registry = await readFile(new URL('../../../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8');
  const aoa = JSON.parse(await readFile(new URL('../../../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  const values = JSON.stringify(aoa.execution_contracts['REL.values']);
  const fragment = JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
  const ordered = JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
  const contracts = checked(moon.clientPrepareInstalledSequenceContracts(registry, values, fragment, ordered));
  const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(bound, contracts,
    values, 1n, 0n, 0n, 0n, fragment, ordered);
  assert(owned, 'same original source-free Effect Host');
  let execution:Execution|undefined, inputs:unknown;
  try {
    // The Host's managedPhysicalSource returns an owner only when its withRows port is present.
    execution = await runCapturedEffectComputation(owned) as Execution;
    assert.equal(execution.status, 'host-tasks-completed');
    inputs = checked(moon.clientProgramPinEffectSources(owned, 2));
    const indexes:number[] = [];
    for (let index = 0; index < moon.clientProgramEffectLocalResultCount(inputs); index++) {
      if (moon.clientProgramEffectLocalResultMatchesMember(inputs, index, 0)) indexes.push(index);
    }
    assert.equal(indexes.length, 1);
    const limits = moon.clientProgramEffectInputExportLimits(
      10, 1000, 10000, 100, 100, 10000, 100000, 64, 100000,
      100000, 10000, 64, 10, 10000, 100000, 10003, 66, 10, 100000, 10000, 64, 4096);
    assert(limits);
    return {moon, owned, execution, inputs, limits, resultIndex: indexes[0]!,
      originalRowLimits: {maxNodes: 1000, maxDepth: 64, maxUtf16Units: 10000},
      async close() {
        moon.clientProgramReleaseEffectInputs(inputs);
        await execution!.close();
        assert.equal(execution!.cleanupPending(), false);
      }};
  } catch (cause) {
    if (inputs !== undefined) moon.clientProgramReleaseEffectInputs(inputs);
    if (execution !== undefined) await execution.close();
    throw cause;
  }
}
