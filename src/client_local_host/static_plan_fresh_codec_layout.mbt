///|
// Quote DATA only. The caller has already backed the quote's own fixed
// controls; this does not grant the constructors whose extent it describes.
// Issued keys/maps validate both their body and their complete sealed shape.
pub fn client_fresh_static_plan_codec_layout(
  name : String,
  geometry : (Int, Int, Int),
  quoted_name_bytes : Int,
) -> ClientStaticPlanCodecLayout? {
  if name != "logical_step_key" &&
    name != "logical_port_key" &&
    name != "logical_map" &&
    name != "plan_view" {
    return None
  }
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
  client_static_plan_codec_layout(
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
pub fn client_static_plan_carrier_construction_max(
  a : @publication_host.ClientCarrierMeasurementConstruction,
  b : @publication_host.ClientCarrierMeasurementConstruction,
) -> @publication_host.ClientCarrierMeasurementConstruction {
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
