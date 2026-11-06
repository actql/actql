///|
// Original Salesforce body/request constructors. Shared Owners supply parser,
// decoder, writer, collection, normalization and representation quantities;
// this module describes only the closed calls and returned material above
// those Owners. It does not select policy, admit a Run or issue a grant.
fn sf_effect_capacity(
  retained : @execution.PreparationRepresentationUnits,
  workspace : @execution.PreparationRepresentationUnits,
) -> @execution.ExecutionCapacity? {
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// The installing salesforceWriteDriver closure, its returned original method
/// view and the initializer's one result holder. Installed Mapping/Catalog,
/// Site, namespace functions and limits are borrowed from this SAME parent.
/// This does not fund later per-Run callbacks or infer a managed recipe.
pub fn effect_driver_construction_capacity() -> @execution.ExecutionCapacity? {
  guard @shape.collection_construction_extent({
      // Six private helpers, twelve original method closures, plus installing
      // mapping/occurrence callbacks. Include each closure's captured view;
      // shared engine environment representation is conservatively co-held.
      // Three closed kind recipes: eight returned capacities, nine possible
      // typed operation extents, seven credential selections, nine JS
      // operation entries, root/selectors and their original typed carriers.
      // Staging keeps both initial/maximum capacity sets, eight extra extent
      // alternatives/four Some maxima, and four original callback/context
      // pairs per kind. Six added captured native methods share one owner.
      // The current-body projector adds the same 2H14R original-method view.
      records: 2L * 26L + 3L + 3L * (24L + 17L + 7L + 9L + 3L + 16L + 4L + 8L),
      record_references: 26L * 14L +
      19L +
      3L * (17L * 8L + 7L * 3L + 9L * 2L + 48L + 4L + 4L * 14L),
      record_words: 1L + 3L * (24L * 2L + 17L * 4L + 7L * 3L + 32L + 4L),
      // The three original immutable kind labels borrow module Strings.
      reference_arrays: 4L + 3L * 9L,
      reference_items: 3L + 22L + 8L + 6L + 3L * (24L + 4L + 5L + 7L + 4L + 24L),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(owned) else {
    return None
  }
  sf_initialization_capacity([sf_initialization_collection_units(owned)])
}

///|
/// Recovery keeps this connector bundle's original Preview identity through
/// request reconstruction, then returns only the requests and Catalogs. The
/// complete identity constructor is therefore private capture workspace, not
/// another permanently retained Preview or an allowance inferred from rows.
pub fn effect_recovery_preview_construction_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  guard @publication.effect_preview_identity_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(peak) else {
    return None
  }
  sf_effect_capacity(
    {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    {
      record_headers: peak.record_headers,
      reference_slots: peak.reference_slots,
      scalar_words: peak.scalar_words,
      owned_utf16_units: peak.owned_utf16_units,
      owned_wire_bytes: peak.owned_wire_bytes,
    },
  )
}

///|
/// prepare_write_projection -> prepare_execution_write_body -> original
/// SingleWriteRequest/CID and target JSON export. Body DATA stays preserving;
/// only the existing external-ID URI owner performs its original NFC step.
/// Input String/Bytes, Host JSON output, HTTP and recovery are composed by the
/// same checked implementation recipe, never inferred from these quantities.
pub fn effect_request_construction_capacity(
  body : @catalog.WriteBodyLimits,
  request : @catalog.WriteRequestLimits,
  fields : Int,
  field_name_units : Int,
  api_units : Int,
  resource_units : Int,
) -> @execution.ExecutionCapacity? {
  if body.max_bytes < 1 ||
    body.max_nodes < 1 ||
    body.max_depth < 1 ||
    request.max_path_bytes < 1 ||
    request.max_target_bytes < 1 ||
    request.max_body_bytes < 1 ||
    fields < 1 ||
    field_name_units < 1 ||
    api_units < 1 ||
    resource_units < 1 {
    return None
  }
  let b = body.max_bytes.to_int64()
  let n = Int::min(body.max_bytes, body.max_nodes)
  let f = fields.to_int64()
  let t = request.max_target_bytes.to_int64()
  guard sf_initialization_decoded_construction(
      body.max_bytes,
      n,
      body.max_depth,
      false,
    )
    is Some(parsed) &&
    @encode.text_writer_construction_inventory(
      body.max_bytes,
      n,
      body.max_depth,
    )
    is Some(writer) &&
    @encode.hash_writer_construction_inventory(16, 2) is Some(hash) &&
    // The existing NFC+LF inventory contains every original NFC URI phase.
    // LF is unused here; this is an upper constructor envelope, not another
    // transformation of the target or of any body DATA.
    @canonical.nfc_lf_construction_extent(request.max_target_bytes) is Some(uri) else {
    return None
  }
  // The prefix is constructed BEFORE the final path-byte refusal. Do not
  // replace its original immutable API/resource lengths by max_path_bytes.
  let prefix = "/services/data//sobjects//".length().to_int64() +
    api_units.to_int64() +
    resource_units.to_int64()
  let suffix = field_name_units.to_int64() + 1L + t
  let path = prefix + suffix
  let target_json = 6L * t + 2L
  let child = @decode.indexed_child_construction_extent()
  guard @shape.collection_construction_extent({
      // Binding, WriteProjection, external Some, WriteBody, request, target
      // alternative, and the bounded request-CID/target export carriers.
      records: 8L,
      record_references: 32L,
      record_words: 16L,
      // fieldsOf input, Native field names/selection, and returned copy.
      // Their field metadata and String payloads borrow the original Catalog.
      reference_arrays: 4L,
      reference_items: 4L * f,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(output) &&
    @shape.collection_construction_extent({
      // Current lookup/cell/array item, Date/Decimal conversion, and typed
      // refusal alternatives. These close before the next field is emitted.
      records: 16L + 8L * child.record_headers,
      record_references: 24L + 8L * child.reference_slots,
      record_words: 32L + 8L * child.scalar_words,
      // Object-name vector, sorted field copy, active writer pair, and
      // multipicklist scalar traversal. No F independent full input copies.
      reference_arrays: 4L,
      reference_items: n.to_int64() + f + 4L,
      scalar_arrays: 1L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  sf_effect_capacity(
    {
      record_headers: output.record_headers + 5L,
      reference_slots: output.reference_slots,
      scalar_words: output.scalar_words,
      // Both original body spellings, final path, target JSON and request CID.
      owned_utf16_units: 2L * b + path + target_json + 71L,
      owned_wire_bytes: 0L,
    },
    {
      record_headers: parsed.record_headers +
      2L * writer.record_headers +
      hash.record_headers +
      uri.record_headers +
      controls.record_headers,
      reference_slots: parsed.reference_slots +
      2L * writer.reference_slots +
      hash.reference_slots +
      uri.reference_slots +
      controls.reference_slots,
      scalar_words: parsed.scalar_words +
      2L * writer.scalar_words +
      hash.scalar_words +
      uri.scalar_words +
      controls.scalar_words,
      // Writers include their returned B units; those SAME two results are
      // retained above. Preserve old/new concat and encoded URI/target export
      // alternatives, decoded input and the closed numeric/date spellings.
      owned_utf16_units: parsed.owned_utf16_units +
      b +
      2L * (writer.owned_utf16_units - b) +
      hash.owned_utf16_units +
      uri.owned_utf16_units +
      2L * prefix +
      2L * suffix +
      2L * target_json +
      128L,
      owned_wire_bytes: hash.owned_wire_bytes + t,
    },
  )
}

///|
/// ONE target response followed by its original Preview-row projection.
/// The physical response Bytes and original request/Catalog are borrowed.
/// This inventory keeps their returned observation/row, original before wire
/// and all target identity digests; HTTP/credential/Host parsing is composed
/// by the existing Plan recipe, not granted by this constructor quantity.
pub fn effect_target_construction_capacity(
  limits : @catalog.TargetObservationLimits,
  fields : Int,
) -> @execution.ExecutionCapacity? {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_identity_bytes < 1 ||
    fields < 1 {
    return None
  }
  let nodes = Int::min(limits.max_bytes, limits.max_nodes)
  let b = limits.max_bytes.to_int64()
  let identity = limits.max_identity_bytes.to_int64()
  guard sf_initialization_decoded_construction(
      limits.max_bytes,
      nodes,
      limits.max_depth,
      false,
    )
    is Some(parsed) &&
    @encode.text_writer_construction_inventory(
      limits.max_bytes,
      nodes,
      limits.max_depth,
    )
    is Some(before) &&
    @encode.text_writer_construction_inventory(limits.max_identity_bytes, 2, 1)
    is Some(target) &&
    @encode.hash_writer_construction_inventory(64, 2) is Some(digest) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(physical_digest) else {
    return None
  }
  let child = @decode.indexed_child_construction_extent()
  guard @shape.collection_construction_extent({
      // TargetObservation(9R), TargetPreviewRow(5R), expected/observed and
      // later Preview target identities(3R each), plus the original returned
      // bridge field vector and observed-target/Result alternatives.
      records: 10L,
      record_references: 32L,
      record_words: 8L,
      reference_arrays: 1L,
      reference_items: 5L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(output) &&
    @shape.collection_construction_extent({
      // Current field/Id/external target lookups, emit_write_cell conversion
      // and typed refusal carriers. Ordered fields borrow Catalog metadata;
      // current decoded array traversal cannot exceed original JSON nodes.
      records: 16L + 8L * child.record_headers,
      record_references: 24L + 8L * child.reference_slots,
      record_words: 32L + 8L * child.scalar_words,
      reference_arrays: 5L,
      reference_items: nodes.to_int64() + fields.to_int64() + 16L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  sf_effect_capacity(
    {
      record_headers: output.record_headers + 13L,
      reference_slots: output.reference_slots,
      scalar_words: output.scalar_words,
      // Two expected/observed triples, one version digest and the later
      // Preview target triple. Source path/body/Catalog and after/changes
      // borrow the SAME request; do not charge independent copies of them.
      owned_utf16_units: b + identity + 10L * 71L + 64L,
      owned_wire_bytes: 0L,
    },
    {
      record_headers: parsed.record_headers +
      before.record_headers +
      target.record_headers +
      digest.record_headers +
      physical_digest.record_headers +
      controls.record_headers,
      reference_slots: parsed.reference_slots +
      before.reference_slots +
      target.reference_slots +
      digest.reference_slots +
      physical_digest.reference_slots +
      controls.reference_slots,
      scalar_words: parsed.scalar_words +
      before.scalar_words +
      target.scalar_words +
      digest.scalar_words +
      physical_digest.scalar_words +
      controls.scalar_words,
      // Include decoded input, both writers' scratch and scalar conversion.
      // Each writer's SAME returned wire is already retained above. Digest
      // writers run serially; one complete hash scratch bounds all ten calls.
      owned_utf16_units: parsed.owned_utf16_units +
      b +
      (before.owned_utf16_units - b) +
      (target.owned_utf16_units - identity) +
      digest.owned_utf16_units +
      physical_digest.owned_utf16_units +
      128L,
      owned_wire_bytes: digest.owned_wire_bytes +
      physical_digest.owned_wire_bytes,
    },
  )
}

///|
/// Original single-record success/rejection classification, typed outcome
/// writer, and the subsequent data-key Preview-row/outcome correspondence.
/// Unknown/unclassified replies retain the physical observation in its old
/// owner; this quantity neither classifies one nor acknowledges its cleanup.
pub fn effect_response_construction_capacity(
  limits : @catalog.WriteCollectionResponseLimits,
  identity_bytes : Int,
  fields : Int,
) -> @execution.ExecutionCapacity? {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    identity_bytes < 1 ||
    fields < 1 {
    return None
  }
  let nodes = Int::min(limits.max_bytes, limits.max_nodes)
  let n = nodes.to_int64()
  let b = limits.max_bytes.to_int64()
  guard sf_initialization_decoded_construction(
      limits.max_bytes,
      nodes,
      limits.max_depth,
      false,
    )
    is Some(response) &&
    // check_effect_preview_row_outcome reparses the emitted outcome with
    // data_keys=true, converts it to CanonicalValue and re-emits it before
    // validating the existing closed shape. Preserve both original forests
    // and the complete failed prefix; this is not a normalizing DATA parser.
    sf_initialization_forest(n) is Some(canonical) &&
    sf_initialization_decoded_construction(identity_bytes, 64, 8, false)
    is Some(target) &&
    @encode.text_writer_construction_inventory(
      limits.max_bytes,
      nodes,
      limits.max_depth,
    )
    is Some(writer) &&
    @encode.hash_writer_construction_inventory(64, 2) is Some(digest) &&
    @shape.collection_construction_extent({
      // WriteSingleResponse, row/rejection/Some alternatives, returned
      // projection and error records. Each error/field consumed distinct
      // response nodes; never errors*independently-full max_nodes vectors.
      records: 8L + n,
      record_references: 16L + 3L * n,
      record_words: 8L + n,
      reference_arrays: 2L + n,
      reference_items: 2L * n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(output) &&
    @shape.collection_construction_extent({
      // Current error and published-field selection; validation cursors,
      // sorted canonical field tuples and failed typed alternatives. The
      // declared-field vector borrows the original immutable projection.
      records: 32L + 8L * n,
      record_references: 48L + 8L * n,
      record_words: 48L + 8L * n,
      reference_arrays: 6L,
      reference_items: 3L * n + 2L * fields.to_int64() + 1L,
      scalar_arrays: 1L,
      scalar_items: limits.max_depth.to_int64() + 1L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  sf_effect_capacity(
    {
      record_headers: output.record_headers + n + 12L,
      reference_slots: output.reference_slots,
      scalar_words: output.scalar_words,
      // Actual published error code/field Strings borrow the decoded
      // response's cumulative B units. Private messages are not published.
      // Outcome wire, response SHA, request/row target digests remain owned.
      owned_utf16_units: 2L * b + 64L + 8L * 71L,
      owned_wire_bytes: 0L,
    },
    {
      record_headers: 2L * response.record_headers +
      canonical.record_headers +
      target.record_headers +
      2L * writer.record_headers +
      digest.record_headers +
      controls.record_headers,
      reference_slots: 2L * response.reference_slots +
      canonical.reference_slots +
      target.reference_slots +
      2L * writer.reference_slots +
      digest.reference_slots +
      controls.reference_slots,
      scalar_words: 2L * response.scalar_words +
      canonical.scalar_words +
      target.scalar_words +
      2L * writer.scalar_words +
      digest.scalar_words +
      controls.scalar_words,
      // Response decode, emitted-outcome decode and its canonical re-encode
      // are distinct. Keep all returned intermediate text through refusal;
      // only the first writer's retained outcome is subtracted here.
      owned_utf16_units: 2L * response.owned_utf16_units +
      2L * b +
      target.owned_utf16_units +
      identity_bytes.to_int64() +
      2L * writer.owned_utf16_units -
      b +
      digest.owned_utf16_units,
      owned_wire_bytes: b + identity_bytes.to_int64() + digest.owned_wire_bytes,
    },
  )
}
