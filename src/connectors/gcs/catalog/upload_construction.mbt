///|
// These inventories describe the existing pure GCS declaration producers.
// They issue no collection binding, original, permission or Resource. The
// same-runtime caller must reserve their full peak BEFORE invoking a producer.
fn upload_construction_inventory(
  parser_bytes : Int,
  parser_nodes : Int,
  raw_nodes : Int64,
  writer_bytes : Int,
  writer_nodes : Int,
  retained_text : Int64,
  retained_wire : Int64,
  limits : ObjectUploadDeclarationLimits,
) -> @execution.PreparationRepresentationUnits? {
  guard @source.json_construction_extent(
      parser_bytes,
      parser_nodes,
      limits.max_depth,
      normalize_keys=false,
    )
    is Some(parser) &&
    @encode.text_writer_construction_inventory(
      writer_bytes,
      writer_nodes,
      limits.max_depth,
    )
    is Some(writer) else {
    return None
  }
  let n = writer_nodes.to_int64()
  guard @shape.collection_construction_extent({
      // Raw Json tag/number spelling/field pair; Map, original+sorted+copied
      // field arrays. Parsed outer declaration, Catalog and detached registry
      // are distinct originals, whereas inserted command members are borrowed.
      records: 3L * raw_nodes,
      record_references: 4L * raw_nodes,
      record_words: 2L * raw_nodes,
      reference_arrays: 3L * raw_nodes,
      reference_items: 4L * raw_nodes,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: raw_nodes,
      map_entries: raw_nodes,
    })
    is Some(raw) &&
    @shape.collection_construction_extent({
      // canonical_json.from_json: CanonicalValue, field pair, BuildFrame;
      // canonical emission: EmitFrame and borrowed-array/object cursor.
      // The pinned field/key sorting scratch is6H/4R/10W per member.
      records: (3L + 2L + 6L) * n,
      record_references: (5L + 4L + 4L) * n,
      record_words: (2L + 2L + 10L) * n,
      reference_arrays: 4L * n,
      reference_items: 6L * n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: n,
      map_entries: n,
    })
    is Some(canonical) else {
    return None
  }
  Some({
    record_headers: parser.record_headers +
    raw.record_headers +
    canonical.record_headers +
    writer.record_headers,
    reference_slots: parser.reference_slots +
    raw.reference_slots +
    canonical.reference_slots +
    writer.reference_slots,
    scalar_words: parser.scalar_words +
    raw.scalar_words +
    canonical.scalar_words +
    writer.scalar_words,
    // collection_json uses data_keys=true: scalar text is validated and
    // borrowed, NOT NFC-normalized. Count actual retained wire/text domains.
    owned_utf16_units: parser.owned_utf16_units +
    writer.owned_utf16_units +
    retained_text,
    owned_wire_bytes: retained_wire,
  })
}

///|
fn upload_peak_capacity(
  peak : @execution.PreparationRepresentationUnits,
) -> @execution.ExecutionCapacity? {
  @execution.preparation_execution_capacity({
    retained: peak,
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
// upload_command_bundle's complete tree has83 value occurrences. Its fixed
// JSON vocabulary/punctuation is1508 bytes when connector/CID slots are empty:
// input body18; sealed input24; sealed output11; Command46; bundle+array2.
// Six connector occurrences and five canonical71-byte CIDs fill those slots.
fn upload_bundle_bytes(connector_units : Int) -> Int64 {
  1508L + 6L * 6L * connector_units.to_int64() + 5L * 71L
}

///|
// Allocation-free initialization-only bound over the SAME immutable wire.
// A JSON value is a root, an object value following a colon, or an array
// first/subsequent item following '['/','. Count both container alternatives.
// Detached embedded JSON delimiters are either visible literal code units or
// hidden behind escapes; every hidden delimiter spends at least one original
// backslash. Counting all punctuation even inside ordinary strings only
// overestimates. This bounds EACH outer/Catalog/detached-registry family, not
// their sum; their distinct retained originals remain separately accounted.
// No validity, canonical identity, decoded tree or permission is produced.
fn upload_structural_node_bound(wire : String) -> Int64 {
  let mut nodes = 1L
  for index in 0..<wire.length() {
    let unit = wire.code_unit_at(index)
    if unit == 0x7b || unit == 0x5b {
      nodes += 2L
    } else if unit == 0x3a || unit == 0x2c || unit == 0x5c {
      nodes += 1L
    }
  }
  nodes
}

///|
fn upload_catalog_bounds(
  declared_wire : String,
  connector_units : Int,
  limits : ObjectUploadDeclarationLimits,
) -> (Int, Int, Int, Int, Int64, Int64, Int64)? {
  if connector_units < 0 ||
    limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 {
    return None
  }
  let u = declared_wire.length().to_int64()
  // UTF8 length is never smaller than UTF16 length; this original cannot
  // reach a parser when already over its unchanged byte ceiling.
  if u > limits.max_bytes.to_int64() {
    return None
  }
  let all_nodes = upload_structural_node_bound(declared_wire)
  let n = Int64::min(all_nodes, limits.max_nodes.to_int64())
  let bytes = Int64::min(limits.max_bytes.to_int64(), Int64::max(1L, 3L * u))
  let bundle = upload_bundle_bytes(connector_units)
  // Each decoded Catalog/registry String domain has total length<=outer U.
  // JSON escaping takes<=6 units; a numeric spelling takes<=25 bytes/node.
  // The new fixed bundle contributes its own complete original syntax.
  // Detached contract/command bodies are an AGGREGATE, not one writer.
  // Their sum must not be clamped to an individual document's byte limit.
  let bodies = 6L * u + 25L * all_nodes + bundle
  // Outer declaration retains Catalog, contracts and command_bodies before
  // serializing. Existing other keys/values are bounded by original U.
  let output_nodes = Int64::min(limits.max_nodes.to_int64(), 2L * n + 83L)
  let output = Int64::min(
    limits.max_bytes.to_int64(),
    6L * (u + 3L * bodies) +
    3L * output_nodes +
    "command_bodies".length().to_int64() +
    4L,
  )
  if bundle > 2147483647L {
    return None
  }
  Some(
    (
      bytes.to_int(),
      n.to_int(),
      output.to_int(),
      output_nodes.to_int(),
      bodies,
      bundle,
      all_nodes,
    ),
  )
}

///|
// The complete old constructor prefix remains workspace. Its output-retained
// quantity below is additional, never subtracted from this conservative peak.
fn upload_catalog_peak_inventory(
  declared_wire : String,
  connector_units : Int,
  limits : ObjectUploadDeclarationLimits,
) -> @execution.PreparationRepresentationUnits? {
  guard upload_catalog_bounds(declared_wire, connector_units, limits)
    is Some((bytes, nodes, output, output_nodes, bodies, bundle, all_nodes)) else {
    return None
  }
  let u = declared_wire.length().to_int64()
  guard upload_construction_inventory(
      bytes,
      nodes,
      // Outer declaration, parsed Catalog and detached contract registry.
      // Each individual parser is capped; the detached registry aggregate
      // is bounded by the original structural scan, not one parser's max_nodes.
      2L * nodes.to_int64() + all_nodes + 83L + output_nodes.to_int64(),
      output,
      output_nodes,
      // Source projection also JSON.parses the original returned wire.
      3L * u + 3L * bodies + 2L * output.to_int64() + bundle,
      // Sequential parse UTF8 conversion and hash conversion can overlap
      // the retained declaration strings; neither is a second parse grant.
      bytes.to_int64() + bodies,
      limits,
    )
    is Some(peak) else {
    return None
  }
  Some(peak)
}

///|
fn upload_collection_units(
  value : @shape.CollectionConstructionExtent,
  text : Int64,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: text,
    owned_wire_bytes: 0L,
  }
}

///|
// freezeSourceProjection freezes in place. Its pending array, Object.values
// arrays and iteration/control frames do not escape either completed walk.
// Per visited value, co-count four iterator/result/control records (two refs
// and one word each), two value/pending arrays and four item references.
// Eight fixed control records (two refs/one word each) and two root arrays
// cover entry/exit. The caller sums both declared and aliased-command walks.
fn upload_freeze_workspace(
  nodes : Int64,
) -> @execution.PreparationRepresentationUnits? {
  guard @shape.collection_construction_extent({
      records: 4L * nodes + 8L,
      record_references: 8L * nodes + 16L,
      record_words: 4L * nodes + 8L,
      reference_arrays: 2L * nodes + 2L,
      reference_items: 4L * nodes,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(value) else {
    return None
  }
  Some(upload_collection_units(value, 0L))
}

///|
fn upload_output_capacity(
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
/// One pure catalog-extension call. The installed projection retains only its
/// exact wire and ONE JSON.parse graph; commands aliases command_bodies in that
/// graph. Common freezes it in place. No native Catalog/Json/Contract escapes.
/// The full peak remains reserved until successful output validation/freeze;
/// failure retains the complete original peak through initializer retirement.
pub fn object_upload_catalog_construction_capacity(
  declared_wire : String,
  connector_units : Int,
  limits : ObjectUploadDeclarationLimits,
) -> @execution.ExecutionCapacity? {
  guard upload_catalog_bounds(declared_wire, connector_units, limits)
    is Some((_, _, output, output_nodes, _, _, _)) &&
    upload_catalog_peak_inventory(declared_wire, connector_units, limits)
    is Some(peak) else {
    return None
  }
  let n = output_nodes.to_int64()
  guard @shape.collection_construction_extent({
      // Co-count plain object/array/scalar node alternatives and their edges;
      // no parser/index/canonical/writer frames survive this returned JSON tree.
      // One project wrapper retains declared, commands(alias) and wire.
      // Value records plus at most n key String headers; key backing below.
      records: 2L * n + 2L,
      record_references: 3L * n + 4L,
      record_words: n,
      reference_arrays: n,
      reference_items: Int64::max(0L, n - 1L),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: n,
      map_entries: Int64::max(0L, n - 1L),
    })
    is Some(graph) &&
    upload_freeze_workspace(2L * n) is Some(freeze) &&
    @execution.compose_preparation_representation([peak, freeze])
    is Some(workspace) else {
    return None
  }
  // JSON.parse key/value text totals <=wire bytes. Wire backing and decoded
  // String backing are distinct; all other references are aliases.
  upload_output_capacity(
    upload_collection_units(graph, 2L * output.to_int64()),
    workspace,
  )
}

///|
/// Existing collection binding + mapping producer, after the actual Site has
/// supplied the installation CID. Mapping generation intentionally revalidates
/// the complete Command Catalog by calling object_upload_catalog_json again.
pub fn object_collection_mapping_construction_capacity(
  declared_wire : String,
  project_units : Int,
  bucket_units : Int,
  prefix_units : Int,
  target_ref_units : Int,
  connector_units : Int,
  limits : ObjectUploadDeclarationLimits,
) -> @execution.ExecutionCapacity? {
  if project_units < 0 ||
    bucket_units < 0 ||
    prefix_units < 0 ||
    target_ref_units < 0 {
    return None
  }
  guard upload_catalog_peak_inventory(declared_wire, connector_units, limits)
    is Some(extension_peak) &&
    upload_catalog_bounds(declared_wire, connector_units, limits)
    is Some((_, _, output, output_nodes, _, bundle, _)) else {
    return None
  }
  let provider = "{\"version\":\"actql-gcs-provider/0.1\",\"project\":\"\",\"bucket\":\"\"}"
    .length()
    .to_int64() +
    6L * (project_units.to_int64() + bucket_units.to_int64())
  let scope = "{\"version\":\"actql-gcs-resource-scope/0.1\",\"project\":\"\",\"bucket\":\"\",\"prefix\":\"\"}"
    .length()
    .to_int64() +
    6L *
    (
      project_units.to_int64() +
      bucket_units.to_int64() +
      prefix_units.to_int64()
    )
  let identity = "{\"version\":\"actql.collection_resource_identity/0.1\",\"provider_namespace\":\"gcs\",\"resource_kind\":\"file_collection\",\"target_ref\":\"\",\"collection_identity\":{\"project\":\"\",\"bucket\":\"\",\"prefix\":\"\"},\"boundary_topology\":\"connector_connection\"}"
    .length()
    .to_int64() +
    6L *
    (
      project_units.to_int64() +
      bucket_units.to_int64() +
      prefix_units.to_int64() +
      target_ref_units.to_int64()
    )
  let resource = "{\"$actql_ref\":\"resource\",\"version\":\"actql-resource-ref/0.1\",\"provider_namespace\":\"gcs\",\"resource_kind\":\"file_collection\",\"provider_identity_cid\":\"\",\"authority_scope_cid\":\"\",\"boundary_cid\":\"\",\"identity_cid\":\"\"}"
    .length()
    .to_int64() +
    4L * 71L
  // upload_declaration.mbt's Mapping has103 nodes and1885 bytes of fixed
  // syntax with its two connector, target-ref and six CID slots empty.
  // Rules contribute45 nodes (four alternatives), row_mapping13, schema17.
  let mapping = 1885L +
    6L * (2L * connector_units.to_int64() + target_ref_units.to_int64()) +
    6L * 71L
  let binding_text = provider + scope + identity + resource
  let writer_bytes = Int64::min(
    limits.max_bytes.to_int64(),
    Int64::max(mapping, Int64::max(binding_text, bundle)),
  )
  let parser_bytes = Int64::min(
    limits.max_bytes.to_int64(),
    Int64::max(
      output.to_int64(),
      3L * (identity + resource + declared_wire.length().to_int64()),
    ),
  )
  let parser_nodes = Int::min(limits.max_nodes, Int::max(output_nodes, 13))
  let writer_nodes = Int::min(limits.max_nodes, 103)
  guard upload_construction_inventory(
      parser_bytes.to_int(),
      parser_nodes,
      // Complete declared output + manifest4/resource9 parsed originals;
      // four binding bodies4+5+10+9, new bundle83, final Mapping103.
      output_nodes.to_int64() + 4L + 9L + 4L + 5L + 10L + 9L + 83L + 103L,
      writer_bytes.to_int(),
      writer_nodes,
      output.to_int64() +
      declared_wire.length().to_int64() +
      binding_text +
      mapping +
      bundle,
      parser_bytes + writer_bytes,
      limits,
    )
    is Some(pipeline) &&
    // Only these five native fields escape collection_identity.mbt::
    // prepare_object_collection_binding: installation_cid, target_ref,
    // identity_wire, identity_cid, resource_wire. No Catalog/declaration field.
    // gcs-collection-target.mjs retains that binding in WeakMap {moon,binding};
    // its target borrows the three exported Strings. The installed projection
    // adds {target,mappingWires:[mapping]} and no parsed Mapping/Catalog tree.
    @shape.collection_construction_extent({
      records: 4L,
      record_references: 12L,
      record_words: 0L,
      reference_arrays: 1L,
      reference_items: 1L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 4L,
      map_entries: 8L,
    })
    is Some(escaped) &&
    upload_freeze_workspace(7L) is Some(freeze) &&
    @execution.compose_preparation_representation([
      extension_peak, pipeline, freeze,
    ])
    is Some(workspace) else {
    return None
  }
  let retained_identity = Int64::min(identity, limits.max_bytes.to_int64())
  let retained_resource = Int64::min(resource, limits.max_bytes.to_int64())
  let retained_mapping = Int64::min(mapping, limits.max_bytes.to_int64())
  // Conservatively co-count native/export String backings even though the
  // current getters borrow them. Installation/target originals remain live
  // through the binding; count their exact copied bounds as well.
  let text = 2L * (retained_identity + retained_resource + 71L) +
    retained_mapping +
    target_ref_units.to_int64() +
    71L
  upload_output_capacity(upload_collection_units(escaped, text), workspace)
}
