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
test "HubSpot metadata quotes only native Property role while Account keeps its original peak" {
  let property_limits : PropertyLimits = {
    max_bytes: 8192,
    max_nodes: 2000,
    max_depth: 24,
    max_properties: 100,
    max_name_units: 256,
  }
  let (old, _) = object_initialization_peak_capacity(
    512, 0, 9, property_limits, 100, 256, 8192, 2000, 24,
  ).unwrap()
  let selected = effect_metadata_construction_capacity(512, 9, property_limits).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(selected) <
    @execution.execution_capacity_retained_bytes(old),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(selected) <
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

///|
test "HubSpot installation quote retains only its closed holders and digests while full original metadata stays borrowed" {
  let original = effect_installation_construction_capacity(1, 2, 2, 1024).unwrap()
  let longer = effect_installation_construction_capacity(1, 2, 2, 8192).unwrap()
  let more_sources = effect_installation_construction_capacity(1, 2, 8, 1024).unwrap()
  let more_mappings = effect_installation_construction_capacity(2, 4, 2, 1024).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(original),
    @execution.execution_capacity_retained_bytes(longer),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(longer) >
    @execution.execution_capacity_execution_bytes(original),
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(original),
    @execution.execution_capacity_retained_bytes(more_sources),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(more_sources) >
    @execution.execution_capacity_execution_bytes(original),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(more_mappings) >
    @execution.execution_capacity_retained_bytes(original),
  )
  assert_true(effect_installation_construction_capacity(0, 1, 1, 1) is None)
  assert_true(effect_installation_construction_capacity(2, 1, 2, 1) is None)
  assert_true(effect_installation_construction_capacity(2, 2, 1, 1) is None)
  assert_true(effect_installation_construction_capacity(1, 1, 1, 0) is None)
}

///|
test "Effect Catalog response funds only its real projection beside retained original response" {
  let limits : PropertyLimits = {
    max_bytes: 524288,
    max_nodes: 65536,
    max_depth: 32,
    max_properties: 256,
    max_name_units: 6003,
  }
  // Independent same-scale input, including unknown fields and many nested
  // nodes. No provider response, credential or stopped business state is read.
  let properties = Array::makei(245, index => {
    "{\"name\":\"field_" +
    index.to_string() +
    "\",\"type\":\"string\",\"fieldType\":\"text\",\"description\":\"" +
    String::make(1050, 'x') +
    "\",\"shape\":[" +
    Array::make(11, "{\"a\":0,\"b\":0,\"c\":0,\"d\":0,\"e\":0}").join(",") +
    "]}"
  })
  let body = @utf8.encode("{\"results\":[" + properties.join(",") + "]}")
  assert_true(body.length() > 300000 && body.length() < limits.max_bytes)
  let selected = effect_metadata_construction_capacity(body.length(), 9, limits).unwrap()
  let reference = source_property_recheck_construction_capacity(
    [
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
      limits.max_properties,
      limits.max_name_units,
    ],
    body.length(),
  ).unwrap()
  println(
    "Effect metadata body=\{body.length()} selectedE=\{@execution.execution_capacity_execution_bytes(selected)} nativePropertyRoleE=\{@execution.execution_capacity_execution_bytes(reference)}",
  )
  // The actual installed adapter projects/rechecks a Catalog. It constructs
  // no ObjectSchema/Contract/export or second Host schema JSON forest.
  assert_true(
    @execution.execution_capacity_execution_bytes(selected) <=
    @execution.execution_capacity_execution_bytes(reference),
  )
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 10000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  let initial = effect_metadata_construction_capacity(0, 9, limits).unwrap()
  let token = @resources.reserve_capacity(
    ledger,
    @execution.execution_capacity_retained_bytes(initial),
    @execution.execution_capacity_execution_bytes(initial),
  ).unwrap()
  // Keep the same actual remaining execution allowance as the captured
  // refusal. This represents retained raw response/other live dependencies;
  // it does not classify or retire those originals, or claim normal gain.
  let other = @resources.reserve_capacity(
    ledger,
    0L,
    536870912L -
    60234615L -
    @execution.execution_capacity_execution_bytes(initial),
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @resources.grow_capacity_reservation(
      ledger,
      token,
      @execution.execution_capacity_retained_bytes(selected),
      @execution.execution_capacity_execution_bytes(selected),
    )
    is Err(ExecutionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // The byte-zero initial quote already funded this SAME input's preflight.
  let path = "/crm/v3/properties/companies"
  let prepared = prepare_property_response_source(
    body, path, "companies", limits,
  )
  let data = property_response_source_geometry_data(prepared)
  assert_eq(data.length(), 12)
  let observed = effect_metadata_observed_construction_capacity(
    body.length(),
    9,
    limits,
    data,
  ).unwrap()
  println(
    "Effect observed R=\{@execution.execution_capacity_retained_bytes(observed)} E=\{@execution.execution_capacity_execution_bytes(observed)} nodes=\{data[11]}",
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(observed) <
    @execution.execution_capacity_retained_bytes(selected),
  )
  @resources.grow_capacity_reservation(
    ledger,
    token,
    @execution.execution_capacity_retained_bytes(observed),
    @execution.execution_capacity_execution_bytes(observed),
  ).unwrap()
  let catalog = consume_property_response_source(prepared, path, body).unwrap()
  recheck_property_catalog(catalog, catalog, limits.max_properties).unwrap()
  assert_eq(catalog.properties.length(), 245)
  retire_property_response_source(prepared)
  @resources.settle_capacity(ledger, token).unwrap()
  @resources.settle_capacity(ledger, other).unwrap()
}

///|
test "Effect observed metadata sizes never replace original byte grammar or cursor bounds" {
  let body = b"{\"results\":[]}"
  let limits : PropertyLimits = {
    max_bytes: 256,
    max_nodes: 32,
    max_depth: 8,
    max_properties: 4,
    max_name_units: 32,
  }
  let prepared = prepare_property_response_source(
    body, "/properties", "companies", limits,
  )
  let data = property_response_source_geometry_data(prepared)
  assert_eq(data.length(), 12)
  let quote = effect_metadata_observed_construction_capacity(
    body.length(),
    9,
    limits,
    data,
  ).unwrap()
  let full = effect_metadata_construction_capacity(body.length(), 9, limits).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(quote) <=
    @execution.execution_capacity_retained_bytes(full),
  )
  assert_true(
    effect_metadata_observed_construction_capacity(
      body.length() + 1,
      9,
      limits,
      data,
    )
    is None,
  )
  assert_true(
    effect_metadata_observed_construction_capacity(body.length(), 9, limits, [1])
    is None,
  )
  let invalid = data.copy()
  invalid[11] = -1
  assert_true(
    effect_metadata_observed_construction_capacity(
      body.length(),
      9,
      limits,
      invalid,
    )
    is None,
  )
  assert_true(
    effect_metadata_observed_construction_capacity(
      body.length(),
      9,
      { ..limits, max_bytes: body.length() - 1, },
      data,
    )
    is None,
  )
  let fallback = effect_metadata_observed_construction_capacity(
    body.length(),
    9,
    limits,
    [],
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(fallback),
    @execution.execution_capacity_retained_bytes(full),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(fallback),
    @execution.execution_capacity_execution_bytes(full),
  )
  // Geometry can be copied, but cannot supply or replace the original source.
  let _ = consume_property_response_source(prepared, "/properties", body).unwrap()
  assert_true(
    consume_property_response_source(prepared, "/properties", body) is Err(_),
  )
  retire_property_response_source(prepared)
  for
    bad in [
      b"{\"results\":[],\"other\":NaN}", b"{\"results\":[],\"x\":0,\"x\":1}",
    ] {
    let staged = prepare_property_response_source(
      bad, "/properties", "companies", limits,
    )
    let sizes = property_response_source_geometry_data(staged)
    // A successful preflight/quote is still not a full grammar admission.
    assert_true(
      effect_metadata_observed_construction_capacity(
        bad.length(),
        9,
        limits,
        sizes,
      )
      is Some(_),
    )
    assert_true(
      consume_property_response_source(staged, "/properties", bad) is Err(_),
    )
    retire_property_response_source(staged)
  }
}
