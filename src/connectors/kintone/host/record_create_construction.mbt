///|
/// Native mapped CREATE constructor units, not capacity or permission. The
/// same Form/Mapping remains borrowed. Source parsing/index/key normalization,
/// input UTF8, Host saved envelopes/HTTP/credentials and response construction
/// are deliberately separate caller components. The caller must back quotation
/// metadata before entry and compose these units before constructing a request.
pub(all) struct RecordCreateRequestConstructionInventory {
  representation : @shape.CollectionConstructionExtent
  owned_utf16_units : Int64
}

///|
fn create_construction_domain(contract : @contract.Contract) -> Bool {
  match contract.shape {
    @contract.Text(_) | @contract.Date | @contract.Timestamp => true
    @contract.Array(item, ..) =>
      !contract.nullable && !item.nullable && item.shape is @contract.Text(_)
    _ => false
  }
}

///|
fn create_construction_max(
  left : @shape.CollectionConstructionExtent,
  right : @shape.CollectionConstructionExtent,
) -> @shape.CollectionConstructionExtent {
  {
    record_headers: Int64::max(left.record_headers, right.record_headers),
    reference_slots: Int64::max(left.reference_slots, right.reference_slots),
    scalar_words: Int64::max(left.scalar_words, right.scalar_words),
  }
}

///|
// Shared mapped-write Value body family. CREATE and UPDATE use the SAME
// original Catalog/checked text, date, timestamp and String-array admission.
// This inspects types only, without constructing values or a copied Mapping.
fn record_write_value_construction_extents(
  original : RecordDeclaration,
  write : @catalog.RecordWriteLimits,
) -> (@shape.CollectionConstructionExtent, @shape.CollectionConstructionExtent)? {
  if write.max_fields < 1 ||
    write.max_nodes < 1 ||
    write.max_nodes == 2147483647 ||
    write.max_text_bytes < 1 {
    return None
  }
  let fields = Int::min(write.max_fields, write.max_nodes)
  let n = write.max_nodes.to_int64()
  // All cells share the native max_nodes/max_text_bytes counters. A synthetic
  // envelope ROOT describes their forest; it is quantity DATA only and is
  // never materialized/admitted as a Value or Parameter. At most F native
  // arrays plus that root coexist; the remaining nodes may all be text leaves.
  let arrays = Int::min(fields, write.max_nodes)
  let geometry : @decode.SubtreeConstructionGeometry = {
    nodes: write.max_nodes + 1,
    arrays: arrays + 1,
    array_items: write.max_nodes,
    objects: 0,
    fields: 0,
    texts: write.max_nodes - arrays,
    max_object_fields: 0,
    max_key_utf16: 0,
    max_text_utf16: write.max_text_bytes,
    total_utf16: write.max_text_bytes.to_int64(),
    work: 2L * n + 1L,
  }
  let mut values : @shape.CollectionConstructionExtent = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  }
  let mut traversal = values
  let mut supported = 0
  for index in 0..<@catalog.form_field_count(original.catalog) {
    guard @catalog.record_write_field_contract_at(original.catalog, index)
      is Some(contract) else {
      continue
    }
    if !create_construction_domain(contract) {
      return None
    }
    supported += 1
    guard @admitted.contract_value_body_construction_inventory(
        contract, geometry,
      )
      is Some(body) &&
      body.owned_value_utf16_units == 0L &&
      body.owned_decimal_scratch_utf16_units == 0L &&
      body.key_normalization is None else {
      return None
    }
    // Validate EVERY actual Form contract. All permitted alternatives use the
    // same non-Decimal Value family over the shared forest bound; componentwise
    // maxima cover that family without multiplying a global node budget by F.
    values = create_construction_max(values, body.value_extent)
    traversal = create_construction_max(traversal, body.traversal_extent)
  }
  if supported == 0 {
    return None
  }
  Some((values, traversal))
}

///|
/// One standard row's EXISTING native constructor and saved-value wire export,
/// including retained cells/documents and a failed prefix. Native batch is unchanged;
/// this selected per-row implementation requires max_records=1. No constructor
/// runs here and no unsupported field can select a default inventory.
pub fn record_create_mapped_request_construction_inventory(
  mapping : RecordCreateMapping,
  max_input_bytes : Int,
  write : @catalog.RecordWriteLimits,
  request : @catalog.RecordMutationLimits,
) -> RecordCreateRequestConstructionInventory? {
  if !record_create_mapping_is_original(mapping) {
    return None
  }
  record_write_admission_construction_inventory(
    mapping.original,
    mapping.written_fields.length(),
    max_input_bytes,
    write,
    request,
  )
}

///|
// The original CREATE envelope also covers UPDATE's identical mapped-value
// admission, correspondence, native document and saved-value writer. Its
// unused CREATE request writer remains a conservative WORKSPACE alternative;
// UPDATE prices its own returned proposal separately, without retaining it.
fn record_write_admission_construction_inventory(
  original : RecordDeclaration,
  written_fields : Int,
  max_input_bytes : Int,
  write : @catalog.RecordWriteLimits,
  request : @catalog.RecordMutationLimits,
) -> RecordCreateRequestConstructionInventory? {
  if max_input_bytes < 1 ||
    write.max_fields < 1 ||
    write.max_name_bytes < 1 ||
    write.max_nodes < 1 ||
    write.max_nodes == 2147483647 ||
    write.max_depth < 1 ||
    write.max_text_bytes < 1 ||
    write.max_output_bytes < 1 ||
    request.max_records != 1 ||
    request.max_identity_bytes < 1 ||
    request.max_comparison_work < 1 ||
    request.max_output_bytes < 1 ||
    request.max_output_nodes < 1 ||
    request.max_output_depth < 1 {
    return None
  }
  if written_fields <= 0 || written_fields > write.max_fields {
    return None
  }
  // Native admission can construct an unmapped but otherwise writable field
  // before final Mapping correspondence refuses it. Cover that failed prefix.
  let fields = Int::min(write.max_fields, write.max_nodes)
  let f = fields.to_int64()
  let n = write.max_nodes.to_int64()
  guard record_write_value_construction_extents(original, write)
    is Some((values, traversal)) else {
    return None
  }
  // Per field: two original Form-derived Contract projections at most6H10R5W
  // each; initial+rechecked CheckedValue2H4R; cells/originals/checked tuples
  // 3H7R. Native source/target Strings and installed Form metadata are borrowed.
  // Shared Request/WriteValues/self Some/two EncodedDocuments/five success
  // Results/WireEmitCursor/captured Mapping predicates add16H22R13W.
  // The extracted checked-row parser adds one Ok(Array) and the shared request
  // validation adds one Ok(Unit):2H1R1W. The emitted document remains co-counted
  // as constructor workspace even though the request now retains only its text.
  // Four field arrays + two one-element lookup-path arrays per field; three
  // one-record request/value copies. The seen-field Map owns F keys.
  guard @shape.collection_construction_extent({
      records: 18L + 17L * f,
      record_references: 23L + 31L * f,
      record_words: 14L + 10L * f,
      reference_arrays: 7L + 2L * f,
      reference_items: 3L + 6L * f,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: f,
    })
    is Some(native) else {
    return None
  }
  // The typed admission/recheck entry keeps14H17R28W beyond the Value body.
  // Two row open_object views add4H6R2W and their original maps below.
  // Date/Timestamp validation co-counts both initial/recheck alternatives:
  // seven digit Options, instant/Some, date tuple and the fixed month tables.
  // The SAME scalar owner's UTF8 controls run synchronously once at a time,
  // never once per text character or field. One scalar-count Option is extra.
  let utf8 = @scalar.utf8_length_admission_construction_units()
  guard @shape.collection_construction_extent({
      records: 14L + 4L + 20L + utf8.0 + 1L + 2L + 10L,
      record_references: 17L + 6L + 8L + utf8.1 + 10L,
      record_words: 28L + 2L + 34L + utf8.2 + 2L + 10L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 6L,
      scalar_items: 56L,
      maps: 2L,
      map_entries: 2L * n,
    })
    is Some(controls) &&
    @shape.scale_collection_construction_extent(
      @decode.indexed_field_construction_extent(),
      f,
    )
    is Some(field_reads) &&
    @decode.issue_construction_extent(write.max_depth) is Some(issue) else {
    return None
  }
  // The10 failure wrappers cover Decode/Abort/failed poll/admission Err/native
  // invalid field/Write/inner+outer JSON Err/execution Catalog+Err. The original
  // decoder owns the same copied path/span inventory. No failed output escapes.
  // The third writer emits saved Common values. Its WireFrames and one current
  // StringEmitCursor fit the same non-reference traversal envelope: <=2N+2
  // live frames, each <=3 references/4 words, plus its existing array backing.
  let value_writer = @encode.text_writer_construction_inventory(
    write.max_output_bytes,
    write.max_nodes,
    write.max_depth,
  )
  let request_writer = @encode.text_writer_construction_inventory(
    request.max_output_bytes,
    request.max_output_nodes,
    request.max_output_depth,
  )
  let saved_writer = @encode.text_writer_construction_inventory(
    max_input_bytes,
    write.max_nodes,
    write.max_depth,
  )
  guard value_writer is Some(value_writer) &&
    request_writer is Some(request_writer) &&
    saved_writer is Some(saved_writer) else {
    return None
  }
  let writers : @shape.CollectionConstructionExtent = {
    record_headers: value_writer.record_headers +
    request_writer.record_headers +
    saved_writer.record_headers,
    reference_slots: value_writer.reference_slots +
    request_writer.reference_slots +
    saved_writer.reference_slots,
    scalar_words: value_writer.scalar_words +
    request_writer.scalar_words +
    saved_writer.scalar_words,
  }
  guard @shape.compose_collection_construction_extents([
      native,
      controls,
      values,
      traversal,
      traversal,
      field_reads,
      @decode.indexed_child_construction_extent(),
      issue,
      writers,
    ])
    is Some(representation) else {
    return None
  }
  Some({
    representation,
    // The two Timestamp substring/concat spellings add19+20 units at the
    // current field. All original scalar text stays with the source input.
    owned_utf16_units: value_writer.owned_utf16_units +
    request_writer.owned_utf16_units +
    saved_writer.owned_utf16_units +
    39L,
  })
}

///|
/// Price ONLY the native constructor/output inventory above with the existing
/// execution owner. The standard Host still adds parser/index/input/wrapper,
/// physical request/response/secret and complete retained-lifetime overlap.
/// Holding this entire constructor envelope until output retirement deliberately
/// does not infer an early release from constructor return or GC.
pub fn record_create_mapped_request_construction_capacity(
  mapping : RecordCreateMapping,
  max_input_bytes : Int,
  write : @catalog.RecordWriteLimits,
  request : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_create_mapped_request_construction_inventory(
      mapping, max_input_bytes, write, request,
    )
    is Some(inventory) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: inventory.representation.record_headers,
      reference_slots: inventory.representation.reference_slots,
      scalar_words: inventory.representation.scalar_words,
      owned_utf16_units: inventory.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// The complete native proposal ingress, for fresh emission OR exact saved
/// body comparison. This adds the outer Common change-envelope constructors
/// to the existing mapped-row family; it does not reuse the array ingress as
/// the whole proposal price. Parser/index/input backing remains a separate
/// caller component, as do Host/physical/secret and failed-child overlap.
pub fn record_create_mapped_proposal_construction_inventory(
  mapping : RecordCreateMapping,
  max_input_bytes : Int,
  write : @catalog.RecordWriteLimits,
  request : @catalog.RecordMutationLimits,
) -> RecordCreateRequestConstructionInventory? {
  guard record_create_mapped_request_construction_inventory(
      mapping, max_input_bytes, write, request,
    )
    is Some(base) &&
    // Unknown/duplicate fields may fail before native value admission. The
    // allowed width TWO never bounds that supplied object or its key maps.
    @decode.closed_object_field_construction_extent(
      Some(write.max_nodes),
      2,
      0L,
    )
    is Some(envelope) &&
    @shape.scale_collection_construction_extent(
      @decode.indexed_child_construction_extent(),
      2L,
    )
    is Some(lookups) &&
    @decode.issue_construction_extent(write.max_depth) is Some(issue) else {
    return None
  }
  let utf8 = @scalar.utf8_length_admission_construction_units()
  // Allowed-name Array2 and the one-record [values] Array1. text's Ok and
  // missing/wrong-state Err add2H1R2W; both entry Result wrapper alternatives
  // add4H4R4W. Cold's CompareOutput+ComparedText+finish tuple add3H2R7W.
  // The two saved-body UTF8 checks (outer ingress and inner native restore)
  // use the scalar owner's SAME controls, with no encoded copy of that body.
  // The base deliberately still co-counts its emitted TextOutput constructor
  // beside these comparator controls, so it also bounds the fresh branch.
  guard @shape.collection_construction_extent({
      records: 9L + 2L * utf8.0,
      record_references: 7L + 2L * utf8.1,
      record_words: 13L + 2L * utf8.2,
      reference_arrays: 2L,
      reference_items: 3L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) &&
    @shape.compose_collection_construction_extents([
      base.representation,
      envelope,
      lookups,
      issue,
      controls,
    ])
    is Some(representation) else {
    return None
  }
  Some({ representation, owned_utf16_units: base.owned_utf16_units, })
}

///|
/// Price only the proposal-native family above, held until output retirement.
/// The original saved body is borrowed from its separately backed caller; no
/// constructor, grant, clock, new lifetime or physical operation is issued.
pub fn record_create_mapped_proposal_construction_capacity(
  mapping : RecordCreateMapping,
  max_input_bytes : Int,
  write : @catalog.RecordWriteLimits,
  request : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_create_mapped_proposal_construction_inventory(
      mapping, max_input_bytes, write, request,
    )
    is Some(inventory) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: inventory.representation.record_headers,
      reference_slots: inventory.representation.reference_slots,
      scalar_words: inventory.representation.scalar_words,
      owned_utf16_units: inventory.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
