///|
// Fixed consumer-interface proposal; publication does not adopt a byte policy.
// Before issuance, the original owner must fund this record, the
// additional ModelState reference, validation and all simultaneous backend
// allocations. Byte arguments below are reviewed grants, not census estimates.
struct OriginalModelStartup {
  rows : @relation.PreparedInferRows
  scope : @publication_host.ClientInferCallScope?
  ledger : @resources.Ledger
  capacity : @resources.CapacityReservation
  retained_bytes : Int64
  execution_bytes : Int64
  shared_mock : OriginalMockPurpose?
  mut used : Bool
}

///|
/// Initial backing for the fresh original startup and Model execution. At
/// this boundary the seven maps and all vectors are empty. Every eligible
/// slot reserves separately before it can construct a request or response.
pub fn original_fresh_model_start_construction_capacity() -> @relation.ExecutionCapacity? {
  guard @shape.collection_construction_extent({
      // Original seal/purpose, row use, Model state/progress, common
      // control/reader/session/token and the result/option carriers.
      records: 24L,
      record_references: 96L,
      record_words: 48L,
      // Six reference vectors and seven empty Map constructor inputs.
      reference_arrays: 13L,
      reference_items: 0L,
      scalar_arrays: 1L,
      scalar_items: 0L,
      maps: 7L,
      map_entries: 0L,
    })
    is Some(units) &&
    @relation.preparation_representation_cost({
      record_headers: units.record_headers,
      reference_slots: units.reference_slots,
      scalar_words: units.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) else {
    return None
  }
  @relation.execution_capacity(bytes, bytes)
}

///|
// The consuming owner obtains scope/rows from the current bind_run execution
// after its Identity scan. This issuer retains no generic-origin shortcut
// and accepts no independently reissued Ledger or quantity aggregate.
pub fn prepare_original_model_startup(
  read : @publication_host.ClientModelReadPreparation,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  scope : @publication_host.ClientInferCallScope,
  rows : @relation.PreparedInferRows,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  OriginalModelStartup,
  @publication_host.ClientModelInputCapacityIssue,
] {
  if retained_bytes <= 0L || execution_bytes < 0L {
    return Err(Read(Resource(@resources.Resource(@resources.InvalidCharge))))
  }
  let (ledger, capacity) = match
    @publication_host.handoff_client_model_read_input_capacity(
      read, compiled, definition, plan, scope, rows, retained_bytes, execution_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    rows,
    scope: Some(scope),
    ledger,
    capacity,
    retained_bytes,
    execution_bytes,
    shared_mock: None,
    used: false,
  })
}

///|
/// Continue the one-shot early consumer through the same original input guard
/// and Ledger. This does not issue dispatch permission or release read custody.
pub fn prepare_original_model_consumer_startup(
  consumer : @publication_host.ClientModelReadConsumer,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  scope : @publication_host.ClientInferCallScope,
  rows : @relation.PreparedInferRows,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  OriginalModelStartup,
  @publication_host.ClientModelInputCapacityIssue,
] {
  if retained_bytes <= 0L || execution_bytes < 0L {
    return Err(Read(Resource(@resources.Resource(@resources.InvalidCharge))))
  }
  let (ledger, capacity) = match
    @publication_host.handoff_client_model_read_consumer_input_capacity(
      consumer, compiled, definition, plan, scope, rows, retained_bytes, execution_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    rows,
    scope: Some(scope),
    ledger,
    capacity,
    retained_bytes,
    execution_bytes,
    shared_mock: None,
    used: false,
  })
}

///|
/// Start only from the original issuer's seal. No Ledger/token projection or
/// second begin state machine is exposed. Refusal leaves the seal with its
/// issuing owner; success transfers settlement to existing Model cleanup.
pub fn start_original_model_execution(
  startup : OriginalModelStartup,
  rows : @relation.PreparedInferRows,
  provider : ModelProvider,
  fixed_request_cid : String,
  limits : ModelExecutionLimits,
  call_scope : @publication_host.ClientInferCallScope,
  dispatch_admission? : @publication_host.ClientInferDispatchAdmission? = None,
  quantity_capacity? : ModelQuantityCapacity? = None,
  physical_preflight? : ModelPhysicalPreflight? = None,
  egress_admission? : @publication_host.ClientInferEgressAdmission? = None,
  durable_calls? : Bool = false,
  send_mask? : Array[Bool]? = None,
) -> Result[ModelExecution, ModelExecutionIssue] {
  start_model_owned(
    rows,
    Provider(provider),
    fixed_request_cid,
    limits,
    Some(call_scope),
    dispatch_admission~,
    quantity_capacity~,
    physical_preflight~,
    egress_admission~,
    durable_calls~,
    send_mask~,
    original_startup=Some(startup),
  )
}

///|
/// Called by the original input cleanup path, never by a cancellation request
/// or a failed start alone. Core checks retirement of the exact sealed rows;
/// no caller boolean is accepted as cleanup evidence. False retains the seal.
/// Once consumed, only cleanup_model_execution may settle its capacity token.
/// This does not settle original read/Store custody or acknowledge FD cleanup.
pub fn cleanup_original_model_startup(
  startup : OriginalModelStartup,
) -> Result[Bool, ModelExecutionIssue] {
  if startup.used {
    return Ok(!@resources.capacity_reservation_open(startup.capacity))
  }
  if !@relation.cleanup_prepared_infer_rows(startup.rows) {
    return Ok(false)
  }
  match @resources.settle_capacity(startup.ledger, startup.capacity) {
    Ok(_) => {
      startup.used = true
      Ok(true)
    }
    Err(issue) => Err(Ledger(issue))
  }
}

///|
fn original_model_startup_matches(
  value : OriginalModelStartup,
  rows : @relation.PreparedInferRows,
  scope : @publication_host.ClientInferCallScope?,
  limits : ModelExecutionLimits,
  quantities : ModelQuantityCapacity?,
  provider : ModelProvider?,
) -> Bool {
  !value.used &&
  physical_equal(value.rows, rows) &&
  (match (value.scope, scope) {
    (Some(a), Some(b)) => physical_equal(a, b)
    (None, None) => true // Only whitebox fixtures construct an unscoped token.
    _ => false
  }) &&
  original_model_startup_limits_match(value, limits, provider) &&
  (if value.shared_mock is Some(_) {
    // This original purpose retains one component's contract on a shared
    // parent. Its original reservation/trace inventory enforces the component
    // ceiling; Resource also enforces the SAME Run's aggregate expenditure.
    @resources.quantity_configuration_covers(
      value.ledger,
      quantities.map(value => value.limits),
    )
  } else {
    @resources.quantity_configuration_matches(
      value.ledger,
      quantities.map(value => value.limits),
    )
  }) &&
  value.retained_bytes > 0L &&
  value.execution_bytes >= 0L &&
  @resources.capacity_reservation_matches(
    value.ledger,
    value.capacity,
    value.retained_bytes,
    value.execution_bytes,
  )
}
