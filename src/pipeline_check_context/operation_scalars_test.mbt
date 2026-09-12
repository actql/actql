///|
fn scalar_steps(operation : String) -> String {
  let prefix =
    #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"derive":{"x":"concat($p, to_string($n))"}},
  prefix + operation + "]"
}

///|
test "bound counts retain repeated Parameter occurrences and inclusive budgets" {
  let steps = scalar_steps(
    (
      #|{"take":{"count":{"$param":"n"},"offset":{"$param":"n"}}}
    ),
  )
  for
    (number, expected) in [
      ("1", 1L),
      ("2", 2L),
      ("9007199254740991", 9007199254740991L),
    ] {
    let requirements = operation_order_fixture(
      steps,
      supplied=Some(cursor("{\"n\":" + number + "}")),
    )
    let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
    let result = check_program_operation_scalars(orders, 10000000, 100).unwrap()
    assert_eq(operation_scalars_count(result), 6)
    assert_true(physical_equal(operation_scalars_orders(result), orders))
    let identity = expression_closure_identity(
      operation_requirements_expressions(requirements),
    )
    let stages = program_reference_stages(
      program_sources_references(program_identity_sources(identity)),
    )
    for i in 0..<6 {
      let entry = operation_scalar_at(result, i).unwrap()
      assert_eq(entry.parameter.name, "n")
      assert_true(
        physical_equal(
          entry.site,
          operation_requirements_at(requirements, entry.requirement_index).unwrap(),
        ),
      )
      assert_eq(entry.value, Integer(expected))
      assert_true(entry.parameter.origin is Supplied)
      let bound = parameter_visit_at(
        stage_context_at(stages, entry.site.stage).unwrap(),
        entry.site.producer_visit,
      ).unwrap().bound.unwrap()
      assert_true(
        physical_equal(
          entry.parameter,
          @references.used_value_at(bound, 0).unwrap(),
        ),
      )
    }
    let work = operation_scalars_work(result)
    // Search compares p then n, charging both names before each comparison.
    assert_eq(
      work,
      operation_orders_work(orders) +
      1 +
      operation_requirements_count(requirements) +
      6 * 7,
    )
    assert_true(check_program_operation_scalars(orders, work, 6) is Ok(_))
    assert_true(
      check_program_operation_scalars(orders, work - 1, 6)
      is Err(BudgetExceeded),
    )
    assert_true(
      check_program_operation_scalars(orders, work, 5) is Err(BudgetExceeded),
    )
    assert_true(
      check_program_operation_scalars(orders, -1, 6) is Err(InvalidLimits),
    )
    assert_true(
      check_program_operation_scalars(orders, work, -1) is Err(InvalidLimits),
    )
    for i in [-1, 6, 2147483647] {
      assert_true(operation_scalar_at(result, i) is None)
    }
  }
}

///|
test "zero offset is accepted while fractional negative and unsafe offsets are rejected" {
  let steps = scalar_steps(
    (
      #|{"take":{"count":1,"offset":{"$param":"n"}}}
    ),
  )
  for number in ["0", "-1", "1.5", "9007199254740992"] {
    let requirements = operation_order_fixture(
      steps,
      supplied=Some(cursor("{\"n\":" + number + "}")),
    )
    let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
    let result = check_program_operation_scalars(orders, 10000000, 100)
    if number == "0" {
      assert_eq(
        operation_scalar_at(result.unwrap(), 0).unwrap().value,
        Integer(0L),
      )
    } else {
      guard result is Err(InvalidValue(i, demand)) else {
        abort("invalid offset")
      }
      assert_eq(demand, @pipeline.SafeInteger("n", minimum=0L))
      assert_true(operation_requirements_at(requirements, i) is Some(_))
    }
  }
}

///|
test "fraction and finite thresholds use different domains of the same bound number" {
  for
    (operation, fraction) in [
      (
        "{\"group\":{\"by\":[],\"aggregates\":{\"p\":{\"fn\":\"percentile_cont\",\"field\":\"id\",\"fraction\":{\"$param\":\"n\"}}}}}",
        true,
      ),
      (
        "{\"watermark_rows\":{\"time\":\"id\",\"watermark_ms\":{\"$param\":\"n\"},\"late_policy\":\"mark\"}}",
        false,
      ),
    ] {
    for
      (number, accepted) in [
        ("-0.5", !fraction),
        ("0", true),
        ("0.5", true),
        ("1", true),
        ("1.5", !fraction),
      ] {
      let requirements = operation_order_fixture(
        scalar_steps(operation),
        supplied=Some(cursor("{\"n\":" + number + "}")),
      )
      let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
      let result = check_program_operation_scalars(orders, 10000000, 100)
      assert_eq(result is Ok(_), accepted)
      if accepted {
        let result = result.unwrap()
        assert_eq(operation_scalars_count(result), 3)
        let value = operation_scalar_at(result, 0).unwrap().value
        assert_eq(value is Fraction(_), fraction)
        assert_eq(value is Finite(_), !fraction)
      }
    }
  }
}

///|
test "duration requirements retain authored text while exposing exact milliseconds" {
  let steps = scalar_steps(
    (
      #|{"watermark_rows":{"time":"id","max_skew":{"$param":"p"},"late_policy":"mark"}}
    ),
  )
  let parameters =
    #|{"p":{"type":"string","format":"duration","default":"01S"},"n":{"type":"number","default":1}}
  let requirements = operation_order_fixture(steps, parameters~)
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  let result = check_program_operation_scalars(orders, 10000000, 3).unwrap()
  assert_eq(operation_scalars_count(result), 3)
  for i in 0..<3 {
    let entry = operation_scalar_at(result, i).unwrap()
    assert_eq(entry.value, DurationMilliseconds(1000L))
    guard entry.parameter.value.value is @value.Text(text) else {
      abort("duration")
    }
    assert_eq(text, "01S")
  }
  let work = operation_scalars_work(result)
  assert_true(check_program_operation_scalars(orders, work, 3) is Ok(_))
  assert_true(
    check_program_operation_scalars(orders, work - 1, 3) is Err(BudgetExceeded),
  )
}

///|
test "late invalid scalar and nullable numeric binding cannot expose partial success" {
  let steps = scalar_steps(
    (
      #|{"watermark_rows":{"time":"id","watermark_ms":{"$param":"n"},"late_policy":"mark"}},{"take":{"count":1,"offset":{"$param":"n"}}}
    ),
  )
  let requirements = operation_order_fixture(
    steps,
    supplied=Some(cursor("{\"n\":1.5}")),
  )
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  guard check_program_operation_scalars(orders, 10000000, 100)
    is Err(InvalidValue(index, @pipeline.SafeInteger("n", minimum=0L))) else {
    abort("late invalid offset")
  }
  assert_true(index > 0)
  assert_eq(operation_requirements_at(requirements, index).unwrap().step, 3)
  let parameters =
    #|{"p":{"type":"string","default":"x"},"n":{"type":"number","nullable":true,"default":1}}
  let steps = scalar_steps(
    (
      #|{"take":{"count":{"$param":"n"}}}
    ),
  )
  let requirements = operation_order_fixture(
    steps,
    parameters~,
    supplied=Some(cursor("{\"n\":null}")),
  )
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  assert_true(
    check_program_operation_scalars(orders, 10000000, 100)
    is Err(InvalidValue(_, @pipeline.SafeInteger("n", minimum=1L))),
  )
}
