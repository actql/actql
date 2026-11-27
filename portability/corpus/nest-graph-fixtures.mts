// Authored inputs to the independent lowering subset. No implementation imports.
export const capacity = {
  version:'actql-capacity-host-policy/0.1', max_relation_output_rows:100000,
  max_infer_items:10000,max_effect_items:100000,max_artifact_rows:100000,
  max_artifact_bytes:16777216,max_graph_paths:10000,max_graph_input_nodes:100000,
  max_graph_input_edges:200000,max_graph_output_rows:100000,
  max_temporal_matches_per_key:1000,max_temporal_output_rows:100000,
  max_aggregate_array_items:100000,max_nested_value_bytes:16777216,max_nested_value_depth:64,
  max_model_request_bytes_per_item:1048576,max_model_input_tokens_per_item:8192,max_model_total_duration_ms:30000,
};
type Column = {type: 'string' | 'number' | 'artifact_ref'; nullable: boolean}
  | {type: 'resource_ref'; resource_kind: 'file'; nullable: boolean};
type Inline = {carrier: 'relation'; primary_key?: string[]; schema: Record<string, Column>};
type InlineInputs = {parents: Inline; children: Inline};
type Reference = {connector: 'fixture'; resource: string; view: 'records'};
type Ordering = Record<string, 'asc' | 'desc'>[];
type NestStep = {from?: string; nest: {with: string; on: {left: string; right: string}[];
  into: string; fields: (string | Record<string, string>)[]; max_items: number; order_by?: Ordering}; as: string};
type Stage<Inputs> = {id: string; inputs: Inputs; from: string;
  steps: (NestStep | {from: string; sort: Ordering; as: string})[];
  results: {main: {from: string; fields: string[]}}};
type Program = {version: string; id: string; stages: [Stage<InlineInputs | Record<string, Reference>>];
  results: {main: {from: {stage: string; result: string}}}};
const string: Column={type:'string',nullable:false},number: Column={type:'number',nullable:true};
function fixture(name: string, modify: (stage: Stage<InlineInputs>, step: NestStep) => void = () => {}) {
  const step: NestStep={nest:{with:'children',on:[{left:'key',right:'key'}],into:'items',fields:['value'],max_items:3},as:'nested'};
  const stage: Stage<InlineInputs>={id:'main',inputs:{
    parents:{carrier:'relation',primary_key:['id'],schema:{id:string,key:{...string,nullable:true}}},
    children:{carrier:'relation',primary_key:['id'],schema:{id:string,key:{...string,nullable:true},value:number}},
  },from:'parents',steps:[step],results:{main:{from:'nested',fields:['id','key','items']}}};
  modify(stage,step);
  const program: Program={version:'actql/0.1',id:`nest.golden.${name}`,stages:[stage],results:{main:{from:{stage:'main',result:'main'}}}};
  if(name==='reference-key'||name==='artifact-key'){
    const input_contracts=structuredClone(stage.inputs);
    const references=Object.fromEntries(Object.keys(input_contracts).map(name=>
      [name,{connector:'fixture',resource:name,view:'records'} satisfies Reference]));
    program.stages[0]={...stage,inputs:references};
    return {name,program,capacity,input_contracts};
  }
  return {name,program,capacity};
}
export const fixtures=[
  fixture('candidate-key'),
  fixture('explicit-tie',(_,step)=>{step.nest.order_by=[{value:'desc'}];}),
  fixture('numeric-rename',(p,step)=>{
    delete p.inputs.children.primary_key;
    p.inputs.children.schema.a=number;p.inputs.children.schema.b=number;
    step.nest.fields=[{'10':'a'},{'2':'b'},{'値':'value'}];
  }),
  fixture('composite-correlation',(p,step)=>{
    p.inputs.parents.schema.zone=string;p.inputs.children.schema.zone=string;
    step.nest.on.push({left:'zone',right:'zone'});
    p.results.main.fields=['id','key','zone','items'];
  }),
  fixture('reference-key',p=>{
    const ref: Column={type:'resource_ref',resource_kind:'file',nullable:false};
    p.inputs.children.schema.id=ref;
    p.inputs.children.schema.key={...ref,nullable:true};p.inputs.parents.schema.key={...ref,nullable:true};
  }),
  fixture('artifact-key',p=>{p.inputs.children.schema.id={type:'artifact_ref',nullable:false};}),
  fixture('existing-witness',(p,step)=>{
    p.steps.unshift({from:'children',sort:[{value:'desc'},{id:'asc'}],as:'ranked_children'});
    step.from='parents';step.nest.with='ranked_children';
  }),
  fixture('unresolved-authored-tie',(p,step)=>{delete p.inputs.children.primary_key;step.nest.order_by=[{value:'asc'}];}),
];
