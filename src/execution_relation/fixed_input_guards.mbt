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
  InputRepresentationRequired(Int)
}

///|
priv struct FixedInputGuardBudget {
  mut work : Int
  mut bytes : Int
  mut nodes : Int
  depth : Int
}

///|
/// Bind the existing demanded-root guards before starting a bounded provider.
/// This performs no expression evaluation. Return the remaining physical
/// allowance so the caller cannot reuse the context preparation work credit.
pub fn prepare_fixed_input_guard_roots(
  original : GeneratedSequence,
  ceiling : Int,
  all_roots : Bool,
  physical : FixedInputGuardMeasureLimits,
) -> Result[
  (GeneratedSequence, FixedInputGuardMeasureLimits),
  FixedInputGuardIssue,
] {
  if ceiling < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let budget : FixedInputGuardBudget = {
    work: physical.max_work,
    bytes: physical.max_bytes,
    nodes: physical.max_nodes,
    depth: physical.max_depth,
  }
  constrain_guard_roots(original, ceiling, all_roots, budget).map(sequence => {
    (sequence, { ..physical, max_work: budget.work, })
  })
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
  column_usage? : Array[(Int, Int)],
  column_maxima? : Array[Int],
  column_nulls? : Array[Int],
  row_measurements? : ManagedRowMeasurements,
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
      if !rows.cell_present(row, column) {
        // No scalar is invented for omission. Presence metadata still consumes
        // a physical node; dense row-measurement reuse is explicitly unsupported.
        if row_measurements is Some(_) {
          return Err(InvalidLayout)
        }
        if budget.nodes <= 0 {
          return Err(Measurement(phase, row, column, @encode.OutputLimit))
        }
        budget.nodes -= 1
        continue
      }
      let cell = rows.read_cell(row, column)
      let usage = try {
        let writer = @encode.measuring_writer(
          budget.bytes,
          budget.nodes,
          budget.depth,
        )
        emit_runtime_value(cell, writer)
        @encode.finish_measurement_usage(writer)
      } catch {
        issue => return Err(Measurement(phase, row, column, issue))
      }
      budget.bytes -= usage.0
      budget.nodes -= usage.1
      if usage.0 > ceiling {
        return Err(ValueBytes(phase, row, column))
      }
      if column_usage is Some(totals) {
        let (bytes, nodes) = totals[column]
        // Subtotals cannot overflow: the enclosing successful budget bounds
        // their nonnegative sum. Publish only with the complete verified scan.
        totals[column] = (bytes + usage.0, nodes + usage.1)
      }
      if column_maxima is Some(maxima) {
        maxima[column] = Int::max(maxima[column], usage.0)
      }
      if column_nulls is Some(nulls) &&
        (cell is Null || cell is Captured(@admitted.Null)) {
        nulls[column] += 1
      }
      if row_measurements is Some(index) {
        if !managed_row_measurement_push(
            index,
            (usage.0, usage.1, cell is Null || cell is Captured(@admitted.Null)),
          ) {
          return Err(InvalidLayout)
        }
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
        if !rows.cell_present(row, column) {
          if budget.nodes <= 0 {
            return Err(Measurement(phase, row, column, @encode.OutputLimit))
          }
          budget.nodes -= 1
          continue
        }
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
  guard output.table is Some(table) else { return Err(MissingOutput) }
  let measured_output = if record_values {
    let names = RelationRows::field_names(table)
    measure_input_records(
      table,
      column => names[column],
      max_value_bytes,
      Output,
      budget,
    )
  } else {
    measure_input_values(table, max_value_bytes, Output, budget)
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

///|
/// Scratch for measuring the already-admitted cells of one original
/// projection. All cells share the same peak, including on refusal. The
/// byte/node/work counters are still cumulative over the complete output.
pub fn admitted_output_measurement_workspace(
  limits : FixedInputGuardMeasureLimits,
) -> Int64? {
  let depth = limits.max_depth
  guard depth >= 0 && depth <= 2147483644 else { return None }
  // All objects emitted from an admitted cell use ordered keys, including
  // the one-key $json wrapper and canonical values inside a Reference.
  // Both traversals share one writer depth. Include the current leaf, its
  // continuation and the Reference step outside the open containers. The
  // emitter inventory already allows both stack backings and their growth.
  guard @encode.measuring_writer_construction_extent(
      0,
      depth,
      unordered_depth=0,
    )
    is Some(writer) &&
    @admitted.wire_emit_bounded_construction_inventory(depth + 3)
    is Some(emitter) else {
    return None
  }
  let operation = @encode.measurement_operation_construction_extent()
  // Borrowed row adapter, active cell/Option, budget, usage projections,
  // per-column usage replacement and returned typed refusal can coexist.
  // Admission and retained metadata have their own existing workspace.
  preparation_representation_cost({
    record_headers: writer.record_headers +
    emitter.record_headers +
    operation.collections.record_headers +
    12L,
    reference_slots: writer.reference_slots +
    emitter.reference_slots +
    operation.collections.reference_slots +
    16L,
    scalar_words: writer.scalar_words +
    emitter.scalar_words +
    operation.collections.scalar_words +
    12L,
    owned_utf16_units: emitter.owned_utf16_units + operation.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}
