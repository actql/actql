///|
/// Physical observations of ONE issued optional-usage action. These describe
/// that callback/child, not Model completion, send permission or a close ACK.
pub(all) enum ModelUsageObservation {
  CopyRetained
  CopyRefused
  Authorized
  Denied
  Unavailable
  CaptureComplete
  CaptureIncomplete
  Recorded
  CallbackFailed
  CleanupPending
  CleanupComplete
}

///|
enum ModelUsagePhase {
  Retain
  Select
  Authorize
  Capture
  Record
  Retire
  Done
} derive(Eq)

///|
pub(all) enum ModelUsageCompletion {
  Complete
  RequiredUnavailable
  ReadDenied
  SinkFailure
  BudgetExceeded
} derive(Eq, Debug)

///|
/// A continuation of the existing publication borrow, not another Owner or
/// reservation. Only this capacity may retain it; all escaped action tokens
/// lose their back-reference on consumption.
pub struct ModelUsagePublication {
  mut capacity : OriginalModelPublicationCapacity?
  mut capture : VerifiedModelCapture?
  retained_prefix : Int64
  execution_prefix : Int64
  max_bytes : Int
  count : Int
  mut slot : Int
  mut copied_bytes : Int
  mut phase : ModelUsagePhase
  mut active : ModelUsageAction?
  mut completion : ModelUsageCompletion
  mut stopped : Bool
  mut advancing : Bool
  mut attempt : String?
  items : Array[(Int, ModelUsageCompletion, String?)]
}

///|
/// Only the next action may be observed. A same-shaped foreign token, stale
/// action or reentrant advance cannot settle this original child.
pub struct ModelUsageAction {
  mut publication : ModelUsagePublication?
  phase : ModelUsagePhase
  slot : Int
  mut wire : String?
  mut bound : Bool
}

///|
fn model_usage_publication_current(value : ModelUsagePublication) -> Bool {
  guard value.capacity is Some(capacity) &&
    capacity.usage is Some(original) &&
    physical_equal(value, original) &&
    value.capture is Some(capture) &&
    capture.owner.state.call_scope is Some(scope) else {
    return false
  }
  original_model_publication_capacity_matches_parent(
    capacity,
    capture.owner,
    scope,
  ) &&
  original_model_publication_capacity_covers(capacity, 0L, 0L)
}

///|
fn model_usage_action_matches(action : ModelUsageAction) -> Bool {
  guard action.publication is Some(value) &&
    value.capacity is Some(capacity) &&
    capacity.usage is Some(original) &&
    physical_equal(value, original) &&
    value.active is Some(active) &&
    physical_equal(action, active) else {
    return false
  }
  action.phase == value.phase && action.slot == value.slot
}

///|
pub fn original_model_usage_action_belongs_to(
  value : ModelUsagePublication,
  action : ModelUsageAction,
) -> Bool {
  model_usage_action_matches(action) &&
  action.publication is Some(original) &&
  physical_equal(value, original)
}

///|
pub fn original_model_usage_finished(value : ModelUsagePublication) -> Bool {
  value.phase == Done
}

///|
fn model_usage_set_incomplete(
  value : ModelUsagePublication,
  completion : ModelUsageCompletion,
) -> Unit {
  if value.completion == Complete {
    value.completion = completion
  }
}

///|
/// Fund the original fixed window before constructing this continuation or
/// any Host copy child. The publication's initial None field was funded by
/// reserve, not retroactively by this grow.
pub fn begin_original_model_usage_publication(
  execution : ModelExecution,
  capacity : OriginalModelPublicationCapacity,
  capture : VerifiedModelCapture,
  retained_prefix : Int64,
  execution_prefix : Int64,
  max_bytes : Int,
) -> Result[ModelUsagePublication, ModelExecutionIssue] {
  if capacity.usage is Some(_) || max_bytes < 1 || max_bytes > 1048576 {
    return Err(InvalidLimits)
  }
  match
    prepare_original_model_capture_usage(
      execution, capacity, capture, retained_prefix, execution_prefix,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let value : ModelUsagePublication = {
    capacity: Some(capacity),
    capture: Some(capture),
    retained_prefix,
    execution_prefix,
    max_bytes,
    count: verified_model_capture_call_count(capture).unwrap(),
    slot: 0,
    copied_bytes: 0,
    phase: Retain,
    active: None,
    completion: Complete,
    stopped: false,
    advancing: false,
    attempt: None,
    items: [],
  }
  capacity.usage = Some(value)
  Ok(value)
}

///|
/// Select portable order and completion in Common. The binding only executes
/// the issued physical callback. No outstanding action may be advanced twice.
pub fn next_original_model_usage_action(
  value : ModelUsagePublication,
) -> Result[ModelUsageAction?, ModelExecutionIssue] {
  if value.phase == Done {
    return Ok(None)
  }
  if value.advancing || value.active is Some(_) || value.capacity is None {
    return Err(OutputIdentity)
  }
  value.advancing = true
  defer {
    value.advancing = false
  }
  if value.phase != Retire &&
    (value.stopped || !model_usage_publication_current(value)) {
    value.stopped = true
    model_usage_set_incomplete(value, RequiredUnavailable)
    value.phase = Retire
  }
  if value.phase == Select {
    value.attempt = None
    let capture = value.capture.unwrap()
    while value.slot < value.count {
      if model_usage_projection_current(
          capture.owner,
          value.capacity.unwrap(),
          capture,
          value.slot,
        ) {
        break
      }
      value.items.push((value.slot, RequiredUnavailable, None))
      model_usage_set_incomplete(value, RequiredUnavailable)
      value.slot += 1
    }
    value.phase = if value.slot == value.count { Record } else { Authorize }
  }
  let mut wire = None
  if value.phase == Capture {
    let capture = value.capture.unwrap()
    let remaining = value.max_bytes - value.copied_bytes
    let projected = if remaining < 1 {
      Err(ModelExecutionIssue::InvalidLimits)
    } else {
      project_original_model_capture_usage(
        capture.owner,
        value.capacity.unwrap(),
        capture,
        value.slot,
        value.retained_prefix,
        value.execution_prefix,
        remaining,
      )
    }
    match projected {
      Err(_) => {
        model_usage_set_incomplete(
          value,
          if remaining < 1 {
            BudgetExceeded
          } else {
            RequiredUnavailable
          },
        )
        value.phase = Record
      }
      Ok((output, _, _)) => {
        // This exact seven-field writer contains only ASCII keys, original
        // sha256 CIDs, decimal Int64/null and the two fixed origin words. Its
        // UTF-16 length is therefore its byte extent; do not copy the wire to
        // another UTF-8 buffer just to count it.
        let bytes = output.length()
        if bytes > remaining {
          model_usage_set_incomplete(value, BudgetExceeded)
          value.phase = Record
        } else {
          value.copied_bytes += bytes
          wire = Some(output)
        }
      }
    }
  }
  if value.phase != Retire &&
    (value.stopped || !model_usage_publication_current(value)) {
    value.stopped = true
    model_usage_set_incomplete(value, RequiredUnavailable)
    value.phase = Retire
    wire = None
  }
  if value.phase == Retire {
    wire = None
  }
  let action : ModelUsageAction = {
    publication: Some(value),
    phase: value.phase,
    slot: value.slot,
    wire,
    bound: false,
  }
  value.active = Some(action)
  Ok(Some(action))
}

///|
/// Match the original continuation's borrowed entry against the capture's
/// actual call/attempt. These strings cannot issue an attempt or permission.
pub fn original_model_usage_binding_matches(
  action : ModelUsageAction,
  slot_cid : String,
  attempt_cid : String,
) -> Bool {
  action.bound = false
  guard model_usage_action_matches(action) &&
    action.phase == Authorize &&
    action.publication is Some(value) &&
    !value.advancing &&
    value.capture is Some(capture) else {
    return false
  }
  value.advancing = true
  defer {
    value.advancing = false
  }
  guard model_usage_publication_current(value) &&
    !value.stopped &&
    verified_model_capture_call_at(capture, action.slot) is Some(call) &&
    @publication.run_evidence_value_identity(call) == slot_cid else {
    return false
  }
  let original_attempt = if capture.owner.state.restored_calls.get(action.slot)
    is Some(saved) {
    Some(@publication.run_evidence_value_identity(saved.proof.attempt))
  } else {
    capture.owner.state.attempts
    .get(action.slot)
    .map(trace => @publication.run_evidence_value_identity(trace.attempt))
  }
  let matches = original_attempt == Some(attempt_cid)
  if matches {
    action.bound = true
    value.attempt = original_attempt
  }
  matches
}

///|
pub fn observe_original_model_usage_action(
  action : ModelUsageAction,
  observation : ModelUsageObservation,
) -> Result[Unit, ModelExecutionIssue] {
  if !model_usage_action_matches(action) ||
    action.publication.unwrap().advancing {
    return Err(OutputIdentity)
  }
  let value = action.publication.unwrap()
  let next = match (action.phase, observation) {
    (Retain, CopyRetained) => Select
    (Retain, CopyRefused) => {
      model_usage_set_incomplete(value, RequiredUnavailable)
      Retire
    }
    (Authorize, Authorized) => {
      if !action.bound {
        return Err(OutputIdentity)
      }
      Capture
    }
    (Authorize, Denied) => {
      if !action.bound {
        return Err(OutputIdentity)
      }
      value.items.push((value.slot, ReadDenied, None))
      model_usage_set_incomplete(value, ReadDenied)
      value.slot += 1
      Select
    }
    (Authorize, Unavailable) => {
      value.items.push((value.slot, RequiredUnavailable, None))
      model_usage_set_incomplete(value, RequiredUnavailable)
      value.slot += 1
      Select
    }
    (Capture, CaptureComplete) => {
      value.items.push((value.slot, Complete, value.attempt))
      value.slot += 1
      Select
    }
    (Capture, CaptureIncomplete) => {
      value.items.push((value.slot, SinkFailure, value.attempt))
      model_usage_set_incomplete(value, SinkFailure)
      value.slot += 1
      Select
    }
    (Record, Recorded) => Retire
    (Authorize | Capture | Record, CallbackFailed) => {
      model_usage_set_incomplete(value, RequiredUnavailable)
      if action.phase == Record {
        Retire
      } else {
        Record
      }
    }
    (Retire, CleanupPending) => return Ok(())
    (Retire, CleanupComplete) => Done
    _ => return Err(OutputIdentity)
  }
  action.publication = None
  action.wire = None
  value.active = None
  value.phase = if value.stopped && next != Done { Retire } else { next }
  if next == Done {
    let capacity = value.capacity.unwrap()
    // Release-only: returning this child never requires the retired input to
    // become live again. The original publication's own release fences remain.
    capacity.usage = None
    value.capacity = None
    value.capture = None
    value.attempt = None
    value.items.clear()
  }
  Ok(())
}

///|
/// A stop request selects no further callbacks and cannot clear an outstanding
/// one. Its SAME action must report actual settlement before retirement.
pub fn stop_original_model_usage_publication(
  value : ModelUsagePublication,
) -> Unit {
  if value.phase == Done {
    return
  }
  value.stopped = true
  model_usage_set_incomplete(value, RequiredUnavailable)
  if value.active is None {
    value.phase = Retire
  }
}

///|
pub fn original_model_usage_action_kind(action : ModelUsageAction) -> String? {
  if !model_usage_action_matches(action) {
    return None
  }
  Some(
    match action.phase {
      Retain => "retain"
      Authorize => "authorize"
      Capture => "capture"
      Record => "record"
      Retire => "retire"
      _ => return None
    },
  )
}

///|
pub fn original_model_usage_action_slot(action : ModelUsageAction) -> Int? {
  if model_usage_action_matches(action) {
    Some(action.slot)
  } else {
    None
  }
}

///|
pub fn original_model_usage_action_wire(action : ModelUsageAction) -> String? {
  if model_usage_action_matches(action) {
    action.wire
  } else {
    None
  }
}

///|
pub fn original_model_usage_completion(
  value : ModelUsagePublication,
) -> ModelUsageCompletion {
  value.completion
}

///|
pub fn original_model_usage_item_count(value : ModelUsagePublication) -> Int {
  value.items.length()
}

///|
pub fn original_model_usage_item(
  value : ModelUsagePublication,
  index : Int,
) -> (Int, ModelUsageCompletion)? {
  value.items.get(index).map(item => (item.0, item.1))
}

///|
pub fn original_model_usage_item_attempt(
  value : ModelUsagePublication,
  index : Int,
) -> String? {
  match value.items.get(index) {
    Some(item) => item.2
    None => None
  }
}
