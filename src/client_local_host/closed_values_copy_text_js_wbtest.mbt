///|
extern "js" fn closed_copy_text_document(new_text : Bool) -> String =
  #|newText => JSON.stringify({version:'actql/0.1',id:'closed-copy-text',stages:[{id:'producer',inputs:{},steps:[{values:{schema:{id:{type:'number',nullable:false},tag:{type:'string',nullable:true}},rows:[{id:1,tag:'g'.repeat(256)}]},as:'seed'},{filter:{eq:[{field:'tag'},{literal:'g'.repeat(256)}]},as:'matched'},...(newText?[{derive:{fresh:{concat:[{field:'tag'},{literal:'new'}]}},as:'created'}]:[]),{select:['id','tag'],as:'out'}],results:{r:{from:'out',fields:['id','tag']}}},...['a','b'].map(id=>({id,inputs:{rows:{result:{stage:'producer',result:'r'}}},steps:[{select:['id','tag'],as:'out'}],results:{r:{from:'out',fields:['id','tag']}}}))],results:{answer:{from:{stage:'b',result:'r'}}}})

///|
extern "js" fn closed_temporal_copy_document(
  sequence : Bool,
  new_text : Bool,
  empty : Bool,
) -> String =
  #|(sequence,newText,empty) => {
  #| const number={type:'number',nullable:false},text={type:'string',nullable:true};
  #| const fields=sequence?['tag','start_id','end_id','start_time_ms','end_time_ms','match_start_ms','match_end_ms']:['id','tag'];
  #| const seed={id:'seed',inputs:{},steps:[{values:{schema:{id:{type:'string',nullable:false},tag:text,clock:number,value:number},rows:empty?[]:[{id:'g'.repeat(81),tag:'p'.repeat(81),clock:1,value:1},{id:'h'.repeat(81),tag:'p'.repeat(81),clock:2,value:2}]},as:'out'}],results:{r:{from:'out',fields:['id','tag','clock','value']}}};
  #| const predicate=newText?{eq:[{concat:[{field:'tag'},{literal:'x'}]},{literal:'px'}]}:{eq:[{field:'value'},{literal:1}]};
  #| const producer=sequence?{id:'producer',inputs:{rows:{result:{stage:'seed',result:'r'}}},steps:[{from:'rows',sequence:{by:['tag'],id:'id',time:'clock',pattern:[{as:'start',where:predicate},{as:'end',where:{eq:[{field:'value'},{literal:2}]}}],within:10,overlap:'allow',contiguity:'subsequence'},as:'out'}],results:{r:{from:'out',fields}}}:{id:'producer',inputs:{l:{result:{stage:'seed',result:'r'}},r:{result:{stage:'seed',result:'r'}}},steps:[...(newText?[{from:'l',derive:{fresh:{concat:[{field:'tag'},{literal:'x'}]}},as:'made'}]:[]),{from:newText?'made':'l',interval_join:{with:'r',kind:'left',mode:'point_in_interval',on:[{left:'tag',right:'tag'}],left:{time:'clock'},right:{start:'clock',end:'value'},select:{id:'left.id',tag:'right.tag'},max_output_rows:12},as:'out'}],results:{r:{from:'out',fields}}};
  #| const consumer={id:'consumer',inputs:{rows:{result:{stage:'producer',result:'r'}}},steps:[{select:fields,as:'out'}],results:{r:{from:'out',fields}}};
  #| return JSON.stringify({version:'actql/0.1',id:'closed-temporal-copy',stages:[seed,producer,consumer],results:{answer:{from:{stage:'consumer',result:'r'}}}});
  #|}

///|
test "closed interval and sequence copies retain literal multiplicity and original IO and work" {
  for sequence in [false, true] {
    for empty in [false, true] {
      let document = closed_temporal_copy_document(sequence, false, empty)
      let plan = original_graph_parallel_requirements(document).capacity_plan
      let (text, wire, row_wire) = client_local_original_values_copy_text_bound(
        plan.sequences,
        plan.value_node_demand.unwrap(),
        plan.graph,
        plan.graph_offset,
      ).unwrap()
      assert_eq(plan.values.max_text_bytes, text)
      assert_true(text < 20000000)
      assert_eq(
        plan.values.max_work,
        client_local_source_free_max_work(None).unwrap(),
      )
      assert_eq(plan.execution.rows.input_values.max_text_bytes, text)
      assert_eq(plan.execution.rows.output_values.max_text_bytes, text)
      assert_true(
        plan.imports.wire.max_bytes >= wire &&
        plan.exports.wire.max_bytes >= wire,
      )
      assert_true(plan.imports.row.max_bytes >= row_wire)
      let foreign = original_graph_parallel_requirements(document).capacity_plan
      assert_true(
        client_local_original_values_copy_text_bound(
          plan.sequences,
          plan.value_node_demand.unwrap(),
          foreign.graph,
          0,
        )
        is None,
      )
    }
  }
}

///|
test "closed temporal copies reject new intermediate or predicate Text" {
  for sequence in [false, true] {
    let plan = original_graph_parallel_requirements(
        closed_temporal_copy_document(sequence, true, false),
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
}

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

///|
extern "js" fn closed_copy_membership_document(length : Int) -> String =
  #|length => {const text='😀'.repeat(length);return JSON.stringify({version:'actql/0.1',id:'closed-membership-text',params:{items:{type:'array',nullable:false,items:{type:'string',nullable:true},default:[text,text]}},stages:[{id:'producer',inputs:{},steps:[{values:{schema:{id:{type:'number',nullable:false},tag:{type:'string',nullable:true}},rows:[{id:1,tag:text},{id:2,tag:null}]},as:'seed'},{derive:{included:{in:[{field:'tag'},{$param:'items'}]}},as:'flags'},{select:['id','included'],as:'out'}],results:{r:{from:'out',fields:['id','included']}}},...['a','b'].map(id=>({id,inputs:{rows:{result:{stage:'producer',result:'r'}}},steps:[{select:['id','included'],as:'out'}],results:{r:{from:'out',fields:['id','included']}}}))],results:{answer:{from:{stage:'b',result:'r'}}}})}

///|
test "closed membership derives finite Text from its original admitted parameter array" {
  let mut previous = 0
  for length in [8, 64] {
    let requirements = original_graph_parallel_requirements(
      closed_copy_membership_document(length),
    )
    let plan = requirements.capacity_plan
    let (text, _, _) = client_local_original_values_copy_text_bound(
      plan.sequences,
      plan.value_node_demand.unwrap(),
      plan.graph,
      plan.graph_offset,
    ).unwrap()
    assert_true(text > previous)
    previous = text
    assert_eq(plan.values.max_text_bytes, text)
    assert_eq(
      plan.values.max_work,
      client_local_source_free_max_work(None).unwrap(),
    )
    assert_true(text < plan.values.max_work)
    assert_eq(requirements.maximum_limits().retained_bytes, 536870912L)
    assert_eq(requirements.maximum_limits().execution_bytes, 536870912L)
  }
}

///|
test "closed membership literal proof refuses nested values and exhausted original proof work" {
  let scalar = @admitted.checked_text_value(
      "😀",
      @contract.primitive(@contract.StringType, nullable=false),
    ).unwrap().value
  let array = @admitted.array_value([@admitted.array_value([scalar])])
  let remaining = Ref(10)
  let text = Ref(0L)
  assert_false(client_local_copy_scalar_literal_text(array, remaining, text))
  assert_eq(text.val, 0L)
  assert_false(client_local_copy_scalar_literal_text(scalar, Ref(0), text))
  assert_true(client_local_copy_scalar_literal_text(scalar, remaining, text))
  assert_true(text.val >= 4L)
}
