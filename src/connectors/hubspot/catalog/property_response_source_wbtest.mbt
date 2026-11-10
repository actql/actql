///|
fn staged_property_test_limits() -> PropertyLimits {
  {
    max_bytes: 100000,
    max_nodes: 1000,
    max_depth: 16,
    max_properties: 8,
    max_name_units: 100,
  }
}

///|
test "HubSpot staged parser preserves BOM numeric refusal and final complete digest" {
  let path = "/crm/v3/properties/companies"
  let limits = staged_property_test_limits()
  let body = @utf8.encode(
    "\u{feff}{\"results\":[{\"name\":\"counter\",\"type\":\"number\",\"fieldType\":\"number\"}],\"unknown\":-12.50e2}",
  )
  let prepared = prepare_property_response_source(
    body, path, "companies", limits,
  )
  let catalog = consume_property_response_source(prepared, path, body).unwrap()
  assert_eq(property_names(catalog), ["counter"])
  assert_eq(catalog.response_sha256, @sha.hex(body))
  for spelling in ["01", "1e", "NaN"] {
    let body = @utf8.encode("{\"results\":[],\"unknown\":" + spelling + "}")
    let prepared = prepare_property_response_source(
      body, path, "companies", limits,
    )
    assert_true(property_response_source_geometry(prepared) is Some(_))
    assert_true(
      consume_property_response_source(prepared, path, body)
      is Err(InvalidResponse),
    )
  }
}

///|
#cfg(target="js")
test "HubSpot staged Source transfers original once and retires copy mutation path cancellation" {
  let path = "/crm/v3/properties/companies"
  let text = "{\"results\":[{\"name\":\"status\",\"type\":\"enumeration\",\"fieldType\":\"select\",\"options\":[{\"value\":\"é\"}]}],\"e\\u0301\":\"" +
    String::make(10000, '日') +
    "\"}"
  let body = @utf8.encode(text)
  let prepared = prepare_property_response_source(
    body,
    path,
    "companies",
    staged_property_test_limits(),
  )
  let original = prepared.unwrap()
  let g = property_response_source_geometry(prepared).unwrap()
  assert_eq(g.input_bytes, body.length())
  assert_true(g.node_upper < 32)
  let catalog = consume_property_response_source(prepared, path, body).unwrap()
  assert_eq(property_names(catalog), ["status"])
  assert_eq(catalog.response_sha256, @sha.hex(body))
  assert_true(
    @source.take_json_source_parser(original.preflight) is Err(Consumed),
  )
  assert_true(
    consume_property_response_source(prepared, path, body)
    is Err(InvalidResponse),
  )
  retire_property_response_source(prepared)
  retire_property_response_source(prepared)
  for mode in 0..<3 {
    let body = @utf8.encode(text)
    let prepared = prepare_property_response_source(
      body,
      path,
      "companies",
      staged_property_test_limits(),
    )
    let original = prepared.unwrap()
    let supplied = if mode == 0 { @utf8.encode(text) } else { body }
    if mode == 1 {
      mutate_staged_property_body(body)
    }
    assert_true(
      consume_property_response_source(
        prepared,
        if mode == 2 {
          "/foreign"
        } else {
          path
        },
        supplied,
      )
      is Err(InvalidResponse),
    )
    assert_true(original.retired)
    assert_true(
      @source.take_json_source_parser(original.preflight) is Err(Consumed),
    )
  }
  let pending = prepare_property_response_source(
    body,
    path,
    "companies",
    staged_property_test_limits(),
  )
  let original = pending.unwrap()
  assert_false(original.taken)
  assert_false(original.retired)
  retire_property_response_source(pending)
  assert_true(
    @source.take_json_source_parser(original.preflight) is Err(Consumed),
  )
  assert_true(
    consume_property_response_source(pending, path, body)
    is Err(InvalidResponse),
  )
}

///|
#cfg(target="js")
extern "js" fn mutate_staged_property_body(body : Bytes) -> Unit =
  #|body => { body[0] = 0x20; }

///|
test "HubSpot staged geometry does not admit invalid unknown fields or relax original limits" {
  let path = "/crm/v3/properties/companies"
  let limits = staged_property_test_limits()
  let failed = prepare_property_response_source(
    b"\xff", path, "companies", limits,
  )
  assert_true(failed is Err(InvalidResponse))
  assert_eq(property_response_source_geometry_data(failed), [])
  assert_true(
    consume_property_response_source(failed, path, b"\xff")
    is Err(InvalidResponse),
  )
  retire_property_response_source(failed)
  for
    text in [
      "{\"results\":[],\"unknown\":{\"é\":0,\"e\\u0301\":1}}", "{\"results\":[],\"unknown\":[1,",
    ] {
    let body = @utf8.encode(text)
    let prepared = prepare_property_response_source(
      body, path, "companies", limits,
    )
    assert_true(property_response_source_geometry(prepared) is Some(_))
    assert_true(
      consume_property_response_source(prepared, path, body)
      is Err(InvalidResponse),
    )
  }
  for selected in [{ ..limits, max_nodes: 2, }, { ..limits, max_depth: 1, }] {
    let body = b"{\"results\":[],\"unknown\":[[1]]}"
    let prepared = prepare_property_response_source(
      body, path, "companies", selected,
    )
    assert_true(
      consume_property_response_source(prepared, path, body)
      is Err(BudgetExceeded),
    )
  }
}
