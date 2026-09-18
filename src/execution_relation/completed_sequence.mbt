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
      table_from_capture_bounded(captured, control, {
        limit: limits.operation_entries,
        live: 0,
        peak: 0,
      }).map(table => RowTable(table))
    },
    fn(bound, id, output_budget) {
      guard bound.output.table is Some(source) else { return Err(InvalidRows) }
      let adopted = match source {
        RowTable(table) => RowTable({ ..table, owner: bound.receiver, id, })
        NumberTable(table) =>
          NumberTable({ ..table, owner: bound.receiver, id, })
        AdmittedTable(table) =>
          AdmittedTable({ ..table, owner: bound.receiver, id, })
      }
      match bound.projection {
        None => Ok(adopted)
        Some(projection) =>
          evaluate_completed_body(
            Projection(projection),
            adopted,
            id,
            limits.max_rows,
            control,
            output_budget,
            { limit: limits.operation_entries, live: 0, peak: 0, },
            None,
          )
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
  join_ceiling? : (Int, Int64)? = None,
  aggregate_outputs? : Array[SelectedAggregateOutput] = [],
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
      table_from_capture_bounded(captured, control, {
        limit: limits.operation_entries,
        live: 0,
        peak: 0,
      }).map(table => RowTable(table))
    },
    (kernel, input, logical) => {
      evaluate_completed_rows(
        kernel,
        input,
        limits.max_rows,
        control,
        invocation.output_budget,
        { limit: limits.operation_entries, live: 0, peak: 0, },
        logical,
        aggregate_outputs=selected_aggregate_outputs_at(
          aggregate_outputs,
          @lower.kernel_step(kernel),
        ),
        identity_limits=Some(invocation.limits.input_values),
      )
    },
    store => PhysicalStore(store),
    evaluate_window=Some((window, input) => {
      evaluate_window_rows(
        window,
        input,
        limits.max_rows,
        control,
        invocation.output_budget,
        { limit: limits.operation_entries, live: 0, peak: 0, },
      ).map(table => RowTable(table))
    }),
    evaluate_join=Some((kernel, left, right) => {
      evaluate_join_rows(
        kernel,
        left,
        right,
        limits.max_rows,
        control,
        invocation.output_budget,
        { limit: limits.operation_entries, live: 0, peak: 0, },
        selected_ceiling=join_ceiling,
      ).map(table => RowTable(table))
    }),
    evaluate_cross_join=Some((kernel, left, right) => {
      evaluate_cross_join_rows(
        kernel,
        left,
        right,
        limits.max_rows,
        control,
        invocation.output_budget,
        { limit: limits.operation_entries, live: 0, peak: 0, },
        selected_ceiling=join_ceiling,
      ).map(table => RowTable(table))
    }),
    evaluate_append=Some((kernel, left, right) => {
      evaluate_append_rows(
        kernel,
        left,
        right,
        limits.max_rows,
        control,
        invocation.output_budget,
        { limit: limits.operation_entries, live: 0, peak: 0, },
      ).map(table => RowTable(table))
    }),
    evaluate_set=Some((kernel, left, right) => {
      evaluate_set_rows(
        kernel,
        left,
        right,
        limits.max_rows,
        control,
        invocation.output_budget,
        { limit: limits.operation_entries, live: 0, peak: 0, },
      ).map(table => RowTable(table))
    }),
  )
}
