///|
/// Private capture read material on the existing Request reservation. These
/// are the established executor units, not a new heap tariff or a wire cap.
/// The actual encrypted extent bounds plaintext and aggregate decoded text;
/// every JSON value occupies at least one wire byte. No claimed row count or
/// smaller public collection bound can replace this original extent.
fn request_effect_capture_recovery_capacity(
  encrypted_bytes : Int,
  definition_units : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  nodes? : Int? = None,
  definition_nodes? : Int? = None,
) -> @execution.ExecutionCapacity? {
  let tree_nodes = nodes.unwrap_or(encrypted_bytes)
  let definition_tree_nodes = definition_nodes.unwrap_or(definition_units)
  if encrypted_bytes < 0 ||
    tree_nodes < 0 ||
    definition_units < 0 ||
    definition_tree_nodes < 0 ||
    definition_tree_nodes > definition_units ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return None
  }
  let bytes = encrypted_bytes.to_int64()
  // Before AEAD, the encrypted JSON envelope itself still needs one full
  // conservative native tree. After AEAD, retain the larger of that envelope
  // peak and the three inventories bounded by the actual plaintext spelling.
  // Legacy cold callers without plaintext geometry retain their original quote.
  let node_slots = match nodes {
    None => bytes * 3L
    Some(_) => Int64::max(bytes, tree_nodes.to_int64() * 3L)
  }
  @execution.execution_capacity_inventory(
    [
      // One selected physical piece and one failed-close piece can coexist.
      // The Store's original consumeObject piece bound is 65536, independent
      // of a small capture record and of the payloads it validates.
      { unit: QuotedBytes, count: 65536L, copies: 2, },
      // One fixed read/retirement control group, using the same established
      // coarse Host control allowance as the private Request entrance.
      { unit: QuotedBytes, count: 4096L, copies: 1, },
      // Key, nonce and authentication tag have dedicated original backings.
      { unit: QuotedBytes, count: 32L + 12L + 16L, copies: 1, },
      // The original Definition wire getter is an alias; re-admitting that
      // contract creates one additional bounded tree/text backing before
      // capture metadata is known. Admit it in the initial zero-extent phase.
      // Only the live owner's successful constructor may select its recorded
      // final node count. Initial/cold/failed calls keep the original peak.
      {
        unit: ValueNodeSlots,
        count: definition_tree_nodes.to_int64(),
        copies: 1,
      },
      { unit: DecodedTextBytes, count: definition_units.to_int64(), copies: 1, },
      // Capture JSON, retained typed contracts, and prepared schema/member
      // inventory coexist during construction. Successful Store return cuts
      // only the full parsed container; the returned two tree inventories
      // stay backed until their original child cleanup has completed.
      { unit: ValueNodeSlots, count: node_slots, copies: 1, },
      // Capture wire, decoded record strings, and independently decoded typed
      // strings. A getter alias of an existing wire is not another copy.
      { unit: DecodedTextBytes, count: bytes, copies: 3, },
      // Encrypted record/ciphertext, plaintext and Store writer or failed-child
      // bytes coexist during construction. Only successful Store return cuts
      // all four buffers; retained Strings have their separate bounds above.
      // Directory/FD ownership and failed cleanup stay with that Store.
      { unit: CanonicalWireBytes, count: bytes, copies: 4, },
    ],
    [
      // Active bounded Common validation/tree and canonical writer workspace
      // overlap the complete retained inventory, including partial failure.
      {
        unit: ValueNodeSlots,
        count: Int::min(tree_nodes, max_nodes).to_int64(),
        copies: 2,
      },
      { unit: CanonicalWireBytes, count: bytes, copies: 4, },
      {
        unit: CursorRootSlots,
        count: Int::min(encrypted_bytes, max_depth).to_int64(),
        copies: 2,
      },
    ],
    RetainedAlongsideExecution,
  )
}

///|
/// Bind the already authorized journal Request/Run to its existing generic
/// resource preparation. No Request, Run, compiler, Ledger, read grant, claim
/// or continuation is issued here. The fixed Host retains this parent before
/// calling, and retires its actual Store/schema children before ordinary Abort.
/// Zero extent admits the fixed physical read overlap before metadata lookup;
/// the SAME reservation grows to the exact selected extent before decryption.
pub fn[I] reserve_request_effect_capture_recovery(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  encrypted_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard (owner.phase == Open || owner.phase == EffectCaptureRecovery) &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is None &&
    owner.effect_capacity is None &&
    @publication.publication_contract_name(definition) == "run_definition" else {
    return Err(ForeignOriginal)
  }
  let required = match
    request_effect_capture_recovery_capacity(
      encrypted_bytes,
      @publication.publication_contract_json(definition).length(),
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    None => return Err(Policy)
    Some(value) => value
  }
  match owner.program_domain_compilation_inputs {
    None => {
      if owner.phase != Open ||
        owner.snapshot_base is Some(_) ||
        owner.submitted_intent is Some(_) ||
        owner.program_json is Some(_) ||
        owner.program_check is Some(_) {
        return Err(WrongPhase)
      }
      let base = match
        @resources.preparation_capacity_working_extents(owner.capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      // The two-reference domain variant uses the existing four-reference
      // resident slot. Its fixed controls use the Request entrance allowance.
      owner.program_domain_compilation_inputs = Some(
        RequestEffectCaptureRecovery(request, definition),
      )
      owner.program_plan_quote = Some(base)
      owner.phase = EffectCaptureRecovery
    }
    Some(RequestEffectCaptureRecovery(old_request, old_definition)) =>
      if !physical_equal(old_request, request) ||
        !physical_equal(old_definition, definition) {
        return Err(ForeignOriginal)
      }
    _ => return Err(ForeignOriginal)
  }
  guard owner.program_plan_quote is Some((base_r, base_e)) &&
    @execution.checked_preparation_add_product(
      base_r,
      @execution.execution_capacity_retained_bytes(required),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      base_e,
      @execution.execution_capacity_execution_bytes(required),
      1L,
    )
    is Some(e) else {
    return Err(Policy)
  }
  let (r, e) = match owner.program_domain_quote {
    None => (r, e)
    Some((old_r, old_e)) => (Int64::max(r, old_r), Int64::max(e, old_e))
  }
  owner.program_domain_quote = Some((r, e))
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    r,
    e,
  )
  // The original current callback can reenter. Do not revive a closed owner
  // or replace the selected original after it returns or declines admission.
  if owner.phase != Selecting ||
    !(owner.input is Some(original) && physical_equal(original, input)) ||
    !(owner.program_domain_compilation_inputs
    is Some(RequestEffectCaptureRecovery(old_request, old_definition)) &&
    physical_equal(old_request, request) &&
    physical_equal(old_definition, definition)) {
    return Err(ForeignOriginal)
  }
  owner.phase = EffectCaptureRecovery
  result.map_err(issue => Capacity(issue))
}
