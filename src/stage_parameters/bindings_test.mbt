///|
fn bound_three(s : Source) -> @parameter.BoundValues {
  let input = @decode.admit(
    @source.parse_json("{\"n\":3}", {
      max_input_bytes: 100,
      max_nodes: 10,
      max_depth: 3,
    }).unwrap(),
    {
      max_nodes: 10,
      max_depth: 3,
      max_string_bytes: 100,
      max_total_string_bytes: 100,
    },
  ).unwrap()
  guard @parameter.bind(declarations(s), Some(input), {
      max_nodes: 10,
      max_depth: 3,
      max_text_bytes: 100,
    }).unwrap()
    is Ready(v) else {
    abort("test requires complete bindings")
  }
  v
}

///|
fn values_text(index : @references.BoundIndex) -> String raise {
  let out = @encode.writer(1000, 100, 20)
  @references.emit_used_values(index, out)
  @encode.finish(out)
}

///|
test "source bound operations share one value owner in local and Program coordinates" {
  let s = prepared(parsed())
  let pipelines = [
    checked(s, 0, Some(declarations(s))),
    checked(s, 1, Some(declarations(s))),
  ]
  let operations = collect_operations(s, pipelines, caps()).unwrap()
  let values = bound_three(s)
  let bound = bind_operations(operations, values, max_work=10000).unwrap()
  assert_true(physical_equal(bound_operations(bound), operations))
  let global = bound_program_index(bound)
  assert_true(
    physical_equal(
      @references.bound_index(global),
      operations_index(operations),
    ),
  )
  assert_true(physical_equal(@references.bound_values(global), values))
  assert_eq(@references.reference_count(@references.bound_index(global)), 2)
  assert_eq(@references.used_value_count(global), 1)
  let expected =
    #|{"values":{"n":3},"version":"actql-parameter-values/0.1"}
  assert_eq(values_text(global), expected)
  let mut work = operations_usage(operations).work +
    @references.binding_work(global)
  for i in 0..<2 {
    let index = bound_stage_at(bound, i).unwrap()
    assert_true(physical_equal(@references.bound_values(index), values))
    assert_eq(values_text(index), expected)
    let stage_refs = @references.bound_index(index)
    assert_true(
      physical_equal(
        stage_refs,
        @collection.index(
          collection(operations_stage_at(operations, i).unwrap()),
        ),
      ),
    )
    assert_eq(
      @references.reference_at(stage_refs, 0).unwrap().path,
      "/steps/0/take",
    )
    work += 1 + @references.binding_work(index)
  }
  assert_eq(bindings_usage(bound), { ..operations_usage(operations), work, })
  assert_true(bind_operations(operations, values, max_work=work) is Ok(_))
  assert_true(
    bind_operations(operations, values, max_work=work - 1)
    is Err(StageBinding(1, WorkLimit)),
  )
  assert_true(
    bind_operations(
      operations,
      values,
      max_work=operations_usage(operations).work - 1,
    )
    is Err(WorkLimit),
  )
  assert_true(
    bind_operations(operations, values, max_work=-1) is Err(InvalidLimits),
  )
  assert_true(bound_stage_at(bound, -1) is None)
  assert_true(bound_stage_at(bound, 2) is None)
  let foreign = prepared(program(s))
  assert_true(
    bind_operations(operations, bound_three(foreign), max_work=10000)
    is Err(ProgramBinding(ForeignDeclarations)),
  )
  pipelines.clear()
  assert_eq(values_text(bound_stage_at(bound, 1).unwrap()), expected)
}
