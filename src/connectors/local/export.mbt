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
    w.max_bytes.to_int64() +
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
    attempt.export_stream is None &&
    attempt.export_receipt is None &&
    attempt.release_check is Some(_) &&
    attempt.output is Some(output) &&
    attempt.output_limits is Some(limits) else {
    return Err(State)
  }
  match
    @execution.prepare_completed_output_export(
      output,
      limits.max_rows,
      limits.values,
      limits.wire,
      limits.max_batch_bytes,
    ) {
    Ok(stream) => {
      attempt.export_stream = Some(stream)
      Ok(())
    }
    Err(issue) => Err(Export(issue))
  }
}

///|
pub fn next_local_output_export(
  attempt : LocalMaterializingAttempt,
) -> Result[String?, LocalMaterializingIssue] {
  guard !attempt.closed && attempt.export_stream is Some(stream) else {
    return Err(State)
  }
  @execution.next_completed_output_export(stream).map_err(issue => Export(issue))
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
