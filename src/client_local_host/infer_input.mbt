///|
/// Input preparation under the normal checked Program owner. The existing
/// Local chain owns intermediate completions until the model consumer ends.
/// No ModelTask provider is invoked by input preparation.
struct ClientInferInputExecution {
  prefix : @local.ManagedProviderExecution?
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
  ProducerRead(@execution.ProducerReadIssue)
  Capture(@query.CapturedSourceIssue)
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
  // This entry owns an empty input list. Acquired prefixes must be started
  // with their actual captured input owner, never through the empty route.
  if @publication_host.client_infer_prefix_owner(prepared, task, step) is None {
    return Err(UnsupportedProgram)
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
  start_client_infer_input_sequence(
    sequence,
    step,
    [],
    execution,
    measurement,
    mapping,
  )
}

///|
/// Start the Local segment after source capture without replaying the scan.
/// The caller owns the capture until this input execution is reclaimed.
pub fn start_client_acquired_infer_input(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  source : @query.CapturedInputSource,
  registry_body : String,
  values_body : String,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  mapping : @execution.InferPreparationLimits,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  guard @publication_host.client_acquired_infer_prefix_owner(
      prepared, task, step,
    )
    is Some(owner) &&
    @publication_host.prepare_client_query_acquisition(prepared, task, 0)
    is Ok(query) &&
    @sourceviews.query_acquisition_capture(query) is @pipeline.Step(capture) &&
    capture + 1 < step else {
    return Err(UnsupportedProgram)
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
    is Some(prefix) &&
    @execution.select_generated_sequence_range(prefix, capture + 1, step - 1)
    is Some(sequence) else {
    return Err(UnsupportedProgram)
  }
  let inputs : Array[@local.ManagedProviderInput] = []
  for consumer in (capture + 1)..<step {
    guard @lower.node_at(@lower.bound_preparation(owner), consumer)
      is Some(node) else {
      return Err(UnsupportedProgram)
    }
    for port in 0..<@lower.node_input_count(node) {
      guard @lower.node_input_target(node, port) is Some(@pipeline.Step(target)) else {
        return Err(UnsupportedProgram)
      }
      if target > capture {
        continue
      }
      let bound = match
        @query.bind_captured_source_operation(source, owner, consumer, port) {
        Ok(bound) => bound
        Err(issue) => return Err(Capture(issue))
      }
      let read = match
        @execution.prepare_producer_read(
          owner,
          bound,
          execution.rows.operation_entries,
          measurement.max_bytes,
        ) {
        Ok(read) => read
        Err(issue) => return Err(ProducerRead(issue))
      }
      inputs.push(@local.managed_provider_relation_input(read))
    }
  }
  start_client_infer_input_sequence(
    sequence, step, inputs, execution, measurement, mapping,
  )
}

///|
fn start_client_infer_input_sequence(
  sequence : @execution.GeneratedSequence,
  step : Int,
  inputs : Array[@local.ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  mapping : @execution.InferPreparationLimits,
  restored_input? : @execution.CompletedOutput? = None,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  if mapping.max_work < 0 || execution.max_work < 0 {
    return Err(InvalidLimits)
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
  // A restored input must carry the actual receiving completion. This bind
  // rejects foreign occurrences and representations before mapping any row.
  let control = @bounded.control()
  let restored_mapping = match restored_input {
    None => None
    Some(output) => {
      let bound = match
        @execution.bind_infer_completed_input(
          expressions, owner, target, output,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Mapping(issue))
      }
      match @execution.start_infer_rows_preparation(control, bound, mapping) {
        Ok(value) => Some(value)
        Err(issue) => return Err(Mapping(issue))
      }
    }
  }
  let prefix = if restored_input is Some(_) {
    None
  } else {
    guard @local.local_bounded_relation_provider(
        execution, measurement, sequence,
      )
      is Some(provider) else {
      return Err(UnsupportedProgram)
    }
    let prefix = match
      @local.start_managed_provider_with_inputs_and_execution(
        provider,
        sequence,
        inputs,
        execution.rows.max_rows,
        measurement.max_bytes,
        execution,
      ) {
      Ok(value) => Some(value)
      Err(issue) => return Err(Local(issue))
    }
    prefix
  }
  Ok({
    prefix,
    sequence,
    infer_step: step,
    owner,
    target,
    expressions,
    limits: mapping,
    control,
    mapping: restored_mapping,
    rows: None,
    completed_input: restored_input,
    prefix_done: restored_input is Some(_),
    stopped: false,
    cancelled: false,
    reclaimed: false,
    work: 0L,
  })
}

///|
/// Map a Store-readmitted completion through the normal checked INFER input
/// owner without executing its prefix again. The caller retains the admitted
/// receiving completion and physical Store custody until this consumer ends.
/// CIDs or caller-authored rows cannot substitute for this opaque completion.
pub fn start_client_restored_infer_input(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  input : @execution.CompletedOutput,
  registry_body : String,
  values_body : String,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  mapping : @execution.InferPreparationLimits,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  if @publication_host.client_infer_prefix_owner(prepared, task, step) is None {
    return Err(UnsupportedProgram)
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
  start_client_infer_input_sequence(
    sequence,
    step,
    [],
    execution,
    measurement,
    mapping,
    restored_input=Some(input),
  )
}

///|
/// The common task driver supplies exact producer reads for a composed Unit.
/// Reuse the component's Local-prefix and Infer-row mapping owners; finished
/// caller-authored rows are not an accepted input to this operation.
pub fn start_client_composed_infer_input(
  occurrence : @publication_host.ClientInferOccurrence,
  sequence : @execution.GeneratedSequence,
  inputs : Array[@local.ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  mapping : @execution.InferPreparationLimits,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  if !physical_equal(
      @publication_host.client_infer_occurrence_preparation(occurrence),
      @execution.generated_sequence_owner(sequence),
    ) ||
    @execution.generated_sequence_step_count(sequence) != step {
    return Err(UnsupportedProgram)
  }
  for index in 0..<step {
    if @execution.generated_sequence_step_index_at(sequence, index) !=
      Some(index) {
      return Err(UnsupportedProgram)
    }
  }
  start_client_infer_input_sequence(
    sequence, step, inputs, execution, measurement, mapping,
  )
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
    guard active.prefix is Some(prefix) else { return Err(InvalidLimits) }
    let poll = match @local.advance_managed_provider(prefix, quantum) {
      Ok(value) => value
      Err(issue) => {
        active.stopped = @local.managed_provider_stopped(prefix)
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
  } else if active.prefix is Some(prefix) {
    @local.cancel_managed_provider(prefix) |> ignore
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
  if active.prefix is Some(prefix) {
    match @local.cleanup_managed_provider(prefix) {
      Ok(true) => ()
      Ok(false) => return Ok(false)
      Err(issue) => return Err(Local(issue))
    }
  }
  active.reclaimed = true
  active.completed_input = None
  Ok(true)
}
