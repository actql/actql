///|
/// Fund one actual key-construction cohort from this Run's SAME control.
/// The caller immediately constructs those keys. Repeated construction keeps
/// its additional original text charged; a saved key is never an IO ACK.
/// Preview admission and checked Run binding supply counts, not Host scalars.
pub fn retain_installed_effect_dispatch_key_construction(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  allowed : @publication_host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
  scope : @effect.LogicalRequestScope,
  max_key_bytes : Int,
  max_key_nodes : Int,
  max_key_depth : Int,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    physical_equal(plan, expected_plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) else {
    return Err(ForeignOriginal)
  }
  guard @publication_host.prepared_client_effect_request_scope(
      prepared, request,
    )
    is Ok(expected_scope) &&
    @effect.logical_request_scope_cid(expected_scope) ==
    @effect.logical_request_scope_cid(scope) else {
    return Err(ForeignOriginal)
  }
  let bound = match
    @publication_host.bind_client_effect_compiled_run(
      prepared, allowed, definition,
    ) {
    Err(_) => return Err(ForeignOriginal)
    Ok(value) => value
  }
  if plan.query_time is Some(time) &&
    !@publication_host.client_effect_run_query_time_matches(
      bound, time, request,
    ) {
    return Err(ForeignOriginal)
  }
  if @publication.check_effect_preview_run_binding(
      @publication_host.client_effect_allowed_run_admission(allowed),
      definition,
      invocation,
      preview,
    )
    is Err(_) ||
    @publication.effect_preview_member_count(preview) !=
    plan.operations.length() {
    return Err(ForeignOriginal)
  }
  let headers = @checked.effect_program_static_headers(
    @publication_host.prepared_client_effect_computation_candidate(prepared),
  )
  match @resources.charge_planning(ledger, plan.operations.length()) {
    Err(issue) => return Err(Ledger(issue))
    Ok(_) => ()
  }
  let mut rows = 0L
  for index, demand in plan.operations {
    guard @syntax.effect_header_at(headers, index) is Some(header) &&
      @publication.effect_preview_member_effect_id(preview, index) ==
      Some(demand.effect_id) &&
      @publication.effect_preview_member_kind(preview, index) ==
      Some(@syntax.effect_header_kind(header)) &&
      @publication.effect_preview_row_count(preview, index) is Some(count) &&
      count >= 0 &&
      count <= plan.rows else {
      return Err(ForeignOriginal)
    }
    if @syntax.effect_header_kind(header) == "command" && count > 1 {
      guard @execution.checked_preparation_add_product(
          rows,
          count.to_int64(),
          1L,
        )
        is Some(next) else {
        return Err(InsufficientCapacity)
      }
      rows = next
    }
  }
  // CRUD and singleton Command keys borrow their established correlation;
  // they introduce neither a retained String nor an additional byte debit.
  if rows == 0L {
    return Ok(())
  }
  guard max_key_bytes >= 73 &&
    max_key_bytes <= 1000000 &&
    max_key_nodes >= 1 &&
    max_key_nodes <= 1000 &&
    max_key_depth >= 1 &&
    max_key_depth <= 32 &&
    installed_effect_command_dispatch_key_capacity(
      rows, max_key_nodes, max_key_depth,
    )
    is Some(added) else {
    return Err(InsufficientCapacity)
  }
  retain_installed_effect_dependency_capacity(
    owner, preparation, admission, plan, ledger, control, added,
  )
}

///|
// All new returned correlation Strings coexist; their concatenation and
// metadata wrappers are synchronous. Parser/hash/key records keep their
// original selected codec backing, unchanged by this text-only extension.
fn installed_effect_command_dispatch_key_capacity(
  rows : Int64,
  max_key_nodes : Int,
  max_key_depth : Int,
) -> @execution.ExecutionCapacity? {
  if rows < 1L {
    return None
  }
  guard @execution.checked_preparation_add_product(
      0L,
      @effect.effect_command_dispatch_correlation_retained_units(),
      rows,
    )
    is Some(text) else {
    return None
  }
  // Only one new key codec runs at a time. Keep its complete existing
  // preserving/canonical codec envelope, including a failed prefix, beside
  // all returned correlation Strings. The hash writer adds its own bounded
  // outer-object continuation; neither quote is assumed to be idle slack.
  guard installed_effect_contract_response_construction_capacity(
      73, max_key_nodes, max_key_depth,
    )
    is Some(codec) &&
    @encode.hash_writer_construction_inventory(
      max_key_nodes + 4,
      max_key_depth + 1,
    )
    is Some(hash) &&
    @execution.preparation_representation_cost({
      record_headers: hash.record_headers + 4L,
      reference_slots: hash.reference_slots + 4L,
      scalar_words: hash.scalar_words + 4L,
      owned_utf16_units: hash.owned_utf16_units +
      @effect.effect_command_dispatch_correlation_workspace_units(),
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(scratch) &&
    @execution.preparation_representation_cost({
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: text,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      retained,
      @execution.execution_capacity_execution_bytes(codec),
      1L,
    )
    is Some(execution) &&
    @execution.checked_preparation_add_product(execution, scratch, 1L)
    is Some(execution) else {
    return None
  }
  @execution.execution_capacity(retained, execution)
}
