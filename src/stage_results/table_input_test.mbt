///|
fn table_input_program_source(
  store? : Bool = false,
  store_source? : String = "material",
) -> @parameters.Source {
  // Both definitions guarantee the same original key column. Only N declares
  // p; the data deliberately contain a value, explicit NULL and absence.
  let text =
    #|{"version":"actql/0.1","id":"table-input","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"person_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":true}},"rows":[{"person_key":1,"p":7},{"person_key":2,"p":null}]},"as":"persons"},{"values":{"schema":{"person_key":{"type":"number","nullable":false}},"rows":[{"person_key":3}]},"as":"companies"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"persons","key":["person_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]},{"name":"M","from":"companies","key":["person_key"],"labels":[]}],"edges":[]},"as":"g"},{"from":"g","node_rows":true,"as":"rows"},{"select":["person_key"],"as":"public_rows"}],"table_inputs":{"material":{"from":"rows","fields":["person_key","p"]}},"results":{"out":{"from":"public_rows","fields":["person_key"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  local_program_parse(
    if store {
      text
      .replace(
        old="\"table_inputs\":",
        new="\"effects\":{\"save\":{\"store\":{\"target\":\"connector://table/catalog\",\"mapping\":\"mapping:table.catalog.v1\",\"from\":{\"table_input\":\"material\"}}}},\"table_inputs\":",
      )
      .replace(
        old="\"table_input\":\"material\"",
        new="\"table_input\":\"" + store_source + "\"",
      )
    } else {
      text
    },
  )
}

///|
test "private Table sources bind their exact declaration instead of a source-free ordinary Store" {
  let source = table_input_program_source(store=true)
  let prepared = prepare_local_source(
    @parameters.program(source),
    None,
    max_parameters=0,
    local_program_limits(),
  ).unwrap()
  let headers = @syntax.collect_effect_headers(
    @parameters.program(local_source_source(prepared)),
    1,
    100,
  ).unwrap()
  let checked = local_source_results(prepared)
  let bindings = bind_effect_results(headers, checked, 100).unwrap()
  let binding = effect_result_binding_at(bindings, 0).unwrap()
  assert_true(effect_result_binding_result(binding) is None)
  let expected = @results.lookup_table_input(
    stage_table_inputs_at(checked, 0).unwrap(),
    "material",
  ).unwrap()
  assert_true(
    physical_equal(
      effect_result_binding_table_input(binding).unwrap(),
      expected,
    ),
  )
  assert_eq(effect_result_field_binding_count(binding), 0)
  let schema = @results.table_input_schema(expected)
  let p = @schema.lookup_reference(schema, "p").unwrap()
  assert_eq(@schema.field_presence(p), Conditional)
  assert_true(@contract.contract_nullable(@schema.field_contract(p)))
  // An otherwise admitted Result-shaped Preview cannot relabel this private
  // source, even if its ordinary Result field repeats the private input name.
  let preview = checked_preview_test_identity(
    "save",
    "unused",
    include_second=false,
    first_kind="store",
    first_source_name="material",
  )
  assert_eq(
    check_effect_preview_checked_inventory(bindings, 0, preview, 100).unwrap_err(),
    SourceMismatch("save"),
  )
}

///|
test "private Table source admission rejects unknown names without a same-name public Result fallback" {
  for name in ["out", "missing"] {
    let source = table_input_program_source(store=true, store_source=name)
    // Effect header admission refuses these names before binding. Local
    // topology preparation alone is not complete Effect admission. In
    // particular, a public Result named out cannot satisfy the private source.
    let issue = @syntax.collect_effect_headers(
      @parameters.program(source),
      1,
      100,
    ).unwrap_err()
    assert_eq(@syntax.effect_header_issue_kind(issue), InvalidSourceResult)
  }
}

///|
test "Table declarations remain source-owned and separate from public Result ports" {
  let source = table_input_program_source()
  let (wired, _) = prepare_local_program(source, local_program_limits()).unwrap()
  let owner = wiring_stage_at(wired, 0).unwrap()
  let inputs = stage_port_table_inputs(owner).unwrap()
  let input = @results.lookup_table_input(inputs, "material").unwrap()
  assert_eq(@results.table_input_fields(input), ["person_key", "p"])
  let schema = @results.table_input_schema(input)
  assert_eq(
    @schema.field_presence(@schema.lookup_reference(schema, "p").unwrap()),
    Conditional,
  )
  assert_true(
    @contract.type_equal(
      @schema.field_contract(@schema.lookup_reference(schema, "p").unwrap()),
      @contract.primitive(NumberType, nullable=true),
      100,
    ),
  )
  assert_eq(
    @schema.field_presence(
      @schema.lookup_reference(schema, "person_key").unwrap(),
    ),
    Required,
  )
  assert_true(
    @results.lookup_port(stage_port_publications(owner), "material") is None,
  )
  assert_eq(export_count(wired), 1)
  let stage = stage_port_source(owner)
  let ports = stage_port_publications(owner)
  assert_true(bind_ports(stage, ports) is Err(ForeignTableInputs))
  assert_true(bind_ports(stage, ports, table_inputs=Some(inputs)) is Ok(_))
  let (other, _) = prepare_local_program(source, local_program_limits()).unwrap()
  let foreign = stage_port_table_inputs(wiring_stage_at(other, 0).unwrap()).unwrap()
  assert_true(
    bind_ports(stage, ports, table_inputs=Some(foreign))
    is Err(ForeignTableInputs),
  )
}

///|
test "Table declarations use the shared Program admission budget exactly once" {
  let source = table_input_program_source()
  let (_, used) = prepare_local_program(source, local_program_limits()).unwrap()
  // One public Result and one private input consume the same declaration cap.
  assert_eq(used.results, 2)
  let exact = {
    ..local_program_limits(),
    max_steps: used.steps,
    max_results: used.results,
    max_work: used.work,
    max_nodes: used.nodes,
    max_tokens: used.tokens,
    max_text_bytes: used.text_bytes,
  }
  let (_, again) = prepare_local_program(source, exact).unwrap()
  assert_eq(again, used)
  for
    cap in [
      { ..exact, max_results: exact.max_results - 1, },
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(prepare_local_program(source, cap) is Err(_))
  }
}

///|
test "whole Program collection retains exact private input owners and bills their prefix" {
  let source = table_input_program_source()
  let (wired, _) = prepare_local_program(source, local_program_limits()).unwrap()
  let port = wiring_stage_at(wired, 0).unwrap()
  let operations = @parameters.collect_prepared_operations(
    source,
    [stage_port_source(port)],
    {
      max_work: 1000000,
      max_slots: 100,
      max_references: 100,
      max_pointer_units: 100000,
      max_direct_text_bytes: 100000,
    },
  ).unwrap()
  let original = check(operations, limits()).unwrap()
  let used = usage(original)
  let exact : CollectionLimits = {
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_results: used.results,
  }
  let public_results = [stage_at(original, 0).unwrap()]
  let inputs = stage_table_inputs_at(original, 0).unwrap()
  let retained = collect_checked(
    operations,
    public_results,
    exact,
    table_inputs=Some([Some(inputs)]),
  ).unwrap()
  assert_true(
    physical_equal(stage_table_inputs_at(retained, 0).unwrap(), inputs),
  )
  assert_eq(usage(retained), used)
  assert_true(
    collect_checked(operations, public_results, exact)
    is Err(ForeignTableInputs(0)),
  )
  for
    cap in [
      { ..exact, max_results: exact.max_results - 1, },
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(
      collect_checked(
        operations,
        public_results,
        cap,
        table_inputs=Some([Some(inputs)]),
      )
      is Err(BudgetExceeded(0)),
    )
  }
  let prepared = prepare_local_source(
    @parameters.program(source),
    None,
    max_parameters=0,
    local_program_limits(),
  ).unwrap()
  let checked = local_source_results(prepared)
  let stage = wiring_stage_at(local_source_wiring(prepared), 0).unwrap()
  assert_true(
    physical_equal(
      stage_table_inputs_at(checked, 0).unwrap(),
      stage_port_table_inputs(stage).unwrap(),
    ),
  )
  let usage = local_source_usage(prepared)
  let exact_source = {
    ..local_program_limits(),
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_tokens: usage.tokens,
    max_text_bytes: usage.text_bytes,
    max_steps: usage.steps,
    max_results: usage.results,
  }
  let repeated = prepare_local_source(
    @parameters.program(source),
    None,
    max_parameters=0,
    exact_source,
  ).unwrap()
  assert_eq(local_source_usage(repeated), usage)
  assert_true(
    prepare_local_source(@parameters.program(source), None, max_parameters=0, {
      ..exact_source,
      max_work: usage.work - 1,
    })
    is Err(_),
  )
}
