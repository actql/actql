///|
// The original lexical preflight observes the completed canonical wire
// before its actual reader. The member and root widths use upper quantities
// of this SAME input. No second parser or typed Environment is constructed.
fn project_model_environment_wire_geometry(
  wire : String,
) -> @environment.WireAdmissionConstructionGeometry? {
  let limits : @source.ParseLimits = {
    max_input_bytes: 4000000,
    max_nodes: 400000,
    max_depth: 64,
  }
  guard @source.start_json_source_preflight(wire, limits) is Ok(preflight) else {
    return None
  }
  defer @source.cancel_json_source_preflight(preflight)
  guard @source.advance_json_source_preflight(preflight, wire.length() + 1)
    is Ok(JsonSourceReady(shape, ..)) else {
    return None
  }
  Some({
    bytes: shape.input_bytes,
    nodes: shape.node_upper,
    depth: shape.depth_upper,
    fields: shape.fields,
    objects: shape.objects,
    arrays: shape.arrays,
    root_fields: 12,
    max_fields: shape.fields,
    key_utf16_units: shape.quoted_raw_utf16_units,
    max_key_utf16_units: shape.longest_quoted_raw_utf16,
    members: shape.node_upper,
    snapshots: shape.node_upper,
    catalogs: shape.node_upper,
    manifest_entries: shape.node_upper,
  })
}

///|
/// Quote the original bounded reader for the assembled Project body.
pub fn client_project_model_environment_read_inventory(
  body : String,
) -> @execution.PreparationRepresentationUnits? {
  guard project_model_environment_wire_geometry(body) is Some(shape) &&
    @environment.wire_admission_construction_extent(shape) is Some(wire) else {
    return None
  }
  Some({
    record_headers: wire.record_headers,
    reference_slots: wire.reference_slots,
    scalar_words: wire.scalar_words,
    owned_utf16_units: wire.owned_utf16_units,
    owned_wire_bytes: wire.owned_wire_bytes,
  })
}

///|
/// Quote the existing Common Task projector over the already-read wire.
/// The selected Task materials stay borrowed.
pub fn client_project_model_environment_projection_inventory(
  wire : @environment.WireEnvironment,
  tasks : Array[@environment.NormalizedPublicModelTask],
) -> (@environment.ModelTaskLimits, @execution.PreparationRepresentationUnits)? {
  let (_, _, members) = @environment.usage(wire)
  let (bytes, nodes, depth) = @environment.emission_geometry(wire)
  let count = @environment.member_count(wire, ModelTaskContracts)
  guard @environment.public_model_task_environment_limits(
      bytes, nodes, depth, members, count, tasks,
    )
    is Some(limits) &&
    limits.bodies.max_bytes <= 4000000 &&
    limits.bodies.max_nodes <= 400000 &&
    @environment.public_model_task_environment_construction_extent(
      bytes, nodes, depth, members, count, tasks,
    )
    is Some(projection) else {
    return None
  }
  Some(
    (
      limits,
      {
        record_headers: projection.record_headers,
        reference_slots: projection.reference_slots,
        scalar_words: projection.scalar_words,
        owned_utf16_units: projection.owned_utf16_units,
        owned_wire_bytes: projection.owned_wire_bytes,
      },
    ),
  )
}
