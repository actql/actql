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
