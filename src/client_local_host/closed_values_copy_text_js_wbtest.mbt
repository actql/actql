///|
extern "js" fn closed_copy_text_document(new_text : Bool) -> String =
  #|newText => JSON.stringify({version:'actql/0.1',id:'closed-copy-text',stages:[{id:'producer',inputs:{},steps:[{values:{schema:{id:{type:'number',nullable:false},tag:{type:'string',nullable:true}},rows:[{id:1,tag:'g'.repeat(256)}]},as:'seed'},{filter:{eq:[{field:'tag'},{literal:'g'.repeat(256)}]},as:'matched'},...(newText?[{derive:{fresh:{concat:[{field:'tag'},{literal:'new'}]}},as:'created'}]:[]),{select:['id','tag'],as:'out'}],results:{r:{from:'out',fields:['id','tag']}}},...['a','b'].map(id=>({id,inputs:{rows:{result:{stage:'producer',result:'r'}}},steps:[{select:['id','tag'],as:'out'}],results:{r:{from:'out',fields:['id','tag']}}}))],results:{answer:{from:{stage:'b',result:'r'}}}})

///|
test "closed same-graph copies share one literal IO proof without narrowing execution work" {
  let required = original_graph_parallel_requirements(
    closed_copy_text_document(false),
  )
  let plan = required.capacity_plan
  let demand = plan.value_node_demand.unwrap()
  let (text, wire, row_wire) = client_local_original_values_copy_text_bound(
    plan.sequences,
    demand,
    plan.graph,
    plan.graph_offset,
  ).unwrap()
  assert_true(text >= 256)
  assert_true(text < 20000000)
  assert_eq(
    plan.values.max_work,
    client_local_source_free_max_work(None).unwrap(),
  )
  assert_eq(plan.values.max_text_bytes, text)
  assert_eq(plan.execution.rows.input_values.max_text_bytes, text)
  assert_eq(plan.execution.rows.output_values.max_text_bytes, text)
  assert_true(plan.imports.wire.max_bytes >= wire)
  assert_true(plan.exports.wire.max_bytes >= wire)
  assert_true(plan.imports.row.max_bytes >= row_wire)
  assert_true(plan.imports.row.max_text_bytes >= 256)
}

///|
test "closed copy Text refuses an equal-shaped foreign graph and exhausted proof work" {
  let document = closed_copy_text_document(false)
  let first = original_graph_parallel_requirements(document).capacity_plan
  let second = original_graph_parallel_requirements(document).capacity_plan
  assert_true(
    client_local_original_values_copy_text_bound(
      first.sequences,
      first.value_node_demand.unwrap(),
      second.graph,
      0,
    )
    is None,
  )
  let mixed = first.sequences.copy()
  mixed[0] = second.sequences[0]
  assert_true(
    client_local_original_values_copy_text_bound(
      mixed,
      first.value_node_demand.unwrap(),
      first.graph,
      0,
    )
    is None,
  )
  assert_true(
    client_local_original_values_copy_text_bound(
      first.sequences,
      first.value_node_demand.unwrap(),
      first.graph,
      1,
    )
    is None,
  )
  assert_true(
    client_local_original_values_copy_text_bound(
      first.sequences,
      first.value_node_demand.unwrap(),
      first.graph,
      0,
      max_work=1,
    )
    is None,
  )
}

///|
test "closed copy Text keeps new Text expressions on their original independent policy" {
  let plan = original_graph_parallel_requirements(
      closed_copy_text_document(true),
    ).capacity_plan
  assert_true(
    client_local_original_values_copy_text_bound(
      plan.sequences,
      plan.value_node_demand.unwrap(),
      plan.graph,
      0,
    )
    is None,
  )
  assert_eq(plan.values.max_text_bytes, plan.values.max_work)
}
