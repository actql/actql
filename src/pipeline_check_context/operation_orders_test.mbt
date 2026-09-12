///|
fn operation_order_fixture(
  steps : String,
  supplied? : @decode.Cursor? = None,
  tea? : Bool = false,
  sga? : Bool = false,
  calendar? : Bool = false,
  veca? : Bool = false,
  text_rank? : Bool = false,
  host_profile? : String = bound_profile(),
  parameters? : String = "{\"p\":{\"type\":\"string\",\"default\":\"é😀\"},\"n\":{\"type\":\"number\",\"default\":1}}",
) -> ProgramOperationRequirements {
  let (operations, references, bindings) = program_sources_fixture(
    steps=Some(steps),
    supplied~,
    tea~,
    sga~,
    calendar~,
    veca~,
    text_rank~,
    host_profile~,
    parameters~,
  )
  let identity = identify_program_sources(
    bind_program_sources(operations, references, bindings, 10000000).unwrap(),
    identity_limits(),
  ).unwrap()
  collect_program_operation_requirements(
    close_program_expressions(identity, 10000000, 1000).unwrap(),
    10000000,
    1000,
  ).unwrap()
}

///|
test "Program contextual order links reuse exact sort and take resolutions across producers" {
  let requirements = operation_order_fixture(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"derive":{"x":"concat($p, to_string($n))"}},{"sort":[{"id":"asc"}]},{"take":1},{"dedupe_rows":{"by":["id"],"order_by":[{"id":"asc"}]}}]
    ),
  )
  let result = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  assert_true(
    physical_equal(operation_orders_requirements(result), requirements),
  )
  assert_eq(operation_orders_count(result), 6)
  let identity = expression_closure_identity(
    operation_requirements_expressions(requirements),
  )
  let stages = program_reference_stages(
    program_sources_references(program_identity_sources(identity)),
  )
  for i in 0..<6 {
    let link = operation_order_link_at(result, i).unwrap()
    let original = operation_requirements_at(
      requirements,
      link.requirement_index,
    ).unwrap()
    assert_true(physical_equal(link.site, original))
    assert_eq(link.site.step, if i % 2 == 0 { 2 } else { 3 })
    let orders = @results.checked_producer_orders(
      checked_orders(
        parameter_context(stage_context_at(stages, link.site.stage).unwrap()),
      ),
    )
    let owner_orders = @pipeline.contextual_closure_at(
      orders,
      link.site.producer_visit,
    ).unwrap()
    assert_true(
      physical_equal(
        @pipeline.contextual_orders_pipeline(owner_orders),
        link.site.pipeline,
      ),
    )
    assert_eq(
      @pipeline.contextual_order_count(owner_orders, link.site.step),
      Some(1),
    )
    let original = @pipeline.contextual_order_at(
      owner_orders,
      link.site.step,
      0,
    ).unwrap()
    assert_true(physical_equal(link.resolution, original))
    match link.resolution {
      SortSequence(v) => {
        assert_eq(i % 2, 0)
        assert_true(
          physical_equal(@pipeline.sort_order_pipeline(v), link.site.pipeline),
        )
        assert_eq(@pipeline.sort_order_step(v), 2)
      }
      TakeSequence(_) => assert_eq(i % 2, 1)
      _ => fail("unexpected order strategy")
    }
    for j in [-1, 1, 2147483647] {
      assert_true(
        @pipeline.contextual_order_at(owner_orders, link.site.step, j) is None,
      )
    }
    assert_true(@pipeline.contextual_order_count(owner_orders, -1) is None)
    assert_true(@pipeline.contextual_order_count(owner_orders, 5) is None)
    let copy = @pipeline.contextual_orders_at(owner_orders, link.site.step).unwrap()
    copy.clear()
    assert_eq(
      @pipeline.contextual_order_count(owner_orders, link.site.step),
      Some(1),
    )
  }
  let count = operation_orders_count(result)
  let work = operation_orders_work(result)
  // Inventory pass, six step-index reads, six resolutions and six retained links.
  assert_eq(
    work,
    operation_requirements_work(requirements) +
    1 +
    operation_requirements_count(requirements) +
    6 * 3,
  )
  assert_true(link_program_operation_orders(requirements, work, count) is Ok(_))
  assert_true(
    link_program_operation_orders(requirements, work - 1, count)
    is Err(BudgetExceeded),
  )
  assert_true(
    link_program_operation_orders(requirements, work, count - 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    link_program_operation_orders(requirements, -1, count) is Err(InvalidLimits),
  )
  assert_true(
    link_program_operation_orders(requirements, work, -1) is Err(InvalidLimits),
  )
  for i in [-1, count, 2147483647] {
    assert_true(operation_order_link_at(result, i) is None)
  }
}

///|
test "empty sort adds no order resolution and top ties remain outstanding" {
  let requirements = operation_order_fixture(
    (
      #|[{"derive":{"x":"concat($p, to_string($n))"}},{"sort":[]},{"dedupe_rows":{"by":[],"order_by":[{"id":"desc"}]}}]
    ),
  )
  let result = link_program_operation_orders(requirements, 10000000, 0).unwrap()
  assert_eq(operation_requirements_count(requirements), 3)
  assert_eq(operation_orders_count(result), 0)
  for i in 0..<3 {
    let site = operation_requirements_at(requirements, i).unwrap()
    guard site.requirement is @pipeline.RelationRequirement(p) else {
      abort("relation")
    }
    assert_eq(p.kind, FailOnTopTie)
    assert_true(@pipeline.operation_order_demand(site.requirement) is None)
  }
  let work = operation_orders_work(result)
  assert_eq(work, operation_requirements_work(requirements) + 4)
  assert_true(link_program_operation_orders(requirements, work, 0) is Ok(_))
  assert_true(
    link_program_operation_orders(requirements, work - 1, 0)
    is Err(BudgetExceeded),
  )
}

///|
test "multiple aggregate order requirements share their exact group resolution" {
  let requirements = operation_order_fixture(
    (
      #|[{"derive":{"x":"concat($p, to_string($n))"}},{"distinct":["id"]},{"group":{"by":[],"aggregates":{"a":{"fn":"first","field":"id","order_by":[{"id":"desc"}]},"b":{"fn":"last","field":"id","order_by":[{"id":"asc"}]},"c":{"fn":"count"}}}}]
    ),
  )
  let result = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  assert_eq(operation_orders_count(result), 6)
  for i in 0..<3 {
    let first = operation_order_link_at(result, i * 2).unwrap()
    let second = operation_order_link_at(result, i * 2 + 1).unwrap()
    assert_true(physical_equal(first.resolution, second.resolution))
    assert_true(first.requirement_index != second.requirement_index)
    guard first.resolution is @pipeline.Aggregates(group) else {
      abort("group")
    }
    assert_eq(@pipeline.group_orders_count(group), 3)
    assert_true(@pipeline.group_order_at(group, 0) is Some(_))
    assert_true(@pipeline.group_order_at(group, 1) is Some(_))
    assert_true(@pipeline.group_order_at(group, 2) is None)
    assert_true(
      physical_equal(
        @pipeline.group_orders_consumer(group),
        @pipeline.step_at(first.site.pipeline, first.site.step).unwrap(),
      ),
    )
  }
  let work = operation_orders_work(result)
  // Three group indices, not a new scan for each aggregate requirement.
  assert_eq(
    work,
    operation_requirements_work(requirements) +
    1 +
    operation_requirements_count(requirements) +
    3 * 2 +
    6,
  )
  assert_true(link_program_operation_orders(requirements, work, 6) is Ok(_))
  assert_true(
    link_program_operation_orders(requirements, work - 1, 6)
    is Err(BudgetExceeded),
  )
}

///|
test "lag analytic and nested order links retain distinct strategies" {
  for
    (operation, expected) in [
      (
        "{\"top_k\":{\"k\":2,\"by\":[{\"id\":\"asc\"}]}}",
        @pipeline.CompleteOrder,
      ),
      (
        "{\"top_k_by\":{\"partition_by\":[],\"k\":2,\"by\":[{\"id\":\"asc\"}]}}",
        CompleteOrder,
      ),
      (
        "{\"lag\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"field\":\"id\",\"output\":\"previous\"}}",
        @pipeline.LagKey,
      ),
      (
        "{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}}",
        AnalyticPositions,
      ),
      (
        "{\"nest\":{\"with\":\"keyed\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\"]}}",
        NestedRows,
      ),
    ] {
    let prefix =
      #|[{"derive":{"x":"concat($p, to_string($n))"}},{"distinct":["id"],"as":"keyed"},
    let requirements = operation_order_fixture(prefix + operation + "]")
    let result = link_program_operation_orders(requirements, 10000000, 100).unwrap()
    assert_eq(operation_orders_count(result), 3)
    for i in 0..<3 {
      let link = operation_order_link_at(result, i).unwrap()
      assert_eq(
        @pipeline.operation_order_demand(link.site.requirement),
        Some(expected),
      )
      match link.resolution {
        KeyCompletion(_) =>
          assert_true(expected == LagKey || expected == CompleteOrder)
        AnalyticPosition(v) => {
          assert_eq(expected, AnalyticPositions)
          assert_true(
            physical_equal(
              @pipeline.analytic_order_consumer(v),
              @pipeline.step_at(link.site.pipeline, link.site.step).unwrap(),
            ),
          )
        }
        NestedRows(v) => {
          assert_eq(expected, NestedRows)
          assert_true(
            physical_equal(
              @pipeline.nest_order_consumer(v),
              @pipeline.step_at(link.site.pipeline, link.site.step).unwrap(),
            ),
          )
        }
        _ => fail("wrong contextual strategy")
      }
    }
  }
}

///|
test "prefix watermark uses its existing input sequence rather than a completed key" {
  let requirements = operation_order_fixture(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"derive":{"x":"concat($p, to_string($n))"}},{"watermark_rows":{"time":"id","max_skew":1,"late_policy":"mark"}}]
    ),
  )
  let result = link_program_operation_orders(requirements, 10000000, 3).unwrap()
  assert_eq(operation_orders_count(result), 3)
  for i in 0..<3 {
    let link = operation_order_link_at(result, i).unwrap()
    guard link.resolution is @pipeline.InputSequence(v) else {
      abort("input sequence")
    }
    assert_eq(@pipeline.input_order_requirement(v), WatermarkPrefixOrder)
    assert_true(
      physical_equal(
        @pipeline.input_order_consumer(v),
        @pipeline.step_at(link.site.pipeline, link.site.step).unwrap(),
      ),
    )
  }
}

///|
test "pivot first retains an input-sequence strategy distinct from take" {
  let requirements = operation_order_fixture(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"derive":{"x":"concat($p, to_string($n))","bucket":"'a'"}},{"pivot":{"index":[],"column":"bucket","values":["a"],"value":"id","aggregate":"first"}}]
    ),
  )
  let result = link_program_operation_orders(requirements, 10000000, 3).unwrap()
  assert_eq(operation_orders_count(result), 3)
  for i in 0..<3 {
    let link = operation_order_link_at(result, i).unwrap()
    guard link.resolution is @pipeline.InputSequence(v) else {
      abort("input sequence")
    }
    assert_eq(@pipeline.input_order_requirement(v), StableInputOrder)
  }
}
