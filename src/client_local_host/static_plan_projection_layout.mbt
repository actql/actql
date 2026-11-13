///|
/// Complete projection composition DATA only after separately funded typed-IR
/// measurement. It consumes complete mandatory codec/validator/Carrier recipes.
/// No measurement, existing checked owner or physical fixed controls are granted.
pub(all) struct ClientStaticPlanProjectionLayout {
  retained_cost : Int64
  execution_cost : Int64
  string_utf16_units : Int64
  builder_utf16_bound : Int64
  wire_bytes : Int64
  reference_array_slots : Int64
  map_bucket_slots : Int64
  scalar_array_items : Int64
}

///|
// Variable geometry for the first checked-IR projection only. Every argument
// is constructor DATA, not authority. Measurement, the retained checked owner,
// and this helper's fixed controls must ALREADY have backing in the same Read.
// Cold arbitrary JSON does not inherit the fresh issuer's validator recipes.
pub fn client_static_plan_projection_layout(
  geometry : @publication_host.ClientStaticPlanViewConstruction,
  step_key : ClientStaticPlanCodecLayout,
  port_key : ClientStaticPlanCodecLayout,
  map : ClientStaticPlanCodecLayout,
  view : ClientStaticPlanCodecLayout,
  carrier : ClientStaticPlanCodecLayout,
) -> ClientStaticPlanProjectionLayout? {
  let steps = geometry.step_count.to_int64()
  let ports = geometry.input_port_count.to_int64() +
    geometry.output_port_count.to_int64()
  if steps < 1L ||
    ports < 1L ||
    ports > 2147483647L ||
    geometry.max_stage_producers < 1 ||
    geometry.max_step_ports < 1 ||
    geometry.source_field_count < 0L ||
    geometry.source_field_count > steps * geometry.max_source_fields.to_int64() ||
    geometry.max_source_fields < 0 ||
    geometry.quoted_text_bytes < 0L ||
    geometry.quoted_text_bytes > 9223372036854775807L - 2L * steps ||
    geometry.steps_wire_bytes > 9223372036854775807L - steps ||
    geometry.ports_wire_bytes > 9223372036854775807L - ports ||
    geometry.max_quoted_text_bytes < 0 ||
    geometry.steps_wire_bytes < 1L ||
    geometry.ports_wire_bytes < 1L ||
    geometry.view.0 < 1 ||
    geometry.map_body.0 < 1 {
    return None
  }
  // steps, stage producers, current ports, and object_field_names Arrays.
  // Each producer is the actual (step_id, output_id) pair. Step/port Map
  // entries and their growth/old backing use the shared collection owner.
  guard @shape.collection_construction_extent({
      records: geometry.max_stage_producers.to_int64(),
      record_references: 2L * geometry.max_stage_producers.to_int64(),
      record_words: 0L,
      reference_arrays: 4L,
      reference_items: steps +
      geometry.max_stage_producers.to_int64() +
      geometry.max_step_ports.to_int64() +
      geometry.max_source_fields.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L,
      map_entries: steps + ports,
    })
    is Some(collections) &&
    @encode.text_writer_construction_inventory(
      Int::max(2, geometry.max_quoted_text_bytes),
      1,
      1,
    )
    is Some(quote) else {
    return None
  }
  // Complete individual port/step wires, quoted operator/name results, the
  // ports.join and steps.join outputs, and current+next concatenation Strings.
  // Count complete endpoints rather than assuming a growing StringBuilder is
  // the same constructor as String concatenation. Source field count is a
  // conservative bound on operator quote results; one binding adds one/step.
  // Additional endpoints: each step's coordinate/key body, each port's
  // locator/key body, bracketed binding-name intermediate/final strings,
  // current+next key/port concatenations, decimal ordinals and inspect Boolean.
  let decimal_count = 2L * steps + 4L * ports
  let string_count = steps +
    ports +
    geometry.source_field_count +
    steps +
    1L +
    1L +
    2L +
    2L +
    2L +
    2L * steps +
    2L * ports +
    2L * steps +
    2L +
    2L +
    2L +
    decimal_count +
    1L

  guard @execution.checked_preparation_add_product(
      geometry.steps_wire_bytes,
      geometry.ports_wire_bytes,
      1L,
    )
    is Some(strings) &&
    @execution.checked_preparation_add_product(
      strings,
      geometry.quoted_text_bytes,
      1L,
    )
    is Some(strings) &&
    @execution.checked_preparation_add_product(
      strings,
      geometry.steps_wire_bytes + steps,
      1L,
    )
    is Some(strings) &&
    @execution.checked_preparation_add_product(
      strings,
      geometry.ports_wire_bytes + ports,
      1L,
    )
    is Some(strings) &&
    @execution.checked_preparation_add_product(
      strings,
      geometry.max_step.0.to_int64(),
      2L,
    )
    is Some(strings) &&
    @execution.checked_preparation_add_product(
      strings,
      geometry.map_body.0.to_int64(),
      2L,
    )
    is Some(strings) &&
    @execution.checked_preparation_add_product(
      strings,
      geometry.view.0.to_int64(),
      2L,
    )
    is Some(strings) &&
    // Coordinate is a subtree of a step key; locator is a subtree of a port.
    @execution.checked_preparation_add_product(
      strings,
      geometry.step_key.0.to_int64(),
      2L * steps,
    )
    is Some(strings) &&
    @execution.checked_preparation_add_product(
      strings,
      geometry.port_key.0.to_int64(),
      ports,
    )
    is Some(strings) &&
    @execution.checked_preparation_add_product(
      strings,
      geometry.ports_wire_bytes,
      1L,
    )
    is Some(strings) &&
    // Both left-associated bracket concatenations retain at most quote+2.
    @execution.checked_preparation_add_product(
      strings,
      geometry.quoted_text_bytes + 2L * steps,
      2L,
    )
    is Some(strings) &&
    @execution.checked_preparation_add_product(
      strings,
      geometry.step_key.0.to_int64(),
      2L,
    )
    is Some(strings) &&
    @execution.checked_preparation_add_product(
      strings,
      geometry.port_key.0.to_int64(),
      2L,
    )
    is Some(strings) &&
    @execution.checked_preparation_add_product(
      strings,
      geometry.max_port.0.to_int64(),
      2L,
    )
    is Some(strings) &&
    // A nonnegative Int ordinal has at most ten decimal units. inspect is
    // exactly one true/false String, at most five units.
    @execution.checked_preparation_add_product(strings, 10L, decimal_count)
    is Some(strings) &&
    @execution.checked_preparation_add_product(strings, 5L, 1L) is Some(strings) else {
    return None
  }
  let originals : @execution.PreparationRepresentationUnits = {
    record_headers: collections.record_headers + string_count,
    reference_slots: collections.reference_slots,
    scalar_words: collections.scalar_words,
    // UTF8 bytes bound UTF16 units for these valid original JSON Strings.
    owned_utf16_units: strings,
    owned_wire_bytes: 0L,
  }
  let quoted : @execution.PreparationRepresentationUnits = {
    record_headers: quote.record_headers,
    reference_slots: quote.reference_slots,
    scalar_words: quote.scalar_words,
    owned_utf16_units: quote.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_representation_cost(originals) is Some(holding) &&
    @execution.preparation_representation_cost(quoted) is Some(quote_cost) else {
    return None
  }
  let mut live = holding
  let mut scratch = quote_cost
  // Conservatively retain every sealed key/Carrier output through projection.
  // The real issuer retires many sooner; no retirement/refill is assumed here.
  // Scratch is the maximum independent codec phase while those owners remain.
  // In particular view.retained covers the FIRST parsed view while view.scratch
  // independently includes the SECOND parse/control validator. The two trees
  // are not treated as a single reused output. Carrier DATA must additionally
  // include its actual schema/Graph/Record branch constructors: a generic
  // same-sized parse/hash layout alone does not establish those obligations.
  for
    (layout, count) in [
      (step_key, steps),
      (port_key, ports),
      (carrier, ports),
      (map, 1L),
      (view, 1L),
    ] {
    guard @execution.preparation_representation_cost(layout.retained)
      is Some(retained) &&
      @execution.preparation_representation_cost(layout.scratch)
      is Some(temporary) &&
      @execution.checked_preparation_add_product(live, retained, count)
      is Some(next) else {
      return None
    }
    live = next
    scratch = Int64::max(scratch, temporary)
  }
  // Only the returned view String escapes this constructor. Everything above
  // is an execution peak, not five durable outputs or a new resource account.
  let returned : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: geometry.view.0.to_int64(),
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_representation_cost(returned) is Some(retained) &&
    @execution.checked_preparation_add_product(live, scratch, 1L)
    is Some(execution) &&
    @execution.checked_preparation_add_product(execution, retained, 1L)
    is Some(execution) else {
    return None
  }
  let max_array_items = Int64::max(
    steps,
    Int64::max(
      geometry.max_stage_producers.to_int64(),
      Int64::max(
        geometry.max_step_ports.to_int64(),
        geometry.max_source_fields.to_int64(),
      ),
    ),
  )
  guard client_static_plan_map_bucket_slots(ports.to_int())
    is Some(port_buckets) &&
    client_static_plan_map_bucket_slots(geometry.step_count)
    is Some(step_buckets) else {
    return None
  }
  let mut refs = 12L + 3L * max_array_items
  let mut buckets = Int64::max(port_buckets, step_buckets)
  let mut units = geometry.view.0.to_int64()
  let mut builder_units = geometry.max_quoted_text_bytes.to_int64()
  let mut wire = 0L
  let mut scalar_items = 0L
  for layout in [step_key, port_key, carrier, map, view] {
    refs = Int64::max(refs, layout.reference_array_slots)
    buckets = Int64::max(buckets, layout.map_bucket_slots)
    units = Int64::max(units, layout.string_utf16_units)
    builder_units = Int64::max(builder_units, layout.builder_utf16_bound)
    wire = Int64::max(wire, layout.wire_bytes)
    scalar_items = Int64::max(scalar_items, layout.scalar_array_items)
  }
  Some({
    retained_cost: retained,
    execution_cost: execution,
    string_utf16_units: units,
    builder_utf16_bound: builder_units,
    wire_bytes: wire,
    reference_array_slots: refs,
    map_bucket_slots: buckets,
    scalar_array_items: scalar_items,
  })
}
