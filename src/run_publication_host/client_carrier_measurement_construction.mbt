///|
/// Pre-writer DATA from original checked Carrier owners. Scalar traversal and
/// its call-stack/result controls require prior backing. No writer, schema
/// identity, copied Graph array or wire is created by this scan.
/// This is NOT the full helper recipe: Presence cursor controls and Graph sort
/// controls must be composed independently, as indicated by the named fields.
pub(all) struct ClientCarrierMeasurementConstruction {
  value_nodes : Int
  depth : Int
  max_contract_nodes : Int
  graph_nodes : Int
  graph_branch : Bool
  graph_edges : Int
  max_graph_keys : Int
  max_graph_labels : Int
  reference_name_headers : Int64
  reference_name_utf16 : Int64
  max_reference_name_utf16 : Int64
  presence_fields : Int?
} derive(Eq, Debug)

///|
priv struct CarrierMeasurementScan {
  max_depth : Int
  mut nodes : Int64
  mut depth : Int
  mut contracts : Int
  mut keys : Int
  mut labels : Int
  mut name_headers : Int64
  mut name_units : Int64
  mut max_name : Int64
}

///|
fn carrier_measurement_contract(
  scan : CarrierMeasurementScan,
  contract : @contract.Contract,
  enclosing : Int,
) -> Bool {
  guard @contract.checked_emission_geometry(
      contract,
      max_depth=scan.max_depth - enclosing,
    )
    is Some(g) &&
    g.depth <= 2147483647 - enclosing else {
    return false
  }
  scan.nodes += g.value_nodes.to_int64()
  scan.depth = Int::max(scan.depth, g.depth + enclosing)
  scan.contracts = Int::max(scan.contracts, g.contract_nodes)
  scan.nodes <= 2147483647L
}

///|
fn carrier_measurement_name(
  scan : CarrierMeasurementScan,
  name : @schema.FieldName,
) -> Bool {
  let extent = @schema.reference_name_construction_extent(name)
  if scan.name_units > 9223372036854775807L - extent.scratch_utf16_units ||
    scan.name_headers > 9223372036854775807L - extent.scratch.record_headers {
    return false
  }
  scan.name_headers += extent.scratch.record_headers
  scan.name_units += extent.scratch_utf16_units
  scan.max_name = Int64::max(scan.max_name, extent.scratch_utf16_units)
  true
}

///|
fn carrier_measurement_graph_definition(
  scan : CarrierMeasurementScan,
  definition : @carrier.GraphNodeDefinition,
  edge : Bool,
) -> Bool {
  let keys = @carrier.graph_element_definition_key_count(definition)
  let labels = @carrier.graph_element_definition_label_count(definition)
  scan.keys = Int::max(scan.keys, keys)
  scan.labels = Int::max(scan.labels, labels)
  // object, columns, keys, labels, name, properties; edge endpoint scalars.
  scan.nodes += 6L + keys.to_int64() + (if edge { 2L } else { 0L })
  for index in 0..<keys {
    guard @carrier.graph_element_definition_key_at(definition, index) is Some(c) &&
      carrier_measurement_contract(scan, c, 4) else {
      return false
    }
  }
  for index in 0..<labels {
    guard @carrier.graph_element_definition_label_at(definition, index)
      is Some((_, fields)) else {
      return false
    }
    scan.nodes += 1L + @carrier.field_count(fields).to_int64()
    for field_index in 0..<@carrier.field_count(fields) {
      guard @carrier.field_at(fields, field_index) is Some(field) &&
        carrier_measurement_name(scan, field.name) else {
        return false
      }
    }
  }
  let fields = @carrier.graph_element_definition_properties(definition)
  for index in 0..<@carrier.field_count(fields) {
    guard @carrier.field_at(fields, index) is Some(field) &&
      field.contract is Some(c) &&
      carrier_measurement_name(scan, field.name) &&
      carrier_measurement_contract(scan, c, 4) else {
      return false
    }
  }
  scan.nodes <= 2147483647L
}

///|
pub fn client_carrier_measurement_construction(
  carrier : @carrier.Carrier,
  max_depth? : Int = 2147483647,
) -> ClientCarrierMeasurementConstruction? {
  guard client_task_contract_source(carrier) is Some(source) else {
    return None
  }
  if max_depth < 1 {
    return None
  }
  let scan : CarrierMeasurementScan = {
    max_depth,
    nodes: 0L,
    depth: 0,
    contracts: 0,
    keys: 0,
    labels: 0,
    name_headers: 0L,
    name_units: 0L,
    max_name: 0L,
  }
  let mut graph_branch = false
  let mut graph_nodes = 0
  let mut graph_edges = 0
  let mut presence_fields = None
  match source {
    ObjectRelation(row) =>
      if !carrier_measurement_contract(scan, row, 0) {
        return None
      }
    PresenceRelation(schema) => {
      presence_fields = Some(@schema.field_count(schema))
      scan.nodes = 1L
      scan.depth = 1
      for index in 0..<@schema.field_count(schema) {
        guard @schema.field_at(schema, index) is Some(field) &&
          carrier_measurement_name(scan, field.name) else {
          return None
        }
        let conditional = field.presence == @schema.Conditional
        if conditional {
          scan.nodes += 2L
        }
        if !carrier_measurement_contract(
            scan,
            field.contract,
            if conditional {
              2
            } else {
              1
            },
          ) {
          return None
        }
      }
    }
    GraphCarrier(original) => {
      graph_branch = true
      guard original is @carrier.GraphValue(graph) else { return None }
      let profile = @carrier.graph_definition(graph)
      graph_nodes = @carrier.graph_node_count(profile)
      graph_edges = @carrier.graph_edge_count(profile)
      scan.nodes = 7L
      // labels may be empty; 5 is a conservative original fixed wrapper bound.
      scan.depth = 5
      for index in 0..<graph_nodes {
        guard @carrier.graph_node_at(profile, index) is Some(definition) &&
          carrier_measurement_graph_definition(scan, definition, false) else {
          return None
        }
      }
      for index in 0..<graph_edges {
        guard @carrier.graph_edge_at(profile, index) is Some(edge) &&
          carrier_measurement_graph_definition(
            scan,
            @carrier.graph_edge_element(edge),
            true,
          ) else {
          return None
        }
      }
    }
    RecordCarrier(original, row) => {
      scan.nodes = 4L
      scan.depth = 2
      match original {
        @carrier.VectorValue(vectors) =>
          scan.nodes += @carrier.vector_identity_count(vectors).to_int64()
        @carrier.EventValue(_) => ()
        _ => return None
      }
      if !carrier_measurement_contract(scan, row, 1) {
        return None
      }
    }
  }
  if scan.depth > max_depth || scan.nodes > 2147483647L {
    return None
  }
  Some({
    value_nodes: scan.nodes.to_int(),
    depth: scan.depth,
    max_contract_nodes: scan.contracts,
    graph_nodes,
    graph_branch,
    graph_edges,
    max_graph_keys: scan.keys,
    max_graph_labels: scan.labels,
    reference_name_headers: scan.name_headers,
    reference_name_utf16: scan.name_units,
    max_reference_name_utf16: scan.max_name,
    presence_fields,
  })
}

///|
/// Variable helper constructors only. Mandatory Presence cursor/Graph sort and
/// fixed scalar controls are NOT included; their named operands remain visible
/// for the Native/local owner composition. No retained output escapes measure.
pub(all) struct ClientCarrierMeasurementVariableLayout {
  collections : @shape.CollectionConstructionExtent
  owned_utf16_units : Int64
  string_utf16_units : Int64
  reference_array_items : Int64
  writer_live_keys : Int
  writer_depth : Int
  graph_node_sort_items : Int
  graph_edge_sort_items : Int
  presence_fields : Int?
} derive(Eq, Debug)

///|
pub fn client_carrier_measurement_variable_layout(
  data : ClientCarrierMeasurementConstruction,
) -> ClientCarrierMeasurementVariableLayout? {
  if data.value_nodes < 1 ||
    data.depth < 0 ||
    data.max_contract_nodes < 0 ||
    data.graph_nodes < 0 ||
    data.graph_edges < 0 ||
    data.max_graph_keys < 0 ||
    data.max_graph_labels < 0 ||
    data.reference_name_headers < 0L ||
    data.reference_name_utf16 < 0L ||
    data.max_reference_name_utf16 < 0L {
    return None
  }
  // value_nodes bounds simultaneous ordinary-object keys. Ordered contract
  // field writers borrow prior keys and use no per-field key Map; deliberately
  // retaining the shared generic bound is safe for Graph's unordered wrapper.
  guard @encode.measuring_writer_construction_extent(
      data.value_nodes,
      data.depth,
    )
    is Some(writer) &&
    @shape.collection_construction_extent({
      records: data.reference_name_headers,
      record_references: 0L,
      record_words: 0L,
      // emit_graph keeps copied node/edge arrays. Key/label copies belong to
      // one current definition; arrays borrow their existing tuple/children.
      reference_arrays: if data.graph_branch {
        4L
      } else {
        0L
      },
      reference_items: data.graph_nodes.to_int64() +
      data.graph_edges.to_int64() +
      data.max_graph_keys.to_int64() +
      data.max_graph_labels.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(copies) &&
    @shape.add_collection_construction_extents(writer, copies)
    is Some(collections) else {
    return None
  }
  let mut collections = collections
  let mut refs = Int64::max(
    data.depth.to_int64(),
    Int64::max(
      Int64::max(data.graph_nodes.to_int64(), data.graph_edges.to_int64()),
      Int64::max(
        data.max_graph_keys.to_int64(),
        data.max_graph_labels.to_int64(),
      ),
    ),
  )
  if data.max_contract_nodes > 0 {
    guard @contract.checked_emission_construction_extent(
        data.max_contract_nodes,
      )
      is Some(emission) &&
      @shape.add_collection_construction_extents(collections, emission)
      is Some(combined) else {
      return None
    }
    collections = combined
    // Largest checked-emission pending array, from its owner recipe; each
    // separate current member array has at most six elements.
    refs = Int64::max(refs, 6L * data.max_contract_nodes.to_int64() + 8L)
  }
  Some({
    collections,
    owned_utf16_units: data.reference_name_utf16,
    string_utf16_units: data.max_reference_name_utf16,
    reference_array_items: refs,
    writer_live_keys: data.value_nodes,
    writer_depth: data.depth,
    graph_node_sort_items: data.graph_nodes,
    graph_edge_sort_items: data.graph_edges,
    presence_fields: data.presence_fields,
  })
}
