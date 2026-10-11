///|
fn cell_identity_source_fixture() -> (
  NativeIssuerFixture,
  @query.CapturedInputSource,
) raise {
  let fixture = native_issuer_fixture()
  let attempt = native_issued_attempt(fixture)
  native_attempt_receive_fixture(attempt)
  fixture.transport.push(attempt)
  let observation = @duckdb_query.complete_duckdb_native_capture(
    fixture.issuer,
    attempt,
    native_completion_limits(),
  ).unwrap()
  let material = @duckdb_query.materialize_duckdb_native_output(
    fixture.issuer,
    attempt,
    observation,
    100,
    native_retained_values(),
  ).unwrap()
  (fixture, @duckdb_query.native_captured_source(material, 100, 10000).unwrap())
}

///|
fn cell_identity_preparation(
  source : @query.CapturedInputSource,
  work? : Int = 10000,
) -> @query.CapturedSourceIdentityPreparation {
  @query.start_captured_source_identity(
    source,
    2,
    native_retained_values(),
    row_wire_limits(),
    row_wire_limits(),
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    work,
    100000,
  ).unwrap()
}

///|
test "Source identity quantum preserves independent identity and logical work" {
  let mut expected_work : Int64? = None
  for quantum in [1, 7, 100] {
    let (fixture, source) = cell_identity_source_fixture()
    let preparation = cell_identity_preparation(source)
    assert_true(preparation.finish() is Err(Export(NotFinished)))
    let mut work = 0L
    let mut done = false
    for _ in 0..<10000 {
      let (ready, used) = preparation.advance(quantum).unwrap()
      assert_true(used >= 0 && used <= quantum)
      work += used.to_int64()
      if ready {
        done = true
        break
      }
    }
    assert_true(done)
    assert_eq(preparation.work(), work)
    if expected_work is Some(expected) {
      assert_eq(work, expected)
    } else {
      expected_work = Some(work)
    }
    let identity = preparation.finish().unwrap()
    assert_eq(@query.captured_source_relation_row_count(identity), 2)
    assert_eq(
      @query.captured_source_relation_logical_cid(identity),
      "sha256:e07f39c7a3e7a589d556a49072cf1f9fc551f09fad3f441229cff200a98362b6",
    )
    assert_true(
      @query.captured_source_relation_identity_matches_source(identity, source),
    )
    assert_true(@query.captured_source_available(source))
    let (other, foreign) = cell_identity_source_fixture()
    assert_false(
      @query.captured_source_relation_identity_matches_source(identity, foreign),
    )
    @duckdb_query.close_duckdb_native_issuer(other.issuer)
    assert_true(preparation.finish() is Err(Export(Closed)))
    @duckdb_query.close_duckdb_native_issuer(fixture.issuer)
    assert_false(
      @query.captured_source_relation_identity_matches_source(identity, source),
    )
  }
}

///|
test "Source identity unfinished cancelled and exhausted passes never close acquisition" {
  for mode in 0..<3 {
    let (fixture, source) = cell_identity_source_fixture()
    let preparation = cell_identity_preparation(
      source,
      work=if mode == 2 { 1 } else { 10000 },
    )
    preparation.advance(1).unwrap() |> ignore
    let spent = preparation.work()
    assert_true(spent > 0L)
    if mode == 0 {
      assert_true(preparation.cancel())
      assert_true(preparation.advance(1) is Err(Export(Closed)))
    } else if mode == 1 {
      assert_true(preparation.finish() is Err(Export(NotFinished)))
    } else {
      assert_true(
        preparation.advance(100) is Err(Export(Admission(CaptureLimit))),
      )
    }
    assert_eq(preparation.work(), spent)
    assert_true(@query.captured_source_available(source))
    preparation.cancel() |> ignore
    @duckdb_query.close_duckdb_native_issuer(fixture.issuer)
  }
}

///|
test "Source identity revocation across advances preserves monotone work" {
  let (fixture, source) = cell_identity_source_fixture()
  let preparation = cell_identity_preparation(source)
  preparation.advance(1).unwrap() |> ignore
  let work = preparation.work()
  @duckdb_query.close_duckdb_native_issuer(fixture.issuer)
  assert_true(preparation.advance(100) is Err(Unavailable))
  assert_true(preparation.finish() is Err(Unavailable))
  assert_eq(preparation.work(), work)
  assert_true(
    @query.start_captured_source_identity(
      source,
      2,
      native_retained_values(),
      row_wire_limits(),
      row_wire_limits(),
      { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
      10000,
      100000,
    )
    is Err(Unavailable),
  )
}
