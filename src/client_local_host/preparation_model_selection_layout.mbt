///|
// Actual checked Model definitions, not permitted calls/rows/tokens. Borrow
// original graph/selection names and immutable contracts; own only the Host's
// component/Scope/preparation/group wrappers and their live array alternatives.
fn installed_model_selection_layout(count : Int) -> (Int64, Int64)? {
  if count < 0 {
    return None
  }
  if count == 0 {
    return Some((0L, 0L))
  }
  let n = count.to_int64()
  guard @execution.compose_preparation_representation([
      {
        record_headers: 24L + 18L * n,
        // One added ModelState None/reference, one installed Run decoder
        // reference and the weak materialization/group receipt control slots
        // coexist with selection/member/preparation/children wrappers here.
        reference_slots: 64L + 96L * n,
        scalar_words: 24L + 32L * n,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      closed_values_program_arrays(12L, 12L * n, true),
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      {
        record_headers: 12L,
        reference_slots: 40L,
        scalar_words: 12L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      closed_values_program_arrays(6L, 6L * n, true),
    ])
    is Some(scratch) &&
    @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.preparation_representation_cost(scratch) is Some(s) &&
    @execution.checked_preparation_add_product(r, s, 1L) is Some(e) else {
    return None
  }
  Some((r, e))
}

///|
// Pure DATA through the SAME admitted numerical Run. Current/foreign and
// retired reservations are checked by the existing original Plan entrance.
pub fn installed_effect_funded_model_selection_count(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Int, ClientInstalledManagedRunIssue] {
  let plan = match
    installed_effect_managed_operation_plan(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(plan) => plan
  }
  guard plan.model is Some(model) else { return Err(ForeignOriginal) }
  Ok(model.components.map(values => values.length()).unwrap_or(1))
}
