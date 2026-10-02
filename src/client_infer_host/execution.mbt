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
  identity : IdentityLimits
}

///|
/// Input identity is a separate bounded conversion before model dispatch.
pub(all) struct IdentityLimits {
  rows : Int
  wire : @relation.RowWireLimits
  logical_wire : @relation.RowWireLimits
  schema : @relation.RelationSchemaIdentityLimits
  work : Int
  workspace : Int
}

///|
pub(all) enum Issue {
  InvalidAdvance
  Input(@input.ClientInferInputIssue)
  Model(@model.ModelExecutionIssue)
  Capacity(@publication_host.ClientInferHostCapacityIssue)
  IdentityExport(@relation.CompletedExportIssue)
  CallScope(@publication_host.ClientInferCallScopeIssue)
}

///|
enum Phase {
  Input
  Identity
  Model
  Output
  Handoff
  Terminal
}

///|
enum Source {
  Physical(@model.ModelProvider)
  Replay(@model.VerifiedModelCapture)
  Restored(@publication.ModelCaptureBundleRead)
  RestoredSlots(@model.ModelSlotReplayRead)
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
  source : Source
  fixed_request_cid : String
  step : Int
  plan : @publication_host.ClientInferPlanGraph?
  limits : Limits
  mut rows : @relation.PreparedInferRows?
  mut identity : @relation.CompletedRelationIdentityScan?
  mut call_scope : @publication_host.ClientInferCallScope?
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
  mut run_binding : ExecutionRunBinding?
  mut dispatch_admission : @publication_host.ClientInferDispatchAdmission?
  mut quantity_capacity : @model.ModelQuantityCapacity?
  mut physical_preflight : @model.ModelPhysicalPreflight?
  mut egress_admission : @publication_host.ClientInferEgressAdmission?
  mut final_quantity_usage : @resources.QuantityUsage?
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
  plan? : @publication_host.ClientInferPlanGraph? = None,
) -> Result[Execution, Issue] {
  start_owned(
    prepared,
    step,
    registry,
    values,
    Physical(provider),
    fixed_request_cid,
    limits,
    plan,
  )
}

///|
/// Reconstruction follows the ordinary bounded prefix and identity scan.
/// It cannot redispatch: the only model source is an existing checked capture.
pub fn start_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry : String,
  values : String,
  capture : @model.VerifiedModelCapture,
  limits : Limits,
  plan : @publication_host.ClientInferPlanGraph,
) -> Result[Execution, Issue] {
  guard @model.retain_verified_model_capture(capture) is Some(retained) else {
    return Err(Model(@model.OutputIdentity))
  }
  let started = start_owned(
    prepared,
    step,
    registry,
    values,
    Replay(retained),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    Some(plan),
  )
  if started is Err(_) {
    @model.release_verified_model_capture(retained) |> ignore
  }
  started
}

///|
/// A fresh normal Program executes its prefix before verifying saved capture
/// records. No provider is installed in this operation or used as a fallback.
pub fn start_restored_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry : String,
  values : String,
  capture : @publication.ModelCaptureBundleRead,
  limits : Limits,
  plan : @publication_host.ClientInferPlanGraph,
) -> Result[Execution, Issue] {
  guard @publication.retain_model_capture_bundle_read(capture) is Some(retained) else {
    return Err(Model(@model.OutputIdentity))
  }
  let started = start_owned(
    prepared,
    step,
    registry,
    values,
    Restored(retained),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    Some(plan),
  )
  if started is Err(_) {
    @publication.release_model_capture_bundle_read(retained) |> ignore
  }
  started
}

///|
/// Complete saved slot inventory and the separate successful-response bundle
/// follow the same normal Program input path. This cannot dispatch a model.
pub fn start_restored_slot_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry : String,
  values : String,
  read : @model.ModelSlotReplayRead,
  limits : Limits,
  plan : @publication_host.ClientInferPlanGraph,
) -> Result[Execution, Issue] {
  guard @model.retain_model_slot_replay(read) is Some(retained) else {
    return Err(Model(@model.OutputIdentity))
  }
  let started = start_owned(
    prepared,
    step,
    registry,
    values,
    RestoredSlots(retained),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    Some(plan),
  )
  if started is Err(_) {
    @model.release_model_slot_replay(retained) |> ignore
  }
  started
}

///|
/// A synchronization point for physical progress, not evidence authority.
pub fn restoring(active : Execution) -> Bool {
  active.phase is Model &&
  active.model is Some(model) &&
  @model.model_execution_restoring(model)
}

///|
/// Stopped model observations retain custody independently of accepted output.
/// Strict failure may have only an adopted prefix, never fabricated later slots.
pub fn acquire_outcomes(active : Execution) -> @model.ModelOutcomeRead? {
  if active.reclaimed {
    return None
  }
  match active.model {
    Some(model) => @model.acquire_model_outcomes(model)
    None => None
  }
}

///|
fn start_owned(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry : String,
  values : String,
  source : Source,
  fixed_request_cid : String,
  limits : Limits,
  plan : @publication_host.ClientInferPlanGraph?,
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
  if plan is Some(graph) &&
    (
      !@publication_host.client_infer_plan_graph_matches_occurrence(
        graph, prepared, step,
      ) ||
      @publication_host.client_infer_plan_graph_request_cid(graph) !=
      fixed_request_cid
    ) {
    return Err(Model(@model.RequestIdentity))
  }
  let ceiling = match
    @publication_host.prepared_client_infer_host_item_ceiling(prepared, step) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  let request_ceiling = match
    @publication_host.prepared_client_infer_host_request_ceiling(prepared, step) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  if limits.model.max_items < 0 || limits.model.max_request_bytes < 0L {
    return Err(Model(@model.InvalidLimits))
  }
  // A Host-installed physical envelope may tighten the checked policy, never
  // widen it. The common model owner checks this after all keys are admitted
  // and before it reserves attempts or invokes the provider.
  let limits = {
    ..limits,
    model: {
      ..limits.model,
      max_items: Int64::min(ceiling, limits.model.max_items.to_int64()).to_int(),
      max_request_bytes: Int64::min(
        request_ceiling,
        limits.model.max_request_bytes,
      ),
    },
  }
  // The graph's admitted body supplies another ceiling, not permission to
  // dispatch. Reuse the physical ledger's atomic all-slot reservation path;
  // a large caller envelope cannot silently widen the selected contract.
  // Replay consumes existing observations, not another physical allowance.
  let limits = if source is Physical(_) && plan is Some(graph) {
    let execution = @publication_host.client_infer_plan_graph_execution_contract(
      graph,
    )
    let ledger = limits.model.ledger
    {
      ..limits,
      model: {
        ..limits.model,
        ledger: {
          ..ledger,
          attempts: Int64::min(
            ledger.attempts.to_int64(),
            @environment.model_execution_ceiling(
              execution,
              @environment.TotalAttempts,
            ),
          ).to_int(),
          transfer_bytes: Int64::min(
            ledger.transfer_bytes,
            @environment.model_execution_ceiling(
              execution,
              @environment.TotalWireBytes,
            ),
          ),
        },
      },
    }
  } else {
    limits
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
    source,
    fixed_request_cid,
    step,
    plan,
    limits,
    rows: None,
    identity: None,
    call_scope: None,
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
    run_binding: None,
    dispatch_admission: None,
    quantity_capacity: None,
    physical_preflight: None,
    egress_admission: None,
    final_quantity_usage: None,
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
fn begin_model(active : Execution) -> Poll {
  guard active.rows is Some(rows) else { return fail(active, InvalidAdvance) }
  let started = match active.source {
    Physical(provider) =>
      @model.start_model_execution(
        rows,
        provider,
        active.fixed_request_cid,
        active.limits.model,
        call_scope=active.call_scope,
        dispatch_admission=active.dispatch_admission,
        quantity_capacity=active.quantity_capacity,
        physical_preflight=active.physical_preflight,
        egress_admission=active.egress_admission,
      )
    Replay(capture) => {
      guard active.call_scope is Some(scope) else {
        return fail(active, Model(@model.OutputIdentity))
      }
      @model.start_model_capture_replay(
        rows,
        scope,
        capture,
        active.limits.model,
      )
    }
    Restored(capture) => {
      guard active.call_scope is Some(scope) else {
        return fail(active, Model(@model.OutputIdentity))
      }
      @model.start_restored_model_capture_replay(
        rows,
        scope,
        capture,
        active.fixed_request_cid,
        active.limits.model,
      )
    }
    RestoredSlots(read) => {
      guard active.call_scope is Some(scope) else {
        return fail(active, Model(@model.OutputIdentity))
      }
      @model.start_restored_model_slot_replay(
        rows,
        scope,
        read,
        active.fixed_request_cid,
        active.limits.model,
      )
    }
  }
  active.model = match started {
    Ok(value) => Some(value)
    Err(issue) => return fail(active, Model(issue))
  }
  active.child_work = 0L
  active.phase = Model
  Continue(work=active.work)
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
          if active.plan is Some(_) {
            guard @input.client_infer_completed_input(active.input)
              is Some(completed) else {
              return fail(active, InvalidAdvance)
            }
            let limits = active.limits.identity
            active.identity = match
              @relation.start_completed_relation_identity_scan(
                completed,
                limits.rows,
                active.limits.input.rows.output_values,
                limits.wire,
                limits.logical_wire,
                limits.schema,
                limits.work,
                limits.workspace,
              ) {
              Ok(value) => Some(value)
              Err(issue) => return fail(active, IdentityExport(issue))
            }
            active.child_work = 0L
            active.phase = Identity
            return Continue(work=active.work)
          }
          begin_model(active)
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
    Identity => {
      if active.cancelled {
        return stopped(active)
      }
      guard active.identity is Some(identity) else {
        return fail(active, InvalidAdvance)
      }
      let (done, _) = match
        @relation.advance_completed_relation_identity_scan(identity, quantum) {
        Ok(value) => value
        Err(issue) => {
          if !account(
              active,
              @relation.completed_relation_identity_scan_work(identity),
            ) {
            return fail(active, InvalidAdvance)
          }
          return fail(active, IdentityExport(issue))
        }
      }
      if !account(
          active,
          @relation.completed_relation_identity_scan_work(identity),
        ) {
        return fail(active, InvalidAdvance)
      }
      if !done {
        return Continue(work=active.work)
      }
      let receipt = match
        @relation.finish_completed_relation_identity_scan(identity) {
        Ok(value) => value
        Err(issue) => return fail(active, IdentityExport(issue))
      }
      guard active.plan is Some(plan) &&
        @input.client_infer_completed_input(active.input) is Some(completed) else {
        return fail(active, InvalidAdvance)
      }
      active.call_scope = match
        @publication_host.issue_prepared_client_infer_call_scope(
          active.prepared,
          plan,
          active.step,
          completed,
          receipt,
          100000,
          10000,
          100,
        ) {
        Ok(value) => Some(value)
        Err(issue) => return fail(active, CallScope(issue))
      }
      begin_model(active)
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
    Identity =>
      if active.identity is Some(identity) {
        @relation.cancel_completed_relation_identity_scan(identity) |> ignore
      }
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
/// Read a bounded physical phase for cancellation tests and diagnostics.
/// This grants no Run, model-egress or evidence authority.
pub fn request_preflight_pending(active : Execution) -> Bool {
  !active.reclaimed &&
  !active.cancelled &&
  active.phase is Model &&
  active.model is Some(model) &&
  @model.model_execution_preflighting(model)
}

///|
pub fn completed(poll : Poll) -> @relation.CompletedOutput? {
  match poll {
    Complete(value, ..) => Some(value)
    _ => None
  }
}

///|
/// Physical settlement only. Reclamation and public Run outcome are separate.
pub fn execution_stopped(active : Execution) -> Bool {
  !active.advancing && active.phase is Terminal
}

///|
pub fn poll_kind(poll : Poll) -> String {
  match poll {
    Continue(_) => "continue"
    Complete(_, ..) => "complete"
    Failed(_, ..) => "failed"
    Stopped(_) => "stopped"
  }
}

///|
pub fn poll_issue(poll : Poll) -> Issue? {
  match poll {
    Failed(issue, ..) => Some(issue)
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
pub fn identity_pending(active : Execution) -> Bool {
  !active.reclaimed && active.phase is Identity
}

///|
/// Input identity retained by the physical owner, never execution evidence.
pub fn call_scope(
  active : Execution,
) -> @publication_host.ClientInferCallScope? {
  if active.reclaimed {
    None
  } else {
    active.call_scope
  }
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
/// Private successful observation issued by the child execution, not a
/// caller's capture bundle or proof of durable Store custody.
pub fn invocation_evidence(
  active : Execution,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  if active.reclaimed {
    None
  } else {
    match active.model {
      Some(model) => @model.model_execution_invocation_evidence(model, slot)
      None => None
    }
  }
}

///|
/// Retain an opaque read of the checked model owner, independently of output
/// readers. Durable persistence and Run publication are not implied.
pub fn acquire_capture(active : Execution) -> @model.VerifiedModelCapture? {
  if active.reclaimed {
    None
  } else {
    match active.model {
      Some(model) => @model.acquire_verified_model_capture(model)
      None => None
    }
  }
}

///|
pub fn sealing_observation(active : Execution) -> Bool {
  !active.reclaimed &&
  active.model is Some(model) &&
  @model.model_execution_sealing_observation(model)
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
    identity: {
      rows: 100,
      wire: {
        max_columns: 100,
        max_order_work: 10000,
        max_bytes: 500000,
        max_nodes: 20000,
        max_depth: 100,
      },
      logical_wire: {
        max_columns: 100,
        max_order_work: 10000,
        max_bytes: 500100,
        max_nodes: 20002,
        max_depth: 102,
      },
      schema: {
        max_fields: 100,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
      work: values.max_work,
      workspace: 100000,
    },
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
    active.final_quantity_usage = Some(
      @model.model_execution_quantity_usage(model),
    )
    active.model = None
    active.capture = None
  }
  if active.identity is Some(identity) {
    @relation.cancel_completed_relation_identity_scan(identity) |> ignore
    active.identity = None
  }
  match @input.cleanup_client_infer_input(active.input) {
    Ok(true) => {
      if active.source is Replay(capture) {
        @model.release_verified_model_capture(capture) |> ignore
      }
      if active.source is Restored(capture) {
        @publication.release_model_capture_bundle_read(capture) |> ignore
      }
      if active.source is RestoredSlots(read) {
        @model.release_model_slot_replay(read) |> ignore
      }
      active.rows = None
      active.call_scope = None
      active.reclaimed = true
      Ok(true)
    }
    Ok(false) => Ok(false)
    Err(issue) => Err(Input(issue))
  }
}
