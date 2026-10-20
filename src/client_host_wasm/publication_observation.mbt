///|
/// Physical Store observations, never SDK-supplied scope or commit decisions.
/// The trusted Host must perform the original key lookup under its current
/// publisher and six-fact/File fences before filling this original input.
priv enum PublicationCommitObservation {
  ObservedStored(
    @publication.PublicationContract,
    @publication.PublicationContract,
    @publication.PublicationContract
  )
  ObservedNotFound
  ObservedQueryFailed
}

///|
fn read_publication_observation(
  value : Instance,
  borrow : @buffers.BufferBorrow,
) -> Result[PublicationCommitObservation, Unit] {
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["kind", "request", "attempt", "index"])
    is Ok(object) &&
    required_text(object, "kind") is Some(kind) else {
    return Err(())
  }
  match kind {
    "not_found" | "query_failed" => {
      guard @decode.closed_object(cursor, ["kind"]) is Ok(_) else {
        return Err(())
      }
      if kind == "not_found" {
        Ok(ObservedNotFound)
      } else {
        Ok(ObservedQueryFailed)
      }
    }
    "stored" => {
      guard required_text(object, "request") is Some(request_wire) &&
        required_text(object, "attempt") is Some(attempt_wire) &&
        required_text(object, "index") is Some(index_wire) &&
        @publication.admit_publication_contract(
          "publication_request", request_wire, 1048576, 100000, 64,
        )
        is Ok(request) &&
        @publication.admit_publication_contract(
          "publication_attempt", attempt_wire, 1048576, 100000, 64,
        )
        is Ok(attempt) &&
        @publication.admit_publication_contract(
          "public_index_entry", index_wire, 1048576, 100000, 64,
        )
        is Ok(index) else {
        return Err(())
      }
      Ok(ObservedStored(request, attempt, index))
    }
    _ => Err(())
  }
}

///|
/// Use the original nominal publisher port, with the actual validated index
/// for ReturnCommitted. No candidate substitution or cached permission occurs.
fn publication_observation_publisher(
  value : Instance,
  record : StoredPublication,
  publisher : Int,
  current_configuration : Int,
  index : @publication.PublicationContract?,
) -> Int {
  guard value.publishers.get(publisher) is Some(child) &&
    child.port is Some(port) &&
    child.parent == record.preflight &&
    value.publication_preflights.get(child.parent) is Some(parent) &&
    parent.preflight is Some(preflight) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing ||
    value.runtime_closing ||
    record.closing ||
    child.closing ||
    parent.closing {
    return -5
  }
  if !publication_current(value, record, current.account) {
    return -32
  }
  child.configuration = current_configuration
  child.unknown = false
  let (request, attempt) = @local_run.local_publication_preflight_contracts(
    preflight,
  )
  let result = port.check(
    request,
    attempt,
    child.store,
    if index is Some(_) {
      @publication.ReturnCommitted
    } else {
      @publication.Request
    },
    index,
  )
  if child.unknown {
    return -36
  }
  if !publication_current(value, record, current.account) {
    return -32
  }
  match result {
    Ok(_) => 0
    Err(AccessDenied) => -35
    Err(NotCurrent) => -32
    Err(_) => -31
  }
}

///|
/// Retain the same physical response loan, even after parse/validation failure.
/// Completion here is not Store ACK, durable Unknown recording or Run admission.
#export_name("actql_publication_prepare_observation")
pub fn prepare_publication_observation(
  nonce : Int64,
  handle : Int,
  input : Int,
  publisher : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) &&
    value.copies.get(input) is Some((slot, physical)) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  match publication_commit_export_view(value, record, current.account) {
    Err(code) => return code
    Ok(_) => ()
  }
  if record.observation_closing || record.lookup_closing {
    return -5
  }
  if record.lookup_failed {
    return -33
  }
  if record.lookup_input is Some(_) &&
    record.lookup_publisher != Some(publisher) {
    return -2
  }
  if record.pending || record.observation_failed {
    return -33
  }
  if record.observation_input is Some(original) {
    if original != input || record.observation_publisher != Some(publisher) {
      return -2
    }
    let auth = publication_observation_publisher(
      value,
      record,
      publisher,
      current_configuration,
      None,
    )
    if auth != 0 {
      return auth
    }
    return if record.observation is Some(_) { 0 } else { -33 }
  }
  let auth = publication_observation_publisher(
    value,
    record,
    publisher,
    current_configuration,
    None,
  )
  if auth != 0 {
    return auth
  }
  record.observation_input = Some(input)
  record.observation_publisher = Some(publisher)
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => {
      record.observation_failed = true
      return issue_code(issue)
    }
  }
  record.observation_borrow = Some(borrow)
  record.pending = true
  let decoded = read_publication_observation(value, borrow)
  let result = match decoded {
    Ok(ObservedStored(request, attempt, index) as observation) => {
      guard record.commit is Some(commit) && record.commit_view is Some(view) else {
        record.pending = false
        record.observation_failed = true
        return -32
      }
      if record.lookup_input is Some(_) {
        guard record.lookup_index is Some(original_index) &&
          record.lookup_identity is Some(identity) &&
          record.lookup_publisher == Some(publisher) &&
          @publication.publication_contract_identity(index) == identity &&
          commit.view_inspected_index_reference(
            view, identity, original_index, 0,
          )
          is Ok(request_identity) &&
          commit.view_inspected_index_reference(
            view, identity, original_index, 1,
          )
          is Ok(attempt_identity) &&
          @publication.publication_contract_identity(request) ==
          request_identity &&
          @publication.publication_contract_identity(attempt) ==
          attempt_identity else {
          record.pending = false
          record.observation_failed = true
          return -32
        }
      }
      match commit.begin_observed_commit(view, request, attempt, index) {
        Ok(_) => {
          record.observation = Some(observation)
          record.observation_progress = Some((false, 0))
          0
        }
        Err(_) => -32
      }
    }
    Ok(observation) => {
      // Missing a dependent contract after finding an index does not prove an
      // uncommitted publication. Query failure stays Unknown with both loans.
      if record.lookup_input is Some(_) && !(observation is ObservedQueryFailed) {
        record.pending = false
        record.observation_failed = true
        return -32
      }
      record.observation = Some(observation)
      record.observation_progress = Some((true, 0))
      0
    }
    Err(_) => -32
  }
  record.pending = false
  if result != 0 {
    record.observation_failed = true
  }
  result
}

///|
/// Share capture/commit's original total work limit; a fresh response cannot
/// issue a new budget. Non-Stored observations require no semantic traversal.
#export_name("actql_publication_advance_observation")
pub fn advance_publication_observation(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
  quantum : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  let (commit, view) = match
    publication_commit_export_view(value, record, current.account) {
    Ok(original) => original
    Err(code) => return code
  }
  if record.observation_closing || record.lookup_closing {
    return -5
  }
  if quantum <= 0 {
    return -3
  }
  if record.pending || record.observation_failed || record.observation_checked {
    return -33
  }
  guard record.observation is Some(observation) else { return -33 }
  match observation {
    ObservedStored(_, _, _) => ()
    _ => return 0
  }
  if record.observation_progress is Some((true, _)) {
    return -33
  }
  let remaining = record.max_work - record.work
  if remaining <= 0L {
    record.observation_failed = true
    return -32
  }
  let selected_quantum = if remaining < quantum.to_int64() {
    remaining.to_int()
  } else {
    quantum
  }
  record.pending = true
  let result = commit.advance_observed_commit(view, selected_quantum)
  record.pending = false
  match result {
    Err(_) => {
      record.observation_failed = true
      -32
    }
    Ok((done, work)) => {
      if work < 0 || work > selected_quantum {
        record.observation_failed = true
        return -33
      }
      record.work += work.to_int64()
      record.observation_progress = Some((done, work))
      if !publication_current(value, record, current.account) {
        record.observation_failed = true
        return -32
      }
      0
    }
  }
}

///|
#export_name("actql_publication_observation_progress")
pub fn publication_observation_progress(
  nonce : Int64,
  handle : Int,
  field : Int,
) -> Int64 {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) else {
    return -2L
  }
  if field == 2 {
    return record.work
  }
  guard record.observation_progress is Some((done, work)) else { return -33L }
  match field {
    0 => if done { 1L } else { 0L }
    1 => work.to_int64()
    _ => -3L
  }
}

///|
/// Return an existing Core failure action, not an accepted/committed boolean.
/// AppendUnknown still needs the original durable record Owner and Store ACK.
#export_name("actql_publication_finish_observation")
pub fn finish_publication_observation(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  let (commit, view) = match
    publication_commit_export_view(value, record, current.account) {
    Ok(original) => original
    Err(code) => return code
  }
  if record.observation_closing || record.lookup_closing {
    return -5
  }
  if record.pending || record.observation_failed {
    return -33
  }
  guard record.observation is Some(observation) &&
    record.observation_publisher is Some(publisher) &&
    record.observation_progress is Some((true, _)) else {
    return -7
  }
  let index = match observation {
    ObservedStored(_, _, _) =>
      match commit.finish_observed_commit(view) {
        Ok(index) => Some(index)
        Err(_) => {
          record.observation_failed = true
          return -32
        }
      }
    _ => None
  }
  let auth = publication_observation_publisher(
    value, record, publisher, current_configuration, index,
  )
  if auth != 0 {
    return auth
  }
  record.observation_index = index
  record.observation_checked = true
  let action = match observation {
    ObservedStored(_, _, _) =>
      @publication.prepare_publication_commit_failure_step(
        true, false, true, false,
      )
    ObservedNotFound =>
      @publication.prepare_publication_commit_failure_step(
        true, false, false, false,
      )
    ObservedQueryFailed =>
      @publication.prepare_publication_commit_failure_step(
        true, true, false, false,
      )
  }
  @publication.publication_commit_failure_action_code(action)
}

///|
/// Return only the same physical response borrow after all observed outputs
/// stopped. Failed cleanup retains the exact input and blocks replacement.
#export_name("actql_publication_retire_observation")
pub fn retire_publication_observation(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) else {
    return -2
  }
  if record.pending {
    return -33
  }
  record.observation_closing = true
  if value.commit_exports
    .values()
    .any(child => {
      child.publication == handle &&
      (child.projection is Some(ObservedIndex(_)) ||
      child.projection is Some(ObservedRunState(_)) ||
      child.projection is Some(SDKRunState(_, _)))
    }) {
    return -9
  }
  if record.observation_borrow is Some(borrow) {
    let result = status(@buffers.return_buffer_borrow(value.pool, borrow))
    if result != 0 {
      return result
    }
    record.observation_borrow = None
  }
  if record.observation is Some(ObservedStored(_, _, _)) {
    guard record.commit is Some(commit) && record.commit_view is Some(view) else {
      return -32
    }
    match commit.release_observed_commit(view) {
      Err(_) => return -32
      Ok(_) => ()
    }
  }
  record.observation_input = None
  record.observation_publisher = None
  record.observation = None
  record.observation_progress = None
  record.observation_index = None
  record.observation_failed = false
  record.observation_checked = false
  record.observation_closing = false
  0
}
