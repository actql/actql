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
const string={type:'string',nullable:false},number={type:'number',nullable:true};
function fixture(name,modify=()=>{}) {
  const stage={id:'main',inputs:{
    parents:{carrier:'relation',primary_key:['id'],schema:{id:string,key:{...string,nullable:true}}},
    children:{carrier:'relation',primary_key:['id'],schema:{id:string,key:{...string,nullable:true},value:number}},
  },from:'parents',steps:[{nest:{with:'children',on:[{left:'key',right:'key'}],into:'items',fields:['value'],max_items:3},as:'nested'}],
  results:{main:{from:'nested',fields:['id','key','items']}}};
  modify(stage);
  const program={version:'actql/0.1',id:`nest.golden.${name}`,stages:[stage],results:{main:{from:{stage:'main',result:'main'}}}};
  if(name==='reference-key'||name==='artifact-key'){
    const input_contracts=structuredClone(stage.inputs);
    stage.inputs=Object.fromEntries(Object.keys(input_contracts).map(name=>[name,{connector:'fixture',resource:name,view:'records'}]));
    return {name,program,capacity,input_contracts};
  }
  return {name,program,capacity};
}
export const fixtures=[
  fixture('candidate-key'),
  fixture('explicit-tie',p=>{p.steps[0].nest.order_by=[{value:'desc'}];}),
  fixture('numeric-rename',p=>{
    delete p.inputs.children.primary_key;
    p.inputs.children.schema.a=number;p.inputs.children.schema.b=number;
    p.steps[0].nest.fields=[{'10':'a'},{'2':'b'},{'値':'value'}];
  }),
  fixture('composite-correlation',p=>{
    p.inputs.parents.schema.zone=string;p.inputs.children.schema.zone=string;
    p.steps[0].nest.on.push({left:'zone',right:'zone'});
    p.results.main.fields=['id','key','zone','items'];
  }),
  fixture('reference-key',p=>{
    const ref={type:'resource_ref',resource_kind:'file',nullable:false};
    p.inputs.children.schema.id=ref;
    p.inputs.children.schema.key={...ref,nullable:true};p.inputs.parents.schema.key={...ref,nullable:true};
  }),
  fixture('artifact-key',p=>{p.inputs.children.schema.id={type:'artifact_ref',nullable:false};}),
  fixture('existing-witness',p=>{
    p.steps.unshift({from:'children',sort:[{value:'desc'},{id:'asc'}],as:'ranked_children'});
    p.steps[1].from='parents';p.steps[1].nest.with='ranked_children';
  }),
  fixture('unresolved-authored-tie',p=>{delete p.inputs.children.primary_key;p.steps[0].nest.order_by=[{value:'asc'}];}),
];
