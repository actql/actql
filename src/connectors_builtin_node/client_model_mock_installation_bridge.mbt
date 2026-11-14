///|
/// Thin projection of the same portable Model owner. No Node answer selector,
/// credential, physical Provider callback or independent installation registry.
#export_name("clientProgramInstallMockProfile")
pub fn client_program_install_mock_profile(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  contract_nodes : Int,
  contract_depth : Int,
  contract_text_bytes : Int,
  max_work : Int,
) -> Result[
  @check_environment.ModelMockProfile,
  @check_environment.ModelTaskIssue,
] {
  @check_environment.install_model_mock_profile({
    bodies: { max_bytes, max_nodes, max_depth, max_members, },
    contracts: {
      max_nodes: contract_nodes,
      max_depth: contract_depth,
      max_text_bytes: contract_text_bytes,
    },
    max_work,
  })
}

///|
#export_name("clientProgramMockProfileOriginals")
pub fn client_program_mock_profile_originals(
  original : @check_environment.ModelMockProfile,
) -> (String, String, String, String, String, String)? {
  @check_environment.model_mock_profile_originals(original)
}

///|
#export_name("clientProgramMockExecutionMaterials")
pub fn client_program_mock_execution_materials(
  original : @check_environment.ModelMockProfile,
  task : @check_environment.NormalizedPublicModelTask,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  contract_nodes : Int,
  contract_depth : Int,
  contract_text_bytes : Int,
  max_work : Int,
) -> Result[
  (String, String, String, String, String, String),
  @check_environment.ModelTaskIssue,
] {
  @check_environment.model_mock_execution_materials(original, task, {
    bodies: { max_bytes, max_nodes, max_depth, max_members, },
    contracts: {
      max_nodes: contract_nodes,
      max_depth: contract_depth,
      max_text_bytes: contract_text_bytes,
    },
    max_work,
  })
}

///|
#export_name("clientProgramNormalizeMockTask")
pub fn client_program_normalize_mock_task(
  task : @check_environment.PublicModelTaskDeclaration,
  profile : @check_environment.ModelMockProfile,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  contract_nodes : Int,
  contract_depth : Int,
  contract_text_bytes : Int,
  max_work : Int,
) -> Result[
  @check_environment.NormalizedPublicModelTask,
  @check_environment.ModelTaskIssue,
] {
  @check_environment.normalize_public_mock_model_task(task, profile, {
    bodies: { max_bytes, max_nodes, max_depth, max_members, },
    contracts: {
      max_nodes: contract_nodes,
      max_depth: contract_depth,
      max_text_bytes: contract_text_bytes,
    },
    max_work,
  })
}

///|
#export_name("clientProgramInstallOriginalMock")
pub fn client_program_install_original_mock(
  profile : @check_environment.ModelMockProfile,
  task : @check_environment.PublicModelTaskDeclaration,
  normalized : @check_environment.NormalizedPublicModelTask,
  answers : @model.ModelMockAnswers,
  now : () -> String,
) -> Result[@model.ModelMockInstallation, @model.ModelMockInstallationIssue] {
  @model.install_original_model_mock(profile, task, normalized, answers, now)
}

///|
// Declaration DATA can be projected during connection without opening answer
// files. The existing NEW-call gate still requires bound original answers.
#export_name("clientProgramPrepareOriginalMock")
pub fn client_program_prepare_original_mock(
  profile : @check_environment.ModelMockProfile,
  task : @check_environment.PublicModelTaskDeclaration,
  normalized : @check_environment.NormalizedPublicModelTask,
  now : () -> String,
) -> Result[@model.ModelMockInstallation, @model.ModelMockInstallationIssue] {
  @model.prepare_original_model_mock(profile, task, normalized, now)
}

///|
#export_name("clientProgramBindOriginalMockAnswers")
pub fn client_program_bind_original_mock_answers(
  original : @model.ModelMockInstallation,
  answers : @model.ModelMockAnswers,
) -> Result[Unit, @model.ModelMockInstallationIssue] {
  @model.bind_original_model_mock_answers(original, answers)
}

///|
#export_name("clientProgramOriginalMockDeclaration")
pub fn client_program_original_mock_declaration(
  original : @model.ModelMockInstallation,
) -> Result[
  @check_environment.NormalizedPublicModelTask,
  @model.ModelMockInstallationIssue,
] {
  @model.original_model_mock_declaration(original)
}

///|
#export_name("clientProgramOriginalMockProvider")
pub fn client_program_original_mock_provider(
  original : @model.ModelMockInstallation,
) -> Result[@model.ModelProvider, @model.ModelMockInstallationIssue] {
  @model.original_model_mock_provider(original)
}

///|
#export_name("clientProgramAdmitOriginalMockProvider")
pub fn client_program_admit_original_mock_provider(
  original : @model.ModelMockInstallation,
  execution : @check_environment.ModelExecutionContract,
  dependencies : @check_environment.SingleAttemptModelDependencies,
) -> Result[@model.AdmittedModelProvider, @model.ModelProviderAdmissionIssue] {
  @model.admit_original_model_mock_provider(original, execution, dependencies)
}

///|
#export_name("clientProgramRetireOriginalMock")
pub fn client_program_retire_original_mock(
  original : @model.ModelMockInstallation,
) -> Result[Bool, @model.ModelMockInstallationIssue] {
  @model.retire_original_model_mock(original)
}

///|
#export_name("clientProgramRetireMockProfile")
pub fn client_program_retire_mock_profile(
  original : @check_environment.ModelMockProfile,
) -> Bool {
  @check_environment.retire_model_mock_profile(original)
}

///|
#export_name("clientProgramReadOriginalMockModelDependencies")
pub fn client_program_read_original_mock_model_dependencies(
  original : @model.ModelMockInstallation,
  execution : @check_environment.ModelExecutionContract,
  prompt : String?,
  retry : String?,
  backoff : String?,
) -> Result[
  @check_environment.SingleAttemptModelDependencies,
  @check_environment.ModelDependencyIssue,
] {
  @model.read_original_model_mock_dependencies(
    original,
    execution,
    prompt.map(value => @utf8.encode(value)),
    retry.map(value => @utf8.encode(value)),
    backoff.map(value => @utf8.encode(value)),
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10000, },
    1000000,
  )
}
