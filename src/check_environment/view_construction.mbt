///|
// The original mode reader and metadata observer share their actual field names.
let source_modes_acquisition_key : String = "acquisition"

///|
let source_modes_list_key : String = "modes"

///|
let view_metadata_text_fields : Array[String] = []

///|
/// Actual original SourceView occurrences, not unique CIDs or policy maxima.
/// Shapes and mode outputs coexist. Their two original reader frames do not.
pub(all) struct ProtocolViewConstructionInventory {
  shape_retained : @shape.CollectionConstructionExtent
  shape_scratch : @shape.CollectionConstructionExtent
  mode_retained : @shape.CollectionConstructionExtent
  mode_scratch : @shape.CollectionConstructionExtent
  views : Int
  modes : Int64
  work : Int64
} derive(Eq, Debug)

///|
priv struct ViewInspectionMeter {
  mut work : Int64
}

///|
// Structural metadata only. No ObjectView/Map, grammar check or copied body.
fn view_metadata_child(
  root : @decode.Cursor,
  key : String,
  meter : ViewInspectionMeter,
) -> @decode.Cursor? {
  meter.work += 1L
  if @decode.object_length(root) is Some(count) {
    for i in 0..<count {
      let (name, child) = @decode.field_at(root, i).unwrap()
      meter.work += 2L
      if name == key {
        return Some(child)
      }
    }
  }
  None
}

///|
pub fn protocol_view_construction_inspection_bound(
  values : ProtocolValueContracts,
) -> Int64 {
  let contents = values.policies.references.contents
  let environment = contents.registry.environment
  let mut nodes = 0L
  for item in environment.sections[position(SourceViews)] {
    nodes += item.nodes.to_int64()
  }
  // Original cached SourceView member sizes, not contract-registry sizes.
  // Catalog closure already binds every selected view to its original member.
  1L + 16L * nodes + 10L * contents.entries.length().to_int64()
}

///|
pub fn observe_protocol_view_construction(
  values : ProtocolValueContracts,
) -> ProtocolViewConstructionInventory {
  let meter = ViewInspectionMeter::{ work: 1L, }
  let mut views = 0
  let mut modes = 0L
  let mut max_nodes = 0L
  let mut max_fields = 0L
  let mut max_items = 0L
  let mut max_path = 0L
  let mut max_root_fields = 0L
  let mut max_acquisition_fields = 0L
  let mut max_mode_fields = 0L
  let mut max_modes = 0L
  for catalog in values.policies.references.contents.entries {
    meter.work += 1L
    for item in catalog.views {
      meter.work += 1L
      views += 1
      let root = member_body(item)
      let g = @decode.observe_subtree_geometry(root, view_metadata_text_fields)
      meter.work += g.work
      max_nodes = Int64::max(max_nodes, g.nodes.to_int64())
      max_fields = Int64::max(max_fields, g.max_fields.to_int64())
      max_items = Int64::max(max_items, g.max_array_items.to_int64())
      max_path = Int64::max(
        max_path,
        g.nodes.to_int64() + g.outer_depth.to_int64(),
      )
      max_root_fields = Int64::max(
        max_root_fields,
        @decode.object_length(root).unwrap_or(0).to_int64(),
      )
      if view_metadata_child(root, source_modes_acquisition_key, meter)
        is Some(acquisition) {
        max_acquisition_fields = Int64::max(
          max_acquisition_fields,
          @decode.object_length(acquisition).unwrap_or(0).to_int64(),
        )
        if view_metadata_child(acquisition, source_modes_list_key, meter)
          is Some(list) {
          let count = @decode.array_length(list).unwrap_or(0)
          modes += count.to_int64()
          max_modes = Int64::max(max_modes, count.to_int64())
          for i in 0..<count {
            meter.work += 2L
            let mode = @decode.element_at(list, i).unwrap()
            max_mode_fields = Int64::max(
              max_mode_fields,
              @decode.object_length(mode).unwrap_or(0).to_int64(),
            )
          }
        }
      }
    }
  }
  let v = views.to_int64()
  let shape_retained = @shape.collection_construction_extent({
    records: 1L,
    record_references: 2L,
    record_words: 1L,
    reference_arrays: 1L,
    reference_items: v,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  let shape_scratch = @shape.add_collection_construction_extents(
    source_view_shape_frame_construction(
      max_nodes,
      max_fields,
      max_items,
      max_path,
      views > 0,
    ),
    source_view_rule_construction(),
  ).unwrap()
  // Each actual mode is a fresh typed record; its selected default is the
  // SAME record, not another copy. Original Members and Strings stay borrowed.
  let mode_retained = @shape.collection_construction_extent({
    records: 1L + v + modes,
    record_references: 3L + 3L * v + modes,
    record_words: 1L + 2L * modes,
    reference_arrays: 1L + v,
    reference_items: v + modes,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: v,
  }).unwrap()
  // One original root/acquisition/current-mode ObjectView plus duplicate-name
  // Map coexist. Previous view workspaces return before the next view reader.
  // Fixed24H20R18W: budget1/0/1, views3/6/0, typed/selected/tuple8/10/8,
  // scalar/control12/4/9; three field sites and nine shared child sites.
  let mode_scratch = @shape.collection_construction_extent({
    records: 24L + 3L * field.record_headers + 9L * child.record_headers,
    record_references: 20L +
    3L * field.reference_slots +
    9L * child.reference_slots,
    record_words: 18L + 3L * field.scalar_words + 9L * child.scalar_words,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: if views > 0 {
      4L
    } else {
      0L
    },
    map_entries: max_root_fields +
    max_acquisition_fields +
    max_mode_fields +
    max_modes,
  }).unwrap()
  {
    shape_retained,
    shape_scratch,
    mode_retained,
    mode_scratch,
    views,
    modes,
    work: meter.work,
  }
}

///|
pub fn protocol_view_construction_extent(
  v : ProtocolViewConstructionInventory,
) -> RegistryConstructionExtent {
  let mode = @shape.add_collection_construction_extents(
    v.mode_retained,
    v.mode_scratch,
  ).unwrap()
  let peak = @shape.add_collection_construction_extents(v.shape_retained, {
    record_headers: Int64::max(
      v.shape_scratch.record_headers,
      mode.record_headers,
    ),
    reference_slots: Int64::max(
      v.shape_scratch.reference_slots,
      mode.reference_slots,
    ),
    scalar_words: Int64::max(v.shape_scratch.scalar_words, mode.scalar_words),
  }).unwrap()
  {
    record_headers: peak.record_headers,
    reference_slots: peak.reference_slots,
    scalar_words: peak.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
pub fn protocol_view_retained_extent(
  v : ProtocolViewConstructionInventory,
) -> RegistryConstructionExtent {
  let held = @shape.add_collection_construction_extents(
    v.shape_retained,
    v.mode_retained,
  ).unwrap()
  {
    record_headers: held.record_headers,
    reference_slots: held.reference_slots,
    scalar_words: held.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}
