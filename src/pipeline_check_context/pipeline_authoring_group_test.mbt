///|
test "Group authoring retains original execution rules without claiming observations" {
  for function in ["count", "min", "max"] {
    let pipeline = unbound_profile_pipeline(
      false,
      suffix=",{\"group\":{\"by\":[],\"aggregates\":{\"total\":{\"fn\":\"" +
        function +
        "\",\"field\":\"n\"}}}}",
    )
    let profiles = authoring_profile_proof(pipeline)
    let capacity = authoring_capacity()
    let resource = resolve_authoring_values_resources(
      profiles,
      0,
      capacity,
      values_publication_limits(),
    ).unwrap()
    let closure = close_pipeline_authoring(
      profiles,
      capacity,
      [resource],
      100000,
      100,
      3,
    ).unwrap()
    assert_eq(pipeline_authoring_runtime_count(closure), 3)
    guard @pipeline.step_at(pipeline, 3).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("expected the original Group operation")
    }
    let group = @relation.group(operation).unwrap()
    for index in 0..<3 {
      let retained = pipeline_authoring_runtime_at(closure, index).unwrap()
      assert_eq(retained.step, 3)
      assert_eq(retained.index, index)
      assert_true(
        physical_equal(
          @pipeline.operation_obligations_source(retained.owner),
          @relation.source(operation),
        ),
      )
      guard @pipeline.operation_obligations_at(retained.owner, index)
        is Some(@pipeline.RelationRequirement(pending)) else {
        fail("expected the same relation validation")
      }
      match authoring_runtime_group_rule(retained).unwrap() {
        PartitionGroups => assert_eq(pending.kind, @relation.GroupPartitioning)
        EvaluateAggregate(call) | ValidateResultContract(call) => {
          assert_true(
            physical_equal(
              call,
              @relation.aggregate_for_validation(group, index).unwrap(),
            ),
          )
          assert_true(
            pending.kind is @relation.AggregateDemand ||
            pending.kind is @relation.AggregateEnvelope,
          )
        }
        _ => fail("an unrelated execution rule must not be selected")
      }
    }
    let exact = pipeline_authoring_work(closure)
    assert_true(
      close_pipeline_authoring(profiles, capacity, [resource], exact, 100, 3)
      is Ok(_),
    )
    assert_true(
      close_pipeline_authoring(
        profiles,
        capacity,
        [resource],
        exact - 1,
        100,
        3,
      )
      is Err(BudgetExceeded),
    )
    assert_true(
      close_pipeline_authoring(profiles, capacity, [resource], 100000, 100, 2)
      is Err(BudgetExceeded),
    )
  }
}

///|
test "Group authoring cannot defer missing numeric observations or collection limits" {
  for
    call in [
      "{\"fn\":\"sum\",\"field\":\"n\"}", "{\"fn\":\"array_agg\",\"field\":\"n\",\"order_by\":[{\"n\":\"asc\"}],\"max_items\":{\"$param\":\"x\"}}",
    ] {
    let pipeline = unbound_profile_pipeline(
      true,
      suffix=",{\"group\":{\"by\":[],\"aggregates\":{\"total\":" + call + "}}}",
    )
    let profiles = authoring_profile_proof(pipeline)
    let capacity = authoring_capacity()
    let resource = resolve_authoring_values_resources(
      profiles,
      0,
      capacity,
      values_publication_limits(),
    ).unwrap()
    assert_true(
      close_pipeline_authoring(profiles, capacity, [resource], 100000, 100, 100)
      is Err(PendingOperation(3, _, _)),
    )
  }
}
