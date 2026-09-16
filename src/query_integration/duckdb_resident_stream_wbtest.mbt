///|
test "retained resident import verifies full storage and emits exact physical parameters" {
  let transport : FixedComputeTestTransport = { settled: None, }
  let (attempt, _) = fixed_compute_attempt_fixture(
    transport,
    fixed_compute_attempt_limits(),
  )
  let available = Ref(true)
  let held = receive_retained_attempt(attempt, available)
  transport.settled = Some(attempt)
  @duckdb_compute.stage_retained_duckdb_compute_material(
    attempt,
    @execution.retained_output_material(held),
  ).unwrap()
  let output = @duckdb_compute.complete_duckdb_compute_attempt(attempt).unwrap()
  let storage = @execution.prepare_producer_storage(output, 100, 1000).unwrap()
  let imported = @duckdb.prepare_resident_import(
    storage, "retained_copy", 2, 1000,
  ).unwrap()
  for mode in 0..<4 {
    let stream = @duckdb.prepare_resident_import_stream(
      imported,
      2,
      fixed_compute_attempt_limits().retention,
      retained_attempt_wire_limits(),
      64,
    ).unwrap()
    let parameters = @duckdb.append_resident_import_stream(
      stream,
      if mode == 1 {
        "{\"id\":2}"
      } else {
        "{\"id\":3}"
      },
      { max_bytes: 64, max_nodes: 20, max_depth: 4, max_text_bytes: 64, },
    ).unwrap()
    assert_eq(parameters.length(), 1)
    if mode == 0 {
      let writer = @encode.writer(1000, 20, 4)
      @duckdb.emit_physical_parameter(parameters[0], writer)
      assert_eq(
        @encode.finish(writer),
        "{\"type\":{\"id\":\"DOUBLE\"},\"value\":\"4008000000000000\"}",
      )
      let verified = @duckdb.finish_resident_import_stream(stream).unwrap()
      assert_true(@execution.verified_storage_scan_matches(verified, storage))
    } else {
      if mode == 2 {
        @duckdb.cancel_resident_import_stream(stream) |> ignore
      }
      if mode == 3 {
        available.val = false
      }
      assert_true(@duckdb.finish_resident_import_stream(stream) is Err(_))
    }
    assert_true(@duckdb.finish_resident_import_stream(stream) is Err(_))
  }
  @duckdb_compute.close_duckdb_compute_attempt(attempt)
}
