///|
const SAVED_EFFECT_FILE_TERMINAL_KIND : Int = 28

///|
const SAVED_EFFECT_FILE_TERMINAL_HEADER : Int = 320

///|
priv struct StoredSavedEffectFileTerminal {
  parent : Int
  dispatch : Int
  capacity : @resources.CapacityReservation
  original : @host.ClientEffectSavedFileTerminal
  mut successor_attempted : Bool
}

///|
fn produce_saved_effect_file_terminal(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  guard saved_effect_decision_parent(
      value,
      record,
      SAVED_EFFECT_FILE_RESPONSE_KIND,
    )
    is Some((parent, holder, input)) &&
    input.length() == 4 &&
    holder.append_plan is EffectFileResponse(response) &&
    !response.terminal_attempted else {
    return -32
  }
  response.terminal_attempted = true
  match observe_saved_effect_file_response(value, holder, configuration) {
    Ok(true) => ()
    Ok(false) => return -32
    Err(code) => return code
  }
  let fixed = 524288L
  let capacity = match @resources.reserve_capacity(value.root, 0L, fixed) {
    Ok(value) => value
    Err(_) => return -4
  }
  record.append_plan = Decoding(capacity, Idle)
  let peak = Ref(fixed)
  let held = Ref(fixed)
  let refused = Ref(false)
  let grow = (requested : Int64) => {
    if requested <= peak.val {
      return true
    }
    if @resources.grow_capacity_reservation(value.root, capacity, 0L, requested)
      is Err(_) {
      refused.val = true
      return false
    }
    peak.val = requested
    true
  }
  let fund = (bytes : Int, nodes : Int, _) => {
    guard @host.client_protocol_metadata_construction_bytes(
        bytes,
        nodes.to_int64(),
      )
      is Some((scratch, backing)) &&
      @execution.checked_preparation_add_product(held.val, 1L, scratch)
      is Some(total) &&
      @execution.checked_preparation_add_product(
        held.val,
        1L,
        backing + 4L * bytes.to_int64(),
      )
      is Some(next) &&
      grow(total) else {
      refused.val = true
      return false
    }
    held.val = next
    true
  }
  let check = () => submission_lookup_current(value, holder, configuration)
  let original = match
    response.original.prepare_terminal(
      () => check() is Ok(_),
      fund,
      inventory => {
        guard @host.client_run_journal_decode_construction(inventory)
          is Some((r, e)) &&
          @execution.checked_preparation_add_product(fixed, 1L, r)
          is Some(retained) &&
          @execution.checked_preparation_add_product(retained, 1L, e)
          is Some(required) &&
          grow(required) else {
          refused.val = true
          return Err(@host.ClientJournalDecodingIssue::CustodyLost)
        }
        held.val = retained
        Ok(())
      },
      (bytes, nodes, _) => {
        guard @host.client_protocol_metadata_construction_bytes(
            bytes,
            nodes.to_int64(),
            copies=1,
          )
          is Some((scratch, _)) &&
          @execution.checked_preparation_add_product(held.val, 1L, scratch)
          is Some(required) &&
          grow(required) else {
          refused.val = true
          return Err(@host.ClientJournalEncodingIssue::CapacityExceeded)
        }
        Ok(())
      },
    ) {
    Ok(value) => value
    Err(_) => return if refused.val { -4 } else { -31 }
  }
  guard saved_file_journal_packet(original.rows(), original.receipt_cid())
    is Some(header) &&
    header.length() == SAVED_EFFECT_FILE_TERMINAL_HEADER else {
    return -32
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, header),
  )
  if code == 0 {
    record.append_plan = EffectFileTerminal({
      parent,
      dispatch: response.dispatch,
      capacity,
      original,
      successor_attempted: false,
    })
    record.produced = true
  }
  code
}

///|
fn observe_saved_effect_file_terminal(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bool, Int] {
  guard record.append_plan is EffectFileTerminal(terminal) &&
    value.submissions.get(terminal.parent) is Some(holder) &&
    holder.append_plan is EffectFileResponse(response) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return Err(-32)
  }
  let check = () => submission_lookup_current(value, holder, configuration)
  let immutable = response.original.rows()
  for index in 2..<immutable.length() {
    match
      saved_file_journal_coordinate(current.physical, check, immutable[index]) {
      Ok(true) => ()
      Ok(false) => return Err(-32)
      Err(code) => return Err(code)
    }
  }
  observe_saved_file_journal_rows(
    current.physical,
    check,
    terminal.original.rows(),
  )
}
