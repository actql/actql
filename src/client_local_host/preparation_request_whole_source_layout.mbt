///|
// The first Whole-domain frontier, before selecting/retaining Source originals
// or constructing Native locator/capacity/transport vectors. It is quantity
// DATA for the existing Request reservation, never a read or execution grant.
// RowInput/evidence-member construction is a separate, later observed term;
// this fixed frontier cannot be used as a substitute for that term.
fn request_whole_source_route_frontier_bytes(
  count : Int,
  scanned_inputs : Int64,
  select_query? : Bool = false,
) -> Int64? {
  if count <= 0 || scanned_inputs < count.to_int64() {
    return None
  }
  let n = count.to_int64()
  guard @execution.checked_preparation_add_product(0L, n, 5L) is Some(items) &&
    // Source originals, Native locators, Whole capacities and the two
    // transport vectors all coexist through Plan/module construction.
    @execution.preparation_array_representation(5L, items, true)
    is Some(vectors) &&
    // derive_source_acquisition visits the original pipeline input names.
    // Its three-scalar cost literal is separate from those borrowed names.
    @execution.checked_preparation_add_product(0L, scanned_inputs, 3L)
    is Some(scan_words) &&
    @shape.collection_construction_extent({
      records: 0L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: scanned_inputs,
      scalar_items: scan_words,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(scan) &&
    @execution.checked_preparation_add_product(13L, n, 18L) is Some(headers) &&
    @execution.checked_preparation_add_product(12L, n, 34L) is Some(references) &&
    @execution.checked_preparation_add_product(20L, n, 27L) is Some(words) &&
    @execution.compose_preparation_representation([
      vectors,
      {
        record_headers: scan.record_headers,
        reference_slots: scan.reference_slots,
        scalar_words: scan.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      {
        // Fixed grow/refusal/return products: H12/R8/W20 plus the Native
        // four-vector return (H1/R4). Per input, count both Source record
        // alternatives, Input target, route/Result/map and budget carriers
        // (H9/R15/W10); Native locator (H1/R6); and the four immutable
        // RowInput policy records (H4/R3/W15). Listing lookup retains its
        // three-field selection, Some and provider Some (H3/R5/W2), plus
        // the common five-field locator tuple (H1/R5). Paths remain borrowed.
        record_headers: headers,
        reference_slots: references,
        scalar_words: words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(units) else {
    return None
  }
  let cost = @execution.preparation_representation_cost(units)
  if !select_query {
    return cost
  }
  // A successful structural Query selection creates a borrowed acquisition,
  // the filter/select traversal array and selection/result carriers. Count
  // those once per original. The final kind and nullable contracts argument
  // are fixed controls; complete Query construction has its own later quote.
  guard cost is Some(base) &&
    @execution.preparation_representation_cost({
      // Also hold the temporary locator tuple (H1/R2/W2) for each input.
      record_headers: 7L + 7L * n,
      reference_slots: 10L + 14L * n,
      scalar_words: 5L + 10L * n,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(query) else {
    return None
  }
  @execution.checked_preparation_add_product(base, query, 1L)
}

///|
// Borrow only the already checked pipeline topology to bound its original
// name scan. The direct selector has its existing Plan-input backing. This
// does not derive a Query, select fallback, parse or copy a Source declaration.
fn request_whole_source_route_scan_count(
  prepared : @publication_host.PreparedClientProgram,
  direct : @publication_host.ClientDirectAcquisitionOccurrences,
) -> Int64? {
  let count = @publication_host.client_direct_acquisition_occurrence_count(
    direct,
  )
  if count <= 0 ||
    !@publication_host.client_direct_acquisition_occurrences_match_program(
      direct, prepared,
    ) {
    return None
  }
  let program = @strategy.graph_program(
    @publication_host.prepared_client_graph(prepared),
  )
  let mut scanned = 0L
  for index in 0..<count {
    guard @publication_host.client_direct_acquisition_occurrence_at(
        direct, index,
      )
      is Some((stage, _, _)) &&
      @checked.unit_pipeline(program, stage) is Some(pipeline) &&
      @execution.checked_preparation_add_product(
        scanned,
        @pipeline.input_count(pipeline).to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    scanned = next
  }
  Some(scanned)
}
