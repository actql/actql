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
          @lower.DedupeRows | @lower.StableSort(_) | @lower.Limit(_, _, _) => {
            let checked = @lower.kernel_checked(kernel)
            let schema = @relation.input_schema(checked)
            let sorting = !(body is @lower.DedupeRows)
            let keys = if sorting {
              0
            } else {
              @relation.dedupe_key_count(checked)
            }
            let terms = if sorting {
              @lower.kernel_sort_term_count(kernel)
            } else {
              @relation.dedupe_order_count(checked)
            }
            if keys > control.remaining || terms > control.remaining - keys {
              return Err(InputLimit)
            }
            for j = 0; j < keys + terms; j = j + 1 {
              if !spend_control(control, 1) {
                return Err(InputLimit)
              }
              let name = if sorting {
                @lower.kernel_sort_term_at(kernel, j).unwrap().0
              } else if j < keys {
                @relation.dedupe_key_at(checked, j).unwrap().field
              } else {
                @relation.dedupe_order_at(checked, j - keys).unwrap().field
              }
              // This is a checked reference lookup, not source name resolution.
              let spelling = @schema.reference_name(name)
              // Bound the binary-search comparisons before the shared lookup.
              let mut width = @schema.field_count(schema)
              while width > 0 {
                if !spend_control(control, 1) ||
                  !spend_control_text(control, spelling) {
                  return Err(InputLimit)
                }
                width = width / 2
              }
              if !spend_control_text(control, spelling) {
                return Err(InputLimit)
              }
              guard @schema.lookup(schema, name) is Some(contract) else {
                return Err(FragmentContext(i, KernelMismatch))
              }
              if !supported_comparison(contract, contract) {
                return Err(UnsupportedRowComparison(i, name))
              }
            }
          }
          @lower.DistinctRows => {
            let schema = @relation.output_schema(@lower.kernel_checked(kernel))
            for j = 0; j < @schema.field_count(schema); j = j + 1 {
              if !spend_control(control, 1) {
                return Err(InputLimit)
              }
              let field = @schema.field_at(schema, j).unwrap()
              if !supported_comparison(field.contract, field.contract) {
                return Err(UnsupportedRowComparison(i, field.name))
              }
            }
          }
        }
      }
    }
  }
  Ok(())
}
