///|
/// Use the existing family capacity selection on the same source-free Run.
/// No captured Source, Model provider, or synthetic zero-capacity carrier is
/// introduced; physical child ownership remains with the installed Host.
#export_name("clientProgramOpenSourceFreeFamilyEffectHost")
pub fn client_program_open_source_free_family_effect_host(
  prepared : @publication_host.PreparedClientEffectRun,
  registry : String,
  values : String,
  fragment : String?,
  ordered : String?,
  providers : Array[@local.ManagedProvider],
) -> ClientLocalEffectHost? {
  open_client_source_free_family_effect_host(
    prepared,
    registry,
    values,
    fragment,
    ordered,
    providers,
    None,
  )
}

///|
#export_name("clientProgramOpenSourceFreeFamilyEffectHostAtQueryTime")
pub fn client_program_open_source_free_family_effect_host_at_query_time(
  prepared : @publication_host.PreparedClientEffectRun,
  original : @publication_host.ClientQueryTimePreparation,
  request : @publication_host.ClientRequestIdentity,
  registry : String,
  values : String,
  fragment : String?,
  ordered : String?,
  providers : Array[@local.ManagedProvider],
) -> ClientLocalEffectHost? {
  open_client_source_free_family_effect_host(
    prepared,
    registry,
    values,
    fragment,
    ordered,
    providers,
    Some((original, request)),
  )
}

///|
fn open_client_source_free_family_effect_host(
  prepared : @publication_host.PreparedClientEffectRun,
  registry : String,
  values : String,
  fragment : String?,
  ordered : String?,
  providers : Array[@local.ManagedProvider],
  query_time : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )?,
) -> ClientLocalEffectHost? {
  if providers.is_empty() || providers.length() > 32 {
    return None
  }
  let computation = @publication_host.prepared_client_effect_run_computation(
    prepared,
  )
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(computation),
  )
  if @strategy.graph_captured_prefix(graph) != 0 {
    return None
  }
  let (execution, measurement) = client_program_local_execution_limits()
  guard @client_local_host.client_effect_family_ledger_limits(
      computation, registry, values, fragment, ordered, execution, measurement, providers,
    )
    is Some(limits) else {
    return None
  }
  open_client_local_effect_host(
    prepared,
    None,
    registry,
    values,
    1L,
    0L,
    0L,
    0L,
    fragment_body=fragment,
    ordered_body=ordered,
    component_providers=providers,
    source_free_limits=Some(limits),
    query_time~,
  )
}

///|
/// Trusted installed ports adapt the existing bounded Content child. Program
/// data cannot supply a provider, issuer, workspace or physical cleanup fact.
#export_name("clientProgramContentStepWorkspace")
pub fn client_program_content_step_workspace(
  generation_bytes : Int,
  generation_nodes : Int,
  generation_depth : Int,
  generation_frames : Int,
  identity_slots : Int,
  reference_bytes : Int,
  reference_nodes : Int,
  reference_depth : Int,
  contract_bytes : Int,
  contract_nodes : Int,
  contract_depth : Int,
  export_limits : @publication_host.PublicationOutputExportLimits,
) -> @client_local_host.ClientSerializationWorkspaceLimits? {
  let workspace : @client_local_host.ClientSerializationWorkspaceLimits = {
    generation_bytes,
    generation_nodes,
    generation_depth,
    generation_frames,
    identity_slots,
    reference_bytes,
    reference_nodes,
    reference_depth,
    contract_bytes,
    contract_nodes,
    contract_depth,
    export_limits,
  }
  if @client_local_host.client_serialization_workspace_capacity(workspace)
    is Some(_) {
    Some(workspace)
  } else {
    None
  }
}

///|
#export_name("clientProgramEffectContentLocalProvider")
pub fn client_program_effect_content_local_provider(
  prepared : @publication_host.PreparedClientEffectComputation,
  task : Int,
  step : Int,
  registry : String,
  values : String,
  fragment : String?,
  ordered : String?,
  workspace : @client_local_host.ClientSerializationWorkspaceLimits,
  cancel : () -> Bool,
  stopped : () -> Bool,
  cleanup : () -> Bool,
  retain : (@client_local_host.ClientLocalContentStep) -> Bool,
  recovery : @client_local_host.ClientRetainedContentOutput?,
) -> @local.ManagedProvider? {
  let (execution, measurement) = client_program_local_execution_limits()
  @client_local_host.client_effect_content_local_provider(
    prepared,
    task,
    step,
    registry,
    values,
    fragment,
    ordered,
    execution,
    measurement,
    workspace,
    { cancel, stopped, cleanup: () => Ok(cleanup()), },
    retain,
    recovery~,
  )
}

///|
#export_name("clientProgramPrepareRetainedContentOutput")
pub fn client_program_prepare_retained_content_output(
  generation : @publication_host.ClientSerializationGeneration,
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  store : String,
  binding : String,
  descriptor : String,
  rows : Array[String],
  available : () -> Bool,
) -> Result[
  @client_local_host.ClientRetainedContentOutput,
  @client_local_host.ClientInferRetainedInputIssue,
] {
  @client_local_host.prepare_client_retained_content_output(
    generation, run, definition, store, binding, descriptor, rows, available,
  )
}

///|
#export_name("clientProgramEffectContentLedgerLimits")
pub fn client_program_effect_content_ledger_limits(
  prepared : @publication_host.PreparedClientEffectComputation,
  registry : String,
  values : String,
  fragment : String?,
  ordered : String?,
  provider : @local.ManagedProvider,
) -> @resources.LedgerLimits? {
  let (execution, measurement) = client_program_local_execution_limits()
  @client_local_host.client_effect_family_ledger_limits(
    prepared,
    registry,
    values,
    fragment,
    ordered,
    execution,
    measurement,
    [provider],
  )
}

///|
#export_name("clientProgramPrepareContentEffectCaptureLedger")
pub fn client_program_prepare_content_effect_capture_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  capacity : @client_local_host.ClientInstalledCaptureCapacity,
  transport_bytes : Int64,
  transport_execution_bytes : Int64,
  registry : String,
  values : String,
  fragment : String?,
  ordered : String?,
  provider : @local.ManagedProvider,
) -> @resources.Ledger? {
  let (execution, measurement) = client_program_local_execution_limits()
  @client_local_host.prepare_client_effect_family_capture_ledger(
    prepared,
    capacity,
    transport_bytes,
    transport_execution_bytes,
    registry,
    values,
    fragment,
    ordered,
    execution,
    measurement,
    [provider],
  )
}

///|
/// All checked families participate in the same original acquisition ledger.
/// This does not open a family or dispatch a physical operation.
#export_name("clientProgramPrepareFamilyEffectCaptureLedger")
pub fn client_program_prepare_family_effect_capture_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  capacity : @client_local_host.ClientInstalledCaptureCapacity,
  transport_bytes : Int64,
  transport_execution_bytes : Int64,
  registry : String,
  values : String,
  fragment : String?,
  ordered : String?,
  providers : Array[@local.ManagedProvider],
) -> @resources.Ledger? {
  let (execution, measurement) = client_program_local_execution_limits()
  @client_local_host.prepare_client_effect_family_capture_ledger(
    prepared, capacity, transport_bytes, transport_execution_bytes, registry, values,
    fragment, ordered, execution, measurement, providers,
  )
}

///|
#export_name("clientProgramContentStepPendingPiece")
pub fn client_program_content_step_pending_piece(
  active : @client_local_host.ClientLocalContentStep,
) -> (Int, String)? {
  @client_local_host.client_local_content_pending_piece(active)
}

///|
#export_name("clientProgramContentStepAcknowledgePiece")
pub fn client_program_content_step_acknowledge_piece(
  active : @client_local_host.ClientLocalContentStep,
  revision : Int,
) -> Bool {
  @client_local_host.acknowledge_client_local_content_piece(active, revision)
}

///|
#export_name("clientProgramContentStepGenerationInput")
pub fn client_program_content_step_generation_input(
  active : @client_local_host.ClientLocalContentStep,
) -> (
  @publication_host.ClientSerializationInput,
  @execution.CompletedRelationExportReceipt,
  @publication.ContentByteEncoder,
)? {
  @client_local_host.client_local_content_generation_input(active)
}

///|
#export_name("clientProgramContentStepByteCompletion")
pub fn client_program_content_step_byte_completion(
  active : @client_local_host.ClientLocalContentStep,
) -> @publication.ContentByteCompletion? {
  @client_local_host.client_local_content_byte_completion(active)
}

///|
#export_name("clientProgramContentStepGeneration")
pub fn client_program_content_step_generation(
  active : @client_local_host.ClientLocalContentStep,
) -> @publication_host.ClientSerializationGeneration? {
  @client_local_host.client_local_content_step_generation(active)
}

///|
#export_name("clientProgramExportContentGenerationOutput")
pub fn client_program_export_content_generation_output(
  generation : @publication_host.ClientSerializationGeneration,
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  store_cid : String,
) -> Result[
  (String, String, Array[String]),
  @client_local_host.ClientInferRetainedInputIssue,
] {
  match
    @client_local_host.export_client_content_generation_output(
      generation, run, definition, store_cid,
    ) {
    Ok(value) =>
      Ok(
        (
          @client_local_host.client_infer_retained_input_export_binding(value),
          @client_local_host.client_infer_retained_input_export_descriptor(
            value,
          ),
          @client_local_host.client_infer_retained_input_export_rows(value),
        ),
      )
    Err(issue) => Err(issue)
  }
}

///|
#export_name("clientProgramCompleteContentStep")
pub fn client_program_complete_content_step(
  active : @client_local_host.ClientLocalContentStep,
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  evidence : @publication_host.ClientSerializationInputEvidence,
  candidate : @publication.GeneratedContentReference,
  content : @admitted.CheckedValue,
  available : () -> Bool,
  max_nodes : Int,
  max_text_bytes : Int,
  max_depth : Int,
  max_work : Int,
  max_name_bytes : Int,
) -> Result[
  @publication_host.ClientSerializationGeneration,
  @publication_host.ClientSerializationGenerationIssue,
] {
  @client_local_host.complete_client_local_content_step(
    active,
    run,
    definition,
    evidence,
    candidate,
    content,
    available,
    { max_nodes, max_text_bytes, max_depth, max_work, },
    max_name_bytes,
  )
}

///|
#export_name("clientProgramAdmitEffectSerializationCapturedInput")
pub fn client_program_admit_effect_serialization_captured_input(
  run : @publication_host.ClientCompiledRun,
  owner : @publication_host.PreparedClientEffectComputation,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  logical : @publication.RunEvidenceValue,
  source_wire : String,
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
) -> Result[
  @publication_host.ClientSerializationCapturedInput,
  @publication.RunEvidenceValueIssue,
] {
  let evidence = match
    @publication.admit_run_evidence_value(
      "source_evidence", source_wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @publication_host.admit_client_effect_serialization_captured_input(
    run, owner, source, identity, requirement, logical, evidence, authority_scope_cid,
    started_at, completed_at,
  )
}
