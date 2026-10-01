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
}

///|
pub(all) enum ModelObservation {
  Continue(Int64, Int64)
  Completed(ModelCaptureBundle, Int64, Int64)
  Failed(ModelExecutionIssue, Int64, Int64)
  Stopped(@bounded.StopReason, Int64, Int64)
}

///|
priv enum ModelPhase {
  ReserveSlots
  PrepareRequests
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
}

///|
struct ModelState {
  rows : @relation.PreparedInferRows
  input_use : @relation.InferRowsUse
  task : @environment.ModelTaskContract
  source : ModelSource
  fixed_request_cid : String
  limits : ModelExecutionLimits
  call_scope : @publication_host.ClientInferCallScope?
  ledger : @resources.Ledger
  reservations : Array[@resources.Reservation]
  requests : Array[PreparedModelRequest]
  outcomes : Array[AdoptedModelSlot]
  mut request : ModelRequestPreparation?
  captures : Array[ModelSlotCapture]
  responses : Array[@admitted.Value]
  invocation_evidence : Array[@publication.RunEvidenceValue]
  mut restored_evidence : @publication.RunEvidenceValue?
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
    if state.source is Replay(_) || state.source is Restored(_) {
      state.phase = PrepareRequests
      return @bounded.Continue(1, 1)
    }
    if state.reservations.length() <
      @relation.prepared_infer_rows_count(state.rows) {
      match
        @resources.reserve_attempt(
          state.ledger,
          state.limits.max_request_bytes + state.limits.max_response_bytes,
          state.limits.max_request_bytes + state.limits.max_response_bytes,
          0L,
        ) {
        Ok(value) => state.reservations.push(value)
        Err(issue) => return @bounded.Failed(Ledger(issue), 1, 1)
      }
      if state.reservations.length() ==
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
  if state.next_slot >= @relation.prepared_infer_rows_count(state.rows) {
    return @bounded.Complete(
      {
        task_cid: @environment.model_task_identity(state.task).2,
        fixed_request_cid: state.fixed_request_cid,
        captures: state.captures.copy(),
      },
      1,
      1,
    )
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
        if state.source is Restored(_) &&
          (
            state.restored_evidence is None ||
            @publication.run_evidence_value_identity(
              state.restored_evidence.unwrap(),
            ) !=
            @publication.run_evidence_value_identity(evidence)
          ) {
          return @bounded.Failed(OutputIdentity, 1, 1)
        }
        state.restored_evidence = None
        state.invocation_evidence.push(evidence)
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
  if state.source is Replay(capture) {
    return advance_model_capture_replay(state, capture, prepared)
  }
  if state.source is Restored(capture) {
    return begin_restored_model_response(state, capture, prepared)
  }
  guard state.source is Provider(provider) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  let reservation = state.reservations[state.next_slot]
  let response = match (provider.invoke)(request) {
    Ok(value) => value
    Err(issue) => {
      // No physical byte observation arrived. Cleanup cannot turn the
      // dispatched request's unknown usage into an unused reservation.
      match
        @resources.mark_transfer_uncertain(
          state.ledger,
          reservation,
          state.limits.max_request_bytes + state.limits.max_response_bytes,
        ) {
        Err(error) => return @bounded.Failed(Ledger(error), 1, 1)
        Ok(_) => ()
      }
      if @bounded.stop_requested(reader) is Some(reason) {
        return @bounded.Stopped(reason, 1, 1)
      }
      if issue == Cancelled {
        return @bounded.Stopped(@bounded.Cancelled, 1, 1)
      }
      return accept_failed_model_slot(state, issue)
    }
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
  let transfer = state.limits.max_request_bytes +
    state.limits.max_response_bytes
  match @resources.charge_transfer(state.ledger, reservation, transfer) {
    Ok(_) => ()
    Err(issue) => return @bounded.Failed(Ledger(issue), 1, 1)
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
) -> Result[ModelExecution, ModelExecutionIssue] {
  start_model_owned(
    rows,
    Provider(provider),
    fixed_request_cid,
    limits,
    call_scope,
  )
}

///|
fn start_model_owned(
  rows : @relation.PreparedInferRows,
  source : ModelSource,
  fixed_request_cid : String,
  limits : ModelExecutionLimits,
  call_scope : @publication_host.ClientInferCallScope?,
) -> Result[ModelExecution, ModelExecutionIssue] {
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
  if call_scope is Some(scope) &&
    !@publication_host.client_infer_call_scope_matches_rows(
      scope, rows, fixed_request_cid,
    ) {
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
  guard @relation.acquire_prepared_infer_rows(rows) is Some(input_use) else {
    return Err(OutputIdentity)
  }
  let reservations : Array[@resources.Reservation] = []
  let state : ModelState = {
    rows,
    input_use,
    task,
    source,
    fixed_request_cid,
    limits,
    call_scope,
    ledger,
    reservations,
    requests: [],
    outcomes: [],
    request: None,
    captures: [],
    responses: [],
    invocation_evidence: [],
    restored_evidence: None,
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
    _ => true,
    _ => true,
  )
  Ok({ session, token, control, state, })
}

///|
pub fn advance_model_execution(
  execution : ModelExecution,
  quantum : Int,
) -> Result[ModelObservation, ModelExecutionIssue] {
  match @bounded.advance(execution.session, execution.token, quantum) {
    Err(issue) => Err(Session(issue))
    Ok(@bounded.ContinueWith(token, progress~, work~)) => {
      execution.token = token
      Ok(Continue(progress, work))
    }
    Ok(@bounded.Completed(bundle, progress~, work~)) => {
      execution.state.accepted = true
      Ok(Completed(bundle, progress, work))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) =>
      Ok(Failed(issue, progress, work))
    Ok(@bounded.StoppedWith(reason, progress~, work~)) =>
      Ok(Stopped(reason, progress, work))
  }
}

///|
pub fn request_model_cancel(execution : ModelExecution) -> Bool {
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
/// Observe physical preparation progress, never a Run or evidence authority.
pub fn model_execution_preflighting(execution : ModelExecution) -> Bool {
  !execution.state.reclaimed &&
  !@bounded.session_stopped(execution.session) &&
  execution.state.phase is PrepareRequests
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
      for reservation in execution.state.reservations {
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
      execution.state.requests.clear()
      execution.state.outcomes.clear()
      if execution.state.source is Replay(capture) {
        capture.owner.state.output_uses -= 1
      }
      if execution.state.source is Restored(capture) {
        @publication.release_model_capture_bundle_read(capture) |> ignore
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
