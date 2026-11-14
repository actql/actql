///|
priv enum ClientRequestPreparationPhase {
  Open
  ResultRead
  Selecting
  QuerySyntaxQuoted
  QuerySyntaxParsed
  QuerySyntaxFailed
  QueryLoweringQuoted
  QueryLowered
  QueryLoweringFailed
  ProgramJson
  ProgramJsonFailed
  ProgramCheck
  ProgramCheckFailed
  ProgramCompiled
  EffectCompiled
  EffectPlanQuoted
  EffectPlanReserved
  EffectModelScopeQuoted
  EffectBodyReady
  EffectBodyFailed
  EffectCaptureRecovery
  ModelRecovery
  ProgramPlanQuoted
  ProgramPlanReserved
  ModelPlanReserved
  ModelScopeQuoted
  ContentPlanReserved
  ProgramBodyReady
  ProgramBodyFailed
  Selected
  Retiring
  Closed
} derive(Eq)

///|
// Replace the former four-field Model input tuple in its existing resident
// slot. Both selected compiler inputs have the same four original fields;
// no additional parent, phase, retained controller or parameter cache exists.
priv enum ClientRequestDomainCompilationInputs {
  // Read-only recovery retains the existing journal-selected originals. It
  // never continues into a compiler, Source/Model/Effect Plan or send owner.
  RequestEffectCaptureRecovery(
    @publication_host.ClientRequestIdentity,
    @publication.PublicationContract
  )
  // A saved Model continuation keeps its Journal-selected pair while the
  // existing Request reservation funds reconstruction. It cannot compile a
  // new Program, admit another Run or replace the saved physical call scope.
  RequestModelRecovery(
    @publication_host.ClientRequestIdentity,
    @publication.PublicationContract
  )
  RequestModelCompilation(
    @publication_host.ClientCompilationManifests,
    @publication_host.ClientPureCompilationLimits,
    ClientInstalledSequenceContracts,
    @publication_host.ClientInferPlanGraph
  )
  // The original component is already backed before the caller can compile
  // it. Reuse this same four-reference slot, then transfer it to that compiler.
  // Same resident four-reference slot while the backed Graph constructor
  // retains its original mappings/lowering through a failed issuer/current.
  // The SAME resident compiler-input slot may retain the full ordered
  // original graph vector. Its actual Array constructor is backed before
  // allocation; no second compiler/parent or ownership cache is introduced.
  RequestModelsCompilation(
    @publication_host.ClientCompilationManifests,
    @publication_host.ClientPureCompilationLimits,
    ClientInstalledSequenceContracts,
    Array[@publication_host.ClientInferPlanGraph]
  )
  RequestModelGraphs(
    @publication_host.ClientCompilationManifests,
    @publication_host.ClientPureCompilationLimits,
    ClientInstalledSequenceContracts,
    Array[@publication_host.ClientInferPlanGraph]
  )
  RequestModelGraphConstruction(
    @publication_host.ClientCompilationManifests,
    @publication_host.ClientPureCompilationLimits,
    ClientInstalledSequenceContracts,
    @publication_host.ClientInferGraphConstruction
  )
  RequestModelGraph(
    @publication_host.ClientCompilationManifests,
    @publication_host.ClientPureCompilationLimits,
    ClientInstalledSequenceContracts,
    @publication_host.ClientInferPlanGraph
  )
  RequestSerializationGraph(
    @publication_host.ClientCompilationManifests,
    @publication_host.ClientPureCompilationLimits,
    ClientInstalledSequenceContracts,
    @publication_host.ClientSerializationPlanGraph
  )
  RequestSerializationCompilation(
    @publication_host.ClientCompilationManifests,
    @publication_host.ClientPureCompilationLimits,
    ClientInstalledSequenceContracts,
    @publication_host.ClientSerializationPlanGraph
  )
  RequestKeyedSerializationCompilation(
    @publication_host.ClientCompilationManifests,
    @publication_host.ClientPureCompilationLimits,
    ClientInstalledManagedKeyedPreparation,
    @publication_host.ClientSerializationPlanGraph
  )
}

///|
/// Request bootstrap on the original Node preparation child, before an output
/// body type is selected. Unit is never completed or interpreted as a body.
/// This record owns no second Ledger, byte allowance, parser or serializer.
struct ClientRequestPreparation[I] {
  initial : ClientPreparationInitial[I]
  mut _observed_query_parse_calls : Int64
  mut _observed_query_lower_calls : Int64
  mut _observed_semantic_check_calls : Int64
  mut _observed_program_compile_calls : Int64
  ledger : @resources.Ledger
  capacity : @resources.PreparationCapacity[I, Unit]
  mut input : I?
  mut snapshot_base : (Int64, Int64)?
  mut result_read : ClientRequestResultReadBudget?
  mut result_read_metadata : ClientRequestResultMetadataBudget?
  mut snapshot_units : Int64
  mut snapshot_values : Int64
  snapshot_key_units : Ref[Int]
  mut submitted_intent : @publication_host.ClientSubmittedIntent?
  mut source_input : ClientRequestSourceInput?
  mut intent_base : (Int64, Int64)?
  mut intent_source_quote : (Int64, Int64)?
  mut native_intake_base : (Int64, Int64)?
  mut native_intake_wire_bytes : Int
  mut intent_attempted : Bool
  mut intent_peak_live : Bool
  mut intent_work : @resources.PreparationPhaseWork64?
  mut _observed_intent_work : Int64
  mut query_syntax : ClientRequestQuerySyntax?
  // The same generic domain holder owns its source/index/Program aliases.
  // Unit remains uncompleted until the actual output-type continuation.
  mut program_json : ClientProgramJsonPreparation[I, Unit]?
  mut native_parameters : @decode.Cursor?
  mut native_parameters_ready : Bool
  mut native_query_declarations : (@decode.Cursor, @parameters.Declarations)?
  mut held_program : @syntax.Program?
  mut parameter_source : @stages.Source?
  mut program_check : ClientProgramCheckPreparation[I, Unit]?
  mut computation_limits : @publication_host.ClientProgramPreparationLimits?
  // SAME reservation continued to its actual final body type; no second owner.
  mut program_capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ]?
  mut compiled_program : @publication_host.PreparedClientProgram?
  mut effect_capacity : @resources.PreparationCapacity[
    I,
    ClientInstalledEffectManagedPlan,
  ]?
  mut compiled_effect : @publication_host.PreparedClientEffectComputation?
  mut effect_plan : ClientInstalledEffectManagedPlan?
  mut program_data : @checked.ParsedCheckDataEstimate?
  mut program_plan_quote : (Int64, Int64)?
  mut program_measurement_quote : (Int64, Int64)?
  // Sequential Graph, Model Scope and Content constructors reuse this prepaid
  // absolute-target slot across a declined grow. Their completed originals
  // coexist in the distinct existing domain/body slots below.
  mut program_domain_quote : (Int64, Int64)?
  mut program_artifact_geometry : @publication_host.ClientPureCompilationConstruction?
  mut program_artifact_quote : (Int64, Int64, Int64)?
  mut program_invocation_quote : (Int64, Int64)?
  mut program_artifact_work : @resources.PreparationPhaseWork64?
  mut program_artifact_work_charged : Bool
  mut program_artifact_work_spent : Int64
  program_artifact_plan_encoding_nodes : Ref[Int64]
  mut program_artifact_work_issue : @resources.PreparationWorkIssue?
  mut program_artifact_inputs : (
    @publication_host.ClientCompilationManifests,
    @publication_host.ClientPureCompilationLimits,
    ClientInstalledSequenceContracts,
    Bool,
    (@execution.ExecutionCapacity) -> Array[@local.ManagedProvider],
  )?
  mut program_domain_compilation_inputs : ClientRequestDomainCompilationInputs?
  // One existing resident output slot for either ordinary or Model emission.
  // Its original sum is moved to the selected Plan, never a parallel cache.
  mut program_compilation : @publication_host.ClientRunCompilation?
  mut program_source_free_max_work : Int?
  mut program_source_free : ClientInstalledManagedSourceFreePreparation?
  mut program_captured : ClientInstalledManagedCapturePlan?
  mut program_model_direct : @publication_host.ClientDirectAcquisitionOccurrences?
  mut program_model : ClientInstalledManagedModelPlan?
  mut program_content : ClientInstalledContentPreparation
  mut program_content_request : @publication_host.ClientRequestIdentity?
  mut program_body_attempted : Bool
  mut phase : ClientRequestPreparationPhase
}

///|
let request_preparation_borrow_limit : Int = 6

///|
// Fixed Resource-owned census layout, priced by the existing common tariff.
// This is retained installed DATA, not another per-Request owner or budget.
let request_preparation_inventory_slots : (Int64, Int64, Int64) = @resources.preparation_inventory_initial_control_slots(
  request_preparation_borrow_limit, 0, 0,
).unwrap()

///|
pub(all) enum ClientRequestPreparationIssue {
  ForeignOriginal
  WrongPhase
  Policy
  Initial(@resources.ImportedChildLedgerIssue)
  Capacity(@resources.PreparationCapacityIssue)
  SnapshotCapacityExceeded(
    @resources.PreparationCapacityIssue,
    ClientPreparationCapacityRefusal
  )
  ProgramJson(ClientProgramJsonPreparationIssue)
  ProgramCheck(ClientProgramCheckPreparationIssue)
  Parameters(@local_preparation.LocalProgramInputIssue)
  Intent(@publication_host.ClientSubmittedIntentIssue)
  SourceInput(ClientRequestSourceInputIssue)
  Work(@resources.PreparationWorkIssue)
  ParameterDeclarations(@parameters.Issue)
  ParameterSource(@stages.Issue)
} derive(Debug)

///|
// Preserve the original typed suberror for this caller's existing Debug sum.
// Error's native representation retains the actual constructor/cause.
pub impl Debug for ClientProgramCheckPreparationIssue with fn to_repr(self) {
  let original : Error = self
  Repr(original)
}

///|
// One conservative fixed Host/Request control envelope, expressed through the
// existing common representation tariff. Preserve the original 10,368-byte
// envelope plus one Source-context reference slot and two growth-fence words.
// Default Request input selection adds its four nested immutable limit records
// and Result wrapper (5H/7R/10W) before the native Source constructor grow:
// Cache one extra scalar word for that same artifact quote's retired scratch,
// so a declined grow reuses the original split without interpreting it again:
// One observed-input ParseLimits record/Some (2H/1R/3W) also precedes its
// constructor grow. Its original key-extent observation Ref/Some and field
// (2H/2R/1W) share this fixed control group:10,736 bytes plus4,096 installed.
// The Native retained-wire parser keeps one absolute quote tuple/Some and
// its Request field (2H/2R/2W); declined growth never adds that demand twice.
// Native wire intake retains one same-parent baseline tuple/Some and its
// monotone byte observation (2H/2R/3W) before any payload constructor.
// This is intentionally independent of JS closure, carrier and array spelling.
// Input/AST/wire/row/operation storage, selected domain construction and live
// child overlap remain separately charged before their actual constructors.
// The fixed envelope is immutable DATA, not a reservation, phase or RSS bound.
// Four scalar observations (4W) remain on this SAME Request through its typed
// continuation. No new observer record, parent backreference or callback exists.
// Explicit source-free work selection retains one Some/header, its scalar and
// two references on the SAME Request (1H/2R/1W), including failed construction.
// Default Query's observed Stage selection retains four immutable records:
// Program limits (3R/4W), Check limits (2R), Compile limits (6R/1W), and
// structure limits (9W). Their 4H/11R/14W coexist with the original selection
// before checking. Shared nested profiles and original Option payloads are
// borrowed unchanged; no Stage-sized array or policy-sized storage is added.
let request_preparation_fixed_control_envelope : @execution.PreparationRepresentationUnits = {
  record_headers: 238L,
  reference_slots: 429L,
  scalar_words: 496L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
/// Fixed supplier precondition before JS per-request controls exist. This is
/// only a control quote under the original Local policy, not a body budget.
pub fn client_request_preparation_control_capacity(
  policy : ClientLocalResourcePolicy,
) -> (Int64, Int64)? {
  guard client_local_preparation_initial_limits(policy) is Some(limits) &&
    @execution.preparation_representation_cost(
      request_preparation_fixed_control_envelope,
    )
    is Some(original) &&
    @execution.checked_preparation_add_product(original, 4096L, 1L)
    is Some(retained) else {
    return None
  }
  // One trusted private control group: invocation sizing/Option/lean view, or
  // the exclusive read-only capture-recovery quote/reader controls, or the
  // pre-compiler Content Graph measurement/selection call frame. This is
  // installed coarse control overhead, not variable wire/body admission.
  // Native's completed typed body handoff uses one header/reference/tag
  // (1H/1R/1W = 32 bytes) in this same group after its resize has returned;
  // it retains the original borrow and introduces no second capacity.
  // The same group covers later Run growth entry. Its original owner fences
  // recursion before payload construction, so only one refused nested entry
  // overlaps. The fixed carriers are backed NOW, not by a later resize.
  // Optional Native scalar diagnostics retain only bounded before/after tuples
  // and the SAME light parent, plus parser/lowerer Ref/Some call observations
  // (together under 512 bytes), within this fixed 4096 group.
  // The exclusive ResultRead phase retains its bounded budget/control tuple
  // in this same group; variable frames/rows/output reserve separately.
  let growth = @resources.preparation_inventory_growth_entry_construction()
  guard @execution.preparation_representation_cost({
      record_headers: growth.record_headers,
      reference_slots: growth.reference_slots,
      scalar_words: growth.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(entry) &&
    entry <= 4096L else {
    return None
  }
  if retained > limits.retained_bytes {
    return None
  }
  Some((retained, 0L))
}

///|
pub fn[I] begin_request_preparation(
  initial : @resources.NodePreparationAdmission[I],
  input : I,
  policy : ClientLocalResourcePolicy,
) -> Result[ClientRequestPreparation[I], ClientRequestPreparationIssue] {
  begin_request_preparation_original(NodeRequestInitial(initial), input, policy)
}

///|
fn[I] begin_request_preparation_original(
  initial : ClientPreparationInitial[I],
  input : I,
  policy : ClientLocalResourcePolicy,
) -> Result[ClientRequestPreparation[I], ClientRequestPreparationIssue] {
  guard client_local_preparation_initial_limits(policy) is Some(expected) &&
    client_request_preparation_control_capacity(policy)
    is Some((retained, execution)) else {
    return Err(Policy)
  }
  match preparation_initial_input(initial, input) {
    Err(issue) => return Err(Initial(issue))
    Ok(_) => ()
  }
  let ledger = match preparation_initial_start(initial, input) {
    Err(issue) => return Err(Initial(issue))
    Ok(value) => value
  }
  let available = @resources.ledger_limits(ledger)
  let fits = match initial {
    // Keep the original nominal supplier and non-byte controls. Byte ceilings
    // are not constructor demand: the actual fixed quote below, then every
    // phase/grow, must fit this SAME initial Ledger even below the default.
    NodeRequestInitial(_) =>
      installed_effect_limits_fit(
        { ..expected, retained_bytes: 0L, execution_bytes: 0L, },
        available,
      )
    // This nominal scoped child supplies actual backing, not the policy's
    // unused maxima. Keep its original grant within that policy ceiling;
    // every fixed/variable constructor still reserves its full actual quote.
    BackedRequestInitial(_) => installed_effect_limits_fit(available, expected)
  }
  if !fits {
    return Err(Policy)
  }
  let capacity : @resources.PreparationCapacity[I, Unit] = match
    @resources.reserve_preparation_capacity_inventory(
      ledger,
      input,
      retained,
      execution,
      max_borrowers=request_preparation_borrow_limit,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  // The manager stores this original before any shape-specific constructor.
  Ok({
    initial,
    _observed_query_parse_calls: 0L,
    _observed_query_lower_calls: 0L,
    _observed_semantic_check_calls: 0L,
    _observed_program_compile_calls: 0L,
    ledger,
    capacity,
    input: Some(input),
    snapshot_base: None,
    result_read: None,
    result_read_metadata: None,
    snapshot_units: 0L,
    snapshot_values: 0L,
    snapshot_key_units: Ref(-1),
    submitted_intent: None,
    source_input: None,
    intent_base: None,
    intent_source_quote: None,
    native_intake_base: None,
    native_intake_wire_bytes: 0,
    intent_attempted: false,
    intent_peak_live: false,
    intent_work: None,
    _observed_intent_work: 0L,
    query_syntax: None,
    program_json: None,
    native_parameters: None,
    native_parameters_ready: false,
    native_query_declarations: None,
    held_program: None,
    parameter_source: None,
    program_check: None,
    computation_limits: None,
    program_capacity: None,
    compiled_program: None,
    effect_capacity: None,
    compiled_effect: None,
    effect_plan: None,
    program_data: None,
    program_plan_quote: None,
    program_measurement_quote: None,
    program_domain_quote: None,
    program_artifact_geometry: None,
    program_artifact_quote: None,
    program_invocation_quote: None,
    program_artifact_work: None,
    program_artifact_work_charged: false,
    program_artifact_work_spent: 0L,
    program_artifact_plan_encoding_nodes: Ref(0L),
    program_artifact_work_issue: None,
    program_artifact_inputs: None,
    program_domain_compilation_inputs: None,
    program_compilation: None,
    program_source_free_max_work: None,
    program_source_free: None,
    program_captured: None,
    program_model_direct: None,
    program_model: None,
    program_content: NoContent,
    program_content_request: None,
    program_body_attempted: false,
    phase: Open,
  })
}

///|
/// Caller connection to the existing generic domain driver. The SAME original
/// working capacity/input enter B's constructor; Unit is never completed or
/// converted into a prepared Program or Effect. The constructor itself adds
/// its initial domain inventory once, before creating its Source cursor.
///
/// This caller declares only its own resident link and return carriers above.
/// The backend's real first-prelude/input/outer backing is a separate required
/// precondition. The same already selected immutable syntax limits are DATA,
/// not another resource allowance or a new public request option. No standard
/// default is substituted here. Normal SDK snapshot admission is not enabled.
pub fn[I] prepare_request_program_json_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  document : String,
  limits : @syntax.Limits,
) -> Result[
  ClientProgramJsonPreparation[I, Unit],
  ClientRequestPreparationIssue,
] {
  if owner.phase != Open ||
    !request_intent_input_ready(owner) ||
    owner.program_json is Some(_) {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  // Retain the exact parent before B's original current/reservation boundary.
  // No second current call, copied byte quota or pre-reservation is inserted.
  owner.phase = Selecting
  match
    begin_program_json_preparation(owner.capacity, input, document, limits) {
    Err(issue) => {
      owner.phase = ProgramJsonFailed
      Err(ProgramJson(issue))
    }
    Ok(child) => {
      owner.program_json = Some(child)
      owner.phase = ProgramJson
      Ok(child)
    }
  }
}

///|
/// Continue only this parent's original Source Program into the later domain.
/// Keep the exact Program before its grow callback; the original Source packet
/// remains charged, and the later constructor adds its own packet once. These
/// borrowed environment/evidence/limits and callback frames require their real
/// caller backing. No output body, raw capacity or cleanup authority is issued.
pub fn[I] prepare_request_program_check_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : @checked.CheckLimits,
  source_catalog? : @checked.PreparedSourceCatalog? = None,
  source_preparation? : @stages.Source? = None,
) -> Result[
  ClientProgramCheckPreparation[I, Unit],
  ClientRequestPreparationIssue,
] {
  prepare_request_check_preparation_owned(
    owner,
    input,
    environment,
    supplied,
    evidence,
    limits,
    source_catalog~,
    source_preparation~,
  )
}

///|
pub fn[I] prepare_request_effect_check_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : @publication_host.ClientEffectComputationLimits,
  source_catalog? : @checked.PreparedSourceCatalog? = None,
  source_preparation? : @stages.Source? = None,
) -> Result[
  ClientProgramCheckPreparation[I, Unit],
  ClientRequestPreparationIssue,
] {
  prepare_request_check_preparation_owned(
    owner,
    input,
    environment,
    supplied,
    evidence,
    limits.program.checking,
    source_catalog~,
    source_preparation~,
    effect_limits=Some(limits),
  )
}

///|
fn[I] prepare_request_check_preparation_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : @checked.CheckLimits,
  source_catalog? : @checked.PreparedSourceCatalog? = None,
  source_preparation? : @stages.Source? = None,
  effect_limits? : @publication_host.ClientEffectComputationLimits? = None,
  computation_limits? : (
    @publication_host.ClientProgramPreparationLimits,
    @publication_host.ClientEffectComputationLimits,
  )? = None,
) -> Result[
  ClientProgramCheckPreparation[I, Unit],
  ClientRequestPreparationIssue,
] {
  guard owner.program_check is None &&
    (owner.phase == ProgramJson || owner.phase == QueryLowered) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  let supplied = if owner.native_parameters_ready {
    match (owner.native_parameters, supplied) {
      (Some(original), Some(selected)) if !physical_equal(original, selected) =>
        return Err(ForeignOriginal)
      (None, Some(_)) => return Err(ForeignOriginal)
      (original, _) => original
    }
  } else {
    supplied
  }
  let (program, source_catalog) = if owner.phase == QueryLowered {
    guard owner.held_program is Some(program) &&
      owner.query_syntax is Some(query) &&
      query.lowering is Some(lowering) &&
      physical_equal(lowering.environment, environment) &&
      lowering.output is Some(Ok((_, catalog, _))) else {
      return Err(ForeignOriginal)
    }
    let catalog = match source_catalog {
      Some(selected) => {
        // Required-reuse wrappers retain the SAME interpreted Catalog owners.
        // Keep the selected wrapper, including its no-fallback requirement;
        // equal CIDs or a separately admitted Catalog cannot replace it.
        if !@checked.source_catalog_same_original(selected, catalog) {
          return Err(ForeignOriginal)
        }
        selected
      }
      None => catalog
    }
    // The lowerer already retained this exact Program and Catalog. Taking
    // immutable DATA cannot reenter current or construct a replacement tree.
    (program, Some(catalog))
  } else {
    guard owner.held_program is None && owner.program_json is Some(source) else {
      return Err(WrongPhase)
    }
    owner.phase = Selecting
    let program = match take_program_json_preparation_program(source) {
      Err(issue) => {
        owner.phase = ProgramJson
        return Err(ProgramJson(issue))
      }
      Ok(value) => value
    }
    owner.held_program = Some(program)
    (program, source_catalog)
  }
  // This is the original Program's retained parser inventory, not another
  // operation-name scan, check, resource quote or caller classification.
  let effect_limits = match computation_limits {
    None => effect_limits
    Some((program_limits, effect_limits)) =>
      if @syntax.program_preparation_data(program).effect_members == 0 {
        owner.computation_limits = Some(program_limits)
        None
      } else {
        owner.computation_limits = Some(effect_limits.program)
        Some(effect_limits)
      }
  }
  owner.phase = Selecting
  let outcome = prepare_request_parameter_check_owned(
    owner, input, program, environment, supplied, evidence, limits, source_catalog,
    source_preparation, effect_limits,
  )
  match outcome {
    Err(issue) => {
      owner.phase = ProgramCheckFailed
      Err(issue)
    }
    Ok(child) => {
      owner.program_check = Some(child)
      owner.phase = ProgramCheck
      Ok(child)
    }
  }
}

///|
/// Actual observed work on this SAME Request, including attempted work that
/// returned a parser/checker/compiler failure. Foreign input, pre-work refusal
/// and cached projections cannot increment it. DATA only, never permission or
/// currentness. Scalar history survives payload retirement without retaining
/// the input/body. The caller funds this bounded tuple before projection.
pub fn[I] request_preparation_work_calls(
  owner : ClientRequestPreparation[I],
) -> (Int64, Int64, Int64, Int64) {
  let (checked, compiled) = match owner.program_check {
    Some(child) =>
      (
        child._observed_semantic_check_calls,
        child._observed_program_compile_calls,
      )
    None =>
      (
        owner._observed_semantic_check_calls,
        owner._observed_program_compile_calls,
      )
  }
  (
    owner._observed_query_parse_calls,
    owner._observed_query_lower_calls,
    checked,
    compiled,
  )
}

///|
/// Only after this fixed callback's construction/snapshot aliases unwound.
/// Pending original report/stop remains on this same admission; a later callback
/// cannot replace its original unknown outcome with an acknowledgement.
/// A selected stale bootstrap cannot settle its successor's shared token.
pub fn[I] abort_request_preparation_after_cleanup(
  owner : ClientRequestPreparation[I],
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.phase == Selected || owner.phase == Selecting {
    return Err(WrongPhase)
  }
  if owner.phase == Closed {
    return Ok(())
  }
  // A Check output transferred outside this registered chain still belongs
  // to its next consumer, even if the Check controller's DATA was cleared.
  if owner.program_check is Some(child) && child.phase == Transferred {
    return Err(WrongPhase)
  }
  if owner.program_json is Some(child) && child.phase == Transferred {
    // Only our own retained Program/later-controller transition can clear the
    // Source transfer. Direct index/Program take has no such registered link.
    guard owner.held_program is Some(_) &&
      (
        owner.phase == ProgramCheck ||
        owner.phase == ProgramCheckFailed ||
        owner.program_capacity is Some(_) ||
        owner.effect_capacity is Some(_)
      ) else {
      return Err(WrongPhase)
    }
  }
  if owner.program_check is Some(child) {
    let previous = owner.phase
    owner.phase = Selecting
    match clear_program_check_preparation(child) {
      Err(issue) => {
        owner.phase = previous
        return Err(ProgramCheck(issue))
      }
      Ok(_) => {
        owner._observed_semantic_check_calls = child._observed_semantic_check_calls
        owner._observed_program_compile_calls = child._observed_program_compile_calls
        owner.program_check = None
      }
    }
    owner.phase = previous
  }
  if owner.program_json is Some(child) {
    let previous = owner.phase
    owner.phase = Selecting
    match clear_program_json_preparation(child) {
      Err(issue) => {
        owner.phase = previous
        return Err(ProgramJson(issue))
      }
      Ok(_) => owner.program_json = None
    }
    owner.phase = previous
  }
  clear_request_parameter_source(owner)
  match finish_request_query_refusal_binding_work(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Registered controllers have relinquished only their own aliases.
  // This caller is explicitly after its borrowed arguments/returned frames.
  if owner.intent_work is Some(work) {
    match @resources.finish_preparation_phase_work64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(spent) => {
        owner._observed_intent_work = spent
        owner.intent_work = None
      }
    }
  }
  match finish_request_program_artifact_work(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  clear_request_source_input(owner)
  owner.submitted_intent = None
  owner.snapshot_base = None
  owner.result_read = None
  owner.result_read_metadata = None
  owner.snapshot_key_units.val = -1
  owner.intent_base = None
  owner.intent_source_quote = None
  owner.native_intake_base = None
  owner.native_intake_wire_bytes = 0
  owner.intent_peak_live = false
  owner.held_program = None
  owner.native_parameters = None
  owner.native_query_declarations = None
  owner.native_parameters_ready = false
  owner.query_syntax = None
  owner.compiled_program = None
  owner.computation_limits = None
  // Keep the original Effect until its last constructor borrower returns.
  // Its cached normalization custody is severed only after logical retirement.
  owner.effect_plan = None
  owner.program_data = None
  owner.program_plan_quote = None
  owner.program_measurement_quote = None
  owner.program_domain_quote = None
  owner.program_artifact_geometry = None
  owner.program_artifact_quote = None
  owner.program_invocation_quote = None
  owner.program_artifact_work_issue = None
  owner.program_artifact_inputs = None
  owner.program_compilation = None
  owner.program_domain_compilation_inputs = None
  owner.program_source_free_max_work = None
  owner.program_source_free = None
  owner.program_captured = None
  owner.program_model_direct = None
  owner.program_model = None
  owner.program_content = NoContent
  owner.program_content_request = None

  let retiring = owner.phase == Retiring
  owner.phase = Retiring
  // input=None is recorded only after the selected capacity has actually
  // retired. A later retry belongs solely to the SAME physical initial owner;
  // the old Unit handle may already be Continued and cannot settle it again.
  if !(retiring && owner.input is None) {
    let stopped = if owner.effect_capacity is Some(capacity) {
      if retiring || owner.program_body_attempted {
        @resources.retire_preparation_capacity(capacity)
      } else {
        guard owner.input is Some(input) else { return Err(ForeignOriginal) }
        @resources.abort_preparation_capacity_after_cleanup(capacity, input)
      }
    } else {
      match owner.program_capacity {
        Some(capacity) =>
          if retiring || owner.program_body_attempted {
            @resources.retire_preparation_capacity(capacity)
          } else {
            guard owner.input is Some(input) else {
              return Err(ForeignOriginal)
            }
            @resources.abort_preparation_capacity_after_cleanup(capacity, input)
          }
        None =>
          if retiring {
            @resources.retire_preparation_capacity(owner.capacity)
          } else {
            guard owner.input is Some(input) else {
              return Err(ForeignOriginal)
            }
            @resources.abort_preparation_capacity_after_cleanup(
              owner.capacity,
              input,
            )
          }
      }
    }
    match stopped {
      Err(issue) => return Err(Capacity(issue))
      Ok(false) => return Err(WrongPhase)
      Ok(true) => owner.input = None
    }
    // These continued controls were allocated in the payload Read. Keeping
    // a logically closed record until that Read's ACK would pin its own last
    // alias forever. Failed settlement/live borrowers retain the originals.
    if owner.compiled_effect is Some(prepared) {
      @publication_host.clear_prepared_client_effect_custody_after_cleanup(
        prepared,
      )
    }
    owner.compiled_effect = None
    owner.program_capacity = None
    owner.effect_capacity = None
  }
  match preparation_initial_cleanup(owner.initial) {
    Err(issue) => Err(Initial(issue))
    Ok(_) => {
      owner.program_capacity = None
      owner.effect_capacity = None
      owner.phase = Closed
      Ok(())
    }
  }
}

///|
/// Read-only scalar diagnostics of this Request's SAME Ledger and reservation.
/// The typed body continuation shares that reservation; observing it neither
/// checks currentness nor grants, resizes, settles or restores any resource.
pub fn[I] request_preparation_accounting(
  owner : ClientRequestPreparation[I],
) -> (Int64, Int64, Int64, Int64, Int64, Int64) {
  @resources.preparation_capacity_accounting(owner.capacity)
}

///|
/// The same Request owner on a fresh legitimately backed child of the actual
/// installed parent. Fixed VM capacities and the enclosing Host stay owned by
/// that parent; Node's pristine-child/census law is unchanged.
pub fn[I] begin_backed_request_preparation(
  initial : @resources.BackedPreparationAdmission[I],
  input : I,
  policy : ClientLocalResourcePolicy,
) -> Result[ClientRequestPreparation[I], ClientRequestPreparationIssue] {
  begin_request_preparation_original(
    BackedRequestInitial(initial),
    input,
    policy,
  )
}
