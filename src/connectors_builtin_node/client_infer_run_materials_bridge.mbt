///|
/// Private binding to the existing saved Run codec. These values do not claim
/// physical input custody, current authority, funding or permission to send.
pub(all) enum ClientInferRunMaterialsBridgeIssue {
  Manifests(@publication_host.ClientCompilationManifestIssue)
  Materials(@publication_host.ClientTaskRunMaterialsIssue)
  Recovery(@client_local_host.ClientRequestModelRecoveryMaterialsIssue)
}

///|
#export_name("clientProgramIssueInferRunMaterials")
pub fn client_program_issue_infer_run_materials(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  environment : @program_check.CheckEnvironment,
  parameters : String?,
) -> Result[String, @publication_host.ClientTaskRunMaterialsIssue] {
  @publication_host.issue_prepared_client_infer_run_materials(
    compiled,
    definition,
    environment,
    parameters,
    client_effect_original_limits(),
  )
}

///|
#export_name("clientProgramAdmitInferRunMaterials")
pub fn client_program_admit_infer_run_materials(
  wire : String,
  expected_run_cid : String,
  text_time : Bool,
  veca : Bool,
  rela : Bool,
  sga : Bool,
  tea : Bool,
  calendar : Bool,
  text_rank : Bool,
) -> Result[
  @publication_host.ClientTaskRunMaterials,
  ClientInferRunMaterialsBridgeIssue,
] {
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @publication_host.admit_client_infer_run_materials(
    wire,
    expected_run_cid,
    { text_time, veca, },
    { rela, sga, tea, calendar, text_rank, },
    manifests,
    client_effect_original_limits(),
  ).map_err(issue => Materials(issue))
}

///|
/// Installed cold restoration uses its SAME physical Request reservation.
/// Both returned members are originals from that one funded material Read.
#export_name("clientProgramAdmitRequestInferRunMaterials")
pub fn client_program_admit_request_infer_run_materials(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  wire : String,
  text_time : Bool,
  veca : Bool,
  rela : Bool,
  sga : Bool,
  tea : Bool,
  calendar : Bool,
  text_rank : Bool,
) -> Result[
  (
    @publication_host.ClientTaskRunMaterials,
    @publication_host.ClientAuthoringContextPreparation,
  ),
  ClientInferRunMaterialsBridgeIssue,
] {
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Err(issue) => return Err(Manifests(issue))
    Ok(value) => value
  }
  @client_local_host.admit_request_model_recovery_materials(
    parent,
    input,
    request,
    definition,
    wire,
    { text_time, veca, },
    { rela, sga, tea, calendar, text_rank, },
    manifests,
    client_effect_original_limits(),
  ).map_err(issue => Recovery(issue))
}

///|
#export_name("clientProgramInferRunMaterialsCompiled")
pub fn client_program_infer_run_materials_compiled(
  materials : @publication_host.ClientTaskRunMaterials,
) -> Result[
  @publication_host.ClientCompiledRun,
  @publication_host.ClientCompiledRunIssue,
] {
  @publication_host.client_task_run_materials_compiled_original(materials)
}

///|
#export_name("clientProgramInferRunMaterialsPrepared")
pub fn client_program_infer_run_materials_prepared(
  materials : @publication_host.ClientTaskRunMaterials,
) -> @publication_host.PreparedClientProgram {
  materials.prepared
}

///|
#export_name("clientProgramInferRunMaterialsDefinition")
pub fn client_program_infer_run_materials_definition(
  materials : @publication_host.ClientTaskRunMaterials,
) -> @publication.PublicationContract {
  materials.run_definition
}

///|
#export_name("clientProgramInferRunMaterialsGraph")
pub fn client_program_infer_run_materials_graph(
  materials : @publication_host.ClientTaskRunMaterials,
) -> @publication_host.ClientInferPlanGraph? {
  let graphs = @publication_host.client_task_compilation_infers(
    materials.compilation,
  )
  if graphs.length() == 1 {
    graphs.get(0)
  } else {
    None
  }
}

///|
/// Project only the graph/execution retained by this same compiled owner.
/// A physically different preparation, even with equal bytes, cannot use it.
#export_name("clientProgramCompiledInferOriginal")
pub fn client_program_compiled_infer_original(
  compiled : @publication_host.ClientCompiledRun,
  prepared : @publication_host.PreparedClientProgram,
) -> (
  @publication_host.ClientInferPlanGraph,
  @check_environment.ModelExecutionContract,
)? {
  guard @publication_host.client_compiled_run_matches(compiled, prepared) else {
    return None
  }
  let graphs = @publication_host.client_compiled_run_infers(compiled)
  guard graphs.length() == 1 && graphs.get(0) is Some(graph) else {
    return None
  }
  Some(
    (graph, @publication_host.client_infer_plan_graph_execution_contract(graph)),
  )
}

///|
/// Read the complete DATA inventory retained by this admitted materials owner.
/// Copy the outer array; component originals stay owned by its compilation.
#export_name("clientProgramInferRunMaterialsGraphs")
pub fn client_program_infer_run_materials_graphs(
  materials : @publication_host.ClientTaskRunMaterials,
) -> Array[@publication_host.ClientInferPlanGraph] {
  @publication_host.client_task_compilation_infers(materials.compilation).copy()
}

///|
#export_name("clientProgramCompiledInferOriginals")
pub fn client_program_compiled_infer_originals(
  compiled : @publication_host.ClientCompiledRun,
  prepared : @publication_host.PreparedClientProgram,
) -> Array[
  (
    @publication_host.ClientInferPlanGraph,
    @check_environment.ModelExecutionContract,
  ),
]? {
  guard @publication_host.client_compiled_run_matches(compiled, prepared) else {
    return None
  }
  let graphs = @publication_host.client_compiled_run_infers(compiled)
  if graphs.is_empty() {
    return None
  }
  Some(
    graphs.map(graph => {
      (
        graph,
        @publication_host.client_infer_plan_graph_execution_contract(graph),
      )
    }),
  )
}

///|
/// Normal installed capture must enter the same Request's funded constructor.
/// The old standalone codec remains a separate explicit component route.
#export_name("clientProgramIssueRequestInferRunMaterials")
pub fn client_program_issue_request_infer_run_materials(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[String, @client_local_host.ClientRequestProgramPlanIssue] {
  @client_local_host.issue_request_model_run_materials(
    parent, input, compiled, definition,
  )
}
