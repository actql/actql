///|
fn catalog_prefix_source(unknown? : Bool = false) -> @stages.Source {
  let text =
    #|{"version":"actql/0.1","id":"prefix","stages":[{"id":"capture","inputs":{"objects":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"from":"objects","filter":{"literal":true}},{"select":["id","payload"],"as":"saved"}],"results":{"out":{"from":"saved","fields":["id","payload"]}}},{"id":"open","inputs":{"r":{"result":{"stage":"capture","result":"out"}}},"from":"r","steps":[{"derive":{"n":{"literal":1}},"as":"prefix"}],"results":{}}],"results":{}}
  let text = if unknown {
    text.replace(old="\"view\":\"v\"", new="\"view\":\"missing\"")
  } else {
    text
  }
  let caps : @syntax.Limits = {
    source: { max_input_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    tree: {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
    max_stages: 100,
  }
  let document = @origin.document(text, 100000, source_path="prefix-catalog.aql").unwrap()
  let builder = @builder.create(document, {
    source: caps.source,
    tree: caps.tree,
    max_origin_entries: 100000,
    max_output_bytes: 1000000,
  }).unwrap()
  let input = @source.parse_json_measured(text, caps.source, source_path="prefix-catalog.aql").unwrap()
  let generated = @builder.finish(
    builder,
    @builder.import_parsed(builder, input).unwrap(),
  ).unwrap()
  let prefix = @syntax.admit_generated_prefix(generated, caps).unwrap()
  @stages.prepare_prefix(prefix, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
}

///|
test "prefix reuses actual Catalog registration local owner and source attachment" {
  let source = catalog_prefix_source()
  let catalog = sourceview_catalog(static_topology_environment())
  let (views, locals) = prepare_source_registrations(
    source,
    catalog,
    {
      max_work: 1000000,
      max_nodes: 100000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
    max_inputs=100,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_true(
    physical_equal(
      @sourceviews.catalog(@sourceviews.pipeline_resolution(views)),
      catalog,
    ),
  )
  assert_true(physical_equal(@local_inputs.environment_program(locals), source))
  let caps : @stage_results.LocalProgramLimits = {
    max_stages: 100,
    max_steps: 100,
    max_results: 100,
    max_work: 1000000,
    max_nodes: 100000,
    max_tokens: 100000,
    max_text_bytes: 1000000,
    max_depth: 100,
  }
  let (checked, _) = check_sourceview_program(views, locals, caps).unwrap()
  assert_true(physical_equal(topology_sourceviews(checked), views))
  let topology = sourceview_checked_topology(checked)
  assert_true(physical_equal(@stage_results.topology_source(topology), source))
  assert_true(
    physical_equal(
      @stage_results.topology_local_environment(topology).unwrap(),
      locals,
    ),
  )
  assert_true(topology_sourceview_attachment_at(checked, 0) is Some(_))
  let captured = @stage_results.topology_stage_at(topology, 0).unwrap()
  let definition = @results.result_at(
    @results.checked_inputs_results(
      @stage_results.topology_stage_results(captured),
    ),
    0,
  ).unwrap()
  assert_eq(@results.pending_validations(definition), [
    @results.TotalDeterministicOrder,
  ])
  assert_eq(@stage_results.topology_export_count(topology), 0)
  assert_true(
    prepare_sourceview_program(views, locals, caps)
    is Err(Program(CheckOnlyPrefix)),
  )
}

///|
test "prefix unknown Catalog view is refused without pretending it is Local" {
  let source = catalog_prefix_source(unknown=true)
  let catalog = sourceview_catalog(static_topology_environment())
  guard prepare_source_registrations(
      source,
      catalog,
      {
        max_work: 1000000,
        max_nodes: 100000,
        max_text_bytes: 1000000,
        max_depth: 100,
      },
      max_inputs=100,
      max_views=100,
      max_order_keys=100,
    )
    is Err(Selection(issue)) else {
    fail("actual Catalog selection must refuse missing view")
  }
  assert_eq(issue.kind, @sourceviews.Unresolved)
}
