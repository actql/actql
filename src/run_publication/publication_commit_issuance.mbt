///|
pub(all) enum PublicationCommitIssuanceIssue {
  CommitIssuanceWrongContract
  CommitIssuanceEmptyInventory
  CommitIssuanceInventoryMismatch
  CommitIssuanceDuplicateResult(String)
  CommitIssuanceReferenceMismatch(String)
  CommitIssuanceEncoding
  CommitIssuanceContract(PublicationContractIssue)
} derive(Eq, Debug)

///|
priv struct PublicationInventoryEntry {
  name : String
  definition_cid : String
}

///|
fn publication_inventory_entries(
  definitions : Array[PublicationContract],
) -> Result[Array[PublicationInventoryEntry], PublicationCommitIssuanceIssue] {
  if definitions.is_empty() {
    return Err(CommitIssuanceEmptyInventory)
  }
  let entries : Array[PublicationInventoryEntry] = []
  let names : Array[String] = []
  for definition in definitions {
    if definition.name != "result_definition" {
      return Err(CommitIssuanceWrongContract)
    }
    guard contract_string(definition, "result_name") is Some(name) else {
      return Err(CommitIssuanceInventoryMismatch)
    }
    if names.contains(name) {
      return Err(CommitIssuanceDuplicateResult(name))
    }
    names.push(name)
    entries.push({ name, definition_cid: definition.identity, })
  }
  entries.sort_by((left, right) => {
    @canonical.compare_utf16(left.name, right.name)
  })
  Ok(entries)
}

///|
fn finish_publication_body(
  name : String,
  writer : @encode.Writer,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationCommitIssuanceIssue] {
  let body = @encode.finish(writer) catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  match
    seal_publication_contract(name, body, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => Ok(value)
    Err(issue) => Err(CommitIssuanceContract(issue))
  }
}

///|
/// Issue immutable publication intent from one admitted Result inventory.
/// The standard Host supplies the complete checked inventory; this owner fixes
/// its canonical order and rejects duplicate or malformed entries.
pub fn issue_publication_request(
  run_definition : PublicationContract,
  definitions : Array[PublicationContract],
  namespace_id : String,
  authority_scope_cid : String,
  publication_policy_cid : String,
  publication_target_cid : String,
  requested_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationCommitIssuanceIssue] {
  if run_definition.name != "run_definition" {
    return Err(CommitIssuanceWrongContract)
  }
  let entries = match publication_inventory_entries(definitions) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authority_scope_cid")
    @encode.string_value(writer, authority_scope_cid)
    @encode.key(writer, "inventory")
    @encode.begin_array(writer)
    for entry in entries {
      @encode.begin_object(writer)
      @encode.key(writer, "result_definition_cid")
      @encode.string_value(writer, entry.definition_cid)
      @encode.key(writer, "result_name")
      @encode.string_value(writer, entry.name)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "publication_policy_cid")
    @encode.string_value(writer, publication_policy_cid)
    @encode.key(writer, "publication_target_cid")
    @encode.string_value(writer, publication_target_cid)
    @encode.key(writer, "requested_at")
    @encode.string_value(writer, requested_at)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, run_definition.identity)
    @encode.key(writer, "namespace_id")
    @encode.string_value(writer, namespace_id)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-publication-request/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  finish_publication_body(
    "publication_request", writer, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Issue one immutable attempt for an admitted request. Outcome and terminal
/// records are deliberately absent from this identity.
pub fn issue_publication_attempt(
  request : PublicationContract,
  run_definition : PublicationContract,
  attempt_id : String,
  fence_cid : String,
  external_idempotency_key : String?,
  started_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationCommitIssuanceIssue] {
  if request.name != "publication_request" ||
    run_definition.name != "run_definition" {
    return Err(CommitIssuanceWrongContract)
  }
  if contract_string(request, "run_definition_cid") !=
    Some(run_definition.identity) {
    return Err(CommitIssuanceReferenceMismatch("run_definition_cid"))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "attempt_id")
    @encode.string_value(writer, attempt_id)
    match external_idempotency_key {
      Some(value) => {
        @encode.key(writer, "external_idempotency_key")
        @encode.string_value(writer, value)
      }
      None => ()
    }
    @encode.key(writer, "fence_cid")
    @encode.string_value(writer, fence_cid)
    @encode.key(writer, "publication_request_cid")
    @encode.string_value(writer, request.identity)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, run_definition.identity)
    @encode.key(writer, "started_at")
    @encode.string_value(writer, started_at)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-publication-attempt/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  finish_publication_body(
    "publication_attempt", writer, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Validate the immutable inputs that must be known before Compute starts for
/// one complete Named Result publication. Physical capacity and mutable Store
/// state remain adapter observations; this function owns the cross-contract
/// meaning of the preflight decision.
pub fn publication_preflight_valid(
  admission : RunPublicationAdmission,
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  retentions : Array[PublicationContract],
  computation_contract_cids : Array[String],
  input_relation_cids : Array[Array[String]],
  scope_cids : Array[String],
  effective_data_policy_cids : Array[String],
  authority_scope_cids : Array[String],
  request : PublicationContract,
  attempt : PublicationContract,
  program_definition_cid : String,
) -> Bool {
  if run_definition.name != "run_definition" ||
    invocation.name != "run_invocation" ||
    request.name != "publication_request" ||
    attempt.name != "publication_attempt" ||
    definitions.is_empty() ||
    definitions.length() != retentions.length() ||
    definitions.length() != computation_contract_cids.length() ||
    definitions.length() != input_relation_cids.length() ||
    definitions.length() != scope_cids.length() ||
    definitions.length() != effective_data_policy_cids.length() ||
    definitions.length() != authority_scope_cids.length() {
    return false
  }
  if contract_string(run_definition, "invocation_template_cid") !=
    contract_string(invocation, "invocation_template_cid") ||
    contract_string(run_definition, "invocation_template_cid") !=
    Some(admission.template.identity) ||
    contract_string(run_definition, "compiled_plan_cid") !=
    Some(admission.compiled_plan_cid) ||
    contract_string(run_definition, "authorization_context_cid") !=
    Some(admission.authorization_context_cid) ||
    contract_string(run_definition, "valid_until").map(fn(value) {
      value <= admission.expires_at
    }) !=
    Some(true) ||
    contract_string_from_value(
      admission.template.value,
      "program_definition_cid",
    ) !=
    Some(program_definition_cid) ||
    contract_string(request, "run_definition_cid") !=
    Some(run_definition.identity) ||
    contract_string(attempt, "run_definition_cid") !=
    Some(run_definition.identity) ||
    contract_string(attempt, "publication_request_cid") !=
    Some(request.identity) ||
    !publication_inventory_matches(request, definitions) {
    return false
  }
  let result_names : Array[String] = []
  let authority_scope_cid = contract_string(request, "authority_scope_cid")
  let metadata_policy_cid = contract_string(
    retentions[0],
    "metadata_retention_policy_cid",
  )
  let metadata_delete_by = contract_string(retentions[0], "metadata_delete_by")
  for index, definition in definitions {
    if definition.name != "result_definition" {
      return false
    }
    guard contract_string(definition, "result_name") is Some(name) else {
      return false
    }
    if result_names.contains(name) {
      return false
    }
    result_names.push(name)
    if contract_string(definition, "program_definition_cid") !=
      Some(program_definition_cid) {
      return false
    }
    if !valid_contract_cid(computation_contract_cids[index]) ||
      !input_relation_cids[index].all(valid_contract_cid) ||
      !valid_contract_cid(scope_cids[index]) ||
      !valid_contract_cid(effective_data_policy_cids[index]) ||
      !valid_contract_cid(authority_scope_cids[index]) ||
      contract_string(retentions[index], "effective_data_policy_cid") !=
      Some(effective_data_policy_cids[index]) ||
      contract_string(retentions[index], "metadata_retention_policy_cid") !=
      metadata_policy_cid ||
      contract_string(retentions[index], "metadata_delete_by") !=
      metadata_delete_by ||
      authority_scope_cid != Some(authority_scope_cids[index]) {
      return false
    }
  }
  retentions.all(fn(retention) {
    retention.name == "result_retention_policy" &&
    result_retention_intervals_valid(retention)
  })
}

///|
/// Issue the exact entry a Store may install atomically. This establishes no
/// success by itself; the Store still validates and persists the full chain.
pub fn issue_public_index_entry(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  durable_bindings : Array[PublicationContract],
  request : PublicationContract,
  attempt : PublicationContract,
  committed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationCommitIssuanceIssue] {
  for
    (contract, expected) in [
      (run_definition, "run_definition"),
      (invocation, "run_invocation"),
      (manifest, "result_manifest"),
      (receipt, "run_receipt"),
      (captured_run, "captured_run"),
      (request, "publication_request"),
      (attempt, "publication_attempt"),
    ] {
    if contract.name != expected {
      return Err(CommitIssuanceWrongContract)
    }
  }
  for
    (actual, expected, field) in [
      (
        contract_string(manifest, "run_definition_cid"),
        run_definition.identity,
        "manifest.run_definition_cid",
      ),
      (
        contract_string(manifest, "invocation_cid"),
        invocation.identity,
        "manifest.invocation_cid",
      ),
      (
        contract_string(request, "run_definition_cid"),
        run_definition.identity,
        "request.run_definition_cid",
      ),
      (
        contract_string(attempt, "publication_request_cid"),
        request.identity,
        "attempt.publication_request_cid",
      ),
      (
        contract_string(attempt, "run_definition_cid"),
        run_definition.identity,
        "attempt.run_definition_cid",
      ),
    ] {
    if actual != Some(expected) {
      return Err(CommitIssuanceReferenceMismatch(field))
    }
  }
  guard contract_string(request, "namespace_id") is Some(namespace_id) &&
    contract_string(request, "authority_scope_cid") is Some(authority_scope_cid) else {
    return Err(CommitIssuanceReferenceMismatch("request.authority"))
  }
  if durable_bindings.is_empty() {
    return Err(CommitIssuanceEmptyInventory)
  }
  let binding_cids : Array[String] = []
  for binding in durable_bindings {
    if binding.name != "durable_result_binding" {
      return Err(CommitIssuanceWrongContract)
    }
    if contract_string(binding, "run_definition_cid") !=
      Some(run_definition.identity) ||
      contract_string(binding, "invocation_cid") != Some(invocation.identity) {
      return Err(CommitIssuanceReferenceMismatch("durable_result_binding"))
    }
    if binding_cids.contains(binding.identity) {
      return Err(CommitIssuanceInventoryMismatch)
    }
    binding_cids.push(binding.identity)
  }
  binding_cids.sort_by(@canonical.compare_utf16)
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authority_scope_cid")
    @encode.string_value(writer, authority_scope_cid)
    @encode.key(writer, "captured_run_cid")
    @encode.string_value(writer, captured_run.identity)
    @encode.key(writer, "committed_at")
    @encode.string_value(writer, committed_at)
    @encode.key(writer, "durable_result_binding_cids")
    @encode.begin_array(writer)
    for identity in binding_cids {
      @encode.string_value(writer, identity)
    }
    @encode.end_array(writer)
    @encode.key(writer, "invocation_cid")
    @encode.string_value(writer, invocation.identity)
    @encode.key(writer, "publication_attempt_cid")
    @encode.string_value(writer, attempt.identity)
    @encode.key(writer, "publication_request_cid")
    @encode.string_value(writer, request.identity)
    @encode.key(writer, "result_manifest_cid")
    @encode.string_value(writer, manifest.identity)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, run_definition.identity)
    @encode.key(writer, "run_receipt_cid")
    @encode.string_value(writer, receipt.identity)
    @encode.key(writer, "namespace_id")
    @encode.string_value(writer, namespace_id)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-public-index-entry/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  finish_publication_body(
    "public_index_entry", writer, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// A later publication attempt may observe the same committed content even
/// though its attempt and commit time differ. Outcome, captured computation,
/// and physical Result bindings must remain exact; a changed chain cannot be
/// acknowledged as an idempotent commit.
pub fn public_index_same_committed_content(
  committed : PublicationContract,
  candidate : PublicationContract,
) -> Bool {
  if committed.name != "public_index_entry" ||
    candidate.name != "public_index_entry" {
    return false
  }
  for
    field in [
      "namespace_id", "authority_scope_cid", "run_definition_cid", "invocation_cid",
      "result_manifest_cid", "run_receipt_cid", "captured_run_cid", "publication_request_cid",
    ] {
    guard contract_string(committed, field) is Some(value) &&
      contract_string(candidate, field) == Some(value) else {
      return false
    }
  }
  match
    (
      contract_string_array(committed, "durable_result_binding_cids"),
      contract_string_array(candidate, "durable_result_binding_cids"),
    ) {
    (Some(left), Some(right)) => left == right
    _ => false
  }
}

///|
/// Derive the Store key for the one committed Manifest allowed for an exact
/// namespace_id, authority scope, and Run Definition. The key deliberately excludes
/// Invocation and attempt identities: changing either cannot create a second
/// committed publication for the same Run.
pub fn publication_index_scope_storage_key(
  namespace_id : String,
  authority_scope_cid : String,
  run_definition_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, PublicationCommitIssuanceIssue] {
  if namespace_id.is_empty() ||
    !valid_contract_cid(authority_scope_cid) ||
    !valid_contract_cid(run_definition_cid) {
    return Err(CommitIssuanceReferenceMismatch("index.authority"))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authority_scope_cid")
    @encode.string_value(writer, authority_scope_cid)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, run_definition_cid)
    @encode.key(writer, "namespace_id")
    @encode.string_value(writer, namespace_id)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-public-index-key/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  let body = @encode.finish(writer) catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  Ok(@sha.hex(@utf8.encode(body)))
}

///|
pub fn publication_index_storage_key(
  index : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, PublicationCommitIssuanceIssue] {
  if index.name != "public_index_entry" {
    return Err(CommitIssuanceWrongContract)
  }
  guard contract_string(index, "namespace_id") is Some(namespace_id) &&
    contract_string(index, "authority_scope_cid") is Some(authority_scope_cid) &&
    contract_string(index, "run_definition_cid") is Some(run_definition_cid) else {
    return Err(CommitIssuanceReferenceMismatch("index.authority"))
  }
  publication_index_scope_storage_key(
    namespace_id, authority_scope_cid, run_definition_cid, max_wire_bytes, max_nodes,
    max_depth,
  )
}

///|
/// Issue one append-only publication state record. Sequence and predecessor
/// are derived from the admitted prior record rather than caller counters.
pub fn issue_publication_record(
  attempt : PublicationContract,
  previous : PublicationContract?,
  state : String,
  observed_at : String,
  public_index_entry : PublicationContract?,
  failure_cid : String?,
  cleanup_owner_cids : Array[String],
  uncommitted_confirmed : Bool,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationCommitIssuanceIssue] {
  if attempt.name != "publication_attempt" {
    return Err(CommitIssuanceWrongContract)
  }
  let (sequence, prior_cid) = match previous {
    None => (0L, None)
    Some(prior) => {
      if prior.name != "publication_record" ||
        contract_string(prior, "publication_attempt_cid") !=
        Some(attempt.identity) {
        return Err(CommitIssuanceReferenceMismatch("prior_record_cid"))
      }
      guard contract_count(prior, "sequence") is Some(prior_sequence) else {
        return Err(CommitIssuanceReferenceMismatch("sequence"))
      }
      (prior_sequence + 1L, Some(prior.identity))
    }
  }
  match public_index_entry {
    Some(index) =>
      if index.name != "public_index_entry" ||
        contract_string(index, "publication_attempt_cid") !=
        Some(attempt.identity) {
        return Err(CommitIssuanceReferenceMismatch("public_index_entry_cid"))
      }
    None => ()
  }
  let owners = cleanup_owner_cids.copy()
  owners.sort()
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "cleanup_owner_cids")
    @encode.begin_array(writer)
    for owner in owners {
      @encode.string_value(writer, owner)
    }
    @encode.end_array(writer)
    match failure_cid {
      Some(value) => {
        @encode.key(writer, "failure_cid")
        @encode.string_value(writer, value)
      }
      None => ()
    }
    @encode.key(writer, "observed_at")
    @encode.string_value(writer, observed_at)
    match prior_cid {
      Some(value) => {
        @encode.key(writer, "prior_record_cid")
        @encode.string_value(writer, value)
      }
      None => ()
    }
    match public_index_entry {
      Some(value) => {
        @encode.key(writer, "public_index_entry_cid")
        @encode.string_value(writer, value.identity)
      }
      None => ()
    }
    @encode.key(writer, "publication_attempt_cid")
    @encode.string_value(writer, attempt.identity)
    @encode.key(writer, "sequence")
    @encode.number_value(writer, sequence.to_double())
    @encode.key(writer, "state")
    @encode.string_value(writer, state)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-publication-record/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  let record = match
    finish_publication_body(
      "publication_record", writer, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    validate_publication_record_transition(
      previous, record, uncommitted_confirmed,
    ) {
    Ok(_) => Ok(record)
    Err(_) => Err(CommitIssuanceReferenceMismatch("state_transition"))
  }
}
