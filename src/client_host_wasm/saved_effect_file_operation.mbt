///|
const SAVED_EFFECT_FILE_OPERATION_KIND : Int = 24

///|
const SAVED_EFFECT_FILE_REPLACEMENT_KIND : Int = 25

///|
const SAVED_EFFECT_FILE_OPERATION_MAX : Int = 65536

///|
priv struct StoredSavedEffectFileOperation {
  parent : Int
  at : String
  mut projection_attempted : Bool
}

///|
priv struct StoredSavedEffectFileReplacement {
  parent : Int
  capacity : @resources.CapacityReservation
  body : Bytes
  mut response_attempted : Bool
}

///|
fn saved_effect_file_operation_kind(kind : Int) -> Bool {
  kind == SAVED_EFFECT_FILE_OPERATION_KIND || kind == SAVED_EFFECT_FILE_REPLACEMENT_KIND
}

///|
fn require_saved_effect_file_operation(
  value : Instance,
  holder : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  at : String,
) -> Result[
  (StoredSavedEffectFileDispatch, StoredSavedEffectFileRow, @authorization.AccessTuple),
  Int,
] {
  guard holder.append_plan is EffectFileDispatch(dispatch) &&
    value.submissions.get(dispatch.application) is Some(app) &&
    app.append_plan is EffectApplication(application) &&
    value.submissions.get(application.parent) is Some(claim_holder) &&
    claim_holder.append_plan is EffectResumeClaim(claim) &&
    mock_project_request_configuration(value, claim.environment)
    is Some((selected_configuration, _)) &&
    physical_equal(configuration, selected_configuration) &&
    @values.timestamp_epoch_milliseconds(at) is Some(now) &&
    now >= 0L &&
    now < dispatch.original.operation_lease_ms() &&
    application.files.get(dispatch.index) is Some(file) else {
    return Err(-32)
  }
  match observe_saved_effect_file_dispatch(value, holder, configuration) {
    Err(code) => return Err(code)
    Ok(false) => return Err(-32)
    Ok(true) => ()
  }
  let tuple : @authorization.AccessTuple = {
    principal: configuration.tuple.principal,
    connection: file.selected.source.connection,
    resource: file.selected.write.mapping.resource,
    operation: "read",
  }
  guard @authorization.evaluate_account(configuration.account, tuple) is Allow(_) &&
    mock_project_write_visible(
      configuration.account, tuple.principal, file.selected.source, file.selected.write,
    ) &&
    file.row.matches_target(
      file.selected.binding_cid,
      file.selected.write.mapping.mapping_ref,
      file.selected.write.mapping.mapping_cid,
    ) else {
    return Err(-20)
  }
  Ok((dispatch, file, tuple))
}

///|
fn produce_saved_effect_file_operation(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  guard saved_effect_decision_parent(value, record, SAVED_EFFECT_FILE_DISPATCH_KIND)
    is Some((parent, holder, input)) &&
    input.length() == 28 &&
    holder.append_plan is EffectFileDispatch(dispatch) &&
    !dispatch.operation_attempted else {
    return -32
  }
  dispatch.operation_attempted = true
  let at = @utf8.decode(input[4:]) catch { _ => return -31 }
  match require_saved_effect_file_operation(value, holder, configuration, at) {
    Err(code) => return code
    Ok(_) => ()
  }
  guard dispatch.original.replacement_material() is Some((identity, version, _)) &&
    @scalar.admit_utf8_length(identity, SAVED_EFFECT_FILE_OPERATION_MAX - 150)
    is Ok(length) &&
    length > 0 && version.length() == 71 else {
    return -31
  }
  let lease = dispatch.original.operation_lease_ms()
  let body = Bytes::makei(8, index => (lease >> (index * 8)).to_byte()) +
    @utf8.encode(dispatch.original.dispatch_cid() + version + identity)
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, body))
  if code == 0 {
    record.append_plan = EffectFileOperation({ parent, at, projection_attempted: false })
    record.produced = true
  }
  code
}

///|
fn produce_saved_effect_file_replacement(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  guard saved_effect_decision_parent(value, record, SAVED_EFFECT_FILE_OPERATION_KIND)
    is Some((parent, holder, input)) &&
    input.length() > 4 &&
    input.length() <= 4 + @row_host.project_mock_row_page_limits().max_bytes &&
    holder.append_plan is EffectFileOperation(operation) &&
    !operation.projection_attempted &&
    value.submissions.get(operation.parent) is Some(dispatch_holder) else {
    return -32
  }
  operation.projection_attempted = true
  let (dispatch, file, _) = match
    require_saved_effect_file_operation(value, dispatch_holder, configuration, operation.at) {
    Ok(value) => value
    Err(code) => return code
  }
  // Paid once before the detached locked body is copied out of its input span.
  let baseline = 262144L + (input.length() - 4).to_int64()
  let capacity = match @resources.reserve_capacity(value.root, 0L, baseline) {
    Ok(value) => value
    Err(_) => return -4
  }
  record.append_plan = Decoding(capacity, Idle)
  let peak = Ref(baseline)
  let fund = (extra : Int64) => {
    guard @execution.checked_preparation_add_product(baseline, 1L, extra)
      is Some(requested) else { return false }
    if requested <= peak.val { return true }
    if @resources.grow_capacity_reservation(value.root, capacity, 0L, requested)
      is Err(_) { return false }
    peak.val = requested
    true
  }
  let replacement = match prepare_saved_effect_file_replacement(
    file.selected, dispatch.original, input[4:].to_owned(), fund,
  ) {
    Ok(value) => value
    Err(code) => return code
  }
  match require_saved_effect_file_operation(value, dispatch_holder, configuration, operation.at) {
    Err(code) => return code
    Ok(_) => ()
  }
  // Constructor/parser/locked-copy locals have returned. Only these exact
  // retained bytes and the original parent remain on this loan.
  guard @resources.retain_capacity_reservation_after_construction(
    value.root, capacity, replacement.length().to_int64() + 512L,
  ) is Ok(_) else { return -4 }
  let length = replacement.length()
  let header = Bytes::makei(4, index => (length >> (index * 8)).to_byte())
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, header))
  if code == 0 {
    record.append_plan = EffectFileReplacement({ parent, capacity, body: replacement, response_attempted: false, })
    record.produced = true
  }
  code
}

///|
fn validate_saved_effect_file_operation(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  let operation = match record.append_plan {
    EffectFileOperation(operation) => operation
    EffectFileReplacement(replacement) => {
      guard value.submissions.get(replacement.parent) is Some(holder) &&
        holder.append_plan is EffectFileOperation(operation) else { return -32 }
      operation
    }
    _ => return -32
  }
  guard value.submissions.get(operation.parent) is Some(dispatch) else { return -32 }
  match require_saved_effect_file_operation(value, dispatch, configuration, operation.at) {
    Err(code) => code
    Ok(_) => 0
  }
}
