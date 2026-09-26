///|
/// Checked source metadata for one acquired Query. Physical capability,
/// observed schema, read view, freshness and current authority are supplied
/// by the Host after this logical selection.
pub struct QuerySourceEvidenceFacts {
  source_ref : String
  source_contract_cid : String
  carrier_schema_contract_cid : String
  source_data_policy_cid : String
  data_classification : String
  source_view_contract_cid : String
}

///|
pub fn query_requirement_source_evidence_facts(
  requirement : QueryRequirement,
) -> QuerySourceEvidenceFacts? {
  let acquisition = @query.query_sequence_requirement(
    requirement.material.owner,
  )
  let requests = @acquisition.query_acquisition_owner(acquisition)
  guard @acquisition.pipeline_request_at(
      requests,
      @acquisition.query_acquisition_source_index(acquisition),
    )
    is Some(@acquisition.Direct(mode, _)) else {
    return None
  }
  let selected = @acquisition.mode_input(mode)
  if @acquisition.selected_cid(selected) != requirement.source_contract_cid ||
    @environment.read_mode_kind(@acquisition.mode_contract(mode)) !=
    @environment.SnapshotMode {
    return None
  }
  let catalog = @acquisition.catalog_owner(selected)
  let selected_item = @environment.source_request_member(
    @acquisition.selected_contract(selected),
  )
  let carriers = @environment.source_request_carriers(catalog)
  guard @environment.source_view_carrier(carriers, selected_item)
    is Some(carrier) else {
    return None
  }
  let schema = @environment.source_view_carrier_schema(carrier)
  let schema_cid = @environment.contract_identity(
      @environment.carrier_schema_envelope(schema),
    ).2
  let policies = @environment.value_contract_policies(
    @environment.source_view_shape_values(
      @environment.read_mode_shapes(@environment.carrier_schema_modes(carriers)),
    ),
  )
  guard @environment.source_view_policy(policies, selected_item)
    is Some(view_policy) else {
    return None
  }
  let data_policy = @environment.source_view_data_policy(view_policy)
  if @environment.data_policy_source(data_policy) != requirement.source_ref {
    return None
  }
  let data_policy_cid = @environment.contract_identity(
      @environment.data_policy_envelope(data_policy),
    ).2
  let classification = match @environment.data_classification(data_policy) {
    @environment.Public => "public"
    @environment.Internal => "internal"
    @environment.Confidential => "confidential"
    @environment.Restricted => "restricted"
    @environment.Unknown => "unknown"
  }
  Some({
    source_ref: requirement.source_ref,
    source_contract_cid: requirement.source_contract_cid,
    carrier_schema_contract_cid: schema_cid,
    source_data_policy_cid: data_policy_cid,
    data_classification: classification,
    source_view_contract_cid: @acquisition.selected_cid(selected),
  })
}

///|
pub fn query_source_evidence_fact_values(
  facts : QuerySourceEvidenceFacts,
) -> Array[String] {
  [
    facts.source_ref,
    facts.source_contract_cid,
    facts.carrier_schema_contract_cid,
    facts.source_data_policy_cid,
    facts.data_classification,
    facts.source_view_contract_cid,
  ]
}

///|
/// Select evidence from the same checked Catalog environment as the Query.
/// A caller cannot substitute an unrelated environment with matching names.
pub fn query_requirement_source_evidence_members(
  requirement : QueryRequirement,
) -> Result[@environment.ConnectorSourceEvidenceMembers,
  @environment.SourceEvidenceMemberIssue] {
  guard query_requirement_source_evidence_facts(requirement) is Some(facts) else {
    return Err(@environment.ContractMismatch("checked_source"))
  }
  let acquisition = @query.query_sequence_requirement(requirement.material.owner)
  let requests = @acquisition.query_acquisition_owner(acquisition)
  guard @acquisition.pipeline_request_at(requests,
    @acquisition.query_acquisition_source_index(acquisition))
    is Some(@acquisition.Direct(mode, _)) else {
    return Err(@environment.ContractMismatch("checked_source"))
  }
  let selected = @acquisition.selected_contract(@acquisition.mode_input(mode))
  let environment = @environment.member_environment(
    @environment.source_request_member(selected),
  )
  @environment.select_connector_source_evidence_members(environment, {
    source_ref: facts.source_ref,
    source_contract_cid: facts.source_contract_cid,
    source_view_contract_cid: facts.source_view_contract_cid,
    carrier_schema_contract_cid: facts.carrier_schema_contract_cid,
    source_data_policy_cid: facts.source_data_policy_cid,
    data_classification: facts.data_classification,
  })
}
