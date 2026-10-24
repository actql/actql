///|
test "closed Values shape proof is bound to original indexed input and exact finite work" {
  let text = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"as\":\"v\",\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1},{\"x\":2}]}}],\"results\":{\"r\":{\"from\":\"v\",\"fields\":[\"x\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
  let limits : @syntax.Limits={source:{max_input_bytes:10000,max_nodes:1000,max_depth:40},tree:{max_nodes:1000,max_depth:40,max_string_bytes:10000,max_total_string_bytes:10000},max_stages:1}
  let original=@syntax.parse_program_input(text,limits,format=@syntax.Json).unwrap()
  let shape=closed_values_shape(original,1000).unwrap()
  assert_eq(shape.fields,1)
  assert_eq(shape.rows,2)
  assert_eq(shape.cells,2)
  assert_true(closed_values_shape_work(shape.fields,shape.rows).unwrap()>=shape.inspection_work)
  assert_true(physical_equal(shape.original,original))
  assert_true(closed_values_shape(original,shape.inspection_work) is Some(_))
  assert_true(closed_values_shape(original,shape.inspection_work-1) is None)
  assert_true(@syntax.finish_program_input(original) is Ok(_))
  for bad in [text.replace_all(old="\"nullable\":false",new="\"nullable\":true"),text.replace_all(old="\"x\":2",new="\"x\":\"two\""),text.replace_all(old="\"from\":\"v\"",new="\"from\":\"foreign\"")] {
    let original=@syntax.parse_program_input(bad,limits,format=@syntax.Json).unwrap()
    assert_true(closed_values_shape(original,1000) is None)
  }
}

///|
test "closed Values original 100 by 99 input crosses byte cap with derived parse and shape facts" {
  let schema : Array[String]=[]
  let names : Array[String]=[]
  for column in 0..<100 {
    let name="\"v"+column.to_string()+"\""
    names.push(name)
    schema.push(name+":{\"type\":\"number\",\"nullable\":false}")
  }
  let rows : Array[String]=[]
  for row in 0..<99 {
    let cells : Array[String]=[]
    for column in 0..<100 { cells.push(names[column]+":"+(row+column).to_string()) }
    rows.push("{"+cells.join(",")+"}")
  }
  let text="{\"version\":\"actql/0.1\",\"id\":\"static-limit-acceptance\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"v\",\"values\":{\"schema\":{"+schema.join(",")+"},\"rows\":["+rows.join(",")+"]}}],\"results\":{\"rows\":{\"from\":\"v\",\"fields\":["+names.join(",")+"]}}}],\"results\":{\"answer0\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  assert_true(text.length()>65536)
  let facts=closed_values_lexical_facts(text,text.length()).unwrap()
  let original=@syntax.parse_program_input(text,{
    source:{max_input_bytes:facts.input_bytes,max_nodes:facts.node_upper,max_depth:facts.depth_upper},
    tree:{max_nodes:facts.node_upper,max_depth:facts.depth_upper,max_string_bytes:facts.longest_quoted_utf16,max_total_string_bytes:facts.quoted_utf16_units},max_stages:1,
  },format=@syntax.Json).unwrap()
  let shape=closed_values_shape(original,text.length()).unwrap()
  assert_eq(shape.fields,100)
  assert_eq(shape.rows,99)
  assert_eq(shape.cells,9900)
  assert_true(closed_values_shape_work(shape.fields,shape.rows).unwrap()>=shape.inspection_work)
  assert_true(closed_values_shape(original,shape.inspection_work-1) is None)
  let parsed=@syntax.finish_program_input(original).unwrap()
  let program_inventory=closed_values_program_inventories(shape)
  let actual=@syntax.program_representation_extent(parsed,2).unwrap()
  assert_eq(actual.program_records,1L)
  assert_eq(actual.stage_records,1L)
  assert_eq(actual.array_owners,6L)
  assert_eq(actual.map_owners,3L)
  assert_eq(actual.map_entries,1L)
  assert_true(actual.array_backing_slots<=54L)
  assert_true(actual.map_backing_slots<=28L)
  assert_true(preparation_representation_cost(program_inventory.containers_peak).unwrap()>=preparation_representation_cost(program_inventory.retained).unwrap())
  let assets=@publication_host.client_local_product_assets()
  let environment=@publication_host.admit_client_check_environment(assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    {text_time:true,veca:false},{rela:true,sga:false,tea:false,calendar:false,text_rank:false}).unwrap()
  let standard=@publication_host.client_standard_program_preparation_limits()
  // Diagnostic constructor execution, not a public Resource admission. The
  // phase plan must fund these same owners before activating larger intake.
  let prepared=@publication_host.prepare_parsed_effect_free_client_program(parsed,environment,None,
    {..standard,checking:{..standard.checking,input:{
      source:{max_input_bytes:facts.input_bytes,max_nodes:facts.node_upper,max_depth:facts.depth_upper},
      tree:{max_nodes:facts.node_upper,max_depth:facts.depth_upper,max_string_bytes:facts.longest_quoted_utf16,max_total_string_bytes:facts.quoted_utf16_units},max_stages:1,
    }}}).unwrap()
  assert_eq(@strategy.graph_task_count(@publication_host.prepared_client_graph(prepared)),1)
}
