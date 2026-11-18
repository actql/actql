///|
// Two measuring writers remain live in the original Facts measurement. The
// closed structural profile has no recursive expression emission: its typed
// nodes/children are indexed original observations. Root/step/key/meaning/
// predicate/schema/type frames have at most 32 simultaneously retained keys
// and 14 frames. This is not a copy of the policy-sized value tree.
let explanation_capture_measurement_units : @execution.PreparationRepresentationUnits = {
  let writer = @encode.measuring_writer_construction_extent(32, 14).unwrap()
  {
    record_headers: 2L * writer.record_headers,
    reference_slots: 2L * writer.reference_slots,
    scalar_words: 2L * writer.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
// Scope/borrow/returned original tuple; two mutable geometry/failure holders;
// original-operation/field/node observations; two complete mandatory validator
// and codec quotations, checked sums and return carriers. No variable field,
// expression or Source body is hidden in this fixed constructor census.
let explanation_capture_control_bytes : Int64 = {
  let units = static_plan_quote_sum([
    // Same Resource borrower adapter: seven closures + seven-reference body,
    // original borrower/body Some, mapping/Result and lower return carriers.
    static_plan_quote_units(16L, 24L, 12L),
    // Capture scope, original correspondence tuple/Some, current read/extent
    // Options, two geometry/failure cells, internal reservation callback and
    // final original Plan/Facts tuple. No callback authority is exported.
    static_plan_quote_units(24L, 64L, 48L),
    // Two mandatory body/complete validator quotations and ONE shared full
    // parse/emitter/hash/text/sort codec quotation, not a raw byte multiplier.
    static_plan_quote_repeat(static_plan_validator_quote, 2L),
    static_plan_codec_quote,
    // Fields/max/checked arithmetic and the fixed measuring control tariff.
    static_plan_quote_units(20L, 16L, 48L),
    static_plan_compose_quote(2L),
  ])
  @execution.preparation_representation_cost({
    ..units,
    scalar_words: units.scalar_words + units.record_headers,
  }).unwrap()
}

///|
// Precomputed before requests: even dynamic measurement quotation must have
// real backing first. Entry reads this scalar, not a new quotation forest.
let explanation_capture_entry_control_bytes : Int64 = client_static_plan_quote_construction_bytes() +
  explanation_capture_control_bytes +
  original_dispatch_failure_entry_bytes

///|
fn explanation_capture_measurement_bytes(max_bytes : Int) -> Int64? {
  if max_bytes < 1 {
    return None
  }
  // A JOIN emits two original reference names at once. Their rendered text
  // can each reach the existing artifact byte bound. Other schema/predicate
  // names are sequential observations, not accumulated output copies.
  @execution.preparation_representation_cost({
    ..explanation_capture_measurement_units,
    record_headers: explanation_capture_measurement_units.record_headers + 2L,
    owned_utf16_units: 2L * max_bytes.to_int64(),
  })
}

///|
// Facts can have multiple original input/output ports and schema names. Unlike
// the old fresh Plan's one-binding-name profile, their unique-item bound must
// use the complete measured envelope, not the fresh validator's one-item case.
// The same closed generated body+sealed recipes are mandatory; missing profile
// support cannot turn into zero validation funding.
fn explanation_capture_codec_layout(
  geometry : @publication_host.ClientExplanationFactsConstruction,
) -> ClientStaticPlanCodecLayout? {
  let (bytes, nodes, depth) = geometry.complete
  guard bytes >= geometry.body.0 &&
    nodes >= geometry.body.1 &&
    depth >= geometry.body.2 &&
    @publication.cold_static_plan_validation_construction(
      "explanation_facts",
      false,
      nodes,
      bytes.to_int64(),
      bytes,
      nodes,
      depth,
    )
    is Some(body) &&
    @publication.cold_static_plan_validation_construction(
      "explanation_facts",
      true,
      nodes,
      bytes.to_int64(),
      bytes,
      nodes,
      depth,
    )
    is Some(complete) else {
    return None
  }
  client_static_plan_codec_layout(
    geometry.complete,
    {
      record_headers: body.owner.record_headers + complete.owner.record_headers,
      reference_slots: body.owner.reference_slots +
      complete.owner.reference_slots,
      scalar_words: body.owner.scalar_words + complete.owner.scalar_words,
      owned_utf16_units: body.owned_utf16_units + complete.owned_utf16_units,
      owned_wire_bytes: body.owned_wire_bytes + complete.owned_wire_bytes,
    },
    body.owned_utf16_units + complete.owned_utf16_units,
    Int64::max(
      body.pending_reference_items + body.unique_reference_items,
      complete.pending_reference_items + complete.unique_reference_items,
    ),
    0L,
  )
}

///|
// One complete Plan/map/Facts coexistence recipe for both working Request
// pre-admission and adopted Run construction. These extents grant nothing;
// the selected original owner admits them before any projection constructor.
fn explanation_capture_projection_budget(
  geometry : @publication_host.ClientStaticPlanViewConstruction,
  carrier : @publication_host.ClientCarrierMeasurementConstruction,
  facts_geometry : @publication_host.ClientExplanationFactsConstruction,
  controls : Int64,
) -> (Int64, Int64)? {
  guard client_fresh_static_plan_codec_layout(
      "logical_step_key",
      geometry.step_key,
      0,
    )
    is Some(step_key) &&
    client_fresh_static_plan_codec_layout(
      "logical_port_key",
      geometry.port_key,
      0,
    )
    is Some(port_key) &&
    client_fresh_static_plan_codec_layout(
      "logical_map",
      geometry.map_sealed,
      geometry.max_quoted_text_bytes,
    )
    is Some(map) &&
    client_fresh_static_plan_codec_layout(
      "plan_view",
      geometry.view,
      geometry.max_quoted_text_bytes,
    )
    is Some(view) &&
    client_static_plan_carrier_codec_layout(carrier, geometry.carrier_contract)
    is Some(carrier_codec) &&
    client_static_plan_projection_layout(
      geometry, step_key, port_key, map, view, carrier_codec,
    )
    is Some(projection) &&
    explanation_capture_codec_layout(facts_geometry) is Some(facts_codec) &&
    @execution.preparation_representation_cost(view.retained) is Some(view_hold) &&
    @execution.preparation_representation_cost(facts_codec.retained)
    is Some(facts_hold) &&
    @execution.preparation_representation_cost(facts_codec.scratch)
    is Some(facts_scratch) &&
    @execution.preparation_representation_cost({
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: facts_geometry.body.0.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(body_wire) &&
    @execution.checked_preparation_add_product(
      controls,
      projection.retained_cost,
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(retained, view_hold, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(retained, facts_hold, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(retained, facts_scratch, 1L)
    is Some(facts_peak) &&
    @execution.checked_preparation_add_product(facts_peak, body_wire, 1L)
    is Some(facts_peak) &&
    @execution.checked_preparation_add_product(
      controls,
      projection.execution_cost,
      1L,
    )
    is Some(plan_peak) else {
    return None
  }
  Some((retained, Int64::max(plan_peak, facts_peak)))
}
