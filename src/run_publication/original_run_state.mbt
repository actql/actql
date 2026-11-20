///|
/// Validate retained unpublished metadata without manufacturing a Manifest or
/// a physical-stop witness. Only the original Host can establish the facts
/// before saving; restoration validates their closed immutable DATA domain.
pub fn validate_original_unpublished_run_state(
  definition : PublicationContract,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RunOutcomeStatus, PublicationContractIssue] {
  if definition.name != "run_definition" {
    return Err(InvalidField("run_definition"))
  }
  let value = match
    parse_contract_wire(wire, max_bytes, max_nodes, max_depth, data_keys=true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original = @json.stringify_value(value, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  if original != wire ||
    !validate_generated_protocol_shape(
      "run_state", value, true, max_bytes, max_nodes, max_depth,
    ) {
    return Err(InvalidWire)
  }
  guard contract_string_from_value(value, "run_id") ==
    contract_string(definition, "run_id") &&
    contract_string_from_value(value, "status") is Some(text) &&
    read_run_outcome_status(text) is Some(status) &&
    @json.object_field(value, "result_available") is Some(@json.Bool(false)) &&
    @json.object_field(value, "result_availability") is Some(availability) &&
    object_fields(availability) is Ok(fields) &&
    @json.object_field(value, "next_action") is Some(next) else {
    return Err(InvalidField("run_state"))
  }
  if status == Succeeded || status == WaitingCheckpoint || status == Resuming {
    return Err(InvalidField("status"))
  }
  let names : Array[String] = []
  let observations : Array[ResultAvailability] = []
  for (name, item) in fields {
    if contract_string_from_value(item, "state") != Some("unavailable") ||
      contract_string_from_value(item, "reason") != Some("not_published") {
      return Err(InvalidField("result_availability"))
    }
    names.push(name)
    observations.push({ name, state: Unavailable, reason: NotPublished, })
  }
  let action = if status == NeedsReconciliation {
    if contract_string_from_value(next, "kind") != Some("reconcile_run") {
      return Err(InvalidField("next_action"))
    }
    ReconcileRun
  } else {
    if contract_string_from_value(next, "kind") != Some("none") {
      return Err(InvalidField("next_action"))
    }
    NoAction
  }
  match validate_run_state(status, names, observations, false, action, false) {
    Ok(_) => Ok(status)
    Err(_) => Err(InvalidField("run_state"))
  }
}

///|
/// Validate the original succeeded observation, without inventing a control
/// revision or availability. Declared names come from the original Manifest,
/// never from the incoming observation. This admits metadata, not permission.
pub fn validate_original_succeeded_run_state(
  definition : PublicationContract,
  manifest : PublicationContract,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, PublicationContractIssue] {
  validate_original_succeeded_run_state_body(
    definition, manifest, wire, max_bytes, max_nodes, max_depth, false,
  )
}

///|
/// Historical custody only. An absent journal revision is never issued,
/// persisted as zero, or admitted as current public RunState by this reader.
/// All original bytes, Run/Manifest joins and state laws remain mandatory.
pub fn validate_historical_original_succeeded_run_state(
  definition : PublicationContract,
  manifest : PublicationContract,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, PublicationContractIssue] {
  validate_original_succeeded_run_state_body(
    definition, manifest, wire, max_bytes, max_nodes, max_depth, true,
  )
}

///|
fn validate_original_succeeded_run_state_body(
  definition : PublicationContract,
  manifest : PublicationContract,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  historical : Bool,
) -> Result[Unit, PublicationContractIssue] {
  if definition.name != "run_definition" ||
    manifest.name != "result_manifest" ||
    contract_string(manifest, "run_definition_cid") != Some(definition.identity) {
    return Err(InvalidField("run_definition"))
  }
  let value = match
    parse_contract_wire(wire, max_bytes, max_nodes, max_depth, data_keys=true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original = @json.stringify_value(value, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  if original != wire {
    return Err(InvalidWire)
  }
  let shape = if historical && @json.object_field(value, "revision") is None {
    validate_historical_run_state_shape(value, max_bytes, max_nodes, max_depth)
  } else {
    validate_generated_protocol_shape(
      "run_state", value, true, max_bytes, max_nodes, max_depth,
    )
  }
  if !shape {
    return Err(InvalidWire)
  }
  if contract_string_from_value(value, "status") != Some("succeeded") ||
    contract_string_from_value(value, "run_id") !=
    contract_string(definition, "run_id") {
    return Err(InvalidField("run_state"))
  }
  let declared = match manifest_result_names(manifest) {
    Ok(value) => value
    Err(_) => return Err(InvalidField("result_manifest"))
  }
  guard @json.object_field(value, "result_availability") is Some(availability) &&
    object_fields(availability) is Ok(fields) &&
    @json.object_field(value, "result_available") is Some(@json.Bool(aggregate)) &&
    @json.object_field(value, "next_action") is Some(next) else {
    return Err(InvalidField("run_state"))
  }
  let observations : Array[ResultAvailability] = []
  for (name, item) in fields {
    let state = match contract_string_from_value(item, "state") {
      Some("available") => Available
      Some("unavailable") => Unavailable
      Some("unknown") => Unknown
      _ => return Err(InvalidField("state"))
    }
    let reason = match contract_string_from_value(item, "reason") {
      Some("confirmed_present") => ConfirmedPresent
      Some("retention_expired") => RetentionExpired
      Some("deleted") => Deleted
      Some("policy_unavailable") => PolicyUnavailable
      Some("integrity_failed") => IntegrityFailed
      Some("not_published") => NotPublished
      Some("store_query_failed") => StoreQueryFailed
      Some("clock_uncertain") => ClockUncertain
      Some("verification_pending") => VerificationPending
      _ => return Err(InvalidField("reason"))
    }
    observations.push({ name, state, reason, })
  }
  let targets : Array[String] = []
  if @json.object_field(next, "results") is Some(@json.Array(items)) {
    for index in 0..<@json.array_count(items) {
      let item = @json.array_at(items, index).unwrap()
      guard item is @json.String(name) else {
        return Err(InvalidField("results"))
      }
      targets.push(name)
    }
  }
  let action = match contract_string_from_value(next, "kind") {
    Some("none") => NoAction
    Some("read_result") => ReadResult(targets)
    Some("refresh_availability") => RefreshAvailability(targets)
    _ => return Err(InvalidField("next_action"))
  }
  match
    validate_run_state(
      Succeeded,
      declared,
      observations,
      aggregate,
      action,
      false,
    ) {
    Ok(_) => Ok(())
    Err(_) => Err(InvalidField("run_state"))
  }
}
