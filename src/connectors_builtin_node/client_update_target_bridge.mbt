///|
/// Reuse existing compiler and bounded original-material owners. These bridges
/// neither resolve a current alias nor grant permission to start a Run.
pub(all) enum ClientEffectOriginalBridgeIssue {
  Manifests(@publication_host.ClientCompilationManifestIssue)
  Materials(@publication_host.ClientEffectRunMaterialsIssue)
}

///|
fn client_effect_original_manifests() -> Result[
  @publication_host.ClientCompilationManifests,
  ClientEffectOriginalBridgeIssue,
] {
  @publication_host.admit_client_compilation_manifests(
    @check_environment.compiler_grammar_manifest_wire(),
    @check_environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).map_err(issue => Manifests(issue))
}

///|
fn client_effect_original_limits() -> @publication_host.ClientValuesRunMaterialsLimits {
  {
    preparation: @publication_host.client_standard_program_preparation_limits(),
    sequence: @publication_host.client_standard_values_sequence_limits(),
    max_sequence_steps: 1000,
    max_sequence_work: 10000,
    max_evidence_bytes: 1000000,
    max_evidence_nodes: 100000,
    max_evidence_depth: 100,
  }
}

///|
#export_name("clientProgramEffectTargetSelections")
pub fn client_program_effect_target_selections(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> String? {
  @publication_host.prepared_client_effect_target_selections(prepared)
}

///|
#export_name("clientProgramIssueEffectPreparedOriginal")
pub fn client_program_issue_effect_prepared_original(
  compilation : @publication_host.ClientEffectCompilation,
) -> Result[String, @publication_host.ClientEffectRunMaterialsIssue] {
  @publication_host.issue_client_effect_prepared_original(compilation)
}

///|
#export_name("clientProgramAdmitEffectPreparedOriginal")
pub fn client_program_admit_effect_prepared_original(
  wire : String,
  expected_plan_cid : String,
  text_time : Bool,
  veca : Bool,
  rela : Bool,
  sga : Bool,
  tea : Bool,
  calendar : Bool,
  text_rank : Bool,
) -> Result[
  @publication_host.ClientEffectPreparedOriginal,
  ClientEffectOriginalBridgeIssue,
] {
  let manifests = match client_effect_original_manifests() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @publication_host.admit_client_effect_prepared_original(
    wire,
    expected_plan_cid,
    { text_time, veca, },
    { rela, sga, tea, calendar, text_rank, },
    manifests,
    client_effect_original_limits(),
    client_program_effect_limits(),
  ).map_err(issue => Materials(issue))
}

///|
#export_name("clientProgramEffectPreparedOriginalPrepared")
pub fn client_program_effect_prepared_original_prepared(
  value : @publication_host.ClientEffectPreparedOriginal,
) -> @publication_host.PreparedClientEffectComputation {
  @publication_host.client_effect_prepared_original_prepared(value)
}

///|
#export_name("clientProgramEffectPreparedOriginalCompilation")
pub fn client_program_effect_prepared_original_compilation(
  value : @publication_host.ClientEffectPreparedOriginal,
) -> @publication_host.ClientEffectCompilation {
  @publication_host.client_effect_prepared_original_compilation(value)
}

///|
#export_name("clientProgramIssuePreparedEffectRunMaterials")
pub fn client_program_issue_prepared_effect_run_materials(
  allowed : @publication_host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request : @publication_host.ClientRequestIdentity?,
) -> Result[String, @publication_host.ClientEffectRunMaterialsIssue] {
  @publication_host.issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request~,
  )
}

///|
#export_name("clientProgramAdmitEffectRunMaterials")
pub fn client_program_admit_effect_run_materials(
  wire : String,
  expected_run_cid : String,
  text_time : Bool,
  veca : Bool,
  rela : Bool,
  sga : Bool,
  tea : Bool,
  calendar : Bool,
  text_rank : Bool,
  expected_request : @publication_host.ClientRequestIdentity?,
) -> Result[
  @publication_host.ClientEffectRunMaterials,
  ClientEffectOriginalBridgeIssue,
] {
  let manifests = match client_effect_original_manifests() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @publication_host.admit_client_effect_run_materials(
    wire,
    expected_run_cid,
    { text_time, veca, },
    { rela, sga, tea, calendar, text_rank, },
    manifests,
    client_effect_original_limits(),
    client_program_effect_limits(),
    expected_request~,
  ).map_err(issue => Materials(issue))
}

///|

///|
/// Reuse the exact already-backed compiler original from this Request. The
/// existing materials Owner still binds saved evidence, full inputs and the
/// independently selected Request/Run; no compiler, Run or grant is issued.
#export_name("clientProgramAdmitEffectRunMaterialsWithCompilation")
pub fn client_program_admit_effect_run_materials_with_compilation(
  wire : String,
  expected_run_cid : String,
  compilation : @publication_host.ClientEffectCompilation,
  expected_request : @publication_host.ClientRequestIdentity,
  text_time : Bool,
  veca : Bool,
  rela : Bool,
  sga : Bool,
  tea : Bool,
  calendar : Bool,
  text_rank : Bool,
) -> Result[
  @publication_host.ClientEffectRunMaterials,
  ClientEffectOriginalBridgeIssue,
] {
  let manifests = match client_effect_original_manifests() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @publication_host.admit_client_effect_run_materials(
    wire,
    expected_run_cid,
    { text_time, veca, },
    { rela, sga, tea, calendar, text_rank, },
    manifests,
    client_effect_original_limits(),
    client_program_effect_limits(),
    expected_request=Some(expected_request),
    original_compilation=Some(compilation),
  ).map_err(issue => Materials(issue))
}

///|
#export_name("clientProgramEffectRunMaterialsPrepared")
pub fn client_program_effect_run_materials_prepared(
  value : @publication_host.ClientEffectRunMaterials,
) -> @publication_host.PreparedClientEffectComputation {
  value.prepared
}

///|
#export_name("clientProgramEffectRunMaterialsCompilation")
pub fn client_program_effect_run_materials_compilation(
  value : @publication_host.ClientEffectRunMaterials,
) -> @publication_host.ClientEffectCompilation {
  value.compilation
}

///|
#export_name("clientProgramEffectRunMaterialsAllowed")
pub fn client_program_effect_run_materials_allowed(
  value : @publication_host.ClientEffectRunMaterials,
) -> @publication_host.ClientEffectAllowedRun {
  value.allowed
}

///|
#export_name("clientProgramEffectRunMaterialsDefinition")
pub fn client_program_effect_run_materials_definition(
  value : @publication_host.ClientEffectRunMaterials,
) -> @publication.PublicationContract {
  value.run_definition
}

///|
#export_name("clientProgramEffectRunMaterialsTargetSelections")
pub fn client_program_effect_run_materials_target_selections(
  value : @publication_host.ClientEffectRunMaterials,
) -> Result[String?, @publication_host.ClientEffectUpdateTargetIssue] {
  @publication_host.restore_client_effect_run_target_selections(value)
}

///|
#export_name("clientProgramEffectTargetSelectionOriginal")
pub fn client_program_effect_target_selection_original(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> Array[@publication_host.ClientEffectUpdateTargetSelections] {
  @publication_host.client_effect_target_selection_original(prepared)
}

///|
#export_name("clientProgramEffectTargetSelectionWire")
pub fn client_program_effect_target_selection_wire(
  original : @publication_host.ClientEffectUpdateTargetSelections,
) -> String {
  @publication_host.client_effect_target_selection_wire(original)
}

///|
#export_name("clientProgramEffectTargetSelectionCid")
pub fn client_program_effect_target_selection_cid(
  original : @publication_host.ClientEffectUpdateTargetSelections,
) -> String {
  @publication_host.client_effect_target_selection_cid(original)
}

///|
#export_name("clientProgramEffectTargetSelectionMatchesPrepared")
pub fn client_program_effect_target_selection_matches_prepared(
  original : @publication_host.ClientEffectUpdateTargetSelections,
  prepared : @publication_host.PreparedClientEffectComputation,
) -> Bool {
  @publication_host.client_effect_target_selection_matches_prepared(
    original, prepared,
  )
}

///|
#export_name("clientProgramEffectTargetSelectionMatchesRun")
pub fn client_program_effect_target_selection_matches_run(
  original : @publication_host.ClientEffectUpdateTargetSelections,
  prepared : @publication_host.PreparedClientEffectComputation,
  definition : @publication.PublicationContract,
) -> Bool {
  @publication_host.client_effect_target_selection_matches_run(
    original, prepared, definition,
  )
}

///|
#export_name("clientProgramEffectTargetSelectionCurrent")
pub fn client_program_effect_target_selection_current(
  original : @publication_host.ClientEffectUpdateTargetSelections,
  prepared : @publication_host.PreparedClientEffectComputation,
  observations : String,
) -> Bool {
  @publication_host.client_effect_target_selection_current(
    original, prepared, observations,
  )
}

///|
#export_name("clientProgramIssueEffectTargetInstallation")
pub fn client_program_issue_effect_target_installation(
  facts : String,
) -> Result[(String, String), @publication_host.ClientEffectUpdateTargetIssue] {
  @publication_host.issue_client_effect_target_installation(facts)
}

///|
#export_name("clientProgramEffectTargetInstallationsShape")
pub fn client_program_effect_target_installations_shape(wire : String) -> Bool {
  @publication_host.client_effect_target_installations_shape(wire)
}

///|
#export_name("clientProgramEffectTargetPreparedOriginalShape")
pub fn client_program_effect_target_prepared_original_shape(
  wire : String,
) -> Bool {
  @publication_host.client_effect_target_prepared_original_shape(wire)
}

///|
#export_name("clientProgramEffectTargetRunOriginalShape")
pub fn client_program_effect_target_run_original_shape(
  wire : String,
  evidence : Array[String],
) -> Bool {
  match evidence {
    [] =>
      @publication_host.client_effect_target_run_original_shape(
        wire,
        None,
        None,
      )
    [prepared, authorization] =>
      @publication_host.client_effect_target_run_original_shape(
        wire,
        Some(prepared),
        Some(authorization),
      )
    _ => false
  }
}

///|
#export_name("clientProgramEffectTargetOriginalDataEqual")
pub fn client_program_effect_target_original_data_equal(
  left : String,
  right : String,
) -> Bool {
  @publication_host.client_effect_target_original_data_equal(left, right)
}

///|
#export_name("clientProgramEffectTargetSelectionDataCid")
pub fn client_program_effect_target_selection_data_cid(
  wire : String,
) -> Result[String, @publication_host.ClientEffectUpdateTargetIssue] {
  @publication_host.client_effect_target_selection_data_cid(wire)
}

///|
#export_name("clientProgramEffectTargetRunSelectionCid")
pub fn client_program_effect_target_run_selection_cid(
  wire : String,
) -> Result[Array[String], @publication_host.ClientEffectUpdateTargetIssue] {
  @publication_host.client_effect_target_run_selection_cid(wire)
}

///|
#export_name("clientProgramEffectTargetOriginalCodecLimits")
pub fn client_program_effect_target_original_codec_limits() -> Array[Int] {
  @publication_host.client_effect_target_original_codec_limits()
}

///|
#export_name("clientProgramEffectTargetSelectionMembersCurrent")
pub fn client_program_effect_target_selection_members_current(
  original : @publication_host.ClientEffectUpdateTargetSelections,
  prepared : @publication_host.PreparedClientEffectComputation,
  members : String,
) -> Bool {
  @publication_host.client_effect_target_selection_members_current(
    original, prepared, members,
  )
}
