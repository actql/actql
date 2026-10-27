///|
/// Original constructor quantities only. This does not collect/admit inputs,
/// normalize text, interpret order, resolve a Catalog or issue backing.
pub(all) struct CollectionConstructionGeometry {
  stages : Int
  inputs : Int
  remotes : Int
  max_stage_fields : Int
  max_input_fields : Int
  max_remote_fields : Int
  max_remote_nodes : Int
  max_request_fields : Int
  max_meta_fields : Int
  max_scan_fields : Int
  max_duplicates_fields : Int
  max_duplicates_items : Int
  max_first_fields : Int
  normalization_calls : Int
  normalization_utf16 : Int64
  max_normalization_utf16 : Int
  order_owners : Int
  order_terms : Int
  max_order_fields : Int
  max_path_segments : Int64
  inspection_work : Int64
} derive(Eq, Debug)

///|
priv struct CollectionQuantityScan {
  mut work : Int64
}

///|
// Direct indexed fields only: no ObjectView/Map, recursive body clone or
// diagnostic path. Duplicate/wrong-kind interpretation stays with collect.
fn collection_quantity_child(
  at : @decode.Cursor,
  name : String,
  scan : CollectionQuantityScan,
) -> @decode.Cursor? {
  scan.work += 1L
  if @decode.object_length(at) is Some(n) {
    for i in 0..<n {
      scan.work += 2L
      let (key, child) = @decode.field_at(at, i).unwrap()
      if key == name {
        return Some(child)
      }
    }
  }
  None
}

///|
fn collection_quantity_fields(value : @decode.Cursor?) -> Int {
  value.map(at => @decode.object_length(at).unwrap_or(0)).unwrap_or(0)
}

///|
/// Fund inspection controls before entry. The admitted source tree owns every
/// borrowed Cursor/text. Opaque request/meta descendants contribute traversal
/// nodes only; NFC dimensions select connector/resource/view text exclusively.
pub fn observe_collect_construction_geometry(
  source : @stages.Source,
  limits : Limits,
) -> CollectionConstructionGeometry {
  let scan : CollectionQuantityScan = { work: 0L, }
  let mut stages = 0
  let mut inputs = 0
  let mut remotes = 0
  let mut stage_fields = 0
  let mut input_fields = 0
  let mut remote_fields = 0
  let mut remote_nodes = 0
  let mut request_fields = 0
  let mut meta_fields = 0
  let mut scan_fields = 0
  let mut duplicates_fields = 0
  let mut duplicates_items = 0
  let mut first_fields = 0
  let mut normalization_calls = 0
  let mut normalization_utf16 = 0L
  let mut normalization_max = 0
  let mut order_owners = 0
  let mut order_terms = 0
  let mut order_fields = 0
  let mut path_segments = 0L
  if !collection_limits_invalid(limits) {
    stages = @stages.stage_count(source)
    let (root_depth, ancestry) = @decode.observe_cursor_path_depth(
      @stages.source_body(source),
    )
    scan.work += ancestry
    // The same Envelope owns every Stage at stages/index. Observe the shared
    // original root ancestry once rather than walking it for every input.
    if stages > 0 {
      path_segments = root_depth.to_int64() + 3L
    }
    for s in 0..<stages {
      scan.work += 1L
      let stage = @stages.stage_at(source, s).unwrap()
      let root = @stage.stage_body(stage)
      stage_fields = Int::max(
        stage_fields,
        @decode.object_length(root).unwrap_or(0),
      )
      if collection_quantity_child(root, "inputs", scan) is Some(slots) {
        let n = @decode.object_length(slots).unwrap_or(0)
        inputs += n
        for i in 0..<n {
          scan.work += 2L
          let (_, at) = @decode.field_at(slots, i).unwrap()
          let fields = @decode.object_length(at).unwrap_or(0)
          input_fields = Int::max(input_fields, fields)
          if collection_quantity_child(at, "connector", scan) is Some(_) ||
            collection_quantity_child(at, "resource", scan) is Some(_) {
            remotes += 1
            remote_fields = Int::max(remote_fields, fields)
            let geometry = @decode.observe_subtree_construction_geometry(at)
            scan.work += geometry.work
            remote_nodes = Int::max(remote_nodes, geometry.nodes)
            // root/stages/index/inputs/name, then at most duplicates/
            // first_by_order/order_by/index/field. Opaque descendants are not
            // decoded. A shared source root avoids repeated ancestry walks.
            path_segments = root_depth.to_int64() + 9L
            for name in ["connector", "resource", "view"] {
              if collection_quantity_child(at, name, scan) is Some(value) &&
                @decode.is_text(value) {
                scan.work += 1L
                let size = @decode.text(value).unwrap().length()
                if size > 0 {
                  normalization_calls += 1
                  normalization_utf16 += size.to_int64()
                  normalization_max = Int::max(normalization_max, size)
                }
              }
            }
            request_fields = Int::max(
              request_fields,
              collection_quantity_fields(
                collection_quantity_child(at, "request", scan),
              ),
            )
            meta_fields = Int::max(
              meta_fields,
              collection_quantity_fields(
                collection_quantity_child(at, "meta", scan),
              ),
            )
            scan_fields = Int::max(
              scan_fields,
              collection_quantity_fields(
                collection_quantity_child(at, "scan", scan),
              ),
            )
            if collection_quantity_child(at, "duplicates", scan)
              is Some(duplicates) {
              duplicates_items = Int::max(
                duplicates_items,
                @decode.array_length(duplicates).unwrap_or(0),
              )
              duplicates_fields = Int::max(
                duplicates_fields,
                @decode.object_length(duplicates).unwrap_or(0),
              )
              if collection_quantity_child(duplicates, "first_by_order", scan)
                is Some(first) {
                first_fields = Int::max(
                  first_fields,
                  @decode.object_length(first).unwrap_or(0),
                )
                if collection_quantity_child(first, "order_by", scan)
                  is Some(terms) {
                  let n = @decode.array_length(terms).unwrap_or(0)
                  if n > 0 {
                    order_owners += 1
                    order_terms += n
                    for j in 0..<n {
                      scan.work += 2L
                      let term = @decode.element_at(terms, j).unwrap()
                      order_fields = Int::max(
                        order_fields,
                        @decode.object_length(term).unwrap_or(0),
                      )
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  {
    stages,
    inputs,
    remotes,
    max_stage_fields: stage_fields,
    max_input_fields: input_fields,
    max_remote_fields: remote_fields,
    max_remote_nodes: remote_nodes,
    max_request_fields: request_fields,
    max_meta_fields: meta_fields,
    max_scan_fields: scan_fields,
    max_duplicates_fields: duplicates_fields,
    max_duplicates_items: duplicates_items,
    max_first_fields: first_fields,
    normalization_calls,
    normalization_utf16,
    max_normalization_utf16: normalization_max,
    order_owners,
    order_terms,
    max_order_fields: order_fields,
    max_path_segments: path_segments,
    inspection_work: scan.work,
  }
}

///|
/// Same contiguous original node/field counts bound all fixed indexed probes
/// plus the one subtree observation. This is metadata work, not a row policy.
pub fn collect_construction_inspection_bound(source : @stages.Source) -> Int64 {
  // Each original Object receives at most nine named probes. Each probe
  // costs one call plus two visits per original field. Remote subtrees are
  // disjoint: their spine/node/field walk costs at most3N. Stage/input loops
  // cost at most3N, scalar/order loops3N, and shared root ancestry at mostN.
  let probes = 9L + 2L * 9L
  let subtree = 3L
  let stage_inputs = 3L
  let scalar_order = 3L
  let ancestry = 1L
  1L +
  (probes + subtree + stage_inputs + scalar_order + ancestry) *
  @decode.admission_usage(@stages.source_body(source)).nodes.to_int64()
}

///|
/// Fixed scalar scan/result, at most eight live original field/child frames,
/// one admitted subtree geometry and ancestry tuple, scalar Option/results,
/// and the three literal normalization selector slots. No input-sized Map or
/// detached Cursor array is allocated by this metadata observation.
pub fn collect_construction_inspection_extent() -> @shape.CollectionConstructionExtent {
  let field = @decode.indexed_field_construction_extent()
  @shape.collection_construction_extent({
    records: 2L + 8L * (field.record_headers + 1L) + 1L + 1L + 12L,
    record_references: 8L * (field.reference_slots + 1L) + 12L,
    record_words: 22L + 8L * (field.scalar_words + 1L) + 11L + 2L + 12L,
    reference_arrays: 1L,
    reference_items: 3L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
}
