///|
// Price the actual immutable Catalog member observations performed by
// prepare_row_input_acquisition. Every candidate may be inspected; a selected
// Source cannot use the number of allowed keys to clip malformed body width.
// The original member/tree/String payloads are borrowed, never copied here.
fn request_whole_source_member_construction_bytes(
  original : @sourceviews.SourceAcquisition,
) -> Int64? {
  let selected = @sourceviews.mode_input(
    @sourceviews.source_acquisition_mode(original),
  )
  let environment = @environment.member_environment(
    @environment.source_request_member(@sourceviews.selected_contract(selected)),
  )
  let mut bytes = 0L
  for
    section in [
      @environment.SchemaSnapshots,
      @environment.ConnectorCapabilities,
    ] {
    let count = @environment.member_count(environment, section)
    for index in 0..<count {
      guard @environment.member_at(environment, section, index) is Some(item) else {
        return None
      }
      let body = @environment.member_body(item)
      let (depth, _) = @decode.observe_cursor_path_depth(body)
      let (_, nodes, _) = @environment.member_emission_geometry(item)
      guard depth >= 0 &&
        nodes >= 0 &&
        @decode.open_object_construction_extent(
          @decode.object_length(body).unwrap_or(0),
        )
        is Some(opened) &&
        @decode.closed_object_construction_extent(body, 5, depth)
        is Some(closed) &&
        @decode.issue_path_construction_extent(depth.to_int64() + 1L)
        is Some(issue) &&
        @shape.collection_construction_extent({
          // select_evidence_member: up to four independent open_object
          // calls, three expected-field pairs and their original iterators.
          // capabilities: allowed-name Array, retained CID Array and every
          // indexed element's Cursor/Result/Option/refusal alternative.
          records: 18L + 4L * nodes.to_int64(),
          record_references: 28L + 4L * nodes.to_int64(),
          record_words: 20L + 3L * nodes.to_int64(),
          reference_arrays: 3L,
          reference_items: 3L + 5L + nodes.to_int64(),
          scalar_arrays: 0L,
          scalar_items: 0L,
          maps: 0L,
          map_entries: 0L,
        })
        is Some(caller) &&
        @execution.preparation_representation_cost({
          // Co-count snapshot and capability alternatives; this is an upper
          // bound on the same real member traversal, not another tree parse.
          record_headers: 4L * opened.record_headers +
          closed.record_headers +
          issue.record_headers +
          caller.record_headers,
          reference_slots: 4L * opened.reference_slots +
          closed.reference_slots +
          issue.reference_slots +
          caller.reference_slots,
          scalar_words: 4L * opened.scalar_words +
          closed.scalar_words +
          issue.scalar_words +
          caller.scalar_words,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        })
        is Some(member_bytes) &&
        @execution.checked_preparation_add_product(bytes, member_bytes, 1L)
        is Some(next) else {
        return None
      }
      bytes = next
      if section == @environment.SchemaSnapshots {
        let selector = @environment.connector_source_snapshot_selector_construction(
          item,
        )
        guard @execution.preparation_representation_cost({
            record_headers: selector.record_headers,
            reference_slots: selector.reference_slots,
            scalar_words: selector.scalar_words,
            owned_utf16_units: 0L,
            owned_wire_bytes: 0L,
          })
          is Some(selector_bytes) &&
          @execution.checked_preparation_add_product(bytes, selector_bytes, 1L)
          is Some(next) else {
          return None
        }
        bytes = next
      }
    }
  }
  Some(bytes)
}

///|
// Actual RowInputPreparation/capability-choice and Whole-capacity constructors.
// Full-sequence/AST/schema/Plan payloads keep their original Plan-input debit;
// this term adds the new borrowed controls and owned column spelling only.
fn request_whole_source_input_construction_bytes(
  original : @sourceviews.SourceAcquisition,
) -> Int64? {
  guard @pipeline.schema_at(
      @sourceviews.source_acquisition_pipeline(original),
      @sourceviews.source_acquisition_input(original),
    )
    is Some(schema) else {
    return None
  }
  let fields = @schema.field_count(schema).to_int64()
  let names = @schema.field_reference_name_bytes(schema).to_int64()
  guard request_whole_source_member_construction_bytes(original)
    is Some(members) &&
    @shape.collection_construction_extent({
      // RowInputPreparation H1/R13/W1, RowInputAcquisition H1/R3,
      // facts/selector/member carriers H7/R24/W4, optional limits/listing
      // H4/R5/W2, registry/owner/registration/description H4/R7/W5,
      // candidate/prepared/choice/quantity H4/R10/W3, cost/Result/Option
      // and field projection alternatives H20/R20/W24. Whole-capacity and
      // its initial quote/Result/Option add H6/R8/W8. Scalar/cursor loop
      // products for every input field are counted independently.
      records: 47L + 3L * fields,
      record_references: 90L + 3L * fields,
      record_words: 47L + 3L * fields,
      reference_arrays: 5L,
      reference_items: fields + 4L,
      scalar_arrays: 1L,
      scalar_items: 1L,
      maps: 2L,
      map_entries: 2L,
    })
    is Some(controls) &&
    @execution.preparation_representation_cost({
      record_headers: controls.record_headers + fields,
      reference_slots: controls.reference_slots,
      scalar_words: controls.scalar_words,
      // field_reference_name may construct qualified spelling. UTF8 name
      // bytes bound its UTF16 units; borrow-only flat fields still fit it.
      owned_utf16_units: names,
      owned_wire_bytes: 0L,
    })
    is Some(input) &&
    @execution.checked_preparation_add_product(members, input, 1L)
    is Some(bytes) else {
    return None
  }
  Some(bytes)
}
