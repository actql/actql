///|
const SAVED_EFFECT_FILE_COMPLETION_KIND : Int = 29

///|
const SAVED_EFFECT_FILE_COMPLETION_HEADER : Int = 75

///|
priv struct StoredSavedEffectFileCompletion {
  parent : Int
  capacity : @resources.CapacityReservation
  original : @host.ClientEffectSavedFileCompletion
}

///|
fn produce_saved_effect_file_completion(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  guard saved_effect_decision_parent(value, record, SAVED_EFFECT_FILE_TERMINAL_KIND)
    is Some((parent, holder, input)) &&
    input.length() == 4 &&
    holder.append_plan is EffectFileTerminal(terminal) &&
    !terminal.successor_attempted &&
    value.submissions.get(terminal.dispatch) is Some(dispatch_holder) &&
    dispatch_holder.append_plan is EffectFileDispatch(dispatch) &&
    value.submissions.get(dispatch.application) is Some(app_holder) &&
    app_holder.append_plan is EffectApplication(application) &&
    dispatch.index + 1 == application.files.length() &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return -32
  }
  terminal.successor_attempted = true
  match observe_saved_effect_file_terminal(value, holder, configuration) {
    Ok(true) => ()
    Ok(false) => return -32
    Err(code) => return code
  }
  let check = () => submission_lookup_current(value, holder, configuration)
  match require_saved_effect_file_prefix(value, parent, current.physical, check) {
    Ok(_) => ()
    Err(code) => return code
  }
  let initial = 524288L
  let capacity = match @resources.reserve_capacity(value.root, 0L, initial) {
    Ok(value) => value
    Err(_) => return -52601
  }
  record.append_plan = Decoding(capacity, Idle)
  let originals = Array(capacity=application.files.length())
  let mut selected = Some(parent)
  while selected is Some(handle) {
    guard value.submissions.get(handle) is Some(held) &&
      held.append_plan is EffectFileTerminal(current_terminal) &&
      value.submissions.get(current_terminal.dispatch) is Some(current_holder) &&
      current_holder.append_plan is EffectFileDispatch(current_dispatch) &&
      current_dispatch.application == dispatch.application &&
      current_dispatch.index == application.files.length() - 1 - originals.length() else {
      return -32
    }
    originals.push(current_terminal.original)
    selected = if current_dispatch.index == 0 { None } else { Some(current_dispatch.parent) }
  }
  originals.rev_in_place()
  let retained = Ref(initial)
  let peak = Ref(initial)
  let refused = Ref(false)
  let measured_issue = Ref(-52602)
  let fund_exact = (bytes : Int64) => {
    guard @execution.checked_preparation_add_product(retained.val, 1L, bytes) is Some(requested)
      else { refused.val = true; return false }
    if requested > peak.val {
      if @resources.grow_capacity_reservation(value.root, capacity, 0L, requested) is Err(_) {
        refused.val = true
        return false
      }
      peak.val = requested
    }
    true
  }
  let fund = (bytes : Int, nodes : Int, _) => {
    guard @host.client_protocol_metadata_construction_bytes(bytes, nodes.to_int64())
      is Some((scratch, backing)) &&
      fund_exact(scratch) &&
      @execution.checked_preparation_add_product(
        retained.val, 1L, backing + 4L * bytes.to_int64(),
      ) is Some(next) else {
      refused.val = true
      return false
    }
    retained.val = next
    true
  }
  let work_remaining = Ref(@host.client_standard_effect_computation_limits().effects.max_work)
  let work = (units : Int) => {
    if units < 0 || units > work_remaining.val { return false }
    work_remaining.val -= units
    true
  }
  let original = match application.original.complete_file_evidence(
    originals,
    { max_wire_bytes: SAVED_EFFECT_REVIEW_PRIVATE_MAX, max_nodes: 100000, max_depth: 64 },
    fund,
    bytes => {
      measured_issue.val = -52603
      fund_exact(bytes)
    },
    work,
  ) {
    Ok(value) => value
    Err(_) => return if refused.val { measured_issue.val } else { -31 }
  }
  let count = original.result_count()
  let receipt = original.final_receipt_cid()
  guard count > 0 && count <= value.workspace_slots && receipt.length() == 71 &&
    check() is Ok(_) else { return -32 }
  let header = Bytes::makei(4, index => (count >> (index * 8)).to_byte()) + @utf8.encode(receipt)
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, header))
  if code == 0 {
    record.append_plan = EffectFileCompletion({ parent, capacity, original })
    record.produced = true
  }
  code
}

///|
fn validate_saved_effect_file_completion(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard record.append_plan is EffectFileCompletion(completion) &&
    completion.original.result_count() > 0 &&
    value.submissions.get(completion.parent) is Some(holder) else {
    return -32
  }
  match observe_saved_effect_file_terminal(value, holder, configuration) {
    Ok(true) => 0
    Ok(false) => -32
    Err(code) => code
  }
}
