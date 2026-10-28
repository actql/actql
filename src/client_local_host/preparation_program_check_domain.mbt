///|
priv enum ProgramCheckPreparationPhase {
  BindingInitial
  BindingQuoted
  CheckPrepared
  PreludePrepared
  CatalogInspected
  RegistryPrepared
  RegistryRetained
  ContentsInspected
  ContentsPrepared
  ContentsRetained
  ReferencesInspected
  ReferencesPrepared
  ReferencesRetained
  PoliciesInspected
  PoliciesPrepared
  PoliciesRetained
  ValuesObservationFunded
  ValuesInspected
  ValuesPrepared
  ValuesRetained
  ViewsObservationFunded
  ViewsInspected
  ViewsPrepared
  ViewsRetained
  CarriersObservationFunded
  CarriersInspected
  CarriersMetadataRetained
  CarriersPrepared
  CarriersRetained
  RequestsObservationFunded
  RequestsInspected
  RequestsMetadataRetained
  RequestsPrepared
  RequestsRetained
  SourceRegistrationQuoted
  SourceRegistrationPrepared
  SourceRegistrationRetained
  SourceCollectionObservationFunded
  SourceCollectionInspected
  SourceCollectionMetadataRetained
  SourceCollectionPrepared
  SourceCollectionRetained
  SourceCollectionFailed
  SourceResolutionInitial
  SourceResolutionObservationFunded
  SourceResolutionInspected
  SourceResolutionMetadataRetained
  SourceResolutionPrepared
  SourceResolutionRetained
  SourceResolutionFailed
  SourcePipelineInitial
  SourcePipelineQuoted
  SourcePipelinePrepared
  SourcePipelineRetained
  SourcePipelineFailed
  SourceLocalEntryPrepared
  SourceLocalEntryRetained
  SourceLocalEntryFailed
  SourceLocalIndexInitial
  SourceLocalIndexObservationFunded
  SourceLocalIndexInspected
  SourceLocalIndexMetadataRetained
  SourceLocalIndexPrepared
  SourceLocalIndexRetained
  SourceLocalIndexFailed
  SourceLocalGroupsInitial
  SourceLocalGroupsQuoted
  SourceLocalGroupsPrepared
  SourceLocalGroupsRetained
  SourceLocalGroupsFailed
  SourceLocalSnapshotInitial
  SourceLocalSnapshotObservationFunded
  SourceLocalSnapshotInspected
  SourceLocalSnapshotMetadataRetained
  SourceLocalSnapshotReferenceInitial
  SourceLocalSnapshotReferenceObservationFunded
  SourceLocalSnapshotReferenceInspected
  SourceLocalSnapshotReferenceRetained
  SourceLocalSnapshotBatchInitial
  SourceLocalSnapshotBatchQuoted
  SourceLocalSnapshotBatchInspected
  SourceLocalSnapshotBatchRetained
  SourceLocalSnapshotBatchPrepared
  SourceLocalSnapshotBatchFailed
  SourceLocalSnapshotBatchComplete
  SourceLocalTailInitial
  SourceLocalTailQuoted
  SourceLocalTailInspected
  SourceLocalTailRetained
  SourceLocalTailPrepared
  SourceLocalTailFailed
  SourceLocalTailComplete
  SourceContextInputInitial
  SourceContextInputInspected
  SourceContextInputRetained
  SourceContextInputPrepared
  SourceContextInputComplete
  SourceContextInputFailed
  SourceTopologyEntryInitial
  SourceTopologyEntryPrepared
  SourceTopologyEntryComplete
  SourceTopologyEntryFailed
  SourceTopologyBodyInspectionInitial
  SourceTopologyBodyQuoted
  SourceTopologyBodyReturned
  SourceTopologyBodyRetained
  SourceTopologyBodyFailed
  Transferred
  Failed
  Retired
} derive(Eq)

///|
priv struct ProgramCheckArguments {
  program : @syntax.Program
  environment : @checked.CheckEnvironment
  supplied : @decode.Cursor?
  evidence : Array[@context.StageCapacityInput]
  limits : @checked.CheckLimits
  source_catalog : @checked.PreparedSourceCatalog?
  source_preparation : @stages.Source?
}

///|
/// Later constructor DATA on the existing original capacity. Source/index/Program
/// backing and the caller's immutable input association remain outside this
/// record; its own packet neither creates nor closes a Resource owner.
struct ClientProgramCheckPreparation[I, P] {
  capacity : @resources.PreparationCapacity[I, P]
  mut input : I?
  mut arguments : ProgramCheckArguments?
  mut check_input : @checked.ParsedCheckInput?
  mut check_prelude : @checked.ParsedCheckPrelude?
  mut catalog_input : @checked.ParsedCatalogInput?
  mut check_registry : @checked.ParsedCheckRegistry?
  mut contents_input : @checked.ParsedContentsInput?
  mut references_input : @checked.ParsedReferencesInput?
  mut policies_input : @checked.ParsedPoliciesInput?
  mut values_input : @checked.ParsedValuesInput?
  mut views_input : @checked.ParsedViewsInput?
  mut carriers_input : @checked.ParsedCarriersInput?
  mut requests_input : @checked.ParsedRequestsInput?
  mut registration_source : @stages.Source?
  mut source_registration : @checked.ParsedSourceRegistration?
  mut source_body_quote : (Int64, Int64)?
  mut carriers_quote : (Int64, Int64)?
  mut requests_quote : (Int64, Int64)?
  mut requests_body_quote : (Int64, Int64)?
  mut environment_scratch : Int64?
  mut binding_inventory : @shape.CollectionConstructionInventory?
  mut binding_quote : (Int64, Int64)?
  mut work : @resources.PreparationPhaseWork64?
  mut topology_work : @resources.PreparationPhaseWorkContinuation64?
  // Last original read Usage observation, never another work allowance.
  mut topology_observed_work : Int64
  mut topology_quoted_phase : @stage_results.LocalProgramReadPhase
  mut topology_quoted_stage : Int
  base_retained : Int64
  base_execution : Int64
  mut busy : Bool
  mut phase : ProgramCheckPreparationPhase
}

///|
pub suberror ClientProgramCheckPreparationIssue {
  Capacity(@resources.PreparationCapacityIssue)
  Check(@checked.LocalConstructionFailure)
  Catalog(@checked.ParsedCatalogPreparationIssue)
  SourceRegistration(@checked.ParsedSourceRegistrationIssue)
  TopologyEntry(@context.SourceViewContextIssue)
  Prelude(@checked.ParsedCheckPreludeIssue)
  Work(@resources.PreparationWorkIssue)
  ChangedInputs
  WrongPhase
  Overflow
}

///|
/// The outside caller already backs the original Program/Source, arguments,
/// debit/current/resize entrance. Add this later domain's installed packet once
/// before constructing its controls. The Source-only JSON packet is unchanged.
pub fn[I, P] begin_program_check_preparation(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  program : @syntax.Program,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : @checked.CheckLimits,
  source_catalog? : @checked.PreparedSourceCatalog? = None,
  source_preparation? : @stages.Source? = None,
) -> Result[
  ClientProgramCheckPreparation[I, P],
  ClientProgramCheckPreparationIssue,
] {
  let (base_retained, base_execution) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(
      base_retained, program_check_initial_control_bytes, 1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      base_execution, program_check_initial_control_bytes, 1L,
    )
    is Some(e) else {
    return Err(Overflow)
  }
  match @resources.reserve_working_preparation_phase(capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  Ok({
    capacity,
    input: Some(input),
    arguments: Some({
      program,
      environment,
      supplied,
      evidence,
      limits,
      source_catalog,
      source_preparation,
    }),
    check_input: None,
    check_prelude: None,
    catalog_input: None,
    check_registry: None,
    contents_input: None,
    references_input: None,
    policies_input: None,
    values_input: None,
    views_input: None,
    carriers_input: None,
    requests_input: None,
    registration_source: None,
    source_registration: None,
    source_body_quote: None,
    carriers_quote: None,
    requests_quote: None,
    requests_body_quote: None,
    environment_scratch: None,
    binding_inventory: None,
    binding_quote: None,
    work: None,
    topology_work: None,
    topology_observed_work: 0L,
    topology_quoted_phase: @stage_results.LocalInputs,
    topology_quoted_stage: 0,
    base_retained,
    base_execution,
    busy: false,
    phase: BindingInitial,
  })
}

///|
fn[I, P] current_program_check_preparation(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  guard owner.input is Some(input) else { return Err(WrongPhase) }
  match
    @resources.check_working_preparation_capacity_current(owner.capacity, input) {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => Ok(())
  }
}

///|
fn[I, P] transfer_program_check_input(
  owner : ClientProgramCheckPreparation[I, P],
) -> Unit {
  owner.arguments = None
  owner.check_input = None
  owner.check_prelude = None
  owner.catalog_input = None
  owner.check_registry = None
  owner.contents_input = None
  owner.references_input = None
  owner.policies_input = None
  owner.values_input = None
  owner.views_input = None
  owner.carriers_input = None
  owner.requests_input = None
  owner.registration_source = None
  owner.source_registration = None
  owner.source_body_quote = None
  owner.carriers_quote = None
  owner.requests_quote = None
  owner.requests_body_quote = None
  owner.binding_inventory = None
  owner.binding_quote = None
  owner.environment_scratch = None
  owner.topology_work = None
  owner.topology_observed_work = 0L
  owner.topology_quoted_phase = @stage_results.LocalInputs
  owner.topology_quoted_stage = 0
  owner.input = None
  owner.phase = Transferred
}

///|
/// Only this controller's returned synchronous references. A failed constructor
/// may retain its closed reader state; finishing any original work receipt
/// preserves spent work. No backing/parent/physical ACK is issued.
pub fn[I, P] clear_program_check_preparation(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.busy {
    return Err(WrongPhase)
  }
  if owner.work is Some(work) {
    match @resources.finish_preparation_phase_work64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => owner.work = None
    }
  }
  if owner.topology_work is Some(work) {
    match @resources.finish_preparation_phase_work_continuation64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => owner.topology_work = None
    }
  }
  // The alias-drop helper marks Transferred for its actual take callers.
  // Clearing must preserve only a real handoff that preceded this helper.
  let transferred = owner.phase == Transferred
  if !transferred && owner.source_registration is Some(original) {
    @checked.clear_parsed_source_registration(original)
  }
  transfer_program_check_input(owner)
  if !transferred {
    owner.phase = Retired
  }
  Ok(())
}
