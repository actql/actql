///|
pub enum AcquisitionIssue {
  InvalidLimits
  ForeignRequests
  WorkLimit
  PartialCorrelation(Int)
  MissingKeyedConsumer(Int)
  InvalidKeyedConsumer(Int, SourceUse)
  Mode(Int, ModeIssue)
  Request(Int, RequestIssue)
  Binding(Int, RequestParameterIssue)
}

///|
pub enum AcquisitionRequest {
  Direct(DirectMode, ParameterizedRequest)
  Keyed(KeyedMode, ParameterizedKeyedRequest)
}

///|
struct PipelineRequests {
  uses : PipelineUses
  parameters : RequestParameters
  entries : Array[AcquisitionRequest]
  work : Int
  pairs : Int
  nodes : Int
  text : Int
}

///|
priv suberror AcquisitionStop {
  AcquisitionStop(AcquisitionIssue)
}

///|
fn acquisition_charge(b : Budget, n : Int) -> Unit raise AcquisitionStop {
  if n > b.work {
    raise AcquisitionStop(WorkLimit)
  }
  b.work -= n
}

///|
/// Select and validate request forms against every actual consumer. This is not
/// completeness/capacity/authority admission or an executable acquisition plan.
pub fn check_pipeline_requests(
  uses : PipelineUses,
  parameters : RequestParameters,
  limits : RequestLimits,
) -> Result[PipelineRequests, AcquisitionIssue] {
  if limits.max_work < 0 ||
    limits.max_pairs < 0 ||
    limits.values.max_nodes < 0 ||
    limits.values.max_depth < 0 ||
    limits.values.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let context = parameters.context
  if !physical_equal(context.resolved, uses.attachment.inputs.resolved) {
    return Err(ForeignRequests)
  }
  let index = @stages.stage_index(uses.attachment.stage)
  let inputs = uses.attachment.inputs.stages[index]
  let b = { work: limits.max_work, }
  let mut pairs = limits.max_pairs
  let mut nodes = limits.values.max_nodes
  let mut text = limits.values.max_text_bytes
  let entries = []
  try {
    acquisition_charge(b, 1)
    for i in 0..<inputs.length() {
      acquisition_charge(b, 1)
      let input = inputs[i].input
      let correlation = @environment.source_request_correlation(
        input.selected.contract,
      )
      let mut keyed = false
      if correlation is Some(c) {
        let reserved : Map[String, Bool] = Map([])
        let count = @environment.source_correlation_pair_count(c)
        for j in 0..<count {
          let name = @environment.source_correlation_pair_at(c, j).unwrap().request.name
          acquisition_charge(b, 1)
          acquisition_charge(b, name.length())
          reserved[name] = true
        }
        acquisition_charge(b, input.declaration.input_name.length())
        let fields = context.fields
          .get((index, input.declaration.input_name))
          .unwrap_or([])
        let mut present = 0
        for field in fields {
          acquisition_charge(b, 1)
          acquisition_charge(b, field.field_name.length())
          if reserved.contains(field.field_name) {
            present += 1
          }
        }
        if present != 0 && present != count {
          raise AcquisitionStop(PartialCorrelation(i))
        }
        if present == 0 {
          keyed = true
          if uses.entries[i].is_empty() {
            raise AcquisitionStop(MissingKeyedConsumer(i))
          }
          for consumer in uses.entries[i] {
            acquisition_charge(b, 1)
            if !(consumer is JoinRight(_)) {
              raise AcquisitionStop(InvalidKeyedConsumer(i, consumer))
            }
          }
        }
      }
      let request_limits : RequestLimits = {
        max_work: b.work,
        max_pairs: pairs,
        values: {
          max_nodes: nodes,
          max_depth: limits.values.max_depth,
          max_text_bytes: text,
        },
      }
      if keyed {
        let mode = match select_keyed_mode(input, b.work) {
          Ok(v) => v
          Err(e) => raise AcquisitionStop(Mode(i, e))
        }
        acquisition_charge(b, keyed_mode_work(mode))
        let request = match
          check_keyed_request(context, input, {
            ..request_limits,
            max_work: b.work,
          }) {
          Ok(v) => v
          Err(e) => raise AcquisitionStop(Request(i, e))
        }
        let (work, used_pairs, used_nodes, used_text) = keyed_request_usage(
          request,
        )
        acquisition_charge(b, work)
        pairs -= used_pairs
        nodes -= used_nodes
        text -= used_text
        let bound = match
          bind_keyed_request_parameters(parameters, request, b.work) {
          Ok(v) => v
          Err(e) => raise AcquisitionStop(Binding(i, e))
        }
        acquisition_charge(b, parameterized_keyed_request_work(bound))
        entries.push(Keyed(mode, bound))
      } else {
        let mode = match select_direct_mode(input, b.work) {
          Ok(v) => v
          Err(e) => raise AcquisitionStop(Mode(i, e))
        }
        acquisition_charge(b, mode_work(mode))
        let request = match
          check_direct_request(context, input, {
            ..request_limits,
            max_work: b.work,
          }) {
          Ok(v) => v
          Err(e) => raise AcquisitionStop(Request(i, e))
        }
        let (work, used_pairs, used_nodes, used_text) = request_usage(request)
        acquisition_charge(b, work)
        pairs -= used_pairs
        nodes -= used_nodes
        text -= used_text
        let bound = match bind_request_parameters(parameters, request, b.work) {
          Ok(v) => v
          Err(e) => raise AcquisitionStop(Binding(i, e))
        }
        acquisition_charge(b, parameterized_request_work(bound))
        entries.push(Direct(mode, bound))
      }
    }
    Ok({
      uses,
      parameters,
      entries,
      work: limits.max_work - b.work,
      pairs: limits.max_pairs - pairs,
      nodes: limits.values.max_nodes - nodes,
      text: limits.values.max_text_bytes - text,
    })
  } catch {
    AcquisitionStop(e) => Err(e)
  }
}

///|
pub fn pipeline_requests_uses(v : PipelineRequests) -> PipelineUses {
  v.uses
}

///|
pub fn pipeline_requests_parameters(v : PipelineRequests) -> RequestParameters {
  v.parameters
}

///|
pub fn pipeline_requests_count(v : PipelineRequests) -> Int {
  v.entries.length()
}

///|
pub fn pipeline_request_at(
  v : PipelineRequests,
  i : Int,
) -> AcquisitionRequest? {
  v.entries.get(i)
}

///|
pub fn pipeline_requests_usage(v : PipelineRequests) -> (Int, Int, Int, Int) {
  (v.work, v.pairs, v.nodes, v.text)
}
