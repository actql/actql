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
} derive(Eq, Debug)

///|
/// A sealed slot capture. It is retained by the execution owner until the
/// caller explicitly transfers it to publication; replay never calls a
/// provider.
pub(all) struct ModelSlotCapture {
  slot : Int
  slot_cid : String
  input_key_cid : String
  fixed_request_cid : String
  provider_id : String
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
pub(all) enum ModelObservation {
  Continue(Int64, Int64)
  Completed(ModelCaptureBundle, Int64, Int64)
  Failed(ModelExecutionIssue, Int64, Int64)
  Stopped(@bounded.StopReason, Int64, Int64)
}

///|
struct ModelState {
  rows : @relation.PreparedInferRows
  input_use : @relation.InferRowsUse
  task : @environment.ModelTaskContract
  provider : ModelProvider
  fixed_request_cid : String
  limits : ModelExecutionLimits
  ledger : @resources.Ledger
  reservations : Array[@resources.Reservation]
  captures : Array[ModelSlotCapture]
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
fn request_inputs(
  rows : @relation.PreparedInferRows,
  slot : Int,
  owner : @infer.CheckedInfer,
) -> Array[(String, @admitted.CheckedValue)]? {
  let output : Array[(String, @admitted.CheckedValue)] = []
  for index in 0..<@infer.input_binding_count(owner) {
    guard @infer.input_binding_at(owner, index) is Some(binding) &&
      @relation.prepared_infer_rows_value(rows, slot, index) is Some(value) else {
      return None
    }
    output.push((@infer.input_binding_role(binding), value))
  }
  Some(output)
}

///|
fn make_request(
  state : ModelState,
) -> Result[ModelRequest, ModelExecutionIssue] {
  let owner = @relation.prepared_infer_rows_owner(state.rows)
  let task = @infer.model_task(owner)
  guard request_key(state.rows, state.next_slot, owner) is Some(key) &&
    request_inputs(state.rows, state.next_slot, owner) is Some(inputs) &&
    slot_cid(state.fixed_request_cid, state.next_slot, key) is Some(slot_cid) else {
    return Err(OutputIdentity)
  }
  Ok({
    task,
    slot: state.next_slot,
    slot_cid,
    fixed_request_cid: state.fixed_request_cid,
    key,
    inputs,
  })
}

///|
fn provider_error(value : ModelProviderFailure) -> ModelExecutionIssue {
  Provider(value)
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
  if quantum < 1 {
    return @bounded.Failed(InvalidLimits, 0, 0)
  }
  let request = match make_request(state) {
    Ok(value) => value
    Err(issue) => return @bounded.Failed(issue, 1, 1)
  }
  let reservation = state.reservations[state.next_slot]
  let response = match (state.provider.invoke)(request) {
    Ok(value) => value
    Err(issue) => return @bounded.Failed(provider_error(issue), 1, 1)
  }
  guard key_cid(request.key) is Some(input_key_cid) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  if response.provider_model.is_empty() ||
    response.provider_request_id.is_empty() ||
    response.observed_at.is_empty() ||
    response.input_tokens < 0L ||
    response.output_tokens < 0L {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  let checked = match
    @admitted.recheck_runtime_value(
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
  state.captures.push({
    slot: request.slot,
    slot_cid: request.slot_cid,
    input_key_cid,
    fixed_request_cid: request.fixed_request_cid,
    provider_id: state.provider.provider_id,
    provider_request_id: response.provider_request_id,
    value: checked,
    input_tokens: response.input_tokens,
    output_tokens: response.output_tokens,
    observed_at: response.observed_at,
  })
  state.next_slot += 1
  if state.next_slot == @relation.prepared_infer_rows_count(state.rows) {
    @bounded.Complete(
      {
        task_cid: @environment.model_task_identity(state.task).2,
        fixed_request_cid: state.fixed_request_cid,
        captures: state.captures.copy(),
      },
      1,
      1,
    )
  } else {
    @bounded.Continue(1, 1)
  }
}

///|
pub fn start_model_execution(
  rows : @relation.PreparedInferRows,
  provider : ModelProvider,
  fixed_request_cid : String,
  limits : ModelExecutionLimits,
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
  let count = @relation.prepared_infer_rows_count(rows)
  let task = @infer.model_task(@relation.prepared_infer_rows_owner(rows))
  if provider.provider_id != @environment.model_task_connector(task) {
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
  for _ in 0..<count {
    match
      @resources.reserve_attempt(
        ledger,
        limits.max_request_bytes + limits.max_response_bytes,
        limits.max_response_bytes,
        0L,
      ) {
      Ok(value) => reservations.push(value)
      Err(issue) => {
        for prior in reservations {
          @resources.settle_reservation(ledger, prior) |> ignore
        }
        @relation.release_prepared_infer_rows_use(input_use) |> ignore
        return Err(Ledger(issue))
      }
    }
  }
  let state : ModelState = {
    rows,
    input_use,
    task,
    provider,
    fixed_request_cid,
    limits,
    ledger,
    reservations,
    captures: [],
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
      for reservation in execution.state.reservations {
        if @resources.reservation_open(reservation) {
          @resources.settle_reservation(execution.state.ledger, reservation)
          |> ignore
        }
      }
      @relation.release_prepared_infer_rows_use(execution.state.input_use)
      |> ignore
      execution.state.captures.clear()
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
      @encode.key(writer, "provider_id")
      @encode.string_value(writer, capture.provider_id)
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
