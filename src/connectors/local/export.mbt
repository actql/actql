///|
pub(all) struct LocalExportLimits {
  max_rows : Int
  values : @execution.ValueLimits
  wire : @execution.RowWireLimits
  max_batch_bytes : Int
}

///|
/// Conservative bytes for bounded encoding state and the independent file.
/// Local's existing execution and input-buffer allowance remains separate.
pub fn local_export_retention_capacity(limits : LocalExportLimits) -> Int64? {
  let v = limits.values
  let w = limits.wire
  for
    n in [
      limits.max_rows,
      v.max_nodes,
      v.max_text_bytes,
      v.max_depth,
      v.max_work,
      w.max_bytes,
      w.max_nodes,
      w.max_depth,
      w.max_columns,
      w.max_order_work,
    ] {
    if n < 0 {
      return None
    }
  }
  if w.max_nodes < 1 ||
    limits.max_batch_bytes < 1 ||
    limits.max_batch_bytes > 16777216 {
    return None
  }
  Some(
    // Sixteen preparation roots bound the largest fixed overlap. The row
    // cursor's eight roots do not overlap preparation after transfer.
    // The physical-batch mode adds three stream words and two row words.
    // Precharge their fixed controls before construction on this SAME task.
    // It reuses the existing builder: no second accumulator or row array.
    1088L +
    w.max_bytes.to_int64() +
    // Exact row/column authority and reference roots survive the cell-to-file
    // conversion. They are bounded independently of the canonical file bytes.
    128L * v.max_nodes.to_int64() +
    // Existing simultaneous builder/drained String/FD snapshot backing. A
    // larger group of small rows may fill this window, never exceed it.
    8L * limits.max_batch_bytes.to_int64() +
    64L *
    (w.max_columns.to_int64() + w.max_depth.to_int64() + v.max_depth.to_int64()),
  )
}

///|
/// Installed Store owns this predicate; registration precedes any storage I/O.
pub fn install_local_export_retention(
  attempt : LocalMaterializingAttempt,
  released : () -> Bool,
) -> Result[Unit, LocalMaterializingIssue] {
  if attempt.closed ||
    attempt.started ||
    attempt.output_limits is None ||
    attempt.release_check is Some(_) {
    return Err(State)
  }
  attempt.release_check = Some(released)
  Ok(())
}

///|
pub fn begin_local_output_export(
  attempt : LocalMaterializingAttempt,
) -> Result[Unit, LocalMaterializingIssue] {
  guard !attempt.closed &&
    !attempt.exported &&
    attempt.export_preparation is None &&
    attempt.export_stream is None &&
    attempt.export_receipt is None &&
    attempt.release_check is Some(_) &&
    attempt.output is Some(output) &&
    attempt.output_limits is Some(limits) else {
    return Err(State)
  }
  guard @execution.completed_export_preparation_workspace_slots(
      limits.wire.max_columns,
    )
    is Some(slots) else {
    return Err(Capacity)
  }
  match
    @execution.start_completed_output_export(
      output,
      limits.max_rows,
      limits.values,
      limits.wire,
      limits.max_batch_bytes,
      slots,
    ) {
    Ok(preparation) => {
      attempt.export_preparation = Some(preparation)
      Ok(())
    }
    Err(issue) => Err(Export(issue))
  }
}

///|
pub fn advance_local_output_export_preparation(
  attempt : LocalMaterializingAttempt,
  quantum : Int,
) -> Result[(Bool, Int), LocalMaterializingIssue] {
  if attempt.closed {
    return Err(State)
  }
  if attempt.export_stream is Some(_) {
    return Ok((true, 0))
  }
  guard attempt.export_preparation is Some(preparation) else {
    return Err(State)
  }
  @execution.advance_completed_output_export_preparation(preparation, quantum)
  .bind(result => {
    if result.0 {
      @execution.finish_completed_output_export_preparation(preparation).map(stream => {
        attempt.export_preparation = None
        attempt.export_stream = Some(stream)
        result
      })
    } else {
      Ok(result)
    }
  })
  .map_err(issue => Export(issue))
}

///|
pub fn next_local_output_export(
  attempt : LocalMaterializingAttempt,
) -> Result[String?, LocalMaterializingIssue] {
  // Blocking convenience consumers drain the same metadata owner.
  while attempt.export_preparation is Some(_) {
    match advance_local_output_export_preparation(attempt, 64) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  guard !attempt.closed && attempt.export_stream is Some(stream) else {
    return Err(State)
  }
  @execution.next_completed_output_export(stream).map_err(issue => Export(issue))
}

///|
pub fn advance_local_output_export(
  attempt : LocalMaterializingAttempt,
  quantum : Int,
) -> Result[@execution.CompletedOutputExportAdvance, LocalMaterializingIssue] {
  guard !attempt.closed &&
    attempt.export_stream is Some(stream) &&
    attempt.output_limits is Some(limits) else {
    return Err(State)
  }
  guard @execution.completed_output_export_workspace_slots(
      limits.values,
      limits.wire,
    )
    is Some(slots) else {
    return Err(Capacity)
  }
  @execution.advance_completed_output_export(stream, quantum, slots).map_err(issue => {
    Export(issue)
  })
}

///|
pub fn finish_local_output_export(
  attempt : LocalMaterializingAttempt,
) -> Result[
  (@execution.AdmittedOutputStreamReceipt, String),
  LocalMaterializingIssue,
] {
  guard !attempt.closed && attempt.export_stream is Some(stream) else {
    return Err(State)
  }
  @execution.finish_completed_output_export(stream)
  .map(value => {
    let (receipt, tail) = value
    attempt.export_stream = None
    attempt.export_receipt = Some(receipt)
    (@execution.completed_export_content(receipt), tail)
  })
  .map_err(issue => Export(issue))
}

///|
pub fn bind_local_output_export(
  attempt : LocalMaterializingAttempt,
  material : @execution.RetainedOutputMaterial,
) -> Result[Unit, LocalMaterializingIssue] {
  guard !attempt.closed &&
    !attempt.exported &&
    attempt.export_receipt is Some(receipt) else {
    return Err(State)
  }
  let source = attempt.output
  @execution.bind_completed_output_export(receipt, material)
  .map(output => {
    attempt.publication_output = source
    attempt.output = Some(output)
    attempt.exported = true
    attempt.export_receipt = None
    // Independent storage no longer borrows imported Local buffers.
    for i in 0..<attempt.copies.length() {
      attempt.copies[i] = None
    }
  })
  .map_err(issue => Export(issue))
}
