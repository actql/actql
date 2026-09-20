///|
pub(all) enum DeliveryIssuanceIssue {
  DeliveryIssuanceWrongContract(String)
  DeliveryIssuanceReferenceMismatch(String)
  DeliveryIssuanceUnknownResult(String)
  DeliveryIssuanceDuplicateResult(String)
  DeliveryIssuanceUnsupportedFormat(String)
  DeliveryIssuanceInvalidLimit
  DeliveryIssuanceInvalidOutcome
  DeliveryIssuanceExpiredGrant
  DeliveryIssuanceEncoding
  DeliveryIssuanceContract(PublicationContractIssue)
  DeliveryIssuanceTransition(DeliveryTransitionIssue)
} derive(Eq, Debug)

///|
priv struct GrantedResult {
  name : String
  artifact_cid : String
}

///|
/// Physical facts observed by a Store adapter before one retained Result can
/// back a formal Delivery Attempt. The portable contract owner compares these
/// facts with the committed Manifest and durable representation binding.
pub(all) struct DeliveryPayloadFacts {
  store_authority_cid : String
  material_generation_cid : String
  logical_result_cid : String
  result_schema_cid : String
  ordering_evidence_cid : String
  codec_contract_cid : String
  result_fields : Array[String]
  result_schema_wire : String
  row_count : Int64
  byte_count : Int64
  physical_sha256 : String
}

///|
pub(all) struct DurableResultBindingRead {
  material_generation_cid : String
  result_schema_cid : String
  result_fields : Array[String]
}

///|
/// Exact durable references carried by one committed public index. This
/// projection lets Store adapters retrieve bodies without interpreting the
/// index contract themselves.
pub(all) struct PublicIndexRead {
  tenant_id : String
  authority_scope_cid : String
  run_definition_cid : String
  invocation_cid : String
  result_manifest_cid : String
  durable_result_binding_cids : Array[String]
}

///|
/// Portable resolution of one named Result to its exact durable generation.
/// The Store still opens and verifies physical bytes; this value owns the
/// cross-contract selection and binding meaning.
pub(all) struct CommittedResultRead {
  result_name : String
  result_artifact_cid : String
  result_definition_cid : String
  logical_result_cid : String
  result_schema_cid : String
  ordering_evidence_cid : String
  effective_retention_policy_cid : String
  durable_result_binding_cid : String
  material_generation_cid : String
  store_authority_cid : String
  codec_contract_cid : String
  result_fields : Array[String]
  row_count : Int64
  byte_count : Int64
  physical_sha256 : String
}

///|
fn delivery_format_rank(format : String) -> Int? {
  match format {
    "json" => Some(0)
    "jsonl" => Some(1)
    "csv" => Some(2)
    _ => None
  }
}

///|
fn delivery_serialization_version(format : String) -> String? {
  match format {
    "json" => Some("actql-json/0.1")
    "jsonl" => Some("actql-jsonl/0.1")
    "csv" => Some("actql-csv/0.1")
    _ => None
  }
}

///|
pub fn result_serialization_contract_cid(
  format : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, DeliveryIssuanceIssue] {
  guard delivery_serialization_version(format) is Some(version) else {
    return Err(DeliveryIssuanceUnsupportedFormat(format))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, version)
    @encode.end_object(writer)
  } catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  let wire = @encode.finish(writer) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  let value = match
    parse_contract_wire(wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(DeliveryIssuanceEncoding)
  }
  Ok(@json.cid_value(value, max_wire_bytes, max_nodes, max_depth)) catch {
    _ => Err(DeliveryIssuanceEncoding)
  }
}

///|
fn finish_delivery_body(
  name : String,
  writer : @encode.Writer,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, DeliveryIssuanceIssue] {
  let body = @encode.finish(writer) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  match
    seal_publication_contract(name, body, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => Ok(value)
    Err(issue) => Err(DeliveryIssuanceContract(issue))
  }
}

///|
fn manifest_result_artifact_cid(
  manifest : PublicationContract,
  name : String,
) -> String? {
  guard @json.object_field(manifest.value, "results") is Some(results) else {
    return None
  }
  guard @json.object_field(results, name) is Some(artifact) else { return None }
  optional_string(@json.object_field(artifact, "result_artifact_cid"))
}

///|
pub fn manifest_result_names(
  manifest : PublicationContract,
) -> Result[Array[String], DeliveryIssuanceIssue] {
  if manifest.name != "result_manifest" {
    return Err(DeliveryIssuanceWrongContract("result_manifest"))
  }
  guard @json.object_field(manifest.value, "results") is Some(results) &&
    object_fields(results) is Ok(fields) else {
    return Err(DeliveryIssuanceReferenceMismatch("results"))
  }
  let names = fields.map(field => field.0)
  names.sort_by(@canonical.compare_utf16)
  Ok(names)
}

///|
pub fn manifest_result_names_json(
  manifest : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, DeliveryIssuanceIssue] {
  let names = match manifest_result_names(manifest) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  try {
    @encode.begin_array(writer)
    for name in names {
      @encode.string_value(writer, name)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(DeliveryIssuanceEncoding)
  }
}

///|
pub fn result_read_definition_cid(
  manifest : PublicationContract,
  result_name : String,
) -> Result[String, DeliveryIssuanceIssue] {
  if manifest.name != "result_manifest" {
    return Err(DeliveryIssuanceWrongContract("result_manifest"))
  }
  guard @json.object_field(manifest.value, "results") is Some(results) &&
    @json.object_field(results, result_name) is Some(artifact) &&
    optional_string(@json.object_field(artifact, "result_definition_cid"))
    is Some(definition_cid) else {
    return Err(DeliveryIssuanceUnknownResult(result_name))
  }
  Ok(definition_cid)
}

///|
pub fn run_definition_run_id(
  run_definition : PublicationContract,
) -> Result[String, DeliveryIssuanceIssue] {
  if run_definition.name != "run_definition" {
    return Err(DeliveryIssuanceWrongContract("run_definition"))
  }
  match contract_string(run_definition, "run_id") {
    Some(value) => Ok(value)
    None => Err(DeliveryIssuanceReferenceMismatch("run_id"))
  }
}

///|
pub fn result_read_retention_policy_cid(
  manifest : PublicationContract,
  result_name : String,
) -> Result[String, DeliveryIssuanceIssue] {
  if manifest.name != "result_manifest" {
    return Err(DeliveryIssuanceWrongContract("result_manifest"))
  }
  guard @json.object_field(manifest.value, "results") is Some(results) &&
    @json.object_field(results, result_name) is Some(artifact) &&
    optional_string(
      @json.object_field(artifact, "effective_retention_policy_cid"),
    )
    is Some(retention_cid) else {
    return Err(DeliveryIssuanceUnknownResult(result_name))
  }
  Ok(retention_cid)
}

///|

///|
pub fn result_retention_intervals_valid(
  retention : PublicationContract,
) -> Bool {
  guard retention.name == "result_retention_policy" &&
    contract_string(retention, "available_until") is Some(available_until) &&
    contract_string(retention, "delete_by") is Some(delete_by) &&
    contract_string(retention, "extension_ceiling_at") is Some(ceiling) &&
    contract_string(retention, "metadata_delete_by") is Some(metadata_delete_by) &&
    valid_timestamp(available_until) &&
    valid_timestamp(delete_by) &&
    valid_timestamp(ceiling) &&
    valid_timestamp(metadata_delete_by) else {
    return false
  }
  available_until <= delete_by && delete_by <= metadata_delete_by
}

///|
fn retention_interval_state(
  retention : PublicationContract,
  observed_at : String,
) -> Result[String, DeliveryIssuanceIssue] {
  guard contract_string(retention, "available_until") is Some(available_until) &&
    contract_string(retention, "delete_by") is Some(delete_by) &&
    valid_timestamp(observed_at) &&
    result_retention_intervals_valid(retention) else {
    return Err(DeliveryIssuanceReferenceMismatch("retention_interval"))
  }
  if observed_at <= available_until {
    Ok("available")
  } else if observed_at < delete_by {
    Ok("retention_expired")
  } else {
    Ok("delete_due")
  }
}

///|
pub fn result_metadata_retention_state(
  retention : PublicationContract,
  observed_at : String,
) -> Result[String, DeliveryIssuanceIssue] {
  guard result_retention_intervals_valid(retention) &&
    valid_timestamp(observed_at) &&
    contract_string(retention, "metadata_delete_by") is Some(delete_by) else {
    return Err(DeliveryIssuanceReferenceMismatch("metadata_retention_interval"))
  }
  if observed_at < delete_by {
    Ok("retained")
  } else {
    Ok("delete_due")
  }
}

///|
pub fn result_read_availability(
  manifest : PublicationContract,
  result_name : String,
  retention : PublicationContract,
  observed_at : String,
) -> Result[String, DeliveryIssuanceIssue] {
  let expected = match result_read_retention_policy_cid(manifest, result_name) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if retention.name != "result_retention_policy" {
    return Err(DeliveryIssuanceWrongContract("result_retention_policy"))
  }
  if retention.identity != expected {
    return Err(
      DeliveryIssuanceReferenceMismatch("effective_retention_policy_cid"),
    )
  }
  retention_interval_state(retention, observed_at)
}

///|
fn retention_extension_valid(
  base : PublicationContract,
  extension : PublicationContract,
) -> Bool {
  if base.name != "result_retention_policy" ||
    extension.name != "result_retention_policy" {
    return false
  }
  for
    field in [
      "retention_contract_cid", "effective_data_policy_cid", "delete_by", "extension_ceiling_at",
      "metadata_retention_policy_cid", "metadata_delete_by", "clock_contract_cid",
    ] {
    if contract_string(base, field) != contract_string(extension, field) {
      return false
    }
  }
  guard contract_string(base, "available_until") is Some(base_until) &&
    contract_string(extension, "available_until") is Some(extended_until) &&
    contract_string(base, "delete_by") is Some(delete_by) &&
    contract_string(base, "extension_ceiling_at") is Some(ceiling) &&
    valid_timestamp(base_until) &&
    valid_timestamp(extended_until) &&
    valid_timestamp(delete_by) &&
    valid_timestamp(ceiling) else {
    return false
  }
  base_until <= extended_until &&
  extended_until <= delete_by &&
  extended_until <= ceiling
}

///|
pub fn issue_result_retention_extension(
  base : PublicationContract,
  available_until : String,
  admitted_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, DeliveryIssuanceIssue] {
  if base.name != "result_retention_policy" {
    return Err(DeliveryIssuanceWrongContract("result_retention_policy"))
  }
  guard contract_string(base, "available_until") is Some(base_until) &&
    contract_string(base, "delete_by") is Some(delete_by) &&
    contract_string(base, "extension_ceiling_at") is Some(ceiling) &&
    contract_string(base, "retention_contract_cid") is Some(contract_cid) &&
    contract_string(base, "effective_data_policy_cid") is Some(data_policy) &&
    contract_string(base, "metadata_retention_policy_cid")
    is Some(metadata_policy) &&
    contract_string(base, "metadata_delete_by") is Some(metadata_delete_by) &&
    contract_string(base, "clock_contract_cid") is Some(clock_contract) &&
    valid_timestamp(base_until) &&
    valid_timestamp(available_until) &&
    valid_timestamp(delete_by) &&
    valid_timestamp(ceiling) &&
    valid_timestamp(metadata_delete_by) &&
    valid_timestamp(admitted_at) &&
    result_retention_intervals_valid(base) &&
    base_until <= available_until &&
    available_until <= delete_by &&
    available_until <= ceiling &&
    admitted_at <= available_until &&
    admitted_at < delete_by else {
    return Err(DeliveryIssuanceReferenceMismatch("retention_extension"))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "available_until")
    @encode.string_value(writer, available_until)
    @encode.key(writer, "clock_contract_cid")
    @encode.string_value(writer, clock_contract)
    @encode.key(writer, "delete_by")
    @encode.string_value(writer, delete_by)
    @encode.key(writer, "effective_data_policy_cid")
    @encode.string_value(writer, data_policy)
    @encode.key(writer, "extension_ceiling_at")
    @encode.string_value(writer, ceiling)
    @encode.key(writer, "metadata_retention_policy_cid")
    @encode.string_value(writer, metadata_policy)
    @encode.key(writer, "metadata_delete_by")
    @encode.string_value(writer, metadata_delete_by)
    @encode.key(writer, "retention_contract_cid")
    @encode.string_value(writer, contract_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-result-retention-policy/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  finish_delivery_body(
    "result_retention_policy", writer, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
pub fn result_read_extended_availability(
  manifest : PublicationContract,
  result_name : String,
  base : PublicationContract,
  extension : PublicationContract,
  observed_at : String,
) -> Result[String, DeliveryIssuanceIssue] {
  let expected = match result_read_retention_policy_cid(manifest, result_name) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if base.name != "result_retention_policy" || base.identity != expected {
    return Err(
      DeliveryIssuanceReferenceMismatch("effective_retention_policy_cid"),
    )
  }
  if !retention_extension_valid(base, extension) {
    return Err(DeliveryIssuanceReferenceMismatch("retention_extension"))
  }
  retention_interval_state(extension, observed_at)
}

///|
pub fn result_retention_clock_contract_cid(
  retention : PublicationContract,
) -> Result[String, DeliveryIssuanceIssue] {
  if retention.name != "result_retention_policy" {
    return Err(DeliveryIssuanceWrongContract("result_retention_policy"))
  }
  match contract_string(retention, "clock_contract_cid") {
    Some(value) => Ok(value)
    None => Err(DeliveryIssuanceReferenceMismatch("clock_contract_cid"))
  }
}

///|
pub fn trusted_clock_not_before(
  previous : String?,
  observed_at : String,
) -> Bool {
  if !valid_timestamp(observed_at) {
    return false
  }
  match previous {
    Some(value) => valid_timestamp(value) && observed_at >= value
    None => true
  }
}

///|
fn validate_public_read_root(
  index : PublicationContract,
  manifest : PublicationContract,
) -> Result[Unit, DeliveryIssuanceIssue] {
  if index.name != "public_index_entry" {
    return Err(DeliveryIssuanceWrongContract("public_index_entry"))
  }
  if manifest.name != "result_manifest" {
    return Err(DeliveryIssuanceWrongContract("result_manifest"))
  }
  for
    (actual, expected, field) in [
      (
        contract_string(index, "result_manifest_cid"),
        manifest.identity,
        "result_manifest_cid",
      ),
      (
        contract_string(index, "run_definition_cid"),
        contract_string(manifest, "run_definition_cid").unwrap_or(""),
        "run_definition_cid",
      ),
      (
        contract_string(index, "invocation_cid"),
        contract_string(manifest, "invocation_cid").unwrap_or(""),
        "invocation_cid",
      ),
    ] {
    if actual != Some(expected) {
      return Err(DeliveryIssuanceReferenceMismatch(field))
    }
  }
  Ok(())
}

///|
fn emit_common_grant_fields(
  writer : @encode.Writer,
  index : PublicationContract,
  principal_id : String,
  purpose : String,
  data_ceiling_cid : String,
  max_bytes : Int,
  max_uses : Int,
  expires_at : String,
  authorization_context_cid : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, "authority_scope_cid")
  @encode.string_value(
    writer,
    contract_string(index, "authority_scope_cid").unwrap_or(""),
  )
  @encode.key(writer, "authorization_context_cid")
  @encode.string_value(writer, authorization_context_cid)
  @encode.key(writer, "data_ceiling_cid")
  @encode.string_value(writer, data_ceiling_cid)
  @encode.key(writer, "expires_at")
  @encode.string_value(writer, expires_at)
  @encode.key(writer, "max_bytes")
  @encode.number_value(writer, max_bytes.to_double())
  @encode.key(writer, "max_uses")
  @encode.number_value(writer, max_uses.to_double())
  @encode.key(writer, "principal_id")
  @encode.string_value(writer, principal_id)
  @encode.key(writer, "purpose")
  @encode.string_value(writer, purpose)
  @encode.key(writer, "result_manifest_cid")
  @encode.string_value(
    writer,
    contract_string(index, "result_manifest_cid").unwrap_or(""),
  )
  @encode.key(writer, "run_definition_cid")
  @encode.string_value(
    writer,
    contract_string(index, "run_definition_cid").unwrap_or(""),
  )
  @encode.key(writer, "tenant_id")
  @encode.string_value(
    writer,
    contract_string(index, "tenant_id").unwrap_or(""),
  )
}

///|
pub fn issue_manifest_read_grant(
  index : PublicationContract,
  manifest : PublicationContract,
  principal_id : String,
  purpose : String,
  data_ceiling_cid : String,
  max_bytes : Int,
  max_uses : Int,
  expires_at : String,
  authorization_context_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, DeliveryIssuanceIssue] {
  match validate_public_read_root(index, manifest) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if max_bytes < 0 || max_uses < 1 {
    return Err(DeliveryIssuanceInvalidLimit)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    emit_common_grant_fields(
      writer, index, principal_id, purpose, data_ceiling_cid, max_bytes, max_uses,
      expires_at, authorization_context_cid,
    )
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-manifest-read-grant/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  finish_delivery_body(
    "manifest_read_grant", writer, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
pub fn issue_result_read_grant(
  index : PublicationContract,
  manifest : PublicationContract,
  result_names : Array[String],
  formats : Array[String],
  principal_id : String,
  purpose : String,
  data_ceiling_cid : String,
  max_bytes : Int,
  max_uses : Int,
  expires_at : String,
  authorization_context_cid : String,
  egress_admission_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, DeliveryIssuanceIssue] {
  match validate_public_read_root(index, manifest) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if result_names.is_empty() ||
    formats.is_empty() ||
    max_bytes < 0 ||
    max_uses < 1 {
    return Err(DeliveryIssuanceInvalidLimit)
  }
  let results : Array[GrantedResult] = []
  for name in result_names {
    if results.any(result => result.name == name) {
      return Err(DeliveryIssuanceDuplicateResult(name))
    }
    guard manifest_result_artifact_cid(manifest, name) is Some(artifact) else {
      return Err(DeliveryIssuanceUnknownResult(name))
    }
    results.push({ name, artifact_cid: artifact, })
  }
  results.sort_by((left, right) => {
    @canonical.compare_utf16(left.name, right.name)
  })
  let ordered_formats = formats.copy()
  let seen_formats : Array[String] = []
  for format in ordered_formats {
    if seen_formats.contains(format) {
      return Err(DeliveryIssuanceUnsupportedFormat(format))
    }
    guard delivery_format_rank(format) is Some(_) else {
      return Err(DeliveryIssuanceUnsupportedFormat(format))
    }
    seen_formats.push(format)
  }
  ordered_formats.sort_by((left, right) => {
    delivery_format_rank(left)
    .unwrap()
    .compare(delivery_format_rank(right).unwrap())
  })
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    emit_common_grant_fields(
      writer, index, principal_id, purpose, data_ceiling_cid, max_bytes, max_uses,
      expires_at, authorization_context_cid,
    )
    @encode.key(writer, "egress_admission_cid")
    @encode.string_value(writer, egress_admission_cid)
    @encode.key(writer, "formats")
    @encode.begin_array(writer)
    for format in ordered_formats {
      @encode.string_value(writer, format)
    }
    @encode.end_array(writer)
    @encode.key(writer, "results")
    @encode.begin_array(writer)
    for result in results {
      @encode.begin_object(writer)
      @encode.key(writer, "result_artifact_cid")
      @encode.string_value(writer, result.artifact_cid)
      @encode.key(writer, "result_name")
      @encode.string_value(writer, result.name)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-result-read-grant/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  finish_delivery_body(
    "result_read_grant", writer, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
fn grant_has_result(
  grant : PublicationContract,
  name : String,
  artifact_cid : String,
) -> Bool {
  guard @json.object_field(grant.value, "results") is Some(value) else {
    return false
  }
  guard value is @json.Array(items) else { return false }
  @json.array_values(items).any(item => {
    optional_string(@json.object_field(item, "result_name")) == Some(name) &&
    optional_string(@json.object_field(item, "result_artifact_cid")) ==
    Some(artifact_cid)
  })
}

///|
fn grant_has_format(grant : PublicationContract, format : String) -> Bool {
  guard @json.object_field(grant.value, "formats") is Some(value) else {
    return false
  }
  guard value is @json.Array(items) else { return false }
  @json.array_values(items).any(item => {
    optional_string(Some(item)) == Some(format)
  })
}

///|
pub fn issue_delivery_attempt(
  index : PublicationContract,
  manifest : PublicationContract,
  grant : PublicationContract,
  result_name : String,
  format : String,
  attempt_id : String,
  requested_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, DeliveryIssuanceIssue] {
  match validate_public_read_root(index, manifest) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if grant.name != "result_read_grant" {
    return Err(DeliveryIssuanceWrongContract("result_read_grant"))
  }
  for
    (actual, expected, field) in [
      (
        contract_string(grant, "run_definition_cid"),
        contract_string(index, "run_definition_cid").unwrap_or(""),
        "grant.run_definition_cid",
      ),
      (
        contract_string(grant, "result_manifest_cid"),
        manifest.identity,
        "grant.result_manifest_cid",
      ),
      (
        contract_string(grant, "tenant_id"),
        contract_string(index, "tenant_id").unwrap_or(""),
        "grant.tenant_id",
      ),
      (
        contract_string(grant, "authority_scope_cid"),
        contract_string(index, "authority_scope_cid").unwrap_or(""),
        "grant.authority_scope_cid",
      ),
    ] {
    if actual != Some(expected) {
      return Err(DeliveryIssuanceReferenceMismatch(field))
    }
  }
  guard manifest_result_artifact_cid(manifest, result_name)
    is Some(artifact_cid) else {
    return Err(DeliveryIssuanceUnknownResult(result_name))
  }
  if !grant_has_result(grant, result_name, artifact_cid) {
    return Err(DeliveryIssuanceReferenceMismatch("grant.results"))
  }
  if !grant_has_format(grant, format) {
    return Err(DeliveryIssuanceUnsupportedFormat(format))
  }
  guard contract_string(grant, "expires_at") is Some(expires_at) else {
    return Err(DeliveryIssuanceReferenceMismatch("grant.expires_at"))
  }
  if !valid_timestamp(requested_at) || requested_at > expires_at {
    return Err(DeliveryIssuanceExpiredGrant)
  }
  let serialization_cid = match
    result_serialization_contract_cid(
      format, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "attempt_id")
    @encode.string_value(writer, attempt_id)
    @encode.key(writer, "requested_at")
    @encode.string_value(writer, requested_at)
    @encode.key(writer, "result_artifact_cid")
    @encode.string_value(writer, artifact_cid)
    @encode.key(writer, "result_manifest_cid")
    @encode.string_value(writer, manifest.identity)
    @encode.key(writer, "result_name")
    @encode.string_value(writer, result_name)
    @encode.key(writer, "result_read_grant_cid")
    @encode.string_value(writer, grant.identity)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(
      writer,
      contract_string(index, "run_definition_cid").unwrap_or(""),
    )
    @encode.key(writer, "serialization_contract_cid")
    @encode.string_value(writer, serialization_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-delivery-attempt/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  finish_delivery_body(
    "delivery_attempt", writer, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
pub fn delivery_result_definition_cid(
  manifest : PublicationContract,
  attempt : PublicationContract,
) -> Result[String, DeliveryIssuanceIssue] {
  if manifest.name != "result_manifest" {
    return Err(DeliveryIssuanceWrongContract("result_manifest"))
  }
  if attempt.name != "delivery_attempt" {
    return Err(DeliveryIssuanceWrongContract("delivery_attempt"))
  }
  if contract_string(attempt, "result_manifest_cid") != Some(manifest.identity) {
    return Err(DeliveryIssuanceReferenceMismatch("result_manifest_cid"))
  }
  guard contract_string(attempt, "result_name") is Some(result_name) else {
    return Err(DeliveryIssuanceReferenceMismatch("result_name"))
  }
  guard @json.object_field(manifest.value, "results") is Some(results) &&
    @json.object_field(results, result_name) is Some(artifact) &&
    optional_string(@json.object_field(artifact, "result_artifact_cid")) ==
    contract_string(attempt, "result_artifact_cid") &&
    optional_string(@json.object_field(artifact, "result_definition_cid"))
    is Some(result_definition_cid) else {
    return Err(DeliveryIssuanceReferenceMismatch("result_artifact_cid"))
  }
  Ok(result_definition_cid)
}

///|
fn contract_string_array(
  contract : PublicationContract,
  field : String,
) -> Array[String]? {
  guard @json.object_field(contract.value, field) is Some(value) else {
    return None
  }
  guard value is @json.Array(items) else { return None }
  let result : Array[String] = []
  for item in @json.array_values(items) {
    guard item is @json.String(value) else { return None }
    result.push(value)
  }
  Some(result)
}

///|
fn delivery_optional_count(value : @json.CanonicalValue?) -> Int64? {
  match value {
    Some(@json.Number(number)) => @scalar.read_safe_integer(number)
    _ => None
  }
}

///|
pub fn project_public_index_read(
  index : PublicationContract,
) -> Result[PublicIndexRead, DeliveryIssuanceIssue] {
  if index.name != "public_index_entry" {
    return Err(DeliveryIssuanceWrongContract("public_index_entry"))
  }
  guard contract_string(index, "tenant_id") is Some(tenant_id) &&
    contract_string(index, "authority_scope_cid") is Some(authority_scope_cid) &&
    contract_string(index, "run_definition_cid") is Some(run_definition_cid) &&
    contract_string(index, "invocation_cid") is Some(invocation_cid) &&
    contract_string(index, "result_manifest_cid") is Some(result_manifest_cid) &&
    contract_string_array(index, "durable_result_binding_cids")
    is Some(durable_result_binding_cids) &&
    !durable_result_binding_cids.is_empty() else {
    return Err(DeliveryIssuanceReferenceMismatch("public_index.references"))
  }
  Ok({
    tenant_id,
    authority_scope_cid,
    run_definition_cid,
    invocation_cid,
    result_manifest_cid,
    durable_result_binding_cids,
  })
}

///|
/// Select the one durable binding for a named committed Result. Every binding
/// listed by the index must be supplied exactly once; missing or additional
/// bodies are rejected before a physical generation can be opened.
pub fn project_committed_result_read(
  index : PublicationContract,
  manifest : PublicationContract,
  result_name : String,
  bindings : Array[PublicationContract],
) -> Result[CommittedResultRead, DeliveryIssuanceIssue] {
  match validate_public_read_root(index, manifest) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let index_read = match project_public_index_read(index) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @json.object_field(manifest.value, "results") is Some(results) &&
    @json.object_field(results, result_name) is Some(artifact) &&
    optional_string(@json.object_field(artifact, "result_artifact_cid"))
    is Some(result_artifact_cid) &&
    optional_string(@json.object_field(artifact, "result_definition_cid"))
    is Some(result_definition_cid) &&
    optional_string(@json.object_field(artifact, "logical_result_cid"))
    is Some(logical_result_cid) &&
    optional_string(@json.object_field(artifact, "result_schema_cid"))
    is Some(result_schema_cid) &&
    optional_string(@json.object_field(artifact, "ordering_evidence_cid"))
    is Some(ordering_evidence_cid) &&
    optional_string(
      @json.object_field(artifact, "effective_retention_policy_cid"),
    )
    is Some(effective_retention_policy_cid) &&
    delivery_optional_count(@json.object_field(artifact, "actual_row_count"))
    is Some(actual_row_count) else {
    return Err(DeliveryIssuanceUnknownResult(result_name))
  }
  if bindings.length() != index_read.durable_result_binding_cids.length() {
    return Err(DeliveryIssuanceReferenceMismatch("index.bindings"))
  }
  let supplied : Array[String] = []
  let mut selected : PublicationContract? = None
  for binding in bindings {
    if binding.name != "durable_result_binding" ||
      supplied.contains(binding.identity) ||
      !index_read.durable_result_binding_cids.contains(binding.identity) {
      return Err(DeliveryIssuanceReferenceMismatch("index.bindings"))
    }
    supplied.push(binding.identity)
    if contract_string(binding, "result_definition_cid") ==
      Some(result_definition_cid) {
      if selected is Some(_) {
        return Err(DeliveryIssuanceDuplicateResult(result_name))
      }
      selected = Some(binding)
    }
  }
  if index_read.durable_result_binding_cids.any(identity => {
      !supplied.contains(identity)
    }) {
    return Err(DeliveryIssuanceReferenceMismatch("index.bindings"))
  }
  guard selected is Some(binding) &&
    contract_string(binding, "run_definition_cid") ==
    Some(index_read.run_definition_cid) &&
    contract_string(binding, "invocation_cid") ==
    Some(index_read.invocation_cid) &&
    contract_string(binding, "logical_result_cid") == Some(logical_result_cid) &&
    contract_string(binding, "result_schema_cid") == Some(result_schema_cid) &&
    contract_string(binding, "ordering_evidence_cid") ==
    Some(ordering_evidence_cid) &&
    contract_string(binding, "effective_retention_policy_cid") ==
    Some(effective_retention_policy_cid) &&
    contract_count(binding, "row_count") == Some(actual_row_count) &&
    contract_string(binding, "material_generation_cid")
    is Some(material_generation_cid) &&
    contract_string(binding, "store_authority_cid") is Some(store_authority_cid) &&
    contract_string(binding, "codec_contract_cid") is Some(codec_contract_cid) &&
    contract_string_array(binding, "result_fields") is Some(result_fields) &&
    contract_count(binding, "byte_count") is Some(byte_count) &&
    contract_string(binding, "physical_sha256") is Some(physical_sha256) else {
    return Err(DeliveryIssuanceReferenceMismatch("binding.result"))
  }
  Ok({
    result_name,
    result_artifact_cid,
    result_definition_cid,
    logical_result_cid,
    result_schema_cid,
    ordering_evidence_cid,
    effective_retention_policy_cid,
    durable_result_binding_cid: binding.identity,
    material_generation_cid,
    store_authority_cid,
    codec_contract_cid,
    result_fields,
    row_count: actual_row_count,
    byte_count,
    physical_sha256,
  })
}

///|
pub fn project_durable_result_binding_read(
  binding : PublicationContract,
) -> Result[DurableResultBindingRead, DeliveryIssuanceIssue] {
  if binding.name != "durable_result_binding" {
    return Err(DeliveryIssuanceWrongContract("durable_result_binding"))
  }
  guard contract_string(binding, "material_generation_cid")
    is Some(material_generation_cid) &&
    contract_string(binding, "result_schema_cid") is Some(result_schema_cid) &&
    contract_string_array(binding, "result_fields") is Some(result_fields) else {
    return Err(DeliveryIssuanceReferenceMismatch("binding.physical_facts"))
  }
  Ok({ material_generation_cid, result_schema_cid, result_fields, })
}

///|
/// Verify that a Result schema wire is the exact canonical preimage of its
/// declared identity. Store adapters use this before persisting or returning
/// a schema, so restart recovery cannot substitute a non-canonical body.
pub fn validate_result_schema_wire(
  result_schema_cid : String,
  result_schema_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, DeliveryIssuanceIssue] {
  let schema = match
    parse_contract_wire(
      result_schema_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(DeliveryIssuanceEncoding)
  }
  let schema_cid = @json.cid_value(schema, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  let canonical_schema = @json.stringify_value(
    schema, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  if schema_cid != result_schema_cid || canonical_schema != result_schema_wire {
    return Err(DeliveryIssuanceReferenceMismatch("binding.result_schema"))
  }
  Ok(())
}

///|
/// Verify observed Store facts against one durable Result binding. This is
/// shared by publication commit and delivery so neither adapter may make a
/// semantic binding visible without opening the exact retained generation.
pub fn validate_durable_result_binding_facts(
  binding : PublicationContract,
  facts : DeliveryPayloadFacts,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, DeliveryIssuanceIssue] {
  if binding.name != "durable_result_binding" {
    return Err(DeliveryIssuanceWrongContract("durable_result_binding"))
  }
  for
    (field, expected) in [
      ("store_authority_cid", facts.store_authority_cid),
      ("material_generation_cid", facts.material_generation_cid),
      ("logical_result_cid", facts.logical_result_cid),
      ("result_schema_cid", facts.result_schema_cid),
      ("ordering_evidence_cid", facts.ordering_evidence_cid),
      ("codec_contract_cid", facts.codec_contract_cid),
      ("physical_sha256", facts.physical_sha256),
    ] {
    if contract_string(binding, field) != Some(expected) {
      return Err(DeliveryIssuanceReferenceMismatch("binding." + field))
    }
  }
  if contract_count(binding, "row_count") != Some(facts.row_count) ||
    contract_count(binding, "byte_count") != Some(facts.byte_count) ||
    contract_string_array(binding, "result_fields") != Some(facts.result_fields) {
    return Err(DeliveryIssuanceReferenceMismatch("binding.physical_facts"))
  }
  validate_result_schema_wire(
    facts.result_schema_cid,
    facts.result_schema_wire,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Verify that an exact retained generation is the durable representation of
/// the committed Result selected by a Delivery Attempt. This is a semantic
/// check; opening the generation and verifying its physical digest remain
/// Store adapter effects.
pub fn validate_delivery_payload_binding(
  index : PublicationContract,
  manifest : PublicationContract,
  attempt : PublicationContract,
  binding : PublicationContract,
  facts : DeliveryPayloadFacts,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, DeliveryIssuanceIssue] {
  match validate_public_read_root(index, manifest) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if attempt.name != "delivery_attempt" {
    return Err(DeliveryIssuanceWrongContract("delivery_attempt"))
  }
  if binding.name != "durable_result_binding" {
    return Err(DeliveryIssuanceWrongContract("durable_result_binding"))
  }
  if contract_string(attempt, "result_manifest_cid") != Some(manifest.identity) ||
    contract_string(attempt, "run_definition_cid") !=
    contract_string(index, "run_definition_cid") {
    return Err(DeliveryIssuanceReferenceMismatch("delivery_attempt"))
  }
  guard contract_string(attempt, "result_name") is Some(result_name) &&
    @json.object_field(manifest.value, "results") is Some(results) &&
    @json.object_field(results, result_name) is Some(artifact) else {
    return Err(DeliveryIssuanceReferenceMismatch("delivery_result"))
  }
  let expected_definition = optional_string(
    @json.object_field(artifact, "result_definition_cid"),
  )
  let expected_logical = optional_string(
    @json.object_field(artifact, "logical_result_cid"),
  )
  let expected_schema = optional_string(
    @json.object_field(artifact, "result_schema_cid"),
  )
  let expected_ordering = optional_string(
    @json.object_field(artifact, "ordering_evidence_cid"),
  )
  let expected_retention = optional_string(
    @json.object_field(artifact, "effective_retention_policy_cid"),
  )
  let expected_rows = delivery_optional_count(
    @json.object_field(artifact, "actual_row_count"),
  )
  for
    (actual, expected, field) in [
      (
        contract_string(binding, "run_definition_cid"),
        contract_string(index, "run_definition_cid"),
        "binding.run_definition_cid",
      ),
      (
        contract_string(binding, "invocation_cid"),
        contract_string(index, "invocation_cid"),
        "binding.invocation_cid",
      ),
      (
        contract_string(binding, "result_definition_cid"),
        expected_definition,
        "binding.result_definition_cid",
      ),
      (
        contract_string(binding, "logical_result_cid"),
        expected_logical,
        "binding.logical_result_cid",
      ),
      (
        contract_string(binding, "result_schema_cid"),
        expected_schema,
        "binding.result_schema_cid",
      ),
      (
        contract_string(binding, "ordering_evidence_cid"),
        expected_ordering,
        "binding.ordering_evidence_cid",
      ),
      (
        contract_string(binding, "effective_retention_policy_cid"),
        expected_retention,
        "binding.effective_retention_policy_cid",
      ),
    ] {
    if actual != expected {
      return Err(DeliveryIssuanceReferenceMismatch(field))
    }
  }
  if expected_logical != Some(facts.logical_result_cid) ||
    expected_schema != Some(facts.result_schema_cid) ||
    expected_ordering != Some(facts.ordering_evidence_cid) ||
    expected_rows != Some(facts.row_count) {
    return Err(DeliveryIssuanceReferenceMismatch("binding.physical_facts"))
  }
  validate_durable_result_binding_facts(
    binding, facts, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
pub fn result_read_grant_allows_bytes(
  grant : PublicationContract,
  byte_count : Int,
) -> Bool {
  if grant.name != "result_read_grant" || byte_count < 0 {
    return false
  }
  contract_count(grant, "max_bytes")
  .map(max_bytes => byte_count.to_int64() <= max_bytes)
  .unwrap_or(false)
}

///|
pub fn manifest_read_grant_allows_bytes(
  grant : PublicationContract,
  byte_count : Int,
) -> Bool {
  if grant.name != "manifest_read_grant" || byte_count < 0 {
    return false
  }
  contract_count(grant, "max_bytes")
  .map(max_bytes => byte_count.to_int64() <= max_bytes)
  .unwrap_or(false)
}

///|
pub fn manifest_read_grant_valid_at(
  grant : PublicationContract,
  observed_at : String,
) -> Bool {
  grant.name == "manifest_read_grant" &&
  valid_timestamp(observed_at) &&
  contract_string(grant, "expires_at")
  .map(expires_at => observed_at <= expires_at)
  .unwrap_or(false)
}

///|
pub fn result_read_grant_valid_at(
  grant : PublicationContract,
  observed_at : String,
) -> Bool {
  grant.name == "result_read_grant" &&
  valid_timestamp(observed_at) &&
  contract_string(grant, "expires_at")
  .map(expires_at => observed_at <= expires_at)
  .unwrap_or(false)
}

///|
pub fn issue_result_delivery_receipt(
  index : PublicationContract,
  manifest : PublicationContract,
  grant : PublicationContract,
  attempt : PublicationContract,
  delivered_byte_count : Int,
  delivered_sha256 : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, DeliveryIssuanceIssue] {
  match validate_public_read_root(index, manifest) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if grant.name != "result_read_grant" {
    return Err(DeliveryIssuanceWrongContract("result_read_grant"))
  }
  if attempt.name != "delivery_attempt" {
    return Err(DeliveryIssuanceWrongContract("delivery_attempt"))
  }
  if delivered_byte_count < 0 ||
    contract_string(attempt, "result_read_grant_cid") != Some(grant.identity) ||
    contract_string(attempt, "run_definition_cid") !=
    contract_string(index, "run_definition_cid") ||
    contract_string(attempt, "result_manifest_cid") != Some(manifest.identity) {
    return Err(DeliveryIssuanceReferenceMismatch("delivery_attempt"))
  }
  guard contract_string(attempt, "result_name") is Some(result_name) &&
    contract_string(attempt, "result_artifact_cid") is Some(artifact_cid) &&
    contract_string(attempt, "serialization_contract_cid")
    is Some(serialization_cid) &&
    contract_string(index, "invocation_cid") is Some(invocation_cid) &&
    contract_string(grant, "authorization_context_cid")
    is Some(authorization_context_cid) &&
    contract_string(grant, "egress_admission_cid") is Some(egress_admission_cid) else {
    return Err(DeliveryIssuanceReferenceMismatch("delivery_receipt"))
  }
  if !grant_has_result(grant, result_name, artifact_cid) ||
    manifest_result_artifact_cid(manifest, result_name) != Some(artifact_cid) {
    return Err(DeliveryIssuanceReferenceMismatch("delivery_result"))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authorization_context_cid")
    @encode.string_value(writer, authorization_context_cid)
    @encode.key(writer, "delivered_byte_count")
    @encode.number_value(writer, delivered_byte_count.to_double())
    @encode.key(writer, "delivered_sha256")
    @encode.string_value(writer, delivered_sha256)
    @encode.key(writer, "egress_admission_cid")
    @encode.string_value(writer, egress_admission_cid)
    @encode.key(writer, "invocation_cid")
    @encode.string_value(writer, invocation_cid)
    @encode.key(writer, "result_artifact_cid")
    @encode.string_value(writer, artifact_cid)
    @encode.key(writer, "result_manifest_cid")
    @encode.string_value(writer, manifest.identity)
    @encode.key(writer, "result_name")
    @encode.string_value(writer, result_name)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(
      writer,
      contract_string(index, "run_definition_cid").unwrap_or(""),
    )
    @encode.key(writer, "serialization_contract_cid")
    @encode.string_value(writer, serialization_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-result-delivery-receipt/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  finish_delivery_body(
    "result_delivery_receipt", writer, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
fn validate_delivery_receipt_binding(
  attempt : PublicationContract,
  receipt : PublicationContract,
  confirmed_byte_count : Int64,
  delivered_sha256 : String,
) -> Result[Unit, DeliveryIssuanceIssue] {
  if receipt.name != "result_delivery_receipt" {
    return Err(DeliveryIssuanceWrongContract("result_delivery_receipt"))
  }
  for
    (receipt_field, attempt_field) in [
      ("run_definition_cid", "run_definition_cid"),
      ("result_manifest_cid", "result_manifest_cid"),
      ("result_name", "result_name"),
      ("result_artifact_cid", "result_artifact_cid"),
      ("serialization_contract_cid", "serialization_contract_cid"),
    ] {
    if contract_string(receipt, receipt_field) !=
      contract_string(attempt, attempt_field) {
      return Err(DeliveryIssuanceReferenceMismatch("delivery_receipt"))
    }
  }
  if contract_count(receipt, "delivered_byte_count") !=
    Some(confirmed_byte_count) ||
    contract_string(receipt, "delivered_sha256") != Some(delivered_sha256) {
    return Err(DeliveryIssuanceReferenceMismatch("delivery_receipt"))
  }
  Ok(())
}

///|
pub fn validate_delivery_success_evidence(
  attempt : PublicationContract,
  receipt : PublicationContract,
  record : PublicationContract,
) -> Result[Unit, DeliveryIssuanceIssue] {
  if attempt.name != "delivery_attempt" {
    return Err(DeliveryIssuanceWrongContract("delivery_attempt"))
  }
  if record.name != "delivery_record" ||
    contract_string(record, "state") != Some("succeeded") ||
    contract_string(record, "delivery_attempt_cid") != Some(attempt.identity) ||
    contract_string(record, "result_delivery_receipt_cid") !=
    Some(receipt.identity) {
    return Err(DeliveryIssuanceReferenceMismatch("delivery_record"))
  }
  guard contract_count(record, "confirmed_byte_count") is Some(byte_count) &&
    contract_string(record, "delivered_sha256") is Some(delivered_sha256) else {
    return Err(DeliveryIssuanceReferenceMismatch("delivery_record"))
  }
  validate_delivery_receipt_binding(
    attempt, receipt, byte_count, delivered_sha256,
  )
}

///|
pub fn issue_delivery_record(
  attempt : PublicationContract,
  previous : PublicationContract?,
  state : String,
  confirmed_byte_count : Int,
  exposure : String,
  possible_unconfirmed_max_bytes : Int?,
  delivered_sha256 : String?,
  receipt : PublicationContract?,
  failure_cid : String?,
  observed_at : String,
  cleanup_owner_cids : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, DeliveryIssuanceIssue] {
  if attempt.name != "delivery_attempt" {
    return Err(DeliveryIssuanceWrongContract("delivery_attempt"))
  }
  if confirmed_byte_count < 0 {
    return Err(DeliveryIssuanceInvalidLimit)
  }
  let (sequence, prior_cid) = match previous {
    None => (0L, None)
    Some(value) => {
      if value.name != "delivery_record" ||
        contract_string(value, "delivery_attempt_cid") != Some(attempt.identity) {
        return Err(DeliveryIssuanceReferenceMismatch("prior_record_cid"))
      }
      guard contract_count(value, "sequence") is Some(sequence) else {
        return Err(DeliveryIssuanceReferenceMismatch("sequence"))
      }
      (sequence + 1L, Some(value.identity))
    }
  }
  match receipt {
    Some(value) => {
      if state != "succeeded" || delivered_sha256 is None {
        return Err(DeliveryIssuanceInvalidOutcome)
      }
      match
        validate_delivery_receipt_binding(
          attempt,
          value,
          confirmed_byte_count.to_int64(),
          delivered_sha256.unwrap(),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    None =>
      if state == "succeeded" {
        return Err(DeliveryIssuanceInvalidOutcome)
      }
  }
  let owners = cleanup_owner_cids.copy()
  owners.sort_by(@canonical.compare_utf16)
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "cleanup_owner_cids")
    @encode.begin_array(writer)
    for owner in owners {
      @encode.string_value(writer, owner)
    }
    @encode.end_array(writer)
    @encode.key(writer, "confirmed_byte_count")
    @encode.number_value(writer, confirmed_byte_count.to_double())
    match delivered_sha256 {
      Some(value) => {
        @encode.key(writer, "delivered_sha256")
        @encode.string_value(writer, value)
      }
      None => ()
    }
    @encode.key(writer, "delivery_attempt_cid")
    @encode.string_value(writer, attempt.identity)
    @encode.key(writer, "exposure")
    @encode.string_value(writer, exposure)
    match failure_cid {
      Some(value) => {
        @encode.key(writer, "failure_cid")
        @encode.string_value(writer, value)
      }
      None => ()
    }
    @encode.key(writer, "observed_at")
    @encode.string_value(writer, observed_at)
    match possible_unconfirmed_max_bytes {
      Some(value) => {
        @encode.key(writer, "possible_unconfirmed_max_bytes")
        @encode.number_value(writer, value.to_double())
      }
      None => ()
    }
    match prior_cid {
      Some(value) => {
        @encode.key(writer, "prior_record_cid")
        @encode.string_value(writer, value)
      }
      None => ()
    }
    match receipt {
      Some(value) => {
        @encode.key(writer, "result_delivery_receipt_cid")
        @encode.string_value(writer, value.identity)
      }
      None => ()
    }
    @encode.key(writer, "sequence")
    @encode.number_value(writer, sequence.to_double())
    @encode.key(writer, "state")
    @encode.string_value(writer, state)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-delivery-record/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  let record = match
    finish_delivery_body(
      "delivery_record", writer, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match validate_delivery_record_transition(previous, record) {
    Ok(_) => Ok(record)
    Err(issue) => Err(DeliveryIssuanceTransition(issue))
  }
}
