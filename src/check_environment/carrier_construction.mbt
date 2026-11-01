///|
// The original reader owns these spellings. Metadata only selects which
// original constructor can run; it never admits a body or repairs its grammar.
let carrier_version_key : String = "version"

///|
let carrier_fields_key : String = "fields"

///|
let carrier_records_key : String = "records"

///|
let carrier_presence_key : String = "presence"

///|
let carrier_contract_key : String = "contract"

///|
let carrier_relation_version : String = "actql-relation-schema/0.1"

///|
let carrier_graph_version : String = "actql-graph-contract/0.1"

///|
let carrier_events_version : String = "actql-events-contract/0.1"

///|
let carrier_vectors_version : String = "actql-vectors-contract/0.1"

///|
pub(all) struct ProtocolCarrierConstructionInventory {
  retained : RegistryConstructionExtent
  scratch : RegistryConstructionExtent
  schemas : Int
  bindings : Int
  work : Int64
} derive(Eq, Debug)

///|
priv struct CarrierConstructionObservation {
  mut retained : RegistryConstructionExtent
  mut scratch : RegistryConstructionExtent
  mut all_facts : @shape.CollectionConstructionExtent
  mut held_facts : @shape.CollectionConstructionExtent
  mut schemas : Int
  mut facts : Int
  mut bindings : Int
  mut max_fields : Int
  mut max_fact_nodes : Int
  mut max_fact_fields : Int
  mut work : Int64
}

///|
fn carrier_units(
  v : @shape.CollectionConstructionExtent,
  text? : Int64 = 0L,
  wire? : Int64 = 0L,
) -> RegistryConstructionExtent {
  {
    record_headers: v.record_headers,
    reference_slots: v.reference_slots,
    scalar_words: v.scalar_words,
    owned_utf16_units: text,
    owned_wire_bytes: wire,
  }
}

///|
fn carrier_add_units(
  a : RegistryConstructionExtent,
  b : RegistryConstructionExtent,
) -> RegistryConstructionExtent {
  {
    record_headers: a.record_headers + b.record_headers,
    reference_slots: a.reference_slots + b.reference_slots,
    scalar_words: a.scalar_words + b.scalar_words,
    owned_utf16_units: a.owned_utf16_units + b.owned_utf16_units,
    owned_wire_bytes: a.owned_wire_bytes + b.owned_wire_bytes,
  }
}

///|
fn carrier_peak_units(
  a : RegistryConstructionExtent,
  b : RegistryConstructionExtent,
) -> RegistryConstructionExtent {
  {
    record_headers: Int64::max(a.record_headers, b.record_headers),
    reference_slots: Int64::max(a.reference_slots, b.reference_slots),
    scalar_words: Int64::max(a.scalar_words, b.scalar_words),
    owned_utf16_units: Int64::max(a.owned_utf16_units, b.owned_utf16_units),
    owned_wire_bytes: Int64::max(a.owned_wire_bytes, b.owned_wire_bytes),
  }
}

///|
fn carrier_metadata_child(
  root : @decode.Cursor,
  key : String,
  g : CarrierConstructionObservation,
) -> @decode.Cursor? {
  g.work += 1L
  if @decode.object_length(root) is Some(count) {
    for i in 0..<count {
      g.work += 2L
      let (name, child) = @decode.field_at(root, i).unwrap()
      if name == key {
        return Some(child)
      }
    }
  }
  None
}

///|
fn carrier_metadata_value(
  root : @decode.Cursor,
  g : CarrierConstructionObservation,
) -> Unit {
  let geometry = @value_contract.observe_read_construction_geometry(root)
  g.work += geometry.work
  let value = @value_contract.read_construction_inventory(geometry).unwrap()
  g.retained = carrier_add_units(g.retained, carrier_units(value.retained))
  g.scratch = carrier_peak_units(
    g.scratch,
    carrier_units(value.scratch, text=value.scratch_utf16_units),
  )
}

///|
fn carrier_metadata_rows(
  root : @decode.Cursor,
  fields : @decode.Cursor?,
  presence : Bool,
  g : CarrierConstructionObservation,
) -> Unit {
  let count = fields
    .map(value => @decode.object_length(value).unwrap_or(0))
    .unwrap_or(0)
  let mut name_units = 0
  if presence {
    if fields is Some(fields) {
      for i in 0..<count {
        g.work += 1L
        let (name, entry) = @decode.field_at(fields, i).unwrap()
        name_units = Int::max(name_units, name.length())
        let selected = if carrier_metadata_child(entry, carrier_presence_key, g)
          is Some(_) {
          carrier_metadata_child(entry, carrier_contract_key, g)
        } else {
          Some(entry)
        }
        if selected is Some(contract) {
          carrier_metadata_value(contract, g)
        }
      }
    }
    let rows = @row.unqualified_presence_construction_inventory(
      count, name_units,
    ).unwrap()
    g.retained = carrier_add_units(g.retained, carrier_units(rows.retained))
    g.scratch = carrier_peak_units(
      g.scratch,
      carrier_units(rows.scratch, text=rows.scratch_utf16_units),
    )
  } else {
    carrier_metadata_value(root, g)
    g.retained = carrier_add_units(
      g.retained,
      carrier_units(@row.from_object_construction_extent(1).unwrap()),
    )
  }
  let typed = @carrier.typed_rows_construction_inventory(count).unwrap()
  g.retained = carrier_add_units(g.retained, carrier_units(typed.retained))
  g.scratch = carrier_peak_units(g.scratch, carrier_units(typed.scratch))
}

///|
fn carrier_metadata_body(
  root : @decode.Cursor,
  nodes : Int,
  g : CarrierConstructionObservation,
) -> Unit {
  g.max_fields = Int::max(
    g.max_fields,
    @decode.object_length(root).unwrap_or(0),
  )
  g.scratch = carrier_peak_units(
    g.scratch,
    wire_hash_construction_extent(nodes).unwrap(),
  )
  let version = carrier_metadata_child(root, carrier_version_key, g)
  match version {
    None =>
      carrier_metadata_rows(
        root,
        carrier_metadata_child(root, carrier_fields_key, g),
        false,
        g,
      )
    Some(value) =>
      match @decode.text(value) {
        Ok(value) if value == carrier_graph_version => {
          let graph = @graph.observe_graph_read_construction(root)
          g.work += @graph.graph_read_construction_work(graph)
          let all = @graph.graph_read_construction_extent(graph)
          let held = @graph.graph_read_retained_extent(graph)
          let (held_text, scratch_text, scratch_wire) = @graph.graph_read_construction_text(
            graph,
          )
          g.retained = carrier_add_units(
            g.retained,
            carrier_units(held, text=held_text),
          )
          g.scratch = carrier_peak_units(g.scratch, {
            record_headers: all.record_headers - held.record_headers,
            reference_slots: all.reference_slots - held.reference_slots,
            scalar_words: all.scalar_words - held.scalar_words,
            owned_utf16_units: scratch_text,
            owned_wire_bytes: scratch_wire,
          })
        }
        Ok(value) if value == carrier_relation_version =>
          carrier_metadata_rows(
            root,
            carrier_metadata_child(root, carrier_fields_key, g),
            true,
            g,
          )
        Ok(value) if value == carrier_events_version ||
          value == carrier_vectors_version => {
          if carrier_metadata_child(root, carrier_records_key, g)
            is Some(records) {
            carrier_metadata_rows(
              records,
              carrier_metadata_child(records, carrier_fields_key, g),
              false,
              g,
            )
          }
          if value == carrier_vectors_version {
            let count = carrier_metadata_child(root, "ids", g)
              .map(value => @decode.array_length(value).unwrap_or(0))
              .unwrap_or(0)
              .to_int64()
            // The returned identities Array aliases already typed Fields. The
            // original input FieldName Array and duplicate-role Map are scratch.
            let held = @shape.collection_construction_extent({
              records: 0L,
              record_references: 0L,
              record_words: 0L,
              reference_arrays: 1L,
              reference_items: count,
              scalar_arrays: 0L,
              scalar_items: 0L,
              maps: 0L,
              map_entries: 0L,
            }).unwrap()
            let frame = @shape.collection_construction_extent({
              records: 5L + count,
              record_references: 4L + count,
              record_words: 3L + count,
              reference_arrays: 1L,
              reference_items: count,
              scalar_arrays: 0L,
              scalar_items: 0L,
              maps: 1L,
              map_entries: count,
            }).unwrap()
            g.retained = carrier_add_units(g.retained, carrier_units(held))
            g.scratch = carrier_peak_units(g.scratch, carrier_units(frame))
          }
        }
        _ => ()
      }
  }
}

///|
fn carrier_metadata_facts(
  root : @decode.Cursor,
  held : Bool,
  g : CarrierConstructionObservation,
) -> Unit {
  let mut tuples = 0
  let mut fields = 0
  let mut key = 0L
  let mut score = 0L
  g.max_fact_fields = Int::max(
    g.max_fact_fields,
    @decode.object_length(root).unwrap_or(0),
  )
  if carrier_metadata_child(root, relation_keys_component_key, g) is Some(keys) {
    key = 1L
    if carrier_metadata_child(keys, relation_keys_list_key, g) is Some(list) {
      tuples = @decode.array_length(list).unwrap_or(0)
      for i in 0..<tuples {
        g.work += 1L
        fields += @decode.array_length(@decode.element_at(list, i).unwrap()).unwrap_or(
          0,
        )
      }
    }
  }
  if carrier_metadata_child(root, relation_scores_component_key, g)
    is Some(scores) {
    let geometry = @decode.observe_subtree_geometry(scores, [])
    g.work += geometry.work
    g.max_fact_nodes = Int::max(g.max_fact_nodes, geometry.nodes)
    g.max_fact_fields = Int::max(g.max_fact_fields, geometry.max_fields)
    score = 1L
  }
  let t = tuples.to_int64()
  let f = fields.to_int64()
  // The original tuple Cursor, field-Array and tuple pair survive with Facts.
  // Names are borrowed; each tuple also retains its already-read maximum
  // UTF16 name length1W. Score facts retain only their original source cursor.
  let value = @shape.collection_construction_extent({
    records: 2L * key + 2L * t + 2L * score,
    record_references: 3L * key + 4L * t + 3L * score,
    record_words: 2L * t,
    reference_arrays: key + t,
    reference_items: t + f,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  g.all_facts = @shape.add_collection_construction_extents(g.all_facts, value).unwrap()
  if held {
    g.held_facts = @shape.add_collection_construction_extents(
      g.held_facts,
      value,
    ).unwrap()
  }
  g.max_fact_nodes = Int::max(g.max_fact_nodes, tuples + fields)
}

///|
/// Each bound derives from the SAME cached original Environment/Reference
/// inventory. Metadata never inspects arbitrary carrier-facts extension bodies.
pub fn protocol_carrier_construction_inspection_bound(
  modes : SourceReadModes,
) -> Int64 {
  let refs = modes.shapes.values.policies.references
  1L +
  160L * refs.contents.registry.environment.nodes.to_int64() +
  32L * refs.references.length().to_int64()
}

///|
/// Fund before the first metadata walk. The only input-sized observation
/// collection is the needed-facts Map; its keys are original borrowed CIDs.
/// Its extent comes from the SAME cached original lists, not a policy ceiling.
pub fn protocol_carrier_construction_inspection_extent(
  modes : SourceReadModes,
) -> RegistryConstructionExtent {
  let refs = modes.shapes.values.policies.references
  let entries = Int::min(
    refs.contents.registry.entries.length(),
    refs.references.length(),
  ).to_int64()
  // Call-expanded fixed observation packet: original observer/geometry and
  // typed return controls110H117R265W; <=24 simultaneously retained/nested
  // collection-quote scopes at the existing21H2R42W constructor envelope.
  // This quotes observer DATA only: no represented schema, String, Graph,
  // hashing buffer, permission or physical allocation is constructed here.
  carrier_units(
    @shape.collection_construction_extent({
      records: 110L + 24L * 21L,
      record_references: 117L + 24L * 2L,
      record_words: 265L + 24L * 42L,
      reference_arrays: 4L,
      reference_items: 24L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: entries,
    }).unwrap(),
  )
}

///|
/// Original occurrence counts, including unused schemas and the distinct
/// SourceView alias holders. Only the actual referenced facts survive return.
/// This quantity observation is neither a grammar pass nor current authority.
pub fn observe_protocol_carrier_construction(
  modes : SourceReadModes,
) -> ProtocolCarrierConstructionInventory {
  let refs = modes.shapes.values.policies.references
  let z = carrier_units({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  })
  let g = CarrierConstructionObservation::{
    retained: z,
    scratch: z,
    all_facts: { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, },
    held_facts: { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, },
    schemas: 0,
    facts: 0,
    bindings: 0,
    max_fields: 0,
    max_fact_nodes: 0,
    max_fact_fields: 0,
    work: 1L,
  }
  let needed : Map[String, Bool] = Map([])
  for reference in refs.references {
    g.work += 1L
    if reference.contract.kind != "carrier_schema" {
      continue
    }
    g.bindings += 1
    let root = member_body(reference.item)
    if carrier_metadata_child(root, "output", g) is Some(output) {
      // Both original ObjectViews coexist while binding the SourceView.
      g.max_fields = Int::max(
        g.max_fields,
        @decode.object_length(root).unwrap_or(0) +
        @decode.object_length(output).unwrap_or(0),
      )
      if carrier_metadata_child(output, "facts", g) is Some(facts) {
        if catalog_reference_for_cursor(refs, facts) is Some(original) {
          needed[original.contract.cid] = true
        }
      }
    }
  }
  for envelope in refs.contents.registry.entries {
    g.work += 1L
    if envelope.kind == "carrier_schema" {
      g.schemas += 1
      carrier_metadata_body(
        envelope.body,
        contract_body_node_count(envelope),
        g,
      )
    } else if envelope.kind == "carrier_facts" {
      g.facts += 1
      carrier_metadata_facts(envelope.body, needed.contains(envelope.cid), g)
    }
  }
  let s = g.schemas.to_int64()
  let b = g.bindings.to_int64()
  let roots = @shape.collection_construction_extent({
    records: 1L + 4L * s + 5L * b,
    record_references: 4L + 8L * s + 12L * b,
    record_words: 3L + s,
    reference_arrays: 1L,
    reference_items: s,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 2L,
    map_entries: s + b,
  }).unwrap()
  g.retained = carrier_add_units(
    g.retained,
    carrier_add_units(
      carrier_units(roots, text=71L * s),
      carrier_units(g.held_facts),
    ),
  )
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  let f = g.max_fact_nodes.to_int64()
  let caller = @shape.collection_construction_extent({
    records: 42L +
    9L * child.record_headers +
    4L * field.record_headers +
    4L * f,
    record_references: 38L +
    9L * child.reference_slots +
    4L * field.reference_slots +
    6L * f,
    record_words: 34L +
    9L * child.scalar_words +
    4L * field.scalar_words +
    4L * f,
    reference_arrays: 5L,
    reference_items: 4L * f + 24L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 7L,
    map_entries: g.facts.to_int64() +
    g.max_fields.to_int64() +
    2L * g.max_fact_fields.to_int64() +
    f,
  }).unwrap()
  // All facts remain in the original reader's two Maps until that frame
  // returns. Unreferenced facts then retire; do not report them as held output.
  let unused : @shape.CollectionConstructionExtent = {
    record_headers: g.all_facts.record_headers - g.held_facts.record_headers,
    reference_slots: g.all_facts.reference_slots - g.held_facts.reference_slots,
    scalar_words: g.all_facts.scalar_words - g.held_facts.scalar_words,
  }
  {
    retained: g.retained,
    scratch: carrier_add_units(
      g.scratch,
      carrier_units(
        @shape.add_collection_construction_extents(caller, unused).unwrap(),
      ),
    ),
    schemas: g.schemas,
    bindings: g.bindings,
    work: g.work,
  }
}

///|
pub fn protocol_carrier_construction_extent(
  value : ProtocolCarrierConstructionInventory,
) -> RegistryConstructionExtent {
  carrier_add_units(value.retained, value.scratch)
}

///|
pub fn protocol_carrier_retained_extent(
  value : ProtocolCarrierConstructionInventory,
) -> RegistryConstructionExtent {
  value.retained
}
