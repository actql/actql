///|
const SAVED_EFFECT_FILE_DISPATCH_KIND : Int = 22

///|
const SAVED_EFFECT_FILE_DISPATCH_FIELD_KIND : Int = 23

///|
const SAVED_EFFECT_FILE_DISPATCH_HEADER : Int = 237

///|
priv struct StoredSavedEffectFileDispatch {
  parent : Int
  application : Int
  index : Int
  capacity : @resources.CapacityReservation
  original : @host.ClientEffectSavedFileDispatch
  mut operation_attempted : Bool
}

///|
fn produce_saved_effect_file_dispatch(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  let candidate = match select_saved_effect_file_dispatch(value, record, configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  let holder = candidate.holder
  let input = candidate.input
  let index = candidate.index
  guard value.submissions.get(candidate.application) is Some(app_holder) &&
    app_holder.append_plan is EffectApplication(application) &&
    value.submissions.get(application.parent) is Some(resume_holder) &&
    resume_holder.append_plan is EffectResumeClaim(claim) &&
    mock_project_request_configuration(value, claim.environment)
    is Some((selected_configuration, check)) &&
    physical_equal(configuration, selected_configuration) &&
    check.data_path is Some(path) &&
    application.files.get(index) is Some(file) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return -32
  }
  let at = @utf8.decode(input[4:]) catch { _ => return -31 }
  guard @values.timestamp_epoch_milliseconds(at) is Some(now) else {
    return -31
  }
  let fixed = 524288L
  let capacity = match @resources.reserve_capacity(value.root, 0L, fixed) {
    Ok(value) => value
    Err(_) => return -4
  }
  record.append_plan = Decoding(capacity, Idle)
  let peak = Ref(fixed)
  let held = Ref(fixed)
  let denied = Ref(false)
  let grow_to = (needed : Int64) => {
    if needed > peak.val {
      if @resources.grow_capacity_reservation(value.root, capacity, 0L, needed)
        is Err(_) {
        denied.val = true
        return false
      }
      peak.val = needed
    }
    true
  }
  let fund_amount = (bytes : Int64) => {
    guard @execution.checked_preparation_add_product(held.val, 1L, bytes)
      is Some(needed) else {
      denied.val = true
      return false
    }
    grow_to(needed)
  }
  let fund = (bytes : Int, nodes : Int, _) => {
    guard @host.client_protocol_metadata_construction_bytes(
        bytes,
        nodes.to_int64(),
      )
      is Some((scratch, retained)) &&
      fund_amount(scratch) &&
      @execution.checked_preparation_add_product(
        held.val,
        1L,
        retained + 4L * bytes.to_int64(),
      )
      is Some(next) else {
      denied.val = true
      return false
    }
    held.val = next
    true
  }
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 64,
  }
  let validated = if candidate.previous is Some(_) {
    match observe_saved_effect_file_terminal(value, holder, configuration) {
      Ok(true) => 0
      Ok(false) => -32
      Err(code) => code
    }
  } else {
    validate_saved_effect_application(value, holder, configuration)
  }
  if validated != 0 { return validated }
  let account = configuration.account
  let tuple : @authorization.AccessTuple = {
    principal: configuration.tuple.principal,
    connection: file.selected.source.connection,
    resource: file.selected.write.mapping.resource,
    operation: "read",
  }
  guard @authorization.evaluate_account(account, tuple) is Allow(_) &&
    mock_project_write_visible(
      account,
      tuple.principal,
      file.selected.source,
      file.selected.write,
    ) &&
    application.original.authorize_file_target(
      account,
      { ..tuple, operation: "effect", },
      at,
      fund,
    ) else {
    return if denied.val { -4 } else { -20 }
  }
  guard file.row.selected_file_target(path, tuple.resource, limits, fund)
    is Some(target) else {
    return if denied.val { -4 } else { -32 }
  }
  let check = () => submission_lookup_current(value, holder, configuration)
  let (run_key, run_extent, witness_key, witness_extent) = match candidate.previous {
    None => {
      let (prior, next) = claim.original.rows()
      let (witness_key, witness_extent) = application.original.empty_ledger_coordinate()
      (prior.key, next.length(), witness_key, witness_extent)
    }
    Some(previous) => {
      let rows = previous.rows()
      (rows[0].key, rows[0].successor.length(), rows[1].key, rows[1].successor.length())
    }
  }
  let run = match physical_journal_row(
    current.physical, check, 1, "client_runs", run_key,
    expected_body_length=Some(run_extent),
  ) {
    Ok(Some(row)) => row
    Ok(None) => return -32
    Err(code) => return code
  }
  let witness = match physical_journal_row(
    current.physical, check, 1, "client_effect_custody", witness_key,
    expected_body_length=Some(witness_extent),
  ) {
    Ok(Some(row)) => row
    Ok(None) => return -32
    Err(code) => return code
  }
  let after_targets = held.val
  let original = match
    file.row.prepare_dispatch(
      run,
      witness,
      candidate.previous,
      index,
      target,
      now,
      () => check() is Ok(_),
      limits,
      fund,
      stage => {
        guard @host.client_run_journal_decode_construction(stage)
          is Some((r, e)) &&
          @execution.checked_preparation_add_product(after_targets, 1L, r)
          is Some(retained) &&
          @execution.checked_preparation_add_product(retained, 1L, e)
          is Some(requested) &&
          grow_to(requested) else {
          denied.val = true
          return Err(@host.ClientJournalDecodingIssue::CustodyLost)
        }
        held.val = retained
        Ok(())
      },
      (size, nodes, _) => {
        guard @host.client_protocol_metadata_construction_bytes(
            size,
            nodes.to_int64(),
            copies=1,
          )
          is Some((scratch, _)) &&
          fund_amount(scratch) else {
          return Err(@host.ClientJournalEncodingIssue::CapacityExceeded)
        }
        Ok(())
      },
    ) {
    Ok(value) => value
    Err(_) => return if denied.val { -4 } else { -31 }
  }
  let ((run, run_next), (witness, witness_next)) = original.rows()
  guard run.key.length() == 71 &&
    witness.key.length() == 71 &&
    run_next.length() > 0 &&
    witness_next.length() > 0 else {
    return -32
  }
  let header = Bytes::makei(24, index => {
      let first = index < 12
      let offset = if first { index } else { index - 12 }
      let revision = if first { run.revision } else { witness.revision }
      let extent = if first { run_next.length() } else { witness_next.length() }
      if offset < 8 {
        (revision >> (offset * 8)).to_byte()
      } else {
        (extent >> ((offset - 8) * 8)).to_byte()
      }
    }) +
    @utf8.encode(run.key + witness.key + original.dispatch_cid())
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, header),
  )
  if code == 0 {
    record.append_plan = EffectFileDispatch({
      parent:candidate.parent, application:candidate.application, index, capacity, original,
      operation_attempted: false,
    })
    record.produced = true
  }
  code
}

///|
fn observe_saved_effect_file_dispatch(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bool, Int] {
  guard record.append_plan is EffectFileDispatch(dispatch) &&
    value.submissions.get(dispatch.application) is Some(holder) &&
    holder.append_plan is EffectApplication(_) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return Err(-32)
  }
  let check = () => submission_lookup_current(value, holder, configuration)
  if dispatch.index > 0 {
    match require_saved_effect_file_prefix(value, dispatch.parent, current.physical, check) {
      Ok(_) => ()
      Err(code) => return Err(code)
    }
  }
  let (run, witness) = dispatch.original.rows()
  let read = (table : String, pair : (@host.ClientJournalPhysicalRow, Bytes)) => {
    let (before, next) = pair
    physical_journal_row(
      current.physical,
      check,
      1,
      table,
      before.key,
      expected_successor_lengths=Some(
        (before.revision, before.body.length(), next.length()),
      ),
    ).bind(actual => {
      match actual {
        Some(row) if row.key == before.key &&
          row.revision == before.revision &&
          row.body == before.body => Ok(false)
        Some(row) if row.key == before.key &&
          row.revision == before.revision + 1L &&
          row.body == next => Ok(true)
        _ => Err(-32)
      }
    })
  }
  let run = match read("client_runs", run) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  let witness = match read("client_effect_custody", witness) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  if run == witness {
    check().map(_ => run)
  } else {
    Err(-32)
  }
}

///|
fn produce_saved_effect_file_dispatch_field(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  guard saved_effect_decision_parent(
      value,
      record,
      SAVED_EFFECT_FILE_DISPATCH_KIND,
    )
    is Some((parent, holder, input)) &&
    input.length() == 16 &&
    holder.append_plan is EffectFileDispatch(dispatch) else {
    return -32
  }
  let field = mock_effect_descriptor_field(input, 4)
  let ((_, run), (_, witness)) = dispatch.original.rows()
  let body = match field {
    0 => run
    1 => witness
    _ => return -31
  }
  let offset = mock_effect_descriptor_field(input, 8)
  let count = mock_effect_descriptor_field(input, 12)
  guard offset >= 0 &&
    count > 0 &&
    count <= SAVED_EFFECT_DECISION_FIELD_MAX &&
    offset <= body.length() - count else {
    return -31
  }
  guard observe_saved_effect_file_dispatch(value, holder, configuration)
    is Ok(false) else {
    return -32
  }
  let code = status(
    @buffers.supply_buffer_output(
      value.pool,
      record.slot,
      body[offset:offset + count].to_owned(),
    ),
  )
  if code == 0 {
    record.append_plan = EffectDecisionField(parent)
    record.produced = true
  }
  code
}

///|
fn saved_effect_file_dispatch_kind(kind : Int) -> Bool {
  kind == SAVED_EFFECT_FILE_DISPATCH_KIND ||
  kind == SAVED_EFFECT_FILE_DISPATCH_FIELD_KIND
}

///|
priv struct SavedEffectDispatchEntry {
  parent : Int
  holder : StoredSubmissionProjection
  input : Bytes
  application : Int
  index : Int
  previous : @host.ClientEffectSavedFileTerminal?
}

///|
fn select_saved_effect_file_dispatch(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[SavedEffectDispatchEntry, Int] {
  if saved_effect_decision_parent(
      value, record, SAVED_EFFECT_APPLICATION_KIND,
    )
    is Some((parent, holder, input)) &&
    holder.append_plan is EffectApplication(application) {
    guard input.length() == 28 && !application.dispatch_attempted
      else { return Err(-33) }
    application.dispatch_attempted = true
    return Ok({ parent, holder, input, application: parent, index: 0, previous: None, })
  }
  guard saved_effect_decision_parent(value, record, SAVED_EFFECT_FILE_TERMINAL_KIND)
    is Some((parent, holder, input)) &&
    input.length() == 28 &&
    holder.append_plan is EffectFileTerminal(terminal) &&
    !terminal.successor_attempted &&
    value.submissions.get(terminal.dispatch) is Some(dispatch_holder) &&
    dispatch_holder.append_plan is EffectFileDispatch(dispatch) &&
    physical_equal(configuration, value.run_configurations[holder.configuration]) else {
    return Err(-32)
  }
  terminal.successor_attempted = true
  Ok({
    parent, holder, input, application: dispatch.application,
    index: dispatch.index + 1, previous: Some(terminal.original),
  })
}

///|
fn require_saved_effect_file_prefix(
  value : Instance,
  last : Int,
  physical : Int,
  check : () -> Result[Unit, Int],
) -> Result[Unit, Int] {
  let mut parent = Some(last)
  while parent is Some(handle) {
    guard value.submissions.get(handle) is Some(holder) &&
      holder.append_plan is EffectFileTerminal(terminal) &&
      value.submissions.get(terminal.parent) is Some(response_holder) &&
      response_holder.append_plan is EffectFileResponse(response) &&
      value.submissions.get(terminal.dispatch) is Some(dispatch_holder) &&
      dispatch_holder.append_plan is EffectFileDispatch(dispatch) else {
      return Err(-32)
    }
    let committed = response.original.rows()
    for index in 2..<committed.length() {
      match saved_file_journal_coordinate(physical, check, committed[index]) {
        Ok(true) => ()
        Ok(false) => return Err(-32)
        Err(code) => return Err(code)
      }
    }
    match saved_file_journal_coordinate(physical, check, terminal.original.rows()[2]) {
      Ok(true) => ()
      Ok(false) => return Err(-32)
      Err(code) => return Err(code)
    }
    parent = if dispatch.index == 0 { None } else { Some(dispatch.parent) }
  }
  Ok(())
}
