///|
/// Physical preparation performs no provider I/O. Each start, advance and
/// cleanup callback must do one bounded unit of adapter work. The execution
/// owner charges transitions and observes cancellation between these units.
/// A cursor retains its buffers until cleanup succeeds, including on refusal.
pub(all) struct ModelRequestPreflight {
  advance : () -> Result[ModelPhysicalRequestPlan?, ModelExecutionIssue]
  cleanup : () -> Bool
}

///|
/// The installed adapter retains the exact prepared payload in invoke. It
/// must not rebuild a different request at dispatch. Tokenizer/media bounds
/// describe the complete attempt, including the possible output, not usage.
pub struct ModelPhysicalRequestPlan {
  request : ModelRequest
  wire_bytes : Int64
  quantities : @resources.QuantityAmounts
  invoke : () -> Result[ModelResponse, ModelProviderFailure]
}

///|
pub fn model_physical_request_plan(
  request : ModelRequest,
  wire_bytes : Int64,
  quantities : @resources.QuantityAmounts,
  invoke : () -> Result[ModelResponse, ModelProviderFailure],
) -> Result[ModelPhysicalRequestPlan, ModelExecutionIssue] {
  if wire_bytes < 0L ||
    wire_bytes > 9007199254740991L ||
    quantities.tokens < 0L ||
    quantities.tokens > 9007199254740991L ||
    quantities.cost_units < 0L ||
    quantities.cost_units > 9007199254740991L ||
    quantities.duration_ms < 0L ||
    quantities.duration_ms > 9007199254740991L {
    return Err(InvalidLimits)
  }
  if quantities.tokens <
    @environment.model_task_generation_config(request.task).max_output_tokens {
    return Err(InvalidLimits)
  }
  Ok({ request, wire_bytes, quantities, invoke, })
}

///|
pub type ModelPhysicalPreflight = (ModelRequest) -> Result[
  ModelRequestPreflight,
  ModelExecutionIssue,
]

///|
// The cursor, plan and retained array entries have a separate bookkeeping
// envelope. Payload buffers remain within the request/response reservation;
// an adapter must not allocate another unreserved copy during preparation.
let physical_preflight_metadata_bytes : Int64 = 256L

///|
fn cleanup_model_physical_preflight(state : ModelState) -> Bool {
  // The bounded session must keep its cleanup pending until all physical
  // cursors release successfully. Its cleanup result reports a transition,
  // not an idempotent success flag.
  if state.physical_cleanup_index < state.physical_cursors.length() {
    let index = state.physical_cleanup_index
    if !(state.physical_cursors[index].cleanup)() {
      return false
    }
    state.physical_cleanup_index += 1
  }
  state.physical_cleanup_index == state.physical_cursors.length()
}

///|
// Mapped requests and every reservation already exist. No slot may dispatch
// until every physical plan has passed this common envelope/binding check.
fn advance_model_physical_preflight(
  state : ModelState,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  guard state.physical_preflight is Some(start) else {
    return @bounded.Failed(InvalidProvider, 1, 1)
  }
  let index = state.physical_next_slot
  if index == state.requests.length() {
    state.phase = DispatchSlot
    return @bounded.Continue(1, 1)
  }
  if !model_slot_send_eligible(state, index) {
    state.physical_next_slot += 1
    return @bounded.Continue(1, 1)
  }
  let request = state.requests[index].request
  if state.physical_pending is None {
    match start(request) {
      Err(issue) => return @bounded.Failed(issue, 1, 1)
      Ok(cursor) => {
        state.physical_cursors.push(cursor)
        state.physical_pending = Some(cursor)
      }
    }
    return @bounded.Continue(1, 1)
  }
  match (state.physical_pending.unwrap().advance)() {
    Err(issue) => @bounded.Failed(issue, 1, 1)
    Ok(None) => @bounded.Continue(1, 1)
    Ok(Some(plan)) => {
      if !physical_equal(plan.request, request) {
        return @bounded.Failed(RequestIdentity, 1, 1)
      }
      if plan.wire_bytes > state.limits.max_request_bytes {
        return @bounded.Failed(RequestLimit, 1, 1)
      }
      guard state.quantity_capacity is Some(capacity) else {
        return @bounded.Failed(InvalidLimits, 1, 1)
      }
      if plan.quantities.tokens > capacity.per_attempt.tokens {
        return @bounded.Failed(Ledger(@resources.TokenLimit), 1, 1)
      }
      if plan.quantities.cost_units > capacity.per_attempt.cost_units {
        return @bounded.Failed(Ledger(@resources.CostLimit), 1, 1)
      }
      if plan.quantities.duration_ms > capacity.per_attempt.duration_ms {
        return @bounded.Failed(Ledger(@resources.DurationLimit), 1, 1)
      }
      state.physical_plans[index] = plan
      state.physical_pending = None
      state.physical_next_slot += 1
      @bounded.Continue(1, 1)
    }
  }
}

///|
fn model_slot_send_eligible(state : ModelState, slot : Int) -> Bool {
  match state.send_mask {
    None => true
    Some(mask) => mask.get(slot).unwrap_or(false)
  }
}

///|
/// Monotone physical-cursor cleanup progress, never a stop or release permit.
/// A Host may schedule another bounded cleanup step only while this advances.
pub fn model_cleanup_progress(execution : ModelExecution) -> Int {
  execution.state.physical_cleanup_index
}
