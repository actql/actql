///|
fn observed_read_inventory_cost(
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
// Same fixed Native caller/evaluator prefix as its Store scaffold. The
// additional H16/R32/W32 owns observer/fence/consumer closures, Native failure
// Ref/Some, result carriers, bound/quote tuples and the accepted State carrier.
let observed_read_caller_bytes : Int64 = 2176L + 16384L

///|
fn NativeLocalHostConnection::observe_publication_in_original_read(
  self : NativeLocalHostConnection,
  publisher : NativeLocalPublisherBinding,
  authority : NativeLocalPolicyAuthority,
  pending : @native_publication.NativePreparedCapturedRunPublication,
  operation : NativeLocalStoreOperation,
  observed_at : String,
  max_workspace : Int,
  quantum : Int,
  max_rounds : Int,
) -> Result[NativeLocalObservedRunState, NativeLocalObservedRunStateIssue] {
  guard operation.bridge is Some(original) &&
    publisher.store.matches_original_operation(original) &&
    publisher.authority.capture is Some(capture) &&
    physical_equal(capture, operation.receiver.capture) else {
    return Err(ForeignOriginal)
  }
  // This scalar entrance owns the actual short Store flight and its pending
  // return duty. It requires StoreFromRead before any new closure or Ref.
  match publisher.store.prepare_run_observation_constructor_scaffold(original) {
    Err(issue) => return Err(Candidate(Publication(Store(issue))))
    Ok(_) => ()
  }
  let (bytes, nodes, depth) = pending.run_state_construction_limits()
  guard @publication.run_state_observation_construction_inventory(
      bytes, nodes, depth,
    )
    is Some((state_retained, state_workspace)) &&
    observed_read_inventory_cost(state_retained) is Some(state_r) &&
    observed_read_inventory_cost(state_workspace) is Some(state_w) &&
    @execution.checked_preparation_add_product(state_r, state_w, 1L)
    is Some(state_e) else {
    return Err(Candidate(InvalidLimits))
  }
  let state_block = @sqlite.publication_construction_block_bound(
    nodes, nodes, bytes,
  )
  if state_block < 1L {
    return Err(Candidate(InvalidLimits))
  }
  let native_failure : Ref[@publication_store.NativePublicationStoreIssue?] = Ref(
    None,
  )
  let fund = fn(demand : @local.ClientProgramValidationReadDemand) {
    guard @execution.checked_preparation_add_product(
        observed_read_caller_bytes, state_r, 1L,
      )
      is Some(base_r) &&
      @execution.checked_preparation_add_product(
        base_r,
        demand.retained_bytes,
        1L,
      )
      is Some(r) &&
      @execution.checked_preparation_add_product(
        observed_read_caller_bytes, state_e, 1L,
      )
      is Some(base_e) &&
      @execution.checked_preparation_add_product(
        base_e,
        demand.execution_bytes,
        1L,
      )
      is Some(e) else {
      return Err(@local.Owner(@local.Policy))
    }
    let block = @sqlite.publication_construction_block_bound(
      demand.copied_slots,
      demand.metadata_nodes,
      0,
    )
    if block < 1L {
      return Err(@local.Owner(@local.Policy))
    }
    match
      publisher.store.prepare_run_observation_construction(
        original,
        r,
        e,
        Int64::max(block, state_block),
      ) {
      Ok(_) => Ok(())
      Err(issue) => {
        if native_failure.val is None {
          native_failure.val = Some(issue)
        }
        Err(@local.Owner(@local.Policy))
      }
    }
  }
  let fence : () -> Result[
    Unit,
    @native_publication.NativeRunStateCandidateIssue,
  ] = fn() {
    fund({
      retained_bytes: 0L,
      execution_bytes: 0L,
      copied_slots: 0,
      copied_arrays: 0,
      metadata_nodes: 0,
      phase: @local.Fence,
    }).map_err(issue => @native_publication.Publication(Preparation(issue)))
  }
  let result = pending.with_run_state_candidate_in_read(
    observed_at,
    max_workspace,
    quantum,
    max_rounds,
    fund,
    candidate => {
      self.finalize_observed_run_state_candidate(
        publisher,
        authority,
        candidate,
        read_fence=Some(fence),
      )
    },
  )
  // A precise Native funding/return failure is never replaced by the abstract
  // Core callback refusal. The same Store retains any outstanding return duty.
  match (result, native_failure.val) {
    // The Store still owns a failed return/funding prefix. It cannot replace
    // the already observed consumer primary while the same owner cleans up.
    (Ok(Err(primary)), _) => Err(primary)
    (_, Some(issue)) => Err(Candidate(Publication(Store(issue))))
    (Err(issue), None) => Err(Candidate(issue))
    (Ok(Ok(value)), None) => Ok(value)
  }
}
