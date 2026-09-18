///|
/// Closed Run-publication contract admitted and canonically identified by the
/// portable core. Environment adapters may persist `wire`; they do not decide
/// whether its shape, conditional fields, or self identity are valid.
struct PublicationContract {
  name : String
  identity_field : String
  identity : String
  wire : String
  value : @json.CanonicalValue
}

///|
pub(all) enum PublicationContractIssue {
  UnknownContract
  InvalidLimits
  InvalidWire
  InvalidObject
  MissingField(String)
  UnknownField(String)
  InvalidField(String)
  IdentityAlreadyPresent
  IdentityMissing
  IdentityMismatch
  ConditionalField(String)
  Encoding
} derive(Eq, Debug)

///|
pub(all) enum PublicationTransitionIssue {
  WrongContract
  AttemptMismatch
  SequenceMismatch
  PriorRecordMismatch
  StateMismatch
  UncommittedNotConfirmed
} derive(Eq, Debug)

///|
pub(all) enum DeliveryTransitionIssue {
  DeliveryWrongContract
  DeliveryAttemptMismatch
  DeliverySequenceMismatch
  DeliveryPriorRecordMismatch
  DeliveryStateMismatch
  ConfirmedBytesDecreased
} derive(Eq, Debug)

///|
priv enum FieldRule {
  Exact(String)
  Cid
  Digest
  Timestamp
  NonemptyText
  SafeCount
  Choice(Array[String])
  CidList
  Inventory
  ResultList
  FormatList
}

///|
priv struct FieldSpec {
  name : String
  rule : FieldRule
  required : Bool
}

///|
priv struct ContractSpec {
  name : String
  version : String
  identity : String
  fields : Array[FieldSpec]
}

///|
fn required(name : String, rule : FieldRule) -> FieldSpec {
  { name, rule, required: true, }
}

///|
fn optional(name : String, rule : FieldRule) -> FieldSpec {
  { name, rule, required: false, }
}

///|
fn common_grant_fields() -> Array[FieldSpec] {
  [
    required("tenant_id", NonemptyText),
    required("authority_scope_cid", Cid),
    required("principal_id", NonemptyText),
    required("run_definition_cid", Cid),
    required("result_manifest_cid", Cid),
    required("purpose", NonemptyText),
    required("data_ceiling_cid", Cid),
    required("max_bytes", SafeCount),
    required("max_uses", SafeCount),
    required("expires_at", Timestamp),
    required("authorization_context_cid", Cid),
  ]
}

///|
fn contract_spec(name : String) -> ContractSpec? {
  match name {
    "result_definition" =>
      Some({
        name,
        version: "actql-result-definition/0.1",
        identity: "result_definition_cid",
        fields: [
          required("program_definition_cid", Cid),
          required("result_name", NonemptyText),
        ],
      })
    "run_invocation" =>
      Some({
        name,
        version: "actql-run-invocation/0.1",
        identity: "invocation_cid",
        fields: [
          required("invocation_template_cid", Cid),
          required("observation_set_cid", Cid),
        ],
      })
    "result_retention_policy" =>
      Some({
        name,
        version: "actql-result-retention-policy/0.1",
        identity: "effective_retention_policy_cid",
        fields: [
          required("retention_contract_cid", Cid),
          required("effective_data_policy_cid", Cid),
          required("available_until", Timestamp),
          required("delete_by", Timestamp),
          required("extension_ceiling_at", Timestamp),
          required("metadata_retention_policy_cid", Cid),
          required("clock_contract_cid", Cid),
        ],
      })
    "durable_result_binding" =>
      Some({
        name,
        version: "actql-durable-result-binding/0.1",
        identity: "durable_result_binding_cid",
        fields: [
          required("run_definition_cid", Cid),
          required("result_definition_cid", Cid),
          required("invocation_cid", Cid),
          required("logical_result_cid", Cid),
          required("result_schema_cid", Cid),
          required("ordering_evidence_cid", Cid),
          required("codec_contract_cid", Cid),
          required("material_generation_cid", Cid),
          required("store_authority_cid", Cid),
          required("effective_retention_policy_cid", Cid),
          required("row_count", SafeCount),
          required("byte_count", SafeCount),
          required("physical_sha256", Digest),
        ],
      })
    "publication_request" =>
      Some({
        name,
        version: "actql-publication-request/0.1",
        identity: "publication_request_cid",
        fields: [
          required("tenant_id", NonemptyText),
          required("authority_scope_cid", Cid),
          required("run_definition_cid", Cid),
          required("inventory", Inventory),
          required("publication_policy_cid", Cid),
          required("publication_target_cid", Cid),
          required("requested_at", Timestamp),
        ],
      })
    "publication_attempt" =>
      Some({
        name,
        version: "actql-publication-attempt/0.1",
        identity: "publication_attempt_cid",
        fields: [
          required("publication_request_cid", Cid),
          required("run_definition_cid", Cid),
          required("attempt_id", NonemptyText),
          required("fence_cid", Cid),
          optional("external_idempotency_key", NonemptyText),
          required("started_at", Timestamp),
        ],
      })
    "publication_record" =>
      Some({
        name,
        version: "actql-publication-record/0.1",
        identity: "publication_record_cid",
        fields: [
          required("publication_attempt_cid", Cid),
          optional("prior_record_cid", Cid),
          required("sequence", SafeCount),
          required(
            "state",
            Choice([
              "preparing", "committing", "publication_unknown", "succeeded", "failed",
              "cancelled",
            ]),
          ),
          required("observed_at", Timestamp),
          optional("public_index_entry_cid", Cid),
          optional("failure_cid", Cid),
          required("cleanup_owner_cids", CidList),
        ],
      })
    "manifest_read_grant" => {
      let fields = common_grant_fields()
      Some({
        name,
        version: "actql-manifest-read-grant/0.1",
        identity: "manifest_read_grant_cid",
        fields,
      })
    }
    "result_read_grant" => {
      let fields = common_grant_fields()
      fields.push(required("results", ResultList))
      fields.push(required("formats", FormatList))
      fields.push(required("egress_admission_cid", Cid))
      Some({
        name,
        version: "actql-result-read-grant/0.1",
        identity: "result_read_grant_cid",
        fields,
      })
    }
    "delivery_attempt" =>
      Some({
        name,
        version: "actql-delivery-attempt/0.1",
        identity: "delivery_attempt_cid",
        fields: [
          required("attempt_id", NonemptyText),
          required("result_read_grant_cid", Cid),
          required("run_definition_cid", Cid),
          required("result_manifest_cid", Cid),
          required("result_name", NonemptyText),
          required("result_artifact_cid", Cid),
          required("serialization_contract_cid", Cid),
          required("requested_at", Timestamp),
        ],
      })
    "delivery_record" =>
      Some({
        name,
        version: "actql-delivery-record/0.1",
        identity: "delivery_record_cid",
        fields: [
          required("delivery_attempt_cid", Cid),
          optional("prior_record_cid", Cid),
          required("sequence", SafeCount),
          required(
            "state",
            Choice(["streaming", "succeeded", "failed", "cancelled"]),
          ),
          required("confirmed_byte_count", SafeCount),
          required("exposure", Choice(["exact", "unknown_additional"])),
          optional("possible_unconfirmed_max_bytes", SafeCount),
          optional("delivered_sha256", Digest),
          optional("result_delivery_receipt_cid", Cid),
          optional("failure_cid", Cid),
          required("observed_at", Timestamp),
          required("cleanup_owner_cids", CidList),
        ],
      })
    "public_index_entry" =>
      Some({
        name,
        version: "actql-public-index-entry/0.1",
        identity: "public_index_entry_cid",
        fields: [
          required("tenant_id", NonemptyText),
          required("authority_scope_cid", Cid),
          required("run_definition_cid", Cid),
          required("invocation_cid", Cid),
          required("result_manifest_cid", Cid),
          required("run_receipt_cid", Cid),
          required("captured_run_cid", Cid),
          required("publication_request_cid", Cid),
          required("publication_attempt_cid", Cid),
          required("committed_at", Timestamp),
        ],
      })
    _ => None
  }
}

///|
fn valid_hex(value : String, start : Int, end : Int) -> Bool {
  for index = start; index < end; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn valid_contract_cid(value : String) -> Bool {
  value.length() == 71 && value.has_prefix("sha256:") && valid_hex(value, 7, 71)
}

///|
fn valid_digest(value : String) -> Bool {
  value.length() == 64 && valid_hex(value, 0, 64)
}

///|
fn ascii_digit(value : String, index : Int) -> Bool {
  let unit = value[index].to_int()
  unit >= 48 && unit <= 57
}

///|
fn valid_timestamp(value : String) -> Bool {
  if value.length() != 24 ||
    value[4] != '-' ||
    value[7] != '-' ||
    value[10] != 'T' ||
    value[13] != ':' ||
    value[16] != ':' ||
    value[19] != '.' ||
    value[23] != 'Z' {
    return false
  }
  for index in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18, 20, 21, 22] {
    if !ascii_digit(value, index) {
      return false
    }
  }
  true
}

///|
fn object_fields(
  value : @json.CanonicalValue,
) -> Result[Array[(String, @json.CanonicalValue)], PublicationContractIssue] {
  match @json.object_fields(value) {
    Some(fields) => Ok(fields)
    None => Err(InvalidObject)
  }
}

///|
fn field_value(
  fields : Array[(String, @json.CanonicalValue)],
  name : String,
) -> @json.CanonicalValue? {
  for (key, value) in fields {
    if key == name {
      return Some(value)
    }
  }
  None
}

///|
fn string_value(value : @json.CanonicalValue) -> String? {
  match value {
    @json.String(text) => Some(text)
    _ => None
  }
}

///|
fn optional_string(value : @json.CanonicalValue?) -> String? {
  match value {
    Some(item) => string_value(item)
    None => None
  }
}

///|
priv struct NamedCid {
  name : String
  cid : String
}

///|
fn valid_safe_count(value : @json.CanonicalValue) -> Bool {
  match value {
    @json.Number(number) =>
      match @scalar.read_safe_integer(number) {
        Some(value) => value >= 0L
        None => false
      }
    _ => false
  }
}

///|
fn validate_named_cid_object(
  value : @json.CanonicalValue,
  name_field : String,
  cid_field : String,
) -> NamedCid? {
  guard object_fields(value) is Ok(fields) else { return None }
  if fields.length() != 2 {
    return None
  }
  guard optional_string(field_value(fields, name_field)) is Some(name) else {
    return None
  }
  guard optional_string(field_value(fields, cid_field)) is Some(cid) else {
    return None
  }
  if name.is_empty() || !valid_contract_cid(cid) {
    None
  } else {
    Some({ name, cid, })
  }
}

///|
fn validate_unique_named_array(
  value : @json.CanonicalValue,
  name_field : String,
  cid_field : String,
) -> Bool {
  guard value is @json.Array(values) else { return false }
  let items = @json.array_values(values)
  if items.is_empty() {
    return false
  }
  let identities : Array[String] = []
  let names : Array[String] = []
  for item in items {
    guard validate_named_cid_object(item, name_field, cid_field) is Some(id) else {
      return false
    }
    let identity = id.name + "\u{0}" + id.cid
    if identities.contains(identity) || names.contains(id.name) {
      return false
    }
    identities.push(identity)
    names.push(id.name)
  }
  true
}

///|
fn validate_string_array(
  value : @json.CanonicalValue,
  choices : Array[String]?,
  allow_empty : Bool,
) -> Bool {
  guard value is @json.Array(values) else { return false }
  let items = @json.array_values(values)
  if !allow_empty && items.is_empty() {
    return false
  }
  let seen : Array[String] = []
  for item in items {
    guard string_value(item) is Some(text) else { return false }
    if seen.contains(text) ||
      (choices is Some(allowed) && !allowed.contains(text)) {
      return false
    }
    seen.push(text)
  }
  true
}

///|
fn validate_rule(value : @json.CanonicalValue, rule : FieldRule) -> Bool {
  match rule {
    Exact(expected) => string_value(value) == Some(expected)
    Cid => string_value(value).map(valid_contract_cid).unwrap_or(false)
    Digest => string_value(value).map(valid_digest).unwrap_or(false)
    Timestamp => string_value(value).map(valid_timestamp).unwrap_or(false)
    NonemptyText =>
      string_value(value).map(text => !text.is_empty()).unwrap_or(false)
    SafeCount => valid_safe_count(value)
    Choice(values) =>
      string_value(value)
      .map(fn(text) { values.contains(text) })
      .unwrap_or(false)
    CidList => {
      guard value is @json.Array(values) else { return false }
      let items = @json.array_values(values)
      let seen : Array[String] = []
      for item in items {
        guard string_value(item) is Some(text) else { return false }
        if !valid_contract_cid(text) || seen.contains(text) {
          return false
        }
        seen.push(text)
      }
      true
    }
    Inventory =>
      validate_unique_named_array(value, "result_name", "result_definition_cid")
    ResultList =>
      validate_unique_named_array(value, "result_name", "result_artifact_cid")
    FormatList =>
      validate_string_array(value, Some(["json", "jsonl", "csv"]), false)
  }
}

///|
fn conditional_validation(
  spec : ContractSpec,
  fields : Array[(String, @json.CanonicalValue)],
) -> Result[Unit, PublicationContractIssue] {
  if spec.name == "publication_record" {
    let state = optional_string(field_value(fields, "state")).unwrap()
    if state == "succeeded" &&
      field_value(fields, "public_index_entry_cid") is None {
      return Err(ConditionalField("public_index_entry_cid"))
    }
    if state == "failed" && field_value(fields, "failure_cid") is None {
      return Err(ConditionalField("failure_cid"))
    }
  }
  if spec.name == "delivery_record" {
    let state = optional_string(field_value(fields, "state")).unwrap()
    let exposure = optional_string(field_value(fields, "exposure")).unwrap()
    if state == "succeeded" &&
      (
        exposure != "exact" ||
        field_value(fields, "delivered_sha256") is None ||
        field_value(fields, "result_delivery_receipt_cid") is None
      ) {
      return Err(ConditionalField("succeeded"))
    }
    if exposure == "unknown_additional" &&
      field_value(fields, "possible_unconfirmed_max_bytes") is None {
      return Err(ConditionalField("possible_unconfirmed_max_bytes"))
    }
  }
  Ok(())
}

///|
fn validate_contract(
  spec : ContractSpec,
  value : @json.CanonicalValue,
  complete : Bool,
) -> Result[Unit, PublicationContractIssue] {
  let fields = match object_fields(value) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let allowed = ["version", spec.identity]
  for field in spec.fields {
    allowed.push(field.name)
  }
  for (name, _) in fields {
    if !allowed.contains(name) {
      return Err(UnknownField(name))
    }
  }
  guard field_value(fields, "version") is Some(version) else {
    return Err(MissingField("version"))
  }
  if !validate_rule(version, Exact(spec.version)) {
    return Err(InvalidField("version"))
  }
  for field in spec.fields {
    match field_value(fields, field.name) {
      None if field.required => return Err(MissingField(field.name))
      None => ()
      Some(value) =>
        if !validate_rule(value, field.rule) {
          return Err(InvalidField(field.name))
        }
    }
  }
  match field_value(fields, spec.identity) {
    Some(_) if !complete => return Err(IdentityAlreadyPresent)
    None if complete => return Err(IdentityMissing)
    Some(value) =>
      if !validate_rule(value, Cid) {
        return Err(InvalidField(spec.identity))
      }
    None => ()
  }
  conditional_validation(spec, fields)
}

///|
fn parse_contract_wire(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@json.CanonicalValue, PublicationContractIssue] {
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  let node = match
    @source.parse_json(wire, {
      max_input_bytes: max_wire_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidWire)
  }
  Ok(@json.from_source(node, max_nodes, max_depth, max_wire_bytes)) catch {
    _ => Err(InvalidWire)
  }
}

///|
pub fn seal_publication_contract(
  name : String,
  body_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationContractIssue] {
  let spec = match contract_spec(name) {
    Some(value) => value
    None => return Err(UnknownContract)
  }
  if max_nodes < 2 {
    return Err(InvalidLimits)
  }
  let body = match
    parse_contract_wire(body_wire, max_wire_bytes, max_nodes - 1, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match validate_contract(spec, body, false) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let identity = @json.cid_value(body, max_wire_bytes, max_nodes - 1, max_depth) catch {
    _ => return Err(Encoding)
  }
  let complete = match
    @json.object_with_string_field(body, spec.identity, identity) {
    Some(value) => value
    None => return Err(InvalidObject)
  }
  match validate_contract(spec, complete, true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let wire = @json.stringify_value(
    complete, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  Ok({ name, identity_field: spec.identity, identity, wire, value: complete, })
}

///|
pub fn admit_publication_contract(
  name : String,
  complete_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationContractIssue] {
  let spec = match contract_spec(name) {
    Some(value) => value
    None => return Err(UnknownContract)
  }
  let complete = match
    parse_contract_wire(complete_wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match validate_contract(spec, complete, true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard optional_string(@json.object_field(complete, spec.identity))
    is Some(identity) else {
    return Err(IdentityMissing)
  }
  let preimage = match @json.object_without_field(complete, spec.identity) {
    Some(value) => value
    None => return Err(IdentityMissing)
  }
  let expected = @json.cid_value(preimage, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  if expected != identity {
    return Err(IdentityMismatch)
  }
  let wire = @json.stringify_value(
    complete, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  Ok({ name, identity_field: spec.identity, identity, wire, value: complete, })
}

///|
fn contract_string(contract : PublicationContract, name : String) -> String? {
  optional_string(@json.object_field(contract.value, name))
}

///|
fn contract_count(contract : PublicationContract, name : String) -> Int64? {
  match @json.object_field(contract.value, name) {
    Some(@json.Number(number)) => @scalar.read_safe_integer(number)
    _ => None
  }
}

///|
/// Validate one append-only publication record transition. Physical CAS,
/// durable write, and directory synchronization remain Store responsibilities;
/// the portable core alone decides whether the transition is meaningful.
pub fn validate_publication_record_transition(
  previous : PublicationContract?,
  next : PublicationContract,
  uncommitted_confirmed : Bool,
) -> Result[Unit, PublicationTransitionIssue] {
  if next.name != "publication_record" {
    return Err(WrongContract)
  }
  let next_attempt = contract_string(next, "publication_attempt_cid").unwrap()
  let next_sequence = contract_count(next, "sequence").unwrap()
  let next_prior = contract_string(next, "prior_record_cid")
  let next_state = contract_string(next, "state").unwrap()
  match previous {
    None => {
      if next_sequence != 0L {
        return Err(SequenceMismatch)
      }
      if next_prior is Some(_) {
        return Err(PriorRecordMismatch)
      }
      if next_state != "preparing" {
        return Err(StateMismatch)
      }
    }
    Some(value) => {
      if value.name != "publication_record" {
        return Err(WrongContract)
      }
      if contract_string(value, "publication_attempt_cid") != Some(next_attempt) {
        return Err(AttemptMismatch)
      }
      let previous_sequence = contract_count(value, "sequence").unwrap()
      if next_sequence != previous_sequence + 1L {
        return Err(SequenceMismatch)
      }
      if next_prior != Some(value.identity) {
        return Err(PriorRecordMismatch)
      }
      let previous_state = contract_string(value, "state").unwrap()
      let allowed = match previous_state {
        "preparing" =>
          next_state == "preparing" ||
          next_state == "committing" ||
          next_state == "failed" ||
          next_state == "cancelled"
        "committing" | "publication_unknown" =>
          next_state == "publication_unknown" ||
          next_state == "succeeded" ||
          next_state == "failed" ||
          next_state == "cancelled"
        _ => false
      }
      if !allowed {
        return Err(StateMismatch)
      }
      if (
          previous_state == "committing" ||
          previous_state == "publication_unknown"
        ) &&
        (next_state == "failed" || next_state == "cancelled") &&
        !uncommitted_confirmed {
        return Err(UncommittedNotConfirmed)
      }
    }
  }
  Ok(())
}

///|
pub fn publication_record_allows_commit(record : PublicationContract) -> Bool {
  record.name == "publication_record" &&
  contract_string(record, "state") == Some("committing")
}

///|
/// Validate append-only progress for one immutable Delivery Attempt. Sink I/O,
/// exposure observation, and durable record CAS remain adapter effects.
pub fn validate_delivery_record_transition(
  previous : PublicationContract?,
  next : PublicationContract,
) -> Result[Unit, DeliveryTransitionIssue] {
  if next.name != "delivery_record" {
    return Err(DeliveryWrongContract)
  }
  let next_attempt = contract_string(next, "delivery_attempt_cid").unwrap()
  let next_sequence = contract_count(next, "sequence").unwrap()
  let next_prior = contract_string(next, "prior_record_cid")
  let next_state = contract_string(next, "state").unwrap()
  let next_bytes = contract_count(next, "confirmed_byte_count").unwrap()
  match previous {
    None => {
      if next_sequence != 0L {
        return Err(DeliverySequenceMismatch)
      }
      if next_prior is Some(_) {
        return Err(DeliveryPriorRecordMismatch)
      }
    }
    Some(value) => {
      if value.name != "delivery_record" {
        return Err(DeliveryWrongContract)
      }
      if contract_string(value, "delivery_attempt_cid") != Some(next_attempt) {
        return Err(DeliveryAttemptMismatch)
      }
      let previous_sequence = contract_count(value, "sequence").unwrap()
      if next_sequence != previous_sequence + 1L {
        return Err(DeliverySequenceMismatch)
      }
      if next_prior != Some(value.identity) {
        return Err(DeliveryPriorRecordMismatch)
      }
      if contract_string(value, "state") != Some("streaming") {
        return Err(DeliveryStateMismatch)
      }
      let previous_bytes = contract_count(value, "confirmed_byte_count").unwrap()
      if next_bytes < previous_bytes {
        return Err(ConfirmedBytesDecreased)
      }
    }
  }
  if next_state != "streaming" &&
    next_state != "succeeded" &&
    next_state != "failed" &&
    next_state != "cancelled" {
    return Err(DeliveryStateMismatch)
  }
  Ok(())
}

///|
pub fn publication_contract_name(contract : PublicationContract) -> String {
  contract.name
}

///|
pub fn publication_contract_identity_field(
  contract : PublicationContract,
) -> String {
  contract.identity_field
}

///|
pub fn publication_contract_identity(contract : PublicationContract) -> String {
  contract.identity
}

///|
pub fn publication_contract_json(contract : PublicationContract) -> String {
  contract.wire
}
