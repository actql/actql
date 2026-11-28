///|
// Measured lexical geometry of the retained Project and Relation wires. The
// environment writer's existing 4M/400k/64 profile remains independent.
priv struct MockCheckGeometry {
  mut bytes : Int64
  mut nodes : Int64
  mut bodies : Int64
  mut largest_original_text : Int
}

///|
fn MockCheckGeometry::include_wire(self : Self, wire : String) -> Bool {
  guard client_project_admission_geometry(wire, 4000000, max_nodes=400000)
    is Some((bytes, nodes, _)) else {
    return false
  }
  self.bytes += bytes.to_int64()
  self.nodes += nodes.to_int64()
  self.bodies += 1L
  self.largest_original_text = Int::max(
    self.largest_original_text,
    wire.length(),
  )
  true
}

///|
// Fund the original bounded literal parser, canonical forest and writer,
// including the branch which refuses after constructing its partial tree.
fn mock_check_codec_inventory(
  bytes : Int,
  nodes : Int,
  bodies : Int64,
  passes : Int64,
  normalization_text? : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard @source.json_literal_construction_extent(bytes, nodes, 64)
    is Some(literal) &&
    @canonical.source_conversion_construction_extent(
      nodes,
      nodes,
      nodes,
      nodes,
      64,
      normalization_text.unwrap_or(bytes),
    )
    is Some(canonical) &&
    @canonical_value.nfc_lf_retained_output_units(bytes.to_int64())
    is Some(canonical_text) &&
    @encode.text_writer_construction_inventory(bytes, nodes, 64) is Some(writer) &&
    @encode.text_writer_construction_inventory(0, 1, 64) is Some(control) else {
    return None
  }
  // Each duplicate check can keep its encoded body until the final writer.
  // Per-body containers/writer frames and UTF-8/hash copies accompany the
  // aggregate literal/canonical geometry, including discarded members.
  let n = nodes.to_int64()
  let fixed = bodies + 1L
  Some({
    record_headers: passes *
    (
      literal.record_headers +
      canonical.retained.record_headers +
      canonical.scratch.record_headers +
      writer.record_headers +
      control.record_headers * fixed +
      12L * n +
      48L * fixed
    ),
    reference_slots: passes *
    (
      literal.reference_slots +
      canonical.retained.reference_slots +
      canonical.scratch.reference_slots +
      writer.reference_slots +
      control.reference_slots * fixed +
      28L * n +
      128L * fixed
    ),
    scalar_words: passes *
    (
      literal.scalar_words +
      canonical.retained.scalar_words +
      canonical.scratch.scalar_words +
      writer.scalar_words +
      control.scalar_words * fixed +
      12L * n +
      256L * fixed
    ),
    owned_utf16_units: passes *
    (
      literal.owned_utf16_units +
      canonical_text +
      canonical.scratch_utf16_units +
      writer.owned_utf16_units +
      control.owned_utf16_units * fixed +
      96L * n +
      128L * fixed
    ),
    owned_wire_bytes: passes * (bytes.to_int64() + 128L * fixed),
  })
}

///|
/// Constructor demand for the existing Mock environment assembly and its
/// audience-visible read aliases. The caller owns these exact input strings,
/// provides no extra File capabilities or lookup policy, and pays for final
/// Checker admission separately using the actual returned wire.
pub fn[T] mock_project_check_assembly_inventory(
  base : @checked.CheckEnvironment,
  sources : Array[T],
  declaration : (T) -> @row_host.RowDeclaration,
  entry : (T) -> String,
  write_bodies : (T) -> Iter[String],
) -> @execution.PreparationRepresentationUnits? {
  project_check_assembly_inventory(
    base, sources, declaration, entry, write_bodies, false,
  )
}

///|
fn local_file_check_assembly_inventory(
  base : @checked.CheckEnvironment,
  catalogs : Array[ClientProjectLocalFileCatalog],
) -> @execution.PreparationRepresentationUnits? {
  project_check_assembly_inventory(
    base,
    catalogs,
    catalog => catalog.declaration,
    _ => "{}",
    _ => Iter::empty(),
    true,
  )
}

///|
fn[T] project_check_assembly_inventory(
  base : @checked.CheckEnvironment,
  sources : Array[T],
  declaration : (T) -> @row_host.RowDeclaration,
  entry : (T) -> String,
  write_bodies : (T) -> Iter[String],
  original_text_only : Bool,
) -> @execution.PreparationRepresentationUnits? {
  let (base_bytes, base_nodes, _) = @environment.emission_geometry(
    @checked.checking_environment_wire(base),
  )
  let geometry : MockCheckGeometry = {
    bytes: base_bytes.to_int64(),
    nodes: base_nodes.to_int64(),
    bodies: 1L,
    // Static keys, literals and the newly issued SHA-256 CID.
    largest_original_text: Int::max(71, base_bytes),
  }
  for source in sources {
    let original = declaration(source)
    if !geometry.include_wire(entry(source)) ||
      !geometry.include_wire(original.catalog) ||
      !geometry.include_wire(original.manifest_entry) {
      return None
    }
    if @row_host.local_file_store_declaration_wires(original)
      is Some((command, _, _)) &&
      !geometry.include_wire(command) {
      return None
    }
    for wires in [original.contracts, original.view_bodies] {
      for wire in wires {
        if !geometry.include_wire(wire) {
          return None
        }
      }
    }
    for mapping in write_bodies(source) {
      if !geometry.include_wire(mapping) {
        return None
      }
      // The private audience context also borrows this Mapping's SHA256 CID.
      geometry.bytes += 74L
      geometry.nodes += 1L
    }
    // The two original Row Evidence member constructors have their own
    // 4096-byte/64-node writers. The generated members coexist with both
    // Canonical inputs. Alias bodies borrow the same declaration strings.
    let views = original.views.length().to_int64()
    geometry.bytes += (2L * 4096L + 512L) * views
    geometry.nodes += (2L * 64L + 16L) * views
    geometry.bodies += 2L * views
    if original_text_only {
      for view in original.views {
        for
          text in [
            view.source_ref,
            view.classification,
            view.view_cid,
            view.carrier_schema_cid,
            view.data_policy_cid,
          ] {
          geometry.largest_original_text = Int::max(
            geometry.largest_original_text,
            text.length(),
          )
        }
      }
    }
  }
  // An assembled JSON body emits actual input strings within their original
  // escaped size and adds a fixed wrapper. The alias projection includes
  // fresh keys, three references per entry and any rejected unknown key.
  let bytes = 6L * geometry.bytes + 128L * geometry.nodes + 1024L
  let nodes = geometry.nodes * 3L + 128L
  if bytes > 2147483647L || nodes > 2147483647L {
    return None
  }
  // Base emission/parse, individual member canonicalize, environment
  // preimage/final and publication are separately covered.
  // Local inserts only original members and fixed evidence fields. Neither
  // normalization of one scalar nor its transient arrays escape that
  // constructor. Keep every returned scalar and all forest/writer bounds.
  let normalization_text = if original_text_only {
    geometry.largest_original_text
  } else {
    bytes.to_int()
  }
  mock_check_codec_inventory(
    bytes.to_int(),
    nodes.to_int(),
    geometry.bodies * 3L,
    3L,
    normalization_text~,
  )
}

///|
/// The aliases borrow view names and CIDs, but the publication encoder may
/// repeat those references for every authored alias. Fund that owned text
/// before projection. The original entry quote separately covers its names,
/// input objects, and rejected unknown fields.
pub fn mock_project_check_alias_reference_inventory(
  entry : Json,
  declaration : @row_host.RowDeclaration,
) -> @execution.PreparationRepresentationUnits? {
  guard entry is Object(object) &&
    object.get("query_aliases") is Some(Array(aliases)) else {
    return None
  }
  let mut longest = 0
  for view in declaration.views {
    guard @scalar.admit_utf8_length(view.source_ref, 4096) is Ok(bytes) else {
      return None
    }
    longest = Int::max(longest, bytes)
  }
  // Escape each reference independently and include both original CIDs.
  // Only two final text buffers coexist here: the canonical writer's
  // construction and its hash input. Other key/shape backing is admitted
  // with the aggregate environment and authored input.
  let bytes = (6L * longest.to_int64() + 142L) * aliases.length().to_int64()
  if bytes > 2147483647L {
    return None
  }
  guard @encode.text_writer_construction_inventory(bytes.to_int(), 1, 0)
    is Some(writer) else {
    return None
  }
  Some({
    record_headers: 2L * writer.record_headers,
    reference_slots: 2L * writer.reference_slots,
    scalar_words: 2L * writer.scalar_words,
    owned_utf16_units: 2L * writer.owned_utf16_units,
    owned_wire_bytes: bytes,
  })
}

///|
// The original lexical preflight observes the completed canonical wire
// before its actual reader. The member and root widths use upper quantities
// of this SAME input. No second parser or typed Environment is constructed.
fn mock_check_wire_geometry(
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
pub fn mock_project_check_wire_read_inventory(
  body : String,
) -> @execution.PreparationRepresentationUnits? {
  guard mock_check_wire_geometry(body) is Some(shape) &&
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
pub fn mock_project_check_model_projection_inventory(
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

///|
/// Use the original wire-admission inventory and the exact returned
/// publication. The two representations coexist through the Checker.
pub fn mock_project_check_admission_inventory(
  environment : String,
  publication : String,
) -> @execution.PreparationRepresentationUnits? {
  guard mock_check_wire_geometry(environment) is Some(shape) &&
    @environment.wire_admission_construction_extent(shape) is Some(checked) &&
    client_project_admission_geometry(publication, 4000000, max_nodes=400000)
    is Some((pbytes, pnodes, _)) &&
    @decode.preserving_json_admission_construction_inventory(pbytes, pnodes, 64)
    is Some(pub_reader) &&
    mock_check_codec_inventory(pbytes, pnodes, pnodes.to_int64(), 2L)
    is Some(declared) else {
    return None
  }
  let wrapper = client_check_environment_wrapper_construction_extent(true)
  @execution.compose_preparation_representation([
    declared,
    {
      record_headers: checked.record_headers +
      pub_reader.record_headers +
      wrapper.record_headers +
      64L,
      reference_slots: checked.reference_slots +
      pub_reader.reference_slots +
      wrapper.reference_slots +
      128L,
      scalar_words: checked.scalar_words +
      pub_reader.scalar_words +
      wrapper.scalar_words +
      128L,
      owned_utf16_units: checked.owned_utf16_units +
      pub_reader.owned_utf16_units,
      owned_wire_bytes: checked.owned_wire_bytes + pbytes.to_int64(),
    },
  ])
}

///|
/// Only the successfully returned WireEnvironment index, empty ModelTask
/// wrapper, and the publication and context strings survive construction.
pub fn mock_project_check_retained_inventory(
  environment : @checked.CheckEnvironment,
  body : String,
  publication : String,
  task_inventory? : @environment.RegistryConstructionExtent? = None,
) -> @execution.PreparationRepresentationUnits? {
  let wire = @checked.checking_environment_wire(environment)
  let tasks = match task_inventory {
    Some(_) => task_inventory
    None => @environment.empty_model_tasks_retained_extent(wire)
  }
  guard mock_check_wire_geometry(body) is Some(shape) &&
    @environment.wire_admission_retained_extent(shape) is Some(index) &&
    tasks is Some(tasks) else {
    return None
  }
  let wrapper = client_check_environment_wrapper_construction_extent(false)
  Some({
    record_headers: index.record_headers +
    tasks.record_headers +
    wrapper.record_headers +
    8L,
    reference_slots: index.reference_slots +
    tasks.reference_slots +
    wrapper.reference_slots +
    16L,
    scalar_words: index.scalar_words +
    tasks.scalar_words +
    wrapper.scalar_words +
    8L,
    owned_utf16_units: index.owned_utf16_units +
    publication.length().to_int64() +
    71L,
    owned_wire_bytes: index.owned_wire_bytes,
  })
}

///|
/// Quote one actual selected Source's write publication. File identity hashes
/// the complete authored Catalog and physical locator. The ordered Mapping
/// identities and publication borrow existing names; their decoded target
/// refs, CIDs and final alias wire still need backing. The current scope
/// writer has its own existing 8192-byte limit.
pub fn mock_project_check_update_alias_inventory(
  catalog : String,
  data_path : String,
  connection : String,
  provider : String,
  declaration : @row_host.RowDeclaration,
  writes : Array[@row_host.ProjectMockWriteDeclaration],
) -> @execution.PreparationRepresentationUnits? {
  let geometry : MockCheckGeometry = {
    bytes: 0L,
    nodes: 0L,
    bodies: 0L,
    largest_original_text: 0,
  }
  let mut aliases = 0L
  for write in writes {
    if !geometry.include_wire(write.mapping.body) {
      return None
    }
    aliases += write.aliases.length().to_int64()
  }
  // Catalog and path are strings of one closed preimage. They never enter
  // the generic JSON reader, key normalizer or target installation writer.
  let source_units = catalog.length().to_int64() +
    data_path.length().to_int64() +
    connection.length().to_int64() +
    provider.length().to_int64()
  let count = writes.length().to_int64()
  let source_bytes = Int64::min(4000000L, 128L + 6L * source_units).to_int()
  let binding_bytes = Int64::min(4000000L, 256L + 74L * count).to_int()
  let installation_bytes = Int64::min(
    65536L,
    2048L +
    36L *
    (
      connection.length().to_int64() +
      declaration.connector_registration.length().to_int64() +
      declaration.connector_version.length().to_int64()
    ),
  ).to_int()
  guard count < 400000L &&
    geometry.bytes <= 2147483647L &&
    geometry.nodes < 2147483647L &&
    @encode.text_writer_construction_inventory(source_bytes, 5, 2)
    is Some(scope) &&
    @encode.text_writer_construction_inventory(
      binding_bytes,
      count.to_int() + 5,
      3,
    )
    is Some(binding) &&
    @encode.text_writer_construction_inventory(8192, 64, 4) is Some(authority) &&
    mock_check_codec_inventory(installation_bytes, 16, 1L, 2L)
    is Some(installation) &&
    mock_check_codec_inventory(
      geometry.bytes.to_int(),
      geometry.nodes.to_int() + 1,
      geometry.bodies,
      1L,
    )
    is Some(mapping_read) else {
    return None
  }
  // Alias entries borrow their admitted names and target/installation stamps.
  // Include the array growth, digest states, and the original refusal controls
  // separately from the publication writer that later consumes this forest.
  @execution.compose_preparation_representation([
    installation,
    mapping_read,
    {
      record_headers: scope.record_headers +
      binding.record_headers +
      authority.record_headers +
      64L * aliases +
      96L,
      reference_slots: scope.reference_slots +
      binding.reference_slots +
      authority.reference_slots +
      128L * aliases +
      128L,
      scalar_words: scope.scalar_words +
      binding.scalar_words +
      authority.scalar_words +
      96L * aliases +
      192L,
      owned_utf16_units: scope.owned_utf16_units +
      binding.owned_utf16_units +
      authority.owned_utf16_units +
      4L * 71L +
      512L,
      owned_wire_bytes: source_bytes.to_int64() +
      binding_bytes.to_int64() +
      8192L +
      1024L,
    },
  ])
}
