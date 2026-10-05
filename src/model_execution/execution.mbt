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
/// A provider is physical I/O. It is installed by the Host and cannot be
/// selected by a Program value or by a model selector string alone.
pub(all) struct ModelProvider {
  invoke : (ModelRequest) -> Result[ModelResponse, ModelProviderFailure]
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
  Ok({ invoke, provider_id, })
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
  Provider(ModelProviderFailure)
  OutputValue
  OutputIdentity
  Cancelled
  Deadline
  Ledger(@resources.LedgerIssue)
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
  provider_model : String
  provider_request_id : String
  value : @admitted.CheckedValue
  input_tokens : Int64
  output_tokens : Int64
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
  CheckResponse(ModelRequest, ModelResponse, String, @admitted.RecheckCursor)
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
  unknown_calls : Map[Int, Bool]
  ledger : @resources.Ledger
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
  mut entering : ModelCallEntry?
  mut prepared_call_set : ModelPreparedCallSet?
  mut settlement_pending : Int?
  mut stop_requested : Bool
  mut observing_response : Bool
  outcomes : Array[AdoptedModelSlot]
  mut request : ModelRequestPreparation?
  captures : Array[ModelSlotCapture]
  responses : Array[@admitted.Value]
  invocation_evidence : Array[@publication.RunEvidenceValue]
  mut restored_evidence : @publication.RunEvidenceValue?
  mut restored_binding : @publication.BoundModelSlotCapture?
  mut phase : ModelPhase
  mut work : Int
  mut next_slot : Int
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
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 0, 0)
  }
  if state.stop_requested && !state.observing_response {
    return @bounded.Stopped(@bounded.Cancelled, 0, 0)
  }
  if quantum < 1 {
    return @bounded.Failed(InvalidLimits, 0, 0)
  }
  if state.work >= state.limits.max_work {
    return @bounded.Failed(WorkLimit, 0, 0)
  }
  state.work += 1
  if state.phase is ReserveSlots {
    // Replay owns a read of an already checked observation. It must neither
    // reserve another physical attempt nor re-enter a provider on failure.
    if state.source is Replay(_) ||
      state.source is Restored(_) ||
      state.source is RestoredSlots(_) {
      state.phase = PrepareRequests
      return @bounded.Continue(1, 1)
    }
    if state.reservation_next_slot <
      @relation.prepared_infer_rows_count(state.rows) {
      let ordinal = state.reservation_next_slot
      if !model_slot_send_eligible(state, ordinal) {
        state.reservation_next_slot += 1
        return @bounded.Continue(1, 1)
      }
      match
        @resources.reserve_attempt(
          state.ledger,
          state.limits.max_request_bytes + state.limits.max_response_bytes,
          state.limits.max_request_bytes +
          state.limits.max_response_bytes +
          (if state.dispatch_admission is Some(_) || state.durable_calls {
            81920L
          } else {
            0L
          }),
          if state.physical_preflight is Some(_) {
            physical_preflight_metadata_bytes
          } else {
            0L
          },
          quantities=state.quantity_capacity.map(value => value.per_attempt),
        ) {
        Ok(value) => state.reservations[ordinal] = value
        Err(issue) => return @bounded.Failed(Ledger(issue), 1, 1)
      }
      state.reservation_next_slot += 1
      if state.reservation_next_slot ==
        @relation.prepared_infer_rows_count(state.rows) {
        state.phase = PrepareRequests
      }
      return @bounded.Continue(1, 1)
    }
    // All reservations precede the first dispatch, including an empty input.
    state.phase = PrepareRequests
  }
  if state.phase is PrepareRequests {
    return advance_model_request_preparation(state)
  }
  if state.phase is PreparePhysicalRequests {
    return advance_model_physical_preflight(state)
  }
  if state.next_slot >= @relation.prepared_infer_rows_count(state.rows) {
    return complete_model_slots(state)
  }
  if state.phase is CheckResponse(request, response, input_key_cid, cursor) {
    match @admitted.advance_recheck_runtime_value(cursor) {
      RecheckContinue => return @bounded.Continue(1, 1)
      RecheckFailed => return @bounded.Failed(OutputValue, 1, 1)
      RecheckComplete(checked, _, _) => {
        if state.call_scope is Some(_) {
          match
            start_model_evidence(
              state, request, response, input_key_cid, checked,
            ) {
            Ok(value) => state.phase = PrepareEvidence(value)
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
  if state.phase is RestoreResponse(prepared, record, cursor) {
    return advance_restored_model_response(state, prepared, record, cursor)
  }
  if state.phase is PrepareEvidence(preparation) {
    match advance_model_evidence(state, preparation) {
      Err(issue) => return @bounded.Failed(issue, 1, 1)
      Ok(None) => return @bounded.Continue(1, 1)
      Ok(Some(evidence)) => {
        if (
            state.source is Restored(_) ||
            state.source is RestoredSlots(_) ||
            state.restored_calls.contains(state.next_slot)
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
          state.restored_calls.contains(state.next_slot) {
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
        if state.attempts.get(state.next_slot) is Some(trace) {
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
  if !(state.phase is DispatchSlot) {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  guard state.requests.get(state.next_slot) is Some(prepared) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  let request = prepared.request
  if state.durable_calls &&
    state.restored_calls.get(state.next_slot) is Some(saved) {
    return advance_partial_model_restore(state, saved, prepared)
  }
  if state.durable_calls && state.unknown_calls.contains(state.next_slot) {
    state.outcomes.push(UnresolvedUnknown)
    state.next_slot += 1
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
  guard model_slot_send_eligible(state, state.next_slot) &&
    state.reservations.get(state.next_slot) is Some(reservation) else {
    return @bounded.Failed(CallEntryRefused, 1, 1)
  }
  let attempt = if state.dispatch_admission is Some(admission) {
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
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 1, 1)
  }
  // ModelResponse contains typed content and token observations, not exact
  // transport bytes. Retain the dispatched envelope as uncertain usage before
  // entering physical I/O: invalid metadata, rejected content or cancellation
  // must not make that request unused when cleanup settles its reservation.
  match
    @resources.mark_transfer_uncertain(
      state.ledger,
      reservation,
      state.limits.max_request_bytes + state.limits.max_response_bytes,
    ) {
    Err(issue) => return @bounded.Failed(Ledger(issue), 1, 1)
    Ok(_) => ()
  }
  if state.quantity_capacity is Some(_) {
    match @resources.mark_quantities_uncertain(state.ledger, reservation) {
      Err(issue) => return @bounded.Failed(Ledger(issue), 1, 1)
      Ok(_) => ()
    }
  }
  // The Host's synchronous callback durably records this exact owner-issued
  // attempt. It is the final fallible admission before the retained provider
  // call. No asynchronous boundary or fresh request construction follows it.
  if state.durable_calls {
    guard state.prepared_call_set is Some(prepared_set) &&
      state.enter_call is Some(enter) &&
      attempt is Some(trace) &&
      state.dispatch_admission is Some(admission) else {
      return @bounded.Failed(CallEntryRefused, 1, 1)
    }
    let entry = {
      prepared: prepared_set,
      slot: state.next_slot,
      trace,
      admission,
    }
    state.entering = Some(entry)
    let admitted = enter(entry)
    state.entering = None
    if !admitted {
      return @bounded.Failed(CallEntryRefused, 1, 1)
    }
  }
  if attempt is Some(attempt) {
    state.attempts[state.next_slot] = attempt
    state.attempt_slots.push(state.next_slot)
  }
  // A cancellation delivered by a synchronous entry observer cannot start I/O.
  // Once provider entry begins, however, returned response custody survives
  // cancellation and is verified/persisted before physical cleanup completes.
  if state.stop_requested {
    return @bounded.Stopped(@bounded.Cancelled, 1, 1)
  }
  state.observing_response = state.durable_calls
  let invoked = match state.physical_preflight {
    None => (provider.invoke)(request)
    Some(_) => {
      guard state.physical_plans.get(state.next_slot) is Some(plan) else {
        return @bounded.Failed(RequestIdentity, 1, 1)
      }
      (plan.invoke)()
    }
  }
  let response = match invoked {
    Ok(value) => value
    Err(issue) => {
      state.observing_response = false
      if @bounded.stop_requested(reader) is Some(reason) {
        return @bounded.Stopped(reason, 1, 1)
      }
      if issue == Cancelled {
        return @bounded.Stopped(@bounded.Cancelled, 1, 1)
      }
      return accept_failed_model_slot(state, issue)
    }
  }
  if state.attempts.get(state.next_slot) is Some(trace) {
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
  state.phase = CheckResponse(request, response, input_key_cid, cursor)
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
) -> Result[ModelExecution, ModelExecutionIssue] {
  if egress_admission is Some(admission) &&
    !(call_scope is Some(scope) &&
    @publication_host.client_infer_egress_matches_scope(admission, scope)) {
    return Err(Egress(@publication_host.ForeignOwner))
  }
  if physical_preflight is Some(_) &&
    (!(source is Provider(_)) || quantity_capacity is None) {
    return Err(InvalidLimits)
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
    9223372036854775807L - 81920L {
    return Err(InvalidLimits)
  }
  if call_scope is Some(scope) &&
    !@publication_host.client_infer_call_scope_matches_rows(
      scope, rows, fixed_request_cid,
    ) {
    return Err(RequestIdentity)
  }
  if dispatch_admission is Some(admission) &&
    !(call_scope is Some(scope) &&
    @publication_host.client_infer_dispatch_matches_scope(admission, scope)) {
    return Err(RequestIdentity)
  }
  let count = @relation.prepared_infer_rows_count(rows)
  let task = @infer.model_task(@relation.prepared_infer_rows_owner(rows))
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
  let ledger = match @resources.create_ledger(limits.ledger) {
    Ok(value) => value
    Err(issue) => return Err(Ledger(issue))
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
    match @resources.configure_quantities(ledger, capacity.limits) {
      Err(issue) => return Err(Ledger(issue))
      Ok(_) => ()
    }
  }
  if send_mask is Some(mask) && (!durable_calls || mask.length() != count) {
    return Err(RequestIdentity)
  }
  guard @relation.acquire_prepared_infer_rows(rows) is Some(input_use) else {
    return Err(OutputIdentity)
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
    ledger,
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
    entering: None,
    prepared_call_set: None,
    settlement_pending: None,
    stop_requested: false,
    observing_response: false,
    outcomes: [],
    request: None,
    captures: [],
    responses: [],
    invocation_evidence: [],
    restored_evidence: None,
    restored_binding: None,
    phase: ReserveSlots,
    work: 0,
    next_slot: 0,
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
  Ok({ session, token, control, state, progress: 0L, work: 0L, })
}

///|
pub fn advance_model_execution(
  execution : ModelExecution,
  quantum : Int,
) -> Result[ModelObservation, ModelExecutionIssue] {
  if quantum < 1 {
    return Err(InvalidLimits)
  }
  let state = execution.state
  if state.durable_calls &&
    !state.reclaimed &&
    !@bounded.session_stopped(execution.session) {
    if state.settlement_pending is Some(slot) {
      return Ok(Settling(slot, execution.progress, execution.work))
    }
    if !state.stop_requested &&
      state.phase is DispatchSlot &&
      (
        state.prepared_call_set is None ||
        state.prepared_call_set.unwrap().scope is None ||
        (
          state.next_slot < state.requests.length() &&
          !state.restored_calls.contains(state.next_slot) &&
          !state.unknown_calls.contains(state.next_slot) &&
          (state.enter_call is None || state.dispatch_admission is None)
        )
      ) {
      return Ok(Waiting(execution.progress, execution.work))
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
  execution.state.stop_requested = true
  if execution.state.durable_calls &&
    (
      execution.state.observing_response ||
      execution.state.settlement_pending is Some(_)
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
    execution.state.phase is PrepareRequests ||
    execution.state.phase is PreparePhysicalRequests
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
  if execution.state.reclaimed {
    return Ok(true)
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
      if execution.state.phase is CheckResponse(_, _, _, cursor) {
        @admitted.cancel_recheck_runtime_value(cursor)
      }
      if execution.state.phase is PrepareEvidence(value) {
        cancel_model_evidence(value)
      }
      if execution.state.phase is RestoreResponse(_, _, cursor) {
        @admitted.cancel_canonical_conversion(cursor)
      }
      if execution.state.request is Some(request) {
        cancel_model_request_preparation(request)
        execution.state.request = None
      }
      execution.state.phase = Reclaimed
      for (_, reservation) in execution.state.reservations {
        if @resources.reservation_open(reservation) {
          @resources.settle_reservation(execution.state.ledger, reservation)
          |> ignore
        }
      }
      @relation.release_prepared_infer_rows_use(execution.state.input_use)
      |> ignore
      execution.state.captures.clear()
      execution.state.responses.clear()
      execution.state.invocation_evidence.clear()
      execution.state.restored_evidence = None
      execution.state.restored_binding = None
      execution.state.requests.clear()
      execution.state.physical_plans.clear()
      execution.state.physical_cursors.clear()
      execution.state.outcomes.clear()
      for (_, saved) in execution.state.restored_calls {
        if saved.bundle is Some(bundle) {
          @publication.release_model_capture_bundle_read(bundle) |> ignore
        }
      }
      execution.state.restored_calls.clear()
      if execution.state.source is Replay(capture) {
        capture.owner.state.output_uses -= 1
      }
      if execution.state.source is Restored(capture) {
        @publication.release_model_capture_bundle_read(capture) |> ignore
      }
      if execution.state.source is RestoredSlots(read) {
        release_model_slot_replay(read) |> ignore
      }
      execution.state.reclaimed = true
      Ok(true)
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
      @encode.decimal_number_value(writer, capture.input_tokens.to_string())
      @encode.key(writer, "observed_at")
      @encode.string_value(writer, capture.observed_at)
      @encode.key(writer, "output_tokens")
      @encode.decimal_number_value(writer, capture.output_tokens.to_string())
      @encode.key(writer, "provider_id")
      @encode.string_value(writer, capture.provider_id)
      @encode.key(writer, "provider_model")
      @encode.string_value(writer, capture.provider_model)
      @encode.key(writer, "provider_request_id")
      @encode.string_value(writer, capture.provider_request_id)
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
/// retained typed values without invoking a Provider.
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
      capture.provider_model.is_empty() ||
      capture.input_tokens < 0L ||
      capture.output_tokens < 0L ||
      capture.observed_at.is_empty() ||
      capture.provider_request_id.is_empty() {
      return Err(OutputIdentity)
    }
    output.push(capture.value)
  }
  Ok(output)
}

///|
/// Replay for the exact admitted input: valid-looking CID strings alone do
/// not prove that captures belong to these keys or call slots. No provider
/// or dispatch operation is available through this path.
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
