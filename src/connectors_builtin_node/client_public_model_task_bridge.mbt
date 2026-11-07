///|
#export_name("clientProgramPublicModelTaskName")
pub fn client_program_public_model_task_name(
  task : @check_environment.PublicModelTaskDeclaration,
) -> String {
  @check_environment.public_model_task_declaration_identity(task).0
}

///|
/// Private actual-runtime projection. Parsing, defaults, original correspondence
/// and canonical Task material stay with Common; no Host DATA builds a handle.
#export_name("clientProgramReadPublicModelTask")
pub fn client_program_read_public_model_task(
  wire : String,
  format : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  contract_nodes : Int,
  contract_depth : Int,
  contract_text_bytes : Int,
  max_work : Int,
) -> Result[
  @check_environment.PublicModelTaskDeclaration,
  @check_environment.ModelTaskIssue,
] {
  @check_environment.read_public_model_task_document(wire, format, {
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
#export_name("clientProgramSelectProjectModelTask")
pub fn client_program_select_project_model_task(
  registry : @publication_host.ClientProjectModelRegistry,
  task : @check_environment.PublicModelTaskDeclaration,
  max_work : Int,
) -> Result[
  @publication_host.ClientProjectModelTaskSelection,
  @publication_host.ClientProjectModelTaskSelectionIssue,
] {
  @publication_host.select_client_project_model_task(registry, task, max_work)
}

///|
#export_name("clientProgramProjectModelTaskSelectionFor")
pub fn client_program_project_model_task_selection_for(
  selection : @publication_host.ClientProjectModelTaskSelection,
  registry : @publication_host.ClientProjectModelRegistry,
  task : @check_environment.PublicModelTaskDeclaration,
) -> (String, String?, String)? {
  @publication_host.client_project_model_task_selection_for(
    selection, registry, task,
  )
}

///|
#export_name("clientProgramNormalizeProjectModelTask")
pub fn client_program_normalize_project_model_task(
  selection : @publication_host.ClientProjectModelTaskSelection,
  registry : @publication_host.ClientProjectModelRegistry,
  task : @check_environment.PublicModelTaskDeclaration,
  defaults : @publication_host.ClientModelProviderDefaults,
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
  @publication_host.normalize_client_project_model_task(
    selection,
    registry,
    task,
    defaults,
    {
      bodies: { max_bytes, max_nodes, max_depth, max_members, },
      contracts: {
        max_nodes: contract_nodes,
        max_depth: contract_depth,
        max_text_bytes: contract_text_bytes,
      },
      max_work,
    },
  )
}

///|
#export_name("clientProgramNormalizedPublicModelTaskMaterials")
pub fn client_program_normalized_public_model_task_materials(
  value : @check_environment.NormalizedPublicModelTask,
) -> (String, String, String, String) {
  @check_environment.normalized_public_model_task_materials(value)
}

///|
/// Canonical outer-Environment DATA only. The installed Host retains every
/// normalized Task original and uses its ordinary full checker afterward.
#export_name("clientProgramProjectPublicModelTaskEnvironment")
pub fn client_program_project_public_model_task_environment(
  wire : String,
  evidence_cid : String,
  tasks : Array[@check_environment.NormalizedPublicModelTask],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  contract_nodes : Int,
  contract_depth : Int,
  contract_text_bytes : Int,
  max_work : Int,
) -> Result[(String, String, Int), @check_environment.ModelTaskIssue] {
  @check_environment.read_project_public_model_task_environment(
    wire,
    evidence_cid,
    tasks,
    {
      bodies: { max_bytes, max_nodes, max_depth, max_members, },
      contracts: {
        max_nodes: contract_nodes,
        max_depth: contract_depth,
        max_text_bytes: contract_text_bytes,
      },
      max_work,
    },
  )
}

///|
/// DATA correspondence only: the same admitted complete Source closure may
/// describe a checked downstream Model. It supplies no Local input or grant.
#export_name("clientProgramComposedInferSourcesMatch")
pub fn client_program_composed_infer_sources_match(
  sources : @publication_host.ClientInferComposedSources,
  occurrence : @publication_host.ClientInferOccurrence,
) -> Bool {
  @publication_host.client_infer_composed_sources_matches(sources, occurrence)
}
