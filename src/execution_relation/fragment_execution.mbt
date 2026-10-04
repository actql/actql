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
      @lower.InferBoundary(_) => ()
      @lower.ValuesStep(_) => ()
      @lower.TimeSeriesStep(_) => ()
      @lower.WindowStep(_) => ()
      @lower.AppendStep(_) => ()
      @lower.SetStep(_) => ()
      @lower.GraphMatchStep(_) => ()
      @lower.GraphSubgraphStep(_) => ()
      @lower.GraphTraverseStep(_) => ()
      @lower.GraphDiagnosticStep(_) => ()
      @lower.PropertyGraphConstructionStep(_) => ()
      @lower.VectorStep(_) => ()
      @lower.EventStep(_) => ()
      @lower.CarrierProjectionStep(_) => ()
      @lower.NestStep(kernel) =>
        for key in 0..<@lower.nest_kernel_key_count(kernel) {
          let pair = @lower.nest_kernel_key_at(kernel, key).unwrap()
          if !spend_control(control, 1) ||
            !spend_control_text(control, @schema.reference_name(pair.left)) ||
            !spend_control_text(control, @schema.reference_name(pair.right)) {
            return Err(InputLimit)
          }
          guard @schema.lookup(
              @lower.nest_kernel_input_schema(kernel, true),
              pair.left,
            )
            is Some(left) &&
            @schema.lookup(
              @lower.nest_kernel_input_schema(kernel, false),
              pair.right,
            )
            is Some(right) else {
            return Err(FragmentContext(i, KernelMismatch))
          }
          if !supported_comparison(left, right) {
            return Err(UnsupportedRowComparison(i, pair.left))
          }
        }
      @lower.JoinStep(kernel) => {
        let profile = @lower.join_kernel_profile(kernel)
        for key in 0..<@lower.inner_join_key_count(profile) {
          let (left, right) = @lower.inner_join_key_at(profile, key).unwrap()
          if !spend_control(control, 1) ||
            !spend_control_text(control, @schema.reference_name(left)) ||
            !spend_control_text(control, @schema.reference_name(right)) {
            return Err(InputLimit)
          }
          guard @schema.lookup(
              @lower.inner_join_input_schema(profile, true),
              left,
            )
            is Some(lc) &&
            @schema.lookup(
              @lower.inner_join_input_schema(profile, false),
              right,
            )
            is Some(rc) else {
            return Err(FragmentContext(i, KernelMismatch))
          }
          if !supported_comparison(lc, rc) {
            return Err(UnsupportedRowComparison(i, left))
          }
        }
      }
      @lower.IntervalJoinStep(_) => ()
      @lower.AsOfJoinStep(_) => ()
      @lower.SequenceMatchStep(_) => ()
      @lower.CrossJoinStep(_) => ()
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
          | @lower.AssertAll(_)
          | @lower.OrderedBindings(_) =>
            if !budgets.contains(i) {
              return Err(MissingFragmentContext(i))
            }
          @lower.AnalyticRows(analytic) =>
            if @lower.analytic_requires_expression_context(analytic) &&
              !budgets.contains(i) {
              return Err(MissingFragmentContext(i))
            }
          @lower.Select(_) => ()
          @lower.JsonPick(_, _, _) => ()
          @lower.Watermark(time, _, _, _) => {
            let name = @schema.reference_name(time)
            if !spend_control(control, 1) ||
              !spend_control_text(control, name) ||
              @schema.lookup(@lower.kernel_input_schema(kernel), time) is None {
              return Err(FragmentContext(i, KernelMismatch))
            }
          }
          @lower.Pivot(pivot) => {
            let schema = @lower.pivot_input_schema(pivot)
            for j = 0; j < @lower.pivot_index_count(pivot) + 2; j = j + 1 {
              let field = if j < @lower.pivot_index_count(pivot) {
                @lower.pivot_index_at(pivot, j).unwrap()
              } else if j == @lower.pivot_index_count(pivot) {
                @lower.pivot_column(pivot)
              } else {
                @lower.pivot_value(pivot)
              }
              let name = @schema.reference_name(field)
              if !spend_control(control, 1) ||
                !spend_control_text(control, name) ||
                @schema.lookup(schema, field) is None {
                return Err(FragmentContext(i, KernelMismatch))
              }
            }
          }
          @lower.Unnest(column, _, _, _, _) => {
            let name = @schema.reference_name(column)
            if !spend_control(control, 1) ||
              !spend_control_text(control, name) ||
              @schema.lookup(@lower.kernel_input_schema(kernel), column) is None {
              return Err(FragmentContext(i, KernelMismatch))
            }
          }
          @lower.Unpivot(columns, keep, _, _) => {
            let schema = @lower.kernel_input_schema(kernel)
            for field in columns + keep {
              let name = @schema.reference_name(field)
              if !spend_control(control, 1) ||
                !spend_control_text(control, name) ||
                @schema.lookup(schema, field) is None {
                return Err(FragmentContext(i, KernelMismatch))
              }
            }
          }
          @lower.AssertUnique(keys) => {
            let schema = @lower.kernel_input_schema(kernel)
            for name in keys {
              if !spend_control(control, 1) ||
                !spend_control_text(control, @schema.reference_name(name)) {
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
          @lower.CountGroups(group) => {
            let schema = @lower.count_group_input_schema(group)
            for j in 0..<@lower.count_group_key_count(group) {
              let name = @lower.count_group_key_at(group, j).unwrap()
              if !spend_control(control, 1) ||
                !spend_control_text(control, @schema.reference_name(name)) {
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
          @lower.Groups(group) => {
            let schema = @lower.group_input_schema(group)
            for j = 0; j < @lower.group_key_count(group); j = j + 1 {
              let name = @lower.group_key_at(group, j).unwrap()
              if !spend_control(control, 1) ||
                !spend_control_text(control, @schema.reference_name(name)) {
                return Err(InputLimit)
              }
              guard @schema.lookup(schema, name) is Some(contract) else {
                return Err(FragmentContext(i, KernelMismatch))
              }
              if !supported_comparison(contract, contract) {
                return Err(UnsupportedRowComparison(i, name))
              }
            }
            for j = 0; j < @lower.group_aggregate_count(group); j = j + 1 {
              let aggregate = @lower.group_aggregate_at(group, j).unwrap()
              if @lower.group_aggregate_requires_expression_context(aggregate) &&
                !budgets.contains(i) {
                return Err(MissingFragmentContext(i))
              }
              for k = 0
                  k < @lower.group_aggregate_order_count(aggregate)
                  k = k + 1 {
                let (name, _, _) = @lower.group_aggregate_order_term_at(
                  aggregate, k,
                ).unwrap()
                if !spend_control(control, 1) ||
                  !spend_control_text(control, @schema.reference_name(name)) {
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
          }
          @lower.TopK(_, _) | @lower.PartitionedTopK(_, _) => {
            let schema = @lower.kernel_input_schema(kernel)
            let partitions = @lower.kernel_top_k_partition_count(kernel)
            let terms = @lower.kernel_sort_term_count(kernel)
            if partitions > control.remaining ||
              terms > control.remaining - partitions {
              return Err(InputLimit)
            }
            for j = 0; j < partitions + terms; j = j + 1 {
              if !spend_control(control, 1) {
                return Err(InputLimit)
              }
              let name = if j < partitions {
                @lower.kernel_top_k_partition_at(kernel, j).unwrap()
              } else {
                @lower.kernel_sort_term_at(kernel, j - partitions).unwrap().0
              }
              let spelling = @schema.reference_name(name)
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
          @lower.Lag(_, _) => {
            let schema = @lower.kernel_input_schema(kernel)
            let partitions = @lower.kernel_lag_partition_count(kernel)
            let terms = @lower.kernel_sort_term_count(kernel)
            if partitions > control.remaining ||
              terms > control.remaining - partitions {
              return Err(InputLimit)
            }
            for j = 0; j < partitions + terms; j = j + 1 {
              if !spend_control(control, 1) {
                return Err(InputLimit)
              }
              let name = if j < partitions {
                @lower.kernel_lag_partition_at(kernel, j).unwrap()
              } else {
                @lower.kernel_sort_term_at(kernel, j - partitions).unwrap().0
              }
              let spelling = @schema.reference_name(name)
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
          @lower.DedupeRows | @lower.StableSort(_) | @lower.Limit(_, _, _) => {
            let schema = @lower.kernel_input_schema(kernel)
            let sorting = !(body is @lower.DedupeRows)
            let keys = if sorting {
              0
            } else {
              @lower.kernel_dedupe_key_count(kernel)
            }
            let terms = if sorting {
              @lower.kernel_sort_term_count(kernel)
            } else {
              @lower.kernel_dedupe_order_count(kernel)
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
                @lower.kernel_dedupe_key_at(kernel, j).unwrap()
              } else {
                @lower.kernel_dedupe_order_at(kernel, j - keys).unwrap().0
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
            let schema = @lower.kernel_output_schema(kernel)
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
