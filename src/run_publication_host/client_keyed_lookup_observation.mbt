///|
/// Evidence borrows the original complete key-set and all physical child
/// holdings. It neither owns another acquisition nor completes a Compute task.
struct ClientKeyedLookupObservation {
  lookup : ClientKeyedLookupInput
  input : @publication.RunEvidenceValue
  source : @publication.RunEvidenceValue
  logical_relation_cid : String
}

///|
pub fn issue_client_keyed_lookup_observation(
  lookup : ClientKeyedLookupInput,
  authority_scope_cid : String,
  observed_at : String,
) -> Result[ClientKeyedLookupObservation, ClientKeyedRequestIssue] {
  let read = match finish_client_keyed_lookup_input(lookup) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard client_keyed_lookup_input_identity(lookup) is Some(snapshot) &&
    lookup.completed is Some(rows) &&
    @execution.supplied_relation_read_available(read) else {
    return Err(Assembly("observation_unavailable"))
  }
  let facts = lookup.left.acquisition.facts
  guard @planning.keyed_source_evidence_facts(facts) is Some(source) else {
    return Err(Assembly("source_facts"))
  }
  let members = match @planning.keyed_source_evidence_members(facts) {
    Ok(value) => value
    Err(_) => return Err(Assembly("source_members"))
  }
  if !@environment.connector_source_evidence_supports(members, [
      @planning.query_evidence_contract_identity(),
    ]) {
    return Err(Assembly("source_capability"))
  }
  let (logical_cid, schema_cid) = if lookup.identity_receipt is Some(receipt) {
    (
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(receipt),
      ),
      @execution.relation_schema_cid(
        @execution.completed_relation_export_schema_identity(receipt),
      ),
    )
  } else {
    let logical = match
      @execution.identify_captured_relation(rows, {
        max_bytes: lookup.max_bytes,
        max_nodes: lookup.max_work,
        max_columns: lookup.max_work,
        max_order_work: lookup.max_work,
        max_depth: 100,
      }) {
      Ok(value) => value
      Err(_) => return Err(Assembly("logical_identity"))
    }
    let schema = match
      @execution.identify_relation_schema(
        @execution.supplied_relation_read_schema(read),
        {
          max_fields: lookup.max_work,
          max_bytes: lookup.max_bytes,
          max_nodes: lookup.max_work,
          max_depth: 100,
        },
      ) {
      Ok(value) => value
      Err(_) => return Err(Assembly("schema_identity"))
    }
    (
      @execution.logical_relation_cid(logical),
      @execution.relation_schema_cid(schema),
    )
  }
  let input = match
    seal_client_source_input_logical(
      logical_cid,
      schema_cid,
      source.source_contract_cid,
    ) {
    Ok(value) => value
    Err(_) => return Err(Assembly("logical_evidence"))
  }
  let (schema_cid, capability_cid) = @environment.connector_source_evidence_member_cids(
    members,
  )
  let evidence = match
    @publication.seal_completed_source_observation({
      input,
      source_ref: source.source_ref,
      source_contract_cid: source.source_contract_cid,
      schema_evidence_cid: schema_cid,
      capability_evidence_cid: capability_cid,
      authority_scope_cid,
      source_data_policy_cid: source.source_data_policy_cid,
      data_classification: source.data_classification,
      source_view_contract_cid: source.source_view_contract_cid,
      observed_at,
      snapshot_ref: snapshot,
    }) {
    Ok(value) => value
    Err(_) => return Err(Assembly("source_evidence"))
  }
  Ok({ lookup, input, source: evidence, logical_relation_cid: logical_cid, })
}

///|
pub fn client_keyed_lookup_observation_wires(
  value : ClientKeyedLookupObservation,
) -> (String, String)? {
  if client_keyed_lookup_input_identity(value.lookup) is None {
    return None
  }
  Some(
    (
      @publication.run_evidence_value_json(value.input),
      @publication.run_evidence_value_json(value.source),
    ),
  )
}

///|
/// Read the original immutable evidence and computed identity while its lookup
/// is live. No serialization, JSON admission or replacement Source is issued.
pub fn client_keyed_lookup_observation_originals(
  value : ClientKeyedLookupObservation,
) -> (@publication.RunEvidenceValue, @publication.RunEvidenceValue, String)? {
  if client_keyed_lookup_input_identity(value.lookup) is None {
    return None
  }
  Some((value.input, value.source, value.logical_relation_cid))
}
