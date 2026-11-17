///|
extern "js" fn closed_replace_text_document(
  length : Int,
  mode : String,
) -> String =
  #|(length,mode)=>JSON.stringify({version:'actql/0.1',id:'closed-replace-text',stages:[{id:'producer',inputs:{},steps:[{values:{schema:{id:{type:'number',nullable:false},payload:{type:'string',nullable:true}},rows:[{id:1,payload:'😀'.repeat(length)},{id:2,payload:null}]},as:'seed'},{derive:{replaced:mode==='concat'?{concat:[{field:'payload'},{literal:'new'}]}:mode==='dormant'?{coalesce:[{field:'payload'},{concat:[{field:'payload'},{literal:'new'}]}]}:{replace:[{field:'payload'},{literal:''},mode==='dynamic'?{field:'payload'}:{literal:'bb'}]},length:{len:{field:'payload'}}},as:'derived'},{select:['id','replaced','length'],as:'out'}],results:{r:{from:'out',fields:['id','replaced','length']}}},...['a','b'].map(id=>({id,inputs:{rows:{result:{stage:'producer',result:'r'}}},steps:[{select:['id','replaced','length'],as:'out'}],results:{r:{from:'out',fields:['id','replaced','length']}}}))],results:{answer:{from:{stage:'b',result:'r'}}}})

///|
test "closed Replace byte proof includes empty search and checked overflow" {
  assert_eq(client_local_replace_output_text_bytes(0L, 6L), Some(6L))
  assert_eq(client_local_replace_output_text_bytes(4L, 6L), Some(34L))
  assert_eq(client_local_replace_output_text_bytes(4096L, 2L), Some(12290L))
  assert_true(client_local_replace_output_text_bytes(-1L, 0L) is None)
  assert_true(client_local_replace_output_text_bytes(0L, -1L) is None)
  assert_true(
    client_local_replace_output_text_bytes(9223372036854775807L, 0L) is None,
  )
  assert_true(
    client_local_replace_output_text_bytes(1L, 9223372036854775807L) is None,
  )
}

///|
test "closed original Replace and Length keep all occurrences under the same work and Resource policy" {
  let mut previous = 0
  for length in [0, 16, 256] {
    let requirements = original_graph_parallel_requirements(
      closed_replace_text_document(length, "replace"),
    )
    let plan = requirements.capacity_plan
    let demand = plan.value_node_demand.unwrap()
    assert_true(
      client_local_original_values_copy_text_bound(
        plan.sequences,
        demand,
        plan.graph,
        plan.graph_offset,
      )
      is None,
    )
    let (text, wire, row_wire) = client_local_original_values_replace_text_bound(
      plan.sequences,
      demand,
      plan.graph,
      plan.graph_offset,
    ).unwrap()
    assert_true(text > previous)
    assert_true(text < plan.values.max_work)
    previous = text
    assert_eq(plan.values.max_text_bytes, text)
    assert_eq(plan.execution.rows.input_values.max_text_bytes, text)
    assert_eq(plan.execution.rows.output_values.max_text_bytes, text)
    assert_true(plan.imports.wire.max_bytes >= wire)
    assert_true(plan.exports.wire.max_bytes >= wire)
    assert_true(plan.imports.row.max_bytes >= row_wire)
    assert_eq(
      plan.values.max_work,
      client_local_source_free_max_work(None).unwrap(),
    )
    assert_eq(requirements.maximum_limits().retained_bytes, 536870912L)
    assert_eq(requirements.maximum_limits().execution_bytes, 536870912L)
  }
}

///|
test "closed Replace refuses another original graph exhausted work and unknown Text families" {
  let document = closed_replace_text_document(16, "replace")
  let first = original_graph_parallel_requirements(document).capacity_plan
  let second = original_graph_parallel_requirements(document).capacity_plan
  assert_true(
    client_local_original_values_replace_text_bound(
      first.sequences,
      first.value_node_demand.unwrap(),
      second.graph,
      0,
    )
    is None,
  )
  assert_true(
    client_local_original_values_replace_text_bound(
      first.sequences,
      first.value_node_demand.unwrap(),
      first.graph,
      1,
    )
    is None,
  )
  assert_true(
    client_local_original_values_replace_text_bound(
      first.sequences,
      first.value_node_demand.unwrap(),
      first.graph,
      0,
      max_work=1,
    )
    is None,
  )
  for mode in ["concat", "dormant", "dynamic"] {
    let plan = original_graph_parallel_requirements(
        closed_replace_text_document(16, mode),
      ).capacity_plan
    assert_true(
      client_local_original_values_replace_text_bound(
        plan.sequences,
        plan.value_node_demand.unwrap(),
        plan.graph,
        0,
      )
      is None,
    )
    assert_eq(plan.values.max_text_bytes, plan.values.max_work)
  }
}
