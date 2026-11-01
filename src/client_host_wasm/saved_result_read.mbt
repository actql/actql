///|
/// One read operation's original metadata and input loans, never an executable
/// Run, grant or process cache. Partial validation remains attached to the same
/// output until explicit close; the physical Host owns its snapshot/FD duties.
priv struct StoredSavedResultRead {
  snapshot : @host.ClientSavedSubmissionSnapshot
  result_name : String
  fences : Array[(String, String, Int64, Bytes)]
  mut source : @local_run.LocalSDKReadSource?
  finite : @host.ClientLocalRunPolicyOriginal?
  mut owner : @publication.PublicationCommitPreparation?
  mut view : @publication.PublicationCommitReadView?
  mut observed : Bool
  mut complete : Bool
}

///|
fn saved_result_read_current(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  result_name : String,
) -> Result[Unit, Int] {
  match submission_lookup_current(value, record, configuration) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let tuple : @authorization.AccessTuple = {
    principal: configuration.tuple.principal,
    connection: configuration.tuple.connection,
    resource: "result/" + result_name,
    operation: "read",
  }
  if @authorization.evaluate_account(configuration.account, tuple)
    is @authorization.Allow(_) {
    Ok(())
  } else {
    Err(-32)
  }
}

///|
fn prepare_saved_result_read(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bytes, Int] {
  guard record.kind == 6 &&
    record.saved_result is None &&
    configuration.sdk is Some(sdk) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    record.borrow is Ok(borrow) &&
    input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "namespaceId", "authorityScopeCid", "runDefinitionCid", "resultName",
    ])
    is Ok(object) &&
    required_text(object, "resultName") is Some(result_name) &&
    !result_name.is_empty() else {
    return Err(-31)
  }
  let check = () => {
    saved_result_read_current(value, record, configuration, result_name)
  }
  match check() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let snapshot = match observe_submission_lookup(value, record, configuration) {
    Ok(Some(value)) => value
    Ok(None) => return Err(-42)
    Err(code) => return Err(code)
  }
  guard @host.client_saved_submission_run_row(snapshot) is Some(row) &&
    @host.decode_client_run_journal_row_with_observation_originals(row.body)
    is Ok((run, Some(policy_wire), Some(observation_wire))) else {
    return Err(-42)
  }
  let submitted = @host.client_saved_submission_record(snapshot)
  // Durable originals are admitted through their own Owner. Current SDK
  // selections must match them; a later equivalent CID cannot reissue them.
  let finite = match
    @host.admit_client_local_run_policy_original(
      @utf8.encode(policy_wire),
      sdk.profile,
      submitted.reference,
      run.request,
      run.definition,
      sdk.adoption_cid,
      @publication.local_sdk_result_read_selection_cid(sdk.read),
    ) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  if @host.restore_client_run_observation_originals_wire(
      run.definition,
      observation_wire,
      131072,
      8192,
      64,
    )
    is Err(_) {
    return Err(-32)
  }
  guard current.generation is Some((device, inode)) &&
    @host.client_publication_store_binding_body(
      configuration.run_namespace,
      sdk.store_authority_cid,
      device,
      inode,
    )
    is Ok(publication_binding) &&
    run.publication_binding == Some(publication_binding) else {
    return Err(-32)
  }
  let retained : StoredSavedResultRead = {
    snapshot,
    result_name,
    fences: [],
    source: None,
    finite: Some(finite),
    owner: None,
    view: None,
    observed: false,
    complete: false,
  }
  // Retain this carrier before the first publication query or fallible advance.
  record.saved_result = Some(retained)
  let read = (table, key) => {
    physical_journal_row(current.physical, check, 1, table, key).bind(row => {
      match row {
        None => Ok(None)
        Some(row) => {
          if row.key != key {
            return Err(-41)
          }
          retained.fences.push((table, key, row.revision, row.body))
          Ok(Some(row.body))
        }
      }
    })
  }
  let owner = match
    @publication.read_stored_effect_free_publication(
      configuration.run_namespace,
      configuration.authority_scope_cid,
      @publication.publication_contract_identity(run.definition),
      read,
      check,
      256,
      8388608,
      262144,
      65536,
      64,
      131072,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(-42)
    Err(Read(code)) => return Err(code)
    Err(_) => return Err(-31)
  }
  retained.owner = Some(owner)
  let mut done = false
  for _ in 0..<250000 {
    match owner.advance(256) {
      Ok((true, _)) => {
        done = true
        break
      }
      Ok((false, _)) => ()
      Err(_) => return Err(-31)
    }
  }
  if !done {
    return Err(-34)
  }
  let view = match owner.finish_view() {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  retained.view = Some(view)
  let request = match owner.view_contract(view, 5) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  let attempt = match owner.view_contract(view, 6) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  let index = match owner.view_contract(view, 7) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  if owner.begin_observed_commit(view, request, attempt, index) is Err(_) {
    return Err(-31)
  }
  retained.observed = true
  done = false
  for _ in 0..<250000 {
    match owner.advance_observed_commit(view, 256) {
      Ok((true, _)) => {
        done = true
        break
      }
      Ok((false, _)) => ()
      Err(_) => return Err(-31)
    }
  }
  if !done {
    return Err(-34)
  }
  guard configuration.source_free_result_policy is Some(source_policy) else {
    return Err(-32)
  }
  let source = match
    @local_run.prepare_local_saved_sdk_read_source(
      snapshot,
      finite,
      source_policy,
      configuration.account,
      configuration.tuple.principal,
      configuration.tuple.connection,
      sdk.adoption_cid,
      owner,
      view,
    ) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  retained.source = Some(source)
  let materials = match
    owner.observed_result_read_materials(view, result_name, 16) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  if materials.read.store_authority_cid != sdk.store_authority_cid {
    return Err(-32)
  }
  let mut binding = None
  for ordinal in 0..<16 {
    match owner.view_binding(view, ordinal) {
      Ok(value) if @publication.publication_contract_identity(value) ==
        materials.read.durable_result_binding_cid => {
        binding = Some(value)
        break
      }
      Ok(_) => ()
      Err(_) => break
    }
  }
  guard binding is Some(binding) else { return Err(-31) }
  let (result_ordinal, binding_ordinal) = match
    @local_run.local_sdk_saved_result_coordinates(
      source,
      configuration.account,
      owner,
      view,
      result_name,
    ) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  let wire = try {
    let writer = @encode.writer(1048576, 32, 1)
    @encode.begin_object(writer)
    for
      (key, text) in [
        ("kind", "result-originals"),
        ("resultOrdinal", result_ordinal.to_string()),
        ("bindingOrdinal", binding_ordinal.to_string()),
        ("resultName", result_name),
        (
          "runDefinitionCid",
          @publication.publication_contract_identity(run.definition),
        ),
        ("index", @publication.publication_contract_json(materials.index)),
        ("manifest", @publication.publication_contract_json(materials.manifest)),
        (
          "definition",
          @publication.publication_contract_json(materials.definition),
        ),
        ("artifact", @publication.publication_contract_json(materials.artifact)),
        (
          "retention",
          @publication.publication_contract_json(materials.retention),
        ),
        ("binding", @publication.publication_contract_json(binding)),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    @utf8.encode(@encode.finish(writer))
  } catch {
    _ => return Err(-34)
  }
  match check() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  retained.complete = true
  Ok(wire)
}

///|
// Pack only a bounded same-namespace set before any physical IO. Binary/large
// fields and single rows keep the old scalar algorithm, not an error fallback.
fn saved_result_fence_packet(
  fences : Array[(String, String, Int64, Bytes)],
  start : Int,
) -> (String, Int)? {
  if start < 0 || start >= fences.length() {
    return None
  }
  try {
    let writer = @encode.writer(4096, 129, 2)
    @encode.begin_array(writer)
    let mut used = 2
    let mut end = start
    let names : Array[String] = []
    while end < fences.length() && end - start < 32 {
      let (table, key, revision, body) = fences[end]
      if table != "publication_contract" || revision < 0L || names.contains(key) {
        break
      }
      let text = @utf8.decode(body) catch { _ => break }
      let document = try {
        let row = @encode.writer(4096, 4, 1)
        @encode.begin_array(row)
        @encode.string_value(row, key)
        @encode.string_value(row, revision.to_string())
        @encode.string_value(row, text)
        @encode.end_array(row)
        Some(@encode.finish_document(row))
      } catch {
        _ => None
      }
      guard document is Some(document) else { break }
      let bytes = @encode.document_bytes(document) +
        (if end == start { 0 } else { 1 })
      if bytes > 4096 - used {
        break
      }
      @encode.emit_document(writer, document)
      used += bytes
      names.push(key)
      end += 1
    }
    if end - start < 2 {
      return None
    }
    @encode.end_array(writer)
    Some((@encode.finish(writer), end))
  } catch {
    _ => None
  }
}

///|
// Actual same-current physical observations, not retained current results.
// Every original fence still participates in exact key/revision/body equality.
fn validate_saved_result_fences(
  fences : Array[(String, String, Int64, Bytes)],
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  packet : (String) -> Result[Bool?, Int],
) -> Result[Unit, Int] {
  let mut index = 0
  let mut scalar_only = false
  while index < fences.length() {
    match
      (if scalar_only {
        None
      } else {
        saved_result_fence_packet(fences, index)
      }) {
      Some((wire, end)) =>
        match packet(wire) {
          Err(code) => return Err(code)
          Ok(Some(false)) => return Err(-32)
          Ok(Some(true)) => {
            index = end
            continue
          }
          Ok(None) => scalar_only = true
        }
      None => ()
    }
    let (table, key, revision, body) = fences[index]
    match read(table, key) {
      Ok(Some(row)) if row.key == key &&
        row.revision == revision &&
        row.body == body => ()
      Err(code) => return Err(code)
      _ => return Err(-32)
    }
    index += 1
  }
  Ok(())
}

///|
fn validate_saved_result_read(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Unit, Int] {
  guard record.saved_result is Some(retained) &&
    retained.complete &&
    retained.owner is Some(owner) &&
    retained.view is Some(view) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return Err(-32)
  }
  let check = () => {
    saved_result_read_current(
      value,
      record,
      configuration,
      retained.result_name,
    )
  }
  match check() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  match
    observe_submission_lookup(
      value,
      record,
      configuration,
      original=Some(retained.snapshot),
    ) {
    Ok(Some(_)) => ()
    Ok(None) => return Err(-42)
    Err(code) => return Err(code)
  }
  match
    validate_saved_result_fences(
      retained.fences,
      (table, key) => {
        physical_journal_row(current.physical, check, 1, table, key)
      },
      wire => physical_journal_fence_packet(current.physical, check, wire),
    ) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  if owner.observed_result_read_materials(view, retained.result_name, 16)
    is Err(_) {
    return Err(-32)
  }
  check()
}

///|
fn close_saved_result_read(record : StoredSubmissionProjection) -> Int {
  guard record.saved_result is Some(retained) else { return 0 }
  if retained.owner is Some(owner) {
    owner.cancel()
    if retained.view is Some(view) {
      if retained.observed && owner.release_observed_commit(view) is Err(_) {
        return -9
      }
      if owner.release_view(view) is Err(_) {
        return -9
      }
    }
  }
  record.saved_result = None
  0
}
