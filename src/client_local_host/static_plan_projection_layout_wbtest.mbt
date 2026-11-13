///|
fn static_projection_test_geometry() -> @publication_host.ClientStaticPlanViewConstruction {
  {
    step_count: 2,
    input_port_count: 1,
    output_port_count: 2,
    max_stage_producers: 2,
    max_step_ports: 2,
    source_field_count: 5L,
    max_source_fields: 3,
    quoted_text_bytes: 24L,
    max_quoted_text_bytes: 10,
    ports_wire_bytes: 900L,
    steps_wire_bytes: 1800L,
    max_step: (1000, 50, 4),
    step_key: (300, 8, 2),
    port_key: (330, 7, 1),
    carrier_contract: (120, 8, 3),
    max_port: (300, 12, 2),
    map_body: (2100, 100, 6),
    map_sealed: (2184, 101, 6),
    view: (2700, 130, 7),
  }
}

///|
// Synthetic codec component tests exercise only composition arithmetic, not
// validator completeness, measured issuer geometry or physical admission.
fn static_projection_test_component() -> ClientStaticPlanCodecLayout {
  client_static_plan_codec_layout(
    (300, 20, 4),
    static_plan_codec_test_validator(),
    17L,
    20L,
    13L,
  ).unwrap()
}

///|
test "projection composition retains only returned view while funding overlapping constructors" {
  let geometry = static_projection_test_geometry()
  let component = static_projection_test_component()
  let layout = client_static_plan_projection_layout(
    geometry, component, component, component, component, component,
  ).unwrap()
  let result : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: geometry.view.0.to_int64(),
    owned_wire_bytes: 0L,
  }
  assert_eq(
    layout.retained_cost,
    @execution.preparation_representation_cost(result).unwrap(),
  )
  assert_true(layout.execution_cost > layout.retained_cost)
  assert_true(layout.string_utf16_units >= geometry.view.0.to_int64())
  assert_true(
    layout.reference_array_slots >=
    12L + 3L * geometry.max_source_fields.to_int64(),
  )
  let expanded = client_static_plan_projection_layout(
    { ..geometry, ports_wire_bytes: geometry.ports_wire_bytes + 100L, },
    component,
    component,
    component,
    component,
    component,
  ).unwrap()
  assert_eq(layout.retained_cost, expanded.retained_cost)
  assert_true(expanded.execution_cost > layout.execution_cost)
}

///|
test "projection composition refuses invalid and overflowing geometry without dropping any component" {
  let geometry = static_projection_test_geometry()
  let component = static_projection_test_component()
  for
    invalid in [
      { ..geometry, step_count: 0, },
      { ..geometry, ports_wire_bytes: -1L, },
      { ..geometry, quoted_text_bytes: 9223372036854775807L, },
      { ..geometry, steps_wire_bytes: 9223372036854775807L, },
      { ..geometry, source_field_count: 9223372036854775807L, },
    ] {
    assert_true(
      client_static_plan_projection_layout(
        invalid, component, component, component, component, component,
      )
      is None,
    )
  }
  let bad = {
    ..component,
    scratch: { ..component.scratch, record_headers: -1L, },
  }
  assert_true(
    client_static_plan_projection_layout(
      geometry, component, component, component, component, bad,
    )
    is None,
  )
}

///|
test "every mandatory codec construction contributes to the same projection peak" {
  let geometry = static_projection_test_geometry()
  let base = static_projection_test_component()
  let larger = {
    ..base,
    retained: {
      ..base.retained,
      owned_utf16_units: base.retained.owned_utf16_units + 100L,
    },
  }
  let original = client_static_plan_projection_layout(
    geometry, base, base, base, base, base,
  ).unwrap()
  for
    layout in [
      client_static_plan_projection_layout(
        geometry, larger, base, base, base, base,
      ),
      client_static_plan_projection_layout(
        geometry, base, larger, base, base, base,
      ),
      client_static_plan_projection_layout(
        geometry, base, base, larger, base, base,
      ),
      client_static_plan_projection_layout(
        geometry, base, base, base, larger, base,
      ),
      client_static_plan_projection_layout(
        geometry, base, base, base, base, larger,
      ),
    ] {
    assert_true(layout.unwrap().execution_cost > original.execution_cost)
    assert_eq(layout.unwrap().retained_cost, original.retained_cost)
  }
}
