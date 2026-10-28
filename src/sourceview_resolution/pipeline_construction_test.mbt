///|
fn pipeline_construction_fixture(empty? : Bool = false) -> Resolved {
  let input = "{\"connector\":\"crm/main\",\"resource\":\"r\",\"view\":\"v\"}"
  let bodies = if empty {
    "{\"id\":\"a\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}," +
    "{\"id\":\"b\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}," +
    "{\"id\":\"c\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}"
  } else {
    "{\"id\":\"a\",\"inputs\":{\"remote\":" +
    input +
    ",\"other\":" +
    input +
    "},\"steps\":[],\"results\":{\"r\":{}}}," +
    "{\"id\":\"b\",\"inputs\":{\"remote\":" +
    input +
    "},\"steps\":[],\"results\":{\"r\":{}}}," +
    "{\"id\":\"c\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}"
  }
  resolve(
    fixture_inputs(input, stage_bodies=Some(bodies)),
    construction_catalog(),
    caps(),
  ).unwrap()
}

///|
test "pipeline constructor quotes actual three Stage groups and repeated occurrences" {
  let resolved = pipeline_construction_fixture()
  assert_eq(count(resolved), 3)
  let inherited = work(resolved)
  let quote = pipeline_preparation_construction(resolved, inherited + 23).unwrap()
  // Three Stage arrays plus the outer Array; three original entry records.
  // Shared Array units expand 4 arrays/6 slots; no row/schema/text maximum.
  assert_eq(quote.returned, {
    record_headers: 19L,
    reference_slots: 80L,
    scalar_words: 12L,
  })
  assert_eq(quote.temporary, {
    record_headers: 5L,
    reference_slots: 2L,
    scalar_words: 24L,
  })
  let (result, spent) = observe_prepare_pipeline_inputs(
    resolved,
    inherited + 23,
  )
  let registered = result.unwrap()
  assert_true(physical_equal(pipeline_resolution(registered), resolved))
  assert_eq(pipeline_input_count(registered, 0), Some(2))
  assert_eq(pipeline_input_count(registered, 1), Some(1))
  assert_eq(pipeline_input_count(registered, 2), Some(0))
  assert_eq(spent, 23) // stages3 + entries3 + names6+5+6
  assert_true(
    physical_equal(
      pipeline_input_source(registered, 0, 0).unwrap(),
      at(resolved, 0).unwrap(),
    ),
  )
}

///|
test "pipeline constructor preserves original prefix refusal and partial name backing" {
  let resolved = pipeline_construction_fixture()
  let inherited = work(resolved)
  let invalid = pipeline_preparation_construction(resolved, -1).unwrap()
  assert_eq(invalid.returned, {
    record_headers: 2L,
    reference_slots: 1L,
    scalar_words: 2L,
  })
  assert_eq(invalid.temporary, {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  })
  assert_true(prepare_pipeline_inputs(resolved, -1) is Err(InvalidLimits))
  for extra in [-1, 0, 2, 3, 5] {
    let quote = pipeline_preparation_construction(resolved, inherited + extra).unwrap()
    assert_eq(quote.returned, invalid.returned)
    assert_eq(quote.temporary, {
      record_headers: 3L,
      reference_slots: 1L,
      scalar_words: 23L,
    })
    assert_true(
      prepare_pipeline_inputs(resolved, inherited + extra) is Err(WorkLimit),
    )
  }
  // All Stage groups exist once the shared prefix3+3 fits, even when the
  // very first name cannot fit. One-short keeps its actual partial work.
  let fit = pipeline_preparation_construction(resolved, inherited + 6).unwrap()
  let success = pipeline_preparation_construction(resolved, inherited + 23).unwrap()
  assert_eq(fit, success)
  let (result, spent) = observe_prepare_pipeline_inputs(
    resolved,
    inherited + 22,
  )
  assert_true(result is Err(WorkLimit))
  assert_eq(spent, 17) // prefix6 + first two names6+5; no failed6 charge
}

///|
test "pipeline constructor keeps empty Stage groups without invented entries" {
  let resolved = pipeline_construction_fixture(empty=true)
  assert_eq(count(resolved), 0)
  let quote = pipeline_preparation_construction(resolved, work(resolved) + 3).unwrap()
  assert_eq(quote.returned, {
    record_headers: 16L,
    reference_slots: 65L,
    scalar_words: 12L,
  })
  assert_eq(quote.temporary, {
    record_headers: 4L,
    reference_slots: 1L,
    scalar_words: 23L,
  })
  let (result, spent) = observe_prepare_pipeline_inputs(
    resolved,
    work(resolved) + 3,
  )
  let registered = result.unwrap()
  assert_eq(spent, 3)
  for i in 0..<3 {
    assert_eq(pipeline_input_count(registered, i), Some(0))
  }
  assert_true(physical_equal(pipeline_resolution(registered), resolved))
}

///|
test "pipeline work envelope excludes original inherited work on success and refusal" {
  let resolved = pipeline_construction_fixture()
  let inherited = work(resolved)
  assert_eq(pipeline_preparation_work_bound(resolved, -1), 0)
  for
    (extra, expected_spent) in [
      (-1, 0),
      (0, 0),
      (2, 0),
      (3, 3),
      (5, 3),
      (6, 6),
      (22, 17),
      (23, 23),
    ] {
    let maximum = inherited + extra
    let bound = pipeline_preparation_work_bound(resolved, maximum)
    assert_eq(bound, Int::max(0, extra))
    let (result, spent) = observe_prepare_pipeline_inputs(resolved, maximum)
    assert_eq(spent, expected_spent)
    assert_true(spent <= bound)
    if extra == 23 {
      assert_true(result is Ok(_))
    } else {
      assert_true(result is Err(WorkLimit))
    }
  }
}
