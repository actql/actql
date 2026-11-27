///|
fn publication_result_count(record : StoredPublication) -> Int {
  if record.saved_effect is Some({ prepared: Some(original), .. }) {
    return original.result_count()
  }
  match record.file {
    Some(file) => file.results.length()
    None => record.publications.length()
  }
}

///|
fn[T] with_sdk_file_payload_result(
  value : Instance,
  publication : StoredPublication,
  file : StoredFilePublicationPreflight,
  ordinal : Int,
  account : @authorization.AdmittedAccountConfiguration,
  use_result : (
    @local_run.LocalCapturedTaskPublicationPreflight[Ref[Int], Int],
    @local_run.LocalCapturedTaskResultPublication[Ref[Int], Int],
    () -> Result[
      Unit,
      @local_run.LocalCapturedTaskPublicationPreflightIssue[Int],
    ],
  ) -> Result[T, @local_run.LocalCapturedTaskPublicationPreflightIssue[Int]],
) -> Result[T, Int] {
  guard publication.file is Some(capture) else { return Err(-35) }
  with_sdk_file_payload_result_current(
    publication,
    file,
    ordinal,
    () => sdk_file_capture_require_current(value, publication, capture, account),
    use_result,
  )
}

///|
fn[T] with_sdk_file_payload_result_current(
  publication : StoredPublication,
  file : StoredFilePublicationPreflight,
  ordinal : Int,
  recheck : () -> Result[
    Unit,
    @local_run.LocalCapturedTaskPublicationPreflightIssue[Int],
  ],
  use_result : (
    @local_run.LocalCapturedTaskPublicationPreflight[Ref[Int], Int],
    @local_run.LocalCapturedTaskResultPublication[Ref[Int], Int],
    () -> Result[
      Unit,
      @local_run.LocalCapturedTaskPublicationPreflightIssue[Int],
    ],
  ) -> Result[T, @local_run.LocalCapturedTaskPublicationPreflightIssue[Int]],
) -> Result[T, Int] {
  guard publication.produced &&
    !publication.closing &&
    publication.file is Some(capture) &&
    physical_equal(capture.original, file) &&
    capture.results.get(ordinal) is Some(result) &&
    file.prepared is Some(preflight) else {
    return Err(-35)
  }
  use_result(preflight, result, recheck).map_err(file_preflight_issue)
}

///|
/// An already Sealed live record may be read against the observed state
/// successor. Existing replay and physical write gates keep their own checks.
fn observed_live_payload_current(
  value : Instance,
  record : StoredPayloadRecord,
  current_configuration : Int,
) -> Result[Unit, Int] {
  if value.payload_requests.get(record.request) is Some(request) &&
    value.publications.get(request.publication)
    is Some({ file: Some(file), .. } as parent) {
    guard request.produced &&
      !request.closing &&
      request.request is Some(issued) &&
      record.source is LiveRequest &&
      record.confirmed &&
      !record.closing &&
      record.record is Some(original) &&
      @payload.publication_payload_record_state(original) is Sealed &&
      physical_equal(
        @payload.publication_payload_record_request(original),
        issued,
      ) &&
      value.run_configurations.get(current_configuration) is Some(current) else {
      return Err(-35)
    }
    return sdk_file_observed_payload_current(
      value,
      request.publication,
      parent,
      file,
      current,
    )
  }
  if payload_record_current(value, record, current_configuration) {
    Ok(())
  } else {
    Err(-32)
  }
}

///|
/// Observe an already begun physical payload leaf while its original record
/// is still held. Parent close seals new requests/replay/Commit; this consumes
/// only the retained request and the original current reader.
fn sdk_file_payload_confirmation_current(
  value : Instance,
  record : StoredPayloadRecord,
  request : StoredPayloadRequest,
  publication : StoredPublication,
  capture : StoredFilePublicationCapture,
  current_configuration : Int,
) -> Bool {
  guard record.produced &&
    record.begun &&
    record.record is Some(physical) &&
    request.produced &&
    request.request is Some(issued) &&
    physical_equal(
      @payload.publication_payload_record_request(physical),
      issued,
    ) &&
    value.run_configurations.get(current_configuration) is Some(current) &&
    value.publication_preflights.get(publication.preflight)
    is Some({ origin: FilePublicationPreflight(file), produced: true, .. }) &&
    physical_equal(file, capture.original) &&
    file.request_publisher is Some(_) &&
    file.prepared is Some(_) &&
    capture.results.get(request.index) is Some(_) &&
    publication.results.get(request.index) is Some(result_handle) &&
    value.result_exports.get(result_handle)
    is Some(
      {
        origin: FileNamedResult(result),
        result: ordinal,
        stream: Some(_),
        issue: None,
        ..
      }
    ) &&
    result.parent == publication.preflight &&
    ordinal == request.index &&
    physical_equal(result.work, file.work) else {
    return false
  }
  file_publication_preflight_current(value, file, current.account) == 0
}
