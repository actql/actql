///|
suberror RetainedContentFailure {
  Content(@execution.RetainedContentReadIssue)
}

///|
#export_name("retainedContentBegin")
pub fn retained_content_begin(
  preparation : @execution.CompletionPreparation,
  expected : @execution.RetainedCompletionDescriptor,
  max_rows : Int,
  values : @execution.ValueLimits,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
) -> @execution.RetainedContentRead raise RetainedContentFailure {
  match
    @execution.prepare_retained_content_read(
      preparation, expected, max_rows, values, wire, max_batch_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise Content(issue)
  }
}

///|
#export_name("retainedContentAppend")
pub fn retained_content_append(
  value : @execution.RetainedContentRead,
  row : String,
  limits : @execution.RetainedRowDecodeLimits,
) -> Unit raise RetainedContentFailure {
  match @execution.append_retained_content_read(value, row, limits) {
    Ok(_) => ()
    Err(issue) => raise Content(issue)
  }
}

///|
#export_name("retainedContentFinish")
pub fn retained_content_finish(
  value : @execution.RetainedContentRead,
) -> @execution.AdmittedOutputStreamReceipt raise RetainedContentFailure {
  match @execution.finish_retained_content_read(value) {
    Ok(receipt) => receipt
    Err(issue) => raise Content(issue)
  }
}

///|
#export_name("retainedContentCancel")
pub fn retained_content_cancel(value : @execution.RetainedContentRead) -> Bool {
  @execution.cancel_retained_content_read(value)
}
