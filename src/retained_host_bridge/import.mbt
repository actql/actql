///|
suberror RetainedImportFailure {
  Import(@execution.CompletedImportIssue)
}

///|
#export_name("retainedImportBegin")
pub fn retained_import_begin(
  source : @execution.CompletedOutput,
  max_rows : Int,
  values : @execution.ValueLimits,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
) -> @execution.CompletedOutputImport raise RetainedImportFailure {
  match
    @execution.prepare_completed_output_import(
      source, max_rows, values, wire, max_batch_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise Import(issue)
  }
}

///|
#export_name("retainedImportAppend")
pub fn retained_import_append(
  conversion : @execution.CompletedOutputImport,
  row : String,
  limits : @execution.RetainedRowDecodeLimits,
) -> Unit raise RetainedImportFailure {
  match
    @execution.append_completed_output_import_wire(conversion, row, limits) {
    Ok(_) => ()
    Err(issue) => raise Import(issue)
  }
}

///|
#export_name("retainedImportFinish")
pub fn retained_import_finish(
  conversion : @execution.CompletedOutputImport,
) -> @execution.CompletedOutput raise RetainedImportFailure {
  match @execution.finish_completed_output_import(conversion) {
    Ok(value) => value
    Err(issue) => raise Import(issue)
  }
}

///|
#export_name("retainedImportCancel")
pub fn retained_import_cancel(
  conversion : @execution.CompletedOutputImport,
) -> Bool {
  @execution.cancel_completed_output_import(conversion)
}
