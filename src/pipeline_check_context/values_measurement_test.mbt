///|
fn assert_values_measurements(
  queries : ProgramOperationQueries,
  expected : (Int, Int, Int),
) -> Unit raise {
  let cells = check_program_operation_cells(queries, 10000000, 100).unwrap()
  let requirements = operation_orders_requirements(
    operation_scalars_orders(
      operation_frames_scalars(
        operation_fills_frames(
          operation_ranges_fills(operation_queries_ranges(queries)),
        ),
      ),
    ),
  )
  let mut count = 0
  let resolutions = index_program_operation_resolutions(
    resolution_profiles(requirements),
    10000000,
    1000,
  ).unwrap()
  for i in 0..<operation_requirements_count(requirements) {
    let site = operation_requirements_at(requirements, i).unwrap()
    if site.requirement
      is @pipeline.ValuesRequirement(@values.ResolvePublicationResources) {
      count += 1
      assert_eq(
        measure_operation_values_rows(
          cells,
          i,
          expected.0,
          expected.1,
          expected.2,
        ).unwrap(),
        expected,
      )
      assert_true(operation_resolution_at(resolutions, i) is Some(Unresolved))
      for
        (bytes, nodes, depth) in [
          (expected.0 - 1, expected.1, expected.2),
          (expected.0, expected.1 - 1, expected.2),
          (expected.0, expected.1, expected.2 - 1),
          (-1, expected.1, expected.2),
        ] {
        assert_true(
          measure_operation_values_rows(cells, i, bytes, nodes, depth)
          is Err(Encoding(@encode.OutputLimit)),
        )
      }
      // Failure cannot mutate the owner or consume a shared binding occurrence.
      assert_eq(
        measure_operation_values_rows(
          cells,
          i,
          expected.0,
          expected.1,
          expected.2,
        ).unwrap(),
        expected,
      )
    } else {
      assert_true(
        measure_operation_values_rows(cells, i, 1000, 1000, 1000)
        is Err(InvalidRequirement),
      )
    }
  }
  assert_eq(count, 3)
  for index in [-1, operation_requirements_count(requirements)] {
    assert_true(
      measure_operation_values_rows(cells, index, 1000, 1000, 1000)
      is Err(InvalidRequirement),
    )
  }
}

///|
test "values wire measurement follows owned repeated binding occurrences" {
  let field = "{\"type\":\"number\",\"nullable\":false}"
  let declaration = "{\"type\":\"number\",\"default\":7}"
  let rows = "[{\"x\":{\"$param\":\"n\"}},{\"x\":1},{\"x\":{\"$param\":\"n\"}}]"
  // Fixed JSON wire lengths: [{"x":7},{"x":1},{"x":7}] is 25 UTF-8 bytes;
  // the same occurrences bound to 100 produce 29, with seven nodes and depth two.
  assert_values_measurements(
    cells_fixture(field, declaration, rows),
    (25, 7, 2),
  )
  assert_values_measurements(
    cells_fixture(
      field,
      declaration,
      rows,
      supplied=Some(cursor("{\"n\":100}")),
    ),
    (29, 7, 2),
  )
}

///|
test "values wire measurement retains typed cells and opaque business data" {
  for
    (field, declaration, expected) in [
      (
        "{\"type\":\"number\",\"nullable\":true}",
        "{\"type\":\"number\",\"nullable\":true,\"default\":null}",
        (12, 3, 2),
      ),
      (
        "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}",
        "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"default\":\"19.90\"}",
        (15, 3, 2),
      ),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"default\":[1,2]}",
        (13, 5, 3),
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"literal\":{\"type\":\"string\",\"nullable\":false}}}",
        "{\"type\":\"object\",\"fields\":{\"literal\":{\"type\":\"string\"}},\"default\":{\"literal\":\"$param\"}}",
        (28, 4, 3),
      ),
    ] {
    assert_values_measurements(
      cells_fixture(field, declaration, "[{\"x\":{\"$param\":\"n\"}}]"),
      expected,
    )
  }
}

///|
test "values wire measurement distinguishes empty rows from a quoted row" {
  let field = "{\"type\":\"number\",\"nullable\":false}"
  let declaration = "{\"type\":\"number\",\"default\":7}"
  assert_values_measurements(cells_fixture(field, declaration, "[]"), (2, 1, 1))
  assert_values_measurements(
    cells_fixture(field, declaration, "[{\"x\":{\"literal\":1}}]"),
    (9, 3, 2),
  )
}
