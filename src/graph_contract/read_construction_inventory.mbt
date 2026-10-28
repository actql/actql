///|
// Shared by the original definition codec/reader and its metadata observation.
let graph_nodes_field : String = "node_definitions"

///|
let graph_edges_field : String = "edge_definitions"

///|
let graph_name_field : String = "name"

///|
let graph_columns_field : String = "key_columns"

///|
let graph_keys_field : String = "key_contracts"

///|
let graph_properties_field : String = "properties"

///|
let graph_labels_field : String = "labels"

///|
let graph_source_field : String = "source_definition"

///|
let graph_target_field : String = "target_definition"

///|
pub struct GraphReadConstructionInventory {
  priv retained : @shape.CollectionConstructionExtent
  priv scratch : @shape.CollectionConstructionExtent
  priv retained_utf16 : Int64
  priv scratch_utf16 : Int64
  priv scratch_wire : Int64
  priv work : Int64
}

///|
priv struct GraphReadGeometry {
  mut definitions : Int
  mut edges : Int
  mut keys : Int
  mut properties : Int
  mut labels : Int
  mut selected_fields : Int
  mut max_schema_fields : Int
  mut name_units : Int64
  mut max_name_units : Int
  mut type_nodes : Int
  mut type_retained : @shape.CollectionConstructionExtent
  mut type_scratch : @shape.CollectionConstructionExtent
  mut type_utf16 : Int64
  mut work : Int64
}

///|
fn graph_metadata_child(
  root : @decode.Cursor,
  name : String,
  g : GraphReadGeometry,
) -> @decode.Cursor? {
  g.work += 1L
  if @decode.object_length(root) is Some(count) {
    for i in 0..<count {
      g.work += 2L
      let (key, child) = @decode.field_at(root, i).unwrap()
      if key == name {
        return Some(child)
      }
    }
  }
  None
}

///|
fn graph_metadata_name(value : String, g : GraphReadGeometry) -> Unit {
  g.name_units += value.length().to_int64()
  g.max_name_units = Int::max(g.max_name_units, value.length())
}

///|
fn graph_metadata_text(c : @decode.Cursor, g : GraphReadGeometry) -> Unit {
  g.work += 1L
  if @decode.text(c) is Ok(value) {
    graph_metadata_name(value, g)
  }
}

///|
fn graph_metadata_type(c : @decode.Cursor, g : GraphReadGeometry) -> Unit {
  let geometry = @value.observe_read_construction_geometry(c)
  g.work += geometry.work
  g.type_nodes += geometry.nodes
  let value = @value.read_construction_inventory(geometry).unwrap()
  g.type_retained = @shape.add_collection_construction_extents(
    g.type_retained,
    value.retained,
  ).unwrap()
  g.type_scratch = {
    record_headers: Int64::max(
      g.type_scratch.record_headers,
      value.scratch.record_headers,
    ),
    reference_slots: Int64::max(
      g.type_scratch.reference_slots,
      value.scratch.reference_slots,
    ),
    scalar_words: Int64::max(
      g.type_scratch.scalar_words,
      value.scratch.scalar_words,
    ),
  }
  g.type_utf16 = Int64::max(g.type_utf16, value.scratch_utf16_units)
}

///|
fn graph_metadata_definition(
  root : @decode.Cursor,
  g : GraphReadGeometry,
) -> Unit {
  g.definitions += 1
  for name in [graph_name_field, graph_source_field, graph_target_field] {
    if graph_metadata_child(root, name, g) is Some(c) {
      graph_metadata_text(c, g)
    }
  }
  if graph_metadata_child(root, graph_keys_field, g) is Some(list) {
    let count = @decode.array_length(list).unwrap_or(0)
    g.keys += count
    for i in 0..<count {
      g.work += 1L
      graph_metadata_type(@decode.element_at(list, i).unwrap(), g)
    }
  }
  if graph_metadata_child(root, graph_columns_field, g) is Some(list) {
    for i in 0..<@decode.array_length(list).unwrap_or(0) {
      graph_metadata_text(@decode.element_at(list, i).unwrap(), g)
    }
  }
  if graph_metadata_child(root, graph_properties_field, g) is Some(fields) {
    let count = @decode.object_length(fields).unwrap_or(0)
    g.properties += count
    g.max_schema_fields = Int::max(g.max_schema_fields, count)
    for i in 0..<count {
      g.work += 1L
      let (name, body) = @decode.field_at(fields, i).unwrap()
      graph_metadata_name(name, g)
      graph_metadata_type(body, g)
    }
  }
  if graph_metadata_child(root, graph_labels_field, g) is Some(fields) {
    let count = @decode.object_length(fields).unwrap_or(0)
    g.labels += count
    for i in 0..<count {
      g.work += 1L
      let (name, selected) = @decode.field_at(fields, i).unwrap()
      graph_metadata_name(name, g)
      let size = @decode.array_length(selected).unwrap_or(0)
      g.selected_fields += size
      g.max_schema_fields = Int::max(g.max_schema_fields, size)
      // These reference already admitted property display names. Retaining
      // their own occurrences is not another String or Contract body copy.
      g.work += size.to_int64()
    }
  }
}

///|
/// Observe actual original definition/field/label occurrences without reading
/// the grammar or issuing a Graph. This must be funded before its first call.
pub fn observe_graph_read_construction(
  root : @decode.Cursor,
) -> GraphReadConstructionInventory {
  let z = @shape.CollectionConstructionExtent::{
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  }
  let g = GraphReadGeometry::{
    definitions: 0,
    edges: 0,
    keys: 0,
    properties: 0,
    labels: 0,
    selected_fields: 0,
    max_schema_fields: 0,
    name_units: 0L,
    max_name_units: 0,
    type_nodes: 0,
    type_retained: z,
    type_scratch: z,
    type_utf16: 0L,
    work: 1L,
  }
  let (nodes, size_work) = @decode.observe_subtree_size(root)
  g.work += size_work
  for (name, edge) in [(graph_nodes_field, false), (graph_edges_field, true)] {
    if graph_metadata_child(root, name, g) is Some(list) {
      let count = @decode.array_length(list).unwrap_or(0)
      if edge {
        g.edges += count
      }
      for i in 0..<count {
        g.work += 1L
        graph_metadata_definition(@decode.element_at(list, i).unwrap(), g)
      }
    }
  }
  let d = g.definitions.to_int64()
  let e = g.edges.to_int64()
  let k = g.keys.to_int64()
  let l = g.labels.to_int64()
  let n = nodes.to_int64()
  // All definition and label-specific schemas survive, not one fictitious
  // schema with their summed columns. Their children remain the original types.
  let schemas = @carrier.unqualified_rows_retained_extent(
    g.properties + g.selected_fields,
    g.definitions + g.labels,
  ).unwrap()
  let graph = @shape.collection_construction_extent({
    // GraphDefinition, Graph, identity Contract, CheckedContract and owned CID
    // String are five distinct roots:10 references and3 scalar words.
    records: 5L + 2L * d + e + k + 2L * l,
    record_references: 10L + 7L * d + 3L * e + k + 2L * l,
    record_words: 3L + k + d + l,
    reference_arrays: 4L * d + 2L,
    reference_items: 2L * k + 2L * l + d,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: d + 2L,
    map_entries: l + d,
  }).unwrap()
  let retained = @shape.add_collection_construction_extents(
    g.type_retained,
    @shape.add_collection_construction_extents(schemas, graph).unwrap(),
  ).unwrap()
  let rows = @carrier.unqualified_rows_construction_inventory(
    g.max_schema_fields,
    g.max_name_units,
  ).unwrap()
  let comparison = @value.relation_construction_inventory(g.type_nodes).unwrap()
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  // Original read frames, names/keys/columns/exposed arrays and output copies;
  // root/definition views, per-definition key/property/selected-name maps and
  // graph-wide names/known/property-type maps. Old/new dictionary backing is
  // priced by the SAME Map owner; referenced property bodies are not copied.
  let frame = @shape.collection_construction_extent({
    records: 64L +
    9L * child.record_headers +
    4L * field.record_headers +
    6L * n,
    record_references: 48L +
    9L * child.reference_slots +
    4L * field.reference_slots +
    10L * n,
    record_words: 48L +
    9L * child.scalar_words +
    4L * field.scalar_words +
    6L * n,
    reference_arrays: 12L,
    reference_items: 5L * n + 24L,
    scalar_arrays: 1L,
    scalar_items: 71L,
    maps: 10L,
    map_entries: 13L + 3L * n,
  }).unwrap()
  let lower = @shape.ascii_lower_construction_extent(g.max_name_units).unwrap()
  let normal = @shape.add_collection_construction_extents(
    frame,
    @shape.add_collection_construction_extents(
      rows.scratch,
      @shape.add_collection_construction_extents(
        comparison.joined,
        comparison.scratch,
      ).unwrap(),
    ).unwrap(),
  ).unwrap()
  let normal = @shape.add_collection_construction_extents(normal, {
    record_headers: 2L * lower.record_headers,
    reference_slots: 2L * lower.reference_slots,
    scalar_words: 2L * lower.scalar_words,
  }).unwrap()
  // The final original graph emitter streams the same admitted body and
  // Strings. It shares the existing writer recipe and runs after read/compare.
  let hash = @encode.hash_writer_construction_inventory(nodes, nodes).unwrap()
  let encoding = @shape.collection_construction_extent({
    records: 40L + 6L * n,
    record_references: 30L + 10L * n,
    record_words: 20L + 8L * n,
    reference_arrays: 8L,
    reference_items: 3L * n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let encoding = @shape.add_collection_construction_extents(encoding, {
    record_headers: hash.record_headers,
    reference_slots: hash.reference_slots,
    scalar_words: hash.scalar_words,
  }).unwrap()
  // The original reader frame still owns its root/definition arrays and views
  // while a child type reader or final emitter runs. Returning one of those
  // callees does not retire the outer reader. Keep that overlap explicitly.
  let typed_phase = @shape.add_collection_construction_extents(
    frame,
    g.type_scratch,
  ).unwrap()
  let encoding_phase = @shape.add_collection_construction_extents(
    frame, encoding,
  ).unwrap()
  {
    retained,
    scratch: {
      record_headers: Int64::max(
        typed_phase.record_headers,
        Int64::max(normal.record_headers, encoding_phase.record_headers),
      ),
      reference_slots: Int64::max(
        typed_phase.reference_slots,
        Int64::max(normal.reference_slots, encoding_phase.reference_slots),
      ),
      scalar_words: Int64::max(
        typed_phase.scalar_words,
        Int64::max(normal.scalar_words, encoding_phase.scalar_words),
      ),
    },
    // CheckedContract retains its original sha256-prefixed CID as well as
    // folded names. A caller extracting only Graph can later retire that CID.
    retained_utf16: g.name_units + 71L,
    scratch_utf16: Int64::max(
      Int64::max(
        g.type_utf16,
        Int64::max(rows.scratch_utf16_units, 2L * lower.owned_utf16_units),
      ) +
      2L * g.name_units,
      hash.owned_utf16_units + 142L,
    ),
    scratch_wire: hash.owned_wire_bytes,
    work: g.work,
  }
}

///|
pub fn graph_read_construction_extent(
  v : GraphReadConstructionInventory,
) -> @shape.CollectionConstructionExtent {
  @shape.add_collection_construction_extents(v.retained, v.scratch).unwrap()
}

///|
pub fn graph_read_retained_extent(
  v : GraphReadConstructionInventory,
) -> @shape.CollectionConstructionExtent {
  v.retained
}

///|
pub fn graph_read_construction_text(
  v : GraphReadConstructionInventory,
) -> (Int64, Int64, Int64) {
  (v.retained_utf16, v.scratch_utf16, v.scratch_wire)
}

///|
pub fn graph_read_construction_work(
  v : GraphReadConstructionInventory,
) -> Int64 {
  v.work
}
