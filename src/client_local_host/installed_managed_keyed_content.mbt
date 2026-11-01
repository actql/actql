///|
// A checked preparation inside the existing Local/Resource owner. Its limits
// are demand; only the separate original Node Content admission supplies the
// ordinary platform service. Neither this record nor its DATA projection is
// an issuer, a permission or a second Ledger.
struct ClientInstalledManagedKeyedPreparation {
  prepared : @publication_host.PreparedClientProgram
  keyed : @publication_host.ClientKeyedAcquisition
  declaration : @row_source_host.RowDeclaration
  row_limits : @row_source_host.RowKeyedLimits
  limits : @resources.LedgerLimits
  direct : ClientInstalledCaptureCapacity
  installed_contracts : ClientInstalledSequenceContracts
  max_requests : Int
  direct_stage : Int
  direct_input : Int
  direct_transfer_bytes : Int64
  direct_execution_bytes : Int64
  fragment_selected : Bool
  ordered_selected : Bool
  serialization_task : Int
  serialization_step : Int
  prefix : ClientInstalledKeyedPrefixPreparation?
}

///|
// Original generated prefix and bounded provider retained by this existing
// Content Plan. These are constructor outputs, not another Run/cleanup owner.
priv struct ClientInstalledKeyedPrefixPreparation {
  sequence : @execution.GeneratedSequence
  provider : @local.ManagedProvider
  capacity : @execution.ExecutionCapacity
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
}

///|
pub fn prepare_installed_managed_keyed_content(
  prepared : @publication_host.PreparedClientProgram,
  direct : ClientInstalledCaptureCapacity,
  keyed : @publication_host.ClientKeyedAcquisition,
  declaration : @row_source_host.RowDeclaration,
  row_limits : @row_source_host.RowKeyedLimits,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  max_bytes : Int,
  max_work : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  task : Int,
  step : Int,
  prefix_retained_bytes : Int64,
  prefix_execution_bytes : Int64,
) -> Result[
  ClientInstalledManagedKeyedPreparation,
  ClientInstalledManagedRunIssue,
] {
  prepare_installed_managed_keyed_content_owned(
    prepared,
    direct,
    keyed,
    declaration,
    row_limits,
    transport_bytes,
    transport_execution_bytes,
    max_bytes,
    max_work,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    task,
    step,
    prefix_retained_bytes,
    prefix_execution_bytes,
    None,
    None,
  )
}

///|
fn prepare_installed_managed_keyed_content_owned(
  prepared : @publication_host.PreparedClientProgram,
  direct : ClientInstalledCaptureCapacity,
  keyed : @publication_host.ClientKeyedAcquisition,
  declaration : @row_source_host.RowDeclaration,
  row_limits : @row_source_host.RowKeyedLimits,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  max_bytes : Int,
  max_work : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  task : Int,
  step : Int,
  prefix_retained_bytes : Int64,
  prefix_execution_bytes : Int64,
  prefix : ClientInstalledKeyedPrefixPreparation?,
  original_requirement : @planning.QueryRequirement?,
) -> Result[
  ClientInstalledManagedKeyedPreparation,
  ClientInstalledManagedRunIssue,
] {
  if !direct.original_input || direct.provider is Some(_) {
    return Err(Unsupported)
  }
  // This first connection covers the existing keyed Content/serialization
  // path, not a later Model or Effect purpose on the same authored Program.
  guard @publication_host.prepared_client_composed_infer_occurrences(prepared)
    is Some(infers) &&
    infers.is_empty() else {
    return Err(Unsupported)
  }
  let capacity = match
    @row_source_host.prepare_keyed_row_capacity(
      @publication_host.client_keyed_acquisition_owner(keyed),
      @publication_host.client_keyed_acquisition_facts(keyed),
      declaration,
      row_limits,
    ) {
    Err(_) => return Err(Unsupported)
    Ok(value) => value
  }
  guard keyed_captured_local_installed_requirements(
      prepared,
      direct,
      keyed,
      capacity,
      transport_bytes,
      transport_execution_bytes,
      max_bytes,
      max_work,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      serialization=Some(
        (task, step, prefix_retained_bytes, prefix_execution_bytes),
      ),
      captured_content=true,
      original_requirement~,
    )
    is Some((limits, direct_stage, direct_input, requests)) &&
    requests >= 0L &&
    requests <= 2147483647L else {
    return Err(Unsupported)
  }
  Ok({
    prepared,
    keyed,
    declaration,
    row_limits,
    limits,
    direct,
    installed_contracts,
    max_requests: requests.to_int(),
    direct_stage,
    direct_input,
    direct_transfer_bytes: transport_bytes[0],
    direct_execution_bytes: transport_execution_bytes[0],
    fragment_selected: fragment_body is Some(_),
    ordered_selected: ordered_body is Some(_),
    serialization_task: task,
    serialization_step: step,
    prefix,
  })
}

///|
fn installed_managed_keyed_content_limits(
  value : ClientInstalledManagedKeyedPreparation,
  prepared : @publication_host.PreparedClientProgram,
  direct : ClientInstalledCaptureCapacity,
  transport_bytes : Int64,
  execution_bytes : Int64,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.LedgerLimits? {
  if !physical_equal(value.prepared, prepared) ||
    !physical_equal(value.direct, direct) ||
    !physical_equal(value.installed_contracts, installed_contracts) ||
    value.direct_transfer_bytes != transport_bytes ||
    value.direct_execution_bytes != execution_bytes ||
    values_body != installed_contracts.original.values_body ||
    (
      value.fragment_selected &&
      fragment_body != installed_contracts.original.fragment_body
    ) ||
    (!value.fragment_selected && fragment_body is Some(_)) ||
    (
      value.ordered_selected &&
      ordered_body != installed_contracts.original.ordered_body
    ) ||
    (!value.ordered_selected && ordered_body is Some(_)) {
    return None
  }
  // This is the exact immutable quote context completed by the constructor.
  // A foreign/restored/changed context must run that constructor for its own
  // Plan; it cannot replace a completed Run's selected original requirements.
  Some(value.limits)
}

///|
/// DATA only, for the actual ordinary Root's managed limit declaration.
pub fn installed_managed_keyed_content_requirements(
  value : ClientInstalledManagedKeyedPreparation,
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
pub fn check_installed_managed_keyed_content_preparation(
  value : ClientInstalledManagedKeyedPreparation,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if physical_equal(value.prepared, prepared) {
    Ok(())
  } else {
    Err(ForeignOriginal)
  }
}

///|
struct ClientInstalledKeyedSourceRead {
  mut original : ClientInstalledKeyedSourceRead?
  mut parent : ClientInstalledManagedRun?
  mut selected : ClientInstalledManagedKeyedPreparation?
  request : @publication_host.ClientKeyedRequest?
  mut acquisition : @row_source_host.RowKeyedAcquisition?
  mut run : @row_source_host.RowRun?
  mut started : Bool
  mut retired : Bool
}

///|
pub fn begin_installed_managed_keyed_source_read(
  value : ClientInstalledManagedRun,
  keyed : @publication_host.ClientKeyedAcquisition,
  request : @publication_host.ClientKeyedRequest,
  declaration : @row_source_host.RowDeclaration,
) -> Result[ClientInstalledKeyedSourceRead, ClientInstalledSourceReadIssue] {
  match require_installed_managed_run(value) {
    Err(issue) => return Err(ManagedRun(issue))
    Ok(_) => ()
  }
  guard value.content is KeyedContent(selected, _) &&
    physical_equal(selected.keyed, keyed) &&
    physical_equal(selected.declaration, declaration) &&
    @publication_host.client_keyed_request_matches_acquisition(request, keyed) else {
    return Err(ForeignOriginal)
  }
  if value.keyed_reads.length() >= selected.max_requests {
    return Err(ManagedRun(InsufficientCapacity))
  }
  for previous in value.keyed_reads {
    if previous.request is Some(original) && physical_equal(original, request) {
      return Err(AlreadyBound)
    }
  }
  guard @publication_host.client_keyed_request_value(request, keyed)
    is Some(input) else {
    return Err(ForeignOriginal)
  }
  let acquisition = match
    @row_source_host.prepare_keyed_row_acquisition(
      @publication_host.client_keyed_acquisition_owner(keyed),
      @publication_host.client_keyed_acquisition_facts(keyed),
      input,
      declaration,
      selected.row_limits,
      input_available=Some(() => {
        @publication_host.client_keyed_request_matches_acquisition(
          request, keyed,
        ) &&
        require_installed_managed_run(value) is Ok(_)
      }),
    ) {
    Err(issue) => return Err(Acquisition(issue))
    Ok(value) => value
  }
  // Recheck after the existing request/current preparation before publishing
  // this child. Its parent and cumulative request slot are never replaced.
  match require_installed_managed_run(value) {
    Err(issue) => return Err(ManagedRun(issue))
    Ok(_) => ()
  }
  let read : ClientInstalledKeyedSourceRead = {
    original: None,
    parent: Some(value),
    selected: Some(selected),
    request: Some(request),
    acquisition: Some(acquisition),
    run: None,
    started: false,
    retired: false,
  }
  read.original = Some(read)
  value.keyed_reads.push(read)
  Ok(read)
}

///|
fn require_installed_keyed_source_read(
  value : ClientInstalledKeyedSourceRead,
) -> Result[@resources.Ledger, ClientInstalledSourceReadIssue] {
  guard value.original is Some(original) && physical_equal(value, original) else {
    return Err(ForeignOriginal)
  }
  if value.retired {
    return Err(Retired)
  }
  guard value.parent is Some(parent) &&
    value.selected is Some(selected) &&
    parent.content is KeyedContent(original, _) &&
    physical_equal(original, selected) &&
    parent.keyed_reads.any(read => physical_equal(read, value)) else {
    return Err(ForeignOriginal)
  }
  require_installed_managed_run(parent).map_err(issue => ManagedRun(issue))
}

///|
pub fn check_installed_keyed_source_read_current(
  value : ClientInstalledKeyedSourceRead,
) -> Result[Unit, ClientInstalledSourceReadIssue] {
  require_installed_keyed_source_read(value).map(_ => ())
}

///|
pub fn installed_keyed_source_read_acquisition(
  value : ClientInstalledKeyedSourceRead,
) -> Result[
  @row_source_host.RowKeyedAcquisition,
  ClientInstalledSourceReadIssue,
] {
  match require_installed_keyed_source_read(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match value.acquisition {
    Some(acquisition) => Ok(acquisition)
    None => Err(Retired)
  }
}

///|
pub fn check_installed_keyed_source_read_ledger(
  value : ClientInstalledKeyedSourceRead,
  expected : @resources.Ledger,
) -> Result[Unit, ClientInstalledSourceReadIssue] {
  match require_installed_keyed_source_read(value) {
    Err(issue) => Err(issue)
    Ok(original) =>
      if physical_equal(original, expected) {
        Ok(())
      } else {
        Err(ForeignOriginal)
      }
  }
}

///|
pub fn start_installed_keyed_source_read_rows(
  value : ClientInstalledKeyedSourceRead,
  acquisition : @row_source_host.RowKeyedAcquisition,
  nonce : String,
  original_stop : (@row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  cleanup_confirmed : (@row_source_host.RowAttempt) -> Bool,
) -> Result[@row_source_host.RowRun, ClientInstalledSourceReadIssue] {
  let ledger = match require_installed_keyed_source_read(value) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard value.acquisition is Some(original) &&
    physical_equal(original, acquisition) else {
    return Err(ForeignOriginal)
  }
  if value.started {
    return Err(AlreadyStarted)
  }
  value.started = true
  match
    @row_source_host.start_accounted_keyed_row_acquisition(
      acquisition, nonce, original_stop, ledger, transfer_bytes, execution_bytes,
      cleanup_confirmed,
    ) {
    Err(issue) => Err(Acquisition(issue))
    Ok(run) => {
      value.run = Some(run)
      Ok(run)
    }
  }
}

///|
pub fn retire_installed_keyed_source_read(
  value : ClientInstalledKeyedSourceRead,
) -> Result[Unit, ClientInstalledSourceReadIssue] {
  guard value.original is Some(original) && physical_equal(value, original) else {
    return Err(ForeignOriginal)
  }
  if value.retired {
    return Ok(())
  }
  if value.run is Some(run) {
    match @row_source_host.close_accounted_row_run(run) {
      Err(issue) => return Err(Acquisition(issue))
      Ok(_) => ()
    }
    match @row_source_host.cleanup_row_capture(run) {
      Err(issue) => return Err(Acquisition(issue))
      Ok(false) => return Err(CleanupPending)
      Ok(true) => ()
    }
  }
  value.run = None
  value.acquisition = None
  value.selected = None
  value.parent = None
  value.retired = true
  // Keep the original request identity in the bounded parent history until
  // parent retirement; a closed child is not a fresh request allowance.
  Ok(())
}

///|
pub fn installed_keyed_row_limits(
  max_page_bytes : Int,
  max_text_bytes : Int,
  max_work : Int,
) -> @row_source_host.RowKeyedLimits {
  {
    page: {
      max_bytes: max_page_bytes,
      max_nodes: 10000,
      max_depth: 100,
      max_rows: 100,
    },
    retention: { max_nodes: 100000, max_depth: 100, max_work, max_text_bytes, },
    request: {
      max_work,
      max_pairs: 100,
      values: { max_nodes: 10000, max_depth: 100, max_text_bytes, },
    },
    wire: {
      max_columns: 100,
      max_order_work: max_work,
      max_bytes: max_text_bytes,
      max_nodes: 100000,
      max_depth: 100,
    },
  }
}

///|
/// Called after the existing Run current/post-callback fence. Only original
/// references and immutable scalar DATA are read below: no sequence/provider
/// constructor or external callback can justify another current observation.
fn prepare_retained_installed_keyed_content_ledger(
  run : ClientInstalledManagedRun,
  selected : ClientInstalledManagedKeyedPreparation,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  ledger : @resources.Ledger,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard run.content is KeyedContent(original, _) &&
    physical_equal(original, selected) &&
    run.ledger is Some(original_ledger) &&
    physical_equal(original_ledger, ledger) &&
    capacities.length() == 1 &&
    transport_bytes.length() == 1 &&
    transport_execution_bytes.length() == 1 &&
    run.reads.length() == 1 else {
    return Err(ForeignOriginal)
  }
  let prepared = match run.preparation {
    Some(PreparationContentManaged(_, prepared)) => prepared
    _ => return Err(ForeignOriginal)
  }
  guard installed_managed_keyed_content_limits(
      selected,
      prepared,
      capacities[0],
      transport_bytes[0],
      transport_execution_bytes[0],
      contracts,
      values_body,
      fragment_body,
      ordered_body,
    )
    is Some(required) else {
    return Err(ForeignOriginal)
  }
  if !installed_effect_limits_fit(required, @resources.ledger_limits(ledger)) {
    return Err(InsufficientCapacity)
  }
  guard run.reads.get(selected.direct_stage) is Some(Some(read)) &&
    read.acquisition is Some(acquisition) &&
    selected.direct.acquisition is Some(original) &&
    physical_equal(original, acquisition) &&
    read.requirement is Some(requirement) &&
    physical_equal(requirement, selected.direct.requirement) else {
    return Err(ForeignOriginal)
  }
  Ok(ledger)
}
