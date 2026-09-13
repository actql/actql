///|
test "native root eligibility is static owned and does not assume filtered rows hide false roots" {
  let (_, owner) = query_sequence_fixture()
  let query = @duckdb.compile_native_filter_select(
    owner,
    "main",
    "input",
    native_compile_limits(),
  ).unwrap()
  assert_true(@duckdb.prepare_native_root_guard(query, -1) is Err(InvalidLimit))
  for ceiling in [0, 3, 4] {
    assert_true(
      @duckdb.prepare_native_root_guard(query, ceiling)
      is Err(UnsupportedCeiling),
    )
  }
  let proof = @duckdb.prepare_native_root_guard(query, 5).unwrap()
  assert_eq(@duckdb.native_root_guard_bound(proof), 5)
  assert_true(@duckdb.native_root_guard_matches(proof, query, 5))
  assert_false(@duckdb.native_root_guard_matches(proof, query, 4))
  assert_false(@duckdb.native_root_guard_matches(proof, query, 6))
  // Equal SQL and the same checked owner are not this exact compiled realization.
  let other = @duckdb.compile_native_filter_select(
    owner,
    "main",
    "input",
    native_compile_limits(),
  ).unwrap()
  assert_false(@duckdb.native_root_guard_matches(proof, other, 5))
}

///|
test "owned NULL parameter comparison has a four byte root without evaluating input rows" {
  let (_, owner) = query_sequence_fixture(
    parameters="{\"minimum\":{\"type\":\"number\",\"nullable\":true}}",
    supplied="{\"minimum\":null}",
  )
  let query = @duckdb.compile_native_filter_select(
    owner,
    "main",
    "input",
    native_compile_limits(),
  ).unwrap()
  assert_true(
    @duckdb.prepare_native_root_guard(query, 3) is Err(UnsupportedCeiling),
  )
  let proof = @duckdb.prepare_native_root_guard(query, 4).unwrap()
  assert_eq(@duckdb.native_root_guard_bound(proof), 4)
  assert_true(@duckdb.native_root_guard_matches(proof, query, 4))
  let (_, changed) = query_sequence_fixture(
    parameters="{\"minimum\":{\"type\":\"number\",\"nullable\":true}}",
    supplied="{\"minimum\":1}",
  )
  let other = @duckdb.compile_native_filter_select(
    changed,
    "main",
    "input",
    native_compile_limits(),
  ).unwrap()
  assert_false(@duckdb.native_root_guard_matches(proof, other, 4))
  assert_true(
    @duckdb.prepare_native_root_guard(other, 4) is Err(UnsupportedCeiling),
  )
}
