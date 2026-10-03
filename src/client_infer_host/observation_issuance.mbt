///|
/// Installed bounds for flat publication metadata, not INFER language limits.
/// A whole inventory is emitted one adopted slot per bounded step. Final schema
/// admission is capped at 16 KiB and 1,024 nodes, independently of input size.
pub(all) struct ObservationIssuanceLimits {
  max_slots : Int
  max_wire_bytes : Int
  max_work : Int
}

///|
priv enum ObservationIssuancePhase {
  Begin
  Slot
  Finalize
  Done
}

///|
struct ObservationIssuanceState {
  owner : Execution
  output_use : OutputUse
  capture : @model.VerifiedModelCapture
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  template : @publication.RunEvidenceValue
  artifact : @publication.RunEvidenceValue
  policy_cid : String
  sources : Array[@publication.ModelSourceObservation]
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  writer : @encode.Writer
  limits : ObservationIssuanceLimits
  count : Int
  mut index : Int
  mut phase : ObservationIssuancePhase
  mut work : Int
  mut bindings : Array[@publication.BoundModelSlotCapture]
  mut observation : @publication.RunEvidenceValue?
  mut invocation : @publication.PublicationContract?
}

///|
/// This common owner derives evidence from the real execution and its original
/// admitted Run. Adapters supply neither slot lists nor evidence JSON. Its
/// caller's existing publication ledger reserves metadata custody; this is not
/// a model retry, dispatch grant or another Run state machine.
pub struct ObservationIssuance {
  state : ObservationIssuanceState
  session : @bounded.Session[ObservationIssuanceState, Unit, Issue]
  control : @bounded.Control
  mut token : @bounded.Token
  mut accepted : Bool
  mut reclaimed : Bool
  mut uses : Int
}

///|
pub fn start_observation_issuance(
  active : Execution,
  ledger : @resources.Ledger,
  limits : ObservationIssuanceLimits,
) -> Result[ObservationIssuance, Issue] {
  if limits.max_slots < 0 ||
    limits.max_slots > 128 ||
    limits.max_wire_bytes < 1 ||
    limits.max_wire_bytes > 16384 ||
    limits.max_work < 1 {
    return Err(InvalidAdvance)
  }
  guard active.run_binding is Some(bound) &&
    active.call_scope is Some(scope) &&
    active.plan is Some(_) &&
    active.model is Some(model) &&
    !active.reclaimed &&
    !active.cancelled &&
    active.phase is Terminal &&
    active.completed is Some(_) else {
    return Err(Model(@model.OutputIdentity))
  }
  // An accepted physical owner or verified stored replay, never a structural
  // test read. This remains mandatory for zero keys, where no slot is visited.
  if !@model.model_execution_has_adopted_evidence(model) {
    return Err(Model(@model.OutputIdentity))
  }
  guard acquire_capture(active) is Some(capture) else {
    return Err(Model(@model.OutputIdentity))
  }
  let count = @model.verified_model_capture_call_count(capture).unwrap()
  guard @publication_host.client_compiled_run_infer_observation_policy(
      bound.compiled,
    )
    is Some(policy_cid) else {
    @model.release_verified_model_capture(capture) |> ignore
    return Err(Model(@model.OutputIdentity))
  }
  if count > limits.max_slots {
    @model.release_verified_model_capture(capture) |> ignore
    return Err(Model(@model.ItemLimit))
  }
  guard acquire_output(active) is Some(output_use) else {
    @model.release_verified_model_capture(capture) |> ignore
    return Err(Model(@model.OutputIdentity))
  }
  // Writers, sealed wire, bounded parser scratch, observation, invocation and
  // the per-slot binding table coexist. Reserve before any of those allocations.
  // The fixed multiplier is an installed workspace allowance, not measured
  // payload bytes or a fabricated model usage observation.
  let workspace = limits.max_wire_bytes.to_int64() * 16L +
    count.to_int64() * 128L
  let reservation = match
    @resources.reserve_attempt(ledger, 0L, workspace, 0L) {
    Ok(value) => value
    Err(issue) => {
      release_output(output_use) |> ignore
      @model.release_verified_model_capture(capture) |> ignore
      return Err(Model(@model.Ledger(issue)))
    }
  }
  let writer = @encode.writer(limits.max_wire_bytes, 1024, 20) catch {
    _ => {
      @resources.settle_reservation(ledger, reservation) |> ignore
      release_output(output_use) |> ignore
      @model.release_verified_model_capture(capture) |> ignore
      return Err(InvalidAdvance)
    }
  }
  let state : ObservationIssuanceState = {
    owner: active,
    output_use,
    capture,
    compiled: bound.compiled,
    definition: bound.definition,
    template: @publication_host.client_compiled_run_template(bound.compiled),
    artifact: @publication_host.client_infer_call_scope_artifact(scope),
    sources: @publication_host.client_infer_call_scope_source_observations(
      scope,
    ),
    policy_cid,
    ledger,
    reservation,
    writer,
    limits,
    count,
    index: 0,
    phase: Begin,
    work: 0,
    bindings: [],
    observation: None,
    invocation: None,
  }
  let control = @bounded.control()
  let (session, token) = @bounded.start(
    control,
    state,
    advance_observation_issuance_step,
    _ => true,
    _ => true,
  )
  Ok({
    state,
    session,
    control,
    token,
    accepted: false,
    reclaimed: false,
    uses: 0,
  })
}

///|
fn emit_observation_issuance_step(
  state : ObservationIssuanceState,
) -> Result[Unit, Issue] raise @encode.EncodeFailure {
  let writer = state.writer
  match state.phase {
    Begin => {
      @encode.begin_object(writer)
      for
        (name, value) in [
          ("version", "actql-observation-set/0.1"),
          (
            "invocation_template_cid",
            @publication.run_evidence_value_identity(state.template),
          ),
          ("data_policy_cid", state.policy_cid),
          (
            "consistency",
            if !state.sources.is_empty() {
              "independent_snapshots"
            } else {
              "no_external_sources"
            },
          ),
        ] {
        @encode.key(writer, name)
        @encode.string_value(writer, value)
      }
      @encode.key(writer, "captured_input_artifact_cids")
      @encode.begin_array(writer)
      @encode.string_value(
        writer,
        @publication.run_evidence_value_identity(state.artifact),
      )
      @encode.end_array(writer)
      @encode.key(writer, "source_evidence_cids")
      @encode.begin_array(writer)
      for source in state.sources {
        @encode.string_value(
          writer,
          @publication.model_source_observation_fields(source).0,
        )
      }
      @encode.end_array(writer)
      for
        (index, name) in [
          (0, "capture_started_at"),
          (1, "capture_completed_at"),
        ] {
        @encode.key(writer, name)
        match @publication.model_source_observation_interval(state.sources) {
          None => @encode.null_value(writer)
          Some((started, completed)) =>
            @encode.string_value(
              writer,
              if index == 0 {
                started
              } else {
                completed
              },
            )
        }
      }
      @encode.key(writer, "replayability")
      @encode.begin_object(writer)
      @encode.key(writer, "materialized")
      // Evidence identity precedes Store durability. Later availability evidence
      // cannot be invented from a successful physical call or equal CID.
      @encode.bool_value(writer, false)
      @encode.key(writer, "availability_evidence_cids")
      @encode.begin_array(writer)
      @encode.end_array(writer)
      @encode.end_object(writer)
      @encode.key(writer, "model_slot_capture_cids")
      @encode.begin_array(writer)
      state.phase = if state.count == 0 { Finalize } else { Slot }
    }
    Slot => {
      let record = match
        @model.verified_model_capture_owned_slot(state.capture, state.index) {
        Ok(value) => value
        Err(issue) => return Err(Model(issue))
      }
      let binding = match
        @model.bind_verified_model_slot_capture(
          state.capture,
          state.index,
          record,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Model(issue))
      }
      @encode.string_value(
        writer,
        @publication.run_evidence_value_identity(record),
      )
      state.bindings.push(binding)
      state.index += 1
      if state.index == state.count {
        state.phase = Finalize
      }
    }
    Finalize => {
      @encode.end_array(writer)
      @encode.end_object(writer)
      let observation = match
        @publication.seal_run_evidence_value(
          "observation_set",
          @encode.finish(writer),
          state.limits.max_wire_bytes,
          1024,
          20,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Model(@model.InvocationEvidence(issue)))
      }
      let invocation = match
        @publication.issue_model_run_invocation(
          state.template,
          observation,
          state.bindings,
          state.limits.max_wire_bytes,
          1024,
          20,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Model(@model.InvocationEvidence(issue)))
      }
      state.observation = Some(observation)
      state.invocation = Some(invocation)
      state.phase = Done
    }
    Done => ()
  }
  Ok(())
}

///|
fn advance_observation_issuance_step(
  state : ObservationIssuanceState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[Unit, Issue] {
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 0, 0)
  }
  if quantum < 1 {
    return @bounded.Failed(InvalidAdvance, 0, 0)
  }
  if state.work >= state.limits.max_work {
    return @bounded.Failed(Model(@model.WorkLimit), 0, 0)
  }
  if @resources.charge_planning(state.ledger, 1) is Err(issue) {
    return @bounded.Failed(Model(@model.Ledger(issue)), 0, 0)
  }
  state.work += 1
  match
    (emit_observation_issuance_step(state) catch {
      _ => Err(Model(@model.OutputValue))
    }) {
    Err(issue) => @bounded.Failed(issue, 1, 1)
    Ok(_) =>
      if state.phase is Done {
        @bounded.Complete((), 1, 1)
      } else {
        @bounded.Continue(1, 1)
      }
  }
}

///|
pub fn advance_observation_issuance(
  active : ObservationIssuance,
  quantum : Int,
) -> Result[(Bool, Int64), Issue] {
  match @bounded.advance(active.session, active.token, quantum) {
    Err(_) => Err(InvalidAdvance)
    Ok(@bounded.ContinueWith(token, work~, ..)) => {
      active.token = token
      Ok((false, work))
    }
    Ok(@bounded.Completed(_, work~, ..)) => {
      active.accepted = true
      Ok((true, work))
    }
    Ok(@bounded.FailedWith(issue, ..)) => Err(issue)
    Ok(@bounded.StoppedWith(_, ..)) => Err(Model(@model.Cancelled))
  }
}

///|
pub fn observation_issuance_value(
  active : ObservationIssuance,
) -> (@publication.RunEvidenceValue, @publication.PublicationContract)? {
  if active.accepted && !active.reclaimed {
    Some((active.state.observation.unwrap(), active.state.invocation.unwrap()))
  } else {
    None
  }
}

///|
pub fn cancel_observation_issuance(active : ObservationIssuance) -> Bool {
  if active.reclaimed || @bounded.session_stopped(active.session) {
    false
  } else {
    @bounded.request_cancel(active.control)
  }
}

///|
pub fn cleanup_observation_issuance(
  active : ObservationIssuance,
) -> Result[Bool, Issue] {
  if active.reclaimed {
    return Ok(true)
  }
  if active.uses > 0 || !@bounded.session_stopped(active.session) {
    return Ok(false)
  }
  match @bounded.cleanup(active.session) {
    Err(_) => return Err(InvalidAdvance)
    Ok(false) => return Ok(false)
    Ok(true) => ()
  }
  match
    @resources.settle_reservation(active.state.ledger, active.state.reservation) {
    Err(issue) => return Err(Model(@model.Ledger(issue)))
    Ok(_) => ()
  }
  @encode.cancel_writer(active.state.writer)
  active.state.bindings = []
  active.state.observation = None
  active.state.invocation = None
  @model.release_verified_model_capture(active.state.capture) |> ignore
  release_output(active.state.output_use) |> ignore
  active.reclaimed = true
  Ok(true)
}

///|
/// Only this issuer's exact checked Run and completed execution can adopt its
/// observation. Independent output consumers keep their original custody.
pub fn bind_issued_invocation(
  execution : Execution,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  issued : ObservationIssuance,
) -> Result[InvocationBinding, InvocationBindingIssue] {
  guard !issued.reclaimed &&
    issued.accepted &&
    physical_equal(issued.state.owner, execution) &&
    physical_equal(issued.state.compiled, compiled) &&
    @publication.publication_contract_identity(issued.state.definition) ==
    @publication.publication_contract_identity(definition) &&
    issued.uses < 2147483647 &&
    observation_issuance_value(issued) is Some((observation, invocation)) else {
    return Err(UnverifiedSlots)
  }
  guard acquire_output(execution) is Some(output_use) else {
    return Err(IncompleteExecution)
  }
  issued.uses += 1
  Ok({ output_use, observation, invocation, issuance: Some(issued), })
}
