///|
const SAVED_EFFECT_RESUME_KIND : Int = 20

///|
priv struct StoredSavedEffectResumeClaim {
  parent : Int
  environment : Int
  capacity : @resources.CapacityReservation
  original : @host.ClientEffectResolutionResumeClaim
  mut application_attempted : Bool
}

///|
fn produce_saved_effect_resume_claim(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  guard saved_effect_decision_parent(value, record, SAVED_EFFECT_DECISION_KIND)
    is Some((parent, decision_holder, input)) &&
    input.length() == 103 &&
    decision_holder.append_plan is EffectDecision(decision) &&
    !decision.resume_attempted &&
    value.submissions.get(decision.parent) is Some(use_holder) &&
    use_holder.append_plan is EffectAttestationUse(use_entry) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    mock_project_request_configuration(value, mock_effect_descriptor_field(input, 4))
    is Some((selected_configuration, selected)) &&
    physical_equal(configuration, selected_configuration) &&
    selected.environment is Some((environment, _, _)) else {
    return -32
  }
  decision.resume_attempted = true
  let (checkpoint, resolution, approved) = decision.original.candidate_coordinates()
  if !approved { return -32 }
  let fixed = 524288L
  let capacity = match @resources.reserve_capacity(value.root, 0L, fixed) {
    Ok(value) => value
    Err(_) => return -4
  }
  record.append_plan = Decoding(capacity, Idle)
  let check = () => submission_lookup_current(value, decision_holder, configuration)
  let (prior, body) = decision.original.rows()
  let actual = match physical_journal_row(
    current.physical, check, 1, "client_runs", prior.key,
    expected_body_length=Some(body.length()),
  ) {
    Ok(Some(actual)) if decision.original.confirmed(actual) => actual
    Ok(_) => return -32
    Err(code) => return code
  }
  match require_saved_effect_signing_use(value, configuration, use_holder, use_entry,
      observed_run=Some(actual)) {
    Err(code) => return code
    Ok(_) => ()
  }
  let at = @utf8.decode(input[8:32]) catch { _ => return -31 }
  let claimant = @utf8.decode(input[32:]) catch { _ => return -31 }
  guard @values.timestamp_epoch_milliseconds(at) is Some(now) else { return -31 }
  let binding : @checkpoint.ResumeBinding = {
    authorization_context_cid: configuration.authority_scope_cid,
    environment_binding_cid: @checked.checking_environment_cid(environment),
  }
  let peak = Ref(fixed)
  let held = Ref(0L)
  let refused = Ref(false)
  let fund = (extra : Int64) => {
    guard @execution.checked_preparation_add_product(fixed, extra, 1L) is Some(total) else {
      refused.val = true
      return false
    }
    if total <= peak.val { return true }
    if @resources.grow_capacity_reservation(value.root, capacity, 0L, total) is Err(_) {
      refused.val = true
      return false
    }
    peak.val = total
    true
  }
  let claim = match decision.original.prepare_resume_claim(
    actual, claimant, now, 30000L, binding, () => check() is Ok(_),
    before_decode=Some(stage => {
      guard @host.client_run_journal_decode_construction(stage) is Some((r, e)) &&
        fund(r + e) else { return Err(@host.ClientJournalDecodingIssue::CustodyLost) }
      held.val = r
      Ok(())
    }),
    before_encode=Some((size, nodes, _) => {
      guard @host.client_protocol_metadata_construction_bytes(size, nodes.to_int64(), copies=1)
        is Some((scratch, _)) && fund(held.val + scratch) else {
        return Err(@host.ClientJournalEncodingIssue::CapacityExceeded)
      }
      Ok(())
    }),
  ) {
    Ok(value) => value
    Err(_) => return if refused.val { -4 } else { -31 }
  }
  let (before, body) = claim.rows()
  // A begun settlement-only lease must not proceed down the application arm.
  let authorized = claim.permits_application()
  guard saved_effect_journal_header(before, body, checkpoint, resolution, authorized) is Some(header) else {
    return -31
  }
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, header))
  if code == 0 {
    record.append_plan = EffectResumeClaim({
      parent, environment: mock_effect_descriptor_field(input, 4),
      capacity, original: claim, application_attempted: false,
    })
    record.produced = true
  }
  code
}

///|
fn validate_saved_effect_resume_claim(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard record.append_plan is EffectResumeClaim(claim) &&
    value.submissions.get(claim.parent) is Some(decision_holder) &&
    decision_holder.append_plan is EffectDecision(decision) &&
    value.submissions.get(decision.parent) is Some(use_holder) &&
    use_holder.append_plan is EffectAttestationUse(use_entry) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return -32
  }
  let check = () => submission_lookup_current(value, record, configuration)
  let (before, body) = claim.original.rows()
  let actual = match physical_journal_row(
    current.physical, check, 1, "client_runs", before.key,
    expected_successor_lengths=Some((before.revision, before.body.length(), body.length())),
  ) {
    Ok(Some(actual)) if actual.key == before.key &&
      ((actual.revision == before.revision && actual.body == before.body) ||
      (actual.revision == before.revision + 1L && actual.body == body)) => actual
    Ok(_) => return -32
    Err(code) => return code
  }
  match require_saved_effect_signing_use(value, configuration, use_holder, use_entry,
      observed_run=Some(actual)) {
    Err(code) => code
    Ok(_) => 0
  }
}
