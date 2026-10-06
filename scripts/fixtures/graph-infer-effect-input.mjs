// Independent, complete JSON inputs. Only the installation-specific MappingRef
// is bound; no operation, result or assertion is appended by the consumer.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';

// Explicit Host Result Policy admitted by #339's common owner. This original
// records unknown provenance; it is separate from the Model egress contract.
export const graphResultDataPolicy = Object.freeze({
  kind: 'data_policy',
  cid: 'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563',
  wire: '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}',
});

const fixture = name => JSON.parse(readFileSync(new URL(name, import.meta.url), 'utf8'));
const templates = Object.fromEntries(['node','edge'].map(family => [family,
  fixture(`./graph-${family}-infer-effect.program.template.json`)]));
const refusalTemplates = Object.fromEntries(['duplicate-key','null-property']
  .map(variant => [variant,
    fixture(`./graph-node-infer-effect-${variant}.program.template.json`)]));
const normalize = value => Array.isArray(value) ? value.map(normalize)
  : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value)
    .sort().map(key => [key, normalize(value[key])])) : value;
const cid = value => 'sha256:' + createHash('sha256').update(
  JSON.stringify(normalize(value))).digest('hex');

// Graph definition identity is derived from the authored canonical preimage,
// never an admitted Graph, checker, snapshot encoder or observed Result.
const definitionConstructor = structuredClone(templates.node.stages[0].steps[2].graph);
let occurrence = 0;
for (const family of ['nodes','edges']) for (const element of definitionConstructor[family]) {
  delete element.from;
  element.input_occurrence = occurrence++;
}
export const graphDefinitionCid = cid({constructor:definitionConstructor,
  producer_definitions: templates.node.stages[0].steps.slice(0,2)
    .map(step => ({body:{values:step.values},dependencies:[]})),
  version:'actql-graph-definition/0.1'});
const identity = (definition, key) => ({definition,domain:graphDefinitionCid,
  key:['a',key],key_types:[{kind:'string'},{kind:'number'}]});
const classified = definition => [
  {id:1,graph_identity:identity(definition,1),tenant_key:'a',note:7,
    left_amount:10,right_amount:100,risk:'low'},
  {id:2,graph_identity:identity(definition,2),tenant_key:'a',note:null,
    left_amount:20,right_amount:200,risk:'high'},
];
const columns = [
  {name:'id',contract:{type:'number',nullable:false}},
  {name:'graph_identity',contract:{type:'json',nullable:false}},
  {name:'tenant_key',contract:{type:'string',nullable:false}},
  {name:'note',contract:{type:'number',nullable:true}},
  {name:'left_amount',contract:{type:'number',nullable:false}},
  {name:'right_amount',contract:{type:'number',nullable:false}},
  {name:'risk',contract:{type:'string',nullable:true}},
];
export function graphCompositionExpectations(family) {
  assert.ok(['node','edge'].includes(family));
  const rows = classified(family === 'node' ? 'N' : 'E');
  return {classified:rows,updates:[{...rows[1],target_id:'a00000000000002',
    next_name:'review-required'}],classifiedColumns:structuredClone(columns),
    updateColumns:[...structuredClone(columns),
      {name:'target_id',contract:{type:'string',nullable:false,max_utf8_bytes:15}},
      {name:'next_name',contract:{type:'string',nullable:false,max_utf8_bytes:15}}],
    writes:[{id:'a00000000000002',body:{Name:'review-required'}}],
    modelInputs:[100,200],sourceReadSessions:[0,0,0,0],
    effectWriteCounts:[0,0,1,1],restartBoundaries:['capture-waiting','approval-committed']};
}
export function graphCompositionProgram(mappingRef, family) {
  assert.ok(['node','edge'].includes(family));
  return bindMapping(templates[family], mappingRef);
}
function bindMapping(template, mappingRef) {
  assert.equal(typeof mappingRef,'string');
  assert.ok(mappingRef.length > 0);
  const document = structuredClone(template);
  const update = document.stages[2].effects.save.update;
  assert.equal(update.mapping,'__PUBLICATION_MAPPING_REF__');
  update.mapping = mappingRef;
  return document;
}
export function graphCompositionRefusalProgram(mappingRef, variant) {
  assert.ok(Object.hasOwn(refusalTemplates, variant));
  return bindMapping(refusalTemplates[variant], mappingRef);
}
export const graphCompositionTemplates = templates;
export const graphCompositionRefusalTemplates = refusalTemplates;

// The acceptance supervisor runs one dedicated execution child at a time.
// Select its append-only observation window before comparing cleanup counters.
export function computationCustodySince(contents, offset) {
  assert.ok(Number.isSafeInteger(offset) && offset >= 0);
  return contents.trim().split('\n').filter(Boolean).slice(offset).map(line => JSON.parse(line))
    .filter(record => record.pendingScratch);
}
