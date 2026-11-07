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

///|
test "relation file preflight quotes the same complete constructor overlap without acquisition" {
  let (declaration, requirement, acquisition) = capture_fixture_logical()
  let limits = capture_fixture_limits()
  let selection : NativeRelationFileSelection = {
    directory: "/fixture",
    name: "rows.json",
    resource: "records",
    items_path: ["items"],
    key_path: None,
    primary_identity: "id",
  }
  let expected = capture_fixture_quote(
    declaration, acquisition, selection, limits,
  )
  let actual = native_relation_file_capture_limits(
    declaration, requirement, acquisition, selection, limits,
  ).unwrap()
  assert_eq(actual.planning_work, 0)
  assert_eq(actual.attempts, 1)
  assert_eq(actual.holdings, 1)
  assert_eq(actual.transfer_bytes, limits.page.max_bytes.to_int64())
  assert_eq(actual.retained_bytes, expected.total_retained)
  assert_eq(actual.execution_bytes, expected.total_execution)
}

///|
test "relation file preflight rejects equivalent declaration foreign requirement and wrong resource" {
  let (declaration, requirement, acquisition) = capture_fixture_logical()
  let (other, other_requirement, _) = capture_fixture_logical()
  let limits = capture_fixture_limits()
  let selection : NativeRelationFileSelection = {
    directory: "/not-opened",
    name: "rows.json",
    resource: "records",
    items_path: ["items"],
    key_path: None,
    primary_identity: "id",
  }
  assert_true(
    native_relation_file_capture_limits(
      other, requirement, acquisition, selection, limits,
    )
    is Err(Row(@rows.ForeignDeclaration)),
  )
  assert_true(
    native_relation_file_capture_limits(
      declaration, other_requirement, acquisition, selection, limits,
    )
    is Err(Row(@rows.ForeignDeclaration)),
  )
  assert_true(
    native_relation_file_capture_limits(
      declaration,
      requirement,
      acquisition,
      { ..selection, resource: "wrong", },
      limits,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    native_relation_file_capture_limits(
      declaration,
      requirement,
      acquisition,
      selection,
      { ..limits, page: { ..limits.page, max_bytes: 0, }, },
    )
    is Err(InvalidInput),
  )
}

///|
test "relation file resource-only preflight preserves mapping and selection refusals" {
  let (declaration, requirement, acquisition) = capture_fixture_logical()
  let selection : NativeRelationFileSelection = {
    directory: "/never-opened",
    name: "rows.json",
    resource: "records",
    items_path: ["items"],
    key_path: None,
    primary_identity: "id",
  }
  let limits = capture_fixture_limits()
  let target = @rows.row_source_target(declaration, requirement).unwrap()
  let source_ref = @planning.query_requirement_source(requirement).0
  let view = @rows.row_declaration_view(declaration, source_ref).unwrap()
  assert_eq(view.resource, target.0)
  assert_eq(view.fields, target.1)
  assert_true(
    native_relation_file_capture_limits(
      declaration, requirement, acquisition, selection, limits,
    )
    is Ok(_),
  )
  // Positive limits are still insufficient for the original mapping. The
  // resource-only projection must not skip its original bounded validation.
  assert_true(
    native_relation_file_capture_limits(
      declaration,
      requirement,
      acquisition,
      selection,
      { ..limits, page: { ..limits.page, max_nodes: 1, }, },
    )
    is Err(Mapping(_)),
  )
  // A wrong selected resource remains the earlier refusal even when mapping
  // would also fail. This quote never opens the selected file.
  assert_true(
    native_relation_file_capture_limits(
      declaration,
      requirement,
      acquisition,
      { ..selection, resource: "other", },
      { ..limits, page: { ..limits.page, max_nodes: 1, }, },
    )
    is Err(ForeignOriginal),
  )
}

///|
test "Source caller preparation inventory matches independent constructor vectors" {
  let selection : NativeRelationFileSelection = {
    directory: "/fixture",
    name: "records.json",
    resource: "records",
    items_path: ["items"],
    key_path: None,
    primary_identity: "id",
  }
  let limits = capture_fixture_limits()
  // Independently expanded original mapping recipes plus the named Source
  // control frontier. Expected values are not emitted by the product helper.
  // The mapping acquisition selector and the caller's Query/whole-Source
  // selector each retain one header, reference and scalar: +2H/+2R/+2S.
  // At the existing 16/8/8-byte tariff this adds 64 bytes; neither selector
  // owns text/wire or changes the preceding inventory-evaluation frontier.
  // Managed input additionally borrows its original read, selected capacity
  // and provider in the same selector: +3R, or 24 bytes, in every vector.
  for
    (page, path_count, key_count, h, r, s, text, wire, bytes, evaluator_bytes) in [
      (
        @rows.RowPageLimits::{
          max_bytes: 1,
          max_nodes: 1,
          max_depth: 1,
          max_rows: 1,
        },
        1,
        0,
        4930L,
        4278L,
        13393L,
        997L,
        297L,
        222539L,
        23832L,
      ),
      (
        @rows.RowPageLimits::{
          max_bytes: 8192,
          max_nodes: 512,
          max_depth: 8,
          max_rows: 2,
        },
        1,
        0,
        250530L,
        590744L,
        1582531L,
        836435L,
        8488L,
        23076038L,
        23832L,
      ),
      (
        @rows.RowPageLimits::{
          max_bytes: 65536,
          max_nodes: 8192,
          max_depth: 32,
          max_rows: 100,
        },
        16,
        16,
        3937966L,
        9394548L,
        18054027L,
        6874451L,
        65832L,
        296410790L,
        26312L,
      ),
    ] {
    let selected = {
      ..selection,
      items_path: Array::make(path_count, "items"),
      key_path: if key_count == 0 {
        None
      } else {
        Some(Array::make(key_count, "key"))
      },
    }
    let actual = native_relation_file_caller_preparation_inventory(selected, {
      ..limits,
      page,
    }).unwrap()
    assert_eq(actual.record_headers, h)
    assert_eq(actual.reference_slots, r)
    assert_eq(actual.scalar_words, s)
    assert_eq(actual.owned_utf16_units, text)
    assert_eq(actual.owned_wire_bytes, wire)
    assert_eq(
      @execution.preparation_representation_cost(actual).unwrap(),
      bytes,
    )
    assert_eq(
      @execution.preparation_representation_cost(
        native_relation_file_caller_preparation_evaluation_inventory(selected),
      ).unwrap(),
      evaluator_bytes,
    )
  }
  for
    page in [
      @rows.RowPageLimits::{
        max_bytes: 65537,
        max_nodes: 8192,
        max_depth: 32,
        max_rows: 100,
      },
      @rows.RowPageLimits::{
        max_bytes: 65536,
        max_nodes: 8193,
        max_depth: 32,
        max_rows: 100,
      },
      @rows.RowPageLimits::{
        max_bytes: 65536,
        max_nodes: 8192,
        max_depth: 33,
        max_rows: 100,
      },
      @rows.RowPageLimits::{
        max_bytes: 65536,
        max_nodes: 8192,
        max_depth: 32,
        max_rows: 101,
      },
    ] {
    assert_true(
      native_relation_file_caller_preparation_inventory(selection, {
        ..limits,
        page,
      })
      is None,
    )
  }
  assert_true(
    native_relation_file_caller_preparation_inventory(
      { ..selection, items_path: Array::make(17, "items"), },
      limits,
    )
    is None,
  )
  assert_true(
    native_relation_file_caller_preparation_inventory(
      { ..selection, key_path: Some(Array::make(17, "key")), },
      limits,
    )
    is None,
  )
}
