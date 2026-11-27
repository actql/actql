///|
fn same_sdk_file_binding(
  original : @publication.PublicationContract,
  expected : @publication.PublicationContract,
) -> Bool {
  @publication.publication_contract_identity(original) == @publication.publication_contract_identity(expected) &&
  @publication.publication_contract_json(original) == @publication.publication_contract_json(expected)
}

///|
/// Select the same previously issued File binding, never admit a substitute
/// wire from the envelope. Physical material is independently checked at use.
fn sdk_file_original_payload_binding(
  value : Instance,
  publication : StoredPublication,
  ordinal : Int,
  expected : String,
) -> @publication.PublicationContract? {
  let mut selected = None
  for _, child in value.payload_bindings {
    if !child.produced || child.closing { continue }
    guard child.file_binding is Some(binding) &&
      value.payload_records.get(child.parent) is Some(payload) && !payload.closing &&
      payload.source is LiveRequest && payload.begun && payload.confirmed &&
      payload.record is Some(original) &&
      @payload.publication_payload_record_state(original) is Sealed &&
      @payload.publication_payload_record_generation(original) is Some(_) &&
      @payload.publication_payload_record_revision(original) == child.revision &&
      value.payload_requests.get(payload.request) is Some(request) &&
      !request.closing && request.produced && request.index == ordinal &&
      request.request is Some(issued) &&
      physical_equal(issued, @payload.publication_payload_record_request(original)) &&
      value.publications.get(request.publication) is Some(parent) &&
      physical_equal(parent, publication) else { continue }
    if selected is Some(_) || @publication.publication_contract_json(binding) != expected {
      return None
    }
    selected = Some(binding)
  }
  selected
}

///|
fn prepare_sdk_file_commit_candidate(
  value : Instance,
  record : StoredPublication,
  file : StoredFilePublicationCapture,
  receipt : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  inputs : Array[@decode.Cursor],
  committed_at : String,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[
  (@publication.PublicationContract, @publication.PublicationCommitPreparation),
  Int,
] {
  guard file.original.prepared is Some(preflight) && file.manifest is Some(manifest) &&
    record.capture is Some(capture) && file.capacity is Some(_) &&
    inputs.length() == file.results.length() else { return Err(-35) }
  let current = () => sdk_file_capture_require_current(value, record, file, account)
  match current() {
    Err(issue) => return Err(file_preflight_issue(issue))
    Ok(_) => ()
  }
  let (request, attempt) = @local_run.local_captured_task_publication_preflight_contracts(preflight)
  let mut nodes = 128L
  for contract in [
    request, attempt, receipt, captured,
    @local_run.local_captured_task_publication_manifest_contract(manifest),
  ] {
    guard @publication.publication_contract_wire_usage(contract) is Some((_, count, _)) &&
      @execution.checked_preparation_add_product(nodes, count.to_int64(), 1L) is Some(next_nodes)
      else { return Err(-4) }
    nodes = next_nodes
  }
  // Observe existing wire geometry without allocating the binding inventory.
  for ordinal, cursor in inputs {
    guard @decode.text(cursor) is Ok(wire) &&
      sdk_file_original_payload_binding(value, record, ordinal, wire) is Some(binding)
      else { return Err(-35) }
    guard @publication.publication_contract_wire_usage(binding) is Some((_, count, _)) &&
      @execution.checked_preparation_add_product(nodes, count.to_int64(), 1L) is Some(next_nodes)
      else { return Err(-4) }
    nodes = next_nodes
  }
  let count = inputs.length().to_int64()
  // The contracts and decoded binding wires remain with their existing
  // owners. Fund the new reference arrays and bounded validator controls.
  let slots = nodes + 16L * count
  let workspace = Int64::min(record.max_workspace.to_int64(), 4L * slots)
  guard @execution.preparation_representation_cost({
    record_headers: 24L,
    reference_slots: 64L + 8L * count,
    scalar_words: 32L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }) is Some(retained) &&
    @execution.checked_preparation_add_product(8192L, slots + workspace, 128L)
    is Some(controls) &&
    grow_sdk_file_publication_capacity(file, retained, controls) else {
    return Err(-4)
  }
  match current() {
    Err(issue) => return Err(file_preflight_issue(issue))
    Ok(_) => ()
  }
  let bindings = Array(capacity=inputs.length())
  for ordinal, cursor in inputs {
    guard @decode.text(cursor) is Ok(wire) &&
      sdk_file_original_payload_binding(value, record, ordinal, wire) is Some(binding)
      else { return Err(-35) }
    bindings.push(binding)
  }
  @local_run.prepare_local_captured_task_commit_candidate(
    manifest, capture, receipt, captured, bindings, committed_at,
    sdk_file_capture_limits(value), record.max_workspace, current,
    (retained, temporary) => {
      guard @execution.checked_preparation_add_product(controls, temporary, 1L)
        is Some(scratch) else { return false }
      grow_sdk_file_publication_capacity(file, retained, scratch)
    },
  ).map_err(file_preflight_issue)
}
