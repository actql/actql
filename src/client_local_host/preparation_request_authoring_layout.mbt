///|
/// Closed fixed authoring control group, admitted separately on the SAME
/// Request before inspection/state/work constructors. It is not codec-sized.
/// Controller/baseline/quote/Some/result carriers <=17H/21R/41W; original
/// WorkContinuation/state/closures <=16H/26R/23W; indexed observer, fixed
/// field tables, Cursor/tuple/Option returns <=32H/48R/64W. The co-held guarded
/// arithmetic/current/grow return carriers close the bound at80H/128R/160W.
/// Payload-bearing Some includes its tag word. No variable path/meta is here.
fn request_authoring_control_bytes() -> Int64 {
  @execution.preparation_representation_cost({
    record_headers: 80L,
    reference_slots: 128L,
    scalar_words: 160L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
/// Original collection/path/sort and two measuring passes. Actual annotation
/// count/path text and metadata field/node counts come from Common's indexed
/// observer; an arbitrary caller maximum is never an allocation quantity.
fn request_authoring_collection_extents(
  value : @publication_host.ClientAuthoringCollectionGeometry,
) -> (Int64, Int64)? {
  guard value.items >= 0 &&
    value.path_utf16 >= 0L &&
    value.max_path_utf16 >= 0 &&
    value.max_quoted_key_bytes >= 0 &&
    value.meta_nodes >= 0 &&
    value.meta_nodes <= 2147483643 &&
    value.meta_fields >= 0 &&
    value.meta_fields <= 2147483643 &&
    value.source_depth >= 0 &&
    value.source_depth <= 2147483643 &&
    closed_values_append_capacity(value.items) is Some(capacity) &&
    closed_values_sort_scratch_layout(Int::max(1, value.items)) is Some(sort) &&
    @encode.text_writer_construction_inventory(value.max_quoted_key_bytes, 1, 0)
    is Some(path_writer) &&
    @encode.measuring_writer_construction_extent(
      value.meta_fields + 4,
      Int::min(value.source_depth, value.meta_nodes) + 4,
    )
    is Some(measure) &&
    @encode.text_writer_live_key_inventory(0, 0, 0) is Some(initial_writer) else {
    return None
  }
  let n = value.items.to_int64()
  // Growing vector3H/13+3capacity R/2W; each item record1H/4R,
  // optional name1H/1R/1W, borrowed Cursor1H/3R/1W, owned path String
  // 1H/1R/1W. Prepared original/result/Some controls are independently coheld.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 8L + 4L * n,
    reference_slots: 21L + 3L * capacity + 9L * n,
    scalar_words: 9L + 3L * n,
    owned_utf16_units: value.path_utf16,
    owned_wire_bytes: 0L,
  }
  // Six co-held concat spans bound old/new stage/field/key paths; input
  // names remain borrowed. Two quoted-key Writers conservatively co-count
  // sequential helper calls. EmitWork keeps two depth-sized alternatives,
  // each with Cursor/tag/index and growing-vector backing. Metadata payload
  // itself is never cloned into the collection.
  let depth = Int::min(value.source_depth, value.meta_nodes).to_int64() + 4L
  let traversal : @execution.PreparationRepresentationUnits = {
    record_headers: 12L + 8L * depth,
    reference_slots: 24L + 18L * depth,
    scalar_words: 24L + 12L * depth,
    owned_utf16_units: 6L * value.max_path_utf16.to_int64() + 20L,
    owned_wire_bytes: 0L,
  }
  let paths : @execution.PreparationRepresentationUnits = {
    record_headers: path_writer.record_headers * 2L,
    reference_slots: path_writer.reference_slots * 2L,
    scalar_words: path_writer.scalar_words * 2L,
    owned_utf16_units: path_writer.owned_utf16_units * 2L,
    owned_wire_bytes: 0L,
  }
  // ConstructionGeometry adds one sink state per measuring Writer; both
  // returned geometry records stay in the separately admitted fixed group.
  let measuring : @execution.PreparationRepresentationUnits = {
    record_headers: measure.record_headers * 2L + 4L,
    reference_slots: measure.reference_slots * 2L + 2L,
    scalar_words: measure.scalar_words * 2L + 12L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // The original output Writer is already retained, but still empty during
  // measurement. Its initial object/builder/backing remain separate from the
  // sequential quoted-key Writer and future full body/complete output.
  let initial : @execution.PreparationRepresentationUnits = {
    record_headers: initial_writer.record_headers,
    reference_slots: initial_writer.reference_slots,
    scalar_words: initial_writer.scalar_words,
    owned_utf16_units: initial_writer.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([retained, initial])
    is Some(retained) &&
    @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.compose_preparation_representation([
      retained, sort, traversal, paths, measuring,
    ])
    is Some(execution) &&
    @execution.preparation_representation_cost(execution) is Some(e) else {
    return None
  }
  Some((r, e))
}
