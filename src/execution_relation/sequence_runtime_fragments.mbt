///|
/// Caller-selected preparation and runtime ceilings for the original checked
/// sequence. These are installation inputs, not inferred expression budgets.
pub(all) struct SequenceFragmentLimits {
  roots : @lower.RootLimits
  demands : @lower.DemandLimits
  physical : RegistryLimits
  logical : @lower.FragmentRowLimits
  max_input_rows : Int64
  max_value_bytes : Int64
}

///|
pub(all) enum SequenceFragmentIssue {
  MissingContract(Int)
  Roots(Int, @lower.RootIssue)
  Request(Int, @lower.FragmentRequestIssue)
  Runtime(Int, RuntimeFragmentIssue)
}

///|
/// Assemble every required context through the existing lowering, contract and
/// runtime owners. No expression is executed and no new sequence owner is made.
pub fn prepare_sequence_runtime_fragments(
  sequence : @lower.PreparedSequence,
  contract : FragmentContract?,
  ordered : RegisteredOrderedContract?,
  limits : SequenceFragmentLimits,
) -> Result[Array[FragmentRuntimeContext], SequenceFragmentIssue] {
  let contexts : Array[FragmentRuntimeContext] = []
  for step in 0..<@lower.sequence_count(sequence) {
    guard @lower.sequence_step(sequence, step) is Some(@lower.RowStep(kernel)) else {
      continue
    }
    let required = match @lower.kernel_body(kernel) {
      @lower.SnapshotMap(_)
      | @lower.OrderedBindings(_)
      | @lower.Filter(_)
      | @lower.AssertAll(_) => true
      @lower.Groups(group) => {
        let mut found = false
        for aggregate in 0..<@lower.group_aggregate_count(group) {
          if @lower.group_aggregate_requires_expression_context(
              @lower.group_aggregate_at(group, aggregate).unwrap(),
            ) {
            found = true
          }
        }
        found
      }
      @lower.AnalyticRows(analytic) =>
        @lower.analytic_requires_expression_context(analytic)
      _ => false
    }
    if !required {
      continue
    }
    guard contract is Some(contract) else { return Err(MissingContract(step)) }
    let fragment = match
      @lower.prepare_fragment_pipeline(sequence, step, limits.roots) {
      Ok(value) => value
      Err(issue) => return Err(Roots(step, issue))
    }
    let is_ordered = @lower.kernel_body(kernel) is @lower.OrderedBindings(_)
    let request = match
      @lower.prepare_fragment_request(
        fragment,
        limits.max_input_rows,
        limits.max_value_bytes,
        row_limits=if is_ordered { Some(limits.logical) } else { None },
      ) {
      Ok(value) => value
      Err(issue) => return Err(Request(step, issue))
    }
    match
      prepare_runtime_fragment(
        request,
        contract,
        limits.demands,
        limits.physical,
        limits.logical,
        ordered=if is_ordered { ordered } else { None },
      ) {
      Ok(value) => contexts.push(value)
      Err(issue) => return Err(Runtime(step, issue))
    }
  }
  Ok(contexts)
}
