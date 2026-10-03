///|
fn[T] with_sequence_workspace(
  limit : Int,
  action : (RowWorkspace) -> Result[T, RowIssue],
) -> Result[T, RowIssue] {
  let workspace = row_workspace(limit)
  with_scoped_slots(workspace, fn() { action(workspace) })
}

///|
fn prepare_physical_sequence(
  contracts : RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  supplied : Array[CapturedRows],
  retained_ids : Array[String],
  limits : SequenceRunLimits,
  control : ControlBudget,
  produced : Array[BoundProducerInput],
  fragments : Array[FragmentRuntimeContext]?,
  ordered : OrderedExecution,
) -> Result[SequenceInvocation[CompletedTable], SequenceRunIssue] {
  prepare_sequence_with_importers(
    contracts,
    sequence,
    supplied,
    retained_ids,
    limits,
    control,
    captured => {
      with_sequence_workspace(limits.operation_entries, workspace => {
        completed_table_from_capture(captured, control, workspace)
      })
    },
    fn(bound, id, output_budget) {
      guard bound.output.table is Some(source) else { return Err(InvalidRows) }
      let adopted = match source {
        RowTable(table) => RowTable({ ..table, owner: bound.receiver, id, })
        NumberTable(table) =>
          NumberTable({ ..table, owner: bound.receiver, id, })
        AdmittedTable(table) =>
          AdmittedTable({ ..table, owner: bound.receiver, id, })
        ColumnTable(table) =>
          ColumnTable({ ..table, owner: bound.receiver, id, })
        PresenceTable(table) =>
          PresenceTable({ ..table, owner: bound.receiver, id, })
      }
      match bound.projection {
        None => Ok(adopted)
        Some(projection) =>
          with_sequence_workspace(limits.operation_entries, workspace => {
            evaluate_completed_body(
              Projection(projection),
              adopted,
              id,
              limits.max_rows,
              control,
              output_budget,
              workspace,
              None,
            )
          })
      }
    },
    reserve_storage=Some(reserve_completed_storage),
    produced~,
    fragments~,
    ordered~,
  )
}

///|
fn evaluate_physical_sequence(
  contracts : RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  supplied : Array[CapturedRows],
  retained_ids : Array[String],
  limits : SequenceRunLimits,
  control : ControlBudget,
  produced : Array[BoundProducerInput],
  fragments : Array[FragmentRuntimeContext]?,
  ordered : OrderedExecution,
  join_ceilings? : Array[(Int, Int64)] = [],
  expansion_ceilings? : Array[(Int, Int64)] = [],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
  aggregate_outputs? : Array[SelectedAggregateOutput] = [],
  analytic_envelopes? : Array[SelectedAnalyticEnvelope] = [],
  numeric? : NumericAggregateExecution? = None,
  nest_item_ceilings? : Array[(Int, Int64)] = [],
  nest_grouped_byte_ceilings? : Array[(Int, Int64)] = [],
  nest_attached_byte_ceilings? : Array[(Int, Int64)] = [],
) -> Result[CompletedSequence, SequenceRunIssue] {
  let invocation = match
    prepare_physical_sequence(
      contracts, sequence, supplied, retained_ids, limits, control, produced, fragments,
      ordered,
    ) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  run_completed_sequence_backend(
    invocation,
    captured => {
      with_sequence_workspace(limits.operation_entries, workspace => {
        completed_table_from_capture(captured, control, workspace)
      })
    },
    (kernel, input, logical) => {
      with_sequence_workspace(limits.operation_entries, workspace => {
        evaluate_completed_rows(
          kernel,
          input,
          selected_expansion_row_limit(
            expansion_ceilings,
            @lower.kernel_step(kernel),
            limits.max_rows,
          ),
          control,
          invocation.output_budget,
          workspace,
          logical,
          aggregate_outputs=selected_aggregate_outputs_at(
            aggregate_outputs,
            @lower.kernel_step(kernel),
          ),
          analytic_envelope=selected_analytic_envelope_at(
            analytic_envelopes,
            @lower.kernel_step(kernel),
          ),
          identity_limits=Some(invocation.limits.input_values),
          numeric~,
        )
      })
    },
    store => PhysicalStore(store),
    evaluate_window=Some((window, input) => {
      with_sequence_workspace(limits.operation_entries, workspace => {
        evaluate_window_rows(
          window,
          input,
          limits.max_rows,
          control,
          invocation.output_budget,
          workspace,
        ).map(table => RowTable(table))
      })
    }),
    evaluate_join=Some((kernel, left, right) => {
      with_sequence_workspace(limits.operation_entries, workspace => {
        evaluate_join_rows(
          kernel,
          left,
          right,
          limits.max_rows,
          control,
          invocation.output_budget,
          workspace,
          selected_ceiling=selected_join_ceiling_at(
            join_ceilings,
            @lower.join_kernel_step(kernel),
          ),
        ).map(table => RowTable(table))
      })
    }),
    evaluate_interval_join=Some((kernel, left, right) => {
      let step = @lower.interval_join_step(kernel)
      guard selected_step_ceiling(interval_search_ceilings, step)
        is Some(search_ceiling) else {
        return Err(InvalidRowLimits)
      }
      with_sequence_workspace(limits.operation_entries, workspace => {
        evaluate_interval_join_rows(
          kernel,
          left,
          right,
          limits.max_rows,
          search_ceiling,
          control,
          invocation.output_budget,
          workspace,
          selected_ceiling=selected_join_ceiling_at(join_ceilings, step),
        ).map(table => RowTable(table))
      })
    }),
    evaluate_asof_join=Some((kernel, left, right) => {
      let step = @lower.asof_join_step(kernel)
      guard selected_step_ceiling(asof_search_ceilings, step)
        is Some(search_ceiling) else {
        return Err(InvalidRowLimits)
      }
      with_sequence_workspace(limits.operation_entries, workspace => {
        evaluate_asof_join_rows(
          kernel,
          left,
          right,
          limits.max_rows,
          search_ceiling,
          control,
          invocation.output_budget,
          workspace,
          selected_ceiling=selected_join_ceiling_at(join_ceilings, step),
        ).map(table => RowTable(table))
      })
    }),
    evaluate_sequence_match=Some((kernel, input) => {
      with_sequence_workspace(limits.operation_entries, workspace => {
        evaluate_sequence_match_rows(
          kernel,
          input,
          limits.max_rows,
          control,
          invocation.output_budget,
          workspace,
        ).map(table => RowTable(table))
      })
    }),
    evaluate_cross_join=Some((kernel, left, right) => {
      with_sequence_workspace(limits.operation_entries, workspace => {
        evaluate_cross_join_rows(
          kernel,
          left,
          right,
          limits.max_rows,
          control,
          invocation.output_budget,
          workspace,
          selected_ceiling=selected_join_ceiling_at(
            join_ceilings,
            @lower.cross_join_kernel_step(kernel),
          ),
        ).map(table => RowTable(table))
      })
    }),
    evaluate_append=Some((kernel, left, right) => {
      with_sequence_workspace(limits.operation_entries, workspace => {
        evaluate_append_rows(
          kernel,
          left,
          right,
          limits.max_rows,
          control,
          invocation.output_budget,
          workspace,
        ).map(table => RowTable(table))
      })
    }),
    evaluate_set=Some((kernel, left, right) => {
      with_sequence_workspace(limits.operation_entries, workspace => {
        evaluate_set_rows(
          kernel,
          left,
          right,
          limits.max_rows,
          control,
          invocation.output_budget,
          workspace,
        ).map(table => RowTable(table))
      })
    }),
    evaluate_nest=Some((kernel, parent, child) => {
      let step = @lower.nest_kernel_step(kernel)
      with_sequence_workspace(limits.operation_entries, workspace => {
        evaluate_nest_rows(
          kernel,
          parent,
          child,
          limits.max_rows,
          control,
          invocation.output_budget,
          workspace,
          selected_item_limit=selected_step_ceiling(nest_item_ceilings, step),
          grouped_byte_limit=selected_step_ceiling(
            nest_grouped_byte_ceilings, step,
          ),
          attached_byte_limit=selected_step_ceiling(
            nest_attached_byte_ceilings, step,
          ),
        ).map(table => RowTable(table))
      })
    }),
  )
}
