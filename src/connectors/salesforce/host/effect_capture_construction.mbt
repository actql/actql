///|
/// Historical whole-Catalog recovery retains the original listing, all its
/// selected metadata and the exact observation. The bounded raw inventory is
/// cumulative across responses. It is not S independent full Describe bodies.
fn sf_effect_catalog_recovery_capacity(
  list : @catalog.ListLimits,
  describe : @catalog.DescribeLimits,
  raw_bytes : Int,
  observation_bytes : Int,
  binding_units : Int,
) -> @execution.ExecutionCapacity? {
  if list.max_bytes < 1 ||
    list.max_nodes < 1 ||
    list.max_depth < 1 ||
    list.max_selected < 1 ||
    list.max_resources < list.max_selected ||
    list.max_name_units < 1 ||
    describe.max_bytes < 1 ||
    describe.max_nodes < 1 ||
    describe.max_depth < 1 ||
    describe.max_fields < 1 ||
    describe.max_name_units < 1 ||
    raw_bytes < 1 ||
    observation_bytes < 1 ||
    binding_units < 0 {
    return None
  }
  let b = raw_bytes.to_int64()
  let selected = list.max_selected.to_int64()
  let resources = list.max_resources.to_int64()
  // One refused/current field can precede the complete23-byte field proof.
  let fields = Int64::min(
    selected * describe.max_fields.to_int64(),
    b / 23L + selected,
  )
  let references = Int64::min(b, selected * describe.max_nodes.to_int64())
  guard sf_read_metadata_construction_inventory(fields, references)
    is Some(metadata) &&
    @shape.collection_construction_extent({
      // Listing/selected copies, Sync entries/alternatives, observation and
      // original JS recovery vectors/Binding carriers. Count listed Resource
      // controls too, before the selected-count and observation comparisons.
      records: 24L * (resources + selected) + 32L,
      record_references: 96L * (resources + selected) + 128L,
      record_words: 32L * (resources + selected) + 64L,
      reference_arrays: 16L,
      reference_items: 24L * (resources + selected),
      scalar_arrays: 2L,
      scalar_items: 2L * selected,
      maps: 3L,
      map_entries: 2L * resources + selected,
    })
    is Some(carriers) &&
    sf_initialization_decoded_construction(
      Int::min(raw_bytes, list.max_bytes),
      Int::min(raw_bytes, list.max_nodes),
      list.max_depth,
      true,
    )
    is Some(list_parse) &&
    sf_read_describe_parse_inventory({
      ..describe,
      max_bytes: Int::min(raw_bytes, describe.max_bytes),
      max_nodes: Int::min(raw_bytes, describe.max_nodes),
    })
    is Some(describe_parse) &&
    @encode.text_writer_construction_inventory(
      observation_bytes,
      Int::min(raw_bytes, list.max_nodes),
      Int::max(list.max_depth, 4),
    )
    is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) &&
    @execution.compose_preparation_representation([
      sf_initialization_collection_units(metadata),
      sf_initialization_collection_units(carriers),
      {
        record_headers: 64L + 2L * (3L * fields + references),
        reference_slots: 0L,
        scalar_words: 0L,
        // Raw decoded String families, exact observation/copy and retained
        // base64 evidence. Strings inside metadata copies are borrowed.
        owned_utf16_units: 2L * b +
        3L * observation_bytes.to_int64() +
        4L * ((b + 2L) / 3L) +
        2L * list.max_name_units.to_int64() +
        binding_units.to_int64() +
        8L * 71L * (selected + 1L),
        owned_wire_bytes: b,
      },
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      list_parse,
      describe_parse,
      {
        record_headers: writer.record_headers + hash.record_headers,
        reference_slots: writer.reference_slots + hash.reference_slots,
        scalar_words: writer.scalar_words + hash.scalar_words,
        owned_utf16_units: writer.owned_utf16_units +
        hash.owned_utf16_units +
        observation_bytes.to_int64(),
        owned_wire_bytes: hash.owned_wire_bytes + observation_bytes.to_int64(),
      },
    ])
    is Some(workspace) else {
    return None
  }
  sf_effect_capacity(retained, workspace)
}

///|
/// The original Salesforce driver supplies the same four typed constructor
/// entries consumed by the existing described-record composer. These are
/// implementation quantities only; no member, row, grant or Plan is issued.
pub fn effect_construction_profile(
  body : @catalog.WriteBodyLimits,
  request : @catalog.WriteRequestLimits,
  target : @catalog.TargetObservationLimits,
  response : @catalog.WriteCollectionResponseLimits,
  describe : @catalog.DescribeLimits,
  observation_bytes : Int,
  binding_units : Int,
  fields : Int,
  field_name_units : Int,
  api_units : Int,
  resource_units : Int,
) -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
]? {
  let request_output = body.max_bytes.to_int64() +
    6L * request.max_target_bytes.to_int64() +
    130L
  let target_output = target.max_bytes.to_int64() +
    6L * target.max_identity_bytes.to_int64() +
    130L
  let metadata_output = Int64::min(
    observation_bytes.to_int64(),
    1024L + 6L * (binding_units.to_int64() + resource_units.to_int64()),
  )
  if request_output < 1L ||
    request_output > 2147483647L ||
    target_output < 1L ||
    target_output > 2147483647L ||
    body.max_nodes < 1 ||
    body.max_nodes > 2147483643 ||
    target.max_nodes < 1 ||
    target.max_nodes > 2147483643 ||
    metadata_output < 1L {
    return None
  }
  guard effect_request_construction_capacity(
      body, request, fields, field_name_units, api_units, resource_units,
    )
    is Some(request_capacity) &&
    effect_target_construction_capacity(target, fields) is Some(target_capacity) &&
    effect_response_construction_capacity(
      response,
      target.max_identity_bytes,
      fields,
    )
    is Some(response_capacity) &&
    named_describe_construction_capacity(
      describe, observation_bytes, binding_units, resource_units,
    )
    is Some(metadata_capacity) else {
    return None
  }
  Some([
    (
      request_capacity,
      None,
      Some({
        max_input_bytes: request_output.to_int(),
        max_nodes: body.max_nodes + 4,
        max_depth: Int::max(body.max_depth, 1),
      }),
    ),
    (
      target_capacity,
      None,
      Some({
        max_input_bytes: target_output.to_int(),
        max_nodes: target.max_nodes + 4,
        max_depth: Int::max(target.max_depth, 1),
      }),
    ),
    (
      response_capacity,
      None,
      Some({
        max_input_bytes: response.max_bytes,
        max_nodes: response.max_nodes,
        max_depth: response.max_depth,
      }),
    ),
    (
      metadata_capacity,
      None,
      Some({
        max_input_bytes: metadata_output.to_int(),
        max_nodes: 32,
        max_depth: 4,
      }),
    ),
  ])
}

///|
/// Warm capability/footprint/recovery-wire material and historical request
/// reconstruction are part of the SAME capture occurrence. The original
/// Store object limit bounds each inner recovery wire before this callback;
/// it grants no memory and does not replace the independent raw-byte limit.
/// Fixed, checked-row and Effect-id capacities stay opaque for Core's fold.
pub fn effect_capture_construction_profile(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  preview : @source.ParseLimits,
  list : @catalog.ListLimits,
  describe : @catalog.DescribeLimits,
  observation_bytes : Int,
  raw_bytes : Int,
  recovery_bytes : Int,
  binding_units : Int,
  fields : Int,
  field_name_units : Int,
  api_units : Int,
  resource_units : Int,
  recovery_input_bytes? : Int = -1,
  recovery_source_nodes? : Int? = None,
  recovery_preflight? : Bool = false,
  named_source_geometry? : @source.JsonSourceGeometry? = None,
) -> Array[@execution.ExecutionCapacity]? {
  if recovery_input_bytes < -1 {
    return None
  }
  let warm = recovery_input_bytes == 0
  if recovery_source_nodes is Some(nodes) &&
    (nodes < 1 || recovery_input_bytes < 1) {
    return None
  }
  // This is the original already-owned wire extent, not a replacement codec
  // limit. Every nested JSON spelling and retained base64 body fits inside it.
  let actual = if recovery_input_bytes > 0 {
    recovery_input_bytes
  } else {
    recovery_bytes
  }
  let recovery_bytes = Int::min(recovery_bytes, actual)
  let raw_bytes = Int::min(raw_bytes, actual)
  // In recovery, observationJson is an inner String of the already-owned
  // saved wire. Its decoded spelling cannot exceed that wire's encoded bytes.
  // Preserve the configured codec limit; only this constructor uses the bound.
  let observation_bytes = if recovery_input_bytes > 0 {
    Int::min(observation_bytes, actual)
  } else {
    observation_bytes
  }
  let preview = if recovery_input_bytes > 0 {
    {
      ..preview,
      max_input_bytes: Int::min(preview.max_input_bytes, actual),
      max_nodes: Int::min(preview.max_nodes, actual),
    }
  } else {
    preview
  }
  let zero : @source.JsonLiteralConstructionExtent = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
  }
  guard original is Some(entries) &&
    entries.length() == 4 &&
    recovery_bytes > 0 &&
    fields > 0 &&
    field_name_units > 0 &&
    api_units > 0 &&
    resource_units > 0 &&
    binding_units >= 0 &&
    @catalog.write_capability_construction_limits(preview.max_input_bytes)
    is Some(capability_limits) &&
    // The writer emits only its fixed root/binding and selected field
    // metadata. Each field has at most describe.max_fields reference names.
    // Retain the writer's original byte/depth ceilings and rejection policy.
    @catalog.write_capability_generated_construction_limits(
      capability_limits,
      fields,
      describe.max_fields,
    )
    is Some(capability_limits) &&
    @encode.text_writer_construction_inventory(
      capability_limits.max_input_bytes,
      capability_limits.max_nodes,
      capability_limits.max_depth,
    )
    is Some(capability_writer) &&
    @catalog.write_target_digest_construction_inventory() is Some(target_hash) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(body_hash) &&
    (if warm {
      Some(zero)
    } else {
      @source.json_literal_construction_extent(
        recovery_bytes,
        recovery_source_nodes.unwrap_or(recovery_bytes),
        recovery_source_nodes.unwrap_or(recovery_bytes),
      )
    })
    is Some(recovery_json) &&
    @source.json_literal_construction_extent(
      capability_limits.max_input_bytes,
      capability_limits.max_nodes,
      capability_limits.max_depth,
    )
    is Some(capability_json) &&
    (if warm {
      Some(zero)
    } else {
      @source.json_literal_construction_extent(
        preview.max_input_bytes,
        preview.max_nodes,
        preview.max_depth,
      )
    })
    is Some(preview_json) &&
    (if warm {
      @execution.execution_capacity(0L, 0L)
    } else {
      effect_recovery_preview_construction_capacity(
        preview.max_input_bytes,
        preview.max_nodes,
        preview.max_depth,
      )
    })
    is Some(preview_capacity) &&
    (if warm {
      @execution.execution_capacity(0L, 0L)
    } else {
      guard sf_effect_catalog_recovery_capacity(
          list, describe, raw_bytes, observation_bytes, binding_units,
        )
        is Some(complete) else {
        return None
      }
      // Keep the original full retained allowance on this SAME member. Only
      // private scratch is staged: first the funded outer JSON/binary/Source
      // preflight, then this exact body's complete native Catalog constructor.
      let selected = if recovery_preflight {
        sf_read_describe_preflight_capacity(raw_bytes)
      } else if named_source_geometry is Some(geometry) {
        if geometry.input_bytes > raw_bytes {
          return None
        }
        named_describe_construction_capacity(
          {
            ..describe,
            max_bytes: geometry.input_bytes,
            max_nodes: Int::min(describe.max_nodes, geometry.input_bytes),
          },
          observation_bytes,
          binding_units,
          resource_units,
          source_geometry=Some(geometry),
        )
      } else {
        Some(complete)
      }
      guard selected is Some(selected) else { return None }
      let retained = @execution.execution_capacity_retained_bytes(complete)
      @execution.execution_capacity(
        retained,
        retained +
        @execution.execution_capacity_execution_bytes(selected) -
        @execution.execution_capacity_retained_bytes(selected),
      )
    })
    is Some(catalog_capacity) &&
    @shape.collection_construction_extent({
      // Original CapabilityEvidence/field Map, Host owner/attestation/scope
      // copies and parsed binding; recovery member/index/option/return views.
      records: 40L,
      record_references: 128L,
      record_words: 48L,
      reference_arrays: 16L,
      reference_items: 4L * fields.to_int64() + 32L,
      scalar_arrays: 1L,
      scalar_items: list.max_selected.to_int64(),
      maps: 3L,
      map_entries: fields.to_int64() + 2L * list.max_selected.to_int64(),
    })
    is Some(controls) else {
    return None
  }
  let observation = Int64::min(
    observation_bytes.to_int64(),
    1024L + 6L * (binding_units.to_int64() + resource_units.to_int64()),
  )
  // Base64 characters do not acquire JSON escapes. observationJson is an
  // independently escaped String; names/API/resource remain original DATA.
  let generated_saved_wire = 4096L +
    4L * ((describe.max_bytes.to_int64() + 2L) / 3L) +
    6L *
    (
      observation +
      field_name_units.to_int64() +
      api_units.to_int64() +
      resource_units.to_int64()
    )
  // Warm capture generates this wire from metadata. Cold recovery borrows the
  // original entry.wire inside the same input instead of generating it again.
  let saved_wire = if recovery_input_bytes > 0 {
    Int64::min(generated_saved_wire, actual.to_int64())
  } else {
    generated_saved_wire
  }
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: controls.record_headers + 8L,
    reference_slots: controls.reference_slots,
    scalar_words: controls.scalar_words,
    // Native capability itself is private scratch. Its identity/parsed
    // binding and the original saved wire escape through the common member.
    owned_utf16_units: saved_wire + binding_units.to_int64() + 4L * 71L,
    owned_wire_bytes: 0L,
  }
  let workspace : @execution.PreparationRepresentationUnits = {
    record_headers: recovery_json.record_headers +
    preview_json.record_headers +
    capability_json.record_headers +
    capability_writer.record_headers +
    target_hash.record_headers +
    body_hash.record_headers +
    8L,
    reference_slots: recovery_json.reference_slots +
    preview_json.reference_slots +
    capability_json.reference_slots +
    capability_writer.reference_slots +
    target_hash.reference_slots +
    body_hash.reference_slots,
    scalar_words: recovery_json.scalar_words +
    preview_json.scalar_words +
    capability_json.scalar_words +
    capability_writer.scalar_words +
    target_hash.scalar_words +
    body_hash.scalar_words,
    // Two nested JSON parses (outer profile and observationJson) can
    // coexist. Their total text/forest is bounded by the same wire bytes;
    // the JSON String layer spends at least its decoded inner spelling.
    owned_utf16_units: recovery_json.owned_utf16_units +
    preview_json.owned_utf16_units +
    capability_json.owned_utf16_units +
    capability_writer.owned_utf16_units +
    target_hash.owned_utf16_units +
    body_hash.owned_utf16_units +
    2L * saved_wire +
    4L * 71L,
    owned_wire_bytes: (if warm {
      0L
    } else {
      preview.max_input_bytes.to_int64()
    }) +
    target_hash.owned_wire_bytes +
    body_hash.owned_wire_bytes,
  }
  guard sf_effect_capacity(retained, workspace) is Some(fixed) &&
    @execution.add_execution_capacity(fixed, catalog_capacity) is Some(fixed) &&
    @execution.add_execution_capacity(fixed, preview_capacity) is Some(total) &&
    // recoverCapturedSalesforceSingleRequests completes its member Catalog
    // projections and clears the outer JS Preview tree BEFORE entering the
    // native Preview identity constructor. The parsed member-profile frames
    // have returned too. Their escaped Strings and Catalogs remain retained;
    // they are not private forests which overlap the next native parse.
    // A failed preceding constructor stops here with its complete peak held.
    @execution.execution_capacity(
      @execution.execution_capacity_retained_bytes(total),
      Int64::max(
        @execution.execution_capacity_execution_bytes(fixed) +
        @execution.execution_capacity_retained_bytes(preview_capacity),
        @execution.execution_capacity_retained_bytes(total) +
        @execution.execution_capacity_execution_bytes(preview_capacity) -
        @execution.execution_capacity_retained_bytes(preview_capacity),
      ),
    )
    is Some(fixed) &&
    @shape.collection_construction_extent({
      // Original request/result/CID carriers, request/currents arrays and
      // per-row target identity/footprint entries. Payload stays with the
      // SAME rebuilt request/Catalog; no copy of each full Catalog per row.
      records: 12L,
      record_references: 24L,
      record_words: 8L,
      reference_arrays: 4L,
      reference_items: 8L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(row) &&
    sf_effect_capacity(
      {
        ..sf_initialization_collection_units(row),
        owned_utf16_units: 4L * 71L,
      },
      {
        record_headers: target_hash.record_headers,
        reference_slots: target_hash.reference_slots,
        scalar_words: target_hash.scalar_words,
        owned_utf16_units: target_hash.owned_utf16_units,
        owned_wire_bytes: target_hash.owned_wire_bytes,
      },
    )
    is Some(row) &&
    @execution.execution_capacity(0L, 0L) is Some(effect_id) else {
    return None
  }
  // Core adds its SAME original request constructor, including Host output
  // parsing, to the row quantity before admitting the capture. Effect IDs
  // are borrowed from the common checked member. This provider
  // neither encodes them again nor gives their spelling a second byte rate.
  Some([fixed, row, effect_id])
}

///|
/// Grow the SAME metadata occurrence for its already-owned HTTP response.
/// Actual bytes bound the parser's forest, as in the existing Source reader;
/// field/name/depth policy and all other original constructors stay unchanged.
pub fn effect_metadata_input_construction_profile(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  describe : @catalog.DescribeLimits,
  observation_bytes : Int,
  binding_units : Int,
  resource_units : Int,
  response_bytes : Int,
  source_geometry? : @source.JsonSourceGeometry? = None,
) -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
]? {
  if response_bytes < 0 || response_bytes > describe.max_bytes {
    return None
  }
  guard original is Some(entries) && entries.length() == 4 else { return None }
  let bytes = Int::max(1, response_bytes)
  guard named_describe_construction_capacity(
      {
        ..describe,
        max_bytes: bytes,
        max_nodes: Int::min(describe.max_nodes, bytes),
      },
      observation_bytes,
      binding_units,
      resource_units,
      source_geometry~,
    )
    is Some(capacity) &&
    sf_read_describe_preflight_capacity(describe.max_bytes) is Some(preflight) else {
    return None
  }
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  guard @execution.checked_preparation_add_product(
      retained,
      @execution.execution_capacity_execution_bytes(preflight),
      1L,
    )
    is Some(preflight_peak) &&
    @execution.execution_capacity(
      retained,
      Int64::max(
        @execution.execution_capacity_execution_bytes(capacity),
        preflight_peak,
      ),
    )
    is Some(capacity) else {
    return None
  }
  let (_, input, output) = entries[3]
  let selected = entries.copy()
  selected[3] = (capacity, input, output)
  Some(selected)
}

///|
pub fn effect_target_input_construction_profile(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  target : @catalog.TargetObservationLimits,
  fields : Int,
  response_bytes : Int,
) -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
]? {
  if response_bytes < 0 || response_bytes > target.max_bytes {
    return None
  }
  guard original is Some(entries) &&
    entries.length() == 4 &&
    entries[1].2 is Some(output) else {
    return None
  }
  let bytes = Int::max(1, response_bytes)
  let nodes = Int::min(target.max_nodes, bytes)
  guard effect_target_construction_capacity(
      { ..target, max_bytes: bytes, max_nodes: nodes, },
      fields,
    )
    is Some(capacity) else {
    return None
  }
  let output_bytes = Int64::min(
    output.max_input_bytes.to_int64(),
    bytes.to_int64() + 6L * target.max_identity_bytes.to_int64() + 130L,
  )
  let selected = entries.copy()
  selected[1] = (
    capacity,
    None,
    Some({
      ..output,
      max_input_bytes: output_bytes.to_int(),
      max_nodes: Int::min(output.max_nodes, nodes + 4),
    }),
  )
  Some(selected)
}
