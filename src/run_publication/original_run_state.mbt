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
  if original != wire ||
    !validate_generated_protocol_shape(
      "run_state", value, true, max_bytes, max_nodes, max_depth,
    ) {
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
