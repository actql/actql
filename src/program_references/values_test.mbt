///|
fn bound_fixture(
  usage : DeclarationUsage,
  text : String,
) -> @parameter.BoundValues {
  let source = @source.parse_json(text, {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 1000,
    max_depth: 100,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  match
    @parameter.bind(
      @parameters.declarations(
        parameters(program_index(usage_inventory(usage))),
      ),
      Some(cursor),
      { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    ).unwrap() {
    Ready(v) => v
    _ => abort("fixture must supply every Parameter")
  }
}

///|
fn value_usage(empty? : Bool = false) -> DeclarationUsage {
  let (requests, stages) = fixture(used_bindings=true, empty~)
  check_declaration_usage(
    prepare(requests, stages, caps()).unwrap(),
    max_work=8000000,
  ).unwrap()
}

///|
fn value_text(value : @parameters.BoundIndex) -> String raise {
  let out = @encode.writer(10000, 1000, 100)
  @parameters.emit_used_values(value, out)
  @encode.finish(out)
}

///|
test "all stage value projections share one exact admitted binding set" {
  let usage = value_usage()
  let values = bound_fixture(usage, "{\"m\":2,\"n\":7}")
  let bound = bind_parameter_values(usage, values, max_work=9000000).unwrap()
  assert_true(physical_equal(parameter_usage(bound), usage))
  assert_true(physical_equal(parameter_values(bound), values))
  let program = program_parameter_values(bound)
  let a = stage_parameter_values(bound, 0).unwrap()
  let b = stage_parameter_values(bound, 1).unwrap()
  for index in [program, a, b] {
    assert_true(physical_equal(@parameters.bound_values(index), values))
  }
  assert_true(
    physical_equal(
      @parameters.bound_index(a),
      parameters(stage_index(usage_inventory(usage), 0).unwrap()),
    ),
  )
  assert_eq(
    value_text(program),
    "{\"values\":{\"m\":2,\"n\":7},\"version\":\"actql-parameter-values/0.1\"}",
  )
  assert_eq(value_text(a), value_text(program))
  assert_eq(
    value_text(b),
    "{\"values\":{\"m\":2},\"version\":\"actql-parameter-values/0.1\"}",
  )
  assert_true(stage_parameter_values(bound, -1) is None)
  assert_true(stage_parameter_values(bound, 2) is None)
  // One shared two-value preparation, five selected entries, two stage visits.
  assert_eq(parameter_work(bound), usage_work(usage) + 9)
  let changed = bind_parameter_values(
    usage,
    bound_fixture(usage, "{\"m\":2,\"n\":8}"),
    max_work=9000000,
  ).unwrap()
  assert_true(
    value_text(program_parameter_values(changed)) != value_text(program),
  )
  assert_eq(
    value_text(stage_parameter_values(changed, 1).unwrap()),
    value_text(b),
  )
}

///|
test "Program value binding rejects foreign owners and late work exhaustion" {
  let usage = value_usage()
  let values = bound_fixture(usage, "{\"m\":2,\"n\":7}")
  let exact = usage_work(usage) + 9
  assert_eq(
    parameter_work(
      bind_parameter_values(usage, values, max_work=exact).unwrap(),
    ),
    exact,
  )
  assert_true(
    bind_parameter_values(usage, values, max_work=exact - 1) is Err(WorkLimit),
  )
  assert_true(
    bind_parameter_values(usage, values, max_work=-1) is Err(InvalidLimits),
  )
  let foreign = bound_fixture(value_usage(), "{\"m\":2,\"n\":7}")
  assert_true(
    bind_parameter_values(usage, foreign, max_work=9000000)
    is Err(ForeignDeclarations),
  )
  let empty = value_usage(empty=true)
  let no_values = bound_fixture(empty, "{}")
  let bound = bind_parameter_values(
    empty,
    no_values,
    max_work=usage_work(empty) + 2,
  ).unwrap()
  assert_eq(
    value_text(program_parameter_values(bound)),
    "{\"values\":{},\"version\":\"actql-parameter-values/0.1\"}",
  )
  assert_true(
    bind_parameter_values(
      empty,
      bound_fixture(value_usage(empty=true), "{}"),
      max_work=9000000,
    )
    is Err(ForeignDeclarations),
  )
}
