///|
test "static plan quote controls are retained before any dynamic quote" {
  let mut calls = 0
  let mut retained = 0L
  let result = native_prepare_static_plan_quote_controls((r, e, raw) => {
    calls += 1
    retained = r
    if r > 0L && e == r && raw > 0L {
      Err(CapacityExceeded)
    } else {
      Err(CustodyLost)
    }
  })
  assert_true(result is Err(CapacityExceeded))
  assert_eq(calls, 1)
  assert_eq(retained, static_plan_quote_control_bytes)
  assert_eq(
    @execution.preparation_representation_cost({
      ..static_plan_quote_controls,
      scalar_words: static_plan_quote_controls.scalar_words +
      static_plan_quote_controls.record_headers,
    }),
    Some(retained),
  )
}

///|
test "carrier measurement and issuance quotes keep distinct constructors" {
  let data : @host.ClientCarrierMeasurementConstruction = {
    value_nodes: 3,
    depth: 1,
    max_contract_nodes: 1,
    graph_nodes: 0,
    graph_branch: false,
    graph_edges: 0,
    max_graph_keys: 0,
    max_graph_labels: 0,
    reference_name_headers: 0L,
    reference_name_utf16: 0L,
    max_reference_name_utf16: 0L,
    presence_fields: None,
  }
  let (r, e, raw) = native_static_plan_carrier_measurement_working(data).unwrap()
  assert_eq(r, 0L)
  assert_true(e > 0L && raw > 0L)
  let codec = native_static_plan_carrier_codec_layout(data, (50, 3, 1)).unwrap()
  assert_eq(codec.retained.owned_utf16_units, 71L)
  assert_true(codec.scratch.owned_wire_bytes > 0L)
  assert_eq(codec.builder_utf16_bound, 0L)
  let presence = {
    ..data,
    presence_fields: Some(1),
    reference_name_headers: 1L,
    reference_name_utf16: 4L,
    max_reference_name_utf16: 4L,
  }
  let emitted = native_static_plan_carrier_codec_layout(presence, (70, 4, 2)).unwrap()
  assert_eq(emitted.builder_utf16_bound, 70L)
  assert_true(
    emitted.scratch.owned_utf16_units > codec.scratch.owned_utf16_units,
  )
  assert_true(native_static_plan_carrier_codec_layout(data, (0, 3, 1)) is None)
}
