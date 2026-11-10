///|
/// Installed execution bounds. Run, model dependency and egress admission
/// precede this physical operation; these limits cannot grant model access.
pub(all) struct Limits {
  input : @relation.SequenceExecutionLimits
  measurement : @relation.FixedInputGuardMeasureLimits
  mapping : @relation.InferPreparationLimits
  model : @model.ModelExecutionLimits
  output_rows : Int
  output_values : @relation.ValueLimits
  output_work : Int
  output_workspace : Int
  identity : IdentityLimits
}

///|
/// Input identity is a separate bounded conversion before model dispatch.
pub(all) struct IdentityLimits {
  rows : Int
  wire : @relation.RowWireLimits
  logical_wire : @relation.RowWireLimits
  schema : @relation.RelationSchemaIdentityLimits
  work : Int
  workspace : Int
}

///|
pub(all) enum Issue {
  InvalidAdvance
  Input(@input.ClientInferInputIssue)
  Model(@model.ModelExecutionIssue)
  Capacity(@publication_host.ClientInferHostCapacityIssue)
  IdentityExport(@relation.CompletedExportIssue)
  CallScope(@publication_host.ClientInferCallScopeIssue)
  OriginalCapacity(@publication_host.ClientModelInputCapacityIssue)
}

///|
enum Phase {
  Input
  Identity
  Model
  Output
  Compute
  Handoff
  Terminal
}

///|
enum Source {
  Physical(@model.ModelProvider)
  Replay(@model.VerifiedModelCapture)
  Restored(@publication.ModelCaptureBundleRead)
  RestoredSlots(@model.ModelSlotReplayRead)
}

///|
pub enum Poll {
  Continue(work~ : Int64)
  AwaitIo(work~ : Int64)
  Waiting(work~ : Int64)
  Settling(Int, work~ : Int64)
  Complete(@relation.CompletedOutput, work~ : Int64)
  Failed(Issue, work~ : Int64)
  Stopped(work~ : Int64)
}

///|
/// One physical owner composes existing bounded children. It is neither a
/// Run state machine nor a retry engine. The installing Host supplies an
/// admitted fixed request identity, provider and envelope before dispatch.
pub struct Execution {
  prepared : @publication_host.PreparedClientProgram?
  occurrence : @publication_host.ClientInferOccurrence
  input : @input.ClientInferInputExecution
  source : Source
  fixed_request_cid : String
  step : Int
  plan : @publication_host.ClientInferPlanGraph?
  limits : Limits
  mut rows : @relation.PreparedInferRows?
  mut identity : @relation.CompletedRelationIdentityScan?
  mut identity_body : OriginalInferIdentityBody?
  mut call_scope : @publication_host.ClientInferCallScope?
  mut saved_call_scope : @publication_host.ClientInferSavedCallScope?
  mut model : @model.ModelExecution?
  mut capture : @model.ModelCaptureBundle?
  mut output : @model.ModelOutputPreparation?
  mut suffix_sequence : @relation.GeneratedSequence?
  mut suffix : @local.ManagedProviderExecution?
  mut completed : @relation.CompletedOutput?
  mut phase : Phase
  mut cancelled : Bool
  mut advancing : Bool
  mut reclaimed : Bool
  mut local_component_bound : Bool
  priv entry_work : Int64
  mut work : Int64
  mut child_work : Int64
  mut output_uses : Int
  mut run_binding : ExecutionRunBinding?
  mut original_preparation : OriginalModelPreparation?
  mut dispatch_admission : @publication_host.ClientInferDispatchAdmission?
  mut durable_calls : Bool
  mut model_send_mask : Array[Bool]?
  mut quantity_capacity : @model.ModelQuantityCapacity?
  mut physical_preflight : @model.ModelPhysicalPreflight?
  mut egress_admission : @publication_host.ClientInferEgressAdmission?
  mut final_quantity_usage : @resources.QuantityUsage?
  mut acquired_input : @publication_host.ClientInferCapturedInput?
  composed_sources : @publication_host.ClientInferComposedSources?
  mut serialized_output : @relation.CompletedOutput?
  mut serialized_generation : @publication_host.ClientSerializationGeneration?
}

///|
pub struct OutputUse {
  owner : Execution
  output : @relation.CompletedOutput
  mut released : Bool
}

///|
/// The original Program must prepare and execute its own input prefix. No
/// caller can substitute finished rows or a separately assembled completion.
pub fn start(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  sequence_contracts : @input.ClientInstalledSequenceContracts,
  values : String,
  provider : @model.ModelProvider,
  fixed_request_cid : String,
  limits : Limits,
  plan? : @publication_host.ClientInferPlanGraph? = None,
  acquired_input? : @publication_host.ClientInferCapturedInput? = None,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[Execution, Issue] {
  start_owned(
    prepared,
    step,
    sequence_contracts,
    values,
    Physical(provider),
    fixed_request_cid,
    limits,
    plan,
    acquired_input~,
    fragment_body~,
    ordered_body~,
  )
}

///|
/// Consume the authentic checked Content producer once. Its Store lifetime
/// remains with the caller; this owner retains only the existing bounded
/// input mapping/suffix and still requires ordinary Run/dispatch admission.
pub fn start_serialized(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  plan : @publication_host.ClientInferPlanGraph,
  output : @relation.CompletedOutput,
  provider : @model.ModelProvider,
  limits : Limits,
) -> Result[Execution, Issue] {
  guard @publication_host.prepared_client_infer_execution_occurrence(
      prepared, step,
    )
    is Some(occurrence) &&
    @publication_host.client_infer_occurrence_matches_plan(occurrence, plan) &&
    @publication_host.client_infer_plan_graph_serialization(plan) is Some(_) else {
    return Err(Input(@input.UnsupportedProgram))
  }
  if @publication_host.client_infer_occurrence_has_captured_sources(occurrence) {
    return Err(CallScope(ForeignInput))
  }
  start_serialized_occurrence(
    prepared, occurrence, plan, output, provider, limits,
  )
}

///|
/// A sourced Content input requires the original generation closure, not just
/// its completed row. Retain it with this same input/Model owner until cleanup.
pub fn start_generated(
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  generation : @publication_host.ClientSerializationGeneration,
  plan : @publication_host.ClientInferPlanGraph,
  provider : @model.ModelProvider,
  limits : Limits,
) -> Result[Execution, Issue] {
  guard @publication_host.client_serialization_generation_infer_occurrence(
      generation, compiled, plan,
    )
    is Some(occurrence) &&
    @publication_host.client_infer_occurrence_matches(occurrence, prepared) &&
    @publication_host.client_serialization_generation_output_for(
      generation, compiled,
    )
    is Some(output) else {
    return Err(CallScope(ForeignInput))
  }
  start_serialized_occurrence(
    prepared, occurrence, plan, output, provider, limits,
  ).map(active => {
    active.serialized_generation = Some(generation)
    active
  })
}

///|
/// Start only the Model boundary after the Local chain has completed the
/// original post-generation prefix. Retain its authentic generation closure
/// for call-scope evidence; do not execute that prefix a second time.
pub fn start_generated_inputs(
  compiled : @publication_host.ClientCompiledRun,
  generation : @publication_host.ClientSerializationGeneration,
  plan : @publication_host.ClientInferPlanGraph,
  inputs : Array[@local.ManagedProviderInput],
  provider : @model.ModelProvider,
  limits : Limits,
) -> Result[Execution, Issue] {
  guard @publication_host.client_serialization_generation_infer_occurrence(
      generation, compiled, plan,
    )
    is Some(occurrence) &&
    @publication_host.client_serialization_generation_output_for(
      generation, compiled,
    )
    is Some(_) &&
    inputs.length() == 1 &&
    inputs[0] is @local.RelationInput(read) else {
    return Err(CallScope(ForeignInput))
  }
  let owner = @publication_host.client_infer_occurrence_preparation(occurrence)
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  guard @relation.infer_completed_producer_input(owner, step, read)
    is Some(output) else {
    return Err(CallScope(ForeignInput))
  }
  start_occurrence(
    occurrence,
    None,
    Physical(provider),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    Some(plan),
    limits => {
      @input.start_client_completed_infer_input(
        occurrence,
        output,
        limits.mapping,
      )
    },
  ).map(active => {
    active.serialized_generation = Some(generation)
    active
  })
}

///|
// Enter the original one-shot consumer before the existing generated input
// constructor. No fallible post-start bind or independent root reserve exists.
pub fn start_original_generated(
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  generation : @publication_host.ClientSerializationGeneration,
  plan : @publication_host.ClientInferPlanGraph,
  provider : @model.ModelProvider,
  limits : Limits,
  definition : @publication.PublicationContract,
  consumer : @publication_host.ClientModelReadConsumer,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
) -> Result[Execution, Issue] {
  guard @publication_host.client_serialization_generation_infer_occurrence(
      generation, compiled, plan,
    )
    is Some(occurrence) &&
    @publication_host.client_infer_occurrence_matches(occurrence, prepared) &&
    @publication_host.client_serialization_generation_output_for(
      generation, compiled,
    )
    is Some(_) else {
    return Err(CallScope(ForeignInput))
  }
  match
    enter_original_model_preparation(
      occurrence, compiled, definition, plan, consumer, read_retained_bytes, read_execution_bytes,
      model_retained_bytes, model_execution_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The checked original producer/port and bounded serialization segment
  // still belong to start_generated; do not duplicate their input execution.
  start_generated(prepared, compiled, generation, plan, provider, limits).map(active => {
    retain_original_model_preparation(
      active,
      compiled,
      definition,
      consumer,
      model_retained_bytes,
      model_execution_bytes,
      shared_mock=true,
    )
    active
  })
}

///|
// The Local producer has already completed this exact checked edge. Model
// input allocation still requires its own original consumer entry first.
pub fn start_original_generated_inputs(
  compiled : @publication_host.ClientCompiledRun,
  generation : @publication_host.ClientSerializationGeneration,
  plan : @publication_host.ClientInferPlanGraph,
  inputs : Array[@local.ManagedProviderInput],
  provider : @model.ModelProvider,
  limits : Limits,
  definition : @publication.PublicationContract,
  consumer : @publication_host.ClientModelReadConsumer,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
) -> Result[Execution, Issue] {
  guard @publication_host.client_serialization_generation_infer_occurrence(
      generation, compiled, plan,
    )
    is Some(occurrence) &&
    @publication_host.client_serialization_generation_output_for(
      generation, compiled,
    )
    is Some(_) &&
    inputs.length() == 1 &&
    inputs[0] is @local.RelationInput(read) else {
    return Err(CallScope(ForeignInput))
  }
  let owner = @publication_host.client_infer_occurrence_preparation(occurrence)
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  guard @relation.infer_completed_producer_input(owner, step, read) is Some(_) else {
    return Err(CallScope(ForeignInput))
  }
  match
    enter_original_model_preparation(
      occurrence, compiled, definition, plan, consumer, read_retained_bytes, read_execution_bytes,
      model_retained_bytes, model_execution_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  start_generated_inputs(compiled, generation, plan, inputs, provider, limits).map(active => {
      retain_original_model_preparation(
        active,
        compiled,
        definition,
        consumer,
        model_retained_bytes,
        model_execution_bytes,
        shared_mock=true,
      )
      active
    },
  )
}

///|
fn start_serialized_occurrence(
  prepared : @publication_host.PreparedClientProgram,
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
  output : @relation.CompletedOutput,
  provider : @model.ModelProvider,
  limits : Limits,
) -> Result[Execution, Issue] {
  guard @publication_host.client_infer_plan_graph_serialization(plan)
    is Some(component) else {
    return Err(Input(@input.UnsupportedProgram))
  }
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  let (task, producer) = @publication_host.client_serialization_plan_graph_coordinates(
    component,
  )
  let owner = @publication_host.client_infer_occurrence_preparation(occurrence)
  if task != @publication_host.client_infer_occurrence_coordinates(occurrence).0 ||
    producer >= step ||
    !@relation.completed_output_matches_port(
      output,
      owner,
      @pipeline.Step(producer),
    ) {
    return Err(CallScope(ForeignInput))
  }
  start_occurrence(
    occurrence,
    Some(prepared),
    Physical(provider),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    Some(plan),
    limits => {
      if producer + 1 == step {
        @input.start_client_completed_infer_input(
          occurrence,
          output,
          limits.mapping,
        )
      } else {
        guard @relation.prepare_serialization_infer_input_segment(
            output,
            step,
            @publication_host.prepared_client_values_sequence_limits(prepared),
            limits.input.max_work,
            limits.input.rows.metadata_entries,
          )
          is Some(segment) else {
          return Err(@input.UnsupportedProgram)
        }
        @input.start_client_serialized_infer_input(
          occurrence,
          segment,
          producer,
          output,
          limits.input,
          limits.measurement,
          limits.mapping,
        )
      }
    },
  ).map(active => {
    active.serialized_output = Some(output)
    active
  })
}

///|
/// Reconstruction follows the ordinary bounded prefix and identity scan.
/// It cannot redispatch: the only model source is an existing checked capture.
pub fn start_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  sequence_contracts : @input.ClientInstalledSequenceContracts,
  values : String,
  capture : @model.VerifiedModelCapture,
  limits : Limits,
  plan : @publication_host.ClientInferPlanGraph,
  acquired_input? : @publication_host.ClientInferCapturedInput? = None,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[Execution, Issue] {
  guard @model.retain_verified_model_capture(capture) is Some(retained) else {
    return Err(Model(@model.OutputIdentity))
  }
  let started = start_owned(
    prepared,
    step,
    sequence_contracts,
    values,
    Replay(retained),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    Some(plan),
    acquired_input~,
    fragment_body~,
    ordered_body~,
  )
  if started is Err(_) {
    @model.release_verified_model_capture(retained) |> ignore
  }
  started
}

///|
/// A fresh normal Program executes its prefix before verifying saved capture
/// records. No provider is installed in this operation or used as a fallback.
pub fn start_restored_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  sequence_contracts : @input.ClientInstalledSequenceContracts,
  values : String,
  capture : @publication.ModelCaptureBundleRead,
  limits : Limits,
  plan : @publication_host.ClientInferPlanGraph,
  acquired_input? : @publication_host.ClientInferCapturedInput? = None,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[Execution, Issue] {
  guard @publication.retain_model_capture_bundle_read(capture) is Some(retained) else {
    return Err(Model(@model.OutputIdentity))
  }
  let started = start_owned(
    prepared,
    step,
    sequence_contracts,
    values,
    Restored(retained),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    Some(plan),
    acquired_input~,
    fragment_body~,
    ordered_body~,
  )
  if started is Err(_) {
    @publication.release_model_capture_bundle_read(retained) |> ignore
  }
  started
}

///|
/// Complete saved slot inventory and the separate successful-response bundle
/// follow the same normal Program input path. This cannot dispatch a model.
pub fn start_restored_slot_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  sequence_contracts : @input.ClientInstalledSequenceContracts,
  values : String,
  read : @model.ModelSlotReplayRead,
  limits : Limits,
  plan : @publication_host.ClientInferPlanGraph,
  acquired_input? : @publication_host.ClientInferCapturedInput? = None,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[Execution, Issue] {
  guard @model.retain_model_slot_replay(read) is Some(retained) else {
    return Err(Model(@model.OutputIdentity))
  }
  let started = start_owned(
    prepared,
    step,
    sequence_contracts,
    values,
    RestoredSlots(retained),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    Some(plan),
    acquired_input~,
    fragment_body~,
    ordered_body~,
  )
  if started is Err(_) {
    @model.release_model_slot_replay(retained) |> ignore
  }
  started
}

///|
/// A synchronization point for physical progress, not evidence authority.
pub fn restoring(active : Execution) -> Bool {
  active.phase is Model &&
  active.model is Some(model) &&
  @model.model_execution_restoring(model)
}

///|
/// Stopped model observations retain custody independently of accepted output.
/// Strict failure may have only an adopted prefix, never fabricated later slots.
pub fn acquire_outcomes(active : Execution) -> @model.ModelOutcomeRead? {
  if active.reclaimed {
    return None
  }
  match active.model {
    Some(model) => @model.acquire_model_outcomes(model)
    None => None
  }
}

///|
fn start_owned(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  sequence_contracts : @input.ClientInstalledSequenceContracts,
  values : String,
  source : Source,
  fixed_request_cid : String,
  limits : Limits,
  plan : @publication_host.ClientInferPlanGraph?,
  acquired_input? : @publication_host.ClientInferCapturedInput? = None,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[Execution, Issue] {
  guard @publication_host.prepared_client_infer_execution_occurrence(
      prepared, step,
    )
    is Some(occurrence) else {
    return Err(Input(@input.UnsupportedProgram))
  }
  if acquired_input is Some(captured) &&
    @publication_host.client_infer_captured_input_source(
      captured, prepared, step,
    )
    is None {
    return Err(CallScope(ForeignInput))
  }
  start_occurrence(
    occurrence,
    Some(prepared),
    source,
    fixed_request_cid,
    limits,
    plan,
    limits => {
      if acquired_input is Some(captured) {
        let input_source = @publication_host.client_infer_captured_input_source(
          captured, prepared, step,
        ).unwrap()
        @input.start_client_acquired_infer_input(
          prepared,
          0,
          step,
          input_source,
          sequence_contracts,
          values,
          limits.input,
          limits.measurement,
          limits.mapping,
          fragment_body~,
          ordered_body~,
        )
      } else {
        @input.start_client_infer_input(
          prepared,
          0,
          step,
          sequence_contracts,
          values,
          limits.input,
          limits.measurement,
          limits.mapping,
          fragment_body~,
          ordered_body~,
        )
      }
    },
    acquired_input~,
  )
}

///|
fn start_occurrence(
  occurrence : @publication_host.ClientInferOccurrence,
  prepared : @publication_host.PreparedClientProgram?,
  source : Source,
  fixed_request_cid : String,
  limits : Limits,
  plan : @publication_host.ClientInferPlanGraph?,
  start_input : (Limits) -> Result[
    @input.ClientInferInputExecution,
    @input.ClientInferInputIssue,
  ],
  acquired_input? : @publication_host.ClientInferCapturedInput? = None,
  composed_sources? : @publication_host.ClientInferComposedSources? = None,
  root? : (
    @relation.GeneratedSequence,
    @relation.GeneratedSequence?,
    @resources.Ledger,
  )? = None,
  prior_input_work? : Int64 = 0L,
) -> Result[Execution, Issue] {
  // A caller-supplied Ledger/root tuple is not the original read/consumer.
  // The checked generated branch enters that same Owner before construction.
  if root is Some(_) {
    return Err(OriginalCapacity(@publication_host.ForeignInput))
  }
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  if limits.output_rows < 0 ||
    limits.output_work < 0 ||
    limits.output_workspace < 0 {
    return Err(InvalidAdvance)
  }
  if fixed_request_cid.length() != 71 ||
    !fixed_request_cid.has_prefix("sha256:") {
    return Err(Model(@model.RequestIdentity))
  }
  for index in 7..<71 {
    let c = fixed_request_cid[index].to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      return Err(Model(@model.RequestIdentity))
    }
  }
  if plan is Some(graph) &&
    (
      !@publication_host.client_infer_occurrence_matches_plan(occurrence, graph) ||
      @publication_host.client_infer_plan_graph_request_cid(graph) !=
      fixed_request_cid
    ) {
    return Err(Model(@model.RequestIdentity))
  }
  let limits = match
    select_infer_execution_limits(
      occurrence,
      plan,
      limits,
      source is Physical(_),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The same completed keyed producer has already debited this work. Retain
  // its cumulative history before constructing the remaining input, while
  // each later child/component reports only its newly performed work.
  let entry_work = composed_sources
    .bind(sources => {
      @publication_host.client_infer_composed_keyed_lookup(sources, occurrence).bind(lookup => {
          @publication_host.client_composed_keyed_lookup_prefix_work(
            lookup, occurrence,
          )
        },
      )
    })
    .unwrap_or(0L)
  if prior_input_work < 0L ||
    prior_input_work > limits.input.max_work.to_int64() - entry_work {
    return Err(InvalidAdvance)
  }
  let input = match start_input(limits) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  Ok({
    prepared,
    occurrence,
    input,
    acquired_input,
    composed_sources,
    serialized_output: None,
    serialized_generation: None,
    source,
    fixed_request_cid,
    step,
    plan,
    limits,
    rows: None,
    identity: None,
    identity_body: None,
    call_scope: None,
    saved_call_scope: None,
    model: None,
    capture: None,
    output: None,
    suffix_sequence: root.bind(value => value.1),
    suffix: None,
    completed: None,
    phase: Phase::Input,
    cancelled: false,
    advancing: false,
    reclaimed: false,
    entry_work: entry_work + prior_input_work,
    work: entry_work + prior_input_work,
    child_work: entry_work,
    output_uses: 0,
    run_binding: None,
    original_preparation: None,
    dispatch_admission: None,
    durable_calls: false,
    model_send_mask: None,
    quantity_capacity: None,
    physical_preflight: None,
    egress_admission: None,
    final_quantity_usage: None,
    local_component_bound: false,
  })
}

///|
pub fn matches(
  active : Execution,
  prepared : @publication_host.PreparedClientProgram,
) -> Bool {
  active.prepared
  .map(actual => physical_equal(actual, prepared))
  .unwrap_or(false) &&
  !active.reclaimed
}

///|
/// Connect an original checked Unit and the common task driver's producer
/// reads to the existing Model component. No private Effect-free preparation
/// is exported or reconstructed. Dispatch still needs bind_run, admission,
/// egress and the installed physical envelope before any advance.
pub fn start_composed(
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
  prefix : @relation.GeneratedSequence,
  inputs : Array[@local.ManagedProviderInput],
  provider : @model.ModelProvider,
  limits : Limits,
  sources? : @publication_host.ClientInferComposedSources? = None,
  root? : (@relation.GeneratedSequence?, @resources.Ledger)? = None,
  prior_input_work? : Int64 = 0L,
) -> Result[Execution, Issue] {
  if sources is Some(value) &&
    !@publication_host.client_infer_composed_sources_matches(value, occurrence) {
    return Err(CallScope(ForeignInput))
  }
  if @publication_host.client_infer_occurrence_has_captured_sources(occurrence) &&
    sources is None {
    return Err(CallScope(ForeignInput))
  }
  start_occurrence(
    occurrence,
    None,
    Physical(provider),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    Some(plan),
    limits => {
      @input.start_client_composed_infer_input(
        occurrence,
        prefix,
        inputs,
        if prior_input_work == 0L {
          limits.input
        } else {
          {
            ..limits.input,
            max_work: limits.input.max_work - prior_input_work.to_int(),
          }
        },
        limits.measurement,
        limits.mapping,
        keyed=sources.bind(value => {
          @publication_host.client_infer_composed_keyed_lookup(
            value, occurrence,
          )
        }),
        captured=sources.bind(value => {
          @publication_host.client_infer_composed_direct_source(
            value, occurrence,
          )
        }),
      )
    },
    composed_sources=sources,
    prior_input_work~,
    root=root.map(value => (prefix, value.0, value.1)),
  )
}

///|
/// Open the original keyed input as one installed Model root, not a Local
/// component or a caller-supplied dense Relation. The same Source closure and
/// input owner enforce the original lookup and both capture observations.
pub fn start_keyed(
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
  prefix : @relation.GeneratedSequence,
  provider : @model.ModelProvider,
  limits : Limits,
  sources : @publication_host.ClientInferComposedSources,
  suffix : @relation.GeneratedSequence?,
  ledger : @resources.Ledger,
) -> Result[Execution, Issue] {
  if @publication_host.client_infer_composed_keyed_lookup(sources, occurrence)
    is None {
    return Err(CallScope(ForeignInput))
  }
  start_composed(
    occurrence,
    plan,
    prefix,
    [],
    provider,
    limits,
    sources=Some(sources),
    root=Some((suffix, ledger)),
  )
}

///|
/// Installed root stepping and Local component stepping are mutually
/// exclusive. The existing execution retains the binding; no adapter flag can
/// grant a second driver authority over a component already bound to Local.
pub fn advance_root(active : Execution, quantum : Int) -> Result[Poll, Issue] {
  if active.local_component_bound {
    return Err(InvalidAdvance)
  }
  advance(active, quantum)
}

///|
fn execution_input_unadvanced(active : Execution) -> Bool {
  active.phase is Input &&
  active.work == active.entry_work &&
  // entry_work includes already consumed original producer work; the live
  // child's own cumulative report starts at its original input entry. Any
  // new child work increments active.work and fails the equality above.
  active.child_work <= active.entry_work
}

///|
fn account(active : Execution, child_work : Int64) -> Bool {
  if child_work < active.child_work ||
    child_work - active.child_work > 9223372036854775807L - active.work {
    return false
  }
  active.work += child_work - active.child_work
  active.child_work = child_work
  true
}

///|
/// Install the checked post-acquisition Compute segment before any progress.
/// This is not permission to dispatch: existing Run and model admissions
/// remain mandatory. Equal source text cannot substitute another owner.
pub fn bind_compute_suffix(
  active : Execution,
  sequence : @relation.GeneratedSequence,
) -> Result[Unit, Issue] {
  guard !active.reclaimed &&
    !active.advancing &&
    !active.cancelled &&
    active.phase is Input &&
    execution_input_unadvanced(active) &&
    active.suffix_sequence is None &&
    physical_equal(
      @publication_host.client_infer_occurrence_preparation(active.occurrence),
      @relation.generated_sequence_owner(sequence),
    ) else {
    return Err(InvalidAdvance)
  }
  let count = @relation.generated_sequence_step_count(sequence)
  if count < 1 ||
    count !=
    @publication_host.client_infer_occurrence_output_step(active.occurrence).unwrap_or(
      -1,
    ) -
    active.step ||
    @local.local_bounded_relation_provider(
      active.limits.input,
      active.limits.measurement,
      sequence,
    )
    is None {
    return Err(Input(@input.UnsupportedProgram))
  }
  for position in 0..<count {
    if @relation.generated_sequence_step_index_at(sequence, position) !=
      Some(active.step + 1 + position) {
      return Err(Input(@input.UnsupportedProgram))
    }
  }
  active.suffix_sequence = Some(sequence)
  Ok(())
}

///|
fn fail(active : Execution, issue : Issue) -> Poll {
  active.phase = Terminal
  Failed(issue, work=active.work)
}

///|
fn stopped(active : Execution) -> Poll {
  active.phase = Terminal
  active.completed = None
  Stopped(work=active.work)
}

///|
fn begin_model(active : Execution) -> Poll {
  guard active.rows is Some(rows) else { return fail(active, InvalidAdvance) }
  let mut model_limits = active.limits.model
  let started = match active.source {
    Physical(provider) =>
      if active.original_preparation is Some(original) {
        guard active.run_binding is Some(bound) &&
          active.plan is Some(plan) &&
          active.call_scope is Some(scope) else {
          return fail(active, InvalidAdvance)
        }
        if original.read is Claimed(consumer) {
          let quoted = match
            @publication_host.client_model_read_consumer_model_limits(
              consumer,
              bound.compiled,
              bound.definition,
              plan,
            ) {
            Err(issue) =>
              return fail(
                active,
                OriginalCapacity(@publication_host.Read(issue)),
              )
            Ok(value) => value
          }
          if quoted is Some(ledger) {
            // Reuse the same installed Plan allowance. Logical item/work and
            // request bounds stay on the checked Model limits; the existing
            // Model startup still checks its contract and parent capacity.
            model_limits = { ..model_limits, ledger, }
          }
        }
        // The seal is retained before attempting startup. A refused start must
        // not lose its unconsumed original capacity or input cleanup custody.
        let issued = match original.read {
          Bound(read) =>
            @model.prepare_original_model_startup(
              read,
              bound.compiled,
              bound.definition,
              plan,
              scope,
              rows,
              original.retained_bytes,
              original.execution_bytes,
            )
          Claimed(consumer) =>
            if original.shared_mock {
              @model.prepare_original_model_provider_consumer_startup(
                consumer,
                bound.compiled,
                bound.definition,
                plan,
                scope,
                rows,
                provider,
                model_limits,
                original.retained_bytes,
                original.execution_bytes,
              )
            } else {
              @model.prepare_original_model_consumer_startup(
                consumer,
                bound.compiled,
                bound.definition,
                plan,
                scope,
                rows,
                original.retained_bytes,
                original.execution_bytes,
              )
            }
        }
        let startup = match issued {
          Ok(value) => value
          Err(issue) => return fail(active, OriginalCapacity(issue))
        }
        original.startup = Some(startup)
        @model.start_original_model_execution(
          startup,
          rows,
          provider,
          active.fixed_request_cid,
          model_limits,
          scope,
          dispatch_admission=active.dispatch_admission,
          durable_calls=active.durable_calls,
          send_mask=active.model_send_mask,
          quantity_capacity=active.quantity_capacity,
          physical_preflight=active.physical_preflight,
          egress_admission=active.egress_admission,
        )
      } else {
        @model.start_model_execution(
          rows,
          provider,
          active.fixed_request_cid,
          active.limits.model,
          call_scope=active.call_scope,
          dispatch_admission=active.dispatch_admission,
          durable_calls=active.durable_calls,
          send_mask=active.model_send_mask,
          quantity_capacity=active.quantity_capacity,
          physical_preflight=active.physical_preflight,
          egress_admission=active.egress_admission,
        )
      }
    Replay(capture) => {
      guard active.call_scope is Some(scope) else {
        return fail(active, Model(@model.OutputIdentity))
      }
      @model.start_model_capture_replay(
        rows,
        scope,
        capture,
        active.limits.model,
      )
    }
    Restored(capture) => {
      guard active.call_scope is Some(scope) else {
        return fail(active, Model(@model.OutputIdentity))
      }
      @model.start_restored_model_capture_replay(
        rows,
        scope,
        capture,
        active.fixed_request_cid,
        active.limits.model,
      )
    }
    RestoredSlots(read) => {
      guard active.call_scope is Some(scope) else {
        return fail(active, Model(@model.OutputIdentity))
      }
      @model.start_restored_model_slot_replay(
        rows,
        scope,
        read,
        active.fixed_request_cid,
        active.limits.model,
        compiled_run=active.run_binding.map(value => value.compiled),
      )
    }
  }
  active.model = match started {
    Ok(value) => Some(value)
    Err(issue) => return fail(active, Model(issue))
  }
  active.child_work = 0L
  active.phase = Model
  Continue(work=active.work)
}

///|
fn advance_child(active : Execution, quantum : Int) -> Poll {
  match active.phase {
    Input =>
      match @input.advance_client_infer_input(active.input, quantum) {
        Err(issue) => fail(active, Input(issue))
        Ok(@input.Continue(work~)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          Continue(work=active.work)
        }
        Ok(@input.Complete(rows, work~)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          active.rows = Some(rows)
          // The child is physically stopped. Cancellation at this transition
          // cannot start the next child or release this retained input early.
          if active.cancelled {
            return stopped(active)
          }
          if active.plan is Some(_) {
            guard @input.client_infer_completed_input(active.input)
              is Some(completed) else {
              return fail(active, InvalidAdvance)
            }
            let limits = active.limits.identity
            if active.identity_body is Some(_) {
              guard @relation.completed_relation_identity_body_start_construction_capacity()
                is Some(start) else {
                return fail(active, InvalidAdvance)
              }
              match grow_original_infer_identity_body_capacity(active, start) {
                Err(issue) => return fail(active, issue)
                Ok(_) => ()
              }
            }
            active.identity = match
              @relation.start_completed_relation_identity_scan(
                completed,
                limits.rows,
                active.limits.input.rows.output_values,
                limits.wire,
                limits.logical_wire,
                limits.schema,
                limits.work,
                limits.workspace,
                incremental_metadata=active.identity_body is Some(_),
                retain_body=active.identity_body is Some(_),
              ) {
              Ok(value) => Some(value)
              Err(issue) => return fail(active, IdentityExport(issue))
            }
            active.child_work = 0L
            active.phase = Identity
            return Continue(work=active.work)
          }
          begin_model(active)
        }
        Ok(@input.Failed(issue, work~)) => {
          account(active, work) |> ignore
          fail(active, Input(issue))
        }
        Ok(@input.Stopped(work~)) => {
          account(active, work) |> ignore
          stopped(active)
        }
      }
    Identity => {
      if active.cancelled {
        return stopped(active)
      }
      guard active.identity is Some(identity) else {
        return fail(active, InvalidAdvance)
      }
      let construction = if active.identity_body is Some(_) {
        guard @relation.completed_relation_identity_scan_next_construction_capacity(
            identity,
          )
          is Some(next) else {
          return fail(active, InvalidAdvance)
        }
        guard @relation.completed_relation_identity_scan_body_next_construction_capacity(
            identity,
          )
          is Some(body_demand) else {
          return fail(active, InvalidAdvance)
        }
        match grow_original_infer_identity_body_capacity(active, body_demand) {
          // The original Read still funds its legacy scan envelope. The new
          // extension above covers only body retention beside that envelope.
          Ok(_) => Some(next)
          Err(issue) => return fail(active, issue)
        }
      } else {
        None
      }
      let (done, _) = match
        @relation.advance_completed_relation_identity_scan(
          identity,
          quantum,
          construction_capacity=construction,
        ) {
        Ok(value) => value
        Err(issue) => {
          if !account(
              active,
              @relation.completed_relation_identity_scan_work(identity),
            ) {
            return fail(active, InvalidAdvance)
          }
          return fail(active, IdentityExport(issue))
        }
      }
      if !account(
          active,
          @relation.completed_relation_identity_scan_work(identity),
        ) {
        return fail(active, InvalidAdvance)
      }
      if !done {
        return Continue(work=active.work)
      }
      let receipt = match
        @relation.finish_completed_relation_identity_scan(identity) {
        Ok(value) => value
        Err(issue) => return fail(active, IdentityExport(issue))
      }
      guard active.plan is Some(plan) &&
        @input.client_infer_completed_input(active.input) is Some(completed) else {
        return fail(active, InvalidAdvance)
      }
      let scoped = match active.saved_call_scope {
        Some(saved) =>
          @publication_host.restore_client_infer_call_scope(
            saved, completed, receipt,
          )
        None =>
          @publication_host.issue_client_infer_occurrence_call_scope(
            active.occurrence,
            plan,
            completed,
            receipt,
            100000,
            10000,
            100,
            captured=active.acquired_input,
            sources=active.composed_sources,
            generation=active.serialized_generation,
          )
      }
      active.call_scope = match scoped {
        Ok(value) => Some(value)
        Err(issue) => return fail(active, CallScope(issue))
      }
      begin_model(active)
    }
    Model => {
      guard active.model is Some(model) else {
        return fail(active, InvalidAdvance)
      }
      match @model.advance_model_execution(model, quantum) {
        Err(issue) => fail(active, Model(issue))
        Ok(@model.Continue(_, work)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          Continue(work=active.work)
        }
        Ok(@model.Waiting(_, work)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          Waiting(work=active.work)
        }
        Ok(@model.AwaitIo(_, work)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          AwaitIo(work=active.work)
        }
        Ok(@model.Settling(slot, _, work)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          Settling(slot, work=active.work)
        }
        Ok(@model.Completed(capture, _, work)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          active.capture = Some(capture)
          if active.cancelled {
            return stopped(active)
          }
          guard active.rows is Some(rows) &&
            @input.client_infer_completion_preparation(active.input, rows)
            is Some(completion) else {
            return fail(active, Model(@model.OutputIdentity))
          }
          active.output = match
            @model.start_model_output_preparation(
              model,
              completion,
              active.limits.output_rows,
              active.limits.output_values,
              active.limits.output_work,
              active.limits.output_workspace,
            ) {
            Ok(value) => Some(value)
            Err(issue) => return fail(active, Model(issue))
          }
          active.child_work = 0L
          active.phase = Output
          Continue(work=active.work)
        }
        Ok(@model.Failed(issue, _, work)) => {
          account(active, work) |> ignore
          fail(active, Model(issue))
        }
        Ok(@model.Stopped(_, _, work)) => {
          account(active, work) |> ignore
          stopped(active)
        }
      }
    }
    Output => {
      guard active.output is Some(output) else {
        return fail(active, InvalidAdvance)
      }
      match @model.advance_model_output_preparation(output, quantum) {
        Err(issue) => fail(active, Model(issue))
        Ok(@relation.AdmittedOutputContinue(work~)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          Continue(work=active.work)
        }
        Ok(@relation.AdmittedOutputComplete(_, work~)) => {
          if !account(active, work) {
            return fail(active, InvalidAdvance)
          }
          if active.cancelled {
            return stopped(active)
          }
          active.completed = match @model.complete_model_output(output) {
            Ok(value) => Some(value)
            Err(issue) => return fail(active, Model(issue))
          }
          if active.suffix_sequence is Some(sequence) {
            let remaining = active.limits.input.max_work.to_int64() -
              active.work
            if remaining < 0L {
              return fail(
                active,
                Input(@input.Local(@connector.Execution(@relation.InputLimit))),
              )
            }
            let outputs = [active.completed.unwrap()]
            if @input.client_infer_completed_input(active.input) is Some(prefix) {
              outputs.push(prefix)
            }
            active.suffix = match
              @input.start_client_infer_suffix(
                sequence,
                outputs,
                { ..active.limits.input, max_work: remaining.to_int(), },
                active.limits.measurement,
              ) {
              Ok(child) => Some(child)
              Err(issue) => return fail(active, Input(issue))
            }
            active.completed = None
            active.child_work = 0L
            active.phase = Compute
            return Continue(work=active.work)
          }
          active.phase = Handoff
          Continue(work=active.work)
        }
        Ok(@relation.AdmittedOutputFailed(_, work~)) => {
          account(active, work) |> ignore
          fail(active, Model(@model.OutputValue))
        }
        Ok(@relation.AdmittedOutputStopped(work~)) => {
          account(active, work) |> ignore
          stopped(active)
        }
      }
    }
    Compute => {
      guard active.suffix is Some(child) else {
        return fail(active, InvalidAdvance)
      }
      let poll = match @local.advance_managed_provider(child, quantum) {
        Ok(poll) => poll
        Err(issue) => return fail(active, Input(@input.Local(issue)))
      }
      let work = match poll {
        @local.Continue(work~, ..)
        | @local.Waiting(work~, ..)
        | @local.Settling(_, work~, ..)
        | @local.Complete(_, work~, ..)
        | @local.Failed(_, work~, ..)
        | @local.Stopped(work~, ..)
        | @local.CarrierComplete(_, work~, ..) => work
      }
      if work < 0L ||
        work > 9223372036854775807L - active.child_work ||
        !account(active, active.child_work + work) {
        return fail(active, InvalidAdvance)
      }
      match poll {
        @local.Continue(..) => Continue(work=active.work)
        // A Compute-only suffix has no approval/custody boundary. Preserve
        // its owner for cancellation and cleanup if an invalid provider pauses.
        @local.Waiting(..) | @local.Settling(_, ..) =>
          fail(active, InvalidAdvance)
        @local.Complete(output, ..) => {
          if active.cancelled {
            return stopped(active)
          }
          active.completed = Some(output)
          active.phase = Handoff
          Continue(work=active.work)
        }
        @local.Failed(issue, ..) => fail(active, Input(@input.Local(issue)))
        @local.Stopped(..) => stopped(active)
        @local.CarrierComplete(_, ..) => fail(active, InvalidAdvance)
      }
    }
    Handoff => {
      if active.cancelled {
        return stopped(active)
      }
      guard active.completed is Some(completed) else {
        return fail(active, InvalidAdvance)
      }
      active.phase = Terminal
      Complete(completed, work=active.work)
    }
    Terminal => fail(active, InvalidAdvance)
  }
}

///|
/// Advance exactly one child. A transition never drains the following child
/// under the same quantum. Concurrent or reentrant calls retain the owner.
pub fn advance(active : Execution, quantum : Int) -> Result[Poll, Issue] {
  if quantum <= 0 ||
    active.advancing ||
    active.reclaimed ||
    active.phase is Terminal {
    return Err(InvalidAdvance)
  }
  if active.model is Some(model) &&
    @model.model_execution_mutation_current(model) is Err(issue) {
    return Err(Model(issue))
  }
  active.advancing = true
  let poll = advance_child(active, quantum)
  active.advancing = false
  Ok(poll)
}

///|
pub fn cancel(active : Execution) -> Bool {
  if active.reclaimed || active.phase is Terminal {
    return false
  }
  if active.original_preparation is Some(original) &&
    original.read is Claimed(consumer) {
    match @publication_host.stop_client_model_read_consumer(consumer) {
      Ok(_) => ()
      Err(_) => return false
    }
  }
  if active.cancelled &&
    !active.reclaimed &&
    active.phase is Model &&
    active.model is Some(model) {
    // A second stop observation after per-call custody is acknowledged must
    // finish the already-fenced child; it never authorizes another send.
    @model.request_model_cancel(model) |> ignore
  }
  if active.cancelled {
    return false
  }
  active.cancelled = true
  match active.phase {
    Input => @input.cancel_client_infer_input(active.input) |> ignore
    Identity =>
      if active.identity is Some(identity) {
        @relation.cancel_completed_relation_identity_scan(identity) |> ignore
      }
    Model =>
      if active.model is Some(model) {
        @model.request_model_cancel(model) |> ignore
      }
    Output =>
      if active.output is Some(output) {
        @model.cancel_model_output_preparation(output) |> ignore
      }
    Compute =>
      if active.suffix is Some(child) {
        @local.cancel_managed_provider(child) |> ignore
      }
    Handoff | Terminal => ()
  }
  true
}

///|
/// Read a bounded physical phase for cancellation tests and diagnostics.
/// This grants no Run, model-egress or evidence authority.
pub fn request_preflight_pending(active : Execution) -> Bool {
  !active.reclaimed &&
  !active.cancelled &&
  active.phase is Model &&
  active.model is Some(model) &&
  @model.model_execution_preflighting(model)
}

///|
pub fn completed(poll : Poll) -> @relation.CompletedOutput? {
  match poll {
    Complete(value, ..) => Some(value)
    _ => None
  }
}

///|
/// Physical settlement only. Reclamation and public Run outcome are separate.
pub fn execution_stopped(active : Execution) -> Bool {
  !active.advancing && active.phase is Terminal
}

///|
pub fn poll_kind(poll : Poll) -> String {
  match poll {
    Continue(_) => "continue"
    AwaitIo(_) => "await_io"
    Waiting(_) => "waiting"
    Settling(_, ..) => "settling"
    Complete(_, ..) => "complete"
    Failed(_, ..) => "failed"
    Stopped(_) => "stopped"
  }
}

///|
pub fn poll_issue(poll : Poll) -> Issue? {
  match poll {
    Failed(issue, ..) => Some(issue)
    _ => None
  }
}

///|
/// Publication and downstream consumers retain separate uses. One consumer's
/// release cannot authorize cleanup while another still needs the output.
pub fn acquire_output(active : Execution) -> OutputUse? {
  guard !active.reclaimed &&
    !active.cancelled &&
    active.phase is Terminal &&
    active.completed is Some(output) &&
    active.output_uses < 2147483647 else {
    return None
  }
  active.output_uses += 1
  Some({ owner: active, output, released: false, })
}

///|
pub fn output(value : OutputUse) -> @relation.CompletedOutput? {
  if value.released || value.owner.reclaimed {
    None
  } else {
    Some(value.output)
  }
}

///|
pub fn release_output(value : OutputUse) -> Bool {
  if value.released {
    return false
  }
  value.released = true
  value.owner.output_uses -= 1
  true
}

///|
/// A handoff is a yield boundary, not yet publication or ownership transfer.
pub fn handoff_pending(active : Execution) -> Bool {
  !active.reclaimed && active.phase is Handoff
}

///|
pub fn identity_pending(active : Execution) -> Bool {
  !active.reclaimed && active.phase is Identity
}

///|
/// Input identity retained by the physical owner, never execution evidence.
pub fn call_scope(
  active : Execution,
) -> @publication_host.ClientInferCallScope? {
  if active.reclaimed {
    None
  } else {
    active.call_scope
  }
}

///|
/// This is the child execution's provisional capture, not a durable Run or
/// model-slot capture artifact. The formal evidence owner seals it separately.
pub fn capture(active : Execution) -> @model.ModelCaptureBundle? {
  if active.reclaimed || active.cancelled || active.completed is None {
    None
  } else {
    active.capture
  }
}

///|
/// Private successful observation issued by the child execution, not a
/// caller's capture bundle or proof of durable Store custody.
pub fn invocation_evidence(
  active : Execution,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  if active.reclaimed {
    None
  } else {
    match active.model {
      Some(model) => @model.model_execution_invocation_evidence(model, slot)
      None => None
    }
  }
}

///|
pub fn evaluation_request(
  active : Execution,
  slot : Int,
) -> (@model.ModelRequest, @model.ModelPhysicalRequestEvidence)? {
  if active.reclaimed {
    return None
  }
  match active.model {
    Some(model) => @model.model_evaluation_request(model, slot)
    None => None
  }
}

///|
/// Retain an opaque read of the checked model owner, independently of output
/// readers. Durable persistence and Run publication are not implied.
pub fn acquire_capture(active : Execution) -> @model.VerifiedModelCapture? {
  if active.reclaimed {
    None
  } else {
    match active.model {
      Some(model) => @model.acquire_verified_model_capture(model)
      None => None
    }
  }
}

///|
pub fn sealing_observation(active : Execution) -> Bool {
  !active.reclaimed &&
  active.model is Some(model) &&
  @model.model_execution_sealing_observation(model)
}

///|
/// Existing installed Local bounds for the initial source-free configuration.
/// This preset does not resolve model policy, dependencies or authorization.
pub fn standard_limits() -> Limits {
  let values : @relation.ValueLimits = {
    max_nodes: 20000,
    max_text_bytes: 500000,
    max_depth: 100,
    max_work: 20000000,
  }
  {
    input: {
      rows: {
        max_rows: 100,
        metadata_entries: 10000,
        retained_entries: 10000,
        operation_entries: 10000,
        input_values: values,
        output_values: values,
      },
      max_work: values.max_work,
      max_frames: 100,
    },
    measurement: {
      max_work: values.max_work,
      max_bytes: values.max_text_bytes,
      max_nodes: values.max_nodes,
      max_depth: values.max_depth,
    },
    mapping: {
      max_items: 100,
      max_work: values.max_work,
      max_frames: 100,
      max_workspace_slots: 10000,
      values: {
        max_nodes: values.max_nodes,
        max_depth: values.max_depth,
        max_text_bytes: values.max_text_bytes,
      },
      logical: {
        max_input_rows: 100L,
        max_value_bytes: 10000L,
        max_live_value_bytes: 100000L,
        max_work: values.max_work.to_int64(),
      },
    },
    model: {
      max_items: 100,
      max_work: 10000,
      max_request_bytes: 65536L,
      max_response_bytes: 65536L,
      value_limits: { max_nodes: 10000, max_depth: 64, max_text_bytes: 65536, },
      ledger: {
        planning_work: 10000,
        attempts: 100,
        holdings: 100,
        transfer_bytes: 13107200L,
        retained_bytes: 6553600L,
        execution_bytes: 6553600L,
      },
    },
    output_rows: 100,
    output_values: values,
    output_work: values.max_work,
    output_workspace: 10000,
    identity: {
      rows: 100,
      wire: {
        max_columns: 100,
        max_order_work: 10000,
        max_bytes: 500000,
        max_nodes: 20000,
        max_depth: 100,
      },
      logical_wire: {
        max_columns: 100,
        max_order_work: 10000,
        max_bytes: 500100,
        max_nodes: 20002,
        max_depth: 102,
      },
      schema: {
        max_fields: 100,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
      work: values.max_work,
      workspace: 100000,
    },
  }
}

///|
/// Physical settlement is separate from reclamation. Keep output, capture,
/// mapped-input and prefix custody in this order until all pins are released.
pub fn cleanup(active : Execution) -> Result[Bool, Issue] {
  if active.reclaimed {
    return Ok(true)
  }
  if active.advancing || !(active.phase is Terminal) || active.output_uses > 0 {
    return Ok(false)
  }
  // Refusal retains every original child and borrow before cleanup mutates it.
  // Stopping this ticket is not physical cleanup or reservation settlement.
  if active.original_preparation is Some(original) &&
    original.read is Claimed(consumer) {
    match @publication_host.stop_client_model_read_consumer(consumer) {
      Ok(_) => ()
      Err(issue) => return Err(OriginalCapacity(@publication_host.Read(issue)))
    }
  }
  if active.suffix is Some(child) {
    match @local.cleanup_managed_provider(child) {
      Ok(true) => ()
      Ok(false) => return Ok(false)
      Err(issue) => return Err(Input(@input.Local(issue)))
    }
    active.suffix = None
    active.completed = None
  }
  if active.output is Some(output) {
    match @model.cleanup_model_output_preparation(output) {
      Ok(true) => ()
      Ok(false) => return Ok(false)
      Err(issue) => return Err(Model(issue))
    }
    active.output = None
    active.completed = None
  }
  if active.model is Some(model) {
    match @model.cleanup_model_execution(model) {
      Ok(true) => ()
      Ok(false) => return Ok(false)
      Err(issue) => return Err(Model(issue))
    }
    active.final_quantity_usage = Some(
      @model.model_execution_quantity_usage(model),
    )
    active.model = None
    active.capture = None
  }
  if active.identity is Some(identity) {
    @relation.cancel_completed_relation_identity_scan(identity) |> ignore
    active.identity = None
  }
  active.identity_body = None
  match @input.cleanup_client_infer_input(active.input) {
    Ok(true) => {
      if active.original_preparation is Some(original) &&
        original.startup is Some(startup) {
        match @model.cleanup_original_model_startup(startup) {
          Ok(true) => ()
          Ok(false) => return Ok(false)
          Err(issue) => return Err(Model(issue))
        }
      }
      if active.source is Replay(capture) {
        @model.release_verified_model_capture(capture) |> ignore
      }
      if active.source is Restored(capture) {
        @publication.release_model_capture_bundle_read(capture) |> ignore
      }
      if active.source is RestoredSlots(read) {
        @model.release_model_slot_replay(read) |> ignore
      }
      active.rows = None
      active.call_scope = None
      active.acquired_input = None
      // Release only our borrowed root after the existing input owner settles.
      // Reclamation of the generated bytes remains with their original owner.
      active.serialized_output = None
      active.serialized_generation = None
      // Core retirement does not prove original FD/Store cleanup. The original
      // read owner retains this stopped ticket until its own physical cleanup
      // settles the read and severs both nominal back-references.
      active.original_preparation = None
      active.reclaimed = true
      Ok(true)
    }
    Ok(false) => Ok(false)
    Err(issue) => Err(Input(issue))
  }
}
