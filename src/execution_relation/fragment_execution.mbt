///|
/// Preflight the exact expression-kernel context set before input capture. Mutations
/// are confined to this invocation's private budget map; failure publishes none.
fn attach_fragment_budgets(
  contracts : RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  contexts : Array[FragmentRuntimeContext],
  budgets : Map[Int, LogicalBudget],
  control : ControlBudget,
  metadata : RowWorkspace,
) -> Result[Unit, SequenceRunIssue] {
  if contexts.length() > @lower.sequence_count(sequence) ||
    !reserve_slots(metadata, contexts.length()) {
    return Err(InputLimit)
  }
  for context in contexts {
    if !spend_control(control, 1) {
      return Err(InputLimit)
    }
    let i = @lower.kernel_step(context.kernel)
    guard @lower.sequence_step(sequence, i) is Some(@lower.RowStep(kernel)) else {
      return Err(FragmentContext(i, KernelMismatch))
    }
    let registry = context.fragment.candidate.contract.relations
    if registry.registry_cid != contracts.registry_cid ||
      registry.values_contract_cid != contracts.values_contract_cid ||
      budgets.contains(i) {
      return Err(FragmentContext(i, KernelMismatch))
    }
    let budget = match fragment_runtime_for_kernel(context, kernel) {
      Ok(budget) => budget
      Err(issue) => return Err(FragmentContext(i, issue))
    }
    budgets[i] = budget
  }
  for i = 0; i < @lower.sequence_count(sequence); i = i + 1 {
    if !spend_control(control, 1) {
      return Err(InputLimit)
    }
    match @lower.sequence_step(sequence, i).unwrap() {
      @lower.ValuesStep(_) => ()
      @lower.RowStep(kernel) => {
        let entries = @lower.kernel_view_entries(kernel)
        if !spend_control(control, entries) || !reserve_slots(metadata, entries) {
          return Err(InputLimit)
        }
        let body = @lower.kernel_body(kernel)
        release_slots(metadata, entries)
        match body {
          @lower.SnapshotMap(_)
          | @lower.Filter(_)
          | @lower.OrderedBindings(_) =>
            if !budgets.contains(i) {
              return Err(MissingFragmentContext(i))
            }
          @lower.Select(_) => ()
        }
      }
    }
  }
  Ok(())
}
