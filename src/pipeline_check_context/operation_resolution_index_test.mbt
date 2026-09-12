///|
fn resolution_profiles(
  requirements : ProgramOperationRequirements,
) -> ProgramOperationProfileLinks {
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  let scalars = check_program_operation_scalars(orders, 10000000, 100).unwrap()
  let frames = check_program_operation_frames(scalars, 10000000, 100).unwrap()
  let fills = check_program_operation_fills(frames, 10000000, 100).unwrap()
  profiles_from_ranges(
    check_program_operation_ranges(fills, 10000000, 100).unwrap(),
  )
}

///|
fn check_resolution_index(
  profiles : ProgramOperationProfileLinks,
  seen : Array[Bool],
) -> Unit raise {
  let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
  assert_true(physical_equal(operation_resolution_profiles(index), profiles))
  let requirements = operation_resolution_requirements(index)
  let count = operation_requirements_count(requirements)
  assert_eq(operation_resolution_count(index), count)
  let mut resolved = 0
  for i in 0..<count {
    let state = operation_resolution_at(index, i).unwrap()
    let site = operation_requirements_at(requirements, i).unwrap()
    match state {
      Unresolved => ()
      Resolved(v) => {
        resolved += 1
        let (position, owner, kind) = match v {
          Order(r) => (r.requirement_index, r.site, 0)
          Scalar(r) => (r.requirement_index, r.site, 1)
          Frame(r) => (r.requirement_index, r.site, 2)
          Fill(r) => (r.requirement_index, r.site, 3)
          Range(r) => (r.requirement_index, r.site, 4)
          Query(r) => (r.requirement_index, r.site, 5)
          Cell(r) => (r.requirement_index, r.site, 6)
          ProfileResolution(r) => (r.requirement_index, r.site, 7)
        }
        seen[kind] = true
        assert_eq(position, i)
        assert_true(physical_equal(owner, site))
      }
    }
  }
  assert_eq(operation_resolution_unresolved_count(index), count - resolved)
  let cells = operation_lexical_cells(
    operation_calendar_lexical(operation_profile_links_calendar(profiles)),
  )
  let queries = operation_cells_queries(cells)
  let ranges = operation_queries_ranges(queries)
  let fills = operation_ranges_fills(ranges)
  let frames = operation_fills_frames(fills)
  let scalars = operation_frames_scalars(frames)
  let orders = operation_scalars_orders(scalars)
  let expected = operation_orders_count(orders) +
    operation_scalars_count(scalars) +
    operation_frames_count(frames) +
    operation_fills_count(fills) +
    operation_ranges_count(ranges) +
    operation_queries_count(queries) +
    operation_cells_count(cells) +
    operation_profile_links_count(profiles)
  assert_eq(resolved, expected)
  let work = operation_resolution_work(index)
  assert_eq(work, operation_profile_links_work(profiles) + 1 + count + resolved)
  assert_true(
    index_program_operation_resolutions(profiles, work, count) is Ok(_),
  )
  assert_true(
    index_program_operation_resolutions(profiles, work - 1, count)
    is Err(BudgetExceeded),
  )
  if count > 0 {
    assert_true(
      index_program_operation_resolutions(profiles, work, count - 1)
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    index_program_operation_resolutions(profiles, -1, count)
    is Err(InvalidLimits),
  )
  assert_true(
    index_program_operation_resolutions(profiles, work, -1)
    is Err(InvalidLimits),
  )
  for i in [-2147483648, -1, count, 2147483647] {
    assert_true(operation_resolution_at(index, i) is None)
  }
}

///|
test "resolution index covers all static result families with exact occurrence ownership" {
  let seen = Array::make(8, false)
  check_resolution_index(
    resolution_profiles(
      operation_order_fixture(
        scalar_steps(
          "{\"sort\":[{\"id\":\"asc\"}]},{\"take\":{\"$param\":\"n\"}}",
        ),
      ),
    ),
    seen,
  )
  let frames = check_program_operation_frames(
    frame_fixture(
      "{\"preceding\":{\"$param\":\"n\"}}", "{\"preceding\":1}", "2",
    ),
    10000000,
    100,
  ).unwrap()
  let fills = check_program_operation_fills(frames, 10000000, 100).unwrap()
  check_resolution_index(
    profiles_from_ranges(
      check_program_operation_ranges(fills, 10000000, 100).unwrap(),
    ),
    seen,
  )
  let fills = check_program_operation_fills(
    fill_fixture(
      "{\"type\":\"number\",\"default\":3}", "{\"type\":\"number\",\"nullable\":false}",
      "1", "{\"$param\":\"n\"}",
    ),
    10000000,
    100,
  ).unwrap()
  check_resolution_index(
    profiles_from_ranges(
      check_program_operation_ranges(fills, 10000000, 100).unwrap(),
    ),
    seen,
  )
  let ranges = check_program_operation_ranges(
    range_fixture(
      false, "{\"$param\":\"n\"}", "\"2000-01-01T00:00:00.000Z\"", "1999-12-31T23:59:59.999Z",
    ),
    10000000,
    100,
  ).unwrap()
  check_resolution_index(profiles_from_ranges(ranges), seen)
  check_resolution_index(
    profiles_from_ranges(query_fixture("{\"$param\":\"n\"}", "[1,2]")),
    seen,
  )
  let cells = check_program_operation_cells(
    cells_fixture(
      "{\"type\":\"number\",\"nullable\":false}", "{\"type\":\"number\",\"default\":7}",
      "[{\"x\":{\"$param\":\"n\"}},{\"x\":{\"$param\":\"n\"}}]",
    ),
    10000000,
    100,
  ).unwrap()
  let lexical = check_program_operation_lexical(cells, None, 10000000, 100).unwrap()
  let calendar = check_program_operation_calendar(lexical, None, 10000000, 100).unwrap()
  check_resolution_index(
    link_program_operation_profiles(calendar, 10000000, 100).unwrap(),
    seen,
  )
  assert_true(seen.all(v => v))
}

///|
test "unresolved operation occurrences are not mistaken for runtime bindings or absent slots" {
  let profiles = resolution_profiles(
    operation_order_fixture(
      "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"dedupe_rows\":{\"by\":[\"id\",\"id\"],\"order_by\":[{\"id\":\"asc\"}]}}]",
    ),
  )
  let index = index_program_operation_resolutions(profiles, 10000000, 3).unwrap()
  assert_eq(operation_resolution_count(index), 3)
  assert_eq(operation_resolution_unresolved_count(index), 3)
  for i in 0..<3 {
    assert_true(operation_resolution_at(index, i) is Some(Unresolved))
    let site = operation_requirements_at(
      operation_resolution_requirements(index),
      i,
    ).unwrap()
    guard site.requirement is @pipeline.RelationRequirement(p) else {
      abort("relation")
    }
    assert_eq(p.kind, FailOnTopTie)
  }
  let (identity, _, _) = prepared_identity_fixture()
  let expressions = close_program_expressions(identity, 10000000, 0).unwrap()
  let requirements = collect_program_operation_requirements(
    expressions, 10000000, 0,
  ).unwrap()
  let empty = resolution_profiles(requirements)
  check_resolution_index(empty, Array::make(8, false))
  assert_eq(
    operation_resolution_count(
      index_program_operation_resolutions(empty, 10000000, 0).unwrap(),
    ),
    0,
  )
}
