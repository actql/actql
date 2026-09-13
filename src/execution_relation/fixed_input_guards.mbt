///|
/// Physical measurement limits, separate from the caller's logical guards
/// and the evaluator's existing logical work/live-root budgets.
pub(all) struct FixedInputGuardMeasureLimits {
  max_work : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum FixedInputGuardPhase {
  InputValues
  Output
}

///|
pub(all) enum FixedInputGuardIssue {
  InvalidLimits
  ForeignInput
  MeasurementWork
  Measurement(FixedInputGuardPhase, Int, Int, @encode.EncodeFailure)
  ValueBytes(FixedInputGuardPhase, Int, Int)
  InvalidLayout
  Execution(SequenceRunIssue)
  InputRows
  OutputRows
  MissingOutput
}

///|
priv struct FixedInputGuardBudget {
  mut work : Int
  mut bytes : Int
  mut nodes : Int
  depth : Int
}

///|
fn constrain_guard_roots(
  original : GeneratedSequence,
  ceiling : Int,
  all_roots : Bool,
  budget : FixedInputGuardBudget,
) -> Result[GeneratedSequence, FixedInputGuardIssue] {
  if original.contexts.length() > budget.work {
    return Err(MeasurementWork)
  }
  budget.work -= original.contexts.length()
  let contexts = original.contexts.map(context => {
    ..context,
    all_expression_roots: context.all_expression_roots || all_roots,
    root_result_bytes: Some(
      match context.root_result_bytes {
        Some(prior) => Int64::min(prior, ceiling.to_int64())
        None => ceiling.to_int64()
      },
    ),
  })
  Ok(GeneratedSequence::{ ..original, contexts, })
}

///|
fn[T : IndexedRows] measure_input_values(
  rows : T,
  ceiling : Int,
  phase : FixedInputGuardPhase,
  budget : FixedInputGuardBudget,
) -> Result[Unit, FixedInputGuardIssue] {
  for row in 0..<rows.row_count() {
    if budget.work <= 0 {
      return Err(MeasurementWork)
    }
    budget.work -= 1
    if rows.row_width(row) != rows.column_count() {
      return Err(InvalidLayout)
    }
    for column in 0..<rows.column_count() {
      if budget.work <= 0 {
        return Err(MeasurementWork)
      }
      budget.work -= 1
      let usage = try {
        let writer = @encode.measuring_writer(
          budget.bytes,
          budget.nodes,
          budget.depth,
        )
        emit_runtime_value(rows.read_cell(row, column), writer)
        @encode.finish_measurement_usage(writer)
      } catch {
        issue => return Err(Measurement(phase, row, column, issue))
      }
      budget.bytes -= usage.0
      budget.nodes -= usage.1
      if usage.0 > ceiling {
        return Err(ValueBytes(phase, row, column))
      }
    }
  }
  Ok(())
}

///|
// Measure the complete record without constructing a row object or re-reading
// cells. Field order cannot change its byte length; hashing still uses canonical
// column order. The shared writer accounts for keys, punctuation and the root.
fn[T : IndexedRows] measure_input_records(
  rows : T,
  name_at : (Int) -> String,
  ceiling : Int,
  phase : FixedInputGuardPhase,
  budget : FixedInputGuardBudget,
) -> Result[Unit, FixedInputGuardIssue] {
  for row in 0..<rows.row_count() {
    if budget.work <= 0 {
      return Err(MeasurementWork)
    }
    budget.work -= 1
    if rows.row_width(row) != rows.column_count() {
      return Err(InvalidLayout)
    }
    let usage = try {
      let writer = @encode.measuring_writer(
        budget.bytes,
        budget.nodes,
        budget.depth,
      )
      @encode.begin_object(writer)
      for column in 0..<rows.column_count() {
        if budget.work <= 0 {
          return Err(MeasurementWork)
        }
        budget.work -= 1
        @encode.key(writer, name_at(column))
        emit_runtime_value(rows.read_cell(row, column), writer)
      }
      @encode.end_object(writer)
      @encode.finish_measurement_usage(writer)
    } catch {
      issue => return Err(Measurement(phase, row, -1, issue))
    }
    budget.bytes -= usage.0
    budget.nodes -= usage.1
    if usage.0 > ceiling {
      return Err(ValueBytes(phase, row, -1))
    }
  }
  Ok(())
}

///|
/// Enforce every fixed input value before execution, then the retained output.
/// Existing fragment budgets retain their row/live/work rules;
/// an additional root-only ceiling applies without changing checked identities.
/// The private ledger spans input, context constraints and output. No mutable
/// context or storage escapes, and no expression is evaluated for measurement.
/// The target must be retained; an unavailable output returns MissingOutput
/// after successful sequence execution, without exposing a completed result.
/// record_values selects complete record measurement in place of per-cell
/// measurement and applies the ceiling to every demanded expression root.
/// Selected fragment limits and the default consumer root-only mode are unchanged.
pub fn execute_fixed_input_guarded(
  original : GeneratedSequence,
  input : CapturedRows,
  target : @pipeline.Target,
  execution : SequenceExecutionLimits,
  max_output_rows~ : Int,
  max_value_bytes~ : Int,
  record_values? : Bool = false,
  physical : FixedInputGuardMeasureLimits,
) -> Result[(CompletedSequence, (Int, Int, Int)), FixedInputGuardIssue] {
  if max_output_rows < 0 ||
    max_value_bytes < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(generated_sequence_owner(original), captured_owner(input)) {
    return Err(ForeignInput)
  }
  let budget : FixedInputGuardBudget = {
    work: physical.max_work,
    bytes: physical.max_bytes,
    nodes: physical.max_nodes,
    depth: physical.max_depth,
  }
  let measured = if record_values {
    measure_input_records(
      CapturedWireRows::{ rows: input, },
      column => {
        @schema.reference_name(
          @schema.field_at(input.schema, column).unwrap().name,
        )
      },
      max_value_bytes,
      InputValues,
      budget,
    )
  } else {
    measure_input_values(
      CapturedWireRows::{ rows: input, },
      max_value_bytes,
      InputValues,
      budget,
    )
  }
  match measured {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let generated = match
    constrain_guard_roots(original, max_value_bytes, record_values, budget) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let completed = match
    execute_generated_sequence(generated, [input], execution) {
    Ok(value) => value
    Err(issue) => return Err(Execution(issue))
  }
  guard completed_output(completed, target) is Some(output) else {
    return Err(MissingOutput)
  }
  if completed_row_count(output) > max_output_rows {
    return Err(OutputRows)
  }
  let measured_output = if record_values {
    let names = RelationRows::field_names(output.table)
    measure_input_records(
      output.table,
      column => names[column],
      max_value_bytes,
      Output,
      budget,
    )
  } else {
    measure_input_values(output.table, max_value_bytes, Output, budget)
  }
  match measured_output {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok(
    (
      completed,
      (
        physical.max_work - budget.work,
        physical.max_bytes - budget.bytes,
        physical.max_nodes - budget.nodes,
      ),
    ),
  )
}
