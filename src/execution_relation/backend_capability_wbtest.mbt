///|
fn capability_request(
  rows : String,
  operation : String,
  ordered? : Bool = false,
  nullable? : Bool = true,
) -> @lower.FragmentRequest {
  let sequence = prepared_sequence(
    bound_pipeline(
      "[{\"values\":{\"schema\":{\"d\":{\"type\":\"date\",\"nullable\":" +
      (if nullable { "true" } else { "false" }) +
      "}},\"rows\":" +
      rows +
      "},\"as\":\"seed\"}," +
      operation +
      "]",
    ),
  )
  let pipeline = @lower.prepare_fragment_pipeline(sequence, 1, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  @lower.prepare_fragment_request(
    pipeline,
    10L,
    1000L,
    row_limits=if ordered { Some(capability_limits()) } else { None },
  ).unwrap()
}

///|
fn capability_limits() -> @lower.FragmentRowLimits {
  {
    max_input_rows: 10L,
    max_value_bytes: 1000L,
    max_live_value_bytes: 10000L,
    max_work: 100000L,
  }
}

///|
test "review nonnullable date comparison fails common preparation for empty and nonempty input" {
  for rows in ["[]", "[{\"d\":\"2026-01-01\"}]"] {
    let request = capability_request(
      rows,
      "{\"filter\":\"d = d\"}",
      nullable=false,
    )
    assert_true(
      prepare_runtime_fragment(
        request,
        test_fragment_contract(),
        material_demands(),
        registry_limits(),
        capability_limits(),
      )
      is Err(Runtime(Capability({ kind: UnsupportedComparison(Equal), .. }))),
    )
  }
}

///|
test "unsupported comparison is rejected before rows or lazy branch selection" {
  for rows in ["[]", "[{\"d\":\"2026-01-01\"}]", "[{\"d\":null}]"] {
    for
      expression in [
        "d = d", "d <> d", "d < d", "d <= d", "d > d", "d >= d", "nullif(d, d) IS NULL",
        "if(TRUE, TRUE, d = d)", "coalesce(TRUE, d = d)", "CASE WHEN TRUE THEN TRUE ELSE d = d END",
        "CASE WHEN TRUE THEN TRUE WHEN d = d THEN FALSE ELSE FALSE END",
      ] {
      let request = capability_request(
        rows,
        "{\"filter\":\"" + expression + "\"}",
      )
      let result = prepare_runtime_fragment(
        request,
        test_fragment_contract(),
        material_demands(),
        registry_limits(),
        capability_limits(),
      )
      guard result is Err(Runtime(Capability(issue))) else {
        fail("unsupported comparison must fail preparation")
      }
      assert_true(issue.kind is UnsupportedComparison(_))
      assert_eq(issue.root.step_index, 1)
      assert_eq(
        @decode.text(@lower.expression_location(issue.expression).source).unwrap(),
        expression,
      )
      assert_true(@lower.expression_location(issue.expression).range is Some(_))
      assert_true(@lower.expression_body(issue.expression) is Binary(_, _, _))
    }
  }
}

///|
test "map and ordered kernels use the same backend readiness check" {
  for ordered in [false, true] {
    let operation = if ordered {
      "{\"derive\":[{\"v\":\"if(TRUE, TRUE, d = d)\"}]}"
    } else {
      "{\"derive\":{\"unused\":\"if(TRUE, TRUE, d = d)\"}}"
    }
    let request = capability_request("[]", operation, ordered~)
    let extension = if ordered {
      Some(
        admit_ordered_contract(
          registered_relation_contracts(),
          registered_ordered(),
          registry_limits(),
        ).unwrap(),
      )
    } else {
      None
    }
    assert_true(
      prepare_runtime_fragment(
        request,
        test_fragment_contract(),
        material_demands(),
        registry_limits(),
        capability_limits(),
        ordered=extension,
      )
      is Err(Runtime(Capability({ kind: UnsupportedComparison(Equal), .. }))),
    )
  }
}

///|
test "date passthrough and null inspection are not forbidden by comparison capability" {
  for
    operation in ["{\"derive\":{\"copy\":\"d\"}}", "{\"filter\":\"d IS NULL\"}"] {
    let request = capability_request("[{\"d\":null}]", operation)
    assert_true(
      prepare_runtime_fragment(
        request,
        test_fragment_contract(),
        material_demands(),
        registry_limits(),
        capability_limits(),
      )
      is Ok(_),
    )
  }
}

///|
test "capability traversal shares bounded work across roots and nested children" {
  let request = capability_request(
    "[]", "{\"derive\":{\"a\":\"1 = 1\",\"b\":\"2 = 2\"}}",
  )
  let roots = @lower.fragment_pipeline_roots(
    @lower.fragment_request_pipeline(request),
  )
  // Each binary root charges its queue entry, three visits and two edges.
  assert_true(check_backend_capabilities(roots, 12) is Ok(_))
  assert_true(
    check_backend_capabilities(roots, 11) is Err({ kind: PreparationLimit, .. }),
  )
  assert_true(
    check_backend_capabilities(roots, 0) is Err({ kind: PreparationLimit, .. }),
  )
}

///|
test "backend preparation does not evaluate data dependent failures or change lazy evaluation" {
  for
    (expression, fails) in [
      ("if(TRUE, TRUE, 1 / 0 > 0)", false),
      ("coalesce(TRUE, 1 / 0 > 0)", false),
      ("CASE WHEN TRUE THEN TRUE ELSE 1 / 0 > 0 END", false),
      ("FALSE AND 1 / 0 > 0", true),
      ("TRUE OR 1 / 0 > 0", true),
      ("if(FALSE, TRUE, 1 / 0 > 0)", true),
    ] {
    let request = capability_request(
      "[{\"d\":null}]",
      "{\"filter\":\"" + expression + "\"}",
    )
    let context = prepare_runtime_fragment(
      request,
      test_fragment_contract(),
      material_demands(),
      registry_limits(),
      capability_limits(),
    ).unwrap()
    let roots = @lower.fragment_pipeline_roots(
      @lower.fragment_request_pipeline(request),
    )
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      @lower.root_sequence(roots),
      [context],
      ["where_1"],
      100000,
      10000,
    ).unwrap()
    let result = execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    if fails {
      assert_true(
        result
        is Err(
          Rows(1, Evaluation(0, 0, { kind: Scalar(ArithmeticFailure), .. }))
        ),
      )
    } else {
      assert_true(result is Ok(_))
    }
  }
}
