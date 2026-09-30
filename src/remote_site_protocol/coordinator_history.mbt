///|
/// Only typed observation projections enter this history: Site revision,
/// execution/evidence/cleanup, availability/quarantine, and the three actually
/// supplied (not accumulated) evidence identities. Reply/status transport kind
/// is deliberately not a sender-controlled replay or capacity partition.
/// 64 ordinary positions + at most seven strictly new closing facts; each
/// position has at most three existing typed evidence profiles.
fn coordinator_history_facts(entry : Array[String]) -> Array[Bool] {
  [
    entry[1] == "3" || entry[1] == "4" || entry[1] == "5",
    entry[2] == "2" || entry[2] == "3",
    entry[3] == "4" || entry[3] == "5",
    (entry[3] == "2" || entry[3] == "5") && entry[4] == "0" && entry[5] == "0",
    !entry[6].is_empty(),
    !entry[7].is_empty(),
    !entry[8].is_empty(),
  ]
}

///|
fn coordinator_history_closed(
  history : Array[Array[String]],
  evidence_kind : String,
) -> Bool {
  let mut reclaimed = false
  let mut settled = false
  let mut evidence_durable = false
  let mut evidence_rejected = false
  let mut evidence_pending = false
  let mut complete = false
  for entry in history {
    reclaimed = reclaimed || coordinator_history_facts(entry)[3]
    settled = settled || entry[1] == "3"
    evidence_pending = evidence_pending || entry[2] == "1"
    evidence_durable = evidence_durable || entry[2] == "2"
    evidence_rejected = evidence_rejected || entry[2] == "3"
    complete = complete ||
      (
        !entry[6].is_empty() &&
        !evidence_kind.is_empty() &&
        (
          evidence_kind != remote_managed_output_evidence_kind() ||
          !entry[8].is_empty()
        )
      )
  }
  reclaimed &&
  (
    (!settled && !evidence_pending && !evidence_durable && !evidence_rejected) ||
    evidence_rejected ||
    (evidence_durable && complete)
  )
}

///|
fn coordinator_prepare_history(
  history : Array[Array[String]],
  observed : Array[String],
  evidence_kind : String,
) -> Result[(Array[Array[String]], Bool), DispatchIssue] {
  let positions : Map[String, Bool] = Map([])
  let facts = Array::make(7, false)
  let mut known_position = false
  let mut last_revision = -1L
  for entry in history {
    if entry == observed {
      return Ok((history, true))
    }
    positions[entry[0]] = true
    let revision = @scalar.read_decimal_int64(entry[0]).unwrap()
    if revision > last_revision {
      last_revision = revision
    }
    if entry[0] == observed[0] {
      known_position = true
      for index in 1..<6 {
        if entry[index] != observed[index] {
          return Err(StateCollision)
        }
      }
    }
    // Historical terminal and evidence facts cannot be replaced through a
    // later revision, another response kind, or a different evidence profile.
    let old_facts = coordinator_history_facts(entry)
    let new_facts = coordinator_history_facts(observed)
    if old_facts[0] && new_facts[0] && entry[1] != observed[1] {
      return Err(StateCollision)
    }
    if entry[0] != observed[0] &&
      old_facts[0] &&
      !new_facts[0] &&
      !(observed[1] == "6" && (observed[3] == "4" || observed[3] == "5")) {
      return Err(StateCollision)
    }
    if old_facts[1] && new_facts[1] && entry[2] != observed[2] {
      return Err(StateCollision)
    }
    if entry[0] != observed[0] &&
      old_facts[1] &&
      !new_facts[1] &&
      @scalar.read_decimal_int64(observed[0]).unwrap() > revision {
      return Err(StateCollision)
    }
    for index in 6..<9 {
      if !entry[index].is_empty() &&
        !observed[index].is_empty() &&
        entry[index] != observed[index] {
        return Err(StateCollision)
      }
    }
    for index in 0..<7 {
      facts[index] = facts[index] || old_facts[index]
    }
  }
  // Once final evidence and physical reclaim are durable, no new position is
  // admitted. A previously seen position may still arrive with another of its
  // three bounded, non-conflicting typed profiles (including reverse arrival).
  if coordinator_history_closed(history, evidence_kind) && !known_position {
    return Err(ObservationAdmissionClosed)
  }
  if facts[3] && !known_position && !coordinator_history_facts(observed)[3] {
    return Err(StateCollision)
  }
  if facts[2] && !known_position && observed[3] != "4" && observed[3] != "5" {
    return Err(StateCollision)
  }
  let revision = @scalar.read_decimal_int64(observed[0]).unwrap()
  if !known_position && revision < last_revision {
    return Err(StateCollision)
  }
  if !known_position && positions.length() >= 64 {
    let new_facts = coordinator_history_facts(observed)
    let mut gain = false
    for index in 0..<7 {
      gain = gain || (new_facts[index] && !facts[index])
    }
    if !gain {
      return Err(ObservationHistoryCapacityExceeded)
    }
  }
  if history.length() >= 213 {
    return Err(ObservationHistoryCapacityExceeded)
  }
  Ok((history + [observed], false))
}

///|
fn emit_coordinator_history(
  history : Array[Array[String]],
) -> Result[String, DispatchIssue] {
  let writer = @encode.writer(131072, 4096, 3) catch {
    _ => return Err(InvalidJournal)
  }
  try {
    @encode.begin_array(writer)
    for entry in history {
      @encode.begin_array(writer)
      for value in entry {
        @encode.string_value(writer, value)
      }
      @encode.end_array(writer)
    }
    @encode.end_array(writer)
  } catch {
    _ => return Err(InvalidJournal)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidJournal) })
}

///|
pub fn coordinator_dispatch_record_history_json(
  record : CoordinatorDispatchIntentRecord,
) -> Result[String, DispatchIssue] {
  emit_coordinator_history(record.observation_history)
}

///|
pub fn coordinator_dispatch_transition_history_json(
  transition : CoordinatorDispatchTransition,
) -> Result[String, DispatchIssue] {
  emit_coordinator_history(transition.next_history)
}

///|
pub fn coordinator_dispatch_transition_expected_history_json(
  transition : CoordinatorDispatchTransition,
) -> Result[String, DispatchIssue] {
  emit_coordinator_history(transition.expected_history)
}

///|
pub fn coordinator_dispatch_transition_is_replay(
  transition : CoordinatorDispatchTransition,
) -> Bool {
  transition.replay
}

///|
/// Restore only explicitly recorded admissions. Final identities have already
/// been admitted by the durable record owner; absent historical profiles are
/// never invented from those accumulated identities.
pub fn restore_coordinator_dispatch_history_json(
  record : CoordinatorDispatchIntentRecord,
  body : String,
  evidence : RemoteExecutionEvidence?,
) -> Result[Unit, DispatchIssue] {
  let evidence_kind = match evidence {
    Some(value) => {
      if remote_execution_evidence_cid(value) != record.accepted_evidence_cid ||
        !remote_execution_evidence_matches_dispatch(value, record.request) {
        return Err(InvalidJournal)
      }
      value.evidence_kind
    }
    None => {
      if !record.accepted_evidence_cid.is_empty() {
        return Err(InvalidJournal)
      }
      ""
    }
  }
  try {
    let root = evidence_root(body, 131072, 4096, 3)
    let length = match @decode.array_length(root) {
      Some(value) if value <= 213 && value <= record.revision => value
      _ => raise EvidenceJsonStop
    }
    let mut history = []
    for index in 0..<length {
      let item = @decode.element_at(root, index).unwrap()
      if @decode.array_length(item) != Some(9) {
        raise EvidenceJsonStop
      }
      let entry = []
      for field in 0..<9 {
        entry.push(
          evidence_decoded(
            @decode.text(@decode.element_at(item, field).unwrap()),
          ),
        )
      }
      let codes = []
      for field in 0..<6 {
        match @scalar.read_decimal_int64(entry[field]) {
          Ok(value) if value >= 0L &&
            value <= 2147483647L &&
            value.to_string() == entry[field] => codes.push(value.to_int())
          _ => raise EvidenceJsonStop
        }
      }
      if codes[0] > record.site_revision ||
        codes[4] > 1 ||
        codes[5] > 1 ||
        !valid_site_observation(
          codes[1],
          codes[2],
          codes[3],
          codes[4] == 1,
          codes[5] == 1,
        ) {
        raise EvidenceJsonStop
      }
      if !((entry[6].is_empty() && entry[7].is_empty() && entry[8].is_empty()) ||
        (!entry[6].is_empty() && entry[7].is_empty() && entry[8].is_empty()) ||
        (!entry[6].is_empty() && !entry[7].is_empty() && !entry[8].is_empty())) {
        raise EvidenceJsonStop
      }
      let accepted = [
        record.accepted_evidence_cid,
        record.accepted_subject_cid,
        record.accepted_measurement_cid,
      ]
      for field in 6..<9 {
        if !entry[field].is_empty() &&
          (codes[2] != 2 || entry[field] != accepted[field - 6]) {
          raise EvidenceJsonStop
        }
      }
      let (next, replay) = match
        coordinator_prepare_history(history, entry, evidence_kind) {
        Ok(value) => value
        Err(_) => raise EvidenceJsonStop
      }
      if replay {
        raise EvidenceJsonStop
      }
      history = next
    }
    if record.site_revision == -1 && !history.is_empty() {
      raise EvidenceJsonStop
    }
    if record.site_revision >= 0 {
      let mut found = false
      for entry in history {
        if entry[0] == record.site_revision.to_string() &&
          entry[1] == record.site_execution.to_string() &&
          entry[2] == record.site_evidence.to_string() &&
          entry[3] == record.site_cleanup.to_string() &&
          entry[4] == bool_code(record.site_material_available) &&
          entry[5] == bool_code(record.site_quarantined_capacity) {
          found = true
        }
      }
      if !found {
        raise EvidenceJsonStop
      }
    }
    for field in 6..<9 {
      let accepted = [
        record.accepted_evidence_cid,
        record.accepted_subject_cid,
        record.accepted_measurement_cid,
      ]
      if !accepted[field - 6].is_empty() &&
        !history.any(fn(entry) { entry[field] == accepted[field - 6] }) {
        raise EvidenceJsonStop
      }
    }
    if emit_coordinator_history(history).unwrap() != body {
      raise EvidenceJsonStop
    }
    record.observation_history = history
    record.accepted_evidence_kind = evidence_kind
    Ok(())
  } catch {
    EvidenceJsonStop => Err(InvalidJournal)
  }
}
