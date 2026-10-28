///|
/// Original resolver constructor quantities only. A metadata prefix which
/// cannot construct a later view/input under the original minimum charges is
/// not inspected. This is not semantic selection, a partial Resolved or Allow.
pub(all) struct ResolutionConstructionGeometry {
  inputs : Int
  views : Int
  inherited_work : Int
  candidate_inputs : Int
  candidate_views : Int
  max_view_fields : Int
  max_declaration_fields : Int
  identity_utf16 : Int64
  max_identity_utf16 : Int
  max_connector_utf16 : Int
  max_view_utf16 : Int
  reference_utf16 : Int64
  max_reference_utf16 : Int
  inspection_work : Int64
} derive(Eq, Debug)

///|
priv struct ResolutionQuantityScan {
  mut visits : Int64
}

///|
// Indexed fields from the original admitted Catalog: no ObjectView/Map, NFC,
// subtree copy or permission inference. The original reader remains final.
fn resolution_quantity_text_size(
  root : @decode.Cursor,
  name : String,
  scan : ResolutionQuantityScan,
) -> Int {
  scan.visits += 1L
  for i in 0..<@decode.object_length(root).unwrap() {
    scan.visits += 2L
    let (key, value) = @decode.field_at(root, i).unwrap()
    if key == name {
      return @decode.text(value).unwrap().length()
    }
  }
  abort("original checked SourceView retains its required identity field")
}

///|
/// Fund the fixed metadata frame before entry. Each visited Catalog root uses
/// its actual original field count. The original resolver charges fields+1
/// BEFORE its Map or identity construction; omitting later semantic costs here
/// only enlarges the potential constructor prefix, never admits an input.
pub fn observe_resolution_construction_geometry(
  inputs : @inputs.Inputs,
  catalog : @environment.SourceRequestContracts,
  limits : Limits,
) -> ResolutionConstructionGeometry {
  let scan = ResolutionQuantityScan::{ visits: 0L, }
  let mut input_count = 0
  let mut view_count = 0
  let mut inherited = 0
  let mut candidate_inputs = 0
  let mut candidate_views = 0
  let mut view_fields = 0
  let mut declaration_fields = 0
  let mut identity = 0L
  let mut max_identity = 0
  let mut max_connector = 0
  let mut max_view = 0
  let mut references = 0L
  let mut max_reference = 0
  if !resolution_limits_invalid(limits) {
    input_count = @inputs.count(inputs)
    view_count = @environment.source_request_usage(catalog).2
    inherited = @inputs.work(inputs)
    if input_count <= limits.max_inputs &&
      view_count <= limits.max_views &&
      inherited <= limits.max_work {
      scan.visits = 1L
      let mut remaining = limits.max_work - inherited
      let policies = @environment.value_contract_policies(
        @environment.source_view_shape_values(
          @environment.read_mode_shapes(
            @environment.carrier_schema_modes(
              @environment.source_request_carriers(catalog),
            ),
          ),
        ),
      )
      for i in 0..<view_count {
        scan.visits += 1L
        let contract = @environment.source_request_at(catalog, i).unwrap()
        let root = @environment.member_body(
          @environment.source_request_member(contract),
        )
        let fields = @decode.object_length(root).unwrap()
        if fields >= remaining {
          break
        }
        remaining -= fields + 1
        candidate_views += 1
        view_fields = Int::max(view_fields, fields)
        let connector = resolution_quantity_text_size(
          root, "connector_id", scan,
        )
        let view = resolution_quantity_text_size(root, "view_id", scan)
        let cid = resolution_quantity_text_size(root, "contract_cid", scan)
        identity += connector.to_int64() + view.to_int64() + cid.to_int64()
        max_identity = Int::max(
          max_identity,
          Int::max(connector, Int::max(view, cid)),
        )
        max_connector = Int::max(max_connector, connector)
        max_view = Int::max(max_view, view)
        scan.visits += 1L
        let policy = @environment.source_view_data_policy(
          @environment.source_view_policy(
            policies,
            @environment.source_request_member(contract),
          ).unwrap(),
        )
        let length = @environment.data_policy_source(policy).length()
        references += length.to_int64()
        max_reference = Int::max(max_reference, length)
      }
      if candidate_views == view_count {
        // One original declaration visit is charged before any selection or
        // failure-only explicit-view index. No request/meta body is inspected.
        candidate_inputs = Int::min(input_count, remaining)
        for i in 0..<candidate_inputs {
          scan.visits += 1L
          let declaration = @inputs.at(inputs, i).unwrap()
          if declaration.view is Some(_) {
            declaration_fields = Int::max(
              declaration_fields,
              @decode.object_length(declaration.source).unwrap(),
            )
          }
        }
      }
    }
  }
  {
    inputs: input_count,
    views: view_count,
    inherited_work: inherited,
    candidate_inputs,
    candidate_views,
    max_view_fields: view_fields,
    max_declaration_fields: declaration_fields,
    identity_utf16: identity,
    max_identity_utf16: max_identity,
    max_connector_utf16: max_connector,
    max_view_utf16: max_view,
    reference_utf16: references,
    max_reference_utf16: max_reference,
    inspection_work: scan.visits,
  }
}

///|
/// At most6 visits per original fields+1 minimum charge: three direct probes
/// and one root/policy visit. Input visits use the remaining minimum budget;
/// initial scalar observation and one failed next-root peek add2. The wide
/// bound allocates no proportional storage and imposes no new semantic limit.
pub fn resolution_construction_inspection_bound(
  inputs : @inputs.Inputs,
  limits : Limits,
) -> Int64 {
  if resolution_limits_invalid(limits) {
    return 0L
  }
  let inherited = @inputs.work(inputs)
  let remaining = if inherited > limits.max_work {
    0
  } else {
    limits.max_work - inherited
  }
  2L + 6L * remaining.to_int64()
}

///|
/// Fixed scan/result2H15W, Catalog usage tuple1H3W, original view/input
/// Options2H2R2W, two length Options2H4W, one indexed field frame, Text Ok
///1H1R1W and original policy lookup Some1H1R1W. The three identity names
/// are installed literal borrows; no metadata Array/Map/clone is built.
pub fn resolution_construction_inspection_extent() -> @shape.CollectionConstructionExtent {
  let field = @decode.indexed_field_construction_extent()
  @shape.collection_construction_extent({
    records: 9L + field.record_headers,
    record_references: 4L + field.reference_slots,
    record_words: 26L + field.scalar_words,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
}

///|
/// The SAME returned geometry record only. Its fourteen scalar fields own no
/// Source/tree/Catalog reference or semantic admission. The receiver binding
/// and optional-work cache belong to the actual continuation's own wrapper.
pub fn resolution_construction_geometry_extent() -> @shape.CollectionConstructionExtent {
  resolution_geometry_units
}

///|
let resolution_geometry_units : @shape.CollectionConstructionExtent = {
  record_headers: 1L,
  reference_slots: 0L,
  scalar_words: 14L,
}
