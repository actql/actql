///|
/// Explicit conversion of an existing completed representation, not execution.
/// New values cannot acquire completion authority without the exact source and
/// successful verification of its whole ordered canonical identity.
struct CompletedOutputImport {
  source : CompletedOutput
  admitted : AdmittedOutput
  stream : AdmittedOutputStream
  mut open : Bool
  mut reading : Bool
}

///|
pub(all) enum CompletedImportIssue {
  Unavailable
  NotRetainedRepresentation
  Admission(CaptureIssue)
  Encoding(OutputStreamIssue)
  IdentityMismatch
  Closed
  WireRow(RetainedRowDecodeIssue)
  InputGuard(FixedInputGuardIssue)
  JoinValidation(RowIssue)
}

///|
/// Import the exact representation selected by an admitted receiving port.
/// The caller need not extract or reconstruct the producer's completion.
pub fn prepare_producer_output_import(
  input : ProducerRead,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
) -> Result[CompletedOutputImport, CompletedImportIssue] {
  if !producer_read_available(input) {
    return Err(Unavailable)
  }
  prepare_completed_output_import(
    input.bound.output,
    max_rows,
    values,
    wire,
    max_batch_bytes,
  )
}

///|
pub fn prepare_completed_output_import(
  source : CompletedOutput,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
) -> Result[CompletedOutputImport, CompletedImportIssue] {
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  guard source.representation is Some(material) else {
    return Err(NotRetainedRepresentation)
  }
  let receipt = material.receipt
  if max_rows < receipt.rows {
    return Err(Admission(CaptureLimit))
  }
  let admitted = match
    prepare_admitted_output(receipt.owner, receipt.target, max_rows, values) {
    Ok(admitted) => admitted
    Err(issue) => return Err(Admission(issue))
  }
  let stream = match
    prepare_admitted_output_stream(
      receipt.owner,
      receipt.target,
      max_rows,
      values,
      wire,
      max_batch_bytes,
    ) {
    Ok(stream) => stream
    Err(issue) => return Err(Encoding(issue))
  }
  Ok({ source, admitted, stream, open: true, reading: false, })
}

///|
pub fn cancel_completed_output_import(value : CompletedOutputImport) -> Bool {
  if !value.open {
    return false
  }
  value.open = false
  cancel_admitted_output(value.admitted) |> ignore
  cancel_admitted_output_stream(value.stream) |> ignore
  true
}

///|
pub fn append_completed_output_import(
  value : CompletedOutputImport,
  supplied : Array[@admitted.CheckedValue],
) -> Result[Unit, CompletedImportIssue] {
  if !value.open || value.reading {
    return Err(Closed)
  }
  if !completed_output_available(value.source) {
    cancel_completed_output_import(value) |> ignore
    return Err(Unavailable)
  }
  value.reading = true
  // There is no user callback/await between the two consumers of this bounded
  // immutable cell set. Both admission and hashing see the exact same values.
  let result : Result[Unit, CompletedImportIssue] = match
    append_admitted_output(value.admitted, supplied) {
    Err(issue) => Err(Admission(issue))
    Ok(_) =>
      match
        append_admitted_output_stream(value.stream, supplied.length(), column => {
          supplied.get(column)
        }) {
        Err(issue) => Err(Encoding(issue))
        Ok(_) => Ok(())
      }
  }
  value.reading = false
  if result is Err(_) {
    cancel_completed_output_import(value) |> ignore
  }
  result
}

///|
pub fn finish_completed_output_import(
  value : CompletedOutputImport,
) -> Result[CompletedOutput, CompletedImportIssue] {
  if !value.open || value.reading {
    return Err(Closed)
  }
  if !completed_output_available(value.source) {
    cancel_completed_output_import(value) |> ignore
    return Err(Unavailable)
  }
  let (verified, _) = match finish_admitted_output_stream(value.stream) {
    Ok(verified) => verified
    Err(issue) => {
      cancel_completed_output_import(value) |> ignore
      return Err(Encoding(issue))
    }
  }
  let original = value.source.representation.unwrap().receipt
  if verified.cid != original.cid ||
    verified.rows != original.rows ||
    verified.bytes != original.bytes ||
    verified.nodes != original.nodes ||
    !physical_equal(verified.owner, original.owner) ||
    verified.target != original.target ||
    !physical_equal(verified.schema, original.schema) {
    cancel_completed_output_import(value) |> ignore
    return Err(IdentityMismatch)
  }
  let rows = match finish_admitted_output(value.admitted) {
    Ok(rows) => rows
    Err(issue) => {
      cancel_completed_output_import(value) |> ignore
      return Err(Admission(issue))
    }
  }
  value.open = false
  let prepared = @lower.bound_preparation(original.owner)
  let names = Array::makei(@schema.field_count(original.schema), column => {
    @schema.reference_name(
      @schema.field_at(original.schema, column).unwrap().name,
    )
  })
  let id = match original.target {
    Step(index) => @lower.node_id(@lower.node_at(prepared, index).unwrap())
    Input(_) => abort("retained output must have a checked step target")
  }
  let table = AdmittedTable({
    owner: original.owner,
    id,
    names,
    rows: rows.rows,
  })
  // Same immutable completion and logical restrictions, independently admitted
  // physical storage. Do not capture the source copy's availability callback.
  let completion : CompletedSequence = {
    ..value.source.completion,
    store: ImportedStore(
      @lower.preparation_input_count(prepared),
      original.target,
      table,
    ),
  }
  Ok({
    completion,
    target: original.target,
    table: Some(table),
    representation: None,
  })
}
