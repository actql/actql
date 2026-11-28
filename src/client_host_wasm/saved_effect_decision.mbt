///|
const SAVED_EFFECT_DECISION_KIND : Int = 18

///|
const SAVED_EFFECT_DECISION_FIELD_KIND : Int = 19

///|
const SAVED_EFFECT_DECISION_HEADER : Int = 226

///|
const SAVED_EFFECT_DECISION_FIELD_MAX : Int = 8192

///|
priv struct StoredSavedEffectDecision {
  parent : Int
  capacity : @resources.CapacityReservation
  original : @host.ClientEffectResolutionJournalDecision
  mut resume_attempted : Bool
}

///|
fn saved_effect_decision_parent(
  value : Instance,
  record : StoredSubmissionProjection,
  kind : Int,
) -> (Int, StoredSubmissionProjection, Bytes)? {
  guard record.borrow is Ok(borrow) &&
    @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(input) &&
    input.length() >= 4 else {
    return None
  }
  let parent = mock_effect_descriptor_field(input, 0)
  guard value.submissions.get(parent) is Some(original) &&
    original.kind == kind &&
    original.configuration == record.configuration &&
    original.produced &&
    !original.output_closed else {
    return None
  }
  Some((parent, original, input))
}

///|
fn require_saved_effect_signing_use(
  value : Instance,
  configuration : StoredRunConfiguration,
  child : StoredSubmissionProjection,
  use_entry : StoredSavedEffectAttestationUse,
  observed_run? : @host.ClientJournalPhysicalRow? = None,
) -> Result[Unit, Int] {
  guard value.submissions.get(use_entry.parent) is Some(parent) &&
    parent.produced &&
    !parent.output_closed &&
    parent.append_plan is EffectProof(proof) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    use_entry.original.originals() is Ok((grant_cid, grant, _, use_wire, _)) else {
    return Err(-32)
  }
  let check = () => submission_lookup_current(value, child, configuration)
  let read = (table, key, extent) => {
    if observed_run is Some(actual) &&
      table == "client_runs" &&
      actual.key == key &&
      actual.body.length() == extent {
      check().map(_ => Some(actual))
    } else {
      physical_journal_row(
        current.physical,
        check,
        1,
        table,
        key,
        expected_body_length=Some(extent),
      )
    }
  }
  match proof.challenge.require_waiting(read, -32, observed_run~) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  for
    (table, key, wire) in [
      ("client_local_grant_originals", grant_cid, grant),
      (
        "client_local_signing_use_originals",
        use_entry.original.checkpoint_cid(),
        use_wire,
      ),
    ] {
    let body = @utf8.encode(wire)
    match read(table, key, body.length()) {
      Ok(Some(row)) if row.key == key && row.revision == 0L && row.body == body =>
        ()
      Ok(_) => return Err(-32)
      Err(code) => return Err(code)
    }
  }
  check()
}

///|
fn produce_saved_effect_decision(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  guard saved_effect_decision_parent(
      value,
      record,
      SAVED_EFFECT_ATTESTATION_USE_KIND,
    )
    is Some((parent, retained, input)) &&
    input.length() == 92 &&
    retained.append_plan is EffectAttestationUse(use_entry) &&
    !use_entry.decision_attempted else {
    return -32
  }
  use_entry.decision_attempted = true
  let fixed = 524288L
  let capacity = match @resources.reserve_capacity(value.root, 0L, fixed) {
    Ok(value) => value
    Err(_) => return -4
  }
  record.append_plan = Decoding(capacity, Idle)
  match
    require_saved_effect_signing_use(value, configuration, retained, use_entry) {
    Err(code) => return code
    Ok(_) => ()
  }
  let signature = @utf8.decode(input[4:]) catch { _ => return -31 }
  let peak = Ref(fixed)
  let held = Ref(0L)
  let refused = Ref(false)
  let fund = (extra : Int64) => {
    guard @execution.checked_preparation_add_product(fixed, extra, 1L)
      is Some(total) else {
      refused.val = true
      return false
    }
    if total <= peak.val {
      return true
    }
    if @resources.grow_capacity_reservation(value.root, capacity, 0L, total)
      is Err(_) {
      refused.val = true
      return false
    }
    peak.val = total
    true
  }
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 262144,
    max_nodes: 16384,
    max_depth: 64,
  }
  let decision = match
    use_entry.original.prepare_decision(
      signature,
      () => submission_lookup_current(value, retained, configuration) is Ok(_),
      limits,
      stage => {
        guard @host.client_run_journal_decode_construction(stage)
          is Some((r, e)) &&
          fund(r + e) else {
          return Err(@host.ClientJournalDecodingIssue::CustodyLost)
        }
        held.val = r
        Ok(())
      },
      (size, nodes, _) => {
        guard @host.client_protocol_metadata_construction_bytes(
            size,
            nodes.to_int64(),
            copies=1,
          )
          is Some((scratch, _)) &&
          fund(held.val + scratch) else {
          return Err(@host.ClientJournalEncodingIssue::CapacityExceeded)
        }
        Ok(())
      },
    ) {
    Ok(value) => value
    Err(_) => return if refused.val { -4 } else { -31 }
  }
  let (before, body) = decision.rows()
  let (checkpoint, resolution, approved) = decision.candidate_coordinates()
  guard before.revision == 3L &&
    saved_effect_journal_header(before, body, checkpoint, resolution, approved)
    is Some(header) else {
    return -31
  }
  let accepted = status(
    @buffers.supply_buffer_output(value.pool, record.slot, header),
  )
  if accepted == 0 {
    record.append_plan = EffectDecision({
      parent,
      capacity,
      original: decision,
      resume_attempted: false,
    })
    record.produced = true
  }
  accepted
}

///|
fn saved_effect_journal_header(
  before : @host.ClientJournalPhysicalRow,
  body : Bytes,
  checkpoint : String,
  resolution : String,
  approved : Bool,
) -> Bytes? {
  let stored_key = @utf8.encode(before.key)
  let checkpoint = @utf8.encode(checkpoint)
  let resolution = @utf8.encode(resolution)
  guard body.length() > 0 &&
    body.length() <= 262144 &&
    stored_key.length() == 71 &&
    checkpoint.length() == 71 &&
    resolution.length() == 71 else {
    return None
  }
  Some(
    Bytes::makei(13, index => {
      if index < 8 {
        (before.revision >> (index * 8)).to_int().to_byte()
      } else if index < 12 {
        (body.length() >> ((index - 8) * 8)).to_byte()
      } else if approved {
        b'\x01'
      } else {
        b'\x00'
      }
    }) +
    stored_key +
    checkpoint +
    resolution,
  )
}

///|
fn validate_saved_effect_decision(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard record.append_plan is EffectDecision(decision) &&
    value.submissions.get(decision.parent) is Some(use_holder) &&
    use_holder.produced &&
    !use_holder.output_closed &&
    use_holder.append_plan is EffectAttestationUse(use_entry) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return -32
  }
  let (before, successor) = decision.original.rows()
  let check = () => submission_lookup_current(value, record, configuration)
  let actual = match
    physical_journal_row(
      current.physical,
      check,
      1,
      "client_runs",
      before.key,
      expected_successor_lengths=Some(
        (before.revision, before.body.length(), successor.length()),
      ),
    ) {
    Err(code) => return code
    Ok(Some(row)) => row
    _ => return -32
  }
  guard actual.body.length() <=
    Int::max(before.body.length(), successor.length()) &&
    actual.key == before.key &&
    (
      (actual.revision == before.revision && actual.body == before.body) ||
      decision.original.confirmed(actual)
    ) else {
    return -32
  }
  match
    require_saved_effect_signing_use(
      value,
      configuration,
      use_holder,
      use_entry,
      observed_run=Some(actual),
    ) {
    Ok(_) => 0
    Err(code) => code
  }
}

///|
fn saved_effect_decision_field(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bytes, Int] {
  let requested = saved_effect_decision_parent(
    value,
    record,
    SAVED_EFFECT_DECISION_KIND,
  )
  let selection = match requested {
    Some((id, parent, input)) if parent.append_plan is EffectDecision(decision) =>
      Some(
        (
          id,
          input,
          decision.original.rows().1,
          validate_saved_effect_decision(value, parent, configuration),
        ),
      )
    _ =>
      match
        saved_effect_decision_parent(value, record, SAVED_EFFECT_RESUME_KIND) {
        Some((id, parent, input)) if parent.append_plan
          is EffectResumeClaim(claim) =>
          Some(
            (
              id,
              input,
              claim.original.rows().1,
              validate_saved_effect_resume_claim(value, parent, configuration),
            ),
          )
        _ => None
      }
  }
  guard selection is Some((_, input, body, code)) && input.length() == 12 else {
    return Err(-32)
  }
  if code != 0 {
    return Err(code)
  }
  let offset = mock_effect_descriptor_field(input, 4)
  let count = mock_effect_descriptor_field(input, 8)
  guard offset >= 0 &&
    count > 0 &&
    count <= SAVED_EFFECT_DECISION_FIELD_MAX &&
    offset <= body.length() - count else {
    return Err(-31)
  }
  Ok(body[offset:offset + count].to_owned())
}

///|
fn produce_saved_effect_decision_field(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  let body = match saved_effect_decision_field(value, record, configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, body),
  )
  if code == 0 {
    guard record.borrow is Ok(borrow) &&
      @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(packet) else {
      return -32
    }
    record.append_plan = EffectDecisionField(
      mock_effect_descriptor_field(packet, 0),
    )
    record.produced = true
  }
  code
}

///|
fn validate_saved_effect_decision_field(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  match saved_effect_decision_field(value, record, configuration) {
    Ok(bytes) if @buffers.buffer_wire(value.pool, record.slot) == Some(bytes) =>
      0
    Ok(_) => -32
    Err(code) => code
  }
}
