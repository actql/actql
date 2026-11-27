///|
// Retained on the installed Model in the original command Read. These facts
// bound work and select evidence. The original Account still authorizes it.
priv struct NativeModelHttpRunPolicy {
  egress : NativeModelHttpEgressSelection
  quantities : @model.ModelQuantityCapacity
  raw : NativeClientModelHttpRawOriginals
  ca_path : String
  connect_timeout_ms : Int
  operation_timeout_ms : Int
  credential_expires_at : Int64
  max_projection_frames : Int
}

///|
priv struct NativeModelHttpTransportPolicy {
  observation : @host.ClientInferEgressObservation
  attempt_tokens : Int64
  attempt_cost_units : Int64
  ca_path : String
  connect_timeout_ms : Int
  operation_timeout_ms : Int
  credential_expires_at : Int64
  max_projection_frames : Int
}

///|
priv struct NativeModelHttpPolicySelection {
  transport : NativeModelHttpTransportPolicy
  output_policy : @decode.Cursor?
  retention : String
  metadata : String
  clock : String
  data : String
  available_until : String
  delete_by : String
  extension_ceiling_at : String
  metadata_delete_by : String
}

///|
fn native_model_http_policy_text(
  fields : @decode.ObjectView,
  name : String,
  limit : Int,
) -> String? {
  guard @decode.lookup(fields, name) is Some(cursor) &&
    @decode.text(cursor) is Ok(text) &&
    !text.is_empty() &&
    text.length() <= limit &&
    !text.contains("\u{0}") else {
    return None
  }
  Some(text)
}

///|
fn native_model_http_policy_integer(
  fields : @decode.ObjectView,
  name : String,
  minimum : Int64,
  maximum : Int64,
) -> Int64? {
  guard @decode.lookup(fields, name) is Some(cursor) &&
    @decode.safe_integer(cursor) is Ok(value) &&
    value >= minimum &&
    value <= maximum else {
    return None
  }
  Some(value)
}

///|
fn native_model_http_transport_policy(
  fields : @decode.ObjectView,
) -> NativeModelHttpTransportPolicy? {
  guard native_model_http_policy_text(fields, "ca_path", 4096) is Some(ca_path) &&
    local_runtime_path_valid(ca_path) &&
    native_model_http_policy_integer(
      fields, "connect_timeout_ms", 1L, 2147483647L,
    )
    is Some(connect_timeout) &&
    native_model_http_policy_integer(
      fields, "operation_timeout_ms", connect_timeout, 2147483647L,
    )
    is Some(operation_timeout) &&
    native_model_http_policy_integer(
      fields, "credential_expires_at_ms", 1L, 9007199254740991L,
    )
    is Some(credential_expires_at) &&
    native_model_http_policy_integer(
      fields, "max_projection_frames", 1L, 2147483647L,
    )
    is Some(max_projection_frames) &&
    native_model_http_policy_integer(
      fields, "attempt_tokens", 1L, 9007199254740991L,
    )
    is Some(attempt_tokens) &&
    native_model_http_policy_integer(
      fields, "attempt_cost_units", 0L, 9007199254740991L,
    )
    is Some(attempt_cost_units) &&
    native_model_http_policy_text(fields, "provider_region", 128)
    is Some(region) &&
    @decode.lookup(fields, "provider_retention") is Some(retention) &&
    @decode.boolean(retention) is Ok(provider_retention) &&
    @decode.lookup(fields, "provider_training_use") is Some(training) &&
    @decode.boolean(training) is Ok(training_use) else {
    return None
  }
  let classification : @environment.DataClassification = match
    native_model_http_policy_text(fields, "input_classification", 16) {
    Some("public") => Public
    Some("internal") => Internal
    Some("confidential") => Confidential
    Some("restricted") => Restricted
    _ => return None
  }
  Some({
    observation: { classification, region, provider_retention, training_use, },
    attempt_tokens,
    attempt_cost_units,
    ca_path,
    connect_timeout_ms: connect_timeout.to_int(),
    operation_timeout_ms: operation_timeout.to_int(),
    credential_expires_at,
    max_projection_frames: max_projection_frames.to_int(),
  })
}

///|
fn native_model_http_run_policy_selection(
  body : Bytes,
  limits : @environment.Limits,
) -> NativeModelHttpPolicySelection? {
  guard @source.parse_json_bytes_preserving(body, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    })
    is Ok(node) &&
    @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(cursor) else {
    return None
  }
  guard @decode.closed_object(cursor, [
      "ca_path", "connect_timeout_ms", "operation_timeout_ms", "credential_expires_at_ms",
      "max_projection_frames", "attempt_tokens", "attempt_cost_units", "input_classification",
      "provider_region", "provider_retention", "provider_training_use", "retention_contract_file",
      "metadata_retention_file", "clock_contract_file", "data_policy_file", "available_until",
      "delete_by", "extension_ceiling_at", "metadata_delete_by", "upstream_model_outputs",
    ])
    is Ok(fields) &&
    native_model_http_transport_policy(fields) is Some(transport) &&
    native_model_http_policy_text(fields, "retention_contract_file", 4096)
    is Some(retention) &&
    native_model_http_policy_text(fields, "metadata_retention_file", 4096)
    is Some(metadata) &&
    native_model_http_policy_text(fields, "clock_contract_file", 4096)
    is Some(clock) &&
    native_model_http_policy_text(fields, "data_policy_file", 4096)
    is Some(data) &&
    native_model_http_policy_text(fields, "available_until", 64)
    is Some(available_until) &&
    native_model_http_policy_text(fields, "delete_by", 64) is Some(delete_by) &&
    native_model_http_policy_text(fields, "extension_ceiling_at", 64)
    is Some(extension_ceiling_at) &&
    native_model_http_policy_text(fields, "metadata_delete_by", 64)
    is Some(metadata_delete_by) else {
    return None
  }
  Some({
    transport,
    output_policy: @decode.lookup(fields, "upstream_model_outputs"),
    retention,
    metadata,
    clock,
    data,
    available_until,
    delete_by,
    extension_ceiling_at,
    metadata_delete_by,
  })
}

///|
fn read_native_model_http_policy_body(
  configuration : NativeModelHttpConfiguration,
  name : String,
  kind : String,
  limits : @environment.Limits,
  operations : NativeClientJournalOperationAccess,
) -> Result[@publication.CapturedEffectDependencyBody, NativeLocalAdoptionIssue] {
  guard name != configuration.selected.credential_file &&
    configuration.settings.files.iter().find_first(file => file.name == name)
    is Some(original) else {
    return Err(CustodyLost)
  }
  // Admission requires the canonical bytes to equal this file. Bound the
  // writer by the exact wire length without limiting any accepted body.
  let limits = {
    ..limits,
    max_bytes: Int::min(limits.max_bytes, original.body.length()),
  }
  // Each canonical dependency reader returns its own wire, root and reference
  // records. The parser and canonical hash/write scratch are transient.
  let nodes = Int::min(original.body.length(), limits.max_nodes).to_int64()
  guard native_model_http_profile_construction(original.body, limits)
    is Some((base, scratch)) else {
    return Err(ConfigurationLimit)
  }
  let references : @execution.PreparationRepresentationUnits = {
    record_headers: 1L + nodes,
    reference_slots: 2L * nodes,
    scalar_words: 0L,
    owned_utf16_units: original.body.length().to_int64(),
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([base, references])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      scratch,
      references,
      // The dependency reader checks the canonical output after hashing it.
      // Its bounded writer and its UTF-16 output can overlap the input parse.
      {
        record_headers: 16L,
        reference_slots: 24L,
        scalar_words: 16L,
        owned_utf16_units: 3L * limits.max_bytes.to_int64(),
        owned_wire_bytes: 3L * limits.max_bytes.to_int64(),
      },
    ])
    is Some(working) else {
    return Err(ConfigurationLimit)
  }
  if fund_native_model_http_configuration(operations, retained, working)
    is Err(issue) {
    return Err(issue)
  }
  let wire = @utf8.decode(original.body) catch { _ => return Err(CustodyLost) }
  // Effective data policy may use an identity distinct from its file hash.
  // Work admission checks its canonical CID against the actual compiled Run.
  let identity = if kind == "data_policy" {
    None
  } else {
    Some(original.content_cid)
  }
  @publication.admit_captured_effect_dependency_body(
    kind,
    identity,
    wire,
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).map_err(_ => CustodyLost)
}

///|
priv enum NativeModelHttpPolicyIssue {
  PolicyOriginal(NativeLocalAdoptionIssue)
  PolicyEgress(@host.ClientInferEgressIssue)
}

///|
priv suberror NativeModelHttpPolicyStop {
  NativeModelHttpPolicyStop(NativeLocalAdoptionIssue)
}

///|
fn[T] require_native_model_http_policy(
  result : Result[T, NativeLocalAdoptionIssue],
) -> T raise NativeModelHttpPolicyStop {
  match result {
    Ok(value) => value
    Err(issue) => raise NativeModelHttpPolicyStop(issue)
  }
}

///|
fn read_native_model_http_run_policy(
  configuration : NativeModelHttpConfiguration,
  occurrence : @host.ClientInferOccurrence,
  execution : @environment.ModelExecutionContract,
  binding : @publication.RunEvidenceValue,
  limits : @environment.Limits,
  operations : NativeClientJournalOperationAccess,
) -> Result[NativeModelHttpRunPolicy, NativeModelHttpPolicyIssue] {
  try {
    guard configuration.policy_file is Some(name) &&
      configuration.settings.files.iter().find_first(file => file.name == name)
      is Some(original) else {
      return Err(PolicyOriginal(CustodyLost))
    }
    let (retained, working) = native_model_http_profile_construction(
      original.body,
      limits,
    ).unwrap_or_else(() => raise NativeModelHttpPolicyStop(ConfigurationLimit))
    require_native_model_http_policy(
      fund_native_model_http_configuration(operations, retained, working),
    )
    guard native_model_http_run_policy_selection(original.body, limits)
      is Some(selected) else {
      return Err(PolicyOriginal(CustodyLost))
    }
    let transport = selected.transport
    let totals : @resources.QuantityAmounts = {
      tokens: @environment.model_execution_ceiling(
        execution,
        TotalTokenReservation,
      ),
      cost_units: @environment.model_execution_ceiling(
        execution,
        TotalCostUnits,
      ),
      duration_ms: @environment.model_execution_ceiling(
        execution,
        TotalDurationMs,
      ),
    }
    let attempt : @resources.QuantityAmounts = {
      tokens: transport.attempt_tokens,
      cost_units: transport.attempt_cost_units,
      duration_ms: transport.operation_timeout_ms.to_int64(),
    }
    if attempt.tokens > totals.tokens ||
      attempt.cost_units > totals.cost_units ||
      attempt.duration_ms > totals.duration_ms {
      return Err(PolicyOriginal(ConfigurationLimit))
    }
    let observed = transport.observation
    let egress = match
      @host.prepare_client_infer_occurrence_egress(occurrence, execution, () => {
        Some(observed)
      }) {
      Ok(@host.EgressAdmitted(value)) => {
        if selected.output_policy is Some(_) {
          return Err(PolicyOriginal(CustodyLost))
        }
        NativeEgressReady(value)
      }
      Ok(@host.EgressPending(pending)) => {
        guard selected.output_policy is Some(declared) else {
          return Err(PolicyEgress(UnknownClassification))
        }
        let count = @host.client_infer_pending_egress_result_count(pending).to_int64()
        let units : @execution.PreparationRepresentationUnits = {
          record_headers: 4L + count,
          reference_slots: 10L + 7L * count,
          scalar_words: 1L + 4L * count,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        }
        require_native_model_http_policy(
          fund_native_model_http_configuration(operations, units, units),
        )
        guard admit_native_model_http_output_policy(
            declared,
            pending,
            configuration.settings,
            original,
            binding,
            configuration.response,
          )
          is Some(policy) else {
          return Err(PolicyOriginal(CustodyLost))
        }
        NativeEgressPending(policy)
      }
      Err(issue) => return Err(PolicyEgress(issue))
    }
    let retention = require_native_model_http_policy(
      read_native_model_http_policy_body(
        configuration,
        selected.retention,
        "retention_contract",
        limits,
        operations,
      ),
    )
    let metadata = require_native_model_http_policy(
      read_native_model_http_policy_body(
        configuration,
        selected.metadata,
        "metadata_retention_policy",
        limits,
        operations,
      ),
    )
    let clock = require_native_model_http_policy(
      read_native_model_http_policy_body(
        configuration,
        selected.clock,
        "clock_contract",
        limits,
        operations,
      ),
    )
    let data = require_native_model_http_policy(
      read_native_model_http_policy_body(
        configuration,
        selected.data,
        "data_policy",
        limits,
        operations,
      ),
    )
    Ok({
      egress,
      quantities: { limits: totals, per_attempt: attempt, },
      raw: {
        retention,
        metadata,
        clock,
        data,
        available_until: selected.available_until,
        delete_by: selected.delete_by,
        extension_ceiling_at: selected.extension_ceiling_at,
        metadata_delete_by: selected.metadata_delete_by,
      },
      ca_path: transport.ca_path,
      connect_timeout_ms: transport.connect_timeout_ms,
      operation_timeout_ms: transport.operation_timeout_ms,
      credential_expires_at: transport.credential_expires_at,
      max_projection_frames: transport.max_projection_frames,
    })
  } catch {
    NativeModelHttpPolicyStop(issue) => Err(PolicyOriginal(issue))
  }
}
