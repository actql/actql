///|
pub(all) enum QueryAcquisitionIssue {
  InvalidLimits
  WorkLimit
  UnsupportedShape
  UnboundRequest
} derive(Eq, Debug)

///|
/// A semantic scan/filter/select boundary, never a backend completion claim.
struct QueryAcquisition {
  owner : PipelineRequests
  pipeline : @pipeline.CheckedPipeline
  source_index : Int
  input : @pipeline.Target
  filter_index : Int
  select_index : Int
  filter : @relation.CheckedOperation
  select : @relation.CheckedOperation
  work : Int
}

///|
/// Derive an exclusive scan -> filter -> select chain. Shared source or filter
/// outputs are deliberately outside this increment; consumers of select remain
/// outside capture. No registry, placement, cost or future observation is input.
pub fn derive_query_acquisition(
  requests : PipelineRequests,
  source_index : Int,
  max_work : Int,
) -> Result[QueryAcquisition, QueryAcquisitionIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let mut remaining = max_work
  if remaining == 0 {
    return Err(WorkLimit)
  }
  remaining -= 1
  guard pipeline_request_at(requests, source_index)
    is Some(Direct(mode, request)) else {
    return Err(UnsupportedShape)
  }
  // A finite snapshot read mode is not a requirement for snapshot isolation or
  // a provider snapshot token. Changes/checkpoint semantics are outside scope.
  if @environment.read_mode_kind(mode_contract(mode)) !=
    @environment.SnapshotMode ||
    mode_checkpoint(mode) is Some(_) {
    return Err(UnsupportedShape)
  }
  if request.host_bindings != 0 {
    return Err(UnboundRequest)
  }
  let uses = requests.uses
  guard pipeline_use_count(uses, source_index) == Some(1) &&
    pipeline_use_at(uses, source_index, 0) is Some(StepInput(filter_index, _)) else {
    return Err(UnsupportedShape)
  }
  let stage = uses.attachment.stage
  let pipeline = @collection.pipeline(@stages.collection(stage))
  guard @pipeline.step_at(pipeline, filter_index) is Some(filter_step) &&
    filter_step.input is Some(input) &&
    input is @pipeline.Input(_) &&
    filter_step.operation is @pipeline.Unary(filter) &&
    @relation.operation(filter) == @relation.Filter else {
    return Err(UnsupportedShape)
  }
  let mut selection : (Int, @relation.CheckedOperation)? = None
  // Inspect every edge, including off-chain consumers, before allocating a unit.
  for i in 0..<@pipeline.step_count(pipeline) {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let step = @pipeline.step_at(pipeline, i).unwrap()
    for j in 0..<@pipeline.input_occurrence_count(step) {
      if remaining == 0 {
        return Err(WorkLimit)
      }
      remaining -= 1
      let edge = @pipeline.input_occurrence_at(step, j).unwrap()
      if edge.target == @pipeline.Step(filter_index) {
        guard selection is None &&
          step.operation is @pipeline.Unary(select) &&
          @relation.operation(select) == @relation.Select else {
          return Err(UnsupportedShape)
        }
        selection = Some((i, select))
      }
    }
  }
  let results = @stage_results.stage_at(
    uses.results,
    @stages.stage_index(stage),
  ).unwrap()
  for i in 0..<@results.count(results) {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    if @results.target(@results.result_at(results, i).unwrap()) ==
      @pipeline.Step(filter_index) {
      return Err(UnsupportedShape)
    }
  }
  guard selection is Some((select_index, select)) else {
    return Err(UnsupportedShape)
  }
  Ok({
    owner: requests,
    pipeline,
    source_index,
    input,
    filter_index,
    select_index,
    filter,
    select,
    work: max_work - remaining,
  })
}

///|
pub fn query_acquisition_owner(v : QueryAcquisition) -> PipelineRequests {
  v.owner
}

///|
pub fn query_acquisition_pipeline(
  v : QueryAcquisition,
) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn query_acquisition_source_index(v : QueryAcquisition) -> Int {
  v.source_index
}

///|
pub fn query_acquisition_input(v : QueryAcquisition) -> @pipeline.Target {
  v.input
}

///|
/// The completed select output, not the provider response, is the capture port.
pub fn query_acquisition_capture(v : QueryAcquisition) -> @pipeline.Target {
  @pipeline.Step(v.select_index)
}

///|
pub fn query_acquisition_filter_index(v : QueryAcquisition) -> Int {
  v.filter_index
}

///|
pub fn query_acquisition_filter(
  v : QueryAcquisition,
) -> @relation.CheckedOperation {
  v.filter
}

///|
pub fn query_acquisition_select(
  v : QueryAcquisition,
) -> @relation.CheckedOperation {
  v.select
}

///|
pub fn query_acquisition_work(v : QueryAcquisition) -> Int {
  v.work
}

///|
/// These obligations are retained, not discharged by deriving the boundary.
pub(all) enum QueryAcquisitionRequirement {
  SourceAuthorityAndPolicy
  WholeScanAdmission
  CheckedExpressionDemand
  OutputContract
  LogicalLimits
  PhysicalLimits
  CompleteSourceCoverage
  ImmutableProcessCapture
} derive(Eq, Debug)

///|
pub fn query_acquisition_requirement_count(_v : QueryAcquisition) -> Int {
  8
}

///|
pub fn query_acquisition_requirement_at(
  _v : QueryAcquisition,
  index : Int,
) -> QueryAcquisitionRequirement? {
  match index {
    0 => Some(SourceAuthorityAndPolicy)
    1 => Some(WholeScanAdmission)
    2 => Some(CheckedExpressionDemand)
    3 => Some(OutputContract)
    4 => Some(LogicalLimits)
    5 => Some(PhysicalLimits)
    6 => Some(CompleteSourceCoverage)
    7 => Some(ImmutableProcessCapture)
    _ => None
  }
}

///|
pub fn query_acquisition_contract_cid() -> String {
  "sha256:4bb69dfaade0a15952fe23a8202a9475ff450c9f0fab93f9dd5cef1b82045ab1"
}
