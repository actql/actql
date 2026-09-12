///|
fn fill_fixture(
  parameter : String,
  contract : String,
  cell : String,
  fill : String,
  columns? : String = "[\"a\"]",
  supplied? : @decode.Cursor? = None,
) -> ProgramOperationFrames {
  let parameters = "{\"p\":{\"type\":\"string\",\"default\":\"x\"},\"n\":" +
    parameter +
    "}"
  let steps = "[{\"values\":{\"schema\":{\"status\":{\"type\":\"string\",\"nullable\":false},\"data\":" +
    contract +
    "},\"rows\":[{\"status\":\"a\",\"data\":" +
    cell +
    "}]},\"as\":\"seed\"},{\"derive\":{\"p\":\"$p\"}},{\"pivot\":{\"index\":[],\"column\":\"status\",\"values\":" +
    columns +
    ",\"value\":\"data\",\"aggregate\":\"first\",\"fill\":" +
    fill +
    "}}]"
  let requirements = operation_order_fixture(steps, parameters~, supplied~)
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  let scalars = check_program_operation_scalars(orders, 10000000, 100).unwrap()
  check_program_operation_frames(scalars, 10000000, 100).unwrap()
}

///|
test "pivot fill retains admitted scalar decimal and nullable values without conversion" {
  for
    (parameter, contract, cell) in [
      (
        "{\"type\":\"number\",\"default\":3}", "{\"type\":\"number\",\"nullable\":false}",
        "1",
      ),
      (
        "{\"type\":\"number\",\"nullable\":true,\"default\":null}", "{\"type\":\"number\",\"nullable\":false}",
        "1",
      ),
      (
        "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"default\":\"19.90\"}",
        "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}",
        "\"1.00\"",
      ),
    ] {
    let frames = fill_fixture(parameter, contract, cell, "{\"$param\":\"n\"}")
    let result = check_program_operation_fills(frames, 10000000, 3).unwrap()
    assert_true(physical_equal(operation_fills_frames(result), frames))
    assert_eq(operation_fills_count(result), 3)
    for i in 0..<3 {
      let entry = operation_fill_at(result, i).unwrap()
      assert_eq(entry.parameter.name, "n")
      assert_true(entry.parameter.origin is Default)
      if entry.parameter.value.value is @value.Decimal(decimal) {
        assert_eq(decimal.coefficient, "1990")
        assert_eq(decimal.precision, 4)
        assert_eq(decimal.scale, 2)
      }
      assert_true(
        @contract.assignable(entry.parameter.value.contract, entry.target, 100),
      )
      let requirements = operation_orders_requirements(
        operation_scalars_orders(operation_frames_scalars(frames)),
      )
      assert_true(
        physical_equal(
          entry.site,
          operation_requirements_at(requirements, entry.requirement_index).unwrap(),
        ),
      )
      let identity = expression_closure_identity(
        operation_requirements_expressions(requirements),
      )
      let stages = program_reference_stages(
        program_sources_references(program_identity_sources(identity)),
      )
      let visit = parameter_visit_at(
        stage_context_at(stages, entry.site.stage).unwrap(),
        entry.site.producer_visit,
      ).unwrap()
      assert_true(
        physical_equal(
          entry.parameter,
          @references.used_value_at(visit.bound.unwrap(), 0).unwrap(),
        ),
      )
    }
    let work = operation_fills_work(result)
    assert_true(check_program_operation_fills(frames, work, 3) is Ok(_))
    assert_true(
      check_program_operation_fills(frames, work - 1, 3) is Err(BudgetExceeded),
    )
    assert_true(
      check_program_operation_fills(frames, work, 2) is Err(BudgetExceeded),
    )
    assert_true(
      check_program_operation_fills(frames, -1, 3) is Err(InvalidLimits),
    )
    assert_true(
      check_program_operation_fills(frames, work, -1) is Err(InvalidLimits),
    )
    assert_true(operation_fill_at(result, -1) is None)
    assert_true(operation_fill_at(result, 3) is None)
  }
}

///|
test "supplied pivot fill replaces the default without changing its admitted owner" {
  let frames = fill_fixture(
    "{\"type\":\"number\",\"default\":3}",
    "{\"type\":\"number\",\"nullable\":false}",
    "1",
    "{\"$param\":\"n\"}",
    supplied=Some(cursor("{\"n\":7}")),
  )
  let result = check_program_operation_fills(frames, 10000000, 3).unwrap()
  for i in 0..<3 {
    let parameter = operation_fill_at(result, i).unwrap().parameter
    assert_true(parameter.origin is Supplied)
    guard parameter.value.value is @value.Number(n) else { abort("number") }
    assert_eq(n, 7.0)
  }
  let boundary = "{\"preceding\":{\"$param\":\"n\"}}"
  let scalars = frame_fixture(boundary, boundary, "1")
  let frames = check_program_operation_frames(scalars, 10000000, 0).unwrap()
  let empty = check_program_operation_fills(frames, 10000000, 0).unwrap()
  assert_eq(operation_fills_count(empty), 0)
  assert_true(
    check_program_operation_fills(frames, operation_fills_work(empty), 0)
    is Ok(_),
  )
  assert_true(
    check_program_operation_fills(frames, operation_fills_work(empty) - 1, 0)
    is Err(BudgetExceeded),
  )
}

///|
test "pivot empty columns still resolve whole object and array fill parameters" {
  for
    (parameter, contract, cell) in [
      (
        "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"default\":[1,2]}",
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1]",
      ),
      (
        "{\"type\":\"object\",\"fields\":{\"literal\":{\"type\":\"string\"}},\"default\":{\"literal\":\"$param\"}}",
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"literal\":{\"type\":\"string\",\"nullable\":false}}}",
        "{\"literal\":{\"literal\":\"data\"}}",
      ),
    ] {
    let frames = fill_fixture(
      parameter,
      contract,
      cell,
      "{\"$param\":\"n\"}",
      columns="[]",
    )
    let result = check_program_operation_fills(frames, 10000000, 3).unwrap()
    assert_eq(operation_fills_count(result), 3)
    let work = operation_fills_work(result)
    assert_true(check_program_operation_fills(frames, work, 3) is Ok(_))
    assert_true(
      check_program_operation_fills(frames, work - 1, 3) is Err(BudgetExceeded),
    )
  }
}
