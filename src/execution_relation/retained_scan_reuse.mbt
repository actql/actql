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
