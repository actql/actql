///|
fn cells_fixture(
  field : String,
  declaration : String,
  rows : String,
  supplied? : @decode.Cursor? = None,
) -> ProgramOperationQueries {
  let parameters = "{\"p\":{\"type\":\"string\",\"default\":\"x\"},\"n\":" +
    declaration +
    "}"
  let steps = "[{\"values\":{\"schema\":{\"x\":" +
    field +
    "},\"rows\":" +
    rows +
    "},\"as\":\"seed\"},{\"derive\":{\"p_copy\":\"$p\",\"n_copy\":\"$n\"}}]"
  let requirements = operation_order_fixture(steps, parameters~, supplied~)
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  let scalars = check_program_operation_scalars(orders, 10000000, 100).unwrap()
  let frames = check_program_operation_frames(scalars, 10000000, 100).unwrap()
  let fills = check_program_operation_fills(frames, 10000000, 100).unwrap()
  let ranges = check_program_operation_ranges(fills, 10000000, 100).unwrap()
  check_program_operation_queries(ranges, 10000000, 100).unwrap()
}

///|
test "values cell resolutions retain repeated sites and selected typed bindings" {
  let rows = "[{\"x\":{\"$param\":\"n\"}},{\"x\":1},{\"x\":{\"$param\":\"n\"}}]"
  for supplied in [None, Some(cursor("{\"n\":9}"))] {
    let queries = cells_fixture(
      "{\"type\":\"number\",\"nullable\":true}",
      "{\"type\":\"number\",\"default\":7}",
      rows,
      supplied~,
    )
    let result = check_program_operation_cells(queries, 10000000, 6).unwrap()
    assert_true(physical_equal(operation_cells_queries(result), queries))
    assert_eq(operation_cells_count(result), 6)
    for i in 0..<6 {
      let entry = operation_cell_at(result, i).unwrap()
      assert_eq(entry.occurrence.row, if i % 2 == 0 { 0 } else { 2 })
      assert_eq(entry.occurrence.column, 0)
      assert_true(entry.occurrence.target.nullable)
      assert_false(entry.parameter.value.contract.nullable)
      assert_true(
        physical_equal(
          entry.occurrence,
          @values.pending_binding_cell_at(entry.values, entry.site.index).unwrap(),
        ),
      )
      assert_true(
        entry.site.requirement is @pipeline.ValuesRequirement(BindCell("n")),
      )
      if supplied is Some(_) {
        assert_true(entry.parameter.origin is Supplied)
        assert_true(entry.parameter.value.value is @value.Number(9.0))
      } else {
        assert_true(entry.parameter.origin is Default)
        assert_true(entry.parameter.value.value is @value.Number(7.0))
      }
      if i % 2 == 1 {
        let previous = operation_cell_at(result, i - 1).unwrap()
        assert_true(physical_equal(previous.parameter, entry.parameter))
        assert_true(previous.site.index != entry.site.index)
      }
    }
    let used = operation_cells_work(result)
    assert_true(check_program_operation_cells(queries, used, 6) is Ok(_))
    assert_true(
      check_program_operation_cells(queries, used - 1, 6) is Err(BudgetExceeded),
    )
    assert_true(
      check_program_operation_cells(queries, used, 5) is Err(BudgetExceeded),
    )
    assert_true(
      check_program_operation_cells(queries, -1, 6) is Err(InvalidLimits),
    )
    assert_true(
      check_program_operation_cells(queries, used, -1) is Err(InvalidLimits),
    )
    assert_true(operation_cell_at(result, -1) is None)
    assert_true(operation_cell_at(result, 6) is None)
  }
}

///|
test "bound cells preserve null decimal arrays and parameter-like business objects" {
  for
    (field, declaration) in [
      (
        "{\"type\":\"number\",\"nullable\":true}", "{\"type\":\"number\",\"nullable\":true,\"default\":null}",
      ),
      (
        "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}",
        "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"default\":\"19.90\"}",
      ),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"default\":[1,2]}",
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"literal\":{\"type\":\"string\",\"nullable\":false}}}",
        "{\"type\":\"object\",\"fields\":{\"literal\":{\"type\":\"string\"}},\"default\":{\"literal\":\"$param\"}}",
      ),
    ] {
    let queries = cells_fixture(
      field, declaration, "[{\"x\":{\"$param\":\"n\"}}]",
    )
    let result = check_program_operation_cells(queries, 10000000, 3).unwrap()
    assert_eq(operation_cells_count(result), 3)
    let bound = operation_cell_at(result, 0).unwrap().parameter.value
    match bound.value {
      @value.Null => ()
      @value.Decimal(d) => assert_eq(d.coefficient, "1990")
      @value.Array(xs) => {
        assert_eq(@value.element_count(xs), 2)
        assert_true(@value.element_at(xs, 0) is Some(@value.Number(1.0)))
      }
      @value.Object(xs) => {
        let (name, value) = @value.element_at(xs, 0).unwrap()
        assert_eq(name, "literal")
        assert_true(value is @value.Text("$param"))
      }
      _ => fail("typed value changed")
    }
  }
}

///|
test "empty rows and quoted literals do not fabricate cell binding resolutions" {
  for rows in ["[]", "[{\"x\":{\"literal\":1}}]"] {
    let queries = cells_fixture(
      "{\"type\":\"number\",\"nullable\":false}", "{\"type\":\"number\",\"default\":7}",
      rows,
    )
    let result = check_program_operation_cells(queries, 10000000, 0).unwrap()
    assert_eq(operation_cells_count(result), 0)
    assert_true(operation_cells_work(result) > operation_queries_work(queries))
  }
}
