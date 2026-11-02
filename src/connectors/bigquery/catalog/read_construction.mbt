///|
fn read_collection_units(
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
fn read_decoded_construction(
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
fn read_writer_units(
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
/// Before DescribeTable, GenerateReadDeclaration and DeclarationJson. One
/// BigQuery table produces ONE Relation view, five contract envelopes, one
/// SourceView, one Catalog and one manifest. Every emitted body has the same
/// existing RowDeclarationLimits. The whole peak remains retained until the
/// Source initializer retires; failure does not imply a retained-output shrink.
///
/// Lengths describe the same bounded metadata/configuration originals. The
/// input base64 String is already owned; its decoded Buffer and the canonical
/// base64 comparison are included here. Host Environment parsing/merging is a
/// separate constructor on that same parent, not part of this native quote.
pub fn read_declaration_construction_capacity(
  body_bytes : Int,
  encoded_units : Int,
  target_units : Int,
  resource_units : Int,
  connector_units : Int,
  revision_units : Int,
  description : DescriptionLimits,
  declaration : @rows.RowDeclarationLimits,
) -> @execution.ExecutionCapacity? {
  if body_bytes < 0 ||
    encoded_units < 0 ||
    target_units < 0 ||
    resource_units < 0 ||
    connector_units < 0 ||
    revision_units < 0 ||
    !valid_limits(description) ||
    body_bytes > description.max_bytes ||
    declaration.max_bytes < 1 ||
    declaration.max_nodes < 1 ||
    declaration.max_depth < 1 ||
    declaration.max_views < 1 ||
    declaration.max_fields < 1 {
    return None
  }
  // json_parser.mbt checks its node/depth limits BEFORE value/container
  // allocation. encode_core/writer.mbt value_start and begin_* check before
  // output/frame allocation. Thus these bounds may cap parser/writer work.
  // Raw declaration assembly below is separately counted WITHOUT a node cap:
  // constructing a Json template precedes its bounded writer's admission.
  let b = Int::max(1, body_bytes)
  let n = Int::min(b, description.max_nodes)
  let f = Int::min(b, description.max_fields)
  let names = target_units.to_int64() +
    resource_units.to_int64() +
    connector_units.to_int64() +
    revision_units.to_int64()
  // BigQuery emits only primitive/decimal/record Contracts, optionally wrapped
  // by REPEATED. A base contributes <=5 nodes; the array wrapper adds3.
  // The sum of decoded field-name UTF8 lengths is <= the metadata wire B.
  // The two decimal numbers each use the writer's <=25-byte number spelling.
  let decimal_bytes = "{\"nullable\":false,\"precision\":0,\"scale\":0,\"type\":\"decimal\"}"
    .length()
    .to_int64() +
    2L * 24L
  let object_bytes = "{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"}"
    .length()
    .to_int64()
  let repeated_bytes = "{\"items\":{},\"nullable\":false,\"type\":\"array\"}"
    .length()
    .to_int64() -
    2L
  let schema_bound = 2L +
    6L * b.to_int64() +
    f.to_int64() *
    (Int64::max(decimal_bytes, object_bytes) + repeated_bytes + 4L)
  let schema_bytes = Int64::min(
    description.max_schema_bytes.to_int64(),
    schema_bound,
  ).to_int()
  let schema_nodes = Int64::min(
    description.max_nodes.to_int64(),
    1L + 8L * f.to_int64(),
  ).to_int()
  if 2L * f.to_int64() + 1L > 2147483647L {
    return None
  }
  let child = @decode.indexed_child_construction_extent()
  let lookups = 10L * f.to_int64() + 20L
  guard @shape.collection_construction_extent({
      // One ObjectView per column and the root/reference/schema/key frames.
      // All map entries are original metadata edges, not F separate N maps.
      records: 2L * (f.to_int64() + 6L) + lookups * child.record_headers,
      record_references: 3L * (f.to_int64() + 6L) +
      lookups * child.reference_slots,
      record_words: f.to_int64() + 6L + lookups * child.scalar_words,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: f.to_int64() + 6L,
      map_entries: n.to_int64(),
    })
    is Some(metadata_views) &&
    read_decoded_construction(b, n, description.max_depth, false)
    is Some(metadata) &&
    @rows.single_relation_declaration_construction_inventory(
      schema_bytes, schema_nodes, f, 2, 1, resource_units, connector_units, revision_units,
      declaration,
    )
    is Some(common) &&
    @contract.object_retained_construction_extent(2 * f, f + 1) is Some(objects) &&
    @contract.object_construction_inventory(f, description.max_name_bytes)
    is Some(object_work) &&
    @contract.checked_emission_construction_extent(2 * f + 1) is Some(emission) &&
    read_writer_units(schema_bytes, schema_nodes, description.max_depth)
    is Some(schema_writer) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash_writer) &&
    @shape.collection_construction_extent({
      // describe_column: ColumnDescription1H9R; primitive Contract/Text/
      // TextLimits3H6R; numeric Contract/Decimal/Option/Result4H3R;
      // REPEATED nullable-copy/Array/Contract/Option4H4R. Alternatives
      // deliberately coexist in this upper bound, not a liveness shortcut.
      // required_text(name,type): lookupSome/textOk/returnSome each3H3R.
      // optional_decimal(precision,scale,maxLength): lookupSome/textOk/
      // decimalOk/SomeInt/returnOk each5H5R. Collation has lookup/text/
      // scalar/Some4H4R. Recursive/column outcomes3H3R. The record and
      // selected-projection input tuples total2H4R per field, separately
      // from object_retained_construction_extent's returned Field records.
      records: (1L + 3L + 4L + 4L + 2L * 3L + 3L * 5L + 4L + 3L + 2L) *
      f.to_int64() +
      24L,
      record_references: (9L + 6L + 3L + 4L + 2L * 3L + 3L * 5L + 4L + 3L + 4L) *
      f.to_int64() +
      32L,
      // One tag/word per above record, plus three integer payloads, two
      // Decimal words and three Contract-nullability words. Object/Fields
      // storage and lookup Cursor words have separate inventories above.
      record_words: (
        1L + 3L + 4L + 4L + 2L * 3L + 3L * 5L + 4L + 3L + 2L + 3L + 2L + 3L
      ) *
      f.to_int64() +
      24L,
      // Literal arrays: name/type2, modes3, numeric keys3, numeric kinds4,
      // text kinds2. Working arrays: numeric options3, children aggregate F,
      // record field tuples aggregate F. Projection arrays are fixed below.
      reference_arrays: (5L + 3L) * f.to_int64() + 10L,
      reference_items: (2L + 3L + 3L + 4L + 2L + 3L + 1L + 1L) * f.to_int64() +
      64L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(columns) else {
    return None
  }
  guard @execution.compose_preparation_representation([
      metadata,
      read_collection_units(metadata_views),
      read_collection_units(columns),
      read_collection_units(objects),
      read_collection_units(object_work.scratch),
      read_collection_units(emission),
      schema_writer,
      common,
      {
        record_headers: hash_writer.record_headers,
        reference_slots: hash_writer.reference_slots,
        scalar_words: hash_writer.scalar_words,
        owned_utf16_units: hash_writer.owned_utf16_units +
        object_work.scratch_utf16_units +
        body_bytes.to_int64() +
        schema_bytes.to_int64() +
        encoded_units.to_int64() +
        names,
        owned_wire_bytes: hash_writer.owned_wire_bytes +
        body_bytes.to_int64() +
        schema_bytes.to_int64(),
      },
    ])
    is Some(peak) else {
    return None
  }
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
