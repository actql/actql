///|
// Arbitrary persisted bytes use their measured extent, never the fresh typed
// issuer's assumptions. The preflight itself is funded before it starts; its
// parser is taken once only after the complete codec recipe is reserved.
fn native_cold_plan_preflight(
  wire : String,
  reserve : (Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[
  (@source.JsonSourcePreflight, (Int, Int, Int)),
  NativeClientRunJournalIssue,
] {
  match native_prepare_static_plan_quote_controls(reserve) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let bytes = match @scalar.admit_utf8_length(wire, 2147483518) {
    Ok(value) if value > 0 => value
    _ => return Err(CustodyLost)
  }
  let control = @source.json_source_preflight_control_extent()
  guard @execution.preparation_representation_cost({
      record_headers: control.record_headers,
      reference_slots: control.reference_slots,
      scalar_words: control.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(cost) else {
    return Err(CapacityExceeded)
  }
  let (header, _, _, _, pointer) = @bootstrap.native_managed_value_layout()
  match
    reserve(
      0L,
      cost,
      header + control.reference_slots * pointer + control.scalar_words * 8L,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // A JSON node consumes at least one input byte. Keep the established depth
  // safety bound; do not infer a larger recursion allowance from wire length.
  let preflight = match
    @source.start_json_source_preflight(
      wire,
      { max_input_bytes: bytes, max_nodes: bytes, max_depth: 64, },
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  while true {
    match @source.advance_json_source_preflight(preflight, 4096) {
      Ok(@source.JsonSourceContinue(..)) => continue
      Ok(@source.JsonSourceReady(g, ..)) =>
        return Ok(
          (
            preflight,
            (
              g.input_bytes,
              Int::max(2, g.node_upper),
              Int::max(1, g.depth_upper),
            ),
          ),
        )
      _ => {
        @source.cancel_json_source_preflight(preflight)
        return Err(CustodyLost)
      }
    }
  } nobreak {
    Err(CustodyLost)
  }
}

///|
fn native_cold_plan_codec(
  name : String,
  g : (Int, Int, Int),
) -> @local.ClientStaticPlanCodecLayout? {
  if name == "compiled_plan" {
    guard @publication.saved_compiled_plan_validation_construction(g.1)
      is Some(v) else {
      return None
    }
    return @local.client_static_plan_codec_layout(
      g,
      {
        record_headers: v.record_headers,
        reference_slots: v.reference_slots,
        scalar_words: v.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      0L,
      Int64::max(g.1.to_int64(), 13L),
      0L,
    )
  }
  guard @publication.cold_static_plan_validation_construction(
      name,
      true,
      g.1,
      g.0.to_int64(),
      g.0,
      g.1,
      g.2,
    )
    is Some(v) else {
    return None
  }
  @local.client_static_plan_codec_layout(
    g,
    {
      record_headers: v.owner.record_headers,
      reference_slots: v.owner.reference_slots,
      scalar_words: v.owner.scalar_words,
      owned_utf16_units: v.owned_utf16_units,
      owned_wire_bytes: v.owned_wire_bytes,
    },
    v.owned_utf16_units,
    Int64::max(v.pending_reference_items, v.unique_reference_items),
    0L,
  )
}

///|
fn native_cold_plan_reserve_codec(
  layout : @local.ClientStaticPlanCodecLayout,
  reserve : (Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard @execution.preparation_representation_cost(layout.retained) is Some(r) &&
    @execution.preparation_representation_cost(layout.scratch) is Some(s) &&
    @execution.checked_preparation_add_product(r, s, 1L) is Some(e) &&
    native_static_plan_variable_raw(
      layout.string_utf16_units,
      layout.builder_utf16_bound,
      layout.wire_bytes,
      layout.reference_array_slots,
      layout.map_bucket_slots,
      layout.scalar_array_items,
    )
    is Some(raw) else {
    return Err(CapacityExceeded)
  }
  reserve(r, e, raw)
}

///|
fn native_cold_plan_parse(
  preflight : @source.JsonSourcePreflight,
  g : (Int, Int, Int),
) -> Result[@canonical.CanonicalValue, NativeClientRunJournalIssue] {
  let parser = match @source.take_json_source_parser(preflight) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  defer @source.cancel_json_parse(parser)
  let parsed = while true {
    match @source.advance_json_parse(parser, 4096) {
      Ok(@source.JsonParseContinue(..)) => continue
      Ok(@source.JsonParseComplete(value, ..)) => break value
      _ => return Err(CustodyLost)
    }
  } nobreak {
    return Err(CustodyLost)
  }
  Ok(@canonical.from_source(parsed.node, g.1, g.2, g.0, data_keys=true)) catch {
    _ => Err(CustodyLost)
  }
}

///|
fn native_cold_compiled_plan(
  wire : String,
  reserve : (Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[@publication.PublicationContract, NativeClientRunJournalIssue] {
  let (preflight, g) = match native_cold_plan_preflight(wire, reserve) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  defer @source.cancel_json_source_preflight(preflight)
  guard native_cold_plan_codec("compiled_plan", g) is Some(layout) else {
    return Err(CapacityExceeded)
  }
  match native_cold_plan_reserve_codec(layout, reserve) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let value = match native_cold_plan_parse(preflight, g) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @publication.admit_saved_compiled_plan_value(wire, value, g.0, g.1, g.2).map_err(_ => {
      CustodyLost
    },
  )
}

///|
fn native_cold_plan_view(
  original : NativeClientRunPlanOriginal,
  reserve : (Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[Unit, NativeClientRunJournalIssue] {
  let (preflight, g) = match
    native_cold_plan_preflight(original.view, reserve) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  defer @source.cancel_json_source_preflight(preflight)
  guard native_cold_plan_codec("plan_view", g) is Some(layout) else {
    return Err(CapacityExceeded)
  }
  match native_cold_plan_reserve_codec(layout, reserve) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let value = match native_cold_plan_parse(preflight, g) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let view = match
    @publication.admit_interactive_run_control_value(
      "plan_view",
      original.view,
      value,
      g.0,
      g.1,
      g.2,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard @canonical.object_field(view, "compiled_plan_cid")
    is Some(@canonical.String(cid)) &&
    cid == @publication.publication_contract_identity(original.plan) &&
    @canonical.object_field(view, "logical_map") is Some(map_value) else {
    return Err(ForeignRun)
  }
  // Map borrows the admitted tree, but owns its canonical wire/identity. The
  // enclosing view geometry is a proved upper bound, including malformed input.
  guard native_cold_plan_codec("logical_map", g) is Some(map_layout) else {
    return Err(CapacityExceeded)
  }
  match native_cold_plan_reserve_codec(map_layout, reserve) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let map = match
    @publication.admit_interactive_run_evidence_value(
      "logical_map",
      map_value,
      g.0,
      g.1,
      g.2,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  match native_cold_plan_binding_working(map, original.plan, g, reserve) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  @publication.check_interactive_logical_map_binding(
    map,
    original.plan,
    g.0,
    g.1,
    g.2,
  ).map_err(_ => ForeignRun)
}

///|
// Binding's maps retain only borrowed identifiers and its own coordinates;
// per-step hash/text and per-port parse/seal constructors are sequential.
fn native_cold_plan_binding_working(
  map : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
  g : (Int, Int, Int),
  reserve : (Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[Unit, NativeClientRunJournalIssue] {
  let (control, references, words) = @publication.interactive_logical_map_binding_scanner_controls()
  guard @execution.preparation_representation_cost({
      record_headers: control.record_headers,
      reference_slots: control.reference_slots,
      scalar_words: control.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(control_cost) else {
    return Err(CapacityExceeded)
  }
  let (header, _, _, _, pointer) = @bootstrap.native_managed_value_layout()
  match
    reserve(
      0L,
      control_cost,
      header + references.to_int64() * pointer + words.to_int64() * 8L,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard @publication.interactive_logical_map_binding_construction(
      map,
      plan,
      g.0,
      g.1,
      g.2,
    )
    is Some(binding) &&
    (if binding.steps == 0 {
      Some(native_cold_absent_key_codec)
    } else {
      native_cold_plan_codec("logical_step_key", binding.step_key)
    })
    is Some(step) &&
    (if binding.ports == 0 {
      Some(native_cold_absent_key_codec)
    } else {
      native_cold_plan_codec("logical_port_key", binding.port_complete)
    })
    is Some(port) &&
    @publication.cold_static_plan_validation_construction(
      "logical_port_key", false, 0, 0L, 0, 0, 0,
    )
    is Some(body) &&
    @execution.compose_preparation_representation([
      {
        record_headers: binding.owner.record_headers,
        reference_slots: binding.owner.reference_slots,
        scalar_words: binding.owner.scalar_words,
        owned_utf16_units: binding.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      {
        record_headers: body.owner.record_headers,
        reference_slots: body.owner.reference_slots,
        scalar_words: body.owner.scalar_words,
        owned_utf16_units: body.owned_utf16_units,
        owned_wire_bytes: body.owned_wire_bytes,
      },
      step.retained,
      step.scratch,
      port.retained,
      port.scratch,
    ])
    is Some(peak) &&
    @execution.preparation_representation_cost(peak) is Some(cost) &&
    @local.client_static_plan_map_bucket_slots(
      Int::max(binding.steps, Int::max(binding.ports, binding.outputs)),
    )
    is Some(buckets) &&
    native_static_plan_variable_raw(
      Int64::max(
        binding.port_body_concat_units,
        Int64::max(step.string_utf16_units, port.string_utf16_units),
      ),
      Int64::max(step.builder_utf16_bound, port.builder_utf16_bound),
      Int64::max(step.wire_bytes, port.wire_bytes),
      Int64::max(step.reference_array_slots, port.reference_array_slots),
      Int64::max(
        buckets,
        Int64::max(step.map_bucket_slots, port.map_bucket_slots),
      ),
      Int64::max(step.scalar_array_items, port.scalar_array_items),
    )
    is Some(raw) else {
    return Err(CapacityExceeded)
  }
  reserve(0L, cost, raw)
}

///|
// No key constructor is invoked for an empty step/port collection. This
// module-retained zero inventory is only that absent branch, never a fallback
// for an unknown validator or failed constructor quote.
let native_cold_absent_key_codec : @local.ClientStaticPlanCodecLayout = {
  retained: {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
  scratch: {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
  string_utf16_units: 0L,
  builder_utf16_bound: 0L,
  wire_bytes: 0L,
  reference_array_slots: 0L,
  scalar_array_items: 0L,
  map_bucket_slots: 0L,
}
