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
      let adopted = match bound.output.table {
        RowTable(table) => RowTable({ ..table, owner: bound.receiver, id, })
        NumberTable(table) =>
          NumberTable({ ..table, owner: bound.receiver, id, })
      }
      match bound.projection {
        None => Ok(adopted)
        Some(projection) =>
          evaluate_completed_body(
            CheckedProjection(projection),
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
      )
    },
    store => PhysicalStore(store),
  )
}
