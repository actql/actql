///|
fn operand_parameters() -> @parameter.Declarations {
  @parameter.read_declarations(
    Some(
      cursor(
        (
          #|{"n":{"type":"number"},"f":{"type":"number"},"flag":{"type":"boolean"}}
        ),
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
  ).unwrap()
}

///|
test "non-expression parameters retain count window aggregate and frame positions" {
  let parameters = operand_parameters()
  let checked = @pipeline_typing.check(
    cursor(
      (
        #|[{"take":{"$param":"n"},"as":"unused"},{"take":{"count":{"$param":"n"},"offset":{"$param":"n"}},"from":"rows"},{"row_window":{"kind":"fixed","time":"amount","size":{"$param":"n"},"step":{"$param":"n"},"offset":{"$param":"n"}},"from":"rows"},{"group":{"by":[],"aggregates":{"x":{"fn":"percentile_cont","field":"amount","fraction":{"$param":"f"}}}},"from":"rows"},{"analytic":{"partition_by":[],"order_by":[{"id":"asc"}],"functions":{"first":{"fn":"first_value","expr":"amount"},"prev":{"fn":"lag","expr":"amount","offset":{"$param":"n"}}},"frame":{"start":{"preceding":{"$param":"n"}},"end":"current_row"}},"from":"rows"}]
      ),
    ),
    [("rows", schema())],
    Some(parameters),
    None,
    limits(),
  )
  let p = match checked {
    Ok(p) => p
    Err(issue) => fail(@debug.to_string(issue.kind))
  }
  let slots = collect_parameter_slots(p, max_work=1000, max_slots=100).unwrap()
  let expected = [
    "/0/take", "/1/take/count", "/1/take/offset", "/2/row_window/size", "/2/row_window/step",
    "/2/row_window/offset", "/3/group/aggregates/x/fraction", "/4/analytic/functions/prev/offset",
    "/4/analytic/frame/start/preceding",
  ]
  assert_eq(parameter_slot_count(slots), expected.length())
  assert_true(physical_equal(parameter_slots_pipeline(slots), p))
  let occurrences = []
  for i in 0..<parameter_slot_count(slots) {
    let slot = parameter_slot_at(slots, i).unwrap()
    let syntax = @expression.admit(slot.source, {
      max_nodes: 10,
      max_depth: 10,
      max_text_bytes: 100,
      max_tokens: 10,
      tree: {
        max_nodes: 10,
        max_depth: 10,
        max_string_bytes: 100,
        max_total_string_bytes: 100,
      },
    }).unwrap()
    occurrences.push(
      @expression.collect_parameter_occurrences(syntax, max_work=10).unwrap(),
    )
    assert_true(
      @decode.tree_index(@pipeline_typing.source(p), slot.source) is Some(_),
    )
  }
  let index = @parameter_refs.build(
    @pipeline_typing.source(p),
    parameters,
    occurrences,
    { max_slots: 100, max_references: 100, max_pointer_units: 1000, },
  ).unwrap()
  let paths = []
  for i in 0..<@parameter_refs.reference_count(index) {
    paths.push(@parameter_refs.reference_at(index, i).unwrap().path)
  }
  expected.sort_by(@canonical.compare_utf16)
  assert_eq(paths, expected)
  let work = parameter_slots_work(slots)
  assert_true(
    collect_parameter_slots(p, max_work=work, max_slots=expected.length())
    is Ok(_),
  )
  assert_true(
    collect_parameter_slots(p, max_work=work - 1, max_slots=100)
    is Err(WorkLimit),
  )
  assert_true(
    collect_parameter_slots(p, max_work=work, max_slots=expected.length() - 1)
    is Err(SlotLimit),
  )
  assert_true(
    collect_parameter_slots(p, max_work=-1, max_slots=100) is Err(InvalidLimits),
  )
  assert_true(parameter_slot_at(slots, -1) is None)
}

///|
test "time-series steps retain direct parameter slots" {
  let p = @pipeline_typing.check(
    cursor(
      (
        #|[{"time_series":{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-02T00:00:00.000Z","step":{"$param":"n"}},"as":"grid"}]
      ),
    ),
    [],
    Some(operand_parameters()),
    None,
    limits(),
  ).unwrap()
  let slots = collect_parameter_slots(p, max_work=100, max_slots=1).unwrap()
  assert_eq(parameter_slot_count(slots), 1)
  assert_eq(@decode.cursor_path(parameter_slot_at(slots, 0).unwrap().source), [
    @source.Index(0),
    @source.Key("time_series"),
    @source.Key("step"),
  ])
}

///|
test "parameterized Graph bounds retains each exact threshold occurrence" {
  let checked = @pipeline_typing.check_carriers(
    cursor(
      "[{\"from\":\"g\",\"graph_bounds\":{\"max_nodes\":{\"$param\":\"n\"},\"max_degree\":{\"$param\":\"n\"}}}]",
    ),
    [("g", query_property_graph())],
    Some(operand_parameters()),
    None,
    limits(),
  ).unwrap()
  let slots = collect_parameter_slots(checked, max_work=100, max_slots=2).unwrap()
  assert_eq(parameter_slot_count(slots), 2)
  assert_eq(@decode.cursor_path(parameter_slot_at(slots, 0).unwrap().source), [
    @source.Index(0),
    @source.Key("graph_bounds"),
    @source.Key("max_nodes"),
  ])
  assert_eq(@decode.cursor_path(parameter_slot_at(slots, 1).unwrap().source), [
    @source.Index(0),
    @source.Key("graph_bounds"),
    @source.Key("max_degree"),
  ])
}

///|
test "unconnected Graph components refuses before issuing parameter slots" {
  for
    (operation, body) in [
      (
        "components", "{\"kind\":\"weak\",\"max_output_rows\":{\"$param\":\"n\"}}",
      ),
    ] {
    let issue = @pipeline_typing.check_carriers(
      cursor("[{\"from\":\"g\",\"" + operation + "\":" + body + "}]"),
      [("g", query_property_graph())],
      Some(operand_parameters()),
      None,
      limits(),
    ).unwrap_err()
    assert_true(issue.kind is Graph(@graph.UnsupportedGraphOperation))
    assert_true(issue.path.contains(@source.Key(operation)))
  }
}

///|
test "cell and sequence parameters do not inspect literals metadata or predicates" {
  let checked = @pipeline_typing.check(
    cursor(
      (
        #|[{"values":{"schema":{"value":{"type":"number","nullable":false},"payload":{"type":"object","nullable":false,"fields":{"$param":{"type":"string","nullable":false}}}},"rows":[{"value":{"$param":"n"},"payload":{"literal":{"$param":"hidden"}}}]},"as":"seed","meta":{"$param":"annotation"}},{"to_events":{"id":"id","time":"amount"},"from":"rows"},{"sequence":{"by":["id"],"id":"id","time":"amount","pattern":[{"as":"a","where":"$flag"},{"as":"b","where":{"literal":true}}],"within":{"$param":"n"},"max_matches_per_key":{"$param":"n"},"max_output_rows":{"$param":"n"},"overlap":"allow","contiguity":"adjacent"}}]
      ),
    ),
    [("rows", schema())],
    Some(operand_parameters()),
    None,
    limits(),
  )
  let p = match checked {
    Ok(p) => p
    Err(issue) => fail(@debug.to_string(issue.kind))
  }
  let slots = collect_parameter_slots(p, max_work=1000, max_slots=10).unwrap()
  assert_eq(parameter_slot_count(slots), 4)
  assert_eq(parameter_slot_at(slots, 0).unwrap().step, 0)
  for i in 0..<4 {
    assert_eq(parameter_slot_at(slots, i).unwrap().name, "n")
  }
  let expressions = collect_expression_slots(p, max_work=100, max_slots=10).unwrap()
  assert_eq(expression_slot_count(expressions), 2)
  let refs = @expression.parameter_references(
    @typing.expression(expression_slot_at(expressions, 0).unwrap().expression),
  )
  assert_eq(refs.map(r => r.name), ["flag"])
}
