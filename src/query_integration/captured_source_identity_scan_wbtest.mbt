///|
fn retained_identity_source_fixture() -> (
  NativeIssuerFixture,
  @query.CapturedInputSource,
  Ref[Bool],
) raise {
  let f = native_issuer_fixture()
  let attempt = native_issued_attempt(f)
  let receipt = native_retained_receive(attempt)
  let live = Ref(true)
  let handle = @execution.retain_admitted_output_stream(receipt, (), fn() {
    live.val
  })
  @duckdb_query.stage_duckdb_native_output_material(
    attempt,
    @execution.retained_output_material(handle),
  ).unwrap()
  f.transport.push(attempt)
  let observation = @duckdb_query.complete_duckdb_native_capture(
    f.issuer,
    attempt,
    native_completion_limits(),
  ).unwrap()
  (
    f,
    @duckdb_query.native_retained_captured_source(
      f.issuer,
      attempt,
      observation,
      100,
      10000,
    ).unwrap(),
    live,
  )
}

///|
fn retained_identity_scan(
  source : @query.CapturedInputSource,
) -> @query.CapturedSourceIdentityScan {
  @query.prepare_captured_source_identity_scan(
    source,
    100,
    10000,
    2,
    native_retained_values(),
    row_wire_limits(),
    row_wire_limits(),
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    64,
  ).unwrap()
}

///|
test "retained acquisition identity uses exact held content without cell materialization" {
  let (f, source, _) = retained_identity_source_fixture()
  let scan = retained_identity_scan(source)
  let storage = @query.captured_source_identity_scan_storage(scan).unwrap()
  assert_true(@execution.producer_storage_cell(storage, 0, 0) is None)
  for row in ["{\"id\":3}", "{\"id\":2}"] {
    @query.append_captured_source_identity_scan(scan, row, {
      max_bytes: 100,
      max_nodes: 10,
      max_depth: 10,
      max_text_bytes: 100,
    }).unwrap()
  }
  let identity = @query.finish_captured_source_identity_scan(scan).unwrap()
  assert_true(
    @query.captured_source_relation_identity_matches_source(identity, source),
  )
  assert_eq(@query.captured_source_relation_row_count(identity), 2)
  assert_eq(
    @query.captured_source_relation_logical_cid(identity),
    "sha256:e07f39c7a3e7a589d556a49072cf1f9fc551f09fad3f441229cff200a98362b6",
  )
  assert_true(
    @query.captured_source_relation_dependency_bodies(identity, source) is None,
  )
  assert_true(
    @query.finish_captured_source_identity_scan(scan) is Err(Scan(Closed)),
  )
  let (other, foreign, _) = retained_identity_source_fixture()
  assert_false(
    @query.captured_source_relation_identity_matches_source(identity, foreign),
  )
  @duckdb_query.close_duckdb_native_issuer(other.issuer)
  @duckdb_query.close_duckdb_native_issuer(f.issuer)
  assert_false(
    @query.captured_source_relation_identity_matches_source(identity, source),
  )
}

///|
test "retained acquisition identity cancellation and revocation preserve source ownership" {
  for mode in 0..<4 {
    let (f, source, live) = retained_identity_source_fixture()
    let scan = retained_identity_scan(source)
    @query.append_captured_source_identity_scan(scan, "{\"id\":3}", {
      max_bytes: 100,
      max_nodes: 10,
      max_depth: 10,
      max_text_bytes: 100,
    }).unwrap()
    if mode == 0 {
      assert_true(@query.cancel_captured_source_identity_scan(scan))
      assert_true(@query.captured_source_available(source))
      assert_true(
        @query.finish_captured_source_identity_scan(scan) is Err(Scan(Closed)),
      )
    } else if mode == 1 {
      live.val = false
      assert_true(
        @query.finish_captured_source_identity_scan(scan) is Err(Unavailable),
      )
    } else if mode == 2 {
      @duckdb_query.close_duckdb_native_issuer(f.issuer)
      assert_true(
        @query.finish_captured_source_identity_scan(scan) is Err(Unavailable),
      )
    } else {
      assert_true(
        @query.finish_captured_source_identity_scan(scan)
        is Err(Scan(IdentityMismatch)),
      )
      assert_true(@query.captured_source_available(source))
    }
    @duckdb_query.close_duckdb_native_issuer(f.issuer)
  }
}
