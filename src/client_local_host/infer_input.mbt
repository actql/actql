///|
/// Input preparation under the normal checked Program owner. The existing
/// Local chain owns intermediate completions until the model consumer ends.
/// No ModelTask provider is invoked by input preparation.
struct ClientInferInputExecution {
  prefix : @local.ManagedProviderExecution
  sequence : @execution.GeneratedSequence
  infer_step : Int
  owner : @lower.BoundPrepared
  target : @pipeline.Target
  expressions : @lower.PreparedInferInputs
  limits : @execution.InferPreparationLimits
  control : @bounded.Control
  mut mapping : @execution.InferRowsPreparation?
  mut rows : @execution.PreparedInferRows?
  mut completed_input : @execution.CompletedOutput?
  mut prefix_done : Bool
  mut stopped : Bool
  mut cancelled : Bool
  mut reclaimed : Bool
  mut work : Int64
}

///|
pub(all) enum ClientInferInputIssue {
  UnsupportedProgram
  InvalidLimits
  Preparation(@lower.InferInputIssue)
  Local(@connector.FixedComputeIssue)
  Mapping(@execution.InferPreparationIssue)
}

///|
pub enum ClientInferInputPoll {
  Continue(work~ : Int64)
  Complete(@execution.PreparedInferRows, work~ : Int64)
  Stopped(work~ : Int64)
  Failed(ClientInferInputIssue, work~ : Int64)
}

///|
/// Start only a source-free, exact checked prefix. The installed registry is
/// admitted by the same preparation used by ordinary Local execution.
pub fn start_client_infer_input(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  registry_body : String,
  values_body : String,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  mapping : @execution.InferPreparationLimits,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  if mapping.max_work < 0 || execution.max_work < 0 {
    return Err(InvalidLimits)
  }
  guard prepare_client_infer_prefix(
      prepared,
      task,
      step,
      registry_body,
      values_body,
      fragment_body~,
      ordered_body~,
    )
    is Some(sequence) else {
    return Err(UnsupportedProgram)
  }
  let owner = @execution.generated_sequence_owner(sequence)
  guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) &&
    @lower.node_input_target(node, 0) is Some(target) else {
    return Err(UnsupportedProgram)
  }
  let expressions = match
    @lower.prepare_infer_inputs(
      infer,
      @lower.parameter_bindings(owner),
      @publication_host.client_standard_values_sequence_limits().expressions,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ClientInferInputIssue::Preparation(issue))
  }
  guard @local.local_bounded_relation_provider(execution, measurement, sequence)
    is Some(provider) else {
    return Err(UnsupportedProgram)
  }
  let prefix = match
    @local.start_managed_provider_with_inputs_and_execution(
      provider,
      sequence,
      [],
      execution.rows.max_rows,
      measurement.max_bytes,
      execution,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Local(issue))
  }
  Ok({
    prefix,
    sequence,
    infer_step: step,
    owner,
    target,
    expressions,
    limits: mapping,
    control: @bounded.control(),
    mapping: None,
    rows: None,
    completed_input: None,
    prefix_done: false,
    stopped: false,
    cancelled: false,
    reclaimed: false,
    work: 0L,
  })
}

///|
/// Only the mapped rows actually completed by this input execution can select
/// its acquisition output contract. Equal checked programs are not sufficient.
pub fn client_infer_completion_preparation(
  active : ClientInferInputExecution,
  rows : @execution.PreparedInferRows,
) -> @execution.CompletionPreparation? {
  guard !active.reclaimed &&
    active.rows is Some(actual) &&
    physical_equal(actual, rows) else {
    return None
  }
  @execution.prepare_infer_completion(active.sequence, rows, active.infer_step)
}

///|
/// Borrow the actual pre-INFER completion while its existing prefix owner
/// retains it. This does not copy rows or transfer cleanup responsibility.
pub fn client_infer_completed_input(
  active : ClientInferInputExecution,
) -> @execution.CompletedOutput? {
  guard !active.reclaimed &&
    active.completed_input is Some(output) &&
    @execution.completed_output_available(output) else {
    return None
  }
  Some(output)
}

///|
/// Each call advances exactly one existing child. A child transition does not
/// drain the next phase in the same call, preserving the caller's quantum.
pub fn advance_client_infer_input(
  active : ClientInferInputExecution,
  quantum : Int,
) -> Result[ClientInferInputPoll, ClientInferInputIssue] {
  if quantum <= 0 || active.stopped || active.reclaimed {
    return Err(InvalidLimits)
  }
  if active.cancelled && active.mapping is None && active.prefix_done {
    active.stopped = true
    return Ok(Stopped(work=active.work))
  }
  if !active.prefix_done {
    let poll = match @local.advance_managed_provider(active.prefix, quantum) {
      Ok(value) => value
      Err(issue) => {
        active.stopped = @local.managed_provider_stopped(active.prefix)
        return Err(Local(issue))
      }
    }
    match poll {
      @local.Continue(work~, ..) => {
        active.work += work
        Ok(Continue(work=active.work))
      }
      @local.Complete(output, work~, ..) => {
        active.work += work
        active.prefix_done = true
        active.completed_input = Some(output)
        if active.cancelled {
          active.stopped = true
          return Ok(Stopped(work=active.work))
        }
        let bound = match
          @execution.bind_infer_completed_input(
            active.expressions,
            active.owner,
            active.target,
            output,
          ) {
          Ok(value) => value
          Err(issue) => {
            active.stopped = true
            return Ok(Failed(Mapping(issue), work=active.work))
          }
        }
        active.mapping = match
          @execution.start_infer_rows_preparation(
            active.control,
            bound,
            active.limits,
          ) {
          Ok(value) => Some(value)
          Err(issue) => {
            active.stopped = true
            return Ok(Failed(Mapping(issue), work=active.work))
          }
        }
        Ok(Continue(work=active.work))
      }
      @local.Failed(issue, work~, ..) => {
        active.work += work
        active.stopped = true
        Ok(Failed(Local(issue), work=active.work))
      }
      @local.Stopped(work~, ..) => {
        active.work += work
        active.stopped = true
        Ok(Stopped(work=active.work))
      }
      @local.CarrierComplete(_, work~, ..) => {
        active.work += work
        active.stopped = true
        Ok(Failed(UnsupportedProgram, work=active.work))
      }
    }
  } else {
    guard active.mapping is Some(mapping) else { return Err(InvalidLimits) }
    match @execution.advance_infer_rows_preparation(mapping, quantum) {
      Ok(@execution.InferRowsContinue(work~)) =>
        Ok(Continue(work=active.work + work))
      Ok(@execution.InferRowsComplete(rows, work~)) => {
        active.rows = Some(rows)
        active.work += work
        active.stopped = true
        Ok(Complete(rows, work=active.work))
      }
      Ok(@execution.InferRowsStopped(_, work~)) => {
        active.work += work
        active.stopped = true
        Ok(Stopped(work=active.work))
      }
      Err(issue) => {
        active.stopped = true
        Ok(Failed(Mapping(issue), work=active.work))
      }
    }
  }
}

///|
pub fn cancel_client_infer_input(active : ClientInferInputExecution) -> Bool {
  if active.cancelled || active.stopped || active.reclaimed {
    return false
  }
  active.cancelled = true
  if active.prefix_done {
    @bounded.request_cancel(active.control) |> ignore
  } else {
    @local.cancel_managed_provider(active.prefix) |> ignore
  }
  true
}

///|
/// The ModelTask consumer must settle before its mapped rows and borrowed
/// prefix are reclaimed. This operation never starts or retries computation.
pub fn cleanup_client_infer_input(
  active : ClientInferInputExecution,
) -> Result[Bool, ClientInferInputIssue] {
  if active.reclaimed {
    return Ok(true)
  }
  if !active.stopped {
    return Ok(false)
  }
  if active.rows is Some(rows) {
    if !@execution.cleanup_prepared_infer_rows(rows) {
      return Ok(false)
    }
    active.rows = None
  }
  if active.mapping is Some(mapping) {
    match @execution.cleanup_infer_rows_preparation(mapping) {
      Ok(true) => ()
      Ok(false) => return Ok(false)
      Err(issue) => return Err(Mapping(issue))
    }
  }
  match @local.cleanup_managed_provider(active.prefix) {
    Ok(true) => ()
    Ok(false) => return Ok(false)
    Err(issue) => return Err(Local(issue))
  }
  active.reclaimed = true
  active.completed_input = None
  Ok(true)
}
