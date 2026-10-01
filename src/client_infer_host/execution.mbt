///|
/// Installed execution bounds. Run, model dependency and egress admission
/// precede this physical operation; these limits cannot grant model access.
pub(all) struct Limits {
  input : @relation.SequenceExecutionLimits
  measurement : @relation.FixedInputGuardMeasureLimits
  mapping : @relation.InferPreparationLimits
  model : @model.ModelExecutionLimits
  output_rows : Int
  output_values : @relation.ValueLimits
  output_work : Int
  output_workspace : Int
}

///|
pub(all) enum Issue {
  InvalidAdvance
  Input(@input.ClientInferInputIssue)
  Model(@model.ModelExecutionIssue)
}

///|
enum Phase {
  Input
  Model
  Output
  Handoff
  Terminal
}

///|
pub enum Poll {
  Continue(work~ : Int64)
  Complete(@relation.CompletedOutput, work~ : Int64)
  Failed(Issue, work~ : Int64)
  Stopped(work~ : Int64)
}

///|
/// One physical owner composes existing bounded children. It is neither a
/// Run state machine nor a retry engine. The installing Host supplies an
/// admitted fixed request identity, provider and envelope before dispatch.
pub struct Execution {
  prepared : @publication_host.PreparedClientProgram
  input : @input.ClientInferInputExecution
  provider : @model.ModelProvider
  fixed_request_cid : String
  limits : Limits
  mut rows : @relation.PreparedInferRows?
  mut model : @model.ModelExecution?
  mut capture : @model.ModelCaptureBundle?
  mut output : @model.ModelOutputPreparation?
  mut completed : @relation.CompletedOutput?
  mut phase : Phase
  mut cancelled : Bool
  mut advancing : Bool
  mut reclaimed : Bool
  mut work : Int64
  mut child_work : Int64
  mut output_uses : Int
}

///|
pub struct OutputUse {
  owner : Execution
  output : @relation.CompletedOutput
  mut released : Bool
}

///|
/// The original Program must prepare and execute its own input prefix. No
/// caller can substitute finished rows or a separately assembled completion.
pub fn start(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry : String,
  values : String,
  provider : @model.ModelProvider,
  fixed_request_cid : String,
  limits : Limits,
) -> Result[Execution, Issue] {
  if limits.output_rows < 0 ||
    limits.output_work < 0 ||
    limits.output_workspace < 0 {
    return Err(InvalidAdvance)
  }
  if fixed_request_cid.length() != 71 ||
    !fixed_request_cid.has_prefix("sha256:") {
    return Err(Model(@model.RequestIdentity))
  }
  for index in 7..<71 {
    let c = fixed_request_cid[index].to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      return Err(Model(@model.RequestIdentity))
    }
  }
  let input = match
    @input.start_client_infer_input(
      prepared,
      0,
      step,
      registry,
      values,
      limits.input,
      limits.measurement,
      limits.mapping,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  Ok({
    prepared,
    input,
    provider,
    fixed_request_cid,
    limits,
    rows: None,
    model: None,
    capture: None,
    output: None,
    completed: None,
    phase: Phase::Input,
    cancelled: false,
    advancing: false,
    reclaimed: false,
    work: 0L,
    child_work: 0L,
    output_uses: 0,
  })
}

///|
pub fn matches(
  active : Execution,
  prepared : @publication_host.PreparedClientProgram,
) -> Bool {
  physical_equal(active.prepared, prepared) && !active.reclaimed
}

///|
fn account(active : Execution, child_work : Int64) -> Bool {
  if child_work < active.child_work ||
    child_work - active.child_work > 9223372036854775807L - active.work {
    return false
  }
  active.work += child_work - active.child_work
  active.child_work = child_work
  true
}

///|
fn fail(active : Execution, issue : Issue) -> Poll {
  active.phase = Terminal
  Failed(issue, work=active.work)
}

///|
fn stopped(active : Execution) -> Poll {
  active.phase = Terminal
  active.completed = None
  Stopped(work=active.work)
}

///|
fn advance_child(active : Execution, quantum : Int) -> Poll {
  match active.phase {
    Input =>
      match @input.advance_client_infer_input(active.input, quantum) {
        Err(issue) => fail(active, Input(issue))
        Ok(@input.Continue(work~)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          Continue(work=active.work)
        }
        Ok(@input.Complete(rows, work~)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          active.rows = Some(rows)
          // The child is physically stopped. Cancellation at this transition
          // cannot start the next child or release this retained input early.
          if active.cancelled {
            return stopped(active)
          }
          active.model = match
            @model.start_model_execution(
              rows,
              active.provider,
              active.fixed_request_cid,
              active.limits.model,
            ) {
            Ok(value) => Some(value)
            Err(issue) => return fail(active, Model(issue))
          }
          active.child_work = 0L
          active.phase = Model
          Continue(work=active.work)
        }
        Ok(@input.Failed(issue, work~)) => {
          account(active, work) |> ignore
          fail(active, Input(issue))
        }
        Ok(@input.Stopped(work~)) => {
          account(active, work) |> ignore
          stopped(active)
        }
      }
    Model => {
      guard active.model is Some(model) else {
        return fail(active, InvalidAdvance)
      }
      match @model.advance_model_execution(model, quantum) {
        Err(issue) => fail(active, Model(issue))
        Ok(@model.Continue(_, work)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          Continue(work=active.work)
        }
        Ok(@model.Completed(capture, _, work)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          active.capture = Some(capture)
          if active.cancelled {
            return stopped(active)
          }
          guard active.rows is Some(rows) &&
            @input.client_infer_completion_preparation(active.input, rows)
            is Some(completion) else {
            return fail(active, Model(@model.OutputIdentity))
          }
          active.output = match
            @model.start_model_output_preparation(
              model,
              completion,
              active.limits.output_rows,
              active.limits.output_values,
              active.limits.output_work,
              active.limits.output_workspace,
            ) {
            Ok(value) => Some(value)
            Err(issue) => return fail(active, Model(issue))
          }
          active.child_work = 0L
          active.phase = Output
          Continue(work=active.work)
        }
        Ok(@model.Failed(issue, _, work)) => {
          account(active, work) |> ignore
          fail(active, Model(issue))
        }
        Ok(@model.Stopped(_, _, work)) => {
          account(active, work) |> ignore
          stopped(active)
        }
      }
    }
    Output => {
      guard active.output is Some(output) else {
        return fail(active, InvalidAdvance)
      }
      match @model.advance_model_output_preparation(output, quantum) {
        Err(issue) => fail(active, Model(issue))
        Ok(@relation.AdmittedOutputContinue(work~)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          Continue(work=active.work)
        }
        Ok(@relation.AdmittedOutputComplete(_, work~)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          if active.cancelled {
            return stopped(active)
          }
          active.completed = match @model.complete_model_output(output) {
            Ok(value) => Some(value)
            Err(issue) => return fail(active, Model(issue))
          }
          active.phase = Handoff
          Continue(work=active.work)
        }
        Ok(@relation.AdmittedOutputFailed(_, work~)) => {
          account(active, work) |> ignore
          fail(active, Model(@model.OutputValue))
        }
        Ok(@relation.AdmittedOutputStopped(work~)) => {
          account(active, work) |> ignore
          stopped(active)
        }
      }
    }
    Handoff => {
      if active.cancelled {
        return stopped(active)
      }
      guard active.completed is Some(completed) else {
        return fail(active, InvalidAdvance)
      }
      active.phase = Terminal
      Complete(completed, work=active.work)
    }
    Terminal => fail(active, InvalidAdvance)
  }
}

///|
/// Advance exactly one child. A transition never drains the following child
/// under the same quantum. Concurrent or reentrant calls retain the owner.
pub fn advance(active : Execution, quantum : Int) -> Result[Poll, Issue] {
  if quantum <= 0 ||
    active.advancing ||
    active.reclaimed ||
    active.phase is Terminal {
    return Err(InvalidAdvance)
  }
  active.advancing = true
  let poll = advance_child(active, quantum)
  active.advancing = false
  Ok(poll)
}

///|
pub fn cancel(active : Execution) -> Bool {
  if active.cancelled || active.reclaimed || active.phase is Terminal {
    return false
  }
  active.cancelled = true
  match active.phase {
    Input => @input.cancel_client_infer_input(active.input) |> ignore
    Model =>
      if active.model is Some(model) {
        @model.request_model_cancel(model) |> ignore
      }
    Output =>
      if active.output is Some(output) {
        @model.cancel_model_output_preparation(output) |> ignore
      }
    Handoff | Terminal => ()
  }
  true
}

///|
pub fn completed(poll : Poll) -> @relation.CompletedOutput? {
  match poll {
    Complete(value, ..) => Some(value)
    _ => None
  }
}

///|
/// Publication and downstream consumers retain separate uses. One consumer's
/// release cannot authorize cleanup while another still needs the output.
pub fn acquire_output(active : Execution) -> OutputUse? {
  guard !active.reclaimed &&
    !active.cancelled &&
    active.phase is Terminal &&
    active.completed is Some(output) &&
    active.output_uses < 2147483647 else {
    return None
  }
  active.output_uses += 1
  Some({ owner: active, output, released: false, })
}

///|
pub fn output(value : OutputUse) -> @relation.CompletedOutput? {
  if value.released || value.owner.reclaimed {
    None
  } else {
    Some(value.output)
  }
}

///|
pub fn release_output(value : OutputUse) -> Bool {
  if value.released {
    return false
  }
  value.released = true
  value.owner.output_uses -= 1
  true
}

///|
/// A handoff is a yield boundary, not yet publication or ownership transfer.
pub fn handoff_pending(active : Execution) -> Bool {
  !active.reclaimed && active.phase is Handoff
}

///|
/// This is the child execution's provisional capture, not a durable Run or
/// model-slot capture artifact. The formal evidence owner seals it separately.
pub fn capture(active : Execution) -> @model.ModelCaptureBundle? {
  if active.reclaimed || active.cancelled || active.completed is None {
    None
  } else {
    active.capture
  }
}

///|
/// Existing installed Local bounds for the initial source-free configuration.
/// This preset does not resolve model policy, dependencies or authorization.
pub fn standard_limits() -> Limits {
  let values : @relation.ValueLimits = {
    max_nodes: 20000,
    max_text_bytes: 500000,
    max_depth: 100,
    max_work: 20000000,
  }
  {
    input: {
      rows: {
        max_rows: 100,
        metadata_entries: 10000,
        retained_entries: 10000,
        operation_entries: 10000,
        input_values: values,
        output_values: values,
      },
      max_work: values.max_work,
      max_frames: 100,
    },
    measurement: {
      max_work: values.max_work,
      max_bytes: values.max_text_bytes,
      max_nodes: values.max_nodes,
      max_depth: values.max_depth,
    },
    mapping: {
      max_items: 100,
      max_work: values.max_work,
      max_frames: 100,
      max_workspace_slots: 10000,
      values: {
        max_nodes: values.max_nodes,
        max_depth: values.max_depth,
        max_text_bytes: values.max_text_bytes,
      },
      logical: {
        max_input_rows: 100L,
        max_value_bytes: 10000L,
        max_live_value_bytes: 100000L,
        max_work: values.max_work.to_int64(),
      },
    },
    model: {
      max_items: 100,
      max_work: 10000,
      max_request_bytes: 65536L,
      max_response_bytes: 65536L,
      value_limits: { max_nodes: 10000, max_depth: 64, max_text_bytes: 65536, },
      ledger: {
        planning_work: 10000,
        attempts: 100,
        holdings: 100,
        transfer_bytes: 13107200L,
        retained_bytes: 6553600L,
        execution_bytes: 6553600L,
      },
    },
    output_rows: 100,
    output_values: values,
    output_work: values.max_work,
    output_workspace: 10000,
  }
}

///|
/// Physical settlement is separate from reclamation. Keep output, capture,
/// mapped-input and prefix custody in this order until all pins are released.
pub fn cleanup(active : Execution) -> Result[Bool, Issue] {
  if active.reclaimed {
    return Ok(true)
  }
  if active.advancing || !(active.phase is Terminal) || active.output_uses > 0 {
    return Ok(false)
  }
  if active.output is Some(output) {
    match @model.cleanup_model_output_preparation(output) {
      Ok(true) => ()
      Ok(false) => return Ok(false)
      Err(issue) => return Err(Model(issue))
    }
    active.output = None
    active.completed = None
  }
  if active.model is Some(model) {
    match @model.cleanup_model_execution(model) {
      Ok(true) => ()
      Ok(false) => return Ok(false)
      Err(issue) => return Err(Model(issue))
    }
    active.model = None
    active.capture = None
  }
  match @input.cleanup_client_infer_input(active.input) {
    Ok(true) => {
      active.rows = None
      active.reclaimed = true
      Ok(true)
    }
    Ok(false) => Ok(false)
    Err(issue) => Err(Input(issue))
  }
}
