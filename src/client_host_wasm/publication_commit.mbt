///|
fn prepare_publication_commit_owner(
  value : Instance,
  record : StoredPublication,
  account : @authorization.AdmittedAccountConfiguration,
  borrow : @buffers.BufferBorrow,
) -> Result[
  (@publication.PublicationContract, @publication.PublicationCommitPreparation),
  Unit,
] {
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["bindings", "committed_at"]) is Ok(object) &&
    @decode.required(object, "bindings") is Ok(bindings_cursor) &&
    @decode.elements(bindings_cursor) is Ok(binding_values) &&
    binding_values.length() == record.publications.length() &&
    required_text(object, "committed_at") is Some(committed_at) &&
    record.manifest is Some(manifest) &&
    record.receipt is Some(receipt) &&
    record.captured is Some(captured) &&
    value.publication_preflights.get(record.preflight)
    is Some({ closing: false, preflight: Some(preflight), .. }) &&
    value.run_invocations.get(record.source) is Some({ compute, .. }) &&
    value.computes.get(compute) is Some(original_compute) &&
    stored_compute_original_run(value, original_compute)
    is Some({ normalization: Some(normalization), .. }) else {
    return Err(())
  }
  let bindings : Array[@publication.PublicationContract] = []
  for cursor in binding_values {
    guard @decode.text(cursor) is Ok(wire) else { return Err(()) }
    match
      @publication.admit_publication_contract(
        "durable_result_binding", wire, 1048576, 100000, 64,
      ) {
      Ok(binding) => bindings.push(binding)
      Err(_) => return Err(())
    }
  }
  @local_run.prepare_local_preflight_commit_candidate(
    preflight,
    manifest,
    normalization,
    receipt,
    captured,
    bindings,
    committed_at,
    account,
    {
      max_results: value.workspace_slots,
      max_wire_bytes: 1048576,
      max_nodes: 100000,
      max_depth: 64,
    },
    record.max_workspace,
  ).map_err(_ => ())
}

///|
/// Validate the physical Host's proposed commit chain against the original
/// retained Receipt/Captured Run. This does not authorize or install a Store
/// commit. The Store must separately verify payload facts and current access.
pub fn prepare_publication_commit(
  nonce : Int64,
  handle : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) &&
    value.copies.get(input) is Some((slot, physical)) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if !record.produced || record.pending || record.failed || record.commit_failed {
    return -33
  }
  if !publication_current(value, record, current.account) {
    return -32
  }
  if record.commit_input is Some(original) {
    if original != input {
      return -2
    }
    return if record.commit is Some(_) || record.commit_finished {
      0
    } else {
      -33
    }
  }
  // Retain the same immutable input and original parents even if an Owner
  // call traps. A different input cannot restart this validation attempt.
  record.commit_input = Some(input)
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => {
      record.commit_failed = true
      return issue_code(issue)
    }
  }
  record.commit_borrow = Some(borrow)
  record.pending = true
  let result = prepare_publication_commit_owner(
    value,
    record,
    current.account,
    borrow,
  )
  record.pending = false
  match result {
    Ok((index_entry, commit)) => {
      record.commit_index = Some(index_entry)
      record.commit = Some(commit)
      0
    }
    Err(_) => {
      record.commit_failed = true
      -32
    }
  }
}

///|
pub fn advance_publication_commit(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
  quantum : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) &&
    record.commit is Some(commit) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || record.closing || record.commit_finished {
    return -5
  }
  if quantum <= 0 {
    return -3
  }
  if record.pending ||
    record.commit_failed ||
    record.commit_progress is Some((true, _)) {
    return -33
  }
  if !publication_current(value, record, current.account) {
    return -32
  }
  // Snapshot, capture and commit validation share the original logical-work
  // limit. A new input or authority configuration cannot reset that budget.
  let remaining = record.max_work - record.work
  if remaining <= 0L {
    record.commit_failed = true
    return -32
  }
  let quantum = if remaining < quantum.to_int64() {
    remaining.to_int()
  } else {
    quantum
  }
  record.pending = true
  let result = commit.advance(quantum)
  record.pending = false
  match result {
    Err(_) => {
      record.commit_failed = true
      -32
    }
    Ok((done, work)) => {
      if work < 0 || work > quantum {
        record.commit_failed = true
        return -33
      }
      record.work += work.to_int64()
      record.commit_progress = Some((done, work))
      if !publication_current(value, record, current.account) {
        record.commit_failed = true
        return -32
      }
      0
    }
  }
}

///|
pub fn publication_commit_progress(
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
  guard record.commit_progress is Some((done, work)) else { return -33L }
  match field {
    0 => if done { 1L } else { 0L }
    1 => work.to_int64()
    _ => -3L
  }
}

///|
/// Completion proves only that the existing commit validator accepted this
/// chain. It is neither a durable commit acknowledgement nor Run admission.
pub fn finish_publication_commit(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if !publication_current(value, record, current.account) {
    return -32
  }
  if record.pending || record.commit_failed {
    return -33
  }
  if record.commit_finished {
    return 0
  }
  guard record.commit is Some(commit) &&
    record.commit_progress is Some((true, _)) else {
    return -7
  }
  record.pending = true
  let result = commit.finish_view()
  record.pending = false
  match result {
    Ok(view) => {
      record.commit_finished = true
      record.commit_view = Some(view)
      0
    }
    Err(_) => {
      record.commit_failed = true
      -32
    }
  }
}
