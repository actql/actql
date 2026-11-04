///|
test "original query preflight retains one parser and the same long response" {
  let read = begin_query_read(
    query_test_plan(),
    "v62.0",
    {
      max_bytes: 400000,
      max_nodes: 1000,
      max_depth: 10,
      max_rows: 2,
      max_locator_units: 128,
    },
    2,
    2L,
  ).unwrap()
  let path = query_read_next_path(read).unwrap().unwrap()
  let bytes = @utf8.encode(
    "{\"totalSize\":1,\"done\":true,\"records\":[{\"Id\":\"" +
    "x".repeat(200000) +
    "\"}]}",
  )
  let geometry = prepare_query_read_response(read, path, bytes).unwrap()
  assert_true(geometry.input_bytes > 200000)
  assert_true(geometry.node_upper < 20)
  let original = read.pending_source.unwrap()
  assert_eq(prepare_query_read_response(read, path, bytes), Ok(geometry))
  assert_true(physical_equal(original, read.pending_source.unwrap()))
  assert_eq(query_read_next_path(read), Ok(None))
  assert_false(query_read_complete(read))
  let page = query_read_accept_page(read, path, bytes).unwrap()
  assert_true(read.pending_source is None)
  assert_eq(query_page_row_count(page), 1)
  assert_false(query_read_complete(read))
  acknowledge_query_page(read, page).unwrap()
  assert_true(query_read_complete(read))
  assert_true(
    @source.take_json_source_parser(original.preflight) is Err(Consumed),
  )
}

///|
#cfg(target="js")
extern "js" fn mutate_original_query_body(bytes : Bytes) -> Unit =
  #|bytes => { bytes[0] = 0x20; }

///|
#cfg(target="js")
test "copied or mutated query body cannot consume original preflight" {
  for copied in [true, false] {
    let read = query_read_test()
    let path = query_read_next_path(read).unwrap().unwrap()
    let wire = "{\"totalSize\":1,\"done\":true,\"records\":[{\"Id\":\"001\"}]}"
    let bytes = @utf8.encode(wire)
    ignore(prepare_query_read_response(read, path, bytes).unwrap())
    let original = read.pending_source.unwrap()
    let other = if copied {
      @utf8.encode(wire)
    } else {
      mutate_original_query_body(bytes)
      bytes
    }
    assert_true(query_read_accept_page(read, path, other) is Err(WrongPage))
    assert_true(read.pending_source is None)
    assert_false(query_read_complete(read))
    assert_true(
      @source.take_json_source_parser(original.preflight) is Err(Consumed),
    )
  }
}

///|
test "query preflight is not grammar success and interruption retires the cursor" {
  let read = query_read_test()
  let path = query_read_next_path(read).unwrap().unwrap()
  let bytes = @utf8.encode("{\"records\":[{\"Id\":\"001\"}],\"done\":true,")
  let geometry = prepare_query_read_response(read, path, bytes).unwrap()
  assert_true(geometry.node_upper > 0)
  let original = read.pending_source.unwrap()
  assert_true(
    query_read_accept_page(read, path, bytes) is Err(Page(InvalidResponse)),
  )
  assert_false(query_read_complete(read))
  assert_true(query_read_next_path(read) is Err(Interrupted))
  assert_true(
    @source.take_json_source_parser(original.preflight) is Err(Consumed),
  )
  let stopped = query_read_test()
  let path = query_read_next_path(stopped).unwrap().unwrap()
  let bytes = @utf8.encode("{}")
  ignore(prepare_query_read_response(stopped, path, bytes).unwrap())
  let pending = stopped.pending_source.unwrap()
  assert_true(interrupt_query_read(stopped))
  assert_true(
    @source.take_json_source_parser(pending.preflight) is Err(Consumed),
  )
}

///|
test "invalid UTF8 and source node limit retain original query refusal" {
  let invalid = query_read_test()
  let path = query_read_next_path(invalid).unwrap().unwrap()
  assert_true(
    prepare_query_read_response(invalid, path, b"\xff")
    is Err(Page(InvalidResponse)),
  )
  assert_true(invalid.pending_source is None)
  let limited = begin_query_read(
    query_test_plan(),
    "v62.0",
    { ..query_test_limits(), max_nodes: 2, },
    2,
    2L,
  ).unwrap()
  let path = query_read_next_path(limited).unwrap().unwrap()
  let bytes = @utf8.encode(
    "{\"totalSize\":1,\"done\":true,\"records\":[{\"Id\":\"001\"}]}",
  )
  ignore(prepare_query_read_response(limited, path, bytes).unwrap())
  assert_true(
    query_read_accept_page(limited, path, bytes) is Err(Page(BudgetExceeded)),
  )
  assert_false(query_read_complete(limited))
}

///|
test "long response constructor uses observed query geometry and prior metadata extent" {
  let read = begin_query_read(
    query_test_plan(),
    "v62.0",
    {
      max_bytes: 4000000,
      max_nodes: 400000,
      max_depth: 32,
      max_rows: 2000,
      max_locator_units: 2048,
    },
    10,
    100L,
  ).unwrap()
  let path = query_read_next_path(read).unwrap().unwrap()
  let bytes = @utf8.encode(
    "{\"totalSize\":1,\"done\":true,\"records\":[{\"Id\":\"" +
    "x".repeat(232000) +
    "\"}]}",
  )
  let geometry = prepare_query_read_response(read, path, bytes).unwrap()
  let query : QueryPageLimits = {
    ..read.page_limits,
    max_bytes: geometry.input_bytes,
  }
  let metadata : DescribeLimits = {
    max_bytes: 557,
    max_nodes: 557,
    max_depth: 32,
    max_fields: 1000,
    max_name_units: 200000,
  }
  let actual = @salesforce_host.native_read_construction_capacity(
    metadata,
    query,
    8000000,
    306,
    14,
    query_read_response_columns(read),
    10,
    5,
    4096,
    query_geometry=Some(geometry),
    value_nodes=Some(query_read_response_value_node_bound(read, geometry)),
  ).unwrap()
  let old = @salesforce_host.native_read_construction_capacity(
    {
      ..metadata,
      max_bytes: geometry.input_bytes,
      max_nodes: geometry.input_bytes,
    },
    query,
    8000000,
    306,
    14,
    100,
    10,
    5,
    4096,
  ).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(old) > 536870912L)
  assert_true(@execution.execution_capacity_execution_bytes(actual) < 16777216L)
  // Numeric constructor DATA is not grammar success or a page ACK.
  assert_false(query_read_complete(read))
  assert_eq(query_read_next_path(read), Ok(None))
  assert_true(interrupt_query_read(read))
}
