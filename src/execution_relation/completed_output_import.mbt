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
  mut completed : Bool
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
/// A representation conversion may be used for a checked Result only when it
/// still carries the exact completed occurrence recorded by the captured Run.
/// Equal contents, schema, or target alone do not authorize substitution.
pub fn completed_output_same_occurrence(
  source : CompletedOutput,
  converted : CompletedOutput,
) -> Bool {
  completed_output_available(source) &&
  completed_output_available(converted) &&
  completed_output_occurrence_identity_matches(source, converted)
}

///|
// Immutable completion/target/representation facts only. They select an
// existing current-aware path, never grant availability or another completion.
fn completed_output_occurrence_identity_matches(
  source : CompletedOutput,
  converted : CompletedOutput,
) -> Bool {
  physical_equal(
    source.completion.result_identity,
    converted.completion.result_identity,
  ) &&
  source.target == converted.target &&
  converted.table is Some(_)
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
  deferred_reclamation? : Bool = false,
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
    deferred_reclamation~,
  )
}

///|
pub fn prepare_completed_output_import(
  source : CompletedOutput,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
  deferred_reclamation? : Bool = false,
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
  admitted.buffer.deferred_reclamation = deferred_reclamation
  stream.buffer.deferred_reclamation = deferred_reclamation
  Ok({ source, admitted, stream, open: true, reading: false, completed: false, })
}

///|
pub fn cancel_completed_output_import(value : CompletedOutputImport) -> Bool {
  if !value.open {
    return false
  }
  value.open = false
  revoke_admitted_buffer(value.admitted.buffer)
  value.stream.open = false
  value.stream.measurement = None
  revoke_admitted_buffer(value.stream.buffer)
  true
}

///|
/// Both receiving value admission and verification admission belong to this
/// conversion. Observe their actual cumulative work after failure, finish or
/// reclamation as well; returning a successful output is not required.
pub fn completed_output_import_cumulative_work(
  value : CompletedOutputImport,
) -> Int64 {
  let receiving = value.admitted.buffer.budget
  let verifying = value.stream.buffer.budget
  receiving.work.to_int64() +
  receiving.external_work.to_int64() +
  verifying.work.to_int64() +
  verifying.external_work.to_int64()
}

///|
/// A completed conversion transferred its rows; only private failed or
/// unfinished admission buffers may be reclaimed. No source is re-read.
pub fn advance_cancel_completed_output_import(
  value : CompletedOutputImport,
  quantum : Int,
) -> Bool {
  if value.completed {
    return true
  }
  value.admitted.buffer.deferred_reclamation = true
  value.stream.buffer.deferred_reclamation = true
  cancel_completed_output_import(value) |> ignore
  if quantum <= 0 ||
    value.reading ||
    value.admitted.buffer.reading ||
    value.stream.reading ||
    value.stream.buffer.reading {
    return false
  }
  if !advance_admitted_buffer_reclamation(value.admitted.buffer, quantum) {
    return false
  }
  advance_admitted_buffer_reclamation(value.stream.buffer, quantum)
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
  let table = if @schema.all_fields_required(rows.schema) {
    AdmittedTable({ owner: original.owner, id, names, rows: rows.rows, })
  } else {
    PresenceTable({
      owner: original.owner,
      id,
      names,
      rows: rows.presence_rows,
    })
  }
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
  value.completed = true
  Ok({
    completion,
    target: original.target,
    table: Some(table),
    representation: None,
  })
}

///|
fn append_completed_output_import_presence(
  value : CompletedOutputImport,
  row : AdmittedRelationRow,
) -> Result[Unit, CompletedImportIssue] {
  if !value.open || value.reading {
    return Err(Closed)
  }
  if !completed_output_available(value.source) {
    cancel_completed_output_import(value) |> ignore
    return Err(Unavailable)
  }
  value.reading = true
  let result : Result[Unit, CompletedImportIssue] = match
    append_admitted_output_presence(value.admitted, row) {
    Err(issue) => Err(Admission(issue))
    Ok(_) =>
      match append_admitted_output_stream_presence(value.stream, row) {
        Ok(_) => Ok(())
        Err(issue) => Err(Encoding(issue))
      }
  }
  value.reading = false
  if result is Err(_) {
    cancel_completed_output_import(value) |> ignore
  }
  result
}
