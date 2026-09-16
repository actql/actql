///|
/// Installed representation verifier's authority for one exact receiving read.
/// The verifier must bind the already admitted ordered content to an immutable
/// representation generation and its live lease. A matching CID is insufficient.
struct RetainedScanReuse {
  input : ProducerRead
  material : RetainedOutputMaterial
  available : () -> Bool
}

///|
/// Trusted Host/Store boundary, never supplied by a Program. The typed proof
/// remains owned by its implementation; revocation is checked on every batch
/// and at completion. Consumer measurement/demand are not discharged here.
pub fn[P] prepare_trusted_retained_scan_reuse(
  input : ProducerRead,
  proof : P,
  verify : (P, ProducerRead) -> Bool,
) -> RetainedScanReuse? {
  guard producer_read_retained_material(input) is Some(material) &&
    verify(proof, input) else {
    return None
  }
  Some({ input, material, available: () => verify(proof, input), })
}

///|
fn retained_scan_reuse_available(value : RetainedScanReuse) -> Bool {
  producer_read_available(value.input) &&
  (value.material.available)() &&
  (value.available)()
}

///|
/// Insufficient encoding limits retain the ordinary verification path, preserving
/// its failure ordering. Reuse cannot waive any configured content limit.
pub fn reuse_retained_scan_identity(
  scan : RetainedProducerScan,
  evidence : RetainedScanReuse,
) -> Bool {
  if !scan.open ||
    scan.stream.rows != 0 ||
    scan.reuse is Some(_) ||
    !physical_equal(scan.input, evidence.input) ||
    !retained_scan_reuse_available(evidence) {
    return false
  }
  guard scan.input.bound.output.representation is Some(material) &&
    physical_equal(material, evidence.material) else {
    return false
  }
  let receipt = material.receipt
  if receipt.bytes > scan.wire.max_bytes ||
    receipt.nodes > scan.wire.max_nodes ||
    receipt.depth > scan.wire.max_depth {
    return false
  }
  scan.reuse = Some(evidence)
  true
}

///|
fn append_reused_retained_row(
  scan : RetainedProducerScan,
  values : Array[@admitted.CheckedValue],
) -> Result[Unit, OutputStreamIssue] {
  let stream = scan.stream
  if !stream.open || stream.reading {
    return Err(Closed)
  }
  if stream.rows >= stream.max_rows {
    return Err(Admission(CaptureLimit))
  }
  // Keep value admission and its cumulative budgets. Only canonical encoding
  // and content hashing are replaced by the exact representation evidence.
  let result = append_admitted_buffer_cells(stream.buffer, values.length(), column => {
    values.get(column)
  })
  stream.buffer.rows.clear()
  match result {
    Ok(_) => {
      stream.rows += 1
      Ok(())
    }
    Err(ForeignCheckedValue(_, column)) =>
      Err(Admission(ForeignCheckedValue(stream.rows, column)))
    Err(issue) => Err(Admission(issue))
  }
}

///|
/// Discharge the complete read from an exact live immutable representation.
/// This is only a preparation for the ordinary finish boundary. No rows are
/// supplied and no new consumer-specific predicate or join work is waived.
/// Missing/insufficient evidence leaves the scan unchanged for ordered fallback.
pub fn reuse_retained_scan_values(scan : RetainedProducerScan) -> Bool {
  let stream = scan.stream
  if !scan.open ||
    !stream.open ||
    stream.reading ||
    stream.rows != 0 ||
    scan.join_validation is Some(_) ||
    scan.guard_issue is Some(_) {
    return false
  }
  guard scan.reuse is Some(reuse) && retained_scan_reuse_available(reuse) else {
    return false
  }
  let receipt = reuse.material.receipt
  let budget = stream.buffer.budget
  // Receipt wire depth includes the enclosing array/object and is a safe upper
  // bound on admission depth. A tighter depth falls back, never fails here.
  if receipt.rows > stream.max_rows ||
    receipt.depth > budget.limits.max_depth ||
    receipt.usage.nodes > budget.limits.max_nodes - budget.nodes ||
    receipt.usage.text_bytes > budget.limits.max_text_bytes - budget.text ||
    receipt.usage.work > budget.limits.max_work - budget.work {
    return false
  }
  let measured = match scan.measurement {
    None => None
    Some(measurement) => {
      if !measurement.open || !measurement.scanning_input {
        return false
      }
      guard reusable_retained_value_measurement(scan, measurement)
        is Some(value) else {
        return false
      }
      Some(value)
    }
  }
  // Commit only after every prerequisite passed. Finish rechecks live binding
  // and applies the same consumer measurement charges as the scanned path.
  budget.nodes += receipt.usage.nodes
  budget.text += receipt.usage.text_bytes
  budget.work += receipt.usage.work
  stream.rows = receipt.rows
  scan.measurement_reuse = measured
  true
}
