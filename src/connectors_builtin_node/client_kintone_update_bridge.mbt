// Same-runtime original kintone UPDATE Mapping DATA for the installed Host.
// These ports issue no Account decision, target observation, claim or send.

///|
#export_name("clientProgramKintonePrepareUpdateMapping")
pub fn client_program_kintone_prepare_update_mapping(
  original : @kintone_host.RecordDeclaration,
  resource : String,
  sources : Array[@client_row_source_host.RowMappingSource],
  approval : String,
  limits : @client_row_source_host.RowDeclarationLimits,
) -> Result[
  @kintone_host.RecordUpdateMapping,
  @client_row_source_host.RowMappingIssue,
] {
  @kintone_host.prepare_record_update_mapping(
    original, resource, sources, approval, limits,
  )
}

///|
fn client_kintone_original_update_mapping(
  mapping : @kintone_host.RecordUpdateMapping,
) -> Result[
  @client_row_source_host.RowMapping,
  @client_row_source_host.RowMappingIssue,
] {
  if !@kintone_host.record_update_mapping_is_original(mapping) {
    return Err(InvalidSpecification)
  }
  Ok(@kintone_host.record_update_mapping(mapping))
}

///|
#export_name("clientProgramKintoneUpdateMappingBody")
pub fn client_program_kintone_update_mapping_body(
  mapping : @kintone_host.RecordUpdateMapping,
) -> Result[String, @client_row_source_host.RowMappingIssue] {
  match client_kintone_original_update_mapping(mapping) {
    Ok(original) => Ok(original.body)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("clientProgramKintoneUpdateMappingRef")
pub fn client_program_kintone_update_mapping_ref(
  mapping : @kintone_host.RecordUpdateMapping,
) -> Result[String, @client_row_source_host.RowMappingIssue] {
  match client_kintone_original_update_mapping(mapping) {
    Ok(original) => Ok(original.mapping_ref)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("clientProgramKintoneUpdateMappingCid")
pub fn client_program_kintone_update_mapping_cid(
  mapping : @kintone_host.RecordUpdateMapping,
) -> Result[String, @client_row_source_host.RowMappingIssue] {
  match client_kintone_original_update_mapping(mapping) {
    Ok(original) => Ok(original.mapping_cid)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("clientProgramKintoneUpdateMappingMatchesDeclaration")
pub fn client_program_kintone_update_mapping_matches_declaration(
  mapping : @kintone_host.RecordUpdateMapping,
  original : @kintone_host.RecordDeclaration,
) -> Bool {
  @kintone_host.record_update_mapping_matches_declaration(mapping, original)
}

///|
#export_name("clientProgramKintoneUpdateMappingMatchesRequest")
pub fn client_program_kintone_update_mapping_matches_request(
  mapping : @kintone_host.RecordUpdateMapping,
  request : @kintone_catalog.RecordUpdateRequest,
) -> Bool {
  @kintone_host.record_update_mapping_matches_request(mapping, request)
}

///|
#export_name("clientProgramKintonePrepareUpdateProposal")
pub fn client_program_kintone_prepare_update_proposal(
  mapping : @kintone_host.RecordUpdateMapping,
  identity : String,
  bytes : Bytes,
  max_input_bytes : Int,
  write_limits : @kintone_catalog.RecordWriteLimits,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_host.RecordUpdateProposal,
  @kintone_host.RecordUpdateExecutionIssue,
] {
  @kintone_host.prepare_record_update_proposal(
    mapping, identity, bytes, max_input_bytes, write_limits, limits,
  )
}

///|
#export_name("clientProgramKintoneUpdateProposalIdentity")
pub fn client_program_kintone_update_proposal_identity(
  proposal : @kintone_host.RecordUpdateProposal,
) -> String {
  @kintone_host.record_update_proposal_identity(proposal)
}

///|
#export_name("clientProgramKintoneUpdateProposalValueWire")
pub fn client_program_kintone_update_proposal_value_wire(
  proposal : @kintone_host.RecordUpdateProposal,
) -> String {
  @kintone_host.record_update_proposal_value_wire(proposal)
}

///|
#export_name("clientProgramKintoneUpdateProposalApp")
pub fn client_program_kintone_update_proposal_app(
  proposal : @kintone_host.RecordUpdateProposal,
) -> String {
  @kintone_host.record_update_proposal_app_id(proposal)
}

///|
#export_name("clientProgramKintoneUpdateTargetReadBody")
pub fn client_program_kintone_update_target_read_body(
  proposal : @kintone_host.RecordUpdateProposal,
  max_fields : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @kintone_host.RecordUpdateExecutionIssue] {
  @kintone_host.record_update_target_read_body(
    proposal, max_fields, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramKintoneUpdateMappingRecheckForm")
pub fn client_program_kintone_update_mapping_recheck_form(
  mapping : @kintone_host.RecordUpdateMapping,
  bytes : Bytes,
  limits : @kintone_catalog.FormFieldLimits,
) -> Result[Unit, @kintone_host.RecordUpdateExecutionIssue] {
  @kintone_host.record_update_mapping_recheck_form(mapping, bytes, limits)
}

///|
#export_name("clientProgramKintonePrepareUpdatePreview")
pub fn client_program_kintone_prepare_update_preview(
  proposal : @kintone_host.RecordUpdateProposal,
  bytes : Bytes,
  pages : @kintone_catalog.RecordPageLimits,
  values : @kintone_catalog.RecordValueLimits,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_host.RecordUpdatePreview,
  @kintone_host.RecordUpdateExecutionIssue,
] {
  @kintone_host.prepare_record_update_preview(
    proposal, bytes, pages, values, limits,
  )
}

///|
#export_name("clientProgramKintoneUpdatePreviewIdentity")
pub fn client_program_kintone_update_preview_identity(
  preview : @kintone_host.RecordUpdatePreview,
) -> String {
  @kintone_host.record_update_preview_identity(preview)
}

///|
#export_name("clientProgramKintoneUpdatePreviewBeforeWire")
pub fn client_program_kintone_update_preview_before_wire(
  preview : @kintone_host.RecordUpdatePreview,
) -> String {
  @kintone_host.record_update_preview_before_wire(preview)
}

///|
#export_name("clientProgramKintoneUpdatePreviewVersionCid")
pub fn client_program_kintone_update_preview_version_cid(
  preview : @kintone_host.RecordUpdatePreview,
) -> String {
  @kintone_host.record_update_preview_version_cid(preview)
}

///|
#export_name("clientProgramKintoneUpdatePreviewRevision")
pub fn client_program_kintone_update_preview_revision(
  preview : @kintone_host.RecordUpdatePreview,
) -> String {
  @kintone_host.record_update_preview_revision(preview)
}

///|
#export_name("clientProgramKintoneFinalizeUpdateRequest")
pub fn client_program_kintone_finalize_update_request(
  proposal : @kintone_host.RecordUpdateProposal,
  preview : @kintone_host.RecordUpdatePreview,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_catalog.RecordUpdateRequest,
  @kintone_host.RecordUpdateExecutionIssue,
] {
  @kintone_host.finalize_record_update_request(proposal, preview, limits)
}

///|
#export_name("clientProgramKintoneUpdateExecutionMatches")
pub fn client_program_kintone_update_execution_matches(
  proposal : @kintone_host.RecordUpdateProposal,
  preview : @kintone_host.RecordUpdatePreview,
  request : @kintone_catalog.RecordUpdateRequest,
) -> Bool {
  @kintone_host.record_update_execution_matches(proposal, preview, request)
}

///|
#export_name("clientProgramKintoneRestoreUpdateExecution")
pub fn client_program_kintone_restore_update_execution(
  mapping : @kintone_host.RecordUpdateMapping,
  identity : String,
  value_bytes : Bytes,
  target_bytes : Bytes,
  original_body : String,
  max_input_bytes : Int,
  pages : @kintone_catalog.RecordPageLimits,
  values : @kintone_catalog.RecordValueLimits,
  write_limits : @kintone_catalog.RecordWriteLimits,
  limits : @kintone_catalog.RecordMutationLimits,
  before_limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  (
    @kintone_host.RecordUpdateProposal,
    @kintone_host.RecordUpdatePreview,
    @kintone_catalog.RecordUpdateRequest,
  ),
  @kintone_host.RecordUpdateExecutionIssue,
] {
  @kintone_host.restore_record_update_execution(
    mapping,
    identity,
    value_bytes,
    target_bytes,
    original_body,
    max_input_bytes,
    pages,
    values,
    write_limits,
    limits,
    preview_limits=before_limits,
  )
}

///|
#export_name("clientProgramKintoneUpdateEffectOutcome")
pub fn client_program_kintone_update_effect_outcome(
  request : @kintone_catalog.RecordUpdateRequest,
  response : @kintone_catalog.RecordUpdateAcknowledgement,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_catalog.RecordUpdateEffectOutcome,
  @kintone_catalog.RecordMutationIssue,
] {
  @kintone_catalog.project_record_update_effect_outcome(
    request, response, limits,
  )
}

///|
#export_name("clientProgramKintoneUpdateEffectOutcomeWire")
pub fn client_program_kintone_update_effect_outcome_wire(
  value : @kintone_catalog.RecordUpdateEffectOutcome,
) -> String {
  @kintone_catalog.record_update_effect_outcome_wire(value)
}

///|
#export_name("clientProgramKintoneUpdateEffectOutcomeMatchesRequest")
pub fn client_program_kintone_update_effect_outcome_matches_request(
  value : @kintone_catalog.RecordUpdateEffectOutcome,
  request : @kintone_catalog.RecordUpdateRequest,
) -> Bool {
  @kintone_catalog.record_update_effect_outcome_matches_request(value, request)
}

///|
#export_name("clientProgramKintoneUpdateEffectOutcomeResponseSha256")
pub fn client_program_kintone_update_effect_outcome_response_sha256(
  value : @kintone_catalog.RecordUpdateEffectOutcome,
) -> String {
  @kintone_catalog.record_update_effect_outcome_response_sha256(value)
}

// Same Common issuer's native UPDATE constructor quantities. These private
// DATA ports do not reserve, authorize, admit a target or acknowledge cleanup.

///|
#export_name("clientProgramKintoneUpdateProposalConstructionCapacity")
pub fn client_program_kintone_update_proposal_construction_capacity(
  mapping : @kintone_host.RecordUpdateMapping,
  max_input_bytes : Int,
  write : @kintone_catalog.RecordWriteLimits,
  request : @kintone_catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_update_proposal_construction_capacity(
    mapping, max_input_bytes, write, request,
  )
}

///|
#export_name("clientProgramKintoneUpdateFormConstructionCapacity")
pub fn client_program_kintone_update_form_construction_capacity(
  mapping : @kintone_host.RecordUpdateMapping,
  body_bytes : Int,
  limits : @kintone_catalog.FormFieldLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_update_form_construction_capacity(
    mapping, body_bytes, limits,
  )
}

///|
#export_name("clientProgramKintoneUpdateTargetConstructionCapacity")
pub fn client_program_kintone_update_target_construction_capacity(
  mapping : @kintone_host.RecordUpdateMapping,
  body_bytes : Int,
  pages : @kintone_catalog.RecordPageLimits,
  values : @kintone_catalog.RecordValueLimits,
  limits : @kintone_catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_update_target_construction_capacity(
    mapping, body_bytes, pages, values, limits,
  )
}

///|
#export_name("clientProgramKintoneUpdateFinalizationConstructionCapacity")
pub fn client_program_kintone_update_finalization_construction_capacity(
  mapping : @kintone_host.RecordUpdateMapping,
  limits : @kintone_catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_update_finalization_construction_capacity(
    mapping, limits,
  )
}

///|
#export_name("clientProgramKintoneUpdateResponseConstructionCapacity")
pub fn client_program_kintone_update_response_construction_capacity(
  mapping : @kintone_host.RecordUpdateMapping,
  body_bytes : Int,
  limits : @kintone_catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_update_response_construction_capacity(
    mapping, body_bytes, limits,
  )
}

///|
#export_name("clientProgramKintoneUpdateAddConstructionCapacity")
pub fn client_program_kintone_update_add_construction_capacity(
  native : @execution.ExecutionCapacity,
  host : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity? {
  @execution.add_execution_capacity(native, host)
}

///|
#export_name("clientProgramKintoneUpdateRecipeCapacities")
pub fn client_program_kintone_update_recipe_capacities(
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
  guard original.length() == 4 &&
    output_limits.length() == 9 &&
    limits.length() == 18 &&
    cold_original is Some(finalization) else {
    return Err(Unsupported)
  }
  // Cold kintone restoration really re-admits its saved original target and
  // rebuilds the final native request. Core separately includes the original
  // proposal constructor. Keep extra returned material per row and only the
  // sequential constructor workspace on the SAME member capture.
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  let retained = if host_input_bytes == 0 {
    0L
  } else {
    @execution.execution_capacity_retained_bytes(finalization)
  }
  let workspace = if host_input_bytes == 0 {
    0L
  } else {
    @execution.execution_capacity_execution_bytes(finalization) - retained
  }
  let cold_row = @execution.execution_capacity(retained, retained).unwrap()
  let cold_work = @execution.execution_capacity(0L, workspace).unwrap()
  @client_local_host.installed_described_effect_recipe_capacities(
    // JavaScript supplies the complete vector. Keep its generic Option
    // representation inside this typed bridge, just like capture_original.
    Some([
      (
        original[0],
        None,
        Some({
          max_input_bytes: output_limits[0],
          max_nodes: output_limits[1],
          max_depth: output_limits[2],
        }),
      ),
      (
        original[1],
        None,
        Some({
          max_input_bytes: output_limits[3],
          max_nodes: output_limits[4],
          max_depth: output_limits[5],
        }),
      ),
      (
        original[2],
        None,
        Some({
          max_input_bytes: output_limits[6],
          max_nodes: output_limits[7],
          max_depth: output_limits[8],
        }),
      ),
      (original[3], None, None),
    ]),
    Some([cold_work, cold_row, zero]),
    limits[0],
    limits[1],
    limits[2],
    limits[3],
    limits[4],
    limits[5],
    limits[6],
    limits[7],
    true,
    limits[8],
    limits[9],
    limits[10],
    limits[11],
    limits[12],
    limits[13],
    limits[14],
    limits[15],
    limits[16],
    limits[17],
    metadata_units,
    response_read_quantum~,
    metadata_on_child=true,
    target_on_child=true,
    // Three phases, each with one describe Form plus before/target/after.
    // The Plan keeps all thirteen distinct original physical slots.
    metadata_occurrences=3,
    target_occurrences=9,
    defer_ledger_codec=control_wire_bytes > 0,
    control_wire_bytes=if control_wire_bytes == 0 {
      None
    } else {
      Some(control_wire_bytes)
    },
    host_input_bytes=if host_input_bytes < 0 {
      None
    } else {
      Some(host_input_bytes)
    },
  )
}

///|
#export_name("clientProgramKintoneUpdateMappingConstructionCapacity")
pub fn client_program_kintone_update_mapping_construction_capacity(
  original : @kintone_host.RecordDeclaration,
  source_count : Int,
  input_units : Int64,
  limits : @client_row_source_host.RowDeclarationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_update_mapping_construction_capacity(
    original, source_count, input_units, limits,
  )
}

///|
#export_name("clientProgramKintoneUpdateInstallationConstructionCapacity")
pub fn client_program_kintone_update_installation_construction_capacity(
  fields : Int,
  text_units : Int,
  retained_text_units : Int,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_update_installation_construction_capacity(
    fields, text_units, retained_text_units,
  )
}
