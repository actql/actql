// Private original keyed UPSERT DATA. The same complete lookup selects one
// native branch; these adapters issue no Mapping, Preview, grant or claim.

///|
#export_name("clientProgramKintoneKeyUpsertProposalConstructionCapacity")
pub fn client_program_kintone_key_upsert_proposal_construction_capacity(
  mapping : @kintone_host.RecordKeyUpsertMapping,
  input : Int,
  write : @kintone_catalog.RecordWriteLimits,
  request : @kintone_catalog.RecordMutationLimits,
  lookup : @kintone_catalog.RecordLookupLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_key_upsert_proposal_construction_capacity(
    mapping, input, write, request, lookup,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertBeforeConstructionCapacity")
pub fn client_program_kintone_key_upsert_before_construction_capacity(
  mapping : @kintone_host.RecordKeyUpsertMapping,
  bytes : Int,
  pages : @kintone_catalog.RecordPageLimits,
  values : @kintone_catalog.RecordValueLimits,
  limits : @kintone_catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_key_upsert_before_construction_capacity(
    mapping, bytes, pages, values, limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertFormConstructionCapacity")
pub fn client_program_kintone_key_upsert_form_construction_capacity(
  mapping : @kintone_host.RecordKeyUpsertMapping,
  bytes : Int,
  limits : @kintone_catalog.FormFieldLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_key_upsert_form_construction_capacity(
    mapping, bytes, limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertResponseConstructionCapacity")
pub fn client_program_kintone_key_upsert_response_construction_capacity(
  mapping : @kintone_host.RecordKeyUpsertMapping,
  bytes : Int,
  limits : @kintone_catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_key_upsert_response_construction_capacity(
    mapping, bytes, limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertFinalizationConstructionCapacity")
pub fn client_program_kintone_key_upsert_finalization_construction_capacity(
  mapping : @kintone_host.RecordKeyUpsertMapping,
  write : @kintone_catalog.RecordWriteLimits,
  limits : @kintone_catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_key_upsert_finalization_construction_capacity(
    mapping, write, limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertRecoveryConstructionCapacity")
pub fn client_program_kintone_key_upsert_recovery_construction_capacity(
  mapping : @kintone_host.RecordKeyUpsertMapping,
  target_bytes : Int,
  input : Int,
  lookup : @kintone_catalog.RecordLookupLimits,
  pages : @kintone_catalog.RecordPageLimits,
  values : @kintone_catalog.RecordValueLimits,
  write : @kintone_catalog.RecordWriteLimits,
  request : @kintone_catalog.RecordMutationLimits,
  before : @kintone_catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_key_upsert_recovery_construction_capacity(
    mapping, target_bytes, input, lookup, pages, values, write, request, before,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertRecipeCapacities")
pub fn client_program_kintone_key_upsert_recipe_capacities(
  original : Array[@execution.ExecutionCapacity],
  output_limits : Array[Int],
  cold_original : @execution.ExecutionCapacity?,
  limits : Array[Int],
  metadata_units : Int64,
  response_read_quantum : Int,
  control_wire_bytes : Int,
  host_input_bytes : Int,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  kintone_guarded_recipe_capacities(
    original, output_limits, cold_original, limits, metadata_units, response_read_quantum,
    control_wire_bytes, host_input_bytes, 0, true,
  )
}

///|
#export_name("clientProgramKintoneWriteValuesJson")
pub fn client_program_kintone_write_values_json(
  catalog : @kintone_catalog.FormFieldCatalog,
  bytes : Bytes,
  max_input_bytes : Int,
  limits : @kintone_catalog.RecordWriteLimits,
) -> Result[
  @kintone_catalog.RecordWriteValues,
  @kintone_catalog.RecordWriteJsonIssue,
] {
  @kintone_catalog.prepare_record_write_values_json(
    catalog, bytes, max_input_bytes, limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertRequest")
pub fn client_program_kintone_key_upsert_request(
  lookup : @kintone_catalog.RecordLookupObservation,
  values : @kintone_catalog.RecordWriteValues,
  write_limits : @kintone_catalog.RecordWriteLimits,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_catalog.RecordKeyUpsertRequest,
  @kintone_catalog.RecordKeyUpsertIssue,
] {
  @kintone_catalog.prepare_record_key_upsert_request(
    lookup, values, write_limits, limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertUsesLookup")
pub fn client_program_kintone_key_upsert_uses_lookup(
  request : @kintone_catalog.RecordKeyUpsertRequest,
  lookup : @kintone_catalog.RecordLookupObservation,
) -> Bool {
  @kintone_catalog.record_key_upsert_request_matches_lookup(request, lookup)
}

///|
#export_name("clientProgramKintoneKeyUpsertCreateRequest")
pub fn client_program_kintone_key_upsert_create_request(
  request : @kintone_catalog.RecordKeyUpsertRequest,
) -> @kintone_catalog.RecordCreateRequest? {
  @kintone_catalog.record_key_upsert_create_request(request)
}

///|
#export_name("clientProgramKintoneKeyUpsertUpdateRequest")
pub fn client_program_kintone_key_upsert_update_request(
  request : @kintone_catalog.RecordKeyUpsertRequest,
) -> @kintone_catalog.RecordUpdateRequest? {
  @kintone_catalog.record_key_upsert_update_request(request)
}

///|
#export_name("clientProgramKintoneKeyUpsertResponse")
pub fn client_program_kintone_key_upsert_response(
  request : @kintone_catalog.RecordKeyUpsertRequest,
  status : Int,
  bytes : Bytes,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_catalog.RecordKeyUpsertAcknowledgement,
  @kintone_catalog.RecordMutationIssue,
] {
  @kintone_catalog.project_record_key_upsert_acknowledgement(
    request, status, bytes, limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertResponseUsesRequest")
pub fn client_program_kintone_key_upsert_response_uses_request(
  response : @kintone_catalog.RecordKeyUpsertAcknowledgement,
  request : @kintone_catalog.RecordKeyUpsertRequest,
) -> Bool {
  @kintone_catalog.record_key_upsert_acknowledgement_matches_request(
    response, request,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertOutcome")
pub fn client_program_kintone_key_upsert_outcome(
  request : @kintone_catalog.RecordKeyUpsertRequest,
  response : @kintone_catalog.RecordKeyUpsertAcknowledgement,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_catalog.RecordKeyUpsertEffectOutcome,
  @kintone_catalog.RecordMutationIssue,
] {
  @kintone_catalog.project_record_key_upsert_effect_outcome(
    request, response, limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertOutcomeWire")
pub fn client_program_kintone_key_upsert_outcome_wire(
  outcome : @kintone_catalog.RecordKeyUpsertEffectOutcome,
) -> String {
  @kintone_catalog.record_key_upsert_effect_outcome_wire(outcome)
}

///|
#export_name("clientProgramKintoneKeyUpsertOutcomeResponseSha256")
pub fn client_program_kintone_key_upsert_outcome_response_sha256(
  outcome : @kintone_catalog.RecordKeyUpsertEffectOutcome,
) -> String {
  @kintone_catalog.record_key_upsert_effect_outcome_response_sha256(outcome)
}

///|
#export_name("clientProgramKintoneKeyUpsertOutcomeUsesRequest")
pub fn client_program_kintone_key_upsert_outcome_uses_request(
  outcome : @kintone_catalog.RecordKeyUpsertEffectOutcome,
  request : @kintone_catalog.RecordKeyUpsertRequest,
) -> Bool {
  @kintone_catalog.record_key_upsert_effect_outcome_matches_request(
    outcome, request,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertBefore")
pub fn client_program_kintone_key_upsert_before(
  original : @kintone_host.RecordDeclaration,
  lookup : @kintone_catalog.RecordLookupObservation,
  values : @kintone_catalog.RecordValueLimits,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[@kintone_host.RecordKeyUpsertBefore, @kintone_host.RecordReadIssue] {
  @kintone_host.prepare_record_key_upsert_before(
    original, lookup, values, limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertBeforeKey")
pub fn client_program_kintone_key_upsert_before_key(
  value : @kintone_host.RecordKeyUpsertBefore,
) -> String {
  @kintone_host.record_key_upsert_before_key(value)
}

///|
#export_name("clientProgramKintoneKeyUpsertBeforeIdentity")
pub fn client_program_kintone_key_upsert_before_identity(
  value : @kintone_host.RecordKeyUpsertBefore,
) -> String {
  @kintone_host.record_key_upsert_before_identity(value)
}

///|
#export_name("clientProgramKintoneKeyUpsertBeforeTarget")
pub fn client_program_kintone_key_upsert_before_target(
  value : @kintone_host.RecordKeyUpsertBefore,
) -> @kintone_catalog.OriginalRecordTarget? {
  @kintone_host.record_key_upsert_before_target(value)
}

///|
#export_name("clientProgramKintoneKeyUpsertBeforeWire")
pub fn client_program_kintone_key_upsert_before_wire(
  value : @kintone_host.RecordKeyUpsertBefore,
) -> String? {
  @kintone_host.record_key_upsert_before_wire(value)
}

///|
#export_name("clientProgramKintoneKeyUpsertBeforeVersionCid")
pub fn client_program_kintone_key_upsert_before_version_cid(
  value : @kintone_host.RecordKeyUpsertBefore,
) -> String? {
  @kintone_host.record_key_upsert_before_version_cid(value)
}

///|
#export_name("clientProgramKintoneKeyUpsertBeforeMatches")
pub fn client_program_kintone_key_upsert_before_matches(
  value : @kintone_host.RecordKeyUpsertBefore,
  original : @kintone_host.RecordDeclaration,
  lookup : @kintone_catalog.RecordLookupObservation,
) -> Bool {
  @kintone_host.record_key_upsert_before_matches(value, original, lookup)
}

///|
#export_name("clientProgramKintoneKeyUpsertObservedRequest")
pub fn client_program_kintone_key_upsert_observed_request(
  original : @kintone_host.RecordDeclaration,
  lookup : @kintone_catalog.RecordLookupObservation,
  before : @kintone_host.RecordKeyUpsertBefore,
  values : @kintone_catalog.RecordWriteValues,
  write_limits : @kintone_catalog.RecordWriteLimits,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_catalog.RecordKeyUpsertRequest,
  @kintone_catalog.RecordKeyUpsertIssue,
] {
  if !@kintone_host.record_key_upsert_before_matches(before, original, lookup) {
    return Err(InvalidLookup)
  }
  @kintone_catalog.prepare_record_key_upsert_request(
    lookup,
    values,
    write_limits,
    limits,
    target=@kintone_host.record_key_upsert_before_target(before),
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertMappingConstructionCapacity")
pub fn client_program_kintone_key_upsert_mapping_construction_capacity(
  original : @kintone_host.RecordDeclaration,
  key : String,
  source_count : Int,
  input_units : Int64,
  limits : @client_row_source_host.RowDeclarationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_key_upsert_mapping_construction_capacity(
    original, key, source_count, input_units, limits,
  )
}

///|
#export_name("clientProgramKintonePrepareKeyUpsertMapping")
pub fn client_program_kintone_prepare_key_upsert_mapping(
  original : @kintone_host.RecordDeclaration,
  resource : String,
  key : String,
  sources : Array[@client_row_source_host.RowMappingSource],
  limits : @client_row_source_host.RowDeclarationLimits,
) -> Result[
  @kintone_host.RecordKeyUpsertMapping,
  @client_row_source_host.RowMappingIssue,
] {
  @kintone_host.prepare_record_key_upsert_mapping(
    original, resource, key, sources, limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertMappingBody")
pub fn client_program_kintone_key_upsert_mapping_body(
  mapping : @kintone_host.RecordKeyUpsertMapping,
  original : @kintone_host.RecordDeclaration,
) -> Result[String, @client_row_source_host.RowMappingIssue] {
  if !@kintone_host.record_key_upsert_mapping_matches_declaration(
      mapping, original,
    ) {
    return Err(InvalidSpecification)
  }
  Ok(@kintone_host.record_key_upsert_mapping(mapping).body)
}

///|
#export_name("clientProgramKintonePrepareKeyUpsertProposal")
pub fn client_program_kintone_prepare_key_upsert_proposal(
  mapping : @kintone_host.RecordKeyUpsertMapping,
  identity : String,
  bytes : Bytes,
  max_input_bytes : Int,
  write_limits : @kintone_catalog.RecordWriteLimits,
  lookup_limits : @kintone_catalog.RecordLookupLimits,
) -> Result[
  @kintone_host.RecordKeyUpsertProposal,
  @kintone_host.RecordKeyUpsertExecutionIssue,
] {
  @kintone_host.prepare_record_key_upsert_proposal(
    mapping, identity, bytes, max_input_bytes, write_limits, lookup_limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertProposalLookup")
pub fn client_program_kintone_key_upsert_proposal_lookup(
  proposal : @kintone_host.RecordKeyUpsertProposal,
) -> @kintone_catalog.RecordLookupRequest {
  @kintone_host.record_key_upsert_proposal_lookup(proposal)
}

///|
#export_name("clientProgramKintoneKeyUpsertProposalValueWire")
pub fn client_program_kintone_key_upsert_proposal_value_wire(
  proposal : @kintone_host.RecordKeyUpsertProposal,
) -> String {
  @kintone_host.record_key_upsert_proposal_value_wire(proposal)
}

///|
#export_name("clientProgramKintoneKeyUpsertProposalBefore")
pub fn client_program_kintone_key_upsert_proposal_before(
  proposal : @kintone_host.RecordKeyUpsertProposal,
  observed : @kintone_catalog.RecordLookupObservation,
  values : @kintone_catalog.RecordValueLimits,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_host.RecordKeyUpsertBefore,
  @kintone_host.RecordKeyUpsertExecutionIssue,
] {
  @kintone_host.prepare_record_key_upsert_proposal_before(
    proposal, observed, values, limits,
  )
}

///|
#export_name("clientProgramKintoneFinalizeKeyUpsertRequest")
pub fn client_program_kintone_finalize_key_upsert_request(
  proposal : @kintone_host.RecordKeyUpsertProposal,
  before : @kintone_host.RecordKeyUpsertBefore,
  write_limits : @kintone_catalog.RecordWriteLimits,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_catalog.RecordKeyUpsertRequest,
  @kintone_host.RecordKeyUpsertExecutionIssue,
] {
  @kintone_host.prepare_record_key_upsert_request_from_before(
    proposal, before, write_limits, limits,
  )
}

///|
#export_name("clientProgramKintoneKeyUpsertExecutionMatches")
pub fn client_program_kintone_key_upsert_execution_matches(
  proposal : @kintone_host.RecordKeyUpsertProposal,
  before : @kintone_host.RecordKeyUpsertBefore,
  request : @kintone_catalog.RecordKeyUpsertRequest,
) -> Bool {
  @kintone_host.record_key_upsert_execution_matches(proposal, before, request)
}

///|
#export_name("clientProgramKintoneKeyUpsertPhysicalRequest")
pub fn client_program_kintone_key_upsert_physical_request(
  request : @kintone_catalog.RecordKeyUpsertRequest,
) -> Result[(String, String), @kintone_host.RecordKeyUpsertExecutionIssue] {
  match @kintone_catalog.record_key_upsert_request_operation(request) {
    Insert => {
      guard @kintone_catalog.record_key_upsert_create_request(request)
        is Some(original) else {
        return Err(SavedRequestMismatch)
      }
      Ok(("create", @kintone_catalog.record_create_request_body(original)))
    }
    Update => {
      guard @kintone_catalog.record_key_upsert_update_request(request)
        is Some(original) else {
        return Err(SavedRequestMismatch)
      }
      Ok(("update", @kintone_catalog.record_update_request_body(original)))
    }
  }
}

///|
#export_name("clientProgramKintoneRestoreKeyUpsertExecution")
pub fn client_program_kintone_restore_key_upsert_execution(
  mapping : @kintone_host.RecordKeyUpsertMapping,
  identity : String,
  bytes : Bytes,
  target_bytes : Bytes,
  branch : String,
  body : String,
  max_input_bytes : Int,
  lookup : @kintone_catalog.RecordLookupLimits,
  pages : @kintone_catalog.RecordPageLimits,
  values : @kintone_catalog.RecordValueLimits,
  write : @kintone_catalog.RecordWriteLimits,
  request_limits : @kintone_catalog.RecordMutationLimits,
  before_limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  (
    @kintone_host.RecordKeyUpsertProposal,
    @kintone_host.RecordKeyUpsertBefore,
    @kintone_catalog.RecordKeyUpsertRequest,
  ),
  @kintone_host.RecordKeyUpsertExecutionIssue,
] {
  let operation : @kintone_catalog.RecordKeyUpsertOperation = match branch {
    "create" => Insert
    "update" => Update
    _ => return Err(SavedRequestMismatch)
  }
  @kintone_host.restore_record_key_upsert_execution(
    mapping, identity, bytes, target_bytes, operation, body, max_input_bytes, lookup,
    pages, values, write, request_limits, before_limits,
  )
}
