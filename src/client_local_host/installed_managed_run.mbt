///|
/// A same-Host consumer of the selected Resource admission, not another
/// capacity issuer. Any Source reads and the managed DAG borrow this one Ledger.
priv enum ClientInstalledManagedRunOriginal {
  PureManaged(
    @resources.PreparedRunAdmission[@publication_host.PreparedClientProgram],
    @publication_host.PreparedClientProgram
  )
  PlannedEffectManaged(
    @resources.PreparedRunAdmission[ClientInstalledEffectManagedPlan],
    ClientInstalledEffectManagedPlan
  )
  PreparationContentManaged(
    @resources.PreparedRunAdmission[@publication_host.PreparedClientProgram],
    @publication_host.PreparedClientProgram
  )
}

///|
struct ClientInstalledManagedRun {
  mut original : ClientInstalledManagedRun?
  mut preparation : ClientInstalledManagedRunOriginal?
  request : @publication_host.ClientRequestIdentity
  mut ledger : @resources.Ledger?
  reads : Array[ClientInstalledSourceRead?]
  mut content : ClientInstalledContentPreparation
  mut serialization_prefix : ClientSerializationPrefix?
  keyed_reads : Array[ClientInstalledKeyedSourceRead]
  effect_operations : Array[ClientInstalledEffectOperationBorrow?]
  mut effect_operation_opening : Bool
  mut effect_operation_closing : Bool
  mut effect_operation_controls : ClientEffectOperationControls?
  mut source_free_preparation : ClientInstalledManagedSourceFreePreparation?
  mut captured_preparation : ClientInstalledManagedCapturePlan?
  mut preparation_retirement : ClientManagedPreparationCustody?
  mut source_free_captured : @strategy.CapturedDAG?
  mut source_free_opening : Bool
  mut publication_invocation_started : Bool
  mut publication_definition : @publication.PublicationContract?
  mut publication_invocation : @publication.PublicationContract?
  mut publication_started : Bool
  mut publication : ClientProgramPublication?
}

///|
/// Same-owner immutable sequence preparation, not a Resource admission or a
/// Run. The generated originals serve both the quote and actual Host setup.
struct ClientInstalledManagedSourceFreePreparation {
  owner : ClientLocalSequenceOwner
  // Retain the already-bound invocation, not another sample or Run issuer.
  _observed_query_time : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )?
  installed_contracts : ClientInstalledSequenceContracts
  values_body : String
  fragment_body : String?
  ordered_body : String?
  sequences : Array[@execution.GeneratedSequence]
  capacity_plan : ClientLocalCapacityPlan
  configuration : ClientPreparedLocalConfiguration?
  mut compilation : @publication_host.ClientRunCompilation?
  limits : @resources.LedgerLimits
  provider_retained_bytes : Int64
  provider_execution_bytes : Int64
}

///|
/// The SAME installed Plan retained this typed compilation before Run adoption.
/// Reading immutable DATA performs no current callback or compiler work. The
/// existing payload-retirement fence blocks new reads before final physical
/// cleanup; existing borrowers keep their own originals. No prepared token,
/// equal CID or copied Plan can resurrect the retired Run payload.
pub fn installed_managed_run_compilation_original(
  run : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
) -> @publication_host.ClientRunCompilation? {
  guard run.original is Some(original) &&
    physical_equal(original, run) &&
    run.ledger is Some(_) else {
    return None
  }
  if run.preparation is Some(PreparationContentManaged(_, admitted)) &&
    physical_equal(admitted, prepared) {
    guard run.content is KeyedContent(selected, compilation) &&
      physical_equal(selected.prepared, prepared) else {
      return None
    }
    return compilation
  }
  guard run.preparation is Some(PureManaged(_, admitted)) &&
    physical_equal(admitted, prepared) else {
    return None
  }
  if run.captured_preparation is Some(plan) {
    if !physical_equal(plan.prepared, prepared) {
      return None
    }
    return plan.compilation
  }
  guard run.source_free_preparation is Some(plan) &&
    plan.owner is Pure(owner) &&
    physical_equal(owner, prepared) else {
    return None
  }
  plan.compilation
}

///|
/// Same payload-retirement fence as the original compilation getter. A timed
/// module keeps the original issued Run/Definition through its invocation;
/// later publication must consume those originals rather than issue again.
pub fn installed_managed_run_invocation_original(
  run : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
) -> (
  @publication_host.ClientQueryTimePreparation,
  @publication_host.ClientRequestIdentity,
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
)? {
  guard installed_managed_run_compilation_original(run, prepared)
    is Some(artifact) else {
    return None
  }
  let time = match run.captured_preparation {
    Some(plan) => plan._observed_query_time
    None =>
      run.source_free_preparation.bind(plan => {
        plan._observed_query_time.map(original => original.0)
      })
  }
  guard time is Some(time) else { return None }
  let invocation = @publication_host.client_query_time_preparation_invocation(
    time, prepared,
  )
  guard invocation is Some((_, request, compiled, _)) &&
    physical_equal(request, run.request) &&
    @publication_host.client_compiled_run_matches_pure_compilation(
      compiled, prepared, artifact,
    ) else {
    return None
  }
  invocation
}

///|
pub(all) enum ClientInstalledManagedRunIssue {
  SourceAcquisition(@publication_host.ClientSourceAcquisitionIssue)
  SourceRoute(@sourceviews.SourceAcquisitionRouteIssue)
  ForeignOriginal
  Unsupported
  AlreadyBound
  Retired
  CleanupPending
  InsufficientCapacity
  Resource(@resources.ImportedChildLedgerIssue)
  Preparation(@resources.PreparationCapacityIssue)
  Ledger(@resources.LedgerIssue)
  ModelRead(@publication_host.ClientModelReadPreparationIssue)
  ModelLayout(@publication_host.ClientModelPreparationLayoutIssue)
  Sequence(@lower.SequenceIssue)
  SerializationPrefix(ClientSerializationPrefixIssue)
  MetadataCapacityUnavailable
}

///|
fn installed_managed_run_purpose_supported(
  prepared : @publication_host.PreparedClientProgram,
) -> Bool {
  installed_managed_run_shape_supported(prepared, false)
}

///|
// Purpose is selected by a fixed entry, not by caller DATA. The shared shape
// calculation does not convert a Source/Compute admission into a Model one.
fn installed_managed_run_shape_supported(
  prepared : @publication_host.PreparedClientProgram,
  mock_model : Bool,
) -> Bool {
  installed_managed_owner_shape_supported(Pure(prepared), mock_model)
}

///|
fn installed_managed_owner_shape_supported(
  owner : ClientLocalSequenceOwner,
  mock_model : Bool,
  model? : @publication_host.ClientInferPlanGraph? = None,
  model_graphs? : Array[@publication_host.ClientInferPlanGraph]? = None,
  model_occurrence? : @publication_host.ClientInferOccurrence? = None,
  model_occurrences? : Array[@publication_host.ClientInferOccurrence]? = None,
  content? : ClientInstalledEffectContentPreparation? = None,
) -> Bool {
  let graph = installed_managed_owner_graph(owner)
  let captured = @strategy.graph_captured_prefix(graph)
  // A Graph constructor has the original occurrence before the Graph exists.
  // Later module/Plan callers must supply their actual checked Graph instead.
  let selected_occurrence = match model {
    Some(selected) => Some(selected.occurrence)
    None =>
      match model_graphs {
        Some(graphs) => graphs.get(0).map(value => value.occurrence)
        None =>
          match (owner, model_occurrence) {
            (Effect(prepared), None) if mock_model =>
              @publication_host.prepared_client_effect_infer_occurrence(
                prepared,
              )
            _ => model_occurrence
          }
      }
  }
  // Reuse the same immutable checked occurrence inventory for the count and
  // ordered identity comparison; do not enumerate it again for the vector.
  let original_occurrences = match owner {
    Pure(prepared) =>
      @publication_host.prepared_client_composed_infer_occurrences(prepared)
    Effect(_) => None
  }
  let boundary_count = match owner {
    Pure(_) => original_occurrences.map(value => value.length())
    Effect(prepared) =>
      Some(
        if @publication_host.prepared_client_effect_infer_occurrence(prepared)
          is Some(_) {
          1
        } else {
          0
        },
      )
  }
  if model_graphs is Some(graphs) {
    guard mock_model &&
      model is None &&
      model_occurrences is None &&
      owner is Pure(prepared) &&
      original_occurrences is Some(expected) &&
      graphs.length() > 1 &&
      graphs.length() == expected.length() else {
      return false
    }
    for index, selected in graphs {
      if !physical_equal(selected.owner, prepared) ||
        !@publication_host.client_infer_occurrence_matches_plan(
          expected[index],
          selected,
        ) ||
        selected.serialization is Some(_) {
        return false
      }
    }
  }
  let selected_count = match model_occurrences {
    None =>
      match model_graphs {
        Some(graphs) => graphs.length()
        None => if mock_model { 1 } else { 0 }
      }
    Some(originals) => {
      guard mock_model &&
        owner is Pure(prepared) &&
        originals.length() > 1 &&
        original_occurrences is Some(expected) &&
        expected.length() == originals.length() else {
        return false
      }
      for index, original in originals {
        if !@publication_host.client_infer_occurrence_matches(
            original, prepared,
          ) ||
          @publication_host.client_infer_occurrence_coordinates(original) !=
          @publication_host.client_infer_occurrence_coordinates(expected[index]) {
          return false
        }
      }
      originals.length()
    }
  }
  let serialized = match owner {
    Pure(prepared) =>
      @publication_host.prepared_client_serialization_occurrences(prepared)
    Effect(prepared) =>
      @publication_host.prepared_client_effect_serialization_occurrences(
        prepared,
      )
  }
  (
    (
      captured > 0 &&
      (
        !mock_model ||
        captured == 2 ||
        (selected_occurrence is Some(_) && captured == 1)
      )
    ) ||
    (captured == 0 && @strategy.graph_source_free_inputs_complete(graph))
  ) &&
  boundary_count is Some(count) &&
  count == selected_count &&
  (match model {
    None =>
      (
        (serialized.is_empty() && content is None) ||
        (match (owner, content) {
          (Effect(prepared), Some(original)) =>
            installed_effect_content_preparation_matches(original, prepared)
          _ => false
        })
      ) &&
      (match (model_occurrence, owner) {
        (None, _) => true
        (Some(original), Pure(prepared)) =>
          mock_model &&
          @publication_host.client_infer_occurrence_matches(original, prepared)
        _ => false
      })
    Some(selected) =>
      mock_model &&
      (match owner {
        Pure(prepared) =>
          physical_equal(selected.owner, prepared) &&
          @publication_host.client_infer_occurrence_matches_plan(
            selected.occurrence,
            selected,
          ) &&
          (match selected.serialization {
            None => serialized.is_empty()
            Some(component) =>
              physical_equal(component.owner, prepared) &&
              serialized == [(component.task, component.step)]
          })
        Effect(_) => false
      })
  })
}

///|
fn source_free_installed_managed_preparation_owned(
  owner : ClientLocalSequenceOwner,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  mock_model : Bool,
  model? : @publication_host.ClientInferPlanGraph? = None,
  model_graphs? : Array[@publication_host.ClientInferPlanGraph]? = None,
  content? : ClientInstalledEffectContentPreparation? = None,
  query_time? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )? = None,
) -> Result[
  ClientInstalledManagedSourceFreePreparation,
  ClientInstalledManagedRunIssue,
] {
  let graph = installed_managed_owner_graph(owner)
  if !installed_managed_owner_shape_supported(
      owner,
      mock_model,
      model~,
      model_graphs~,
      content~,
    ) ||
    @strategy.graph_captured_prefix(graph) != 0 ||
    !@strategy.graph_source_free_inputs_complete(graph) {
    return Err(Unsupported)
  }
  let task_count = @strategy.graph_task_count(graph)
  if task_count < 1 {
    return Err(Unsupported)
  }
  let sequences = match
    prepare_client_local_sequences_owned(
      owner,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      query_time~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if sequences.length() != task_count {
    return Err(Unsupported)
  }
  let inputs = Array::make(task_count, 0)
  for index in 0..<@strategy.graph_data_count(graph) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return Err(Unsupported)
    }
    let consumer = @strategy.data_edge_consumer(edge)
    if consumer < 0 || consumer >= task_count {
      return Err(Unsupported)
    }
    inputs[consumer] += 1
  }
  let max_rows = match owner {
    Pure(prepared) =>
      @publication_host.prepared_client_values_max_rows(prepared)
    Effect(_) =>
      @publication_host.client_standard_values_sequence_limits().max_rows
  }
  let capacity_plan = client_local_capacity_plan(
    sequences,
    max_rows,
    // These are facts of the SAME checked Compute graph, not Pure permission.
    // Effect operation/physical demand remains separately composed below its
    // original owner; an unproved nested schema still takes the old fallback.
    scalar_values=true,
    graph=Some(graph),
    content~,
  )
  // Preserve the failed required quote before entering provider construction.
  // Neither a genuine zero nor a graph-less calculator means quote failure.
  if capacity_plan.metadata_quote is MetadataUnavailable {
    return Err(MetadataCapacityUnavailable)
  }
  guard client_local_sequence_capacity(
      sequences,
      task_count,
      capacity_plan=Some(capacity_plan),
      retained_inputs=Some(inputs),
      max_rows~,
    )
    is Some((limits, provider_retained_bytes, provider_execution_bytes)) else {
    return Err(Unsupported)
  }
  Ok({
    owner,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    sequences,
    capacity_plan,
    configuration: None,
    compilation: None,
    _observed_query_time: query_time,
    limits,
    provider_retained_bytes,
    provider_execution_bytes,
  })
}

///|
/// Retain the actual selected module before its Run exists. The caller must
/// already fund factory/module/control construction on its original initial
/// preparation; the returned execution limits do not pay for that overlap.
pub fn prepare_installed_managed_source_free_with_contracts(
  prepared : @publication_host.PreparedClientProgram,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  query_time? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )? = None,
) -> Result[
  ClientInstalledManagedSourceFreePreparation,
  ClientInstalledManagedRunIssue,
] {
  let original = match
    source_free_installed_managed_preparation_owned(
      Pure(prepared),
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      false,
      query_time~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  configure_installed_source_free_preparation(
    prepared, original, retained_output, provider_factory,
  )
}

///|
// Both fixed purposes configure their same original sequences once. This
// neither selects a purpose nor constructs a second Plan/Resource owner.
fn configure_installed_source_free_preparation(
  prepared : @publication_host.PreparedClientProgram,
  original : ClientInstalledManagedSourceFreePreparation,
  retained_output : Bool,
  provider_factory : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
) -> Result[
  ClientInstalledManagedSourceFreePreparation,
  ClientInstalledManagedRunIssue,
] {
  let configuration = match
    prepare_client_local_configuration(
      @publication_host.prepared_client_graph(prepared),
      original.capacity_plan,
      AdmittedRows,
      original.provider_retained_bytes,
      original.provider_execution_bytes,
      retained_output,
      provider_factory,
    ) {
    Some(value) => value
    None => return Err(Unsupported)
  }
  let actual = match
    client_prepared_local_configuration_capacity(configuration, original.limits) {
    Some(value) => value
    None => return Err(Unsupported)
  }
  // The raw sequence/policy inputs remain the same originals. The actual
  // selected module and its sealed IO envelopes replace a late factory call.
  Ok({ ..original, configuration: Some(configuration), limits: actual.limits, })
}

///|
/// Copy only the six scalar limits. Callers cannot mutate the original
/// generated sequences or turn this quote into an admitted Ledger.
pub fn prepared_installed_managed_source_free_requirements(
  value : ClientInstalledManagedSourceFreePreparation,
) -> Array[Int64] {
  let limits = value.limits
  [
    limits.planning_work.to_int64(),
    limits.attempts.to_int64(),
    limits.holdings.to_int64(),
    limits.transfer_bytes,
    limits.retained_bytes,
    limits.execution_bytes,
  ]
}

///|
fn installed_source_free_preparation_matches(
  value : ClientInstalledManagedSourceFreePreparation,
  owner : ClientLocalSequenceOwner,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Bool {
  let same_owner = match (value.owner, owner) {
    (Pure(a), Pure(b)) => physical_equal(a, b)
    (Effect(a), Effect(b)) => physical_equal(a, b)
    _ => false
  }
  same_owner &&
  physical_equal(value.installed_contracts, installed_contracts) &&
  value.values_body == values_body &&
  value.fragment_body == fragment_body &&
  value.ordered_body == ordered_body
}

///|
/// The same actual Resource admission remains mandatory. Preparation DATA
/// supplies neither capacity nor authority and cannot replace its original.
pub fn begin_prepared_installed_managed_source_free_run(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  original : ClientInstalledManagedSourceFreePreparation,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard original.owner is Pure(owner) &&
    physical_equal(owner, prepared) &&
    original.configuration is Some(_) else {
    return Err(ForeignOriginal)
  }
  if original._observed_query_time is Some((_, bound_request)) &&
    !physical_equal(bound_request, request) {
    return Err(ForeignOriginal)
  }
  let value = match begin_installed_managed_run(admission, prepared, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  value.source_free_preparation = Some(original)
  Ok(value)
}

///|
/// Quote the original acquisitions, if any, and managed sequence inventory
/// before physical reads. These extents cannot issue or replace the actual
/// Resource admission, and unsupported downstream families stay unavailable.
pub fn installed_managed_run_requirements(
  prepared : @publication_host.PreparedClientProgram,
  declarations : Array[@row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], ClientInstalledManagedRunIssue] {
  installed_managed_run_requirements_owned(
    Pure(prepared),
    declarations,
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    false,
  )
}

///|
/// The installed Source supplies its typed capture envelope, not a row-source
/// declaration for a different backend. Quote the same checked capture prefix
/// and Local suffix used when that Run later borrows its original Ledger.
pub fn installed_managed_capture_run_requirements(
  prepared : @publication_host.PreparedClientProgram,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], ClientInstalledManagedRunIssue] {
  if !installed_managed_run_purpose_supported(prepared) {
    return Err(Unsupported)
  }
  guard multi_captured_installed_limits_owned(
      Pure(prepared),
      capacities,
      transport_bytes,
      transport_execution_bytes,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
    )
    is Some(limits) else {
    return Err(Unsupported)
  }
  Ok([
    limits.planning_work.to_int64(),
    limits.attempts.to_int64(),
    limits.holdings.to_int64(),
    limits.transfer_bytes,
    limits.retained_bytes,
    limits.execution_bytes,
  ])
}

///|
// The separate Mock entry quotes the same Source and Compute inventory. It
// still requires its own Resource admission and early same-Run Model Scope.
pub fn installed_mock_model_run_requirements(
  prepared : @publication_host.PreparedClientProgram,
  declarations : Array[@row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], ClientInstalledManagedRunIssue] {
  installed_managed_run_requirements_owned(
    Pure(prepared),
    declarations,
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    true,
  )
}

///|
fn installed_managed_run_requirements_owned(
  owner : ClientLocalSequenceOwner,
  declarations : Array[@row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  mock_model : Bool,
) -> Result[Array[Int64], ClientInstalledManagedRunIssue] {
  if !installed_managed_owner_shape_supported(owner, mock_model) {
    return Err(Unsupported)
  }
  if @strategy.graph_captured_prefix(installed_managed_owner_graph(owner)) == 0 {
    if !declarations.is_empty() ||
      !transport_bytes.is_empty() ||
      !transport_execution_bytes.is_empty() {
      return Err(Unsupported)
    }
    let original = match
      source_free_installed_managed_preparation_owned(
        owner, installed_contracts, values_body, fragment_body, ordered_body, mock_model,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let limits = original.limits
    return Ok([
      limits.planning_work.to_int64(),
      limits.attempts.to_int64(),
      limits.holdings.to_int64(),
      limits.transfer_bytes,
      limits.retained_bytes,
      limits.execution_bytes,
    ])
  }
  let acquisitions = match
    prepare_installed_managed_acquisitions_owned(
      owner, declarations, query_contract_body, evidence_contract_body, installed_contracts,
      values_body, fragment_body, ordered_body,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let capacities = []
  for acquisition in acquisitions {
    guard installed_row_capture_capacity(acquisition) is Some(capacity) else {
      return Err(Unsupported)
    }
    capacities.push(capacity)
  }
  guard multi_captured_installed_limits_owned(
      owner, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
      values_body, fragment_body, ordered_body,
    )
    is Some(limits) else {
    return Err(Unsupported)
  }
  Ok([
    limits.planning_work.to_int64(),
    limits.attempts.to_int64(),
    limits.holdings.to_int64(),
    limits.transfer_bytes,
    limits.retained_bytes,
    limits.execution_bytes,
  ])
}

///|
// One set of original acquisition constructors serves quote and retained plan.
fn prepare_installed_managed_acquisitions_owned(
  owner : ClientLocalSequenceOwner,
  declarations : Array[@row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  direct_occurrences? : @publication_host.ClientDirectAcquisitionOccurrences? = None,
  query_time? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )? = None,
) -> Result[
  Array[@row_source_host.RowAcquisition],
  ClientInstalledManagedRunIssue,
] {
  let captured = @strategy.graph_captured_prefix(
    installed_managed_owner_graph(owner),
  )
  if declarations.length() != captured {
    return Err(Unsupported)
  }
  if captured == 0 {
    return Ok([])
  }
  let selected = match direct_occurrences {
    Some(value) => value
    None =>
      match installed_direct_occurrences_owned(owner) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
  }
  if !installed_direct_occurrences_match_owner(selected, owner) ||
    @publication_host.client_direct_acquisition_occurrence_count(selected) !=
    captured {
    return Err(ForeignOriginal)
  }
  let acquisitions = []
  for index in 0..<captured {
    guard @publication_host.client_direct_acquisition_occurrence_at(
        selected, index,
      )
      is Some((stage, input, task)) &&
      task == index else {
      return Err(ForeignOriginal)
    }
    guard prepare_local_query_requirement_owned(
        owner,
        stage,
        input,
        installed_contracts,
        values_body,
        fragment_body,
        ordered_body,
        query_time~,
      )
      is Ok(requirement) &&
      @row_source_host.prepare_row_acquisition(
        declarations[index],
        requirement,
        query_contract_body,
        evidence_contract_body,
      )
      is Ok(acquisition) else {
      return Err(Unsupported)
    }
    acquisitions.push(acquisition)
  }
  Ok(acquisitions)
}

///|
/// The actual installation has retained this admission before compilation.
/// Bind the resulting original checked Program/request; start/take the
/// original imported child once, never once per Source occurrence.
pub fn begin_installed_managed_run(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  match
    @resources.check_node_source_compute_run_preparation(admission, prepared) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  let identity = @publication_host.prepared_client_identity(prepared)
  if identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) {
    return Err(ForeignOriginal)
  }
  if !installed_managed_run_purpose_supported(prepared) {
    return Err(Unsupported)
  }
  let ledger = match @resources.start_node_managed_run_admission(admission) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  Ok(new_installed_managed_run(admission, prepared, request, ledger))
}

///|
fn new_installed_managed_run(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  ledger : @resources.Ledger,
) -> ClientInstalledManagedRun {
  new_installed_managed_run_owned(
    PureManaged(@resources.node_prepared_run_admission(admission), prepared),
    request,
    ledger,
  )
}

///|
fn installed_managed_run_owner(
  value : ClientInstalledManagedRun,
) -> Result[ClientLocalSequenceOwner, ClientInstalledManagedRunIssue] {
  match value.preparation {
    Some(PureManaged(_, prepared)) => Ok(Pure(prepared))
    Some(PlannedEffectManaged(_, plan)) => Ok(Effect(plan.prepared))
    Some(PreparationContentManaged(_, prepared)) => Ok(Pure(prepared))
    None => Err(Retired)
  }
}

///|
fn installed_managed_owner_graph(
  owner : ClientLocalSequenceOwner,
) -> @strategy.CheckedDAG {
  match owner {
    Pure(prepared) => @publication_host.prepared_client_graph(prepared)
    Effect(prepared) =>
      @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(prepared),
      )
  }
}

///|
fn new_installed_managed_run_owned(
  preparation : ClientInstalledManagedRunOriginal,
  request : @publication_host.ClientRequestIdentity,
  ledger : @resources.Ledger,
) -> ClientInstalledManagedRun {
  let value : ClientInstalledManagedRun = {
    original: None,
    preparation: Some(preparation),
    request,
    ledger: Some(ledger),
    reads: Array::make(
      @strategy.graph_captured_prefix(
        installed_managed_owner_graph(
          match preparation {
            PureManaged(_, prepared) => Pure(prepared)
            PlannedEffectManaged(_, plan) => Effect(plan.prepared)
            PreparationContentManaged(_, prepared) => Pure(prepared)
          },
        ),
      ),
      None,
    ),
    content: NoContent,
    serialization_prefix: None,
    keyed_reads: [],
    effect_operations: [],
    effect_operation_opening: false,
    effect_operation_closing: false,
    effect_operation_controls: None,
    source_free_preparation: None,
    captured_preparation: None,
    preparation_retirement: None,
    source_free_captured: None,
    source_free_opening: false,
    publication_invocation_started: false,
    publication_definition: None,
    publication_invocation: None,
    publication_started: false,
    publication: None,
  }
  value.original = Some(value)
  value
}

///|
fn require_installed_managed_run(
  value : ClientInstalledManagedRun,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) && physical_equal(value, original) else {
    return Err(ForeignOriginal)
  }
  guard value.ledger is Some(ledger) else { return Err(Retired) }
  guard value.preparation is Some(preparation) else { return Err(Retired) }
  let checked = match preparation {
    PureManaged(admission, prepared) =>
      check_installed_managed_run_admission(admission, prepared, ledger)
    PlannedEffectManaged(admission, plan) =>
      check_installed_managed_run_admission(admission, plan, ledger)
    PreparationContentManaged(admission, prepared) =>
      check_installed_managed_run_admission(admission, prepared, ledger)
  }
  match checked {
    // Preserve the original parked-inventory error boundary. The same Core
    // check now reads that state after its one physical current callback.
    Err(Resource(ResourceParked)) => return Err(Ledger(ResourceParked))
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  check_installed_managed_run_original(value, ledger, preparation)
}

///|
// Callback-free fence after the original current observation or a closed
// constructor. This checks the same lifetime and bindings without observing
// the external Resource again at the same synchronous boundary.
fn check_installed_managed_run_original(
  value : ClientInstalledManagedRun,
  ledger : @resources.Ledger,
  preparation : ClientInstalledManagedRunOriginal,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) &&
    physical_equal(value, original) &&
    value.ledger is Some(current_ledger) &&
    physical_equal(current_ledger, ledger) &&
    value.preparation is Some(current_preparation) else {
    return Err(Retired)
  }
  let same = match (preparation, current_preparation) {
    (PureManaged(a, p), PureManaged(b, q)) =>
      physical_equal(a, b) && physical_equal(p, q)
    (PlannedEffectManaged(a, p), PlannedEffectManaged(b, q)) =>
      physical_equal(a, b) && physical_equal(p, q)
    (PreparationContentManaged(a, p), PreparationContentManaged(b, q)) =>
      physical_equal(a, b) && physical_equal(p, q)
    _ => false
  }
  if same {
    Ok(ledger)
  } else {
    Err(Retired)
  }
}

///|
/// Observe the same live Run's managed limits and counters without borrowing
/// execution authority. Observation does not check Account admission, report
/// usage, stop the child or acknowledge cleanup. A pending original remains
/// observable; a foreign or retired handle cannot supply a zero snapshot.
///
/// The fresh array follows the complete Core-owned LedgerLimits and
/// LedgerUsage declaration order; the generator owns both field inventories.
/// These are managed accounting values, not a measurement of process memory
/// or physical cleanup.
pub fn installed_managed_run_accounting(
  value : ClientInstalledManagedRun,
) -> Result[Array[Int64], ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) && physical_equal(value, original) else {
    return Err(ForeignOriginal)
  }
  guard value.ledger is Some(ledger) else { return Err(Retired) }
  Ok(installed_managed_run_accounting_values(ledger))
}

///|
fn installed_managed_run_accounting_values(
  ledger : @resources.Ledger,
) -> Array[Int64] {
  @resources.ledger_limits_usage_values(ledger)
}

///|
fn[P] check_installed_managed_run_admission(
  admission : @resources.PreparedRunAdmission[P],
  prepared : P,
  ledger : @resources.Ledger,
) -> Result[Unit, @resources.ImportedChildLedgerIssue] {
  @resources.check_prepared_run_admission(admission, prepared, ledger)
}

///|
pub fn check_installed_managed_run(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  match check_installed_managed_run_binding(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  require_installed_managed_run(value).map(_ => ())
}

///|
// Immutable original binding only. The consuming operation owns one actual
// current callback and the existing post-callback reentry fence.
fn check_installed_managed_run_binding(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard value.preparation is Some(preparation) else { return Err(Retired) }
  let selected = match preparation {
    PureManaged(_, prepared) => Some(prepared)
    PreparationContentManaged(_, prepared) => Some(prepared)
    PlannedEffectManaged(_, _) => None
  }
  guard selected is Some(original) &&
    physical_equal(original, prepared) &&
    value.request == request else {
    return Err(ForeignOriginal)
  }
  if value.captured_preparation is Some(plan) &&
    !physical_equal(plan.request, request) {
    return Err(ForeignOriginal)
  }
  Ok(())
}

///|
/// Every read keeps the same admitted parent; this is not a second import,
/// a Source-only child conversion, or a getter for a public bare Ledger.
pub fn begin_installed_managed_run_source_read(
  value : ClientInstalledManagedRun,
  occurrence : Int,
) -> Result[ClientInstalledSourceRead, ClientInstalledManagedRunIssue] {
  begin_installed_managed_run_source_read_owned(value, occurrence, None)
}

///|
pub fn begin_installed_managed_run_source_read_at(
  value : ClientInstalledManagedRun,
  stage : Int,
  input : Int,
  task : Int,
) -> Result[ClientInstalledSourceRead, ClientInstalledManagedRunIssue] {
  begin_installed_managed_run_source_read_owned(
    value,
    task,
    Some((stage, input, task)),
  )
}

///|
fn begin_installed_managed_run_source_read_owned(
  value : ClientInstalledManagedRun,
  occurrence : Int,
  expected : (Int, Int, Int)?,
) -> Result[ClientInstalledSourceRead, ClientInstalledManagedRunIssue] {
  let ledger = match require_installed_managed_run(value) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  if occurrence < 0 || occurrence >= value.reads.length() {
    return Err(Unsupported)
  }
  if value.reads[occurrence] is Some(_) {
    return Err(AlreadyBound)
  }
  let owner = match installed_managed_run_owner(value) {
    Err(issue) => return Err(issue)
    Ok(owner) => owner
  }
  if expected is Some(coordinate) &&
    installed_managed_run_direct_occurrence(value, occurrence) !=
    Some(coordinate) {
    return Err(ForeignOriginal)
  }
  let read : ClientInstalledSourceRead = {
    original: None,
    child: None,
    managed_run: Some((value, occurrence)),
    ledger: Some(ledger),
    owner: Some(owner),
    declaration: None,
    requirement: None,
    acquisition: None,
    whole_input: None,
    run: None,
    started: false,
  }
  read.original = Some(read)
  value.reads[occurrence] = Some(read)
  Ok(read)
}

///|
/// The same inventory as the legacy Local entry, checked against the actual
/// admitted Run instead of creating a scalar accounting replacement.
pub fn prepare_installed_managed_run_ledger(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  match check_installed_managed_run_binding(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  prepare_installed_managed_run_ledger_owned(
    value, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
    values_body, fragment_body, ordered_body,
  )
}

///|
fn prepare_installed_managed_run_ledger_owned(
  value : ClientInstalledManagedRun,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  let ledger = match require_installed_managed_run(value) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  if value.content is KeyedContent(selected, _) {
    return prepare_retained_installed_keyed_content_ledger(
      value, selected, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
      values_body, fragment_body, ordered_body, ledger,
    )
  }
  if value.content is SerializationContent(content) {
    // The acquired Model already adopted this SAME module/compiler and
    // prefix. Borrow its retained Source inventory without widening a bare
    // terminal Content Run or reconstructing capacity after adoption.
    guard value.captured_preparation is Some(plan) &&
      physical_equal(content.prepared, plan.prepared) &&
      physical_equal(content.request, plan.request) &&
      plan.compilation is Some(@publication_host.Tasks(compilation)) &&
      compilation.infers.length() == 1 &&
      compilation.infers[0].serialization is Some(component) &&
      @publication_host.client_task_compilation_serialization(compilation)
      is Some(original_component) &&
      physical_equal(component, original_component) &&
      @publication_host.client_compiled_run_matches_tasks(
        content._observed_compiled,
        plan.prepared,
        compilation,
      ) &&
      @publication_host.check_client_compiled_run_definition(
        content._observed_compiled,
        content._observed_definition,
      )
      is Ok(_) else {
      return Err(Unsupported)
    }
    return prepare_retained_installed_capture_ledger(
      value, plan, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
      values_body, fragment_body, ordered_body, ledger,
    )
  }
  let owner = match installed_managed_run_owner(value) {
    Err(issue) => return Err(issue)
    Ok(owner) => owner
  }
  if capacities.length() != value.reads.length() ||
    transport_bytes.length() != capacities.length() ||
    transport_execution_bytes.length() != capacities.length() {
    return Err(Unsupported)
  }
  if value.captured_preparation is Some(plan) {
    return prepare_retained_installed_capture_ledger(
      value, plan, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
      values_body, fragment_body, ordered_body, ledger,
    )
  }
  if value.preparation is Some(PlannedEffectManaged(_, plan)) {
    return prepare_planned_installed_effect_ledger(
      value, plan, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
      values_body, fragment_body, ordered_body,
    )
  }
  let required = if value.reads.is_empty() {
    if !capacities.is_empty() ||
      !transport_bytes.is_empty() ||
      !transport_execution_bytes.is_empty() {
      return Err(Unsupported)
    }
    match value.source_free_preparation {
      Some(original) => {
        if !installed_source_free_preparation_matches(
            original, owner, installed_contracts, values_body, fragment_body, ordered_body,
          ) {
          return Err(ForeignOriginal)
        }
        Some(original.limits)
      }
      None => {
        let original = match
          source_free_installed_managed_preparation_owned(
            owner,
            installed_contracts,
            values_body,
            fragment_body,
            ordered_body,
            installed_managed_owner_shape_supported(owner, true),
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        // Retain the first checked plan before projecting its limits. Host
        // opening and publication borrow this original until Run retirement.
        value.source_free_preparation = Some(original)
        Some(original.limits)
      }
    }
  } else {
    multi_captured_installed_limits_owned(
      owner, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
      values_body, fragment_body, ordered_body,
    )
  }
  guard required is Some(required) else { return Err(Unsupported) }
  let available = @resources.ledger_limits(ledger)
  if required.planning_work > available.planning_work ||
    required.attempts > available.attempts ||
    required.holdings > available.holdings ||
    required.transfer_bytes > available.transfer_bytes ||
    required.retained_bytes > available.retained_bytes ||
    required.execution_bytes > available.execution_bytes {
    return Err(InsufficientCapacity)
  }
  for index in 0..<value.reads.length() {
    if !capacities[index].original_input {
      // Native/Broad DuckDB captures already borrow this same Ledger through
      // their typed configuration. They are not RowAcquisition children and
      // cannot manufacture that backend's original read token. This ordinary
      // path admits only the existing opaque DuckDB capacity representation;
      // a Row child or Effect parent cannot be substituted for it.
      guard value.preparation is Some(PureManaged(_, _)) &&
        capacities[index].provider is None &&
        value.reads[index] is None else {
        return Err(Unsupported)
      }
      continue
    }
    if capacities[index].provider is Some(_) {
      return Err(Unsupported)
    }
    guard value.reads[index] is Some(read) &&
      read.acquisition is Some(acquisition) &&
      physical_equal(
        @row_source_host.row_acquisition_requirement(acquisition),
        capacities[index].requirement,
      ) else {
      return Err(ForeignOriginal)
    }
  }
  // All generated sequence and capacity work above remains under this same
  // original admission; a currentness loss cannot publish a usable Ledger.
  require_installed_managed_run(value)
}

///|
/// Open source-free Compute on the same admitted Run. The original Ledger is
/// checked again after sequence preparation; no scalar fallback can replace it.
pub fn open_installed_managed_source_free_host(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  retained_output : Bool,
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
) -> Result[
  @builtin.ConfiguredComputeHost[@strategy.RunIssue]?,
  ClientInstalledManagedRunIssue,
] {
  if value.source_free_opening || value.source_free_captured is Some(_) {
    return Err(AlreadyBound)
  }
  value.source_free_opening = true
  let opened = open_installed_managed_source_free_host_original(
    value,
    prepared,
    request,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    retained_output,
    provider_factory~,
  )
  value.source_free_opening = false
  opened
}

///|
fn open_installed_managed_source_free_host_original(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  retained_output : Bool,
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
) -> Result[
  @builtin.ConfiguredComputeHost[@strategy.RunIssue]?,
  ClientInstalledManagedRunIssue,
] {
  if value.source_free_captured is Some(_) {
    return Err(AlreadyBound)
  }
  if !value.reads.is_empty() {
    return Err(Unsupported)
  }
  match check_installed_managed_run(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.source_free_preparation is Some(original) &&
    original.configuration is Some(configuration) &&
    configuration.retained_output != retained_output {
    return Err(ForeignOriginal)
  }
  let ledger = match
    prepare_installed_managed_run_ledger(
      value,
      prepared,
      request,
      [],
      [],
      [],
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
    ) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  if value.source_free_preparation is Some(original) &&
    original.configuration is Some(configuration) {
    let run = match
      @strategy.open_source_free_dag(
        @publication_host.prepared_client_graph(prepared),
        ledger,
      ) {
      Ok(value) => value
      Err(_) => return Ok(None)
    }
    // The existing Run owner retains its only issued graph before binding.
    // A failed bind or reentrant current change cannot authorize another open.
    value.source_free_captured = Some(run)
    let host = bind_client_local_configuration(
      run, configuration, 1L, 0L, 0L, 0L,
    )
    match require_installed_managed_run(value) {
      Err(issue) => {
        ignore(reject_client_local_run(run))
        return Err(issue)
      }
      Ok(parent) =>
        if !physical_equal(parent, ledger) {
          ignore(reject_client_local_run(run))
          return Err(ForeignOriginal)
        }
    }
    return Ok(host)
  }
  // Explicit unconverted raw preparation callers keep their existing path.
  // A nominal preprepared Run cannot reach this branch: begin_prepared above
  // requires its actual configuration. No failure falls back into this path.
  let opened = open_checked_local_host(
    prepared,
    None,
    installed_contracts,
    values_body,
    1L,
    0L,
    0L,
    0L,
    fragment_body~,
    ordered_body~,
    retained_output~,
    provider_factory~,
    acquisition_ledger=Some(ledger),
    source_free_preparation=value.source_free_preparation,
  )
  // Capture provenance at the actual issuer, never from a caller-provided
  // graph, CID or merely equal Ledger. A second open cannot replace it.
  if opened is Some(host) {
    value.source_free_captured = Some(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
    )
  }
  Ok(opened)
}

///|
/// Stop new original operations and settle only controls whose actual child
/// cleanup has completed. Model Scope quiescence then precedes parent-holder
/// retirement. Pending children keep their same Run and reservation for retry.
pub fn quiesce_installed_managed_run(
  value : ClientInstalledManagedRun,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) && physical_equal(value, original) else {
    return Err(ForeignOriginal)
  }
  if value.source_free_opening || value.effect_operation_opening {
    return Err(CleanupPending)
  }
  if value.ledger is None {
    return Ok(())
  }
  if value.serialization_prefix is Some(prefix) && !prefix.released {
    return Err(CleanupPending)
  }
  for read in value.reads {
    if read is Some(read) && read.ledger is Some(_) {
      return Err(CleanupPending)
    }
  }
  for read in value.keyed_reads {
    if !read.retired {
      return Err(CleanupPending)
    }
  }
  for operation in value.effect_operations {
    if operation is Some(operation) && !operation.retired {
      return Err(CleanupPending)
    }
  }
  // Fence new work before releasing the original idle controls.
  value.effect_operation_closing = true
  // Every original child ACK precedes control retirement. Keep the spent
  // occurrence fence closed even if later Root retirement remains pending.
  if !value.effect_operations.is_empty() ||
    value.effect_operation_controls is Some(_) {
    if value.effect_operation_controls is Some(control) &&
      value.ledger is Some(ledger) {
      match @resources.settle_capacity(ledger, control.reservation) {
        Ok(_) => {
          control.coordinates.clear()
          value.effect_operation_controls = None
        }
        Err(issue) => return Err(Ledger(issue))
      }
    }
    value.effect_operations.clear()
  }
  Ok(())
}

///|
/// Managed retirement after all Source capture duties, actual Compute usage
/// report and the original logical stop. This does not acknowledge FD/backing
/// release, an uncertain operation, or another Run's remaining holdings.
pub fn retire_installed_managed_run(
  value : ClientInstalledManagedRun,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  match quiesce_installed_managed_run(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.ledger is None {
    return Ok(())
  }
  if value.preparation_retirement is Some(original) {
    return match original {
      PurePreparation(original) =>
        retire_preparation_owned_installed_run(value, original)
      EffectPlanPreparation(original) =>
        retire_preparation_owned_installed_run(value, original)
    }
  }
  // Use the original admission's complete cleanup path too. It retains an
  // early read bootstrap when later Scope construction did not return a view;
  // successful child cleanup cannot strand that same initialization token.
  guard value.preparation is Some(preparation) else { return Err(Retired) }
  let cleaned = match preparation {
    PureManaged(admission, _) =>
      @resources.cleanup_prepared_run_admission(admission)
    PlannedEffectManaged(admission, _) =>
      @resources.cleanup_prepared_run_admission(admission)
    PreparationContentManaged(admission, _) =>
      @resources.cleanup_prepared_run_admission(admission)
  }
  match cleaned {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  value.ledger = None
  // The original cleanup proved every borrower stopped. Retained Run handles
  // keep identity and terminal state, not the heavy immutable preparation.
  value.preparation = None
  value.reads.clear()
  value.keyed_reads.clear()
  value.content = NoContent
  value.serialization_prefix = None
  value.source_free_preparation = None
  value.captured_preparation = None
  value.source_free_captured = None
  Ok(())
}

///|
/// Project publication facts from the same nominal preparation already used by
/// quote and execution. A same-shaped but foreign checked Program is not its
/// owner, and cannot borrow its closed-row or schema proofs.
pub fn prepared_installed_managed_publication_limits(
  value : ClientInstalledManagedSourceFreePreparation,
  prepared : @publication_host.PreparedClientProgram,
  max_payload_bytes : Int,
) -> @publication_host.PublicationOutputExportLimits? {
  guard value.owner is Pure(original) && physical_equal(original, prepared) else {
    return None
  }
  client_node_publication_limits(
    prepared,
    max_payload_bytes,
    value.capacity_plan,
  )
}

///|
/// Borrow the publication projection through the live installed owner. The
/// staging preparation may already have moved into this owner; never recreate
/// it or introduce a second strong cache merely to read its checked facts.
pub fn installed_managed_publication_limits(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  max_payload_bytes : Int,
) -> @publication_host.PublicationOutputExportLimits? {
  guard require_installed_managed_run(value) is Ok(_) else { return None }
  if value.captured_preparation is Some(plan) {
    if !physical_equal(plan.prepared, prepared) {
      return None
    }
    if plan.whole_input is Some(_) {
      guard plan.capacity_plan.graph is Some(graph) &&
        physical_equal(graph, plan.graph) else {
        return None
      }
      return client_node_publication_limits_original(
        max_payload_bytes,
        plan.capacity_plan,
      )
    }
    return client_node_publication_limits(
      prepared,
      max_payload_bytes,
      plan.capacity_plan,
    )
  }
  guard value.source_free_preparation is Some(original) else { return None }
  prepared_installed_managed_publication_limits(
    original, prepared, max_payload_bytes,
  )
}

///|
/// The exact DAG issued once by this original managed Run. No public adapter
/// can bind an arbitrary DAG using equal graph bytes or Ledger amounts.
pub fn installed_managed_publication_dag(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[@strategy.CapturedDAG, ClientInstalledManagedRunIssue] {
  match check_installed_managed_run(value, prepared, value.request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard !value.source_free_opening &&
    value.source_free_captured is Some(captured) &&
    value.ledger is Some(ledger) &&
    physical_equal(ledger, @strategy.captured_dag_ledger(captured)) else {
    return Err(Unsupported)
  }
  Ok(captured)
}
