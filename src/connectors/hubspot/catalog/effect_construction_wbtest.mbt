///|
fn effect_page_limits(bytes : Int) -> ObjectPageLimits {
  {
    max_bytes: bytes,
    max_nodes: 3000,
    max_depth: 24,
    max_rows: 1,
    max_columns: 16,
    max_cursor_units: 256,
    max_value_nodes: 2000,
    max_value_text_bytes: 8192,
  }
}

///|
test "HubSpot finalization retains only its new marked output and borrows original immutable text" {
  let warm = effect_request_construction_capacity(
    write_limits(),
    request_limits(),
    read_limits(),
    2,
    10,
    512,
  ).unwrap()
  let finalization = effect_finalization_construction_capacity(
    write_limits(),
    request_limits(),
    read_limits(),
    2,
    10,
    512,
  ).unwrap()
  let wider_text = effect_request_construction_capacity(
    write_limits(),
    request_limits(),
    read_limits(),
    2,
    10,
    4096,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(finalization) <
    @execution.execution_capacity_retained_bytes(warm),
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(wider_text),
    @execution.execution_capacity_retained_bytes(warm),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(wider_text) >
    @execution.execution_capacity_execution_bytes(warm),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(finalization) -
    @execution.execution_capacity_retained_bytes(finalization),
    @execution.execution_capacity_execution_bytes(warm) -
    @execution.execution_capacity_retained_bytes(warm),
  )
}

///|
test "HubSpot Effect constructor quantities separate actual returned representations from scratch" {
  let request = effect_request_construction_capacity(
    write_limits(),
    request_limits(),
    read_limits(),
    2,
    10,
    512,
  ).unwrap()
  let target = effect_target_construction_capacity(
    effect_page_limits(8192),
    { max_input_bytes: 8192, max_nodes: 2000, max_depth: 24, },
    2,
    10,
    512,
  ).unwrap()
  let response = effect_response_construction_capacity(8192, 2000, 24).unwrap()
  let account = effect_account_construction_capacity(16, 1, 8192, 2000, 24).unwrap()
  let metadata = effect_metadata_construction_capacity(512, 9, {
    max_bytes: 8192,
    max_nodes: 2000,
    max_depth: 24,
    max_properties: 100,
    max_name_units: 256,
  }).unwrap()
  for
    (name, capacity) in [
      ("request", request),
      ("target", target),
      ("reply", response),
      ("account", account),
      ("metadata", metadata),
    ] {
    let retained = @execution.execution_capacity_retained_bytes(capacity)
    let peak = @execution.execution_capacity_execution_bytes(capacity)
    assert_true(retained > 0L)
    assert_true(peak > retained)
    assert_true(peak < 536870912L)
    println("HubSpot \{name} constructor retained=\{retained} peak=\{peak}")
  }
}

///|
test "HubSpot metadata and Account quote keep original peaks but not completed parser forests" {
  let property_limits : PropertyLimits = {
    max_bytes: 8192,
    max_nodes: 2000,
    max_depth: 24,
    max_properties: 100,
    max_name_units: 256,
  }
  let old = object_initialization_construction_capacity(
    512, 0, 9, property_limits, 100, 256, 8192, 2000, 24,
  ).unwrap()
  let selected = effect_metadata_construction_capacity(512, 9, property_limits).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(selected) <
    @execution.execution_capacity_retained_bytes(old),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(selected) >=
    @execution.execution_capacity_execution_bytes(old),
  )
  let old_account = account_initialization_construction_capacity(
    16, 0, 1, 8192, 2000, 24,
  ).unwrap()
  let account = effect_account_construction_capacity(16, 1, 8192, 2000, 24).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(account) <
    @execution.execution_capacity_retained_bytes(old_account),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(account) >=
    @execution.execution_capacity_execution_bytes(old_account),
  )
  // Actual old decoders/semantics stay independent of their quantity quotes.
  assert_eq(
    project_account_identity(b"{\"portalId\":7}", {
      max_input_bytes: 8192,
      max_nodes: 2000,
      max_depth: 24,
    }).unwrap().portal_id,
    7,
  )
}

///|
test "HubSpot target quote follows original received bytes while keeping full output limits and refusal" {
  let output : @source.ParseLimits = {
    max_input_bytes: 8192,
    max_nodes: 2000,
    max_depth: 24,
  }
  let small = effect_target_construction_capacity(
    effect_page_limits(1),
    output,
    2,
    10,
    512,
  ).unwrap()
  let large = effect_target_construction_capacity(
    effect_page_limits(8192),
    output,
    2,
    10,
    512,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(small) <
    @execution.execution_capacity_execution_bytes(large),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(small) <
    @execution.execution_capacity_retained_bytes(large),
  )
  let original = read_catalog()
  let request = prepare_record_read_request(
    original,
    [read_target(original, "id", "1")],
    ["amount"],
    read_limits(),
  ).unwrap()
  assert_true(
    project_record_read_observation(
      request,
      b"{}",
      effect_page_limits(8192),
      8192,
      2000,
      24,
    )
    is Err(_),
  )
  let actual = read_response([read_row("1")])
  let observed = project_record_read_observation(
    request,
    actual,
    effect_page_limits(8192),
    8192,
    2000,
    24,
  ).unwrap()
  assert_true(
    record_read_observation_wire(observed).contains(
      "9007199254740993.0100000000",
    ),
  )
}

///|
test "HubSpot Effect quantities refuse invalid original limits and unsupported wider physical leaf" {
  let body = write_limits()
  for
    bad in [
      { ..body, max_depth: 0, },
      { ..body, max_value_nodes: 0, },
      { ..body, max_output_bytes: 0, },
    ] {
    assert_true(
      effect_request_construction_capacity(
        bad,
        request_limits(),
        read_limits(),
        2,
        10,
        512,
      )
      is None,
    )
  }
  assert_true(
    effect_request_construction_capacity(
      body,
      request_limits(),
      read_limits(),
      0,
      10,
      512,
    )
    is None,
  )
  let page = effect_page_limits(8192)
  assert_true(
    effect_target_construction_capacity(
      { ..page, max_rows: 2, },
      { max_input_bytes: 8192, max_nodes: 2000, max_depth: 24, },
      2,
      10,
      512,
    )
    is None,
  )
  assert_true(effect_response_construction_capacity(0, 100, 8) is None)
  assert_true(
    effect_account_construction_capacity(-1, 1, 8192, 2000, 24) is None,
  )
  assert_true(
    effect_metadata_construction_capacity(8193, 9, {
      max_bytes: 8192,
      max_nodes: 2000,
      max_depth: 24,
      max_properties: 100,
      max_name_units: 256,
    })
    is None,
  )
}
