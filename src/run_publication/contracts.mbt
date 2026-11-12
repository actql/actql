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
  wire_usage : (Int, Int, Int)?
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
pub(all) enum RunPublicationChainIssue {
  ChainWrongContract(String)
  ChainRunDefinitionMismatch
  ChainInvocationMismatch
  ChainInvocationTemplateMismatch
  ChainEmptyInventory
  ChainDuplicateResult(String)
  ChainMissingResult(String)
  ChainForeignResult(String)
  ChainResultDefinitionMismatch(String)
  ChainArtifactMismatch(String)
  ChainEncoding
} derive(Eq, Debug)

///|
priv enum FieldRule {
  Exact(String)
  Cid
  Digest
  Timestamp
  VersionToken
  NonemptyText
  SafeCount
  Choice(Array[String])
  CidList
  NonemptyTextList
  Inventory
  ResultList
  FormatList
  ManifestResults
  Ordering
  OrderingTerms
  WitnessList
  ProvenanceList
  ScopeSources
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
    required("namespace_id", NonemptyText),
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
    "lookup_accounting" =>
      Some({
        name,
        version: "actql-lookup-accounting-evidence/0.1",
        identity: "self_cid",
        fields: [],
      })
    "acquisition_attempt_receipt" =>
      Some({
        name,
        version: "actql-lookup-attempt-receipt/0.1",
        identity: "self_cid",
        fields: [],
      })
    "lookup_evidence" =>
      Some({
        name,
        version: "actql-lookup-evidence/0.1",
        identity: "evidence_cid",
        fields: [],
      })
    "native_file_lookup_request" =>
      Some({
        name,
        version: "actql-lookup-semantic-request/0.1",
        identity: "self_cid",
        fields: [],
      })
    "native_file_lookup_call_slot" =>
      Some({
        name,
        version: "actql-lookup-call-slot/0.1",
        identity: "self_cid",
        fields: [],
      })
    "native_file_lookup_activation" =>
      Some({
        name,
        version: "actql-lookup-attempt-activation/0.1",
        identity: "self_cid",
        fields: [],
      })
    "native_file_lookup_attempt_event" =>
      Some({
        name,
        version: "actql-lookup-attempt-event/0.1",
        identity: "self_cid",
        fields: [],
      })
    "native_file_lookup_adoption" =>
      Some({
        name,
        version: "actql-lookup-page-adoption/0.1",
        identity: "self_cid",
        fields: [],
      })
    "native_file_lookup_raw_response" =>
      Some({
        name,
        version: "actql-lookup-raw-response/0.1",
        identity: "self_cid",
        fields: [],
      })
    "native_file_lookup_batch_plan" =>
      Some({
        name,
        version: "actql-lookup-batch-plan/0.1",
        identity: "self_cid",
        fields: [],
      })
    "lookup_barrier" =>
      Some({
        name,
        version: "actql-lookup-barrier/0.1",
        identity: "barrier_cid",
        fields: [],
      })
    "native_file_lookup_transport" =>
      Some({
        name,
        version: "actql-lookup-transport-plan/0.1",
        identity: "self_cid",
        fields: [],
      })
    "native_file_content_read" =>
      Some({
        name,
        version: "actql-native-file-content-read/0.1",
        identity: "transport_cid",
        fields: [],
      })
    "declared_file_content_read" =>
      Some({
        name,
        version: "actql-declared-file-content-read/0.1",
        identity: "transport_cid",
        fields: [],
      })
    "request_key_set" =>
      Some({
        name,
        version: "actql-lookup-key-set/0.1",
        identity: "self_cid",
        fields: [],
      })
    "compiled_plan" =>
      Some({
        name,
        version: "actql-compiled-plan/0.1",
        identity: "compiled_plan_cid",
        fields: [
          required("compiler_version", VersionToken),
          required("aoa_ir_version", VersionToken),
          required("executable_plan_cid", Cid),
          required("program_definition_cid", Cid),
          required("program_semantics_cid", Cid),
          required("aoa_contract_cid", Cid),
          required("aoa_logical_cid", Cid),
          optional("effect_target_selections_cid", Cid),
        ],
      })
    "run_definition" =>
      Some({
        name,
        version: "actql-run-definition/0.1",
        identity: "run_definition_cid",
        fields: [
          required("scope_id", NonemptyText),
          required("run_id", NonemptyText),
          required("compiled_plan_cid", Cid),
          required("invocation_template_cid", Cid),
          required("authorization_context_cid", Cid),
          required("input_artifact_set_cid", Cid),
          required("created_at", Timestamp),
          required("valid_until", Timestamp),
          optional("effect_target_selections_cid", Cid),
        ],
      })
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
    "acquisition_scope" =>
      Some({
        name,
        version: "actql-acquisition-scope/0.1",
        identity: "self_cid",
        fields: [required("sources", ScopeSources)],
      })
    "acquisition_relation" =>
      Some({
        name,
        version: "actql-acquisition-relation/0.1",
        identity: "self_cid",
        fields: [
          required("producer_contract_cid", Cid),
          required("relation_schema_cid", Cid),
          required("logical_value_cid", Cid),
          required("ordering_evidence_cid", Cid),
          required("actual_row_count", SafeCount),
          required("observation_scope_cid", Cid),
          required(
            "actual_completeness",
            Choice(["complete", "partial", "unknown"]),
          ),
          required("effective_data_policy_cid", Cid),
          required("effective_retention_policy_cid", Cid),
          required("provenance_evidence", ProvenanceList),
        ],
      })
    "derivation_evidence" =>
      Some({
        name,
        version: "actql-acquisition-derivation-evidence/0.1",
        identity: "self_cid",
        fields: [
          required("producer_contract_cid", Cid),
          required("computation_contract_cid", Cid),
          required("input_relation_cids", CidList),
          required("logical_value_cid", Cid),
          required("relation_schema_cid", Cid),
          required("scope_cid", Cid),
          required("effective_data_policy_cid", Cid),
          required("ordering", Ordering),
          required("issuer_id", NonemptyText),
          required("authority_scope_cid", Cid),
        ],
      })
    "ordering_evidence" =>
      Some({
        name,
        version: "actql-acquisition-ordering/0.1",
        identity: "self_cid",
        fields: [
          required("producer_contract_cid", Cid),
          required("kind", Choice(["occurrence", "keys"])),
          required("terms", OrderingTerms),
          required("witness_evidence", WitnessList),
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
          required("metadata_delete_by", Timestamp),
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
          required("result_fields", NonemptyTextList),
          required("material_generation_cid", Cid),
          required("store_authority_cid", Cid),
          required("effective_retention_policy_cid", Cid),
          required("row_count", SafeCount),
          required("byte_count", SafeCount),
          required("physical_sha256", Digest),
        ],
      })
    "result_artifact" =>
      Some({
        name,
        version: "actql-result-artifact/0.1",
        identity: "result_artifact_cid",
        fields: [
          required("result_definition_cid", Cid),
          required("invocation_cid", Cid),
          required("logical_result_cid", Cid),
          required("result_schema_cid", Cid),
          required("ordering_evidence_cid", Cid),
          required("actual_row_count", SafeCount),
          required("actual_completeness", Choice(["complete", "partial"])),
          required("effective_data_policy_cid", Cid),
          required("effective_retention_policy_cid", Cid),
          required("provenance_evidence_cids", CidList),
        ],
      })
    "effect_source_artifact" =>
      Some({
        name,
        version: "actql-effect-source-artifact/0.1",
        identity: "result_artifact_cid",
        fields: [
          required("source_binding_cid", Cid),
          required("source_result", NonemptyText),
          required("store_authority_cid", Cid),
          required("invocation_cid", Cid),
          required("logical_result_cid", Cid),
          required("result_schema_cid", Cid),
          required("actual_row_count", SafeCount),
          required("actual_completeness", Choice(["complete", "partial"])),
          required("effective_data_policy_cid", Cid),
          required("effective_retention_policy_cid", Cid),
          required("provenance_evidence_cids", CidList),
        ],
      })
    "result_manifest" =>
      Some({
        name,
        version: "actql-result-manifest/0.1",
        identity: "result_manifest_cid",
        fields: [
          required("run_definition_cid", Cid),
          required("invocation_cid", Cid),
          required("results", ManifestResults),
        ],
      })
    "run_receipt" =>
      Some({
        name,
        version: "actql-run-receipt/0.1",
        identity: "receipt_identity_cid",
        fields: [],
      })
    "captured_run" =>
      Some({
        name,
        version: "actql-captured-run/0.1",
        identity: "captured_run_cid",
        fields: [],
      })
    "result_delivery_receipt" =>
      Some({
        name,
        version: "actql-result-delivery-receipt/0.1",
        identity: "result_delivery_receipt_cid",
        fields: [],
      })
    "effect_apply_receipt" =>
      Some({
        name,
        version: "actql-effect-apply-receipt/0.1",
        identity: "receipt_cid",
        fields: [],
      })
    "effect_local_operation_receipt" =>
      Some({
        name,
        version: "actql-local-effect-operation-receipt/0.1",
        identity: "receipt_cid",
        fields: [],
      })
    "effect_row_outcome_receipt" =>
      Some({
        name,
        version: "actql-effect-row-outcome-receipt/0.1",
        identity: "receipt_cid",
        fields: [],
      })
    "effect_set_apply_receipt" =>
      Some({
        name,
        version: "actql-effect-set-apply-receipt/0.1",
        identity: "receipt_cid",
        fields: [],
      })
    "effect_reconciliation_receipt" =>
      Some({
        name,
        version: "actql-effect-reconciliation-receipt/0.1",
        identity: "reconciliation_receipt_cid",
        fields: [],
      })
    "publication_request" =>
      Some({
        name,
        version: "actql-publication-request/0.1",
        identity: "publication_request_cid",
        fields: [
          required("namespace_id", NonemptyText),
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
          required("namespace_id", NonemptyText),
          required("authority_scope_cid", Cid),
          required("run_definition_cid", Cid),
          required("invocation_cid", Cid),
          required("result_manifest_cid", Cid),
          required("run_receipt_cid", Cid),
          required("captured_run_cid", Cid),
          required("durable_result_binding_cids", CidList),
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
  allow_empty? : Bool = false,
) -> Bool {
  guard value is @json.Array(values) else { return false }
  let items = @json.array_values(values)
  if items.is_empty() && !allow_empty {
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
fn validate_order_term(value : @json.CanonicalValue) -> Bool {
  guard object_fields(value) is Ok(fields) else { return false }
  if fields.length() != 3 {
    return false
  }
  guard optional_string(field_value(fields, "field")) is Some(field) else {
    return false
  }
  guard optional_string(field_value(fields, "dir")) is Some(direction) else {
    return false
  }
  guard optional_string(field_value(fields, "nulls")) is Some(nulls) else {
    return false
  }
  !field.is_empty() &&
  (direction == "asc" || direction == "desc") &&
  (nulls == "first" || nulls == "last")
}

///|
fn validate_order_terms(value : @json.CanonicalValue) -> Bool {
  guard value is @json.Array(frozen) else { return false }
  for term in @json.array_values(frozen) {
    if !validate_order_term(term) {
      return false
    }
  }
  true
}

///|
fn validate_ordering(value : @json.CanonicalValue) -> Bool {
  guard object_fields(value) is Ok(fields) else { return false }
  if fields.length() != 2 {
    return false
  }
  guard optional_string(field_value(fields, "kind")) is Some(kind) else {
    return false
  }
  guard field_value(fields, "terms") is Some(terms) else { return false }
  if !validate_order_terms(terms) {
    return false
  }
  guard terms is @json.Array(frozen) else { return false }
  let count = @json.array_values(frozen).length()
  (kind == "occurrence" && count == 0) || (kind == "keys" && count > 0)
}

///|
fn validate_witness_list(value : @json.CanonicalValue) -> Bool {
  guard value is @json.Array(frozen) else { return false }
  let witnesses = @json.array_values(frozen)
  if witnesses.is_empty() {
    return false
  }
  let mut prior_kind = -1
  let mut prior_cid = ""
  for witness in witnesses {
    guard object_fields(witness) is Ok(fields) else { return false }
    if fields.length() != 2 {
      return false
    }
    guard optional_string(field_value(fields, "kind")) is Some(kind) else {
      return false
    }
    guard optional_string(field_value(fields, "cid")) is Some(cid) else {
      return false
    }
    if (kind != "source" && kind != "derivation") || !valid_contract_cid(cid) {
      return false
    }
    let rank = if kind == "derivation" { 0 } else { 1 }
    if rank < prior_kind || (rank == prior_kind && cid.compare(prior_cid) <= 0) {
      return false
    }
    prior_kind = rank
    prior_cid = cid
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
    VersionToken =>
      string_value(value).map(valid_version_token).unwrap_or(false)
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
    NonemptyTextList => {
      guard value is @json.Array(values) else { return false }
      let items = @json.array_values(values)
      if items.is_empty() {
        return false
      }
      let seen : Array[String] = []
      for item in items {
        guard string_value(item) is Some(text) else { return false }
        if text.is_empty() || seen.contains(text) {
          return false
        }
        seen.push(text)
      }
      true
    }
    Inventory =>
      validate_unique_named_array(
        value,
        "result_name",
        "result_definition_cid",
        allow_empty=true,
      )
    ResultList =>
      validate_unique_named_array(value, "result_name", "result_artifact_cid")
    FormatList =>
      validate_string_array(value, Some(["json", "jsonl", "csv"]), false)
    ManifestResults => {
      guard object_fields(value) is Ok(results) else { return false }
      let artifact_spec = contract_spec("result_artifact").unwrap()
      for (name, artifact) in results {
        if name.is_empty() ||
          validate_contract(artifact_spec, artifact, true) is Err(_) {
          return false
        }
      }
      true
    }
    Ordering => validate_ordering(value)
    OrderingTerms => validate_order_terms(value)
    WitnessList => validate_witness_list(value)
    ProvenanceList => validate_relation_provenance(value)
    ScopeSources => validate_scope_sources(value)
  }
}

///|
fn validate_identity(
  spec : ContractSpec,
  value : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, PublicationContractIssue] {
  guard optional_string(@json.object_field(value, spec.identity))
    is Some(identity) else {
    return Err(IdentityMissing)
  }
  let preimage = match @json.object_without_field(value, spec.identity) {
    Some(value) => value
    None => return Err(IdentityMissing)
  }
  let expected = @json.cid_value(preimage, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  if expected != identity {
    return Err(IdentityMismatch)
  }
  Ok(())
}

///|
fn validate_nested_identities(
  spec : ContractSpec,
  value : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  known_artifacts? : Array[PublicationContract] = [],
) -> Result[Unit, PublicationContractIssue] {
  if spec.name != "result_manifest" {
    return Ok(())
  }
  guard @json.object_field(value, "results") is Some(results_value) else {
    return Err(MissingField("results"))
  }
  guard object_fields(results_value) is Ok(results) else {
    return Err(InvalidField("results"))
  }
  let artifact_spec = contract_spec("result_artifact").unwrap()
  for index in 0..<results.length() {
    let (_, artifact) = results[index]
    // Only an issuer in this package can supply its exact immutable child.
    // External Manifest text has no such original and keeps full admission.
    let matches = fn(original : PublicationContract) -> Bool {
      original.name == "result_artifact" &&
      physical_equal(original.value, artifact) &&
      publication_contract_check_limits(
        original, max_wire_bytes, max_nodes, max_depth,
      )
      is Ok(_)
    }
    // The issuer already supplies these originals in emitted Result order.
    // Reordered or normalized keys retain the existing full search fallback.
    if (index < known_artifacts.length() && matches(known_artifacts[index])) ||
      known_artifacts.any(matches) {
      continue
    }
    match
      validate_identity(
        artifact_spec, artifact, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(_) => ()
      Err(_) => return Err(InvalidField("results"))
    }
  }
  Ok(())
}

///|
fn conditional_validation(
  spec : ContractSpec,
  fields : Array[(String, @json.CanonicalValue)],
) -> Result[Unit, PublicationContractIssue] {
  if spec.name == "ordering_evidence" {
    let kind = optional_string(field_value(fields, "kind")).unwrap()
    guard field_value(fields, "terms") is Some(terms) else {
      return Err(ConditionalField("terms"))
    }
    guard terms is @json.Array(frozen) else {
      return Err(ConditionalField("terms"))
    }
    let count = @json.array_values(frozen).length()
    if (kind == "occurrence" && count != 0) || (kind == "keys" && count == 0) {
      return Err(ConditionalField("terms"))
    }
  }
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
fn validate_protocol_envelope(
  spec : ContractSpec,
  value : @json.CanonicalValue,
  complete : Bool,
) -> Result[Unit, PublicationContractIssue] {
  let fields = match object_fields(value) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard field_value(fields, "version") is Some(version) else {
    return Err(MissingField("version"))
  }
  if !validate_rule(version, Exact(spec.version)) {
    return Err(InvalidField("version"))
  }
  match field_value(fields, spec.identity) {
    Some(_) if !complete => return Err(IdentityAlreadyPresent)
    None if complete => return Err(IdentityMissing)
    Some(identity) =>
      if !validate_rule(identity, Cid) {
        return Err(InvalidField(spec.identity))
      }
    None => ()
  }
  Ok(())
}

///|
fn validate_bounded_contract(
  spec : ContractSpec,
  value : @json.CanonicalValue,
  complete : Bool,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, PublicationContractIssue] {
  if generated_protocol_schema_root(spec.name, complete) is Some(_) {
    match validate_protocol_envelope(spec, value, complete) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    if validate_generated_protocol_shape(
        spec.name,
        value,
        complete,
        max_wire_bytes,
        max_nodes,
        max_depth,
      ) {
      if spec.name == "request_key_set" &&
        !lookup_key_set_order_valid(value, max_wire_bytes, max_nodes, max_depth) {
        return Err(InvalidField("typed_key_order"))
      }
      if spec.name == "native_file_lookup_batch_plan" &&
        !native_file_lookup_batch_order_valid(value) {
        return Err(InvalidField("canonical_single_key_batches"))
      }
      if spec.name == "effect_apply_receipt" &&
        !effect_apply_receipt_consistent(value) {
        return Err(ConditionalField("status"))
      }
      if spec.name == "acquisition_attempt_receipt" &&
        !lookup_lifecycle_order_valid(value) {
        return Err(InvalidField("lifecycle_evidence"))
      }
      if spec.name == "lookup_evidence" &&
        (
          !lookup_cid_set_order_valid(value, "input_content_ref_cids") ||
          !lookup_cid_set_order_valid(value, "request_input_data_policy_cids")
        ) {
        return Err(InvalidField("lookup_cid_sets"))
      }
      return Ok(())
    }
    return Err(InvalidField("protocol_schema"))
  }
  validate_contract(spec, value, complete)
}

///|
fn parse_contract_wire(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  data_keys? : Bool = false,
) -> Result[@json.CanonicalValue, PublicationContractIssue] {
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  let parse_limits : @source.ParseLimits = {
    max_input_bytes: max_wire_bytes,
    max_nodes,
    max_depth,
  }
  let node = match
    (if data_keys {
      @source.parse_json_bytes_preserving(@utf8.encode(wire), parse_limits)
    } else {
      @source.parse_json(wire, parse_limits)
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidWire)
  }
  Ok(@json.from_source(node, max_nodes, max_depth, max_wire_bytes, data_keys~)) catch {
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
  if name == "captured_run" {
    let workspace = if max_nodes > 268435455 {
      2147483647
    } else {
      max_nodes * 8
    }
    let preparation = match
      start_publication_seal_preparation(
        name, body_wire, max_wire_bytes, max_nodes, max_depth, workspace,
      ) {
      Ok(preparation) => preparation
      Err(issue) => return Err(issue)
    }
    // The aggregate capture owner will poll this same child. Explicit callers
    // still drain it here; public issuance is not yet interruption-safe.
    while true {
      match preparation.advance(256) {
        Err(issue) => return Err(issue)
        Ok((true, _)) => return preparation.finish()
        Ok((false, _)) => ()
      }
    } nobreak {
      return Err(Encoding)
    }
  }
  let spec = match contract_spec(name) {
    Some(value) => value
    None => return Err(UnknownContract)
  }
  if max_nodes < 2 {
    return Err(InvalidLimits)
  }
  // Captured values and typed provider outcomes contain opaque JSON keys.
  // The closed structural schema is still checked below.
  let body = match
    parse_contract_wire(
      body_wire,
      max_wire_bytes,
      max_nodes - 1,
      max_depth,
      data_keys=name == "captured_run" ||
        name == "native_file_lookup_request" ||
        name == "lookup_barrier" ||
        name == "native_file_lookup_transport" ||
        name == "effect_row_outcome_receipt" ||
        name == "effect_local_operation_receipt",
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  seal_publication_material(spec, body, max_wire_bytes, max_nodes, max_depth, [])
}

///|
/// Same-owner canonical material. Text callers still parse and admit their
/// original wire before entering this unchanged sealing sequence.
fn seal_publication_material(
  spec : ContractSpec,
  body : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  known_artifacts : Array[PublicationContract],
) -> Result[PublicationContract, PublicationContractIssue] {
  match
    validate_bounded_contract(
      spec,
      body,
      false,
      max_wire_bytes,
      max_nodes - 1,
      max_depth,
    ) {
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
  match
    validate_bounded_contract(
      spec, complete, true, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    validate_nested_identities(
      spec,
      complete,
      max_wire_bytes,
      max_nodes,
      max_depth,
      known_artifacts~,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (wire, bytes, nodes, depth) = try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @json.emit_value(complete, writer)
    @encode.finish_text_usage(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok({
    name: spec.name,
    identity_field: spec.identity,
    identity,
    wire,
    value: complete,
    wire_usage: Some((bytes, nodes, depth)),
  })
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
    parse_contract_wire(
      complete_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=name == "captured_run" ||
        name == "native_file_lookup_request" ||
        name == "lookup_barrier" ||
        name == "native_file_lookup_transport" ||
        name == "effect_row_outcome_receipt" ||
        name == "effect_local_operation_receipt",
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  admit_publication_contract_material(
    spec, complete, complete_wire, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
// The same full admission after exactly one bounded wire parse. Closed
// file-profile selection supplies only its existing spec, never authority.
fn admit_publication_contract_material(
  spec : ContractSpec,
  complete : @json.CanonicalValue,
  complete_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationContractIssue] {
  let name = spec.name
  match
    validate_bounded_contract(
      spec, complete, true, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    validate_identity(spec, complete, max_wire_bytes, max_nodes, max_depth) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    validate_nested_identities(
      spec, complete, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let identity = optional_string(@json.object_field(complete, spec.identity)).unwrap()
  let (wire, bytes, nodes, depth) = try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @json.emit_value(complete, writer)
    @encode.finish_text_usage(writer)
  } catch {
    _ => return Err(Encoding)
  }
  if [
      "acquisition_relation", "acquisition_scope", "request_key_set", "native_file_lookup_batch_plan",
      "native_file_lookup_request", "native_file_lookup_call_slot", "native_file_lookup_activation",
      "native_file_lookup_raw_response", "native_file_lookup_attempt_event", "native_file_lookup_adoption",
      "lookup_accounting", "acquisition_attempt_receipt", "lookup_evidence",
    ].contains(name) &&
    wire != complete_wire {
    return Err(InvalidWire)
  }
  Ok({
    name,
    identity_field: spec.identity,
    identity,
    wire,
    value: complete,
    wire_usage: Some((bytes, nodes, depth)),
  })
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
fn canonical_value_wire(
  value : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String? {
  Some(@json.stringify_value(value, max_wire_bytes, max_nodes, max_depth)) catch {
    _ => None
  }
}

///|
/// Validate the bounded acyclic root using the same private preparation as
/// the polled computation checker. Reference-kind admission remains separate.
pub fn validate_run_publication_chain(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, RunPublicationChainIssue] {
  let check = start_publication_root_preparation(
    {
      run_definition,
      invocation,
      definitions,
      artifacts,
      manifest,
      max_wire_bytes,
      max_nodes,
      max_depth,
    },
    2147483647,
  )
  while true {
    match check.advance(256) {
      Err(EvidenceRoot(issue)) => return Err(issue)
      Err(_) => return Err(ChainEncoding)
      Ok((true, _)) => {
        check.cancel()
        return Ok(())
      }
      Ok((false, _)) => ()
    }
  } nobreak {
    Err(ChainEncoding)
  }
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

///|
/// Immutable DATA from this contract's original final encoder. This projection
/// performs no admission, traversal, permission or physical-current check.
pub fn publication_contract_wire_usage(
  contract : PublicationContract,
) -> (Int, Int, Int)? {
  contract.wire_usage
}

///|
/// Apply tighter serialization limits to this same immutable admitted contract.
/// Usage comes from its original final encoder, not its preimage or caller facts.
/// This checks no permission, lifetime or physical capacity.
pub fn publication_contract_check_limits(
  contract : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, PublicationContractIssue] {
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  guard contract.wire_usage is Some((bytes, nodes, depth)) else {
    return Err(Encoding)
  }
  if bytes > max_wire_bytes || nodes > max_nodes || depth > max_depth {
    return Err(Encoding)
  }
  Ok(())
}

///|
/// Read the original scope from an admitted Run Definition. This projection
/// does not interpret scope syntax, authorize access or read the saved wire.
pub fn publication_contract_run_definition_scope(
  contract : PublicationContract,
) -> String? {
  if contract.name != "run_definition" {
    return None
  }
  contract_string(contract, "scope_id")
}

///|
/// Read the compiler-derived selection projection from an admitted Plan or
/// Run. This identifies retained original material; it grants no execution.
pub fn publication_contract_effect_target_selections_cid(
  contract : PublicationContract,
) -> String? {
  if contract.name != "compiled_plan" && contract.name != "run_definition" {
    return None
  }
  contract_string(contract, "effect_target_selections_cid")
}
