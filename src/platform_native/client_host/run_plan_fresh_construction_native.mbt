///|
// Quote DATA only. The caller has already backed the quote's own fixed
// controls; this does not grant the constructors whose extent it describes.
// Issued keys/maps validate both their body and their complete sealed shape.
fn native_fresh_plan_codec_layout(
  name : String,
  geometry : (Int, Int, Int),
  quoted_name_bytes : Int,
) -> @local.ClientStaticPlanCodecLayout? {
  guard @publication.fresh_static_plan_validation_construction(
      name, true, quoted_name_bytes,
    )
    is Some(complete) else {
    return None
  }
  let body = if name == "plan_view" {
    None
  } else {
    guard @publication.fresh_static_plan_validation_construction(
        name, false, quoted_name_bytes,
      )
      is Some(value) else {
      return None
    }
    Some(value)
  }
  let mut records = complete.owner.record_headers
  let mut references = complete.owner.reference_slots
  let mut words = complete.owner.scalar_words
  let mut units = complete.owned_utf16_units
  let mut wire = complete.owned_wire_bytes
  let mut array_items = Int64::max(
    complete.pending_reference_items,
    complete.unique_reference_items,
  )
  if body is Some(value) {
    records += value.owner.record_headers
    references += value.owner.reference_slots
    words += value.owner.scalar_words
    units += value.owned_utf16_units
    wire += value.owned_wire_bytes
    array_items = Int64::max(
      array_items,
      Int64::max(value.pending_reference_items, value.unique_reference_items),
    )
  }
  @local.client_static_plan_codec_layout(
    geometry,
    {
      record_headers: records,
      reference_slots: references,
      scalar_words: words,
      owned_utf16_units: units,
      owned_wire_bytes: wire,
    },
    units,
    array_items,
    0L,
  )
}

///|
// Componentwise maxima retain each branch's actual constructor demand, not a
// substitute validator or a new allowance. Different ports can supply maxima.
fn native_static_plan_carrier_max(
  a : @host.ClientCarrierMeasurementConstruction,
  b : @host.ClientCarrierMeasurementConstruction,
) -> @host.ClientCarrierMeasurementConstruction {
  {
    value_nodes: Int::max(a.value_nodes, b.value_nodes),
    depth: Int::max(a.depth, b.depth),
    max_contract_nodes: Int::max(a.max_contract_nodes, b.max_contract_nodes),
    graph_nodes: Int::max(a.graph_nodes, b.graph_nodes),
    graph_branch: a.graph_branch || b.graph_branch,
    graph_edges: Int::max(a.graph_edges, b.graph_edges),
    max_graph_keys: Int::max(a.max_graph_keys, b.max_graph_keys),
    max_graph_labels: Int::max(a.max_graph_labels, b.max_graph_labels),
    reference_name_headers: Int64::max(
      a.reference_name_headers,
      b.reference_name_headers,
    ),
    reference_name_utf16: Int64::max(
      a.reference_name_utf16,
      b.reference_name_utf16,
    ),
    max_reference_name_utf16: Int64::max(
      a.max_reference_name_utf16,
      b.max_reference_name_utf16,
    ),
    presence_fields: match (a.presence_fields, b.presence_fields) {
      (Some(x), Some(y)) => Some(Int::max(x, y))
      (Some(x), None) | (None, Some(x)) => Some(x)
      (None, None) => None
    },
  }
}

///|
fn native_funded_static_plan_view(
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  reserve : (Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[String, NativeClientRunJournalIssue] {
  // This reserves the quote/measurement machinery before even its first
  // geometry scan. Measurements below are DATA and never grant themselves.
  match native_prepare_static_plan_measurement(prepared, reserve) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (bytes, nodes, depth) = @host.prepared_client_artifact_limits(prepared)
  let mut carrier = None
  let mut refusal = None
  let geometry = match
    @host.measure_client_compiled_run_static_plan_view(
      compiled,
      prepared,
      bytes,
      nodes,
      depth,
      before_carrier_measurement=Some(original => {
        guard @host.client_carrier_measurement_construction(
            original,
            max_depth=depth,
          )
          is Some(data) &&
          native_static_plan_carrier_measurement_working(data)
          is Some((r, e, raw)) else {
          refusal = Some(CapacityExceeded)
          return false
        }
        match reserve(r, e, raw) {
          Err(issue) => {
            refusal = Some(issue)
            false
          }
          Ok(_) => {
            carrier = Some(
              match carrier {
                None => data
                Some(previous) => native_static_plan_carrier_max(previous, data)
              },
            )
            true
          }
        }
      }),
    ) {
    Ok(value) => value
    Err(_) => return Err(refusal.unwrap_or(UnsupportedPreparation))
  }
  guard carrier is Some(carrier) &&
    native_fresh_plan_codec_layout("logical_step_key", geometry.step_key, 0)
    is Some(step_key) &&
    native_fresh_plan_codec_layout("logical_port_key", geometry.port_key, 0)
    is Some(port_key) &&
    native_fresh_plan_codec_layout(
      "logical_map",
      geometry.map_sealed,
      geometry.max_quoted_text_bytes,
    )
    is Some(map) &&
    native_fresh_plan_codec_layout(
      "plan_view",
      geometry.view,
      geometry.max_quoted_text_bytes,
    )
    is Some(view) &&
    native_static_plan_carrier_codec_layout(carrier, geometry.carrier_contract)
    is Some(carrier_layout) &&
    native_static_plan_projection_working(
      geometry, step_key, port_key, map, view, carrier_layout,
    )
    is Some((retained, execution, raw)) else {
    return Err(CapacityExceeded)
  }
  match reserve(retained, execution, raw) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The same immutable owner issues under its actual selected policy; neither
  // observation of larger DATA nor metadata funding changes that policy.
  @host.client_compiled_run_static_plan_view(
    compiled, prepared, bytes, nodes, depth,
  ).map_err(_ => UnsupportedPreparation)
}
