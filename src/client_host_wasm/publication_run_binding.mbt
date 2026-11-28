///|
fn sdk_file_publication_owns_run(
  value : Instance,
  publication : StoredPublication,
  file : StoredFilePublicationCapture,
  run : Int,
) -> Bool {
  publication.source == file.original.start &&
  value.physical_starts.get(publication.source)
  is Some({ run: original, file_managed: Some(managed), .. }) &&
  original == run &&
  !managed.closing &&
  managed.capture_work is Some(work) &&
  physical_equal(work, file.original.work)
}

///|
fn sdk_file_held_state_update(
  value : Instance,
  handle : Int,
  file : StoredFilePublicationCapture,
  run : Int,
) -> Result[@host.ClientSavedRunStateUpdate?, Int] {
  guard file.state_export is Some(state_handle) else { return Ok(None) }
  guard value.commit_exports.get(state_handle) is Some(output) &&
    output.publication == handle &&
    output.produced &&
    !output.closing &&
    !output.output_closed &&
    output.projection is Some(SDKMeasuredRunState(_, original_run, _, true)) &&
    original_run == run &&
    output.sdk_run_state_update is Some(update) else {
    return Err(-35)
  }
  Ok(Some(update))
}

///|
/// Read the exact held candidate's predecessor or successor from the same
/// physical Store, without using state updates to authorize Request or Commit.
fn sdk_file_live_state_read_current(
  value : Instance,
  handle : Int,
  publication : StoredPublication,
  file : StoredFilePublicationCapture,
  run : Int,
  current : StoredRunConfiguration,
  confirm_update? : @host.ClientSavedRunStateUpdate? = None,
) -> Result[Unit, Int] {
  let custody = sdk_file_capture_custody_current(value, publication, file)
  if custody != 0 {
    return Err(custody)
  }
  sdk_file_held_state_update(value, handle, file, run).bind(update => {
    if confirm_update is Some(expected) &&
      !(update is Some(active) && physical_equal(active, expected)) {
      return Err(-35)
    }
    with_sdk_file_state_snapshot(
      value,
      publication,
      file,
      run,
      current,
      (_, _, _) => {
        let status = file_publication_request_current(value, file.original.work)
        if status != 0 {
          return Err(status)
        }
        let custody = sdk_file_capture_custody_current(value, publication, file)
        if custody != 0 {
          return Err(custody)
        }
        sdk_file_held_state_update(value, handle, file, run).bind(still_held => {
          match (update, still_held) {
            (None, None) => Ok(())
            (Some(original), Some(active)) if physical_equal(active, original) =>
              Ok(())
            _ => Err(-35)
          }
        })
      },
      saved_state_update=update,
      read_predecessor=confirm_update is None,
    )
  })
}

///|
/// Sealed payload readers already select the File publication, and derive its
/// exact Run from the original start. This path grants no payload mutation.
fn sdk_file_observed_payload_current(
  value : Instance,
  handle : Int,
  publication : StoredPublication,
  file : StoredFilePublicationCapture,
  current : StoredRunConfiguration,
) -> Result[Unit, Int] {
  guard value.physical_starts.get(publication.source) is Some({ run, .. }) &&
    value.runs.get(run) is Some(_) else {
    return Err(-35)
  }
  sdk_file_live_state_read_current(
    value, handle, publication, file, run, current,
  )
}

///|
/// Check the original physical Run loan behind this publication. This is only
/// a nominal routing fence; current Account read and publisher checks remain
/// in the original RunState export. No admission, state or ACK is issued here.
pub fn validate_publication_run(
  nonce : Int64,
  handle : Int,
  run : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(publication) &&
    value.runs.get(run) is Some(original_run) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  let owns_run = match publication.file {
    Some(file) => sdk_file_publication_owns_run(value, publication, file, run)
    None =>
      value.run_invocations.get(publication.source) is Some(invocation) &&
      value.computes.get(invocation.compute) is Some(compute) &&
      stored_compute_original_run(value, compute) is Some(compute_run) &&
      physical_equal(original_run, compute_run)
  }
  if !owns_run {
    return -2
  }
  match run_configuration_current(value, current) {
    Err(code) => return code
    Ok(_) => ()
  }
  let checked = match publication.file {
    Some(file) =>
      checked_publication_commit_view(value, publication, () => {
        sdk_file_live_state_read_current(
          value, handle, publication, file, run, current,
        )
      })
    None => publication_commit_export_view(value, publication, current.account)
  }
  match checked {
    Err(code) => code
    Ok(_) => 0
  }
}
