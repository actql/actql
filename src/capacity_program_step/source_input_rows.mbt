///|
pub(all) enum SourceInputRowsIssue {
  InvalidLimits
  WorkLimit
  InvalidInput
  ForeignRequest
  ForeignCarrier
  ForeignProfile
  SubjectMismatch
} derive(Eq, Debug)

///|
/// The actual checked Source input and its already resolved Catalog/Host
/// ceiling. This is not an observed row count, read grant or completed capture.
struct SourceInputRows {
  pipeline : @pipeline.CheckedPipeline
  input : Int
  requests : @environment.SourceRequestContracts
  request : @environment.SourceViewRequestContract
  rows : @environment.FileListingRows
  work : Int
}

///|
/// Owner-relative spelling. Unit conversion must reidentify the input, not
/// promote this process-local name to a persistent Program identity.
pub fn source_input_rows_subject(
  pipeline : @pipeline.CheckedPipeline,
  input : Int,
) -> String? {
  @pipeline.input_at(pipeline, input).map(pair => {
    "source-input:" + pair.0 + ":rows"
  })
}

///|
/// Bind an existing owned enforcement contract to the exact SourceView input.
/// Same schema/CID/value from another admission is not a substitute.
pub fn check_source_input_rows(
  pipeline : @pipeline.CheckedPipeline,
  input : Int,
  requests : @environment.SourceRequestContracts,
  request : @environment.SourceViewRequestContract,
  rows : @environment.FileListingRows,
  max_work : Int,
) -> Result[SourceInputRows, SourceInputRowsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let mut work = 0
  if work == max_work {
    return Err(WorkLimit)
  }
  work += 1
  guard @pipeline.input_at(pipeline, input) is Some((name, _)) &&
    @pipeline.input_contract_at(pipeline, input)
    is Some(@pipeline.SourceViewInput(_, declared, _, carrier)) &&
    name == declared &&
    @pipeline.input_producer(pipeline, input) is None else {
    return Err(InvalidInput)
  }
  if name.length() > max_work - work {
    return Err(WorkLimit)
  }
  work += name.length()
  if max_work - work < 3 {
    return Err(WorkLimit)
  }
  work += 3
  let view_member = @environment.source_request_member(request)
  guard @environment.source_request_for(requests, view_member) is Some(owned) &&
    physical_equal(owned, request) else {
    return Err(ForeignRequest)
  }
  guard @environment.source_view_carrier(
      @environment.source_request_carriers(requests),
      view_member,
    )
    is Some(expected) &&
    physical_equal(expected, carrier) else {
    return Err(ForeignCarrier)
  }
  guard @environment.source_request_file_listing(request) is Some(profile) &&
    physical_equal(profile, @environment.file_listing_rows_profile(rows)) else {
    return Err(ForeignProfile)
  }
  if @wire.limit_subject(@environment.file_listing_rows_claim(rows)) !=
    source_input_rows_subject(pipeline, input).unwrap() {
    return Err(SubjectMismatch)
  }
  Ok({ pipeline, input, requests, request, rows, work, })
}

///|
pub fn source_input_rows_pipeline(
  value : SourceInputRows,
) -> @pipeline.CheckedPipeline {
  value.pipeline
}

///|
pub fn source_input_rows_index(value : SourceInputRows) -> Int {
  value.input
}

///|
pub fn source_input_rows_requests(
  value : SourceInputRows,
) -> @environment.SourceRequestContracts {
  value.requests
}

///|
pub fn source_input_rows_request(
  value : SourceInputRows,
) -> @environment.SourceViewRequestContract {
  value.request
}

///|
pub fn source_input_rows_limit(
  value : SourceInputRows,
) -> @environment.FileListingRows {
  value.rows
}

///|
pub fn source_input_rows_work(value : SourceInputRows) -> Int {
  value.work
}
