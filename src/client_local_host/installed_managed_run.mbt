///|
/// A same-Host consumer of the selected Resource admission, not another
/// capacity issuer. Any Source reads and the managed DAG borrow this one Ledger.
struct ClientInstalledManagedRun {
  mut original : ClientInstalledManagedRun?
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientProgram,
  ]
  prepared : @publication_host.PreparedClientProgram
  request : @publication_host.ClientRequestIdentity
  mut ledger : @resources.Ledger?
  reads : Array[ClientInstalledSourceRead?]
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
}

///|
fn installed_managed_run_purpose_supported(
  prepared : @publication_host.PreparedClientProgram,
) -> Bool {
  let graph = @publication_host.prepared_client_graph(prepared)
  let captured = @strategy.graph_captured_prefix(graph)
  (
    captured == 2 ||
    (captured == 0 && @strategy.graph_source_free_inputs_complete(graph))
  ) &&
  @publication_host.prepared_client_composed_infer_occurrences(prepared)
  is Some(infers) &&
  infers.is_empty() &&
  @publication_host.prepared_client_serialization_occurrences(prepared).is_empty()
}

///|
/// Quote source-free Local work from the same generated sequences, receiving
/// ports and retained-output envelope as the existing installed Local Host.
/// This is demand only; it neither constructs a Ledger nor supplies admission.
fn source_free_installed_managed_limits(
  prepared : @publication_host.PreparedClientProgram,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.LedgerLimits? {
  let graph = @publication_host.prepared_client_graph(prepared)
  if !installed_managed_run_purpose_supported(prepared) ||
    @strategy.graph_captured_prefix(graph) != 0 ||
    !@strategy.graph_source_free_inputs_complete(graph) {
    return None
  }
  let task_count = @strategy.graph_task_count(graph)
  if task_count < 1 || task_count > 32 {
    return None
  }
  guard prepare_client_local_sequences(
      prepared, registry_body, values_body, fragment_body, ordered_body,
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
      max_rows=@publication_host.prepared_client_values_max_rows(prepared),
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
  if !installed_managed_run_purpose_supported(prepared) {
    return Err(Unsupported)
  }
  if @strategy.graph_captured_prefix(
      @publication_host.prepared_client_graph(prepared),
    ) ==
    0 {
    if !declarations.is_empty() ||
      !transport_bytes.is_empty() ||
      !transport_execution_bytes.is_empty() {
      return Err(Unsupported)
    }
    guard source_free_installed_managed_limits(
        prepared, registry_body, values_body, fragment_body, ordered_body,
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
  if declarations.length() != 2 {
    return Err(Unsupported)
  }
  let capacities = []
  for index in 0..<2 {
    guard prepare_local_query_requirement(
        prepared, index, 0, registry_body, values_body, fragment_body, ordered_body,
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
      Pure(prepared),
      capacities,
      transport_bytes,
      transport_execution_bytes,
      registry_body,
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
  match @resources.check_node_managed_run_preparation(admission, prepared) {
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
  let value : ClientInstalledManagedRun = {
    original: None,
    admission,
    prepared,
    request,
    ledger: Some(ledger),
    reads: Array::make(
      @strategy.graph_captured_prefix(
        @publication_host.prepared_client_graph(prepared),
      ),
      None,
    ),
  }
  value.original = Some(value)
  Ok(value)
}

///|
fn require_installed_managed_run(
  value : ClientInstalledManagedRun,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) && physical_equal(value, original) else {
    return Err(ForeignOriginal)
  }
  guard value.ledger is Some(ledger) else { return Err(Retired) }
  match
    @resources.check_node_managed_run_preparation(
      value.admission,
      value.prepared,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  match @resources.check_node_managed_run_admission(value.admission, ledger) {
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
pub fn check_installed_managed_run(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if !physical_equal(value.prepared, prepared) || value.request != request {
    return Err(ForeignOriginal)
  }
  require_installed_managed_run(value).map(_ => ())
}

///|
/// Both reads keep the same admitted parent; this is not a second import,
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
    owner: Some(Pure(value.prepared)),
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
  let ledger = match require_installed_managed_run(value) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  let required = if value.reads.is_empty() {
    if !capacities.is_empty() ||
      !transport_bytes.is_empty() ||
      !transport_execution_bytes.is_empty() {
      return Err(Unsupported)
    }
    source_free_installed_managed_limits(
      prepared, registry_body, values_body, fragment_body, ordered_body,
    )
  } else {
    multi_captured_installed_limits_owned(
      Pure(prepared),
      capacities,
      transport_bytes,
      transport_execution_bytes,
      registry_body,
      values_body,
      fragment_body,
      ordered_body,
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
  match @resources.report_node_managed_run_admission(value.admission) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  match @resources.stop_node_managed_run_admission(value.admission) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  value.ledger = None
  value.reads.clear()
  Ok(())
}
