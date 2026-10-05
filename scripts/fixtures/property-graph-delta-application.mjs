import {createHash} from 'node:crypto';
import {canonicalText} from '../check-canonical-json.mjs';

const cid = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');
const number = {type:'number',nullable:false};
const string = {type:'string',nullable:false};
const lawCid = 'sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc';

// Independent oracle shared by public acceptance and the real managed Host
// stop fixture. Only authored declarations/data enter the expected preimages;
// no product encoder, checker or Delta output supplies an expected value.
export function propertyGraphPresenceOracle(document) {
  const constructor = structuredClone(document.stages[0].steps[3].property_graph);
  let occurrence = 0;
  for (const family of ['nodes','edges']) for (const element of constructor[family]) {
    delete element.from;
    element.input_occurrence = occurrence++;
  }
  const domain = cid({constructor,
    producer_definitions:document.stages[0].steps.slice(0,3)
      .map(step => ({body:{values:step.values},dependencies:[]})),
    version:'actql-property-graph-definition/0.1'});
  const identity = (definition, key, kinds) => ({definition,domain,
    key,key_types:kinds.map(kind=>({kind}))});
  const nodeIdentity = key => identity('N',[key,'a'],['number','string']);
  const contract = {version:'actql-property-graph-contract/0.1',domain,
    identity_law_cid:lawCid,value_law_cid:lawCid,
    node_definitions:[{name:'M',key_columns:['company_key'],key_contracts:[number],labels:{},properties:{}},
      {name:'N',key_columns:['person_key','tenant_key'],key_contracts:[number,string],
        labels:{Owner:['p'],Person:['p']},properties:{p:{type:'number',nullable:true}}}],
    edge_definitions:[{name:'E',key_columns:['edge_key','tenant_key'],key_contracts:[number,string],
      labels:{Link:[]},properties:{},source_definition:'N',target_definition:'N'}]};
  const snapshot = canonicalText(['actql-property-graph-snapshot/0.1',cid(contract),contract,
    [{id:identity('M',[3],['number']),key:[3],props:{}},
      ...[1,2].map(key=>({id:nodeIdentity(key),key:[key,'a'],props:{p:key===1 ? 7 : null}}))],
    [10,11].map(key=>({id:identity('E',[key,'a'],['number','string']),key:[key,'a'],props:{},
      src:nodeIdentity(1),dst:nodeIdentity(2)}))]);
  const snapshotCid = 'sha256:' + createHash('sha256').update(snapshot).digest('hex');
  const rows = {
    node_rows: [{company_key:3,id:identity('M',[3],['number']),labels:[]},
      ...[1,2].map(key=>({id:nodeIdentity(key),labels:['Owner','Person'],
        p:key===1 ? 7 : null,person_key:key,tenant_key:'a'}))],
    edge_rows: [10,11].map(key=>({edge_key:key,
      id:identity('E',[key,'a'],['number','string']),
      src:nodeIdentity(1),dst:nodeIdentity(2),labels:['Link'],tenant_key:'a'})),
  };
  return {contract,identity,nodeIdentity,snapshot,snapshotCid,rows};
}

export function deltaApplicationScenario(fixture, projection, failure, {emptyTarget = false} = {}) {
  const document = structuredClone(fixture);
  document.id = `delta-${projection}-${failure ?? 'valid'}${emptyTarget ? '-empty' : ''}`;
  const oracle = propertyGraphPresenceOracle(fixture);
  const [tag,contractCid,contract,beforeNodes,beforeEdges] = JSON.parse(oracle.snapshot);
  // Replace one property and remove only the second independent parallel edge.
  // Identity, definitions, key components, omission and explicit NULL survive.
  const afterNodes = structuredClone(beforeNodes);
  afterNodes[1].props.p = 8;
  const target = canonicalText([tag,contractCid,contract,
    emptyTarget ? [] : afterNodes,emptyTarget ? [] : [beforeEdges[0]]]);
  const delta = {version:'actql-graph-delta/0.1',graph_contract_cid:contractCid,
    base_graph_cid:oracle.snapshotCid,
    target_graph_cid:'sha256:'+createHash('sha256').update(target).digest('hex'),
    nodes:{add:[],remove:emptyTarget ? beforeNodes : [],
      update:emptyTarget ? [] : [{before:beforeNodes[1],after:afterNodes[1]}]},
    edges:{add:[],remove:emptyTarget ? beforeEdges : [beforeEdges[1]],update:[]}};
  if (failure === 'wrong-base') delta.base_graph_cid = 'sha256:'+'0'.repeat(64);
  if (failure === 'wrong-target') delta.target_graph_cid = oracle.snapshotCid;
  const steps = document.stages[0].steps;
  steps.splice(4,steps.length-4,
    {from:'companies',derive:{delta:{literal:failure === 'malformed' ? {} : delta}},as:'changes'},
    {from:'g',apply_graph_delta:{with:'changes',field:'delta'},as:'applied'},
    {from:'applied',[projection]:true,as:'rows'},
    {filter:'labels IS NOT NULL',as:'filtered'},
    {select:projection === 'node_rows' ? ['id','labels'] : ['id','src','dst','labels','edge_key','tenant_key'],as:'projected'});
  const fields = steps.at(-1).select;
  document.stages[0].results.out.fields = fields;
  const retained = emptyTarget ? [] : projection === 'node_rows'
    ? oracle.rows.node_rows.map((row,index)=>index === 1 ? {...row,p:8} : row)
    : oracle.rows.edge_rows.slice(0,1);
  const expected = retained.map(row=>Object.fromEntries(fields.map(field=>[field,row[field]])));
  return {document,target,retained,expected,fields};
}

// Compose existing sparse Relation consumers after the actual Delta step.
// A constant Required key deliberately coalesces rows whose untouched optional
// property is absent, NULL or a value; whole-row DISTINCT must not coalesce them.
export function deltaRelationCompositionScenario(fixture, operation, {emptyTarget = false} = {}) {
  if (!['keyed-distinct','whole-distinct','group','edge-group'].includes(operation)) {
    throw new Error('UnknownDeltaRelationComposition');
  }
  const projection = operation === 'edge-group' ? 'edge_rows' : 'node_rows';
  const scenario = deltaApplicationScenario(fixture, projection,undefined,{emptyTarget});
  const {document,retained} = scenario;
  document.id = `delta-relation-${operation}${emptyTarget ? '-empty' : ''}`;
  const steps = document.stages[0].steps;
  let derived, output, columns;
  if (operation === 'edge-group') {
    output = emptyTarget ? [] : [{tenant_key:'a',m:10,n:1}];
    columns = [{name:'tenant_key',contract:string},
      {name:'m',contract:{type:'number',nullable:true}}, {name:'n',contract:number}];
    steps.splice(7,steps.length-7,
      {group:{by:['tenant_key'],aggregates:{m:{fn:'max',field:'edge_key'},n:{fn:'count'}}},as:'combined'},
      {select:['tenant_key','m','n'],as:'projected'});
  } else {
    derived = retained.map(row=>({...row,bucket:1}));
    const consumer = operation === 'group'
      ? {group:{by:['bucket'],aggregates:{m:{fn:'max',expr:'bucket'},n:{fn:'count'}}}}
      : {distinct:operation === 'whole-distinct' ? true : ['bucket']};
    output = emptyTarget ? [] : operation === 'group' ? [{bucket:1,m:1,n:3}]
      : operation === 'whole-distinct' ? derived : [{bucket:1}];
    const fields = operation === 'group' ? ['bucket','m','n']
      : operation === 'whole-distinct' ? ['id','bucket'] : ['bucket'];
    columns = operation === 'group' ? [{name:'bucket',contract:number},
      {name:'m',contract:{type:'number',nullable:true}}, {name:'n',contract:number}]
      : operation === 'keyed-distinct' ? [{name:'bucket',contract:number}] : undefined;
    steps.splice(7,steps.length-7,
      {derive:{bucket:{literal:1}},as:'bucketed'}, {...consumer,as:'combined'},
      {select:fields,as:'projected'});
  }
  const fields = steps.at(-1).select;
  document.stages[0].results.out.fields = fields;
  const expected = output.map(row=>Object.fromEntries(fields.map(field=>[field,row[field]])));
  return {...scenario,derived,output,expected,fields,columns};
}
