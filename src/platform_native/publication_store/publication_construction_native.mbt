///|
// Native caller carriers, independent of the Core validator scaffold. The
// initial scalar C entry funds these before the closure/Ref is constructed:
// callback and captures, failure Ref/Some, demand/result/phase/error carriers,
// fixed ABI geometry/result tuples, and index measurement/return controls.
// Count both ref/scalar alternatives conservatively: H32/R48/W64 = 1408B.
let publication_read_caller_bytes : Int64 = 1408L

///|
// Closed quote-evaluator SUM, not the forests described by the quote:
// 13 collection quote expansions+9-word inputs: H286/R26/W663;
// 5 expanded add_extents: H25/R5/W50; Source key/map/decoded: H14/R3/W29;
// 2 canonical NFC-zero/results: H20/R10/W48; outer writer/geometry/options:
// H25/R15/W46; cost/check arithmetic: H28/R0/W68; carried packets/arguments:
// H32/R32/W64. Sum H430/R91/W968; conservative closed H448/R128/W1024.
// Scalar C prepay selects this SAME packet before evaluating the first recipe.
let publication_index_quotation_bytes : Int64 = 16384L

///|
fn Store::check_original_commit_in_read(
  self : Store,
  capture : @local.ClientProgramCapture,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  bindings : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  index : @publication.PublicationContract,
) -> Result[Unit, NativePublicationStoreIssue] {
  let selected = match self.operation_original {
    None => None
    Some(original) => {
      if !self.operation_body_active ||
        !self.database.matches_original_store_operation(original) {
        return Err(InvalidConfiguration)
      }
      match original.has_publication_constructor() {
        Err(issue) => return Err(Database(issue))
        Ok(false) => None
        Ok(true) => Some(original)
      }
    }
  }
  guard selected is Some(original) else {
    return @local.check_program_commit_validation(
      capture, run_definition, invocation, definitions, artifacts, derivations, orderings,
      retentions, bindings, manifest, receipt, captured_run, request, attempt, index,
    ).map_err(issue => PublicationPreparation(issue))
  }
  match original.prepare_publication_scaffold() {
    Err(issue) => return Err(Database(issue))
    Ok(_) => ()
  }
  // Retain the precise Native routing failure independently of Core's
  // abstract callback refusal. The receiver also keeps its original primary.
  let native_failure : Ref[@sqlite.NativeSqliteIssue?] = Ref(None)
  let result = @local.check_program_commit_validation_in_read(
    capture,
    run_definition,
    invocation,
    definitions,
    artifacts,
    derivations,
    orderings,
    retentions,
    bindings,
    manifest,
    receipt,
    captured_run,
    request,
    attempt,
    index,
    demand => {
      guard demand.retained_bytes >= 0L &&
        demand.execution_bytes >= 0L &&
        demand.copied_slots >= 0 &&
        demand.copied_arrays >= 0 &&
        demand.metadata_nodes >= 0 &&
        @execution.checked_preparation_add_product(
          publication_read_caller_bytes,
          demand.retained_bytes,
          1L,
        )
        is Some(r) &&
        @execution.checked_preparation_add_product(
          publication_read_caller_bytes,
          demand.execution_bytes,
          1L,
        )
        is Some(e) else {
        return Err(@local.Owner(@local.Policy))
      }
      // The actual copied plan supplies these counts. No caller arrays or
      // captured rows are independently rescanned or priced as metadata.
      let block = @sqlite.publication_construction_block_bound(
        demand.copied_slots,
        demand.metadata_nodes,
        0,
      )
      if block < 1L {
        return Err(@local.Owner(@local.Policy))
      }
      match original.prepare_publication_construction(r, e, block, false) {
        Ok(_) => Ok(())
        Err(issue) => {
          if native_failure.val is None {
            native_failure.val = Some(issue)
          }
          Err(@local.Owner(@local.Policy))
        }
      }
    },
  )
  match native_failure.val {
    Some(issue) => Err(Database(issue))
    None => result.map_err(issue => PublicationPreparation(issue))
  }
}

///|
fn publication_index_inventory_cost(
  value : @publication.EffectPreviewIdentityConstructionInventory,
) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: value.owned_utf16_units,
    owned_wire_bytes: value.owned_wire_bytes,
  })
}

///|
// Prefix before fact selection, sorted binding-vector construction or Writer.
// The seven contract-kind pairs/five reference triples and returned fact
// record are closed. Binding identities are borrowed; their growing/sort
// vectors remain per-occurrence. No namespace/String copy is made here.
fn publication_index_measurement_cost(bindings : Int) -> Int64? {
  guard bindings >= 0 &&
    @shape.collection_construction_extent({
      records: 7L + 5L + 1L,
      record_references: 14L + 15L + 3L,
      record_words: 0L,
      reference_arrays: 4L,
      reference_items: 12L + 4L * bindings.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(facts) &&
    @encode.measuring_writer_construction_extent(12, 3) is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: facts.record_headers + writer.record_headers,
      reference_slots: facts.reference_slots + writer.reference_slots,
      scalar_words: facts.scalar_words + writer.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(cost) else {
    return None
  }
  @execution.checked_preparation_add_product(
    publication_read_caller_bytes + publication_index_quotation_bytes,
    cost,
    1L,
  )
}

///|
/// Index construction stays inside one existing original Read flight. This
/// returns the original issuance result separately from Native routing/funding
/// errors. The callback is a constructor duty, never commit authorization.
pub fn Store::issue_public_index_entry_in_original_read(
  self : Store,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  bindings : Array[@publication.PublicationContract],
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  committed_at : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Result[
    @publication.PublicationContract,
    @publication.PublicationCommitIssuanceIssue,
  ],
  NativePublicationStoreIssue,
] {
  // No new callback or owned vector precedes this original's first funding.
  guard self.operation_original is Some(original) else {
    return Ok(
      @publication.issue_public_index_entry(
        run_definition, invocation, manifest, receipt, captured_run, bindings, request,
        attempt, committed_at, max_bytes, max_nodes, max_depth,
      ),
    )
  }
  if self.closed {
    return Err(Closed)
  }
  if self.retiring ||
    self.operation_body_active ||
    self.operation_return_pending ||
    self.pending_result_delivery is Some(_) {
    return Err(CleanupPending)
  }
  match original.enter_store() {
    Err(issue) => return Err(Database(issue))
    Ok(_) => ()
  }
  self.operation_body_active = true
  let result = self.issue_public_index_entry_in_scope(
    original, run_definition, invocation, manifest, receipt, captured_run, bindings,
    request, attempt, committed_at, max_bytes, max_nodes, max_depth,
  )
  self.operation_body_active = false
  self.complete_original_return(original, result)
}

///|
fn Store::issue_public_index_entry_in_scope(
  self : Store,
  original : @sqlite.NativeStoreOperationOriginal,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  bindings : Array[@publication.PublicationContract],
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  committed_at : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Result[
    @publication.PublicationContract,
    @publication.PublicationCommitIssuanceIssue,
  ],
  NativePublicationStoreIssue,
] {
  if !self.database.matches_original_store_operation(original) {
    return Err(InvalidConfiguration)
  }
  let selected = match original.has_publication_constructor() {
    Err(issue) => return Err(Database(issue))
    Ok(value) => value
  }
  if selected {
    match original.prepare_publication_scaffold(index=true) {
      Err(issue) => return Err(Database(issue))
      Ok(_) => ()
    }
    let count = bindings.length()
    guard publication_index_measurement_cost(count) is Some(prefix) else {
      return Err(InvalidConfiguration)
    }
    let raw = @sqlite.publication_construction_block_bound(count, 16, 0)
    match
      original.prepare_publication_construction(prefix, prefix, raw, false) {
      Err(issue) => return Err(Database(issue))
      Ok(_) => ()
    }
    if bindings.length() > count {
      return Err(InvalidConfiguration)
    }
    let geometry = match
      @publication.public_index_entry_construction_geometry(
        run_definition, invocation, manifest, receipt, captured_run, bindings, request,
        attempt, committed_at, max_bytes, max_nodes, max_depth,
      ) {
      Err(issue) => return Ok(Err(issue))
      Ok(value) => value
    }
    guard @publication.publication_wire_construction_inventory(geometry)
      is Some((retained, codec)) &&
      publication_index_inventory_cost(retained) is Some(r) &&
      publication_index_inventory_cost(codec) is Some(w) &&
      @encode.text_writer_live_key_inventory(geometry.bytes, 12, geometry.depth)
      is Some(writer) &&
      @execution.preparation_representation_cost({
        record_headers: writer.record_headers,
        reference_slots: writer.reference_slots,
        scalar_words: writer.scalar_words,
        owned_utf16_units: writer.owned_utf16_units,
        owned_wire_bytes: 0L,
      })
      is Some(writer_cost) &&
      @execution.checked_preparation_add_product(prefix, r, 1L) is Some(e) &&
      @execution.checked_preparation_add_product(e, w, 1L) is Some(e) &&
      @execution.checked_preparation_add_product(e, writer_cost, 1L) is Some(e) else {
      return Err(InvalidConfiguration)
    }
    let raw = @sqlite.publication_construction_block_bound(
      count,
      geometry.nodes,
      geometry.bytes,
    )
    match original.prepare_publication_construction(r, e, raw, true) {
      Err(issue) => return Err(Database(issue))
      Ok(_) => ()
    }
    if bindings.length() > count {
      return Err(InvalidConfiguration)
    }
  }
  Ok(
    @publication.issue_public_index_entry(
      run_definition, invocation, manifest, receipt, captured_run, bindings, request,
      attempt, committed_at, max_bytes, max_nodes, max_depth,
    ),
  )
}
