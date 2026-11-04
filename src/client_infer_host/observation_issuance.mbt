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
// Existing issuer funding, not another Owner. The mode/control representation
// and additional constructor frames belong in the installed simultaneous
// inventory for both routes; this refactor adopts no new byte coefficients.
priv enum ObservationIssuanceFunding {
  Metadata(@resources.Ledger, @resources.Reservation)
  Original(@model.OriginalModelPublicationCapacity)
}

///|
struct ObservationIssuanceState {
  owners : Array[Execution]
  output_uses : Array[OutputUse]
  captures : Array[@model.VerifiedModelCapture]
  slots : Array[(@model.VerifiedModelCapture, Int)]
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  template : @publication.RunEvidenceValue
  mut generations : Array[@publication_host.ClientSerializationGeneration]
  artifacts : Array[@publication.RunEvidenceValue]
  policy_cid : String
  sources : Array[@publication.ModelSourceObservation]
  mut funding : ObservationIssuanceFunding?
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
// Compiler order is independent of which original finishes first and retains
// the ONE whole-Run publication borrow. Find that actual nominal receiver
// without reordering members; a non-owner comparison runs no current callback.
fn original_observation_inventory_valid(owners : Array[Execution]) -> Bool {
  !owners.is_empty() && owners.length() <= 128
}

///|
fn complete_original_observation_backing_current(
  owners : Array[Execution],
  capacity : @model.OriginalModelPublicationCapacity,
) -> Bool {
  if !original_observation_inventory_valid(owners) {
    return false
  }
  let found = owners.any(active => {
    active.model is Some(model) &&
    active.call_scope is Some(scope) &&
    @model.original_model_publication_capacity_current(capacity, model, scope)
  })
  found &&
  owners.all(active => {
    !active.advancing &&
    !active.reclaimed &&
    active.phase is Terminal &&
    active.model is Some(model) &&
    active.call_scope is Some(scope) &&
    @model.original_model_publication_capacity_matches_parent(
      capacity, model, scope,
    )
  })
}

///|
// New issuance still needs the original handed-off read. Retirement of
// already-owned metadata needs its SAME live Model/publication backing, not
// permission to produce more evidence after the read consumer was stopped.
fn complete_original_observation_funding_current(
  owners : Array[Execution],
  capacity : @model.OriginalModelPublicationCapacity,
) -> Bool {
  original_observation_inventory_valid(owners) &&
  owners.all(original_infer_publication_owner_current) &&
  complete_original_observation_backing_current(owners, capacity)
}

///|
fn observation_issuance_backing_current(
  state : ObservationIssuanceState,
) -> Bool {
  match state.funding {
    Some(Metadata(ledger, reservation)) =>
      @resources.reservation_open(reservation) &&
      @resources.check_original_resources_mutable(ledger) is Ok(_)
    Some(Original(capacity)) =>
      complete_original_observation_backing_current(state.owners, capacity)
    None => false
  }
}

///|
fn observation_issuance_funding_current(
  state : ObservationIssuanceState,
) -> Bool {
  match state.funding {
    Some(Original(capacity)) =>
      complete_original_observation_funding_current(state.owners, capacity)
    _ => observation_issuance_backing_current(state)
  }
}

///|
fn charge_observation_issuance_step(
  state : ObservationIssuanceState,
) -> Result[Unit, Issue] {
  if !observation_issuance_funding_current(state) {
    return Err(Model(@model.OutputIdentity))
  }
  match state.funding.unwrap() {
    Metadata(ledger, _) =>
      @resources.charge_planning(ledger, 1).map_err(issue => {
        Model(@model.Ledger(issue))
      })
    Original(capacity) =>
      @model.charge_original_model_observation_step(capacity).map_err(issue => {
        Model(issue)
      })
  }
}

///|
fn retire_observation_issuance_metadata(
  funding : ObservationIssuanceFunding,
) -> Result[Unit, Issue] {
  match funding {
    Metadata(ledger, reservation) =>
      @resources.settle_reservation(ledger, reservation).map_err(issue => {
        Model(@model.Ledger(issue))
      })
    // The full original publication envelope is still borrowed by its caller.
    // Writer completion/issuer cleanup is not its Store/alias retirement ACK.
    Original(_) => Ok(())
  }
}

///|
pub fn start_observation_issuance(
  active : Execution,
  ledger : @resources.Ledger,
  limits : ObservationIssuanceLimits,
  generations? : Array[@publication_host.ClientSerializationGeneration] = [],
) -> Result[ObservationIssuance, Issue] {
  start_complete_observation_issuance([active], ledger, limits, generations~)
}

///|
/// All compiler-retained Model components must have adopted their original
/// evidence under the same Run. A partial component list cannot issue a Run
/// Invocation, even when every supplied component finished successfully.
pub fn start_complete_observation_issuance(
  owners : Array[Execution],
  ledger : @resources.Ledger,
  limits : ObservationIssuanceLimits,
  generations? : Array[@publication_host.ClientSerializationGeneration] = [],
) -> Result[ObservationIssuance, Issue] {
  start_observation_issuance_owned(
    owners,
    Some(ledger),
    None,
    limits,
    generations,
  )
}

///|
/// Consume the same original borrow, not a caller-supplied Ledger. The original
/// execution/Run and handed-off read are checked before extra metadata state.
/// The caller retains this full publication borrow beyond issuer cleanup until
/// its actual Store/alias custody retires; no physical ACK is inferred here.
pub fn start_original_observation_issuance(
  active : Execution,
  capacity : @model.OriginalModelPublicationCapacity,
  limits : ObservationIssuanceLimits,
  generations? : Array[@publication_host.ClientSerializationGeneration] = [],
) -> Result[ObservationIssuance, Issue] {
  if !original_infer_publication_owner_current(active) ||
    !@model.original_model_publication_capacity_current(
      capacity,
      active.model.unwrap(),
      active.call_scope.unwrap(),
    ) {
    return Err(Model(@model.OutputIdentity))
  }
  // Even this receiver list is created only under the existing original grant.
  start_observation_issuance_owned(
    [active],
    None,
    Some(capacity),
    limits,
    generations,
  )
}

///|
/// All compiler-retained original Model occurrences share ONE existing
/// publication borrow on their SAME parent Ledger. Original execution/Scope,
/// ordered Plan membership and complete Run inventory remain mandatory.
/// This neither creates a Ledger nor treats completed output as a grant.
pub fn start_complete_original_observation_issuance(
  owners : Array[Execution],
  capacity : @model.OriginalModelPublicationCapacity,
  limits : ObservationIssuanceLimits,
  generations? : Array[@publication_host.ClientSerializationGeneration] = [],
) -> Result[ObservationIssuance, Issue] {
  if !complete_original_observation_funding_current(owners, capacity) {
    return Err(Model(@model.OutputIdentity))
  }
  start_observation_issuance_owned(
    owners,
    None,
    Some(capacity),
    limits,
    generations,
  )
}

///|
fn start_observation_issuance_owned(
  owners : Array[Execution],
  metadata_ledger : @resources.Ledger?,
  original_capacity : @model.OriginalModelPublicationCapacity?,
  limits : ObservationIssuanceLimits,
  generations : Array[@publication_host.ClientSerializationGeneration],
) -> Result[ObservationIssuance, Issue] {
  if limits.max_slots < 0 ||
    limits.max_slots > 128 ||
    limits.max_wire_bytes < 1 ||
    limits.max_wire_bytes > 16384 ||
    limits.max_work < 1 {
    return Err(InvalidAdvance)
  }
  guard owners.length() > 0 &&
    owners.length() <= 128 &&
    owners[0].run_binding is Some(bound) else {
    return Err(Model(@model.OutputIdentity))
  }
  let plans = @publication_host.client_compiled_run_infers(bound.compiled)
  if plans.length() != owners.length() {
    return Err(Model(@model.OutputIdentity))
  }
  // This compiler currently retains at most one Content component. Require
  // its actual completion or authenticated recovered token attached to the
  // original Model owner, not a caller's claim that generation succeeded.
  let content_count = if @publication_host.client_compiled_run_serialization(
      bound.compiled,
    )
    is Some(_) {
    1
  } else {
    0
  }
  if generations.length() != content_count {
    return Err(Model(@model.OutputIdentity))
  }
  for generation in generations {
    if @publication_host.client_serialization_generation_capture_for(
        generation,
        bound.compiled,
        bound.definition,
      )
      is None ||
      !owners.any(active => {
        if active.serialized_generation is Some(original) &&
          physical_equal(original, generation) {
          return true
        }
        @publication_host.client_serialization_generation_output_for(
          generation,
          bound.compiled,
        )
        is Some(output) &&
        active.serialized_output is Some(original) &&
        @relation.completed_output_same_occurrence(output, original)
      }) {
      return Err(Model(@model.OutputIdentity))
    }
  }
  let mut count = 0
  for index in 0..<owners.length() {
    let active = owners[index]
    guard active.run_binding is Some(current) &&
      physical_equal(current.compiled, bound.compiled) &&
      @publication.publication_contract_identity(current.definition) ==
      @publication.publication_contract_identity(bound.definition) &&
      active.plan is Some(plan) &&
      physical_equal(plan, plans[index]) &&
      active.call_scope is Some(_) &&
      active.rows is Some(rows) &&
      active.model is Some(model) &&
      !active.reclaimed &&
      !active.cancelled &&
      active.phase is Terminal &&
      active.completed is Some(_) &&
      @model.model_execution_has_adopted_evidence(model) else {
      return Err(Model(@model.OutputIdentity))
    }
    // All prepared rows are slots, including masked/failed outcomes. Counting
    // these owned rows creates no capture/output borrow or additional array.
    let calls = @relation.prepared_infer_rows_count(rows)
    if calls > limits.max_slots - count {
      return Err(Model(@model.ItemLimit))
    }
    count += calls
  }
  guard @publication_host.client_compiled_run_infer_observation_policy(
      bound.compiled,
    )
    is Some(policy_cid) else {
    return Err(Model(@model.OutputIdentity))
  }
  let workspace = limits.max_wire_bytes.to_int64() * 16L +
    count.to_int64() * 128L +
    (owners.length() - 1).to_int64() * 256L +
    generations.length().to_int64() * 256L
  // This is the unchanged metadata component allowance, not a normal backend
  // whole-phase bound. Original funding must cover it AND all additional
  // simultaneous publication holdings supplied by the actual installation.
  let funding = match (metadata_ledger, original_capacity) {
    (Some(ledger), None) => {
      let reservation = match
        @resources.reserve_attempt(ledger, 0L, workspace, 0L) {
        Ok(value) => value
        Err(issue) => return Err(Model(@model.Ledger(issue)))
      }
      ObservationIssuanceFunding::Metadata(ledger, reservation)
    }
    (None, Some(capacity)) => {
      if !complete_original_observation_funding_current(owners, capacity) {
        return Err(Model(@model.OutputIdentity))
      }
      if !@model.original_model_publication_capacity_covers(
          capacity, workspace, 0L,
        ) {
        return Err(Model(@model.Ledger(@resources.RetentionLimit)))
      }
      ObservationIssuanceFunding::Original(capacity)
    }
    _ => return Err(Model(@model.OutputIdentity))
  }
  let captures : Array[@model.VerifiedModelCapture] = []
  let output_uses : Array[OutputUse] = []
  let release = () => {
    for capture in captures {
      @model.release_verified_model_capture(capture) |> ignore
    }
    for output in output_uses {
      release_output(output) |> ignore
    }
  }
  for active in owners {
    guard acquire_capture(active) is Some(capture) else {
      release()
      retire_observation_issuance_metadata(funding) |> ignore
      return Err(Model(@model.OutputIdentity))
    }
    captures.push(capture)
    let calls = @model.verified_model_capture_call_count(capture).unwrap()
    if calls != @relation.prepared_infer_rows_count(active.rows.unwrap()) {
      release()
      retire_observation_issuance_metadata(funding) |> ignore
      return Err(Model(@model.OutputIdentity))
    }
    guard acquire_output(active) is Some(output) else {
      release()
      retire_observation_issuance_metadata(funding) |> ignore
      return Err(Model(@model.OutputIdentity))
    }
    output_uses.push(output)
  }
  let writer = @encode.writer(limits.max_wire_bytes, 1024, 20) catch {
    _ => {
      retire_observation_issuance_metadata(funding) |> ignore
      release()
      return Err(InvalidAdvance)
    }
  }
  let artifacts : Array[@publication.RunEvidenceValue] = []
  let sources : Array[@publication.ModelSourceObservation] = []
  let slots : Array[(@model.VerifiedModelCapture, Int)] = []
  for index in 0..<owners.length() {
    let scope = owners[index].call_scope.unwrap()
    artifacts.push(@publication_host.client_infer_call_scope_artifact(scope))
    for
      source in @publication_host.client_infer_call_scope_source_observations(
        scope,
      ) {
      let fields = @publication.model_source_observation_fields(source)
      let previous = sources
        .filter(candidate => {
          @publication.model_source_observation_fields(candidate).0 == fields.0
        })
        .get(0)
      match previous {
        None => sources.push(source)
        Some(candidate) =>
          if @publication.model_source_observation_fields(candidate) != fields ||
            @publication.model_source_observation_interval([candidate]) !=
            @publication.model_source_observation_interval([source]) {
            retire_observation_issuance_metadata(funding) |> ignore
            @encode.cancel_writer(writer)
            release()
            return Err(Model(@model.OutputIdentity))
          }
      }
    }
    let capture = captures[index]
    for slot in 0..<@model.verified_model_capture_call_count(capture).unwrap() {
      slots.push((capture, slot))
    }
  }
  let state : ObservationIssuanceState = {
    owners: owners.copy(),
    output_uses,
    captures,
    slots,
    compiled: bound.compiled,
    definition: bound.definition,
    template: @publication_host.client_compiled_run_template(bound.compiled),
    generations: generations.copy(),
    artifacts,
    sources,
    policy_cid,
    funding: Some(funding),
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
  // Physical byte custody remains with the existing Content/Store owner.
  // Recheck its live fence at every bounded step and at publication adoption;
  // a previously observed CID is not a permanent availability grant.
  let generations : Array[@publication.BoundContentGeneration] = []
  for generation in state.generations {
    guard @publication_host.client_serialization_generation_capture_for(
        generation,
        state.compiled,
        state.definition,
      )
      is Some(capture) else {
      return Err(Model(@model.OutputIdentity))
    }
    generations.push(capture)
  }
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
      for artifact in state.artifacts {
        @encode.string_value(
          writer,
          @publication.run_evidence_value_identity(artifact),
        )
      }
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
      // Content proofs exist only after verified physical Store custody. The
      // Model-only path still cannot invent availability from a successful call.
      @encode.bool_value(writer, !generations.is_empty())
      @encode.key(writer, "availability_evidence_cids")
      @encode.begin_array(writer)
      for generation in generations {
        guard @publication.bound_content_generation_availability(generation)
          is Some(cid) else {
          return Err(Model(@model.OutputIdentity))
        }
        @encode.string_value(writer, cid)
      }
      @encode.end_array(writer)
      @encode.end_object(writer)
      if !generations.is_empty() {
        @encode.key(writer, "content_generation_cids")
        @encode.begin_array(writer)
        for generation in generations {
          guard @publication.bound_content_generation_value(generation)
            is Some(value) else {
            return Err(Model(@model.OutputIdentity))
          }
          @encode.string_value(
            writer,
            @publication.run_evidence_value_identity(value),
          )
        }
        @encode.end_array(writer)
      }
      @encode.key(writer, "model_slot_capture_cids")
      @encode.begin_array(writer)
      state.phase = if state.count == 0 { Finalize } else { Slot }
    }
    Slot => {
      let (capture, slot) = state.slots[state.index]
      let record = match
        @model.verified_model_capture_owned_slot(capture, slot) {
        Ok(value) => value
        Err(issue) => return Err(Model(issue))
      }
      let binding = match
        @model.bind_verified_model_slot_capture(capture, slot, record) {
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
      let issued = if generations.is_empty() {
        @publication.issue_model_run_invocation(
          state.template,
          observation,
          state.bindings,
          state.limits.max_wire_bytes,
          1024,
          20,
        )
      } else {
        @publication.issue_content_model_run_invocation(
          state.template,
          observation,
          state.bindings,
          generations,
          state.limits.max_wire_bytes,
          1024,
          20,
        )
      }
      let invocation = match issued {
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
  if charge_observation_issuance_step(state) is Err(issue) {
    return @bounded.Failed(issue, 0, 0)
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
  if active.accepted &&
    !active.reclaimed &&
    observation_issuance_funding_current(active.state) &&
    active.state.generations.all(generation => {
      @publication_host.client_serialization_generation_capture_for(
        generation,
        active.state.compiled,
        active.state.definition,
      )
      is Some(_)
    }) &&
    // Generation availability may cross a physical callback. Recheck the same
    // original funding immediately before exposing the sealed values.
    observation_issuance_funding_current(active.state) {
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
  if !observation_issuance_backing_current(active.state) {
    return Err(Model(@model.OutputIdentity))
  }
  // The legacy metadata Ledger can differ from the borrowed Models. Check
  // each actual Model fence before retiring any of their capture uses too.
  if !active.state.captures.all(capture => {
      @model.verified_model_capture_call_count(capture) is Some(_)
    }) ||
    !active.state.owners.all(owner => {
      owner.model is Some(model) &&
      @model.model_execution_mutation_current(model) is Ok(_)
    }) {
    return Err(Model(@model.OutputIdentity))
  }
  match @bounded.cleanup(active.session) {
    Err(_) => return Err(InvalidAdvance)
    Ok(false) => return Ok(false)
    Ok(true) => ()
  }
  @encode.cancel_writer(active.state.writer)
  active.state.bindings = []
  active.state.observation = None
  active.state.invocation = None
  for capture in active.state.captures {
    @model.release_verified_model_capture(capture) |> ignore
  }
  for output in active.state.output_uses {
    release_output(output) |> ignore
  }
  // These arrays are private to this issuer (owners/generations were copied).
  // Retire their backing references, not escaped immutable contract values.
  active.state.captures.clear()
  active.state.captures.shrink_to_fit()
  active.state.output_uses.clear()
  active.state.output_uses.shrink_to_fit()
  active.state.slots.clear()
  active.state.slots.shrink_to_fit()
  active.state.owners.clear()
  active.state.owners.shrink_to_fit()
  active.state.artifacts.clear()
  active.state.artifacts.shrink_to_fit()
  active.state.sources.clear()
  active.state.sources.shrink_to_fit()
  active.state.generations = []
  match retire_observation_issuance_metadata(active.state.funding.unwrap()) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Original mode does NOT settle the full publication borrow. Its real caller
  // still owns post-issuer Store bodies/aliases and releases it after those
  // children retire, before Model cleanup. Drop only our extra reference here.
  active.state.funding = None
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
    issued.state.owners.any(owner => physical_equal(owner, execution)) &&
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
