///|
// These are records of the SAME Model owner, not another session, Ledger or
// scheduler. The fixed four-entry array, per-attempt frames, outcome map and
// final ordered projection overlap require the original managed envelope.
priv struct ModelSlotFrame {
  slot : Int
  progress : ModelSlotProgress
}

///|
priv struct ModelSlotWindow {
  frames : Array[ModelSlotFrame?]
  outcomes : Map[Int, AdoptedModelSlot]
  adopted_slots : Array[Int]
  mut next_slot : Int
  mut scan : Int
}

///|
// Preserve the original outcome -> success-record indirection. Physical
// arrival order must not turn a success-array index into a logical Slot ID.
fn model_outcome_at(state : ModelState, slot : Int) -> AdoptedModelSlot? {
  match state.slot_window {
    Some(window) => window.outcomes.get(slot)
    None => state.outcomes.get(slot)
  }
}

///|
fn model_outcome_count(state : ModelState) -> Int {
  match state.slot_window {
    Some(window) => window.outcomes.length()
    None => state.outcomes.length()
  }
}

///|
fn model_physical_call_at(state : ModelState, slot : Int) -> ModelPhysicalCall? {
  match state.slot_window {
    Some(window) => {
      for frame in window.frames {
        if frame is Some(frame) && frame.slot == slot {
          return frame.progress.call
        }
      }
      None
    }
    None =>
      match state.progress.call {
        Some(call) =>
          if call.entry is Some(entry) && entry.slot == slot {
            Some(call)
          } else {
            None
          }
        None => None
      }
  }
}

///|
fn adopt_model_outcome(state : ModelState, outcome : AdoptedModelSlot) -> Unit {
  match state.slot_window {
    Some(window) =>
      if !window.outcomes.contains(state.progress.slot) {
        window.adopted_slots.push(state.progress.slot)
        window.outcomes[state.progress.slot] = outcome
      }
    None => state.outcomes.push(outcome)
  }
}

///|
// Final logical projection is one bounded Model transition per Slot. There
// are no fabricated Unknown placeholders for Slots that have not responded.
fn order_model_window_outcomes(
  state : ModelState,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue]? {
  guard state.slot_window is Some(window) else { return None }
  let count = @relation.prepared_infer_rows_count(state.rows)
  if window.outcomes.length() != count ||
    window.frames.any(frame => frame is Some(_)) {
    return Some(@bounded.Continue(1, 1))
  }
  if state.outcomes.length() < count {
    guard window.outcomes.get(state.outcomes.length()) is Some(outcome) else {
      return Some(@bounded.Failed(OutputIdentity, 1, 1))
    }
    state.outcomes.push(outcome)
    return Some(@bounded.Continue(1, 1))
  }
  None
}

///|
// Select at most four original frames fairly. IO observation/cleanup has the
// existing physical-poll semantics; actual CPU work still advances only the
// one original bounded session below. Pending alone invents no work.
fn select_model_window_progress(
  state : ModelState,
) -> Result[Bool, ModelExecutionIssue] {
  guard state.slot_window is Some(window) &&
    state.prepared_call_set is Some(prepared) &&
    prepared.io_access is Some(access) else {
    return Ok(true)
  }
  let count = state.requests.length()
  let first = window.scan
  for offset in 0..<4 {
    let index = (first + offset) % 4
    match window.frames[index] {
      Some(frame) => {
        state.progress = frame.progress
        if frame.progress.call is Some(call) {
          if call.settlement_acknowledged {
            if !cleanup_model_physical_call(state) {
              continue
            }
          } else if frame.progress.phase is AwaitPhysicalResponse {
            if state.stop_requested {
              cancel_model_physical_call(call)
            }
            match poll_model_physical_call(call) {
              Err(issue) => call.poll_issue = Some(issue)
              Ok(Some(PhysicalPending) | None) => continue
              Ok(Some(_)) => ()
            }
          }
        }
        if window.outcomes.contains(frame.slot) &&
          frame.progress.call is None &&
          frame.progress.entry is None &&
          frame.progress.io_duty is None &&
          frame.progress.settlement is None {
          window.frames[index] = None
          continue
        }
        if frame.progress.phase is DispatchSlot &&
          frame.progress.settlement is None &&
          !state.stop_requested {
          match model_slot_io_available(state) {
            Err(issue) => return Err(issue)
            Ok(false) => continue
            Ok(true) => ()
          }
        }
        window.scan = (index + 1) % 4
        return Ok(true)
      }
      None => {
        if state.stop_requested || window.next_slot >= count {
          continue
        }
        let slot = window.next_slot
        guard state.reservations.get(slot) is Some(reservation) else {
          return Err(RequestIdentity)
        }
        match
          @resources.can_claim_model_io_access(
            access,
            state.ledger,
            reservation,
            slot,
            1,
          ) {
          Err(issue) => return Err(IoAdmission(issue))
          Ok(false) => continue
          Ok(true) => ()
        }
        // Readiness is not a claim. The existing bounded Dispatch step will
        // recheck and claim before creating an Entry or starting the transport.
        let progress : ModelSlotProgress = {
          phase: DispatchSlot,
          slot,
          entry: None,
          call: None,
          settlement: None,
          observing_response: false,
          io_duty: None,
        }
        window.frames[index] = Some({ slot, progress, })
        window.next_slot += 1
        window.scan = (index + 1) % 4
        state.progress = progress
        return Ok(true)
      }
    }
  }
  if window.next_slot == count &&
    window.outcomes.length() == count &&
    !window.frames.any(frame => frame is Some(_)) {
    state.progress.slot = count
    state.progress.phase = DispatchSlot
    return Ok(true)
  }
  Ok(false)
}

///|
fn cancel_model_slot_phase(progress : ModelSlotProgress) -> Unit {
  match progress.phase {
    CheckResponse(_, _, _, child) =>
      @admitted.cancel_recheck_runtime_value(child)
    CheckPhysicalMetadata(_, _, child, writer) => {
      @canonical.cancel_emit(child)
      @encode.cancel_writer(writer)
    }
    DecodePhysicalResponse(_, _, child) => cancel_model_response_decode(child)
    PrepareEvidence(child) => cancel_model_evidence(child)
    RestoreResponse(_, _, child) => @admitted.cancel_canonical_conversion(child)
    _ => ()
  }
}

///|
// The same stopped Model cleanup visits every retained original frame, even
// if one Unknown/failed cleanup must keep its duty. Never abandon its siblings.
fn cleanup_model_window_calls(state : ModelState) -> Bool {
  guard state.slot_window is Some(window) else {
    return cleanup_model_physical_call(state)
  }
  let mut complete = true
  for frame in window.frames {
    if frame is Some(frame) {
      state.progress = frame.progress
      if !cleanup_model_physical_call(state) {
        complete = false
      }
      if frame.progress.entry is Some(entry) {
        if entry.persistence is Some(operation) && operation.terminal is None {
          complete = false
        } else {
          retire_model_entering(state)
        }
      }
    }
  }
  complete
}

///|
fn cleanup_model_window_unentered(state : ModelState) -> Bool {
  guard state.slot_window is Some(window) else {
    return retire_model_slot_io_never_entered(state)
  }
  let mut complete = true
  for frame in window.frames {
    if frame is Some(frame) {
      state.progress = frame.progress
      if !retire_model_slot_io_never_entered(state) {
        complete = false
      }
    }
  }
  complete
}
