///|
/// A same-Host consumer of the selected Resource admission, not another
/// capacity issuer. Any Source reads and the managed DAG borrow this one Ledger.
priv enum ClientInstalledManagedRunOriginal {
  PureManaged(
    @resources.NodeManagedRunAdmission[@publication_host.PreparedClientProgram],
    @publication_host.PreparedClientProgram
  )
  EffectManaged(
    @resources.NodeManagedRunAdmission[
      @publication_host.PreparedClientEffectComputation,
    ],
    @publication_host.PreparedClientEffectComputation
  )
  ContentManaged(
    @resources.NodeManagedRunAdmission[@publication_host.PreparedClientProgram],
    @publication_host.PreparedClientProgram
  )
}

///|
struct ClientInstalledManagedRun {
  mut original : ClientInstalledManagedRun?
  preparation : ClientInstalledManagedRunOriginal
  request : @publication_host.ClientRequestIdentity
  mut ledger : @resources.Ledger?
  reads : Array[ClientInstalledSourceRead?]
  mut keyed : ClientInstalledManagedKeyedPreparation?
  keyed_reads : Array[ClientInstalledKeyedSourceRead]
}

///|
pub(all) enum ClientInstalledManagedRunIssue {
  ForeignOriginal
  Unsupported
  AlreadyBound
  Retired
  CleanupPending
  InsufficientCapacity
  Resource(@resources.ImportedChildLedgerIssue)
  Ledger(@resources.LedgerIssue)
  ModelRead(@publication_host.ClientModelReadPreparationIssue)
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
) -> Bool {
  let graph = installed_managed_owner_graph(owner)
  let captured = @strategy.graph_captured_prefix(graph)
  let boundary_count = match owner {
    Pure(prepared) =>
      @publication_host.prepared_client_composed_infer_occurrences(prepared).map(value => {
          value.length()
        },
      )
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
  let serialized = match owner {
    Pure(prepared) =>
      @publication_host.prepared_client_serialization_occurrences(prepared)
    Effect(prepared) =>
      @publication_host.prepared_client_effect_serialization_occurrences(
        prepared,
      )
  }
  (
    (captured > 0 && (!mock_model || captured == 2)) ||
    (captured == 0 && @strategy.graph_source_free_inputs_complete(graph))
  ) &&
  boundary_count is Some(count) &&
  count == (if mock_model { 1 } else { 0 }) &&
  serialized.is_empty()
}

///|
/// Quote source-free Local work from the same generated sequences, receiving
/// ports and retained-output envelope as the existing installed Local Host.
/// This is demand only; it neither constructs a Ledger nor supplies admission.
fn source_free_installed_managed_limits_owned(
  owner : ClientLocalSequenceOwner,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  mock_model : Bool,
) -> @resources.LedgerLimits? {
  let graph = installed_managed_owner_graph(owner)
  if !installed_managed_owner_shape_supported(owner, mock_model) ||
    @strategy.graph_captured_prefix(graph) != 0 ||
    !@strategy.graph_source_free_inputs_complete(graph) {
    return None
  }
  let task_count = @strategy.graph_task_count(graph)
  if task_count < 1 || task_count > 32 {
    return None
  }
  guard prepare_client_local_sequences_owned(
      owner, registry_body, values_body, fragment_body, ordered_body,
    )
    is Some(sequences) &&
    sequences.length() == task_count else {
    return None
  }
  let inputs = Array::make(task_count, 0)
  for index in 0..<@strategy.graph_data_count(graph) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return None
    }
    let consumer = @strategy.data_edge_consumer(edge)
    if consumer < 0 || consumer >= task_count {
      return None
    }
    inputs[consumer] += 1
  }
  guard client_local_sequence_capacity(
      sequences,
      task_count,
      retained_inputs=Some(inputs),
      max_rows=match owner {
        Pure(prepared) =>
          @publication_host.prepared_client_values_max_rows(prepared)
        Effect(_) =>
          @publication_host.client_standard_values_sequence_limits().max_rows
      },
    )
    is Some((limits, _, _)) else {
    return None
  }
  Some(limits)
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
  registry_body : String,
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
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    false,
  )
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
  registry_body : String,
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
    registry_body,
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
  registry_body : String,
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
    guard source_free_installed_managed_limits_owned(
        owner, registry_body, values_body, fragment_body, ordered_body, mock_model,
      )
      is Some(limits) else {
      return Err(Unsupported)
    }
    return Ok([
      limits.planning_work.to_int64(),
      limits.attempts.to_int64(),
      limits.holdings.to_int64(),
      limits.transfer_bytes,
      limits.retained_bytes,
      limits.execution_bytes,
    ])
  }
  let captured = @strategy.graph_captured_prefix(
    installed_managed_owner_graph(owner),
  )
  if declarations.length() != captured {
    return Err(Unsupported)
  }
  let capacities = []
  for index in 0..<captured {
    guard prepare_local_query_requirement_owned(
        owner, index, 0, registry_body, values_body, fragment_body, ordered_body,
      )
      is Ok(requirement) &&
      @row_source_host.prepare_row_acquisition(
        declarations[index],
        requirement,
        query_contract_body,
        evidence_contract_body,
      )
      is Ok(acquisition) &&
      installed_row_capture_capacity(acquisition) is Some(capacity) else {
      return Err(Unsupported)
    }
    capacities.push(capacity)
  }
  guard multi_captured_installed_limits_owned(
      owner, capacities, transport_bytes, transport_execution_bytes, registry_body,
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
    PureManaged(admission, prepared),
    request,
    ledger,
  )
}

///|
fn installed_managed_run_owner(
  value : ClientInstalledManagedRun,
) -> ClientLocalSequenceOwner {
  match value.preparation {
    PureManaged(_, prepared) => Pure(prepared)
    EffectManaged(_, prepared) => Effect(prepared)
    ContentManaged(_, prepared) => Pure(prepared)
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
    preparation,
    request,
    ledger: Some(ledger),
    reads: Array::make(
      @strategy.graph_captured_prefix(
        installed_managed_owner_graph(
          match preparation {
            PureManaged(_, prepared) => Pure(prepared)
            EffectManaged(_, prepared) => Effect(prepared)
            ContentManaged(_, prepared) => Pure(prepared)
          },
        ),
      ),
      None,
    ),
    keyed: None,
    keyed_reads: [],
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
  let checked = match value.preparation {
    PureManaged(admission, prepared) =>
      check_installed_managed_run_admission(admission, prepared, ledger)
    EffectManaged(admission, prepared) =>
      check_installed_managed_run_admission(admission, prepared, ledger)
    ContentManaged(admission, prepared) =>
      match
        @resources.check_node_local_content_run_preparation(admission, prepared) {
        Err(issue) => Err(issue)
        Ok(_) =>
          check_installed_managed_run_admission(admission, prepared, ledger)
      }
  }
  match checked {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  // Import currentness is not permission to mutate a parked inventory. Keep
  // the same fence as the original Source-only path for every shared borrow.
  match @resources.check_original_resources_mutable(ledger) {
    Err(issue) => Err(Ledger(issue))
    Ok(_) => Ok(ledger)
  }
}

///|
fn[P] check_installed_managed_run_admission(
  admission : @resources.NodeManagedRunAdmission[P],
  prepared : P,
  ledger : @resources.Ledger,
) -> Result[Unit, @resources.ImportedChildLedgerIssue] {
  match @resources.check_node_managed_run_preparation(admission, prepared) {
    Err(issue) => Err(issue)
    Ok(_) => @resources.check_node_managed_run_admission(admission, ledger)
  }
}

///|
pub fn check_installed_managed_run(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  let selected = match value.preparation {
    PureManaged(_, prepared) => Some(prepared)
    ContentManaged(_, prepared) => Some(prepared)
    EffectManaged(_, _) => None
  }
  guard selected is Some(original) &&
    physical_equal(original, prepared) &&
    value.request == request else {
    return Err(ForeignOriginal)
  }
  require_installed_managed_run(value).map(_ => ())
}

///|
/// Every read keeps the same admitted parent; this is not a second import,
/// a Source-only child conversion, or a getter for a public bare Ledger.
pub fn begin_installed_managed_run_source_read(
  value : ClientInstalledManagedRun,
  occurrence : Int,
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
  let read : ClientInstalledSourceRead = {
    original: None,
    child: None,
    managed_run: Some((value, occurrence)),
    ledger: Some(ledger),
    owner: Some(installed_managed_run_owner(value)),
    declaration: None,
    requirement: None,
    acquisition: None,
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
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  match check_installed_managed_run(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  prepare_installed_managed_run_ledger_owned(
    value, capacities, transport_bytes, transport_execution_bytes, registry_body,
    values_body, fragment_body, ordered_body,
  )
}

///|
fn prepare_installed_managed_run_ledger_owned(
  value : ClientInstalledManagedRun,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  let ledger = match require_installed_managed_run(value) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  let owner = installed_managed_run_owner(value)
  if capacities.length() != value.reads.length() ||
    transport_bytes.length() != capacities.length() ||
    transport_execution_bytes.length() != capacities.length() {
    return Err(Unsupported)
  }
  let required = if value.keyed is Some(keyed) {
    guard capacities.length() == 1 else { return Err(Unsupported) }
    guard owner is Pure(prepared) else { return Err(Unsupported) }
    installed_managed_keyed_content_limits(
      keyed, prepared, capacities[0], transport_bytes[0], transport_execution_bytes[0],
      registry_body, values_body, fragment_body, ordered_body,
    )
  } else if value.reads.is_empty() {
    if !capacities.is_empty() ||
      !transport_bytes.is_empty() ||
      !transport_execution_bytes.is_empty() {
      return Err(Unsupported)
    }
    source_free_installed_managed_limits_owned(
      owner,
      registry_body,
      values_body,
      fragment_body,
      ordered_body,
      installed_managed_owner_shape_supported(owner, true),
    )
  } else {
    multi_captured_installed_limits_owned(
      owner, capacities, transport_bytes, transport_execution_bytes, registry_body,
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
    if !capacities[index].original_input ||
      capacities[index].provider is Some(_) {
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
  registry_body : String,
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
  if !value.reads.is_empty() {
    return Err(Unsupported)
  }
  let ledger = match
    prepare_installed_managed_run_ledger(
      value,
      prepared,
      request,
      [],
      [],
      [],
      registry_body,
      values_body,
      fragment_body,
      ordered_body,
    ) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  Ok(
    open_checked_local_host(
      prepared,
      None,
      registry_body,
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
    ),
  )
}

///|
/// Managed retirement after all Source capture duties, actual Compute usage
/// report and the original logical stop. This does not acknowledge FD/backing
/// release, an uncertain operation, or another Run's remaining holdings.
pub fn retire_installed_managed_run(
  value : ClientInstalledManagedRun,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) && physical_equal(value, original) else {
    return Err(ForeignOriginal)
  }
  if value.ledger is None {
    return Ok(())
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
  // Use the original admission's complete cleanup path too. It retains an
  // early read bootstrap when later Scope construction did not return a view;
  // successful child cleanup cannot strand that same initialization token.
  let cleaned = match value.preparation {
    PureManaged(admission, _) =>
      @resources.cleanup_node_managed_run_admission(admission)
    EffectManaged(admission, _) =>
      @resources.cleanup_node_managed_run_admission(admission)
    ContentManaged(admission, _) =>
      @resources.cleanup_node_managed_run_admission(admission)
  }
  match cleaned {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  value.ledger = None
  value.reads.clear()
  value.keyed_reads.clear()
  value.keyed = None
  Ok(())
}
