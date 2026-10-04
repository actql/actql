import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, readdir} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';

// The same independent oracle runs against source and repository-external
// tarballs. The packed branch imports no checkout implementation or toolchain.
const packed = process.env.ACTQL_PROPERTY_GRAPH_PACKED === '1';
const {connect, ClientError} = await import(packed ? '@actql/sdk' : '../packages/sdk/index.mjs');
const {connectEmbeddedLocal, openInstalledRemoteHttpHost} = await import(packed
  ? new URL('./adapters/host-node/embedded-local.mjs', import.meta.resolve('@actql/local-node'))
  : '../adapters/host-node/embedded-local.mjs');

const fixture = JSON.parse(await readFile(new URL('./fixtures/property-graph-parallel.program.json', import.meta.url), 'utf8'));
const presenceFixture = JSON.parse(await readFile(new URL('./fixtures/property-graph-presence.program.json', import.meta.url), 'utf8'));
const definitionFixture = JSON.parse(await readFile(new URL('./fixtures/property-graph-definition-rows.program.json', import.meta.url), 'utf8'));
const labelFixture = JSON.parse(await readFile(new URL('./fixtures/property-graph-label-rows.program.json', import.meta.url), 'utf8'));
const selectorDeriveFixture = JSON.parse(await readFile(new URL('./fixtures/property-graph-selector-derive.program.json', import.meta.url), 'utf8'));
const traversalFixture = JSON.parse(await readFile(new URL('./fixtures/property-graph-traverse-nodes.expected.json', import.meta.url), 'utf8'));
// Use the existing authoritative inventory, not a second supported-operation
// list or hand-authored per-consumer request fixtures. The common checker
// refuses unsupported operation keys before interpreting their payloads.
const coverage = JSON.parse(await readFile(new URL(packed
  ? './local-family-coverage.json'
  : '../docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json', import.meta.url), 'utf8'));
const unsupported = coverage.operations.filter(entry =>
  coverage.current_graph_profile.classification[entry.operation] === 'blocked');
assert(unsupported.length > 0);
assert(unsupported.every(entry => entry.status === 'blocked'));
const scratch = new URL(packed ? './state/' : '../_build/property-graph-public-host/', import.meta.url);
await mkdir(scratch, {recursive:true});
const cid = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');

// Independent definition preimage: source aliases become ordered occurrences;
// input data is an inline VALUES definition here, not a bound Artifact or Run.
const constructor = structuredClone(fixture.stages[0].steps[2].property_graph);
let occurrence = 0;
for (const family of ['nodes','edges']) for (const element of constructor[family]) {
  delete element.from;
  element.input_occurrence = occurrence++;
}
const expectedDomain = cid({constructor,
  producer_definitions:fixture.stages[0].steps.slice(0, 2)
    .map(step => ({body:{values:step.values},dependencies:[]})),
  version:'actql-property-graph-definition/0.1'});
const identity = (definition, key) => ({definition,domain:expectedDomain,
  key:['a',key],key_types:[{kind:'string'},{kind:'number'}]});
// Independent canonical snapshot oracle: the constructor definition fixes
// the schema/domain; input rows fix two distinct edge identities. No product
// encoder output is copied into an expected value.
const number = {type:'number',nullable:false};
const string = {type:'string',nullable:false};
const lawCid = 'sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc';
const graphContract = {version:'actql-property-graph-contract/0.1',domain:expectedDomain,
  identity_law_cid:lawCid,value_law_cid:lawCid,
  node_definitions:[{name:'N',key_columns:['tenant','id'],key_contracts:[string,number],
    labels:{Node:['id','tenant'],Person:[]},properties:{id:number,tenant:string}}],
  edge_definitions:[{name:'E',key_columns:['tenant','key'],key_contracts:[string,number],labels:{Link:[],R:['dst','key','src','tenant']},
    properties:{dst:number,key:number,src:number,tenant:string},source_definition:'N',target_definition:'N'}]};
const expectedSnapshot = canonicalText(['actql-property-graph-snapshot/0.1',cid(graphContract),graphContract,
  [{id:identity('N',1),key:['a',1],props:{id:1,tenant:'a'}}],
  [10,11].map(key => ({id:identity('E',key),key:['a',key],props:{key,src:1,dst:1,tenant:'a'},
    src:identity('N',1),dst:identity('N',1)}))]);
const snapshotCid = 'sha256:' + createHash('sha256').update(expectedSnapshot).digest('hex');

const presenceConstructor = structuredClone(presenceFixture.stages[0].steps[3].property_graph);
occurrence = 0;
for (const family of ['nodes','edges']) for (const element of presenceConstructor[family]) {
  delete element.from;
  element.input_occurrence = occurrence++;
}
const presenceDomain = cid({constructor:presenceConstructor,
  producer_definitions:presenceFixture.stages[0].steps.slice(0,3)
    .map(step => ({body:{values:step.values},dependencies:[]})),
  version:'actql-property-graph-definition/0.1'});
const presenceIdentity = (definition, key, kinds) => ({definition,domain:presenceDomain,
  key,key_types:kinds.map(kind=>({kind}))});
const nodeIdentity = key => presenceIdentity('N',[key,'a'],['number','string']);
const presenceContract = {version:'actql-property-graph-contract/0.1',domain:presenceDomain,
  identity_law_cid:lawCid,value_law_cid:lawCid,
  node_definitions:[{name:'M',key_columns:['company_key'],key_contracts:[number],labels:{},properties:{}},
    {name:'N',key_columns:['person_key','tenant_key'],key_contracts:[number,string],
      labels:{Owner:['p'],Person:['p']},properties:{p:{type:'number',nullable:true}}}],
  edge_definitions:[{name:'E',key_columns:['edge_key','tenant_key'],key_contracts:[number,string],
    labels:{Link:[]},properties:{},source_definition:'N',target_definition:'N'}]};
const presenceSnapshot = canonicalText(['actql-property-graph-snapshot/0.1',cid(presenceContract),presenceContract,
  [{id:presenceIdentity('M',[3],['number']),key:[3],props:{}},
    ...[1,2].map(key=>({id:nodeIdentity(key),key:[key,'a'],props:{p:key===1 ? 7 : null}}))],
  [10,11].map(key=>({id:presenceIdentity('E',[key,'a'],['number','string']),key:[key,'a'],props:{},
    src:nodeIdentity(1),dst:nodeIdentity(2)}))]);
const presenceSnapshotCid = 'sha256:' + createHash('sha256').update(presenceSnapshot).digest('hex');
// Independent full Relation streams, including unprojected conditional fields.
// These are canonical ordered rows, not bytes captured from the implementation.
const presenceRows = {
  node_rows: [{company_key:3,id:presenceIdentity('M',[3],['number']),labels:[]},
    ...[1,2].map(key=>({id:nodeIdentity(key),labels:['Owner','Person'],
      p:key===1 ? 7 : null,person_key:key,tenant_key:'a'}))],
  edge_rows: [10,11].map(key=>({edge_key:key,
    id:presenceIdentity('E',[key,'a'],['number','string']),
    src:nodeIdentity(1),dst:nodeIdentity(2),labels:['Link'],tenant_key:'a'})),
};
// The source fixture deliberately supplies descending keys. Canonical Graph
// order must be established, not inherited accidentally from already sorted input.
assert.deepEqual(presenceFixture.stages[0].steps[0].values.rows.map(row=>row.person_key),[2,1]);
assert.deepEqual(presenceFixture.stages[0].steps[2].values.rows.map(row=>row.edge_key),[11,10]);

function presenceFilterScenario(empty, selection = false, companyKey = 3) {
  const document = structuredClone(presenceFixture);
  document.id = `presence-${selection ? 'selection' : 'filter'}-${empty ? 'empty' : 'values'}`;
  const steps = document.stages[0].steps;
  steps[0].values.rows.unshift({person_key:4,tenant_key:'a',p:8});
  steps[1].values = {schema:{person_key:number,tenant_key:string},
    rows:[{person_key:companyKey,tenant_key:'a'}]};
  steps[3].property_graph.nodes[1].key = ['person_key','tenant_key'];
  if (empty) for (const step of steps.slice(0,3)) step.values.rows = [];
  steps[5] = {filter:selection ? 'person_key > 0' : 'person_key < 4',as:'filtered'};
  if (selection) steps.push({sort:[{person_key:'desc'}],as:'sorted'},
    {take:{count:3,offset:1},as:'taken'});
  steps.push({select:['id','labels','person_key'],as:'projected'});
  document.stages[0].results.out.fields = ['id','labels','person_key'];
  const constructor = structuredClone(steps[3].property_graph);
  let occurrence = 0;
  for (const family of ['nodes','edges']) for (const element of constructor[family]) {
    delete element.from;
    element.input_occurrence = occurrence++;
  }
  const domain = cid({constructor,producer_definitions:steps.slice(0,3)
    .map(step=>({body:{values:step.values},dependencies:[]})),
    version:'actql-property-graph-definition/0.1'});
  const identity = (definition,key)=>({definition,domain,key:[key,'a'],
    key_types:[{kind:'number'},{kind:'string'}]});
  // Independently authored canonical order and presence states. The fourth
  // row is removed without removing any of omission, explicit NULL or value.
  const before = empty ? [] : [
    {id:identity('M',companyKey),labels:[],person_key:companyKey,tenant_key:'a'},
    {id:identity('N',1),labels:['Owner','Person'],p:7,person_key:1,tenant_key:'a'},
    {id:identity('N',2),labels:['Owner','Person'],p:null,person_key:2,tenant_key:'a'},
    {id:identity('N',4),labels:['Owner','Person'],p:8,person_key:4,tenant_key:'a'},
  ];
  const sorted = empty ? [] : [before[3],before[0],before[2],before[1]];
  const retained = selection ? sorted.slice(1) : before.slice(0,3);
  const snapshots = selection ? [before,before,sorted,retained] : [before,retained];
  return {document,before,retained,snapshots,expected:retained.map(({id,labels,person_key})=>({id,labels,person_key}))};
}

// Authored heterogeneous declarations and expected streams. The second edge
// uses the same endpoints and raw keys, but remains a distinct definition.
function definitionScenario(projection, empty, alternate = false) {
  const document = structuredClone(presenceFixture);
  document.id = `definition-${projection}-${empty ? 'empty' : 'values'}`;
  const steps = document.stages[0].steps;
  steps[1].values.schema.q = number;
  steps[1].values.rows[0].q = 9;
  steps[3].property_graph.nodes[1].labels = [{name:'Company',properties:
    {mode:'columns',columns:[{from:'q',to:'q'}]}}];
  steps[3].property_graph.edges[0].labels[0].properties =
    {mode:'columns',columns:[{from:'source_key',to:'weight'}]};
  steps[3].property_graph.edges.push({...structuredClone(steps[3].property_graph.edges[0]),
    name:'F',labels:[{name:'Other',properties:{mode:'columns',columns:[{from:'target_key',to:'score'}]}}]});
  if (empty) steps[0].values.rows = [];
  const selected = projection === 'node_rows' ? (alternate ? 'M' : 'N') : (alternate ? 'F' : 'E');
  const property = projection === 'node_rows' ? (alternate ? 'q' : 'p') : (alternate ? 'score' : 'weight');
  const key = projection === 'node_rows' ? (alternate ? 'company_key' : 'person_key') : 'edge_key';
  steps[4] = {from:'g',[projection]:{definition:selected.toLowerCase()},as:'rows'};
  steps[5] = {filter:`${property} IS NULL OR ${property} > 0`,as:'filtered'};
  steps.push({rename:{[property]:'value'},as:'renamed'},
    {select:['id',key,'value'],as:'projected'});
  document.stages[0].results.out.fields = ['id',key,'value'];
  const ctor = structuredClone(steps[3].property_graph);
  const producerDefinitions = [];
  let occurrence = 0;
  for (const family of ['nodes','edges']) for (const element of ctor[family]) {
    const source = steps.slice(0,3).find(step=>step.as === element.from);
    producerDefinitions.push({body:{values:source.values},dependencies:[]});
    delete element.from;
    element.input_occurrence = occurrence++;
  }
  const domain = cid({constructor:ctor,producer_definitions:producerDefinitions,
    version:'actql-property-graph-definition/0.1'});
  const identity = (definition,key,kinds) => ({definition,domain,key,key_types:kinds.map(kind=>({kind}))});
  const node = key=>identity('N',[key,'a'],['number','string']);
  const contract = structuredClone(presenceContract);
  contract.domain = domain;
  Object.assign(contract.node_definitions[0],{labels:{Company:['q']},properties:{q:number}});
  Object.assign(contract.edge_definitions[0],{labels:{Link:['weight']},properties:{weight:number}});
  contract.edge_definitions.push({...structuredClone(contract.edge_definitions[0]),
    name:'F',labels:{Other:['score']},properties:{score:number}});
  const nodes = [{id:identity('M',[3],['number']),key:[3],props:{q:9}},
    ...(empty ? [] : [1,2].map(key=>({id:node(key),key:[key,'a'],props:{p:key===1 ? 7 : null}})))];
  const edges = empty ? [] : ['E','F'].flatMap(definition=>[10,11].map(key=>({
    id:identity(definition,[key,'a'],['number','string']),key:[key,'a'],
    props:definition==='E' ? {weight:1} : {score:2},src:node(1),dst:node(2)})));
  const snapshot = canonicalText(['actql-property-graph-snapshot/0.1',cid(contract),contract,nodes,edges]);
  const retained = projection === 'node_rows' && alternate
    ? [{id:identity('M',[3],['number']),labels:['Company'],company_key:3,q:9}]
    : empty ? [] : projection === 'node_rows'
      ? [1,2].map(key=>({id:node(key),labels:['Owner','Person'],person_key:key,tenant_key:'a',p:key===1 ? 7 : null}))
      : [10,11].map(key=>({id:identity(selected,[key,'a'],['number','string']),src:node(1),dst:node(2),
        labels:[alternate ? 'Other' : 'Link'],edge_key:key,tenant_key:'a',[property]:alternate ? 2 : 1}));
  const expected = retained.map(row=>({id:row.id,[key]:row[key],value:row[property]}));
  return {document,retained,expected,snapshot,property,key};
}
const traversalProgram = structuredClone(fixture);
traversalProgram.stages[0].steps[0].values.rows = traversalFixture.node_keys.map(id=>({id,tenant:'a'}));
traversalProgram.stages[0].steps[1].values.rows = traversalFixture.edges.map(edge=>({...edge,tenant:'a'}));
const traversalDomain = cid({constructor,
  producer_definitions:traversalProgram.stages[0].steps.slice(0,2)
    .map(step=>({body:{values:step.values},dependencies:[]})),
  version:'actql-property-graph-definition/0.1'});
const traversalIdentity = (definition,key)=>({definition,domain:traversalDomain,
  key:['a',key],key_types:[{kind:'string'},{kind:'number'}]});
const traversalContract = {...graphContract,domain:traversalDomain};
// Explicitly canonical expected order, independent of descending source input.
const traversalSnapshot = canonicalText(['actql-property-graph-snapshot/0.1',cid(traversalContract),traversalContract,
  [1,2,3].map(id=>({id:traversalIdentity('N',id),key:['a',id],props:{id,tenant:'a'}})),
  [10,11,12,13,14].map(key=>{
    const edge=traversalFixture.edges.find(edge=>edge.key===key);
    return {id:traversalIdentity('E',key),key:['a',key],props:{...edge,tenant:'a'},
      src:traversalIdentity('N',edge.src),dst:traversalIdentity('N',edge.dst)};
  })]);

// Independent label candidate oracle: two definitions declare the label and
// a third does not. Extra properties/raw aliases remain Conditional, including
// when no candidate row exists. No captured schema or runtime output is used.
function labelScenario(projection, empty) {
  const document = structuredClone(presenceFixture);
  document.id = `label-${projection}-${empty ? 'empty' : 'values'}`;
  const steps = document.stages[0].steps;
  Object.assign(steps[1].values.schema,{p:number,q:number});
  Object.assign(steps[1].values.rows[0],{p:9,q:5});
  steps[3].property_graph.nodes[1].labels = [
    {name:'PERSON',properties:{mode:'columns',columns:[{from:'p',to:'p'}]}},
    {name:'Company',properties:{mode:'columns',columns:[{from:'q',to:'q'}]}},
  ];
  steps[3].property_graph.nodes.push({...structuredClone(steps[3].property_graph.nodes[0]),
    name:'O',labels:[{name:'Other',properties:{mode:'columns',columns:[{from:'p',to:'p'}]}}]});
  const baseEdge = steps[3].property_graph.edges[0];
  baseEdge.labels[0].properties = {mode:'columns',columns:[{from:'source_key',to:'weight'}]};
  steps[3].property_graph.edges.push({...structuredClone(baseEdge),name:'F',labels:[
    {name:'LINK',properties:{mode:'columns',columns:[{from:'target_key',to:'weight'}]}},
    {name:'Extra',properties:{mode:'columns',columns:[{from:'target_key',to:'score'}]}},
  ]}, {...structuredClone(baseEdge),name:'G',labels:[
    {name:'Excluded',properties:{mode:'columns',columns:[{from:'target_key',to:'score'}]}},
  ]});
  if (empty) for (const step of steps.slice(0,3)) step.values.rows = [];
  const label = projection==='node_rows' ? 'Person' : 'Link';
  const property = projection==='node_rows' ? 'p' : 'weight';
  steps[4] = {from:'g',[projection]:{label:label.toLowerCase()},as:'rows'};
  // Existing ordinary Relation kernels require dense input. First use the
  // existing presence-aware Select to prove/retain guaranteed columns; do not
  // weaken their guard or silently fill the remaining Conditional columns.
  steps[5] = {select:['id',property],as:'guaranteed'};
  steps.push({filter:`${property} IS NULL OR ${property} > 0`,as:'filtered'},
    {rename:{[property]:'value'},as:'renamed'}, {select:['id','value'],as:'projected'});
  document.stages[0].results.out.fields = ['id','value'];
  const ctor = structuredClone(steps[3].property_graph);
  const producerDefinitions = [];
  let occurrence = 0;
  for (const family of ['nodes','edges']) for (const element of ctor[family]) {
    const source = steps.slice(0,3).find(step=>step.as===element.from);
    producerDefinitions.push({body:{values:source.values},dependencies:[]});
    delete element.from;
    element.input_occurrence = occurrence++;
  }
  const domain = cid({constructor:ctor,producer_definitions:producerDefinitions,
    version:'actql-property-graph-definition/0.1'});
  const identity = (definition,key,kinds) => ({definition,domain,key,key_types:kinds.map(kind=>({kind}))});
  const node = key=>identity('N',[key,'a'],['number','string']);
  const contract = structuredClone(presenceContract);
  contract.domain = domain;
  Object.assign(contract.node_definitions[0],{labels:{Company:['q'],PERSON:['p']},properties:{p:number,q:number}});
  contract.node_definitions.push({...structuredClone(contract.node_definitions[1]),name:'O',labels:{Other:['p']}});
  Object.assign(contract.edge_definitions[0],{labels:{Link:['weight']},properties:{weight:number}});
  contract.edge_definitions.push({...structuredClone(contract.edge_definitions[0]),
    name:'F',labels:{Extra:['score'],LINK:['weight']},properties:{score:number,weight:number}},
    {...structuredClone(contract.edge_definitions[0]),name:'G',labels:{Excluded:['score']},properties:{score:number}});
  const nodes = empty ? [] : [{id:identity('M',[3],['number']),key:[3],props:{p:9,q:5}},
    ...['N','O'].flatMap(definition=>[1,2].map(key=>({
      id:identity(definition,[key,'a'],['number','string']),key:[key,'a'],props:{p:key===1 ? 7 : null}})))];
  const edges = empty ? [] : ['E','F','G'].flatMap(definition=>[10,11].map(key=>({
    id:identity(definition,[key,'a'],['number','string']),key:[key,'a'],
    props:definition==='E' ? {weight:1} : definition==='F' ? {score:2,weight:2} : {score:2},
    src:node(1),dst:node(2)})));
  const snapshot = canonicalText(['actql-property-graph-snapshot/0.1',cid(contract),contract,nodes,edges]);
  const retained = empty ? [] : projection==='node_rows'
    ? [{company_key:3,id:identity('M',[3],['number']),labels:['Company','PERSON'],p:9,q:5},
      ...[1,2].map(key=>({id:node(key),labels:['Owner','Person'],p:key===1 ? 7 : null,person_key:key,tenant_key:'a'}))]
    : ['E','F'].flatMap(definition=>[10,11].map(key=>({edge_key:key,tenant_key:'a',
      id:identity(definition,[key,'a'],['number','string']),src:node(1),dst:node(2),
      labels:definition==='E' ? ['Link'] : ['Extra','LINK'],
      ...(definition==='E' ? {weight:1} : {score:2,weight:2})})));
  return {document,retained,snapshot,expected:retained.map(row=>({id:row.id,value:row[property]}))};
}

// Reuse each selector's declaration oracle. Required derivation takes place
// before projection so all unrelated Conditional columns cross the Store.
function selectorDeriveScenario(selector, projection, empty) {
  const scenario = selector === 'definition'
    ? definitionScenario(projection,empty) : labelScenario(projection,empty);
  const {document,retained} = scenario;
  document.id = `selector-derive-${selector}-${projection}-${empty ? 'empty' : 'values'}`;
  const property = projection === 'node_rows' ? 'p' : 'weight';
  const steps = document.stages[0].steps;
  steps.splice(5,steps.length - 5,
    {filter:`${property} IS NULL OR ${property} > 0`,as:'filtered'},
    {derive:{z:`${property} + 1`},as:'derived'},
    {select:['id','z'],as:'projected'});
  document.stages[0].results.out.fields = ['id','z'];
  const derived = retained.map(row=>({...row,z:row[property] === null ? null : row[property] + 1}));
  return {...scenario,derived,expected:derived.map(row=>({id:row.id,z:row.z}))};
}

function minimalSelectorDeriveScenario() {
  const document=structuredClone(selectorDeriveFixture);
  const ctor=structuredClone(document.stages[0].steps[2].property_graph);
  const producers=document.stages[0].steps.slice(0,2).map(step=>({body:{values:step.values},dependencies:[]}));
  for (const [index,node] of ctor.nodes.entries()) { delete node.from; node.input_occurrence=index; }
  const domain=cid({constructor:ctor,producer_definitions:producers,version:'actql-property-graph-definition/0.1'});
  const identity=(definition,key)=>({definition,domain,key:[key],key_types:[{kind:'number'}]});
  const contract={version:'actql-property-graph-contract/0.1',domain,identity_law_cid:lawCid,value_law_cid:lawCid,
    node_definitions:[
      {name:'Company',key_columns:['company_key'],key_contracts:[number],labels:{Company:['q'],PERSON:['p']},properties:{p:number,q:string}},
      {name:'Person',key_columns:['person_key'],key_contracts:[number],labels:{Person:['p']},properties:{p:{type:'number',nullable:true}}},
    ],edge_definitions:[]};
  const nodes=[{id:identity('Company',3),key:[3],props:{p:9,q:'company'}},
    {id:identity('Person',1),key:[1],props:{p:7}},{id:identity('Person',2),key:[2],props:{p:null}}];
  const snapshot=canonicalText(['actql-property-graph-snapshot/0.1',cid(contract),contract,nodes,[]]);
  const retained=[{id:identity('Company',3),company_key:3,labels:['Company','PERSON'],p:9,q:'company'},
    {id:identity('Person',1),person_key:1,labels:['Person'],p:7},
    {id:identity('Person',2),person_key:2,labels:['Person'],p:null}];
  const derived=retained.map(row=>({...row,z:row.p===null ? null : row.p+1}));
  return {document,retained,derived,snapshot,expected:derived.map(({id,z})=>({id,z}))};
}

function presenceKeyedDistinctScenario(empty) {
  const scenario = presenceFilterScenario(empty, false, 1);
  const {document,before} = scenario;
  document.id = `presence-keyed-distinct-${empty ? 'empty' : 'values'}`;
  // Two definitions share a raw key value, but not their typed Graph id.
  // The chosen key projection alone determines DISTINCT equality.
  const steps = document.stages[0].steps;
  steps.splice(5,steps.length-5,{distinct:['person_key'],as:'projected'});
  document.stages[0].results.out.fields = ['person_key'];
  // Input canonical order is M:1, N:1, N:2, N:4. DISTINCT retains the
  // first complete projected occurrence; optional p never participates.
  const expected = empty ? [] : [{person_key:1},{person_key:2},{person_key:4}];
  return {document,before,expected};
}

function presenceGroupScenario(empty) {
  const {document,before} = presenceFilterScenario(empty, false, 1);
  document.id = `presence-group-${empty ? 'empty' : 'values'}`;
  document.stages[0].steps.splice(5,document.stages[0].steps.length-5,
    {group:{by:['person_key'],aggregates:{
      m:{fn:'max',expr:'person_key',filter:'person_key > 0'},n:{fn:'count'},
    }},as:'grouped'});
  document.stages[0].results.out.from = 'grouped';
  document.stages[0].results.out.fields = ['person_key','m','n'];
  // M:1 and N:1 coalesce on the guaranteed raw key. Their optional property
  // states do not change the count/max; canonical GROUP key order is numeric.
  const expected = empty ? [] : [
    {person_key:1,m:1,n:2},{person_key:2,m:2,n:1},{person_key:4,m:4,n:1},
  ];
  return {document,before,expected};
}

for (const mode of ['local','remote']) for (const profile of ['graph','presence-filter','presence-selection','selector-derive','presence-keyed-distinct','presence-group']) {
  const name = profile === 'graph'
    ? `keyed constructor and TRAIL reach public Named Results through ${mode}`
    : profile === 'presence-group'
      ? `presence group survives Relation Store and public Named Results through ${mode}`
    : profile === 'presence-keyed-distinct'
      ? `presence keyed distinct survives Relation Store and public Named Results through ${mode}`
    : profile === 'selector-derive'
      ? `selector property derive survives Relation Store and public Named Results through ${mode}`
      : `presence ${profile === 'presence-filter' ? 'filter' : 'selection sort and take'} survives Relation Store and public Named Results through ${mode}`;
  test(name, {timeout:60_000}, async t => {
    const directory = await mkdtemp(new URL(`${mode}-`, scratch));
    t.diagnostic(`Retained Host regression evidence: ${directory}`);
    const snapshots = new Map();
    const relationSnapshots = new Map();
    const snapshotWaiters = new Map();
    const physicalSteps = [];
    const keys = generateKeyPairSync('ed25519');
    const authorization = {accountConfiguration:canonicalText({
      version:'actql-execution-account-config/0.1',account_id:'graph-test-owner',
      entries:[{entry_id:'graph-test-allow',outcome:'allow',principal:{all:true},
        connection:{all:true},resource:{all:true},operation:{all:true},exclusions:[]}]}),
      hostKey:{keyId:'graph-test-host',
      privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})},
      reviewers:[{keyId:'graph-test-reviewer',reviewerId:'graph-test-reviewer',
        principalId:userInfo().username,
        publicKey:keys.publicKey.export({type:'spki',format:'pem'})}],
      observe(name, detail) {
        if (name === 'dispatch_failed') t.diagnostic(`Dispatch failure: ${detail.code}`);
      },
      faultInjection(name, detail) {
      physicalSteps.push(name);
      if (name === 'computed') {
        snapshots.set(detail.ref.runDefinitionCid, detail.carrierSnapshots);
        relationSnapshots.set(detail.ref.runDefinitionCid, detail.relationSnapshots);
        snapshotWaiters.get(detail.ref.runDefinitionCid)?.();
      }
    }};
    const assertSnapshot = async (run, task = 2, expectedCid = snapshotCid, expectedBytes = expectedSnapshot) => {
      // This awaited installed fault hook observes the completed physical
      // route, not an SDK-created diagnostic or a new execution authority.
      if (!snapshots.has(run.ref.runDefinitionCid)) await new Promise(resolve =>
        snapshotWaiters.set(run.ref.runDefinitionCid,resolve));
      assert.deepEqual(snapshots.get(run.ref.runDefinitionCid), [{task,cid:expectedCid,
        bytes:Buffer.byteLength(expectedBytes),verifiedReadBytes:Buffer.byteLength(expectedBytes),
        sourceReleased:true,restored:true,temporaryBodyReclaimed:true}]);
      assert.deepEqual(await readdir(`${directory}/carrier-snapshots`), []);
    };
    let host, server, client;
    if (mode === 'local') {
      client = await connectEmbeddedLocal({mode,owner:'local',installation:{directory,authorization}});
    } else {
      host = await openInstalledRemoteHttpHost({directory,authorization,
        authenticate:header=>header === 'Bearer synthetic-test-token' ? userInfo().username : undefined});
      t.after(async () => { await host.close(); });
      let material;
      if (packed) {
        const read = name => readFile(new URL(`./tls/${name}`, import.meta.url));
        material = {ca:await read('ca.crt'),siteKey:await read('site.key'),siteCertificate:await read('site.crt')};
      } else {
        const {certificates} = await import('../adapters/site-node/https-agent-harness.mjs');
        const tlsDirectory = await mkdtemp(new URL('tls-', scratch));
        material = await certificates(tlsDirectory);
      }
      const previousCAs = getCACertificates('default');
      // Trust the synthetic fixture CA; TLS and hostname checks stay enabled.
      setDefaultCACertificates([...previousCAs,material.ca.toString('utf8')]);
      t.after(() => setDefaultCACertificates(previousCAs));
      server = createServer({key:material.siteKey,cert:material.siteCertificate},host.handler);
      await new Promise((resolve,reject) => {server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
      t.after(() => new Promise((resolve,reject) => server.close(error => error ? reject(error) : resolve())));
      client = await connect({mode,endpoint:`https://127.0.0.1:${server.address().port}/`,token:'synthetic-test-token'});
    }
    t.after(() => client.close());
    if (profile === 'presence-group') {
      for (const empty of [false,true]) {
        const {document,before,expected} = presenceGroupScenario(empty);
        const run = await client.aql(canonicalText(document),
          {format:'json',requestId:`${document.id}-${mode}`});
        const state = await run.wait();
        assert.equal(state.status,'succeeded',JSON.stringify(state));
        assert.deepEqual(await run.result('answer').all(),expected);
        assert.deepEqual(await (await client.attach(run.ref)).result('answer').all(),expected);
        assert.deepEqual((await run.result('answer').describe()).columns,
          [{name:'person_key',contract:number},
            {name:'m',contract:{type:'number',nullable:true}},{name:'n',contract:number}]);
        assert.deepEqual(relationSnapshots.get(run.ref.runDefinitionCid),
          [[4,before],[5,expected]].map(([task,rows])=>{
            const bytes = canonicalText(rows);
            return {task,cid:cid(rows),bytes:Buffer.byteLength(bytes),
              verifiedReadBytes:Buffer.byteLength(bytes),rows:rows.length,
              sourceReleased:true,sourceReadRejected:true,restored:true,temporaryBodyReclaimed:true};
          }));
        assert.deepEqual(await readdir(`${directory}/carrier-snapshots`),[]);
      }
      // Check all authored reference lanes, even unused/dead branches. An
      // empty Relation cannot turn a Conditional property into a Required one.
      for (const empty of [false,true]) for (const group of [
        {by:['p'],aggregates:{n:{fn:'count'}}},
        {by:['person_key'],aggregates:{n:{fn:'count',field:'p'}}},
        {by:['person_key'],aggregates:{n:{fn:'max',expr:'if(false, p, person_key)'}}},
        {by:['person_key'],aggregates:{n:{fn:'count',filter:'false AND p IS NOT NULL'}}},
        {by:['person_key'],aggregates:{n:{fn:'first',field:'person_key',order_by:[{p:'asc'}]}}},
      ]) {
        const {document} = presenceGroupScenario(empty);
        document.stages[0].steps[5].group = group;
        const requestId = `conditional-group-${mode}-${empty}-${cid(group)}`;
        const before = physicalSteps.length;
        await assert.rejects(client.aql(canonicalText(document),{format:'json',requestId}),
          error=>error instanceof ClientError && error.code === 'ClientProgramRejected');
        assert.deepEqual(await client.lookupRequest(requestId),{kind:'not_found'});
        assert.deepEqual(physicalSteps.slice(before),[]);
      }
      return;
    }
    if (profile === 'presence-keyed-distinct') {
      for (const empty of [false,true]) {
        const {document,before,expected} = presenceKeyedDistinctScenario(empty);
        const run = await client.aql(canonicalText(document),
          {format:'json',requestId:`${document.id}-${mode}`});
        const state = await run.wait();
        assert.equal(state.status,'succeeded',JSON.stringify(state));
        assert.deepEqual(await run.result('answer').all(),expected);
        assert.deepEqual(await (await client.attach(run.ref)).result('answer').all(),expected);
        assert.deepEqual((await run.result('answer').describe()).columns,
          [{name:'person_key',contract:number}]);
        assert.deepEqual(relationSnapshots.get(run.ref.runDefinitionCid),
          [[4,before],[5,expected]].map(([task,rows])=>{
            const bytes = canonicalText(rows);
            return {task,cid:cid(rows),bytes:Buffer.byteLength(bytes),
              verifiedReadBytes:Buffer.byteLength(bytes),rows:rows.length,
              sourceReleased:true,sourceReadRejected:true,restored:true,temporaryBodyReclaimed:true};
          }));
        assert.deepEqual(await readdir(`${directory}/carrier-snapshots`),[]);
      }
      for (const distinct of [['p'],true]) {
        const {document} = presenceKeyedDistinctScenario(false);
        document.stages[0].steps[5].distinct = distinct;
        const requestId = `conditional-distinct-${mode}-${String(distinct)}`;
        const before = physicalSteps.length;
        await assert.rejects(client.aql(canonicalText(document),{format:'json',requestId}),
          error=>error instanceof ClientError && error.code === 'ClientProgramRejected');
        assert.deepEqual(await client.lookupRequest(requestId),{kind:'not_found'});
        assert.deepEqual(physicalSteps.slice(before),[]);
      }
      return;
    }
    if (profile === 'selector-derive') {
      for (const [selector,projection,empty] of [
        ['definition','node_rows',false], ['definition','edge_rows',false], ['definition','edge_rows',true],
        ['label','node_rows',true], ['label','node_rows',false], ['label','edge_rows',false],
        ['fixture','node_rows',false],
      ]) {
        const {document,retained,derived,expected,snapshot} = selector === 'fixture'
          ? minimalSelectorDeriveScenario() : selectorDeriveScenario(selector,projection,empty);
        const run = await client.aql(canonicalText(document),
          {format:'json',requestId:`${document.id}-${mode}`});
        const state = await run.wait();
        assert.equal(state.status,'succeeded',JSON.stringify(state));
        assert.deepEqual(await run.result('answer').all(),expected);
        assert.deepEqual(await (await client.attach(run.ref)).result('answer').all(),expected);
        const columns = (await run.result('answer').describe()).columns;
        assert.deepEqual(columns.map(column=>column.name),['id','z']);
        assert.equal(columns[1].contract.nullable,projection === 'node_rows');
        await assertSnapshot(run,selector === 'fixture' ? 2 : 3,'sha256:'+createHash('sha256').update(snapshot).digest('hex'),snapshot);
        const stages = selector === 'label' ? [[4,retained],[5,retained],[6,derived]]
          : selector === 'fixture' ? [[3,retained],[4,retained],[5,derived]]
          : [[4,retained],[6,derived]];
        assert.deepEqual(relationSnapshots.get(run.ref.runDefinitionCid),stages.map(([task,rows])=>{
          const bytes=canonicalText(rows);
          return {task,cid:cid(rows),bytes:Buffer.byteLength(bytes),verifiedReadBytes:Buffer.byteLength(bytes),
            rows:rows.length,sourceReleased:true,sourceReadRejected:true,restored:true,temporaryBodyReclaimed:true};
        }));
      }
      // A common label cannot prove a property belonging to just one candidate,
      // not even when no rows exist or the branch would never be evaluated.
      for (const empty of [false,true]) {
        const {document} = selectorDeriveScenario('label','node_rows',empty);
        document.stages[0].steps[6].derive.z = 'if(false, q, 0)';
        const requestId=`conditional-derive-${mode}-${empty}`;
        const before=physicalSteps.length;
        await assert.rejects(client.aql(canonicalText(document),
          {format:'json',requestId}),
        error=>error instanceof ClientError && error.code === 'ClientProgramRejected');
        assert.deepEqual(await client.lookupRequest(requestId),{kind:'not_found'});
        assert.deepEqual(physicalSteps.slice(before),[]);
      }
      return;
    }
    if (profile !== 'graph') {
      for (const empty of [false,true]) {
        const {document,snapshots:expectedSnapshots,expected} = presenceFilterScenario(empty, profile === 'presence-selection');
        const run = await client.aql(canonicalText(document),
          {format:'json',requestId:`${document.id}-${mode}`});
        const state = await run.wait();
        assert.equal(state.status,'succeeded',JSON.stringify(state));
        assert.deepEqual(await run.result('answer').all(),expected);
        assert.deepEqual(await (await client.attach(run.ref)).result('answer').all(),expected);
        assert.deepEqual((await run.result('answer').describe()).columns.map(column=>column.name),
          ['id','labels','person_key']);
        // Save each sparse intermediate through the real Relation Store,
        // revoke source cell access, and reload before the next operation.
        assert.deepEqual(relationSnapshots.get(run.ref.runDefinitionCid),
          expectedSnapshots.map((rows,index)=>{
            const bytes = canonicalText(rows);
            return {task:4+index,cid:cid(rows),bytes:Buffer.byteLength(bytes),
              verifiedReadBytes:Buffer.byteLength(bytes),rows:rows.length,
              sourceReleased:true,sourceReadRejected:true,restored:true,temporaryBodyReclaimed:true};
          }));
      }
      return;
    }
    // Both public transports must refuse before durable Run acceptance,
    // acquisition I/O or dispatch. A checker-only verdict is not enough.
    for (const entry of unsupported) for (const externalInput of [false,true]) {
      const requestId = `unsupported-${entry.operation}-${mode}-${externalInput}`;
      const rejected = structuredClone(fixture);
      rejected.id = requestId;
      // An unavailable external binding must not turn an unsupported
      // consumer into a Source acquisition or obscure the typed refusal.
      if (externalInput) rejected.stages[0].inputs = {
        unopened:{connector:'unavailable/graph-source',resource:'never-read'},
      };
      rejected.stages[0].steps[3] = {
        from:'g', [entry.operation]:true, as:'matched',
      };
      const before = physicalSteps.length;
      await assert.rejects(client.aql(canonicalText(rejected),
        {format:'json',requestId}), error =>
        error instanceof ClientError && error.code === 'ClientProgramUnsupported');
      assert.deepEqual(await client.lookupRequest(requestId), {kind:'not_found'});
      assert.deepEqual(physicalSteps.slice(before), [],
        `${entry.operation} reached Run admission, acquisition or dispatch`);
      assert.equal(snapshots.size, 0);
    }
    t.diagnostic(`${unsupported.length} inventory-classified unsupported consumers refused with and without external input; no Run or physical work`);
    const run = await client.aql(canonicalText(fixture), {format:'json',requestId:`property-match-${mode}`});
    const state = await run.wait();
    assert.equal(state.status,'succeeded',JSON.stringify(state));
    const result = run.result('answer');
    const description = await result.describe();
    assert.deepEqual(description.columns,[{name:'key',contract:{type:'number',nullable:false}}]);
    assert.deepEqual(await result.all(),[{key:10},{key:11}]);
    await assertSnapshot(run);
    assert.deepEqual(await (await client.attach(run.ref)).result('answer').all(),[{key:10},{key:11}]);

    const trail = structuredClone(fixture);
    trail.id = 'property-graph-trail';
    trail.stages[0].steps.splice(3,1,
      {from:'g',match_nodes:{definition:'N',label:'Node',bindings:{identity:'element'},where:'true',fields:['element']},as:'seeds'},
      {from:'g',traverse:{start:{from:'seeds',id:'element'},direction:'out',min_hops:2,max_hops:2,path_mode:'trail',emit:'paths'},as:'paths'});
    trail.stages[0].results.out = {from:'paths',fields:['start_id','end_id','hop_count','node_ids','edge_ids']};
    const paths = await client.aql(canonicalText(trail), {format:'json',requestId:`property-trail-${mode}`});
    const pathsState = await paths.wait();
    assert.equal(pathsState.status,'succeeded',JSON.stringify(pathsState));
    const rows = await paths.result('answer').all();
    // Independent TRAIL oracle: two different self-loop keys can each be used
    // once; the two ordered two-hop permutations survive. No order is invented.
    const expected = [[10,11],[11,10]].map(keys => ({start_id:identity('N',1),end_id:identity('N',1),
      hop_count:2,node_ids:[identity('N',1),identity('N',1),identity('N',1)],edge_ids:keys.map(key=>identity('E',key))}));
    assert.deepEqual(rows.map(canonicalText).sort(),expected.map(canonicalText).sort());
    await assertSnapshot(paths);

    // Definitions, not sample values or IS NOT NULL, determine row presence.
    // Refusal precedes durable Run acceptance and every physical step.
    for (const selector of ['select','filter','dead-filter']) {
      const rejected = structuredClone(presenceFixture);
      const requestId = `conditional-property-${selector}-${mode}`;
      rejected.stages[0].steps[5] = selector === 'select'
        ? {select:['p'],as:'projected'}
        : {filter:selector === 'dead-filter' ? 'if(false, p > 0, true)' : 'p IS NOT NULL',as:'projected'};
      rejected.stages[0].results.out.fields = selector === 'select' ? ['p'] : ['id'];
      const before = physicalSteps.length;
      await assert.rejects(client.aql(canonicalText(rejected),{format:'json',requestId}),
        error=>error instanceof ClientError && error.code === 'ClientProgramRejected');
      assert.deepEqual(await client.lookupRequest(requestId),{kind:'not_found'});
      assert.deepEqual(physicalSteps.slice(before),[]);
    }
    for (const projection of ['node_rows','edge_rows']) {
      const document = structuredClone(presenceFixture);
      document.id = `property-${projection}`;
      document.stages[0].steps[4] = {from:'g',[projection]:true,as:'rows'};
      const projected = await client.aql(canonicalText(document),
        {format:'json',requestId:`property-${projection}-${mode}`});
      const projectedState = await projected.wait();
      assert.equal(projectedState.status,'succeeded',JSON.stringify(projectedState));
      const actual = await projected.result('answer').all();
      const expected = projection === 'node_rows'
        ? [{id:presenceIdentity('M',[3],['number']),labels:[]},
          ...[1,2].map(key=>({id:nodeIdentity(key),labels:['Owner','Person']}))]
        : [10,11].map(key=>({id:presenceIdentity('E',[key,'a'],['number','string']),labels:['Link']}));
      // node_rows/edge_rows preserve canonical Graph identity order. Compare
      // the ordered oracle directly; sorting would hide a transport regression.
      assert.deepEqual(actual,expected);
      assert.deepEqual((await projected.result('answer').describe()).columns.map(column=>column.name),['id','labels']);
      // The installed route saves the Graph, revokes its source, reloads it,
      // and feeds ordinary Relation projection before public publication.
      await assertSnapshot(projected,3,presenceSnapshotCid,presenceSnapshot);
      // This is Relation retention, not the preceding Graph snapshot. The
      // exact full stream is saved, original cell access is refused, then the
      // same completion is imported and only guaranteed columns are projected.
      const stream = canonicalText(presenceRows[projection]);
      assert.deepEqual(relationSnapshots.get(projected.ref.runDefinitionCid),[
        {task:4,cid:cid(presenceRows[projection]),bytes:Buffer.byteLength(stream),
          verifiedReadBytes:Buffer.byteLength(stream),rows:presenceRows[projection].length,
          sourceReleased:true,sourceReadRejected:true,restored:true,temporaryBodyReclaimed:true},
      ]);
      assert.deepEqual(await (await client.attach(projected.ref)).result('answer').all(),expected);
    }
    for (const projection of ['node_rows','edge_rows']) for (const [empty,alternate] of [[false,false],[true,false],[false,true]]) {
      const {document,retained,expected,snapshot,key} = definitionScenario(projection,empty,alternate);
      const run = await client.aql(canonicalText(document),{format:'json',requestId:`${document.id}-${alternate}-${mode}`});
      const state = await run.wait();
      assert.equal(state.status,'succeeded',JSON.stringify(state));
      assert.deepEqual(await run.result('answer').all(),expected);
      assert.deepEqual(await (await client.attach(run.ref)).result('answer').all(),expected);
      const columns = (await run.result('answer').describe()).columns;
      assert.deepEqual(columns.map(column=>column.name),['id',key,'value']);
      assert.deepEqual(columns[2].contract,projection==='node_rows' && !alternate ? {type:'number',nullable:true} : number);
      await assertSnapshot(run,3,'sha256:'+createHash('sha256').update(snapshot).digest('hex'),snapshot);
      const stream = canonicalText(retained);
      assert.deepEqual(relationSnapshots.get(run.ref.runDefinitionCid),[
        {task:4,cid:cid(retained),bytes:Buffer.byteLength(stream),verifiedReadBytes:Buffer.byteLength(stream),
          rows:retained.length,sourceReleased:true,sourceReadRejected:true,restored:true,temporaryBodyReclaimed:true},
      ]);
    }
    for (const body of [{definition:'Unknown'},{definition:'E'},{definition:'N',label:'Person'},{}]) {
      const {document} = definitionScenario('node_rows',false);
      document.stages[0].steps[4].node_rows = body;
      const requestId = `invalid-definition-${JSON.stringify(body)}-${mode}`;
      const before = physicalSteps.length;
      await assert.rejects(client.aql(canonicalText(document),{format:'json',requestId}),
        error=>error instanceof ClientError && error.code==='ClientProgramRejected');
      assert.deepEqual(await client.lookupRequest(requestId),{kind:'not_found'});
      assert.deepEqual(physicalSteps.slice(before),[]);
    }
    for (const projection of ['node_rows','edge_rows']) for (const empty of [false,true]) {
      const {document,retained,snapshot,expected} = labelScenario(projection,empty);
      const run = await client.aql(canonicalText(document),{format:'json',requestId:`${document.id}-${mode}`});
      const state = await run.wait();
      assert.equal(state.status,'succeeded',JSON.stringify(state));
      assert.deepEqual(await run.result('answer').all(),expected);
      assert.deepEqual(await (await client.attach(run.ref)).result('answer').all(),expected);
      const columns = (await run.result('answer').describe()).columns;
      assert.deepEqual(columns.map(column=>column.name),['id','value']);
      assert.deepEqual(columns[1].contract,projection==='node_rows' ? {type:'number',nullable:true} : number);
      await assertSnapshot(run,3,'sha256:'+createHash('sha256').update(snapshot).digest('hex'),snapshot);
      const stream = canonicalText(retained);
      assert.deepEqual(relationSnapshots.get(run.ref.runDefinitionCid),[
        {task:4,cid:cid(retained),bytes:Buffer.byteLength(stream),verifiedReadBytes:Buffer.byteLength(stream),
          rows:retained.length,sourceReleased:true,sourceReadRejected:true,restored:true,temporaryBodyReclaimed:true},
      ]);
    }
    for (const projection of ['node_rows','edge_rows']) {
      const invalid = [{label:'Unknown'},
        {label:projection==='node_rows' ? 'Link' : 'Person'},
        {label:'Person',definition:'N'}, {label:'Person',extra:true}, {label:7}];
      for (const body of invalid) {
        const {document} = labelScenario(projection,false);
        document.stages[0].steps[4][projection] = body;
        const requestId = `invalid-label-${projection}-${JSON.stringify(body)}-${mode}`;
        const before = physicalSteps.length;
        await assert.rejects(client.aql(canonicalText(document),{format:'json',requestId}),
          error=>error instanceof ClientError && error.code==='ClientProgramRejected');
        assert.deepEqual(await client.lookupRequest(requestId),{kind:'not_found'});
        assert.deepEqual(physicalSteps.slice(before),[]);
      }
      // Actual non-NULL sample data cannot prove Conditional presence. Both
      // populated and empty selection must reject before Run/I/O/dispatch.
      for (const empty of [false,true]) for (const reference of ['projection','predicate']) {
        const {document} = labelScenario(projection,empty);
        const field = projection==='node_rows' ? 'q' : 'score';
        document.stages[0].steps[5] = reference==='projection'
          ? {select:['id',field],as:'guaranteed'}
          : {filter:`${field} IS NOT NULL`,as:'guaranteed'};
        const requestId = `conditional-label-${projection}-${empty}-${reference}-${mode}`;
        const before = physicalSteps.length;
        await assert.rejects(client.aql(canonicalText(document),{format:'json',requestId}),
          error=>error instanceof ClientError && error.code==='ClientProgramRejected');
        assert.deepEqual(await client.lookupRequest(requestId),{kind:'not_found'});
        assert.deepEqual(physicalSteps.slice(before),[]);
      }
    }
    for (const collision of ['id','person_key']) {
      const {document} = definitionScenario('node_rows',false);
      for (const label of document.stages[0].steps[3].property_graph.nodes[0].labels)
        label.properties.columns[0].to = collision;
      const requestId = `selected-collision-${collision}-${mode}`;
      const before = physicalSteps.length;
      await assert.rejects(client.aql(canonicalText(document),{format:'json',requestId}),
        error=>error instanceof ClientError && error.code==='ClientProgramRejected');
      assert.deepEqual(await client.lookupRequest(requestId),{kind:'not_found'});
      assert.deepEqual(physicalSteps.slice(before),[]);
    }
    const minimal = await client.aql(canonicalText(definitionFixture),
      {format:'json',requestId:`minimal-definition-${mode}`});
    const minimalState = await minimal.wait();
    assert.equal(minimalState.status,'succeeded',JSON.stringify(minimalState));
    assert.deepEqual(await minimal.result('answer').all(),[{value:7},{value:null}]);
    assert.deepEqual((await minimal.result('answer').describe()).columns,
      [{name:'value',contract:{type:'number',nullable:true}}]);
    const labelMinimal = await client.aql(canonicalText(labelFixture),
      {format:'json',requestId:`minimal-label-${mode}`});
    const labelMinimalState = await labelMinimal.wait();
    assert.equal(labelMinimalState.status,'succeeded',JSON.stringify(labelMinimalState));
    assert.deepEqual(await labelMinimal.result('answer').all(),[{value:9},{value:7},{value:null}]);
    assert.deepEqual((await labelMinimal.result('answer').describe()).columns,
      [{name:'value',contract:{type:'number',nullable:true}}]);
    for (const [index,scenario] of traversalFixture.cases.entries()) {
      const document = structuredClone(traversalProgram);
      document.id = `property-traverse-nodes-${index}`;
      const start = scenario.relation_start ? {from:'seeds',id:'element'}
        : {ids:scenario.start_keys.map(key=>traversalIdentity('N',key))};
      const body = scenario.hops ? {hops:scenario.hops}
        : {direction:'out',min_hops:scenario.min_hops,max_hops:scenario.max_hops,...scenario.conditions};
      document.stages[0].steps[3] = {from:'g',traverse:{start,...body,path_mode:scenario.path_mode,emit:'nodes'},as:'visited'};
      if (scenario.relation_start) document.stages[0].steps.splice(3,0,
        {from:'g',match_nodes:{definition:'N',label:'Node',bindings:{identity:'element'},
          where:'id = 1',fields:['element']},as:'seeds'});
      document.stages[0].steps.push({from:'visited',select:['start_id','node_id','depth'],as:'projected'});
      document.stages[0].results.out = {from:'projected',fields:['start_id','node_id','depth']};
      let traversed;
      try {
        traversed = await client.aql(canonicalText(document),
          {format:'json',requestId:`traverse-nodes-${index}-${mode}`});
      } catch (cause) {
        throw new Error(`Traversal submission failed: ${scenario.name}; ${String(cause.cause?.cause ?? cause.code)}`,{cause});
      }
      const state = await traversed.wait();
      assert.equal(state.status,'succeeded',JSON.stringify(state));
      const expected = scenario.rows.map(({start_key,node_key,depth})=>({
        start_id:traversalIdentity('N',start_key),node_id:traversalIdentity('N',node_key),depth}));
      assert.deepEqual(await traversed.result('answer').all(),expected,scenario.name);
      assert.deepEqual((await traversed.result('answer').describe()).columns.map(column=>column.name),
        ['start_id','node_id','depth']);
      await assertSnapshot(traversed,2,cid(JSON.parse(traversalSnapshot)),traversalSnapshot);
      const stream=canonicalText(expected);
      assert.deepEqual(relationSnapshots.get(traversed.ref.runDefinitionCid),[
        {task:scenario.relation_start ? 4 : 3,cid:cid(expected),bytes:Buffer.byteLength(stream),verifiedReadBytes:Buffer.byteLength(stream),
          rows:expected.length,sourceReleased:true,sourceReadRejected:true,restored:true,temporaryBodyReclaimed:true},
      ]);
      assert.deepEqual(await (await client.attach(traversed.ref)).result('answer').all(),expected,scenario.name);
    }
  });
}
