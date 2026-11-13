///|
/// One deterministic physical request selected by the shared model owner.
/// The provider receives retained typed values, never source JSON or a name
/// synthesized from a row.
pub(all) struct ModelRequest {
  task : @environment.ModelTaskContract
  slot : Int
  slot_cid : String
  fixed_request_cid : String
  key : Array[@admitted.CheckedValue]
  inputs : Array[(String, @admitted.CheckedValue)]
}

///|
pub(all) struct ModelResponse {
  value : @admitted.Value
  provider_model : String
  provider_request_id : String
  input_tokens : Int64
  output_tokens : Int64
  observed_at : String
}

///|
pub(all) enum ModelProviderFailure {
  RateLimit
  Timeout
  ProviderError
  Refusal
  SchemaInvalid
  SafetyRejected
  Truncated
  Cancelled
} derive(Eq, Debug)

///|
/// A provider implementation is installed by the Host and cannot be
/// selected by a Program value or by a model selector string alone.
pub(all) enum ModelProviderInvocation {
  SynchronousFixture(
    (ModelRequest) -> Result[ModelResponse, ModelProviderFailure]
  )
  AsynchronousPhysical
  OriginalMock(ModelMockInstallation)
}

///|
pub(all) struct ModelProvider {
  invocation : ModelProviderInvocation
  provider_id : String
}

///|
pub fn install_model_provider(
  provider_id : String,
  invoke : (ModelRequest) -> Result[ModelResponse, ModelProviderFailure],
) -> Result[ModelProvider, ModelExecutionIssue] {
  if provider_id.is_empty() {
    return Err(InvalidProvider)
  }
  Ok({ invocation: SynchronousFixture(invoke), provider_id, })
}

///|
/// Physical registration only. The original async preflight, Entry and profile
/// are separately required before any attempt can enter or invoke transport.
pub fn install_async_model_provider(
  provider_id : String,
) -> Result[ModelProvider, ModelExecutionIssue] {
  if provider_id.is_empty() {
    return Err(InvalidProvider)
  }
  Ok({ invocation: AsynchronousPhysical, provider_id, })
}

///|
/// The original fixture callback, never an async fallback or a send grant.
pub fn model_provider_synchronous_invoke(
  provider : ModelProvider,
) -> ((ModelRequest) -> Result[ModelResponse, ModelProviderFailure])? {
  match provider.invocation {
    SynchronousFixture(invoke) => Some(invoke)
    AsynchronousPhysical | OriginalMock(_) => None
  }
}

///|
pub(all) struct ModelExecutionLimits {
  max_items : Int
  max_work : Int
  max_request_bytes : Int64
  max_response_bytes : Int64
  value_limits : @admitted.Limits
  ledger : @resources.LedgerLimits
}

///|
/// An installed physical envelope, not authority or a retry policy. The same
/// shared ledger reserves these units and the request/response byte envelope.
pub(all) struct ModelQuantityCapacity {
  limits : @resources.QuantityAmounts
  per_attempt : @resources.QuantityAmounts
}

///|
pub(all) enum ModelExecutionIssue {
  InvalidLimits
  InvalidProvider
  ItemLimit
  RequestIdentity
  InputReferenceUnavailable
  Content(ModelContentIssue)
  Provider(ModelProviderFailure)
  OutputValue
  OutputIdentity
  Cancelled
  Deadline
  Ledger(@resources.LedgerIssue)
  IoAdmission(@resources.ModelIoAdmissionIssue)
  Session(@bounded.Issue)
  WorkLimit
  RequestLimit
  InvocationEvidence(@publication.RunEvidenceValueIssue)
  Authorization(@publication_host.ClientInferDispatchIssue)
  Egress(@publication_host.ClientInferEgressIssue)
  CallEntryRefused
  UnknownCalls
} derive(Eq, Debug)

///|
/// A private checked slot observation, not a durable model-slot capture or
/// authority/accounting proof. Public evidence is issued by the execution
/// owner separately; this constructible bundle cannot authorize completion.
pub(all) struct ModelSlotCapture {
  slot : Int
  slot_cid : String
  input_key_cid : String
  fixed_request_cid : String
  provider_id : String
  provider_model : String?
  provider_request_id : String?
  value : @admitted.CheckedValue
  input_tokens : Int64?
  output_tokens : Int64?
  observed_at : String
}

///|
pub(all) struct ModelCaptureBundle {
  task_cid : String
  fixed_request_cid : String
  captures : Array[ModelSlotCapture]
}

///|
// The accepted inventory covers every logical key. Successful response records
// remain a separate subset; failed calls never fabricate a typed response.
priv enum AdoptedModelSlot {
  Success(Int)
  NoResponseFailure(ModelProviderFailure)
  UnresolvedUnknown
}

///|
pub(all) enum ModelObservation {
  Continue(Int64, Int64)
  AwaitIo(Int64, Int64)
  Waiting(Int64, Int64)
  Settling(Int, Int64, Int64)
  Completed(ModelCaptureBundle, Int64, Int64)
  Failed(ModelExecutionIssue, Int64, Int64)
  Stopped(@bounded.StopReason, Int64, Int64)
}

///|
priv enum ModelPhase {
  ReserveSlots
  PrepareRequests
  PreparePhysicalRequests
  DispatchSlot
  AwaitPhysicalResponse
  DecodePhysicalResponse(
    PreparedModelRequest,
    ModelPhysicalEncodedResponse,
    ModelResponseDecode
  )
  CheckPhysicalMetadata(
    PreparedModelRequest,
    ModelObservedResponse,
    @canonical.CanonicalEmit,
    @encode.Writer
  )
  CheckResponse(
    ModelRequest,
    ModelObservedResponse,
    String,
    @admitted.RecheckCursor
  )
  RestoreResponse(
    PreparedModelRequest,
    @publication.ModelCaptureRecordRead,
    @admitted.CanonicalConversion
  )
  PrepareEvidence(ModelEvidencePreparation)
  Reclaimed
}

///|
priv enum ModelSource {
  Provider(ModelProvider)
  Replay(VerifiedModelCapture)
  Restored(@publication.ModelCaptureBundleRead)
  RestoredSlots(ModelSlotReplayRead)
}

///|
// Progress belongs to the existing Model owner, not another execution/session.
// A bounded installed window retains each original Entry/Call separately.
// The selected reference is only a scan/work cursor, never every Slot's state.
// The new record/reference and constructor overlap require physical funding;
// moving existing fields does not establish a free layout or concurrency.
struct ModelSlotProgress {
  mut phase : ModelPhase
  mut slot : Int
  mut entry : ModelCallEntry?
  mut call : ModelPhysicalCall?
  mut settlement : Int?
  mut observing_response : Bool
  // Additional original-owner holding; no numerical fee is inferred here.
  mut io_duty : ModelSlotIoDuty?
}

///|
struct ModelState {
  rows : @relation.PreparedInferRows
  input_use : @relation.InferRowsUse
  task : @environment.ModelTaskContract
  source : ModelSource
  fixed_request_cid : String
  limits : ModelExecutionLimits
  quantity_capacity : ModelQuantityCapacity?
  call_scope : @publication_host.ClientInferCallScope?
  mut dispatch_admission : @publication_host.ClientInferDispatchAdmission?
  egress_admission : @publication_host.ClientInferEgressAdmission?
  attempts : Map[Int, ModelAttemptTrace]
  attempt_slots : Array[Int]
  restored_calls : Map[Int, RestoredModelCall]
  unknown_calls : Map[Int, UnknownModelAttempt]
  reconciled_responses : Map[Int, ModelResponse]
  response_reconciliations : Map[Int, ModelResponseReconciliation]
  ledger : @resources.Ledger
  mut prepared_capacity : @resources.CapacityReservation?
  // Private proposal; this extra reference has no adopted physical coefficient.
  mut original_startup : OriginalModelStartup?
  reservations : Map[Int, @resources.Reservation]
  send_mask : Array[Bool]?
  mut reservation_next_slot : Int
  requests : Array[PreparedModelRequest]
  physical_preflight : ModelPhysicalPreflight?
  physical_cursors : Array[ModelRequestPreflight]
  physical_plans : Map[Int, ModelPhysicalRequestPlan]
  mut physical_next_slot : Int
  mut physical_pending : ModelRequestPreflight?
  mut physical_cleanup_index : Int
  durable_calls : Bool
  mut enter_call : ((ModelCallEntry) -> Bool)?
  mut enter_persistence : ((ModelCallEntry) -> ModelCallEntryPersistence?)?
  mut physical_observer : ((ModelPhysicalObservation) -> Unit)?
  mut prepared_call_set : ModelPreparedCallSet?
  mut stop_requested : Bool
  outcomes : Array[AdoptedModelSlot]
  mut request : ModelRequestPreparation?
  captures : Array[ModelSlotCapture]
  responses : Array[@admitted.Value]
  invocation_evidence : Array[@publication.RunEvidenceValue]
  mut restored_evidence : @publication.RunEvidenceValue?
  mut restored_binding : @publication.BoundModelSlotCapture?
  mut progress : ModelSlotProgress
  // Additional managed reference, including None on legacy paths. The original
  // installation must fund its complete window before using this connection.
  mut slot_window : ModelSlotWindow?
  mut work : Int
  mut output_uses : Int
  mut accepted : Bool
  mut reclaimed : Bool
}

///|
pub struct ModelExecution {
  session : @bounded.Session[
    ModelState,
    ModelCaptureBundle,
    ModelExecutionIssue,
  ]
  mut token : @bounded.Token
  control : @bounded.Control
  state : ModelState
  mut progress : Int64
  mut work : Int64
  mut advancing : Bool
}

///|
fn valid_cid(value : String) -> Bool {
  value.length() == 71 && value.has_prefix("sha256:")
}

///|
fn slot_cid(
  fixed_request_cid : String,
  index : Int,
  key : Array[@admitted.CheckedValue],
) -> String? {
  let writer = @encode.hashing_writer(4096, 256, 8) catch { _ => return None }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "fixed_request_cid")
    @encode.string_value(writer, fixed_request_cid)
    @encode.key(writer, "key")
    @encode.begin_array(writer)
    for value in key {
      @admitted.emit_checked_wire_value(value, writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "slot")
    @encode.number_value(writer, index.to_double())
    @encode.end_object(writer)
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    Some("sha256:" + digest)
  } catch {
    _ => None
  }
}

///|
/// The key evidence is retained separately from the call-slot identity so a
/// KEEP consumer can bind its output key without decoding request metadata.
fn key_cid(key : Array[@admitted.CheckedValue]) -> String? {
  let writer = @encode.hashing_writer(4096, 256, 8) catch { _ => return None }
  try {
    @encode.begin_array(writer)
    for value in key {
      @admitted.emit_checked_wire_value(value, writer)
    }
    @encode.end_array(writer)
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    Some("sha256:" + digest)
  } catch {
    _ => None
  }
}

///|
fn request_key(
  rows : @relation.PreparedInferRows,
  slot : Int,
  task : @infer.CheckedInfer,
) -> Array[@admitted.CheckedValue]? {
  let output : Array[@admitted.CheckedValue] = []
  for index in 0..<@infer.key_count(task) {
    guard @relation.prepared_infer_rows_key(rows, slot, index) is Some(value) else {
      return None
    }
    output.push(value)
  }
  Some(output)
}

///|
fn advance_model(
  state : ModelState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  // An asynchronously saved or unconfirmed entry owns the original attempt
  // before any final stop/authority check. A confirmed absence owns no attempt.
  let persistence_issue = model_entry_persistence_issue(state)
  if persistence_issue is Some(issue) {
    if state.work >= state.limits.max_work {
      return @bounded.Failed(WorkLimit, 0, 0)
    }
    state.work += 1
    retire_model_entering(state)
    return @bounded.Failed(issue, 1, 1)
  }
  if @bounded.stop_requested(reader) is Some(reason) {
    retire_model_entering(state)
    return @bounded.Stopped(reason, 0, 0)
  }
  if state.stop_requested && !state.progress.observing_response {
    retire_model_entering(state)
    return @bounded.Stopped(@bounded.Cancelled, 0, 0)
  }
  if quantum < 1 {
    return @bounded.Failed(InvalidLimits, 0, 0)
  }
  if state.work >= state.limits.max_work {
    return @bounded.Failed(WorkLimit, 0, 0)
  }
  state.work += 1
  if state.progress.phase is ReserveSlots {
    // Replay owns a read of an already checked observation. It must neither
    // reserve another physical attempt nor re-enter a provider on failure.
    if state.source is Replay(_) ||
      state.source is Restored(_) ||
      state.source is RestoredSlots(_) {
      state.progress.phase = PrepareRequests
      return @bounded.Continue(1, 1)
    }
    if state.reservation_next_slot <
      @relation.prepared_infer_rows_count(state.rows) {
      let ordinal = state.reservation_next_slot
      if !model_slot_send_eligible(state, ordinal) {
        state.reservation_next_slot += 1
        return @bounded.Continue(1, 1)
      }
      let transfer = state.limits.max_request_bytes +
        state.limits.max_response_bytes
      let retention = state.limits.max_request_bytes +
        state.limits.max_response_bytes +
        (if state.dispatch_admission is Some(_) || state.durable_calls {
          81920L + model_attachment_evidence_bytes(state.task)
        } else {
          0L
        })
      let execution = if state.physical_preflight is Some(_) {
        physical_preflight_metadata_bytes
      } else {
        0L
      }
      match
        check_original_mock_attempt_capacity(
          state, transfer, retention, execution,
        ) {
        Err(issue) => return @bounded.Failed(issue, 1, 1)
        Ok(_) => ()
      }
      match
        @resources.reserve_attempt(
          state.ledger,
          transfer,
          retention,
          execution,
          quantities=state.quantity_capacity.map(value => value.per_attempt),
        ) {
        Ok(value) => state.reservations[ordinal] = value
        Err(issue) => return @bounded.Failed(Ledger(issue), 1, 1)
      }
      state.reservation_next_slot += 1
      if state.reservation_next_slot ==
        @relation.prepared_infer_rows_count(state.rows) {
        state.progress.phase = PrepareRequests
      }
      return @bounded.Continue(1, 1)
    }
    // All reservations precede the first dispatch, including an empty input.
    state.progress.phase = PrepareRequests
  }
  if state.progress.phase is PrepareRequests {
    return advance_model_request_preparation(state)
  }
  if state.progress.phase is PreparePhysicalRequests {
    return advance_model_physical_preflight(state)
  }
  if state.progress.phase is AwaitPhysicalResponse {
    return advance_model_physical_response(state, reader)
  }
  if state.progress.phase is DecodePhysicalResponse(prepared, physical, cursor) {
    return advance_encoded_model_response(
      state, prepared, physical, cursor, reader,
    )
  }
  if state.progress.phase
    is CheckPhysicalMetadata(prepared, response, cursor, writer) {
    return advance_reported_model_metadata(
      state, prepared, response, cursor, writer,
    )
  }
  if state.progress.slot >= @relation.prepared_infer_rows_count(state.rows) {
    return complete_model_slots(state)
  }
  if state.progress.phase
    is CheckResponse(request, response, input_key_cid, cursor) {
    match @admitted.advance_recheck_runtime_value(cursor) {
      RecheckContinue => return @bounded.Continue(1, 1)
      RecheckFailed => return @bounded.Failed(OutputValue, 1, 1)
      RecheckComplete(checked, _, _) => {
        if state.call_scope is Some(_) {
          match
            start_model_evidence(
              state, request, response, input_key_cid, checked,
            ) {
            Ok(value) => state.progress.phase = PrepareEvidence(value)
            Err(issue) => return @bounded.Failed(issue, 1, 1)
          }
          return @bounded.Continue(1, 1)
        }
        return accept_model_slot(
          state, request, response, input_key_cid, checked,
        )
      }
    }
  }
  if state.progress.phase is RestoreResponse(prepared, record, cursor) {
    return advance_restored_model_response(state, prepared, record, cursor)
  }
  if state.progress.phase is PrepareEvidence(preparation) {
    match advance_model_evidence(state, preparation) {
      Err(issue) => return @bounded.Failed(issue, 1, 1)
      Ok(None) => return @bounded.Continue(1, 1)
      Ok(Some(evidence)) => {
        if (
            state.source is Restored(_) ||
            state.source is RestoredSlots(_) ||
            state.restored_calls.contains(state.progress.slot)
          ) &&
          (
            state.restored_evidence is None ||
            @publication.run_evidence_value_identity(
              state.restored_evidence.unwrap(),
            ) !=
            @publication.run_evidence_value_identity(evidence)
          ) {
          return @bounded.Failed(OutputIdentity, 1, 1)
        }
        if state.source is RestoredSlots(_) ||
          state.restored_calls.contains(state.progress.slot) {
          guard state.restored_binding is Some(binding) else {
            return @bounded.Failed(OutputIdentity, 1, 1)
          }
          match
            @publication.verify_model_slot_success_observation(
              binding, evidence,
            ) {
            Err(issue) =>
              return @bounded.Failed(InvocationEvidence(issue), 1, 1)
            Ok(_) => ()
          }
          state.restored_binding = None
        }
        state.restored_evidence = None
        state.invocation_evidence.push(evidence)
        if state.attempts.get(state.progress.slot) is Some(trace) {
          trace.response_cid = preparation.response_cid
          trace.output_cid = preparation.output_cid
        }
        return accept_model_slot(
          state,
          preparation.request,
          preparation.response,
          preparation.key_cid,
          preparation.checked,
        )
      }
    }
  }
  if !(state.progress.phase is DispatchSlot) {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  guard state.requests.get(state.progress.slot) is Some(prepared) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  let request = prepared.request
  if state.durable_calls &&
    state.restored_calls.get(state.progress.slot) is Some(saved) {
    return advance_partial_model_restore(state, saved, prepared)
  }
  if state.durable_calls &&
    state.reconciled_responses.get(state.progress.slot) is Some(response) &&
    state.reservations.get(state.progress.slot) is Some(reservation) {
    state.progress.observing_response = true
    return begin_observed_model_response(
      state, prepared, response, reservation, reader,
    )
  }
  if state.durable_calls && state.unknown_calls.contains(state.progress.slot) {
    adopt_model_outcome(state, UnresolvedUnknown)
    state.progress.slot += 1
    if @infer.result_mode(@relation.prepared_infer_rows_owner(state.rows))
      is Fail {
      return @bounded.Failed(UnknownCalls, 1, 1)
    }
    return @bounded.Continue(1, 1)
  }
  if state.source is Replay(capture) {
    return advance_model_capture_replay(state, capture, prepared)
  }
  if state.source is Restored(capture) {
    return begin_restored_model_response(state, capture, prepared)
  }
  if state.source is RestoredSlots(read) {
    return begin_restored_model_slot(state, read, prepared)
  }
  guard state.source is Provider(provider) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  guard model_slot_send_eligible(state, state.progress.slot) &&
    state.reservations.get(state.progress.slot) is Some(reservation) else {
    return @bounded.Failed(CallEntryRefused, 1, 1)
  }
  // Historical/restored outcome branches above consume their original DATA
  // without another answer file. Only an actual NEW Mock Slot needs answers,
  // before any new IO duty, attempt or entered-call responsibility is claimed.
  if provider.invocation is OriginalMock(original) &&
    original.require_original() is Err(_) {
    return @bounded.Failed(InvalidProvider, 1, 1)
  }
  match claim_model_slot_io(state) {
    Err(issue) => return @bounded.Failed(issue, 1, 1)
    Ok(_) => ()
  }
  let attempt = if state.progress.entry is Some(entry) {
    // Continue the retained entry, never construct another attempt after poll.
    Some(entry.trace)
  } else if state.dispatch_admission is Some(admission) {
    guard prepared.call is Some(call) else {
      return @bounded.Failed(RequestIdentity, 1, 1)
    }
    match start_model_attempt(state, admission, call, request) {
      Err(issue) => return @bounded.Failed(issue, 1, 1)
      Ok(attempt) => Some(attempt)
    }
  } else {
    None
  }
  if state.egress_admission is Some(admission) {
    match @publication_host.check_client_infer_egress_current(admission) {
      Err(issue) => return @bounded.Failed(Egress(issue), 1, 1)
      Ok(_) => ()
    }
  }
  if state.physical_plans.get(state.progress.slot) is Some(plan) &&
    !model_content_admissions_current(plan.attachments) {
    return @bounded.Failed(InputReferenceUnavailable, 1, 1)
  }
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 1, 1)
  }
  // ModelResponse contains typed content and token observations, not exact
  // transport bytes. Physical and arbitrary fixture invocations retain their
  // dispatched envelope as uncertain usage. The nominal OriginalMock branch
  // only selects an admitted local answer and cannot invoke transport; keep
  // its wire ceiling reserved without inventing a physical transfer history.
  // This does not clear any earlier or restored uncertain usage.
  if state.progress.entry is None {
    match mark_model_attempt_entered(state, reservation) {
      Err(issue) => return @bounded.Failed(Ledger(issue), 1, 1)
      Ok(_) => ()
    }
    if state.quantity_capacity is Some(_) {
      match @resources.mark_quantities_uncertain(state.ledger, reservation) {
        Err(issue) => return @bounded.Failed(Ledger(issue), 1, 1)
        Ok(_) => ()
      }
    }
  }
  // Both persistence adapters retain this exact owner-issued attempt. The
  // immediate adapter reports its save here; the polling adapter suspends with
  // the same entry. Both resume through the original final one-shot send gate.
  let mut send_gate : ModelCallSendGate? = None
  if state.durable_calls {
    guard state.prepared_call_set is Some(prepared_set) &&
      attempt is Some(trace) &&
      state.dispatch_admission is Some(admission) else {
      return @bounded.Failed(CallEntryRefused, 1, 1)
    }
    let entry = match state.progress.entry {
      Some(original) => original
      None => {
        let entry : ModelCallEntry = {
          prepared: prepared_set,
          progress: state.progress,
          slot: state.progress.slot,
          trace,
          admission,
          acknowledgement: None,
          persistence: None,
          gate_issued: false,
          send_started: false,
        }
        state.progress.entry = Some(entry)
        if state.progress.io_duty is Some(duty) {
          duty.entry = Some(entry)
        }
        if state.enter_persistence is Some(begin) {
          guard begin(entry) is Some(operation) &&
            entry.persistence is Some(original) &&
            physical_equal(operation, original) else {
            if entry.persistence is Some(original) {
              // A bad returned handle cannot erase a known in-flight save.
              // Drain its owned observation, but never authorize transport.
              original.refused = true
              return @bounded.Continue(1, 1)
            }
            // A begun save without an owned result is unconfirmed, not absent.
            retain_model_entry_attempt(state, entry)
            retire_model_entering(state)
            return @bounded.Failed(CallEntryRefused, 1, 1)
          }
          return @bounded.Continue(1, 1)
        }
        guard state.enter_call is Some(enter) && enter(entry) else {
          retire_model_entering(state)
          return @bounded.Failed(CallEntryRefused, 1, 1)
        }
        entry
      }
    }
    // Preserve entered-attempt responsibility before final current checks.
    // The legacy immediate adapter's true result reports actual persistence;
    // it does not itself authorize transport or fabricate a new approval.
    retain_model_entry_attempt(state, entry)
    let issued = match acknowledge_model_call_entry(entry, prepared_set) {
      None =>
        match model_call_start_current(entry, reader) {
          Err(issue) => Err(issue)
          Ok(_) => Err(CallEntryRefused)
        }
      Some(acknowledgement) =>
        issue_model_call_send_gate(acknowledgement, reader)
    }
    retire_model_call_entry_persistence(entry)
    match issued {
      Err(issue) => {
        retire_model_entering(state)
        return match issue {
          Cancelled => @bounded.Stopped(@bounded.Cancelled, 1, 1)
          Deadline => @bounded.Stopped(@bounded.Deadline, 1, 1)
          _ => @bounded.Failed(issue, 1, 1)
        }
      }
      Ok(gate) => send_gate = Some(gate)
    }
  }
  if !state.durable_calls && attempt is Some(attempt) {
    state.attempts[state.progress.slot] = attempt
    state.attempt_slots.push(state.progress.slot)
  }
  // A cancellation delivered by a synchronous entry observer cannot start I/O.
  // Once provider entry begins, however, returned response custody survives
  // cancellation and is verified/persisted before physical cleanup completes.
  if state.stop_requested {
    return @bounded.Stopped(@bounded.Cancelled, 1, 1)
  }
  // Entry observers may synchronously revoke the original Ref or physical
  // holding. Keep the entered attempt uncertain, but do not invoke its port.
  if state.physical_plans.get(state.progress.slot) is Some(plan) &&
    !model_content_admissions_current(plan.attachments) {
    return @bounded.Failed(InputReferenceUnavailable, 1, 1)
  }
  state.progress.observing_response = state.durable_calls
  // This diagnostic callback is not a physical-start fact. It may revoke
  // authority or cancel, so the original one-shot gate is consumed afterwards.
  if state.physical_preflight is Some(_) &&
    state.physical_plans.get(state.progress.slot) is None {
    return @bounded.Failed(RequestIdentity, 1, 1)
  }
  observe_model_physical(state, BeforeInvoke)
  let started = match send_gate {
    Some(gate) => consume_model_call_send_gate(gate, reader)
    None => check_model_physical_start_current(state, reader)
  }
  match started {
    Err(issue) => {
      retire_model_entering(state)
      state.progress.observing_response = false
      return match issue {
        Cancelled => @bounded.Stopped(@bounded.Cancelled, 1, 1)
        Deadline => @bounded.Stopped(@bounded.Deadline, 1, 1)
        _ => @bounded.Failed(issue, 1, 1)
      }
    }
    Ok(_) => ()
  }
  // No callback, await or request construction separates final consumption
  // from the retained invocation. Entered responsibility already exists if
  // the installed foreign invocation loses its response or throws.
  if state.physical_plans.get(state.progress.slot) is Some(plan) &&
    plan.invocation is Asynchronous(start) {
    guard send_gate is Some(gate) else {
      retire_model_entering(state)
      return @bounded.Failed(CallEntryRefused, 1, 1)
    }
    let started = start(gate.entry)
    // A callback cannot replace custody that it already registered under the
    // original entered attempt. On a bad returned view, cleanup drains that
    // original operation but never admits a fabricated response or new send.
    let owned = started is Some(call) &&
      state.progress.call is Some(original) &&
      physical_equal(call, original)
    retire_model_entering(state)
    if !owned {
      return @bounded.Failed(CallEntryRefused, 1, 1)
    }
    state.progress.phase = AwaitPhysicalResponse
    observe_model_physical(state, InvokeStarted)
    return @bounded.Continue(1, 1)
  }
  let invoked = match state.physical_preflight {
    None =>
      match provider.invocation {
        SynchronousFixture(invoke) => invoke(request)
        OriginalMock(original) =>
          invoke_original_mock(
            original, provider, state, prepared, request, reader,
          )
        AsynchronousPhysical => return @bounded.Failed(InvalidProvider, 1, 1)
      }
    Some(_) => {
      guard state.physical_plans.get(state.progress.slot) is Some(plan) else {
        return @bounded.Failed(RequestIdentity, 1, 1)
      }
      guard plan.invocation is Synchronous(invoke) else {
        return @bounded.Failed(RequestIdentity, 1, 1)
      }
      invoke()
    }
  }
  retire_model_entering(state)
  // Deliver the entry-start fact only after crossing the invocation boundary.
  // It proves neither network delivery nor a valid/saved provider response.
  observe_model_physical(state, InvokeStarted)
  observe_model_physical(
    state,
    match invoked {
      Ok(_) => InvokeReturned
      Err(Cancelled) => InvokeCancelled
      Err(_) => InvokeFailed
    },
  )
  let response = match invoked {
    Ok(value) => value
    Err(issue) => {
      state.progress.observing_response = false
      if @bounded.stop_requested(reader) is Some(reason) {
        return @bounded.Stopped(reason, 1, 1)
      }
      if issue == Cancelled {
        return @bounded.Stopped(@bounded.Cancelled, 1, 1)
      }
      return accept_failed_model_slot(state, issue)
    }
  }
  begin_observed_model_response(state, prepared, response, reservation, reader)
}

///|
// Physical dispatch and original-attempt reconciliation share bounded type
// checking, quantity observations and the same settlement/capture owner.
fn begin_observed_model_response(
  state : ModelState,
  prepared : PreparedModelRequest,
  response : ModelResponse,
  reservation : @resources.Reservation,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  let request = prepared.request
  if state.attempts.get(state.progress.slot) is Some(trace) {
    trace.input_tokens = if response.input_tokens >= 0L {
      Some(response.input_tokens)
    } else {
      None
    }
    trace.output_tokens = if response.output_tokens >= 0L {
      Some(response.output_tokens)
    } else {
      None
    }
  }
  // Account the observed tokens even when cancellation arrived during I/O.
  // Cost and duration are not observed by this response shape and remain
  // uncertain; cleanup cannot rewrite them as zero or refund that envelope.
  if state.quantity_capacity is Some(_) &&
    response.input_tokens >= 0L &&
    response.output_tokens >= 0L {
    if response.input_tokens > 9223372036854775807L - response.output_tokens {
      return @bounded.Failed(OutputIdentity, 1, 1)
    }
    match
      @resources.observe_quantities(
        state.ledger,
        reservation,
        tokens=Some(response.input_tokens + response.output_tokens),
      ) {
      Err(issue) => return @bounded.Failed(Ledger(issue), 1, 1)
      Ok(_) => ()
    }
  }
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 1, 1)
  }
  let input_key_cid = prepared.key_cid
  if response.provider_model.is_empty() ||
    response.provider_request_id.is_empty() ||
    response.observed_at.is_empty() ||
    response.input_tokens < 0L ||
    response.output_tokens < 0L {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  let cursor = match
    @admitted.start_recheck_runtime_value(
      response.value,
      @environment.model_task_output(state.task),
      state.limits.value_limits,
    ) {
    Some(value) => value
    None => return @bounded.Failed(OutputValue, 1, 1)
  }
  state.progress.phase = CheckResponse(
    request,
    lift_historical_model_response(response),
    input_key_cid,
    cursor,
  )
  @bounded.Continue(1, 1)
}

///|
pub fn start_model_execution(
  rows : @relation.PreparedInferRows,
  provider : ModelProvider,
  fixed_request_cid : String,
  limits : ModelExecutionLimits,
  call_scope? : @publication_host.ClientInferCallScope? = None,
  dispatch_admission? : @publication_host.ClientInferDispatchAdmission? = None,
  quantity_capacity? : ModelQuantityCapacity? = None,
  physical_preflight? : ModelPhysicalPreflight? = None,
  egress_admission? : @publication_host.ClientInferEgressAdmission? = None,
  durable_calls? : Bool = false,
  send_mask? : Array[Bool]? = None,
) -> Result[ModelExecution, ModelExecutionIssue] {
  start_model_owned(
    rows,
    Provider(provider),
    fixed_request_cid,
    limits,
    call_scope,
    dispatch_admission~,
    quantity_capacity~,
    physical_preflight~,
    egress_admission~,
    durable_calls~,
    send_mask~,
  )
}

///|
fn start_model_owned(
  rows : @relation.PreparedInferRows,
  source : ModelSource,
  fixed_request_cid : String,
  limits : ModelExecutionLimits,
  call_scope : @publication_host.ClientInferCallScope?,
  dispatch_admission? : @publication_host.ClientInferDispatchAdmission? = None,
  quantity_capacity? : ModelQuantityCapacity? = None,
  physical_preflight? : ModelPhysicalPreflight? = None,
  egress_admission? : @publication_host.ClientInferEgressAdmission? = None,
  durable_calls? : Bool = false,
  send_mask? : Array[Bool]? = None,
  prepared_capacity? : PreparedModelCapacity? = None,
  original_startup? : OriginalModelStartup? = None,
) -> Result[ModelExecution, ModelExecutionIssue] {
  let task = @infer.model_task(@relation.prepared_infer_rows_owner(rows))
  // The actual mock is not the legacy synchronous fixture shortcut. Require
  // the original Run and pre-root startup before retaining inputs. Dispatch
  // is bound after the same request inventory is prepared, as for durable I/O;
  // its original acknowledgement remains mandatory before invocation.
  if source is Provider(provider) &&
    provider.invocation is OriginalMock(original) {
    if !original_mock_provider_matches(original, provider, task) ||
      original.users == 2147483647 ||
      call_scope is None ||
      original_startup is None ||
      physical_preflight is Some(_) ||
      !durable_calls {
      return Err(InvalidProvider)
    }
  }
  if egress_admission is Some(admission) &&
    !(call_scope is Some(scope) &&
    @publication_host.client_infer_egress_matches_scope(admission, scope)) {
    return Err(Egress(@publication_host.ForeignOwner))
  }
  if physical_preflight is Some(_) &&
    (!(source is Provider(_)) || quantity_capacity is None) {
    return Err(InvalidLimits)
  }
  if source is Provider(provider) &&
    provider.invocation is AsynchronousPhysical &&
    (!durable_calls || physical_preflight is None || quantity_capacity is None) {
    return Err(InvalidProvider)
  }
  if !valid_cid(fixed_request_cid) ||
    limits.max_items < 0 ||
    limits.max_work < 0 ||
    limits.max_request_bytes < 0L ||
    limits.max_response_bytes < 0L ||
    limits.max_request_bytes > 9223372036854775807L - limits.max_response_bytes ||
    limits.value_limits.max_nodes < 0 ||
    limits.value_limits.max_depth < 0 ||
    limits.value_limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if (dispatch_admission is Some(_) || durable_calls) &&
    limits.max_request_bytes + limits.max_response_bytes >
    9223372036854775807L - 81920L - model_attachment_evidence_bytes(task) {
    return Err(InvalidLimits)
  }
  if call_scope is Some(scope) &&
    !@publication_host.client_infer_call_scope_matches_rows(
      scope, rows, fixed_request_cid,
    ) {
    return Err(RequestIdentity)
  }
  if source is Provider(provider) &&
    provider.invocation is OriginalMock(original) &&
    !(call_scope is Some(scope) &&
    @environment.model_mock_execution_matches(
      original.profile.unwrap(),
      original.normalized.unwrap(),
      @publication_host.client_infer_call_scope_model_execution(scope),
    )) {
    return Err(RequestIdentity)
  }
  if dispatch_admission is Some(admission) &&
    !(call_scope is Some(scope) &&
    @publication_host.client_infer_dispatch_matches_scope(admission, scope)) {
    return Err(RequestIdentity)
  }
  let count = @relation.prepared_infer_rows_count(rows)
  // Task admission does not enable a native Decision transport in this
  // synchronous profile. Refuse before acquiring inputs or creating a Ledger.
  if source is Provider(provider) &&
    (
      provider.invocation is SynchronousFixture(_) ||
      provider.invocation is OriginalMock(_)
    ) &&
    @environment.model_task_kind(task) == @environment.Decision {
    return Err(InvalidProvider)
  }
  if source is Provider(provider) &&
    provider.provider_id != @environment.model_task_connector(task) {
    return Err(InvalidProvider)
  }
  if count > limits.max_items ||
    (
      @relation.prepared_infer_rows_item_guard(rows) is Some(max) &&
      count.to_int64() > max
    ) ||
    (
      @environment.model_task_max_items(task) is Some(max) &&
      count.to_int64() > max
    ) {
    return Err(ItemLimit)
  }
  if count > limits.max_work {
    return Err(InvalidLimits)
  }
  if original_startup is Some(original) &&
    (
      prepared_capacity is Some(_) ||
      !(source is Provider(_)) ||
      !original_model_startup_matches(
        original,
        rows,
        call_scope,
        limits,
        quantity_capacity,
        match source {
          Provider(provider) => Some(provider)
          _ => None
        },
      )
    ) {
    return Err(RequestIdentity)
  }
  let ledger = match original_startup {
    Some(original) => original.ledger
    None =>
      match @resources.create_ledger(limits.ledger) {
        Ok(value) => value
        Err(issue) => return Err(Ledger(issue))
      }
  }
  if quantity_capacity is Some(capacity) {
    if !(source is Provider(_)) ||
      capacity.per_attempt.tokens < 0L ||
      capacity.per_attempt.cost_units < 0L ||
      capacity.per_attempt.duration_ms < 0L ||
      capacity.per_attempt.tokens > 9007199254740991L ||
      capacity.per_attempt.cost_units > 9007199254740991L ||
      capacity.per_attempt.duration_ms > 9007199254740991L {
      return Err(InvalidLimits)
    }
    // Original quantity configuration predates read custody; compare, never reset.
    if original_startup is None {
      match @resources.configure_quantities(ledger, capacity.limits) {
        Err(issue) => return Err(Ledger(issue))
        Ok(_) => ()
      }
    }
  }
  if send_mask is Some(mask) && (!durable_calls || mask.length() != count) {
    return Err(RequestIdentity)
  }
  // The internal caller must supply the complete extra holding envelope, not
  // an eligible-send count or a spare portion of an attempt's evidence budget.
  // No public caller supplies this descriptor yet; no new key is retained.
  let capacity = match original_startup {
    Some(original) => Some(original.capacity)
    None =>
      match reserve_prepared_model_capacity(ledger, count, prepared_capacity) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
  }
  guard @relation.acquire_prepared_infer_rows(rows) is Some(input_use) else {
    if original_startup is None && capacity is Some(reservation) {
      match @resources.settle_capacity(ledger, reservation) {
        Ok(_) => ()
        Err(issue) => return Err(Ledger(issue))
      }
    }
    return Err(OutputIdentity)
  }
  // Refusals above leave the token unconsumed, with original cleanup custody.
  if original_startup is Some(original) {
    original.used = true
  }
  if source is Provider(provider) &&
    provider.invocation is OriginalMock(original) {
    // Bind the checked Task from the same original rows only on a successful
    // startup. An equal re-parsed Task cannot replace this original later.
    original.task = Some(task)
    original.users += 1
  }
  let reservations : Map[Int, @resources.Reservation] = Map([])
  let state : ModelState = {
    rows,
    input_use,
    task,
    source,
    fixed_request_cid,
    limits,
    quantity_capacity,
    call_scope,
    dispatch_admission,
    egress_admission,
    attempts: Map([]),
    attempt_slots: [],
    restored_calls: Map([]),
    unknown_calls: Map([]),
    reconciled_responses: Map([]),
    response_reconciliations: Map([]),
    ledger,
    prepared_capacity: capacity,
    original_startup,
    reservations,
    send_mask: send_mask.map(mask => mask.copy()),
    reservation_next_slot: 0,
    requests: [],
    physical_preflight,
    physical_cursors: [],
    physical_plans: Map([]),
    physical_next_slot: 0,
    physical_pending: None,
    physical_cleanup_index: 0,
    durable_calls,
    enter_call: None,
    enter_persistence: None,
    physical_observer: None,
    prepared_call_set: None,
    stop_requested: false,
    outcomes: [],
    slot_window: None,
    request: None,
    captures: [],
    responses: [],
    invocation_evidence: [],
    restored_evidence: None,
    restored_binding: None,
    progress: {
      phase: ReserveSlots,
      slot: 0,
      entry: None,
      call: None,
      settlement: None,
      observing_response: false,
      io_duty: None,
    },
    work: 0,
    output_uses: 0,
    accepted: false,
    reclaimed: false,
  }
  let control = @bounded.control()
  let (session, token) = @bounded.start(
    control,
    state,
    advance_model,
    cleanup_model_physical_preflight,
    _ => true,
  )
  Ok({
    session,
    token,
    control,
    state,
    progress: 0L,
    work: 0L,
    advancing: false,
  })
}

///|
pub fn advance_model_execution(
  execution : ModelExecution,
  quantum : Int,
) -> Result[ModelObservation, ModelExecutionIssue] {
  if quantum < 1 {
    return Err(InvalidLimits)
  }
  if execution.advancing {
    return Err(Session(@bounded.ConcurrentResume))
  }
  if check_model_original_resources_mutable(execution.state) is Err(issue) {
    return Err(issue)
  }
  execution.advancing = true
  let observation = advance_model_execution_owned(execution, quantum)
  execution.advancing = false
  observation
}

///|
fn advance_model_execution_owned(
  execution : ModelExecution,
  quantum : Int,
) -> Result[ModelObservation, ModelExecutionIssue] {
  let state = execution.state
  if !state.reclaimed && !@bounded.session_stopped(execution.session) {
    match select_model_window_progress(state) {
      Err(issue) => return Err(issue)
      Ok(false) => return Ok(AwaitIo(execution.progress, execution.work))
      Ok(true) => ()
    }
  }
  if !state.reclaimed &&
    !@bounded.session_stopped(execution.session) &&
    state.progress.call is Some(call) {
    if call.settlement_acknowledged {
      if !cleanup_model_physical_call(state) {
        return Ok(AwaitIo(execution.progress, execution.work))
      }
    } else if state.progress.phase is AwaitPhysicalResponse {
      if state.stop_requested {
        cancel_model_physical_call(call)
      }
      match poll_model_physical_call(call) {
        Err(issue) => call.poll_issue = Some(issue)
        Ok(Some(PhysicalPending) | None) =>
          return Ok(AwaitIo(execution.progress, execution.work))
        Ok(Some(_)) => ()
      }
    }
  }
  if state.durable_calls &&
    !state.reclaimed &&
    !@bounded.session_stopped(execution.session) {
    if state.progress.settlement is Some(slot) {
      return Ok(Settling(slot, execution.progress, execution.work))
    }
    if state.progress.entry is Some(entry) &&
      entry.persistence is Some(operation) {
      match
        poll_model_call_entry_persistence(operation, entry, entry.prepared) {
        Ok(Pending) => return Ok(AwaitIo(execution.progress, execution.work))
        Ok(_) | Err(_) => ()
      }
    }
    if !state.stop_requested &&
      state.progress.phase is DispatchSlot &&
      (
        state.prepared_call_set is None ||
        state.prepared_call_set.unwrap().scope is None ||
        (
          state.progress.slot < state.requests.length() &&
          !state.restored_calls.contains(state.progress.slot) &&
          !state.unknown_calls.contains(state.progress.slot) &&
          (
            (state.enter_call is None && state.enter_persistence is None) ||
            state.dispatch_admission is None
          )
        )
      ) {
      return Ok(Waiting(execution.progress, execution.work))
    }
  }
  // A persistence observation callback may establish a resource fence while
  // retaining its original pending save. Do not enter the kernel from that
  // stale pre-callback check or translate the restriction into a terminal.
  if check_model_original_resources_mutable(state) is Err(issue) {
    return Err(issue)
  }
  if !state.stop_requested && !@bounded.session_stopped(execution.session) {
    match model_slot_io_available(state) {
      Err(issue) => return Err(issue)
      Ok(false) => return Ok(AwaitIo(execution.progress, execution.work))
      Ok(true) => ()
    }
  }
  match @bounded.advance(execution.session, execution.token, quantum) {
    Err(issue) => Err(Session(issue))
    Ok(@bounded.ContinueWith(token, progress~, work~)) => {
      execution.token = token
      execution.progress = progress
      execution.work = work
      Ok(Continue(progress, work))
    }
    Ok(@bounded.Completed(bundle, progress~, work~)) => {
      execution.state.accepted = true
      Ok(Completed(bundle, progress, work))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      finish_model_attempt_failure(execution.state, issue)
      Ok(Failed(issue, progress, work))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      finish_model_attempt_stop(execution.state, reason)
      Ok(Stopped(reason, progress, work))
    }
  }
}

///|
pub fn request_model_cancel(execution : ModelExecution) -> Bool {
  if check_model_original_resources_mutable(execution.state) is Err(_) {
    return false
  }
  execution.state.stop_requested = true
  if execution.state.durable_calls &&
    (
      execution.state.progress.observing_response ||
      execution.state.progress.entry is Some(_) ||
      execution.state.progress.settlement is Some(_)
    ) {
    // Sending is fenced immediately; finishing an already-returned observation
    // is a bounded cleanup duty and does not authorize another provider call.
    return true
  }
  @bounded.request_cancel(execution.control)
}

///|
/// Observe the existing physical ledger; this does not issue budget or Run
/// evidence or authorize another dispatch.
pub fn model_execution_resource_usage(
  execution : ModelExecution,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(execution.state.ledger)
}

///|
pub fn model_execution_quantity_usage(
  execution : ModelExecution,
) -> @resources.QuantityUsage {
  @resources.quantity_usage(execution.state.ledger)
}

///|
/// Observe physical preparation progress, never a Run or evidence authority.
pub fn model_execution_preflighting(execution : ModelExecution) -> Bool {
  !execution.state.reclaimed &&
  !@bounded.session_stopped(execution.session) &&
  (
    execution.state.progress.phase is PrepareRequests ||
    execution.state.progress.phase is PreparePhysicalRequests
  )
}

///|
/// A measured mapped-input body is not an admitted adapter request. It is
/// retained here so later dispatch cannot skip a failed row's preflight.
pub fn model_execution_prepared_request_bytes(
  execution : ModelExecution,
  slot : Int,
) -> Int64? {
  execution.state.requests.get(slot).map(value => value.wire_bytes)
}

///|
pub fn cleanup_model_execution(
  execution : ModelExecution,
) -> Result[Bool, ModelExecutionIssue] {
  if execution.advancing {
    return Err(Session(@bounded.ConcurrentResume))
  }
  if check_model_original_resources_mutable(execution.state) is Err(issue) {
    return Err(issue)
  }
  execution.advancing = true
  let result = cleanup_model_execution_owned(execution)
  execution.advancing = false
  result
}

///|
fn cleanup_model_execution_owned(
  execution : ModelExecution,
) -> Result[Bool, ModelExecutionIssue] {
  if execution.state.reclaimed {
    // Settlement retry must keep the original token without repeating the
    // physical cleanup or admitting another attempt.
    return finish_prepared_model_capacity(execution.state)
  }
  if execution.state.output_uses > 0 {
    return Ok(false)
  }
  match @bounded.cleanup(execution.session) {
    Ok(false) => Ok(false)
    Ok(true) => {
      if @bounded.cleanup_pending(execution.session) {
        return Ok(false)
      }
      if execution.state.slot_window is Some(window) {
        for frame in window.frames {
          if frame is Some(frame) {
            cancel_model_slot_phase(frame.progress)
          }
        }
        window.outcomes.clear()
        if window.export_captures is Some(exported) {
          retire_model_owned_array(exported)
          window.export_captures = None
        }
        retire_model_owned_array(window.adopted_slots)
        retire_model_owned_array(window.frames)
        execution.state.slot_window = None
      } else {
        cancel_model_slot_phase(execution.state.progress)
      }
      if execution.state.request is Some(request) {
        cancel_model_request_preparation(request)
        execution.state.request = None
      }
      execution.state.progress.phase = Reclaimed
      for (_, reservation) in execution.state.reservations {
        if @resources.reservation_open(reservation) {
          @resources.settle_reservation(execution.state.ledger, reservation)
          |> ignore
        }
      }
      @relation.release_prepared_infer_rows_use(execution.state.input_use)
      |> ignore
      retire_model_owned_array(execution.state.captures)
      retire_model_owned_array(execution.state.responses)
      retire_model_owned_array(execution.state.invocation_evidence)
      execution.state.restored_evidence = None
      execution.state.restored_binding = None
      retire_model_owned_array(execution.state.requests)
      execution.state.physical_plans.clear()
      retire_model_owned_array(execution.state.physical_cursors)
      execution.state.physical_observer = None
      retire_model_owned_array(execution.state.outcomes)
      for (_, saved) in execution.state.restored_calls {
        if saved.bundle is Some(bundle) {
          @publication.release_model_capture_bundle_read(bundle) |> ignore
        }
      }
      execution.state.restored_calls.clear()
      execution.state.reconciled_responses.clear()
      execution.state.response_reconciliations.clear()
      if execution.state.source is Replay(capture) {
        capture.owner.state.output_uses -= 1
      }
      if execution.state.source is Restored(capture) {
        @publication.release_model_capture_bundle_read(capture) |> ignore
      }
      if execution.state.source is RestoredSlots(read) {
        release_model_slot_replay(read) |> ignore
      }
      if execution.state.source is Provider(provider) &&
        provider.invocation is OriginalMock(original) {
        original.users -= 1
      }
      // Retire the added adapter captures only after original physical cleanup
      // succeeds. Escaped terminal ACKs still retain their original Owner.
      execution.state.enter_persistence = None
      execution.state.reclaimed = true
      finish_prepared_model_capacity(execution.state)
    }
    Err(issue) => Err(Session(issue))
  }
}

///|
/// Emit the sealed captures as a bounded JSON observation for a Host boundary.
/// The key CID and slot identity remain alongside each typed result so a caller
/// cannot validate only the result values and silently lose input evidence.
pub fn model_capture_bundle_json(
  bundle : ModelCaptureBundle,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String? {
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return None
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "fixed_request_cid")
    @encode.string_value(writer, bundle.fixed_request_cid)
    @encode.key(writer, "task_cid")
    @encode.string_value(writer, bundle.task_cid)
    @encode.key(writer, "captures")
    @encode.begin_array(writer)
    for capture in bundle.captures {
      @encode.begin_object(writer)
      @encode.key(writer, "input_key_cid")
      @encode.string_value(writer, capture.input_key_cid)
      @encode.key(writer, "input_tokens")
      emit_model_optional_tokens(writer, capture.input_tokens)
      @encode.key(writer, "observed_at")
      @encode.string_value(writer, capture.observed_at)
      @encode.key(writer, "output_tokens")
      emit_model_optional_tokens(writer, capture.output_tokens)
      @encode.key(writer, "provider_id")
      @encode.string_value(writer, capture.provider_id)
      @encode.key(writer, "provider_model")
      emit_model_optional_text(writer, capture.provider_model)
      @encode.key(writer, "provider_request_id")
      emit_model_optional_text(writer, capture.provider_request_id)
      @encode.key(writer, "slot")
      @encode.number_value(writer, capture.slot.to_double())
      @encode.key(writer, "slot_cid")
      @encode.string_value(writer, capture.slot_cid)
      @encode.key(writer, "value")
      @admitted.emit_checked_wire_value(capture.value, writer)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Some(@encode.finish(writer))
  } catch {
    _ => None
  }
}

///|
/// Replay validates the fixed request and slot identities, and returns the
/// retained typed values without invoking a Provider. This DATA-only check
/// neither authenticates a formal Run nor replaces verified capture replay.
pub fn replay_model_capture(
  task : @environment.ModelTaskContract,
  fixed_request_cid : String,
  bundle : ModelCaptureBundle,
) -> Result[Array[@admitted.CheckedValue], ModelExecutionIssue] {
  if bundle.task_cid != @environment.model_task_identity(task).2 ||
    bundle.fixed_request_cid != fixed_request_cid {
    return Err(OutputIdentity)
  }
  let output : Array[@admitted.CheckedValue] = []
  for index, capture in bundle.captures {
    if capture.slot != index ||
      capture.fixed_request_cid != fixed_request_cid ||
      !valid_cid(capture.slot_cid) ||
      !valid_cid(capture.input_key_cid) ||
      capture.provider_id != @environment.model_task_connector(task) ||
      !valid_model_optional_text(capture.provider_model) ||
      !valid_model_optional_tokens(capture.input_tokens) ||
      !valid_model_optional_tokens(capture.output_tokens) ||
      capture.observed_at.is_empty() ||
      !valid_model_optional_text(capture.provider_request_id) {
      return Err(OutputIdentity)
    }
    output.push(capture.value)
  }
  Ok(output)
}

///|
/// Replay for the exact admitted input: valid-looking CID strings alone do
/// not prove that captures belong to these keys or call slots. No provider
/// or dispatch operation is available through this path. This legacy helper
/// checks the unscoped array-key and fixed-request/index slot preimages. A
/// scoped model_input_key/formal call-slot CID is a different domain and is
/// refused; use the original Scope/VerifiedModelCapture replay path for it.
pub fn replay_model_capture_rows(
  rows : @relation.PreparedInferRows,
  fixed_request_cid : String,
  bundle : ModelCaptureBundle,
) -> Result[Array[@admitted.CheckedValue], ModelExecutionIssue] {
  guard @relation.acquire_prepared_infer_rows(rows) is Some(input_use) else {
    return Err(OutputIdentity)
  }
  let result = replay_model_capture_rows_owned(rows, fixed_request_cid, bundle)
  @relation.release_prepared_infer_rows_use(input_use) |> ignore
  result
}

///|
fn replay_model_capture_rows_owned(
  rows : @relation.PreparedInferRows,
  fixed_request_cid : String,
  bundle : ModelCaptureBundle,
) -> Result[Array[@admitted.CheckedValue], ModelExecutionIssue] {
  let owner = @relation.prepared_infer_rows_owner(rows)
  let task = @infer.model_task(owner)
  if bundle.captures.length() != @relation.prepared_infer_rows_count(rows) {
    return Err(OutputIdentity)
  }
  for index, capture in bundle.captures {
    guard request_key(rows, index, owner) is Some(key) &&
      key_cid(key) is Some(expected_key) &&
      slot_cid(fixed_request_cid, index, key) is Some(expected_slot) else {
      return Err(OutputIdentity)
    }
    if capture.input_key_cid != expected_key ||
      capture.slot_cid != expected_slot ||
      capture.provider_id != @environment.model_task_connector(task) {
      return Err(OutputIdentity)
    }
  }
  replay_model_capture(task, fixed_request_cid, bundle)
}

///|
// Entered responsibility consumes an attempt even for a local original Mock.
// Its absence of transport must not erase attempt history or invent wire use.
fn mark_model_attempt_entered(
  state : ModelState,
  reservation : @resources.Reservation,
) -> Result[Unit, @resources.LedgerIssue] {
  if state.source is Provider(provider) &&
    provider.invocation is OriginalMock(_) {
    @resources.consume_reserved_attempt(state.ledger, reservation)
  } else {
    @resources.mark_transfer_uncertain(
      state.ledger,
      reservation,
      state.limits.max_request_bytes + state.limits.max_response_bytes,
    )
  }
}
