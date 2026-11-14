///|
// Relation chunks stay on the same original export/control prefix until the
// complete dependency body is joined and admitted. Count actual borrowed
// UTF16 units before adding a chunk holder; never convert bytes into entries.
pub fn retain_installed_effect_dependency_text(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  text : String,
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
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    control.dependency_inputs is Some(inputs) &&
    owner.source_free_captured is Some(captured) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(plan, expected_plan) ||
    control.dependency_inventory is Some(_) ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) ||
    !@strategy.captured_effect_inputs_match_captured_run(inputs, captured) ||
    !@strategy.captured_effect_inputs_retained(inputs) {
    return Err(ForeignOriginal)
  }
  // Metadata observation is O(1). The original chunk plus join builder,
  // old/new builder backing and resulting String are coheld conservatively.
  guard @execution.preparation_execution_capacity({
      retained: {
        record_headers: 2L,
        reference_slots: 4L,
        scalar_words: 2L,
        owned_utf16_units: 4L * text.length().to_int64(),
        owned_wire_bytes: 0L,
      },
      workspace: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(added) else {
    return Err(InsufficientCapacity)
  }
  match @resources.charge_planning(ledger, 1) {
    Err(issue) => return Err(Ledger(issue))
    Ok(_) => ()
  }
  retain_installed_effect_dependency_capacity(
    owner, preparation, admission, plan, ledger, control, added,
  )
}
