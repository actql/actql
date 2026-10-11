///|
fn static_topology_source(imported : Bool, bad_type? : Bool = false) -> @stages.Source {
  let capture =
    (
      #|{"id":"capture","inputs":{"objects":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"from":"objects","filter":{"literal":true}},{"select":["id","payload"],"as":"captured"}],"results":{"source":{"from":"captured","fields":["id","payload"]}}}
    )
  let capture = if bad_type { capture.replace(old="{\"literal\":true}", new="{\"literal\":1}") } else { capture }
  let main = if imported {
    (
      #|{"id":"main","inputs":{"objects":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"objects","select":["id"],"as":"answer"}],"results":{"rows":{"from":"answer","fields":["id"]}}}
    )
  } else {
    (
      #|{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"answer"}],"results":{"rows":{"from":"answer","fields":["id"]}}}
    )
  }
  let program = @syntax.parse("{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[" + capture + "," + main +
    "],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}", {
      source: { max_input_bytes: 100000, max_nodes: 10000, max_depth: 100, },
      tree: { max_nodes: 10000, max_depth: 100, max_string_bytes: 100000,
        max_total_string_bytes: 100000, }, max_stages: 10,
    }, format=Json).unwrap()
  @stages.prepare(program, { max_parameters: 100, max_nodes: 10000,
    max_depth: 100, max_text_bytes: 100000, }).unwrap()
}

///|
fn static_topology_registrations(source : @stages.Source) -> (@sourceviews.PipelineInputs, @local_inputs.ProgramEnvironmentInputs) raise {
  prepare_source_registrations(source, sourceview_catalog(static_topology_environment()),
    { max_work: 1000000, max_nodes: 100000, max_depth: 100, max_text_bytes: 1000000, },
    max_inputs=100, max_views=100, max_order_keys=100).unwrap()
}

///|
test "Catalog-backed check-only topology retains exact Source and pending capture order" {
  for imported in [false, true] {
    let source = static_topology_source(imported)
    let (views, locals) = static_topology_registrations(source)
    let (checked, used) = check_sourceview_program(views, locals, local_program_context_source_limits()).unwrap()
    let topology = sourceview_checked_topology(checked)
    assert_true(physical_equal(@stage_results.topology_source(topology), source))
    assert_true(physical_equal(topology_sourceviews(checked), views))
    assert_true(physical_equal(@stage_results.topology_local_environment(topology).unwrap(), locals))
    assert_true(@stage_results.topology_reconciled_input_at(topology, 0) is Some(_))
    let stage = @stage_results.topology_stage_at(topology, 0).unwrap()
    let attachment = topology_sourceview_attachment_at(checked, 0).unwrap()
    assert_true(physical_equal(@sourceviews.attached_pipeline_inputs(attachment), views))
    assert_true(physical_equal(@sourceviews.attached_pipeline_stage(attachment), @stage_results.topology_stage_source(stage)))
    let inventory = @results.checked_inputs_results(@stage_results.topology_stage_results(stage))
    assert_eq(@results.pending_validations(@results.result_at(inventory, 0).unwrap()), [@results.TotalDeterministicOrder])
    assert_true(used.work >= @stage_results.topology_usage(topology).work)
    guard prepare_sourceview_program(views, locals, local_program_context_source_limits())
      is Err(Program(Order(0, ResultOrder(issue)))) else { abort("strict publication must still refuse") }
    assert_eq(issue.kind, @results.UnresolvedOrder)
    assert_eq(issue.path, [Key("stages"), Index(0), Key("results"), Key("source")])
    let (foreign, _) = prepare_source_registrations(source,
      @sourceviews.catalog(@sourceviews.pipeline_resolution(views)),
      { max_work: 1000000, max_nodes: 100000, max_depth: 100, max_text_bytes: 1000000, },
      max_inputs=100, max_views=100, max_order_keys=100).unwrap()
    assert_true(check_sourceview_program(foreign, locals, local_program_context_source_limits()) is Err(ForeignPartition(0)))
  }
}

///|
test "unused Catalog-backed pipeline remains fully typed in check-only mode" {
  let source = static_topology_source(false, bad_type=true)
  let (views, locals) = static_topology_registrations(source)
  guard check_sourceview_program(views, locals, local_program_context_source_limits())
    is Err(Program(Pipeline(0, issue))) else { abort("invalid unused filter must be refused") }
  assert_eq(issue.path, [Key("stages"), Index(0), Key("steps"), Index(0), Key("filter")])
}

///|
test "check-only cannot promote a Source schema without its Catalog owner" {
  let source = static_topology_source(false)
  guard @stage_results.check_local_program(source, local_program_context_source_limits())
    is Err(LocalInput(0, Declaration("objects", Decode(issue)))) else {
    abort("Connector declaration requires its Catalog partition")
  }
  assert_eq(issue.path, [Key("stages"), Index(0), Key("inputs"), Key("objects"), Key("connector")])
}
