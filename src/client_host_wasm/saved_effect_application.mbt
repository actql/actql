///|
const SAVED_EFFECT_APPLICATION_KIND : Int = 21

///|
priv struct StoredSavedEffectApplication {
  parent : Int
  capacity : @resources.CapacityReservation
  original : @host.ClientEffectSavedApplication
  files : Array[StoredSavedEffectFileRow]
  mut dispatch_attempted : Bool
}

///|
fn prepare_saved_effect_application(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  guard saved_effect_decision_parent(value, record, SAVED_EFFECT_RESUME_KIND)
    is Some((parent, resume_holder, input)) &&
    input.length() == 28 &&
    resume_holder.append_plan is EffectResumeClaim(claim) &&
    !claim.application_attempted &&
    value.submissions.get(claim.parent) is Some(decision_holder) &&
    decision_holder.append_plan is EffectDecision(decision) &&
    value.submissions.get(decision.parent) is Some(use_holder) &&
    use_holder.append_plan is EffectAttestationUse(use_entry) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return -32
  }
  claim.application_attempted = true
  let clock = @utf8.decode(input[4:]) catch { _ => return -31 }
  guard @values.timestamp_epoch_milliseconds(clock) is Some(now) else {
    return -31
  }
  let initial = 524288L
  let capacity = match @resources.reserve_capacity(value.root, 0L, initial) {
    Ok(value) => value
    Err(_) => return -4
  }
  record.append_plan = Decoding(capacity, Idle)
  let check = () => {
    submission_lookup_current(value, resume_holder, configuration)
  }
  let (before, body) = claim.original.rows()
  let actual = match
    physical_journal_row(
      current.physical,
      check,
      1,
      "client_runs",
      before.key,
      expected_body_length=Some(body.length()),
    ) {
    Ok(Some(actual)) if claim.original.confirmed(actual) is Some(_) => actual
    Ok(_) => return -32
    Err(code) => return code
  }
  match
    require_saved_effect_signing_use(
      value,
      configuration,
      use_holder,
      use_entry,
      observed_run=Some(actual),
    ) {
    Err(code) => return code
    Ok(_) => ()
  }
  let retained = Ref(initial)
  let peak = Ref(initial)
  let refused = Ref(false)
  let fund = (bytes : Int, nodes : Int, _) => {
    guard bytes >= 0 &&
      nodes >= 0 &&
      @host.client_protocol_metadata_construction_bytes(bytes, nodes.to_int64())
      is Some((scratch, controls)) &&
      @execution.checked_preparation_add_product(retained.val, scratch, 1L)
      is Some(requested) &&
      @execution.checked_preparation_add_product(
        retained.val,
        controls + 4L * bytes.to_int64(),
        1L,
      )
      is Some(kept) else {
      refused.val = true
      return false
    }
    if requested > peak.val {
      if @resources.grow_capacity_reservation(
          value.root,
          capacity,
          0L,
          requested,
        )
        is Err(_) {
        refused.val = true
        return false
      }
      peak.val = requested
    }
    retained.val = kept
    true
  }
  guard use_entry.original.application_recovery_work_bound(
      SAVED_EFFECT_REVIEW_PRIVATE_MAX,
    )
    is Some(maximum_work) else {
    return -31
  }
  let remaining_work = Ref(maximum_work)
  let work_refused = Ref(false)
  let work = (units : Int) => {
    let amount = units.to_int64()
    if amount < 0L || amount > remaining_work.val {
      work_refused.val = true
      return false
    }
    remaining_work.val -= amount
    true
  }
  let limits = @host.client_standard_effect_computation_limits().effects
  let application = match
    use_entry.original.restore_saved_application(
      claim.original,
      actual,
      now,
      {
        max_wire_bytes: SAVED_EFFECT_REVIEW_PRIVATE_MAX,
        max_nodes: limits.max_admission_nodes,
        max_depth: limits.max_admission_depth,
      },
      fund,
      work,
    ) {
    Ok(value) => value
    Err(_) =>
      return if refused.val { -4 } else if work_refused.val { -10 } else { -32 }
  }
  let files = match
    prepare_saved_effect_file_targets(
      value,
      configuration,
      claim.environment,
      application,
      clock,
      now,
      work,
      fund,
    ) {
    Ok(files) => files
    Err(_) if refused.val => return -4
    Err(code) => return code
  }
  let (members, rows) = application.ordered_count()
  let response = Bytes::makei(8, index => {
    if index < 4 {
      (members >> (index * 8)).to_byte()
    } else {
      (rows >> ((index - 4) * 8)).to_byte()
    }
  })
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, response),
  )
  if code == 0 {
    record.append_plan = EffectApplication({
      parent,
      capacity,
      original: application,
      files,
      dispatch_attempted: false,
    })
    record.produced = true
  }
  code
}

///|
fn validate_saved_effect_application(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard record.append_plan is EffectApplication(application) &&
    value.submissions.get(application.parent) is Some(claim) &&
    claim.append_plan is EffectResumeClaim(parent) &&
    mock_project_request_configuration(value, parent.environment)
    is Some((selected_configuration, _)) &&
    physical_equal(configuration, selected_configuration) &&
    application.original.ordered_count() is (members, rows) &&
    members > 0 &&
    application.files.length() == rows &&
    application.files.all(file => {
      file.row.matches_target(
        file.selected.binding_cid,
        file.selected.write.mapping.mapping_ref,
        file.selected.write.mapping.mapping_cid,
      )
    }) else {
    return -32
  }
  validate_saved_effect_resume_claim(value, claim, configuration)
}
