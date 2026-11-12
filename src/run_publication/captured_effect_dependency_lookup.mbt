///|
fn is_lookup_effect_dependency_kind(kind : String) -> Bool {
  [
    "lookup_evidence", "lookup_accounting", "acquisition_attempt_receipt", "lookup_barrier",
    "native_file_content_read", "declared_file_content_read", "native_file_lookup_transport",
    "native_file_lookup_batch_plan", "native_file_lookup_request", "native_file_lookup_call_slot",
    "native_file_lookup_activation", "native_file_lookup_raw_response", "native_file_lookup_attempt_event",
    "native_file_lookup_adoption",
  ].contains(kind)
}

///|
// Strict protocol admission owns shape, canonical identity and lifecycle
// invariants. These edges retain the existing Lookup reference roles in the
// Effect dependency DAG; none is an execution, egress or physical-stop grant.
// Raw content CIDs and ContentRef payloads remain separate Store custody, not
// JSON dependency bodies. Authority/issuer identifiers are not forged grants.
fn admit_lookup_effect_dependency_body(
  kind : String,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  let contract = match
    admit_publication_contract(kind, wire, max_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(InvalidBody)
  }
  if contract.wire != wire {
    return Err(InvalidBody)
  }
  let value = contract.value
  let required : Array[(String, String)] = match kind {
    "lookup_evidence" =>
      [
        ("barrier_cid", "lookup_barrier"),
        ("input_relation_artifact_cid", "acquisition_relation"),
        ("effective_request_data_policy_cid", "data_policy"),
        ("effective_output_data_policy_cid", "data_policy"),
        ("request_key_set_cid", "request_key_set"),
        ("batch_plan_cid", "native_file_lookup_batch_plan"),
        ("source_view_contract_cid", "source_view_contract"),
        ("validated_lookup_relation_cid", "acquisition_relation"),
        ("attempt_receipt_cid", "acquisition_attempt_receipt"),
      ]
    "lookup_accounting" | "acquisition_attempt_receipt" =>
      [
        ("barrier_cid", "lookup_barrier"),
        ("batch_plan_cid", "native_file_lookup_batch_plan"),
        ("input_relation_artifact_cid", "acquisition_relation"),
      ]
    "lookup_barrier" =>
      [
        ("source_view_contract_cid", "source_view_contract"),
        ("request_schema_cid", "request_schema"),
        ("output_contract_cid", "relation_carrier"),
        ("effective_request_data_policy_cid", "data_policy"),
        ("response_source_data_policy_cid", "data_policy"),
        ("effective_response_data_policy_cid", "data_policy"),
        ("effective_output_data_policy_cid", "data_policy"),
      ]
    "native_file_content_read" | "declared_file_content_read" =>
      [
        ("source_view_contract_cid", "source_view_contract"),
        ("physical_source_view_contract_cid", "source_view_contract"),
        ("request_schema_cid", "request_schema"),
        ("response_schema_cid", "carrier_schema"),
      ]
    "native_file_lookup_transport" =>
      [
        ("source_view_contract_cid", "source_view_contract"),
        ("adapter_contract_cid", "read_execution_profile"),
        ("request_schema_cid", "request_schema"),
        ("response_schema_cid", "carrier_schema"),
      ]
    "native_file_lookup_batch_plan" =>
      [
        ("barrier_cid", "lookup_barrier"),
        ("request_key_set_cid", "request_key_set"),
        ("transport_plan_cid", "native_file_lookup_transport"),
      ]
    "native_file_lookup_request" =>
      [
        ("source_view_contract_cid", "source_view_contract"),
        ("request_schema_cid", "request_schema"),
        ("transport_plan_cid", "native_file_lookup_transport"),
      ]
    "native_file_lookup_call_slot" =>
      [
        ("batch_plan_cid", "native_file_lookup_batch_plan"),
        ("semantic_request_cid", "native_file_lookup_request"),
      ]
    "native_file_lookup_raw_response" =>
      [
        ("call_slot_cid", "native_file_lookup_call_slot"),
        ("effective_data_policy_cid", "data_policy"),
        ("effective_retention_policy_cid", "result_retention_policy"),
      ]
    "native_file_lookup_activation"
    | "native_file_lookup_attempt_event"
    | "native_file_lookup_adoption" =>
      [
        ("barrier_cid", "lookup_barrier"),
        ("batch_plan_cid", "native_file_lookup_batch_plan"),
        ("call_slot_cid", "native_file_lookup_call_slot"),
      ]
    _ => return Err(WrongDependencyKind)
  }
  let references = []
  for (field, target) in required {
    guard dependency_single_reference(value, field, target) is Some(reference) else {
      return Err(InvalidBody)
    }
    references.push(reference)
  }
  if kind == "acquisition_attempt_receipt" {
    guard dependency_single_reference(
        value, "request_key_set_cid", "request_key_set",
      )
      is Some(reference) else {
      return Err(InvalidBody)
    }
    references.push(reference)
  }
  if kind == "native_file_lookup_adoption" {
    for
      (field, target) in [
        ("activation_cid", "native_file_lookup_activation"),
        ("capture_event_cid", "native_file_lookup_attempt_event"),
        ("raw_response_artifact_cid", "native_file_lookup_raw_response"),
        ("response_schema_cid", "carrier_schema"),
        ("page_value_cid", "relation_value"),
      ] {
      guard dependency_single_reference(value, field, target) is Some(reference) else {
        return Err(InvalidBody)
      }
      references.push(reference)
    }
  }
  let optional : Array[(String, String)] = match kind {
    "lookup_evidence" | "acquisition_attempt_receipt" =>
      [
        (
          "source_request_egress_admission_cid", "source_request_egress_admission",
        ),
      ]
    "lookup_accounting" => [("previous_accounting_cid", "lookup_accounting")]
    "native_file_lookup_activation" =>
      [
        ("previous_activation_cid", "native_file_lookup_activation"),
        ("previous_attempt_event_cid", "native_file_lookup_attempt_event"),
      ]
    "native_file_lookup_attempt_event" =>
      [
        ("previous_event_cid", "native_file_lookup_attempt_event"),
        ("raw_response_artifact_cid", "native_file_lookup_raw_response"),
        ("runtime_error_cid", "runtime_error"),
      ]
    "native_file_lookup_adoption" =>
      [("previous_adoption_cid", "native_file_lookup_adoption")]
    "lookup_barrier" =>
      [
        ("lookup_execution_cid", "lookup_execution_policy"),
        ("capacity_proof_cid", "lookup_capacity_proof"),
      ]
    _ => []
  }
  for (field, target) in optional {
    match @json.object_field(value, field) {
      None | Some(@json.Null) => ()
      Some(_) => {
        guard dependency_single_reference(value, field, target)
          is Some(reference) else {
          return Err(InvalidBody)
        }
        references.push(reference)
      }
    }
  }
  if kind == "acquisition_attempt_receipt" {
    match @json.object_field(value, "previous_receipt_cid") {
      Some(@json.Null) => ()
      Some(_) => {
        guard dependency_single_reference(
            value, "previous_receipt_cid", "acquisition_attempt_receipt",
          )
          is Some(reference) else {
          return Err(InvalidBody)
        }
        references.push(reference)
      }
      None => return Err(InvalidBody)
    }
  }
  if kind == "lookup_evidence" || kind == "lookup_barrier" {
    guard dependency_list_references(
        value, "request_input_data_policy_cids", "data_policy",
      )
      is Some(items) else {
      return Err(InvalidBody)
    }
    for item in items {
      references.push(item)
    }
  }
  if ["lookup_evidence", "lookup_accounting", "acquisition_attempt_receipt"].contains(
      kind,
    ) {
    guard @json.object_field(value, "attempts") is Some(@json.Array(items)) else {
      return Err(InvalidBody)
    }
    for item in @json.array_values(items) {
      guard dependency_single_reference(
          item, "call_slot_cid", "native_file_lookup_call_slot",
        )
        is Some(slot) else {
        return Err(InvalidBody)
      }
      references.push(slot)
      if kind != "lookup_accounting" {
        guard dependency_single_reference(
            item, "semantic_request_cid", "native_file_lookup_request",
          )
          is Some(request) else {
          return Err(InvalidBody)
        }
        references.push(request)
      }
      for
        (field, target) in [
          ("raw_response_artifact_cid", "native_file_lookup_raw_response"),
          ("runtime_error_cid", "runtime_error"),
          ("usage_resolution_event_cid", "native_file_lookup_attempt_event"),
        ] {
        match @json.object_field(item, field) {
          None | Some(@json.Null) => ()
          Some(_) => {
            guard dependency_single_reference(item, field, target)
              is Some(reference) else {
              return Err(InvalidBody)
            }
            references.push(reference)
          }
        }
      }
    }
  }
  if kind == "acquisition_attempt_receipt" {
    guard @json.object_field(value, "lifecycle_evidence")
      is Some(@json.Array(items)) else {
      return Err(InvalidBody)
    }
    for item in @json.array_values(items) {
      let target = match evidence_string(item, "kind") {
        Some("accounting") => "lookup_accounting"
        Some("attempt_event") => "native_file_lookup_attempt_event"
        Some("activation") => "native_file_lookup_activation"
        Some("adoption") => "native_file_lookup_adoption"
        _ => return Err(WrongDependencyKind)
      }
      guard dependency_single_reference(item, "cid", target) is Some(reference) else {
        return Err(InvalidBody)
      }
      references.push(reference)
    }
  }
  Ok({
    node: {
      kind,
      identity: contract.identity,
      canonical_bytes: @utf8.encode(wire).length(),
      references,
    },
    wire,
    value,
    wire_usage: None,
  })
}
