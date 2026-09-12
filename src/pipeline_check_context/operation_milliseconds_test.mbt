///|
test "temporal millisecond domains bind fixed step signed offsets and session gaps" {
  for
    (operation, signed) in [
      (
        "{\"row_window\":{\"time\":\"id\",\"kind\":\"fixed\",\"size\":1000,\"step\":{\"$param\":\"n\"}}}",
        false,
      ),
      (
        "{\"row_window\":{\"time\":\"id\",\"kind\":\"fixed\",\"size\":1000,\"offset\":{\"$param\":\"n\"}}}",
        true,
      ),
      (
        "{\"session\":{\"id\":\"id\",\"time\":\"id\",\"by\":[],\"gap\":{\"$param\":\"n\"}}}",
        false,
      ),
    ] {
    for
      (text, n) in [
        ("-9007199254740991", -9007199254740991L),
        ("-1", -1L),
        ("0", 0L),
        ("1", 1L),
        ("9007199254740991", 9007199254740991L),
      ] {
      let requirements = operation_order_fixture(
        scalar_steps(operation),
        supplied=Some(cursor("{\"n\":" + text + "}")),
        tea=true,
      )
      let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
      let result = check_program_operation_scalars(orders, 10000000, 3)
      if signed || n > 0L {
        let result = result.unwrap()
        assert_eq(operation_scalars_count(result), 3)
        for i in 0..<3 {
          let entry = operation_scalar_at(result, i).unwrap()
          assert_eq(entry.value, Milliseconds(n))
          assert_eq(
            @pipeline.operation_scalar_demand(entry.site.requirement),
            Some(@pipeline.Milliseconds("n", signed~)),
          )
          assert_true(entry.parameter.origin is Supplied)
        }
        let work = operation_scalars_work(result)
        assert_true(check_program_operation_scalars(orders, work, 3) is Ok(_))
        assert_true(
          check_program_operation_scalars(orders, work - 1, 3)
          is Err(BudgetExceeded),
        )
        assert_true(
          check_program_operation_scalars(orders, work, 2)
          is Err(BudgetExceeded),
        )
      } else {
        assert_true(
          result
          is Err(InvalidValue(_, @pipeline.Milliseconds("n", signed=false))),
        )
      }
    }
    for text in ["0.5", "9007199254740992", "-9007199254740992"] {
      let requirements = operation_order_fixture(
        scalar_steps(operation),
        supplied=Some(cursor("{\"n\":" + text + "}")),
        tea=true,
      )
      let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
      assert_true(
        check_program_operation_scalars(orders, 10000000, 100)
        is Err(InvalidValue(_, _)),
      )
    }
  }
}

///|
test "temporal duration bindings retain spelling and time series step requirements" {
  for
    operation in [
      "{\"row_window\":{\"time\":\"id\",\"kind\":\"sliding\",\"size\":{\"$param\":\"p\"},\"step\":{\"$param\":\"p\"},\"offset\":{\"$param\":\"p\"}}}",
      "{\"session\":{\"id\":\"id\",\"time\":\"id\",\"by\":[],\"gap\":{\"$param\":\"p\"}}}",
      "{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.000Z\",\"step\":{\"$param\":\"p\"}},\"as\":\"grid\"}",
    ] {
    let parameters = "{\"p\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"01S\"},\"n\":{\"type\":\"number\",\"default\":1}}"
    let requirements = operation_order_fixture(
      scalar_steps(operation),
      parameters~,
      tea=true,
    )
    let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
    let result = check_program_operation_scalars(orders, 10000000, 100).unwrap()
    assert_true(operation_scalars_count(result) > 0)
    for i in 0..<operation_scalars_count(result) {
      let entry = operation_scalar_at(result, i).unwrap()
      assert_eq(entry.value, Milliseconds(1000L))
      guard entry.parameter.value.value is @value.Text(text) else {
        abort("duration")
      }
      assert_eq(text, "01S")
    }
    let work = operation_scalars_work(result)
    assert_true(check_program_operation_scalars(orders, work, 100) is Ok(_))
    assert_true(
      check_program_operation_scalars(orders, work - 1, 100)
      is Err(BudgetExceeded),
    )
  }
}
