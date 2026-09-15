///|
test "array consumers demand input bounds independently of published row targets" {
  let (text, _, environment, _, limits) = public_input_fixture(
    analytic_policy=true,
  )
  for kind in ["group", "analytic", "window_group"] {
    let analytic = kind == "analytic"
    let operation = if analytic {
      "{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":{\"items\":{\"fn\":\"array_agg\",\"field\":\"value\",\"max_items\":20}}},\"as\":\"aggregated\"}"
    } else {
      "{\"group\":{\"by\":[],\"aggregates\":{\"items\":{\"fn\":\"array_agg\",\"field\":\"value\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":20}}},\"as\":\"aggregated\"}"
    }
    // The Result deliberately publishes the imported input, not the aggregate
    // or its take input. The aggregate still has its own checked envelope.
    let operation = operation.replace(old="\"group\":", new="\"" + kind + "\":")
    let prefix = if kind == "window_group" {
      "{\"take\":3},{\"row_window\":{\"time\":\"id\",\"kind\":\"fixed\",\"size\":10}},"
    } else {
      "{\"take\":3},"
    }
    let source = text
      .replace(old="{\"take\":1,\"as\":\"selected\"}", new=prefix + operation)
      .replace(old="\"from\":\"selected\"", new="\"from\":\"rows\"")
    let program = public_checked(
      @program_check.check_document(
        source,
        environment,
        None,
        limits,
        format=Json,
      ),
    )
    let selection = if analytic {
      assert_eq(@program_check.unit_analytic_limit_count(program, 1), Some(1))
      @program_check.analytic_limit_selection(
        @program_check.unit_analytic_limit_at(program, 1, 0).unwrap(),
      )
    } else {
      assert_eq(@program_check.unit_group_limit_count(program, 1), Some(1))
      @program_check.group_limit_selection(
        @program_check.unit_group_limit_at(program, 1, 0).unwrap(),
      )
    }
    // min(Host 1000, authored 20, take 3), regardless of publication demand.
    assert_eq(@context.group_array_limit_maximum(selection), 3L)
    assert_eq(@context.group_array_limit_guard(selection), Some(20L))
    assert_eq(@context.group_array_limit_candidate_count(selection), 1)
    let publication = @program_check.unit_publication_at(program, 1, 0).unwrap()
    assert_eq(
      @context.publication_row_limit_maximum(
        @program_check.publication_selection(publication),
      ),
      1000L,
    )
  }
}

///|
test "repeated array calls share one bound while keeping distinct limits" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let call = "{\"fn\":\"array_agg\",\"field\":\"value\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":20}"
  let usages = []
  for repeated in [false, true] {
    let source = text
      .replace(
        old="{\"take\":1,\"as\":\"selected\"}",
        new="{\"take\":3},{\"group\":{\"by\":[],\"aggregates\":{\"a\":" +
          call +
          (if repeated { ",\"b\":" + call } else { "" }) +
          "}},\"as\":\"aggregated\"}",
      )
      .replace(old="\"from\":\"selected\"", new="\"from\":\"rows\"")
    let program = public_checked(
      @program_check.check_document(
        source,
        environment,
        None,
        limits,
        format=Json,
      ),
    )
    usages.push(
      @context.program_identity_capacity_metadata_usage(
        @program_check.source_identity(program),
      ),
    )
    assert_eq(
      @program_check.unit_group_limit_count(program, 1),
      Some(if repeated { 2 } else { 1 }),
    )
    if repeated {
      let a = @program_check.unit_group_limit_at(program, 1, 0).unwrap()
      let b = @program_check.unit_group_limit_at(program, 1, 1).unwrap()
      assert_true(
        @wire.limit_cid(@program_check.group_limit_claim(a)) !=
        @wire.limit_cid(@program_check.group_limit_claim(b)),
      )
      let bounds = [a, b].map(limit => {
        @step_bounds.target_rows_bound(
          @capacity.target_membership_rows(
            @context.group_array_limit_candidate_at(
              @program_check.group_limit_selection(limit),
              0,
            ).unwrap(),
          ),
        )
      })
      assert_true(physical_equal(bounds[0], bounds[1]))
    }
  }
  assert_true(usages[0].0 > 0)
  assert_eq(usages[0], usages[1])
}
