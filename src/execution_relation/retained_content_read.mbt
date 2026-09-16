///|
/// Bounded revalidation of stored typed rows in a newly prepared runtime.
/// This produces content admission only, never execution/completion evidence.
/// The installed Host must independently verify custody and physical read end.
struct RetainedContentRead {
  expected : RetainedCompletionDescriptor
  stream : AdmittedOutputStream
  mut open : Bool
}

///|
pub(all) enum RetainedContentReadIssue {
  ForeignContract
  MetadataLimit
  Encoding(OutputStreamIssue)
  Row(RetainedRowDecodeIssue)
  IdentityMismatch
  Closed
}

///|
pub fn prepare_retained_content_read(
  preparation : CompletionPreparation,
  expected : RetainedCompletionDescriptor,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
) -> Result[RetainedContentRead, RetainedContentReadIssue] {
  let owner = completion_preparation_owner(preparation)
  let prepared = @lower.bound_preparation(owner)
  if expected.registry_cid != preparation.contracts.registry_cid ||
    expected.values_contract_cid != preparation.contracts.values_contract_cid ||
    expected.output_step < 0 ||
    expected.input_count != @lower.preparation_input_count(prepared) {
    return Err(ForeignContract)
  }
  guard @lower.preparation_schema_at(prepared, Step(expected.output_step))
    is Some(schema) &&
    @schema.field_count(schema) == expected.columns else {
    return Err(ForeignContract)
  }
  if expected.rows < 0 ||
    expected.rows > max_rows ||
    expected.bytes < 0 ||
    expected.bytes > wire.max_bytes ||
    expected.nodes < 0 ||
    expected.nodes > wire.max_nodes ||
    expected.depth < 0 ||
    expected.depth > wire.max_depth ||
    expected.values.nodes < 0 ||
    expected.values.nodes > values.max_nodes ||
    expected.values.text_bytes < 0 ||
    expected.values.text_bytes > values.max_text_bytes ||
    expected.values.work < 0 ||
    expected.values.work > values.max_work {
    return Err(MetadataLimit)
  }
  match
    prepare_admitted_output_stream(
      owner,
      Step(expected.output_step),
      max_rows,
      values,
      wire,
      max_batch_bytes,
    ) {
    Err(issue) => Err(Encoding(issue))
    Ok(stream) => Ok({ expected, stream, open: true, })
  }
}

///|
pub fn cancel_retained_content_read(value : RetainedContentRead) -> Bool {
  if !value.open {
    return false
  }
  value.open = false
  cancel_admitted_output_stream(value.stream) |> ignore
  true
}

///|
/// The same typed decoder and canonical encoder as representation conversion.
/// Canonical text batches are discarded here: the immutable source already
/// exists, and validation must not require an additional full-body copy.
pub fn append_retained_content_read(
  value : RetainedContentRead,
  row : String,
  limits : RetainedRowDecodeLimits,
) -> Result[Unit, RetainedContentReadIssue] {
  if !value.open {
    return Err(Closed)
  }
  let cells = match
    decode_retained_row(value.stream.buffer.schema, row, limits) {
    Ok(cells) => cells
    Err(issue) => {
      cancel_retained_content_read(value) |> ignore
      return Err(Row(issue))
    }
  }
  match
    append_admitted_output_stream(value.stream, cells.length(), column => {
      cells.get(column)
    }) {
    Ok(_) => Ok(())
    Err(issue) => {
      cancel_retained_content_read(value) |> ignore
      Err(Encoding(issue))
    }
  }
}

///|
/// Exact ordered content verification is still not proof of computation, nor
/// permission to substitute equal contents for a different producer/attempt.
pub fn finish_retained_content_read(
  value : RetainedContentRead,
) -> Result[AdmittedOutputStreamReceipt, RetainedContentReadIssue] {
  if !value.open {
    return Err(Closed)
  }
  value.open = false
  let (receipt, _) = match finish_admitted_output_stream(value.stream) {
    Ok(receipt) => receipt
    Err(issue) => return Err(Encoding(issue))
  }
  let expected = value.expected
  if receipt.cid != expected.rows_cid ||
    receipt.rows != expected.rows ||
    receipt.bytes != expected.bytes ||
    receipt.nodes != expected.nodes ||
    receipt.depth != expected.depth ||
    receipt.usage != expected.values {
    return Err(IdentityMismatch)
  }
  Ok(receipt)
}
