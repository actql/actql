///|
fn relation_construction_collection_units(
  value : @shape.CollectionConstructionExtent,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
// The preserving metadata parser and normalizing schema parser are distinct
// original operations. This inventory neither parses nor admits their input.
fn relation_construction_decoded_construction(
  bytes : Int,
  nodes : Int,
  depth : Int,
  normalize_keys : Bool,
) -> @execution.PreparationRepresentationUnits? {
  guard @source.json_construction_extent(bytes, nodes, depth, normalize_keys~)
    is Some(parsed) &&
    @decode.admission_construction_inventory(nodes, nodes, nodes, nodes, depth)
    is Some(index) else {
    return None
  }
  Some({
    record_headers: parsed.record_headers +
    index.indexed.record_headers +
    index.keys.record_headers +
    index.ancestry.record_headers +
    index.controls.record_headers,
    reference_slots: parsed.reference_slots +
    index.indexed.reference_slots +
    index.keys.reference_slots +
    index.ancestry.reference_slots +
    index.controls.reference_slots,
    scalar_words: parsed.scalar_words +
    index.indexed.scalar_words +
    index.keys.scalar_words +
    index.ancestry.scalar_words +
    index.controls.scalar_words,
    owned_utf16_units: parsed.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn relation_construction_writer_units(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) else {
    return None
  }
  Some({
    record_headers: writer.record_headers,
    reference_slots: writer.reference_slots,
    scalar_words: writer.scalar_words,
    owned_utf16_units: writer.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
// Raw Json, ordered object assembly and canonical-value forests. Co-count
// object/array alternatives. A value can retain its tag, optional decimal
// spelling and key/value pair; original/copy/sort arrays overlap each Map.
// String backing is accounted separately from its original wire bound.
fn relation_construction_json_forest(
  nodes : Int64,
) -> @shape.CollectionConstructionExtent? {
  @shape.collection_construction_extent({
    records: 3L * nodes,
    record_references: 4L * nodes,
    record_words: 2L * nodes,
    reference_arrays: 3L * nodes,
    reference_items: 4L * nodes,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: nodes,
    map_entries: nodes,
  })
}

///|
// ReadRelationSchema and its per-field checked Contract readers borrow the
// same admitted schema. Sum object/array endpoint inventories so neither
// mutually exclusive shape is mistakenly used as a bound for the other.
fn relation_construction_contract_units(
  nodes : Int,
  text_units : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  let parts = []
  for objects in [0, nodes] {
    guard @contract.read_construction_inventory({
        nodes,
        objects,
        arrays: nodes - objects,
        fields: nodes - 1,
        max_fields: nodes - 1,
        max_array_items: nodes - 1,
        max_selected_text_units: text_units,
        outer_depth: depth,
        work: nodes.to_int64(),
      })
      is Some(contract) else {
      return None
    }
    parts.push(relation_construction_collection_units(contract.retained))
    parts.push(relation_construction_collection_units(contract.scratch))
    parts.push({
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: contract.scratch_utf16_units,
      owned_wire_bytes: 0L,
    })
  }
  @execution.compose_preparation_representation(parts)
}

///|
/// Demand DATA for the existing single Relation view constructor with absent
/// request/acquisition overrides, followed by DeclarationJson export.
/// Provider producers derive schema geometry from the same bounded originals;
/// this does not admit those originals, reserve capacity, or grant authority.
/// Every synchronous temporary family is retained conservatively through the
/// initializer lifetime, including failure prefixes. Host JSON/Environment
/// construction and provider metadata/schema emission are separate components.
pub fn single_relation_declaration_construction_inventory(
  schema_bytes : Int,
  schema_nodes : Int,
  field_count : Int,
  facts_bytes : Int,
  facts_nodes : Int,
  resource_units : Int,
  connector_units : Int,
  revision_units : Int,
  limits : RowDeclarationLimits,
) -> @execution.PreparationRepresentationUnits? {
  if schema_bytes < 0 ||
    schema_nodes < 1 ||
    field_count < 0 ||
    field_count > 2147483618 ||
    facts_bytes < 0 ||
    facts_nodes < 1 ||
    resource_units < 0 ||
    connector_units < 0 ||
    revision_units < 0 ||
    limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_views < 1 ||
    limits.max_fields < 1 {
    return None
  }
  let names = resource_units.to_int64() +
    connector_units.to_int64() +
    revision_units.to_int64()
  // These literal templates are the exact fixed syntax in Envelopes.add,
  // row_acquisition_body, and generate_row_declaration_impl. Empty strings
  // stand for original identifiers; {} stands for a separately counted body.
  let cid = 71L
  let id = connector_units.to_int64() +
    resource_units.to_int64() +
    "/records/".length().to_int64() +
    1L
  let revision = revision_units.to_int64()
  let source_ref = connector_units.to_int64() +
    resource_units.to_int64() +
    "connector://#records".length().to_int64()
  let reference = "{\"id\":\"\",\"version\":\"\",\"cid\":\"\"}"
    .length()
    .to_int64() +
    6L * (id + "pushdown".length().to_int64() + revision + cid)
  let request_bytes = "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{}}"
    .length()
    .to_int64()
  let policy_bytes = "{\"version\":\"actql-source-data-policy/0.1\",\"source_ref\":\"\",\"classification\":\"unknown\"}"
    .length()
    .to_int64() +
    6L * source_ref
  let pushdown_bytes = "{\"version\":\"actql-source-view-pushdown/0.1\",\"carrier\":\"relation\",\"operations\":[\"projection\"]}"
    .length()
    .to_int64()
  let envelope_base = "{\"schema\":\"actql.contract/0.1\",\"id\":\"\",\"version\":\"\",\"kind\":\"\",\"body\":{},\"cid\":\"\"}"
    .length()
    .to_int64() -
    2L
  let carrier_bytes = schema_bytes.to_int64() +
    "{\"fields\":{},\"version\":\"actql-relation-schema/0.1\"}"
    .length()
    .to_int64() -
    2L
  let envelopes = 5L * envelope_base +
    6L *
    (
      5L * (id + revision + cid) +
      "requestrowfactspolicypushdown".length().to_int64() +
      "request_schemacarrier_schemacarrier_factsdata_policypushdown"
      .length()
      .to_int64()
    ) +
    request_bytes +
    carrier_bytes +
    facts_bytes.to_int64() +
    policy_bytes +
    pushdown_bytes
  let acquisition = "{\"default_mode\":\"snapshot\",\"request_schema\":{},\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"kind\":\"scan\",\"authority\":\"read_content\"}"
    .length()
    .to_int64() -
    2L +
    reference
  let view = "{\"schema\":\"actql.source_view/0.1\",\"connector_id\":\"\",\"connector_version\":\"\",\"resource_kind\":\"relation\",\"view_id\":\"records\",\"view_version\":\"\",\"acquisition\":{},\"request_processing\":{\"mutates_business_state\":false},\"output\":{\"carrier\":\"relation\",\"schema\":{},\"facts\":{},\"data_policy\":{}},\"pushdown\":{\"contract\":{},\"operations\":[\"projection\"]},\"contract_cid\":\"\"}"
    .length()
    .to_int64() -
    10L +
    acquisition +
    4L * reference +
    6L * (connector_units.to_int64() + 2L * revision + cid)
  let catalog = "{\"schema\":\"actql.connector_catalog/0.1\",\"connector_id\":\"\",\"connector_version\":\"\",\"source_views\":[],\"commands\":[],\"contracts\":[],\"catalog_cid\":\"\"}"
    .length()
    .to_int64() +
    view +
    envelopes +
    4L +
    6L * (connector_units.to_int64() + revision + cid)
  let d = Int64::min(limits.max_bytes.to_int64(), catalog)
  // Catalog: root+three scalar members+source_views array+SourceView43+
  // commands array+contracts array+five envelopes(45+schema)+catalog CID.
  let relation_bytes = Int64::min(
    limits.max_bytes.to_int64(),
    schema_bytes.to_int64() + request_bytes + facts_bytes.to_int64(),
  ).to_int()
  let relation_nodes = Int64::min(
    limits.max_nodes.to_int64(),
    schema_nodes.to_int64() + 5L + facts_nodes.to_int64(),
  ).to_int()
  let keys = "connector_idconnector_registrationconnector_versioncatalogcatalog_cidcontractsviewsview_bodiesmanifest_entrymanifest_entry_cidevidence_schemasevidence_capabilitiesresourcesource_refview_cidfieldscarrier_schema_ciddata_policy_cid"
    .length()
    .to_int64()
  let outer = 6L *
    (8L * d + 8192L + 3L * names + schema_bytes.to_int64() + 13L * 71L + keys) +
    3L * field_count.to_int64() +
    3L * 18L +
    16L
  if outer > 2147483647L || catalog > 2147483647L {
    return None
  }
  guard relation_construction_decoded_construction(
      relation_bytes,
      relation_nodes,
      limits.max_depth,
      true,
    )
    is Some(parsed) &&
    relation_construction_contract_units(
      relation_nodes,
      relation_bytes,
      limits.max_depth,
    )
    is Some(contracts) &&
    relation_construction_json_forest(
      schema_nodes.to_int64() + 5L + facts_nodes.to_int64(),
    )
    is Some(input_forest) &&
    // Raw objects are assembled BEFORE the bounded emitters. Do not cap this
    // family at limits.max_nodes: a tiny writer limit can fail after assembly.
    relation_construction_json_forest(98L + 29L + field_count.to_int64() + 16L)
    is Some(assembled) &&
    relation_construction_decoded_construction(
      acquisition.to_int(),
      12,
      limits.max_depth,
      false,
    )
    is Some(acquisition_read) &&
    @canonical.nfc_lf_construction_extent(relation_bytes) is Some(normalization) &&
    @shape.collection_construction_extent({
      // Relation field reference/schema descriptors; shared declaration controls,
      // reference lists, sort index tuples and retained RowDeclaredView.
      records: 32L + 8L * field_count.to_int64(),
      record_references: 64L + 16L * field_count.to_int64(),
      record_words: 32L + 8L * field_count.to_int64(),
      reference_arrays: 24L,
      reference_items: 64L + 8L * field_count.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L,
      map_entries: field_count.to_int64(),
    })
    is Some(controls) else {
    return None
  }
  let parts = [
    parsed,
    parsed,
    contracts,
    acquisition_read,
    // Publication canonical verification and relation measurement each own a
    // raw Json and canonical forest. Defaults are reparsed after stringify.
    relation_construction_collection_units(input_forest),
    relation_construction_collection_units(input_forest),
    relation_construction_collection_units(input_forest),
    relation_construction_collection_units(input_forest),
    relation_construction_collection_units(assembled),
    relation_construction_collection_units(controls),
    {
      record_headers: normalization.record_headers,
      reference_slots: normalization.reference_slots,
      scalar_words: normalization.scalar_words,
      owned_utf16_units: normalization.owned_utf16_units +
      4L * relation_bytes.to_int64() +
      8L * d +
      8192L +
      outer +
      names,
      owned_wire_bytes: schema_bytes.to_int64(),
    },
  ]
  // Five contract envelopes, one SourceView, one Catalog and one manifest
  // each have an independent hash and text writer. Sum their actual families;
  // do not substitute one full-profile writer or multiply schema by max_views.
  let envelope_overhead = envelope_base + 6L * (id + revision + cid + 32L)
  for
    (bytes, nodes) in [
      (envelope_overhead + request_bytes, 11L),
      (envelope_overhead + carrier_bytes, 8L + schema_nodes.to_int64()),
      (envelope_overhead + facts_bytes.to_int64(), 6L + facts_nodes.to_int64()),
      (envelope_overhead + policy_bytes, 10L),
      (envelope_overhead + pushdown_bytes, 11L),
      (view, 43L),
      (catalog, 97L + schema_nodes.to_int64() + facts_nodes.to_int64()),
      (128L + 6L * names, 4L),
      // validate_result_schema_wire emits canonical schema and its hash;
      // request/facts canonicalization has separate text writers.
      (schema_bytes.to_int64(), schema_nodes.to_int64()),
      (request_bytes, 5L),
      (facts_bytes.to_int64(), facts_nodes.to_int64()),
    ] {
    let nb = Int64::min(bytes, limits.max_bytes.to_int64()).to_int()
    let nn = Int64::min(nodes, limits.max_nodes.to_int64()).to_int()
    guard relation_construction_writer_units(nb, nn, limits.max_depth)
      is Some(writer) &&
      @encode.hash_writer_construction_inventory(nn, limits.max_depth)
      is Some(hash) else {
      return None
    }
    parts.push(writer)
    parts.push({
      record_headers: hash.record_headers,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
      owned_utf16_units: hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
  }
  // Two evidence writers, followed by the one unbounded native export writer.
  for
    (bytes, nodes, depth) in [
      (4096, 64, 8),
      (4096, 64, 8),
      (outer.to_int(), 29 + field_count, limits.max_depth),
    ] {
    guard relation_construction_writer_units(bytes, nodes, depth)
      is Some(writer) else {
      return None
    }
    parts.push(writer)
  }
  @execution.compose_preparation_representation(parts)
}
