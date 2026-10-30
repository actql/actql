///|
pub(all) enum SourceAcquisitionIssue {
  InvalidLimits
  WorkLimit
  UnsupportedMode
  UnboundRequest
  MissingInput
} derive(Eq, Debug)

///|
/// The original bounded Source input, before any authored computation. This
/// boundary does not derive the narrower scan/filter/select Query profile or
/// establish coverage, authority, resource backing or completed observation.
struct SourceAcquisition {
  owner : PipelineRequests
  pipeline : @pipeline.CheckedPipeline
  source_index : Int
  input : @pipeline.Target
  mode : DirectMode
  request : ParameterizedRequest
  work : Int
}

///|
/// Retain the same checked request and its actual input position. Consumers
/// may select, sort, branch or publish that input directly; none is executed
/// here. Changes/checkpoint and unbound Host requests need their own lane.
pub fn derive_source_acquisition(
  requests : PipelineRequests,
  source_index : Int,
  max_work : Int,
) -> Result[SourceAcquisition, SourceAcquisitionIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if max_work == 0 {
    return Err(WorkLimit)
  }
  let mut remaining = max_work - 1
  guard pipeline_request_at(requests, source_index)
    is Some(Direct(mode, request)) else {
    return Err(UnsupportedMode)
  }
  if @environment.read_mode_kind(mode_contract(mode)) !=
    @environment.SnapshotMode ||
    !@environment.read_mode_bounded(mode_contract(mode)) ||
    mode_checkpoint(mode) is Some(_) {
    return Err(UnsupportedMode)
  }
  if request.host_bindings != 0 {
    return Err(UnboundRequest)
  }
  let pipeline = @collection.pipeline(
    @stages.collection(requests.uses.attachment.stage),
  )
  let name = declaration(mode_input(mode)).input_name
  for index in 0..<@pipeline.input_count(pipeline) {
    let (candidate, _) = @pipeline.input_at(pipeline, index).unwrap()
    // Charge both original name extents before comparing their contents.
    for cost in [1, name.length(), candidate.length()] {
      if cost > remaining {
        return Err(WorkLimit)
      }
      remaining -= cost
    }
    if candidate == name {
      return Ok({
        owner: requests,
        pipeline,
        source_index,
        input: @pipeline.Input(index),
        mode,
        request,
        work: max_work - remaining,
      })
    }
  }
  Err(MissingInput)
}

///|
pub fn source_acquisition_owner(value : SourceAcquisition) -> PipelineRequests {
  value.owner
}

///|
pub fn source_acquisition_pipeline(
  value : SourceAcquisition,
) -> @pipeline.CheckedPipeline {
  value.pipeline
}

///|
pub fn source_acquisition_source_index(value : SourceAcquisition) -> Int {
  value.source_index
}

///|
pub fn source_acquisition_input(value : SourceAcquisition) -> @pipeline.Target {
  value.input
}

///|
pub fn source_acquisition_mode(value : SourceAcquisition) -> DirectMode {
  value.mode
}

///|
/// This is the same bound typed request. Its existing canonical wire encoder
/// remains the only encoder, called under the receiving owner's reservation.
pub fn source_acquisition_request(
  value : SourceAcquisition,
) -> ParameterizedRequest {
  value.request
}

///|
pub fn source_acquisition_work(value : SourceAcquisition) -> Int {
  value.work
}
