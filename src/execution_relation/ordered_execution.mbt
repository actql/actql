///|
/// Internal configuration, not complete fragment admission. Host representation
/// bounds remain distinct from the logical contract caps.
priv struct OrderedExecution {
  contexts : Array[OrderedLimits]
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
fn prepare_ordered_budgets(
  contracts : RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  execution : OrderedExecution,
  control : ControlBudget,
  metadata : RowWorkspace,
) -> Result[Map[Int, LogicalBudget], SequenceRunIssue] {
  if execution.max_bytes < 0 ||
    execution.max_nodes < 0 ||
    execution.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if execution.contexts.length() > @lower.sequence_count(sequence) ||
    !reserve_slots(metadata, execution.contexts.length()) {
    return Err(InputLimit)
  }
  let budgets : Map[Int, LogicalBudget] = Map([])
  for context in execution.contexts {
    if !spend_control(control, 1) {
      return Err(InputLimit)
    }
    let source = ordered_params_kernel(context.params)
    let index = @lower.kernel_step(source)
    guard @lower.sequence_step(sequence, index) is Some(@lower.RowStep(kernel)) else {
      return Err(OrderedContext(index, ForeignKernel))
    }
    let limits = match ordered_limits_for_kernel(context, kernel) {
      Ok(limits) => limits
      Err(e) => return Err(OrderedContext(index, e))
    }
    let registry = ordered_params_registry(context.params)
    if registry.registry_cid != contracts.registry_cid ||
      registry.values_contract_cid != contracts.values_contract_cid ||
      budgets.contains(index) {
      return Err(OrderedContext(index, ForeignKernel))
    }
    let budget = match
      logical_budget(
        limits,
        execution.max_bytes,
        execution.max_nodes,
        execution.max_depth,
      ) {
      Ok(budget) => budget
      Err(e) => return Err(Rows(index, LogicalRows(e)))
    }
    budgets[index] = budget
  }
  // Validate the exact set before capturing inputs or evaluating any RHS.
  for i = 0; i < @lower.sequence_count(sequence); i = i + 1 {
    if !spend_control(control, 1) {
      return Err(InputLimit)
    }
    match @lower.sequence_step(sequence, i).unwrap() {
      @lower.ValuesStep(_)
      | @lower.TimeSeriesStep(_)
      | @lower.WindowStep(_)
      | @lower.JoinStep(_)
      | @lower.IntervalJoinStep(_)
      | @lower.AsOfJoinStep(_)
      | @lower.SequenceMatchStep(_)
      | @lower.CrossJoinStep(_)
      | @lower.AppendStep(_)
      | @lower.SetStep(_)
      | @lower.NestStep(_) => ()
      @lower.GraphMatchStep(_) => return Err(InputSet)
      @lower.GraphTraverseStep(_) => return Err(InputSet)
      @lower.GraphDiagnosticStep(_) => return Err(InputSet)
      @lower.GraphNormalizeStep(_) => return Err(InputSet)
      @lower.GraphDeltaStep(_) => return Err(InputSet)
      @lower.PropertyGraphConstructionStep(_) => return Err(InputSet)
      @lower.VectorStep(_) => return Err(InputSet)
      @lower.EventStep(_) => return Err(InputSet)
      @lower.CarrierProjectionStep(_) => return Err(InputSet)
      @lower.InferBoundary(_) => return Err(InputSet)
      @lower.RowStep(kernel) => {
        let entries = @lower.kernel_view_entries(kernel)
        if !spend_control(control, entries) || !reserve_slots(metadata, entries) {
          return Err(InputLimit)
        }
        let body = @lower.kernel_body(kernel)
        match body {
          @lower.OrderedBindings(_) =>
            if !budgets.contains(i) {
              return Err(Rows(i, MissingOrderedResourceContext))
            }
          @lower.Groups(group) => {
            let mut required = false
            for aggregate = 0
                aggregate < @lower.group_aggregate_count(group)
                aggregate = aggregate + 1 {
              let value = @lower.group_aggregate_at(group, aggregate).unwrap()
              if @lower.group_aggregate_requires_expression_context(value) {
                required = true
              }
            }
            if required && !budgets.contains(i) {
              return Err(Rows(i, MissingOrderedResourceContext))
            }
          }
          @lower.AnalyticRows(analytic) =>
            if @lower.analytic_requires_expression_context(analytic) &&
              !budgets.contains(i) {
              return Err(Rows(i, MissingOrderedResourceContext))
            }
          @lower.SnapshotMap(_)
          | @lower.Filter(_)
          | @lower.AssertAll(_)
          | @lower.AssertUnique(_)
          | @lower.JsonPick(_, _, _)
          | @lower.Select(_)
          | @lower.Limit(_, _, _)
          | @lower.TopK(_, _)
          | @lower.PartitionedTopK(_, _)
          | @lower.Pivot(_)
          | @lower.Unnest(_, _, _, _, _)
          | @lower.Unpivot(_, _, _, _)
          | @lower.DistinctRows
          | @lower.DedupeRows
          | @lower.StableSort(_)
          | @lower.Lag(_, _)
          | @lower.Watermark(_, _, _, _)
          | @lower.CountGroups(_) => ()
        }
        release_slots(metadata, entries)
      }
    }
  }
  Ok(budgets)
}
