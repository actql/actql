///|
test "Native transport quote rejects each invalid layout fact and overflow" {
  let selected : NativeRelationFileSelection = {
    directory: "/tmp",
    name: "rows.json",
    resource: "records",
    items_path: ["items"],
    key_path: None,
    primary_identity: "id",
  }
  let limits : NativeRelationFileLimits = {
    page: { max_bytes: 8192, max_nodes: 512, max_depth: 8, max_rows: 2, },
    max_work: 1000000,
    chunk_bytes: 7,
    diagnostic_ceiling: 128,
  }
  let layout = @files.native_filesystem_read_layout().unwrap()
  assert_true(
    file_capture_transport_capacity(selected, limits, layout) is Some(_),
  )
  assert_true(file_capture_metadata_capacity(selected, limits) is Some(_))
  // These are negative quote DATA, never synthetic physical originals.
  for
    invalid in [
      { ..layout, root_payload_bytes: -1L, },
      { ..layout, reader_payload_bytes: -1L, },
      { ..layout, observation_payload_bytes: -1L, },
      { ..layout, acquisition_payload_bytes: -1L, },
      { ..layout, external_object_overhead_bytes: -1L, },
      { ..layout, root_payload_bytes: 0L, },
      { ..layout, root_payload_bytes: 9223372036854775807L, },
      { ..layout, acquisition_payload_bytes: 9223372036854775807L, },
      { ..layout, external_object_overhead_bytes: 9223372036854775807L, },
    ] {
    assert_eq(file_capture_transport_capacity(selected, limits, invalid), None)
  }
  let two_buffers = { ..limits, page: { ..limits.page, max_bytes: 8193, }, }
  assert_eq(
    file_capture_transport_capacity(selected, two_buffers, layout).unwrap() -
    file_capture_transport_capacity(selected, limits, layout).unwrap(),
    2L,
  )
  let two_chunks = { ..limits, chunk_bytes: 8, }
  assert_eq(
    file_capture_transport_capacity(selected, two_chunks, layout).unwrap() -
    file_capture_transport_capacity(selected, limits, layout).unwrap(),
    2L,
  )
  // Same independently declared logical fixture, with no physical owner or
  // source read. Use the selected diagnostic directory when one was provided;
  // /tmp is otherwise only finite quote DATA, never a fallback read authority.
  let (declaration, _, acquisition) = capture_fixture_logical()
  let fixture_selection = {
    ..selected,
    directory: @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap_or(
      "/tmp",
    ),
    name: "row-source-input",
  }
  let quote = capture_fixture_quote(
    declaration, acquisition, fixture_selection, limits,
  )
  capture_fixture_report_quote("quote-only", quote)
  assert_true(quote.total_retained >= quote.metadata)
  assert_true(quote.total_execution >= quote.total_retained)
}
