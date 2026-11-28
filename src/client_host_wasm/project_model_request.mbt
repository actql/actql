///|
// The original submitted preparation owns the checked occurrences and the
// admitted execution/dependency material until it returns the Project Checker.
priv struct StoredPortableExecution {
  capacity : @resources.CapacityReservation
  mut retained_bytes : Int64
  mut request : @host.ClientRequestIdentity?
  mut file : StoredPortableModelFile?
  // The backed Request funds and retains this original vector until it is
  // moved into the Compute selection. It is never reconstructed at Start.
  mut bounds : Array[@infer.Limits]?
  members : Array[
    (
      @host.ClientInferOccurrence,
      @environment.ModelExecutionContract,
      @model.AdmittedStructuredModelProvider,
      @model.ModelQuantityCapacity,
    ),
  ]
}

///|
priv struct StoredPortableModelFile {
  selection : @host.ClientProjectLocalCsvSelection
  read_selection : @publication.LocalSDKResultReadSelection
  capacity : @local_host.ClientInstalledWholeSourceCapacity
  transfer : Int64
  execution : Int64
}

///|
/// Join the checked Local read selection to the exact issued Model Request.
/// The unchanged Whole input recipe bounds the later physical row response.
fn prepare_portable_model_file_request(
  value : Instance,
  held : StoredMockProjectRequest,
  environment : Int,
  configuration : StoredRunConfiguration,
  parent : @local_host.ClientRequestPreparation[@buffers.BufferSlot],
  slot : @buffers.BufferSlot,
  request : @host.ClientRequestIdentity,
) -> Int {
  guard held.portable_execution is Some(binding) &&
    binding.request is Some(original) &&
    physical_equal(original, request) &&
    binding.file is None &&
    binding.members.length() == 1 &&
    project_request_configuration(value, environment) is Some((selected, check)) &&
    physical_equal(selected, configuration) &&
    configuration.local_project == Some(check.project) &&
    configuration.sdk is Some(sdk) &&
    check.local_file is Some(checker) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    current.account is Some(account) else {
    return -20
  }
  let chosen = match
    @local_host.reserve_request_portable_model_whole_file(parent, slot, request) {
    Ok(value) => value
    Err(Preparation(issue)) => return mock_project_request_issue(issue)
    Err(_) => return -20
  }
  let (source, limits) = match
    select_paid_local_csv_source(
      checker,
      account,
      configuration.tuple.principal,
      parent,
      slot,
      chosen,
    ) {
    Ok(value) => value
    Err(code) => return code
  }
  let capacity = match
    @local_host.prepare_request_portable_model_whole_source_capacity(
      parent,
      slot,
      chosen,
      source.declaration(),
      value.installed_sequences.contracts,
      limits,
    ) {
    Ok(value) => value
    Err(InsufficientCapacity | MetadataCapacityUnavailable)
    | Err(Preparation(Resource(RetentionLimit | ExecutionLimit))) => return -4
    Err(ForeignOriginal | Preparation(ForeignOriginal)) => return -2
    Err(CleanupPending) => return -9
    Err(_) => return -20
  }
  let input = @local_host.installed_whole_source_acquisition(capacity)
  // The exact selected declaration must classify the input before this
  // Request can become ready. Provider observations never replace this policy.
  if @row_host.row_input_acquisition_facts(input).data_classification ==
    "unknown" {
    return -20
  }
  guard source.bind_input(input) is Ok(selection) &&
    selection.matches_check(checker) else {
    return -2
  }
  match run_configuration_current(value, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  let derives_read = sdk_local_model_file_read_selection_needed(
    configuration, sdk,
  )
  let (read_retained, read_scratch) = if derives_read {
    guard sdk_accepted_file_read_selection_capacity(sdk) is Some(quote) else {
      return -4
    }
    quote
  } else {
    (0L, 0L)
  }
  guard @execution.preparation_representation_cost({
      record_headers: 2L,
      reference_slots: 4L,
      scalar_words: 2L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(file_extent) &&
    @execution.checked_preparation_add_product(
      binding.retained_bytes,
      file_extent,
      1L,
    ).bind(total => {
      @execution.checked_preparation_add_product(total, read_retained, 1L)
    })
    is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, read_scratch, 1L)
    is Some(peak) &&
    @resources.grow_capacity_reservation(
      value.root,
      binding.capacity,
      bytes,
      peak,
    )
    is Ok(_) else {
    return -4
  }
  let read_selection = if derives_read {
    match issue_sdk_accepted_file_read_selection(configuration, sdk) {
      Ok(selection) => selection
      Err(code) => return code
    }
  } else {
    guard @publication.local_sdk_result_read_selection_uses_accepted_run_policy(
      sdk.read,
    ) else {
      return -32
    }
    sdk.read
  }
  binding.file = Some({
    selection,
    read_selection,
    capacity,
    transfer: source.transport.transfer_bytes,
    execution: source.transport.execution_bytes,
  })
  if @resources.shrink_capacity_reservation(
      value.root,
      binding.capacity,
      bytes,
      bytes,
    )
    is Err(_) {
    return -4
  }
  binding.retained_bytes = bytes
  0
}

///|
fn portable_model_compute_storage(
  count : Int,
) -> @execution.PreparationRepresentationUnits? {
  let bounds = @infer.prepared_composed_bounds_construction()
  if count == 0 {
    return Some(bounds)
  }
  let members = count.to_int64()
  guard @execution.preparation_array_representation(4L, 4L * members, true)
    is Some(arrays) &&
    // The quote walks one literal/assertion child at a time. Its one-step
    // view takes two singleton arrays; each capacity fold uses a fixed
    // inventory (at most eleven items). The retained quote and option for
    // each member are included separately below.
    @execution.preparation_array_representation(4L, 16L, true)
    is Some(prefix_quote_arrays) &&
    @execution.preparation_array_representation(2L, 6L, false)
    is Some(physical_quote_arrays) else {
    return None
  }
  @execution.compose_preparation_representation([
    bounds,
    arrays,
    prefix_quote_arrays,
    physical_quote_arrays,
    {
      // Original Prefix and suffix projections borrow the active Task's 22
      // sequence references each. Include both shells and their Some carriers.
      // Lowered prefixes can also hold the adjacent Infer step and terminal
      // lookup options alongside the new scalar prefix selector. The
      // explicitly prepaid prefix also carries its own activation option.
      // The temporary quote includes a selected sequence, three limit records,
      // inventory items and local option/arithmetic carriers. Members keep
      // only the resulting capacity, its option and the closure reference.
      // The Local component binding borrows the same Task sequence through
      // typed output cleanup. Include its variant and the constructor option.
      // The metered prefix recipe adds its startup capacity and option
      // during assembly while the ordinary full-quote closure is retained.
      // The fixed Model startup quote also uses the construction tariff's
      // map/array arithmetic and one resulting capacity/option pair.
      // The Run holds one current-observation closure and its captured
      // configuration and inputs. Each member binds one egress admission,
      // with the checked occurrence and current/result carriers.
      // One Portable writer/cursor inventory is costed at a time. Its
      // construction descriptors, six capacity items and checked amounts
      // are temporary. Each member keeps only the two startup amounts.
      // The installed binder retains its closure and result Option per
      // Model. Its one quote and comparison are synchronous. The Run also
      // holds the exact response profile beside its installation identity.
      // One Scope quote at a time. Admission/writer inventory records,
      // checked sums, their options and one Account decision are synchronous.
      // The retained members add only the two bounded Scope dimensions.
      // A Model retains its completion callback, output borrow and option
      // until the original managed Task's cleanup returns that borrow.
      // The exact checked Run/Definition link, option and validation return
      // coexist with these controls. The installed bodies are borrowed.
      record_headers: 256L + 72L * members,
      reference_slots: 440L + 171L * members,
      // The deferred HTTP port keeps its stage, stop interest and the two
      // physical response scalars. Its Raw and Entry projections add refs.
      scalar_words: 425L + 68L * members,
      // One confirmed Entry digest remains after the wire is released.
      owned_utf16_units: 71L * members,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
fn portable_model_quantity_capacity(
  execution : @environment.ModelExecutionContract,
  per_attempt : @resources.QuantityAmounts,
) -> @model.ModelQuantityCapacity? {
  let limits : @resources.QuantityAmounts = {
    tokens: @environment.model_execution_ceiling(
      execution,
      TotalTokenReservation,
    ),
    cost_units: @environment.model_execution_ceiling(execution, TotalCostUnits),
    duration_ms: @environment.model_execution_ceiling(
      execution,
      TotalDurationMs,
    ),
  }
  // The policy is installation DATA, bounded by the original contract that
  // belongs to this member. It never reallocates another member's budget.
  if per_attempt.tokens > limits.tokens ||
    per_attempt.cost_units > limits.cost_units ||
    per_attempt.duration_ms > limits.duration_ms {
    return None
  }
  Some({ limits, per_attempt, })
}

///|
fn prepare_portable_submission_execution(
  value : Instance,
  held : StoredMockProjectRequest,
  configuration : StoredRunConfiguration,
  prepared : @host.PreparedClientProgram,
) -> Int {
  guard configuration.sdk is Some({ portable_model: Some(handle), .. }) &&
    configuration.host_current is Some(current) &&
    installed_portable_model_task(value, handle, current) is Some(original) &&
    original._configured is Some((configured, physical, capability)) else {
    return -31
  }
  guard original.execution is Some((body, per_attempt, _)) else { return -31 }
  guard @host.prepared_client_composed_infer_count(prepared) is Some(count) else {
    return -31
  }
  if count == 0 {
    return -20
  }
  let n = count.to_int64()
  // Quote the occurrence and retained member vectors, the four-reference
  // occurrence records, member tuples, and installed per-occurrence
  // quantity envelope (with its own total bounds) before constructing a member.
  guard @execution.preparation_array_representation(2L, 2L * n, true)
    is Some(arrays) &&
    @execution.compose_preparation_representation([
      arrays,
      {
        record_headers: 16L + 4L * n,
        reference_slots: 29L + 10L * n,
        scalar_words: 16L + 6L * n,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(storage) &&
    @execution.preparation_representation_cost(storage) is Some(prefix) else {
    return -4
  }
  let capacity = match @resources.reserve_capacity(value.root, prefix, prefix) {
    Ok(capacity) => capacity
    Err(_) => return -4
  }
  let binding : StoredPortableExecution = {
    capacity,
    retained_bytes: prefix,
    request: None,
    file: None,
    bounds: None,
    members: Array(capacity=count),
  }
  held.portable_execution = Some(binding)
  guard @host.prepared_client_composed_infer_occurrences(prepared)
    is Some(occurrences) &&
    occurrences.length() == count else {
    return -31
  }
  let (_, task_cid, _, _) = @environment.normalized_public_model_task_materials(
    configured.task,
  )
  let limits = project_model_task_limits()
  let mut retained = prefix
  for occurrence in occurrences {
    if @host.client_infer_occurrence_model_task_cid(occurrence) !=
      Some(task_cid) {
      return -31
    }
    let charged = Ref(retained)
    let kept = Ref(retained)
    let execution = @model.read_portable_model_http_execution(
      occurrence,
      body,
      limits,
      (held, working) => {
        guard @execution.preparation_representation_cost(held) is Some(bytes) &&
          @execution.preparation_representation_cost(working) is Some(peak) &&
          @execution.checked_preparation_add_product(retained, bytes, 1L)
          is Some(next) &&
          @execution.checked_preparation_add_product(retained, peak, 1L)
          is Some(total) else {
          return false
        }
        let total = Int64::max(charged.val, total)
        match
          @resources.grow_capacity_reservation(
            value.root,
            capacity,
            total,
            total,
          ) {
          Ok(_) => {
            charged.val = total
            kept.val = next
            true
          }
          Err(_) => false
        }
      },
    )
    let (contract, dependencies) = match execution {
      Ok(value) => value
      Err(@model.Capacity) => return -4
      Err(_) => return -31
    }
    guard portable_model_quantity_capacity(contract, per_attempt)
      is Some(quantities) else {
      return -31
    }
    let prompt = @environment.single_attempt_model_prompt(dependencies)
    guard @environment.model_dependency_payload(prompt) is Some(payload) else {
      return -31
    }
    // The decoded prompt remains live while the codec checks its closed
    // payload. Fund its actual key inventory before the validator allocates.
    guard @decode.closed_object_construction_extent(
        payload,
        2,
        limits.bodies.max_depth,
      )
      is Some(fields) &&
      @execution.preparation_representation_cost({
        record_headers: fields.record_headers + 24L,
        reference_slots: fields.reference_slots + 42L,
        scalar_words: fields.scalar_words + 26L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
      is Some(work) &&
      @execution.checked_preparation_add_product(kept.val, work, 1L)
      is Some(peak) &&
      @execution.preparation_representation_cost({
        record_headers: 2L,
        reference_slots: 5L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
      is Some(admitted) &&
      @execution.checked_preparation_add_product(kept.val, admitted, 1L)
      is Some(next) &&
      @resources.grow_capacity_reservation(
        value.root,
        capacity,
        Int64::max(charged.val, peak),
        Int64::max(charged.val, peak),
      )
      is Ok(_) else {
      return -4
    }
    let provider = match
      @model.admit_structured_model_provider(
        capability,
        configured.route,
        contract,
        dependencies,
        physical,
        (_, original_prompt) => {
          @environment.model_openai_chat_instructions(original_prompt)
          is Some(_)
        },
      ) {
      Ok(value) => value
      Err(_) => return -31
    }
    binding.members.push((occurrence, contract, provider, quantities))
    retained = next
    guard @resources.shrink_capacity_reservation(
        value.root,
        capacity,
        retained,
        retained,
      )
      is Ok(_) else {
      return -4
    }
    binding.retained_bytes = retained
  }
  0
}

///|
/// Compile the installed Model on the exact already checked Project
/// Request. Keep its borrow and all selected occurrence bindings for the
/// existing Run owner. No physical attempt is acquired here.
fn prepare_retained_portable_model(
  value : Instance,
  configuration : StoredRunConfiguration,
  held : StoredMockProjectRequest,
  parent : @local_host.ClientRequestPreparation[@buffers.BufferSlot],
  slot : @buffers.BufferSlot,
) -> Int {
  match run_configuration_current(value, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  let input = match @local_host.borrow_request_model_plan_input(parent, slot) {
    Err(issue) => return mock_project_request_issue(issue)
    Ok(value) => value
  }
  held.model_input = Some(input)
  guard @resources.preparation_body_borrow_value(input) is Some(prepared) else {
    return -32
  }
  let code = prepare_portable_submission_execution(
    value, held, configuration, prepared,
  )
  if code != 0 {
    return code
  }
  guard held.portable_execution is Some(execution) else { return -35 }
  {
    let contracts = value.installed_sequences.contracts
    let manifests = @host.packaged_client_compilation_manifests()
    let compilation_limits = @host.client_standard_pure_compilation_limits()
    let count = execution.members.length()
    let mut selected = None
    for index, binding in execution.members {
      guard portable_model_compute_storage(if index == 0 { count } else { 0 })
        is Some(caller_material) else {
        return -4
      }
      let graph = match
        @local_host.prepare_request_model_graph(
          parent,
          slot,
          binding.0,
          binding.1,
          contracts,
          manifests~,
          compilation_limits~,
          caller_material=Some(caller_material),
        ) {
        Err(Preparation(issue)) => return mock_project_request_issue(issue)
        Err(_) => return -31
        Ok(value) => value
      }
      if selected is None {
        selected = Some(Array(capacity=count))
        execution.bounds = Some(Array(capacity=count))
      }
      let bounds = match @infer.prepared_composed_bounds(binding.0, graph) {
        Ok(bounds) => bounds
        Err(_) => return -31
      }
      selected.unwrap().push(graph)
      execution.bounds.unwrap().push(bounds)
    }
    guard selected is Some(graphs) && graphs.length() == count else {
      return -32
    }
    match
      @local_host.prepare_request_portable_model_artifact(
        parent,
        slot,
        graphs,
        contracts,
        manifests~,
        compilation_limits~,
      ) {
      Err(Preparation(issue)) => return mock_project_request_issue(issue)
      Err(_) => return -31
      Ok(_) => ()
    }
  }
  match run_configuration_current(value, configuration) {
    Err(code) => code
    Ok(_) => {
      held.model_ready = true
      0
    }
  }
}

///|
fn retained_sdk_portable_request(
  value : Instance,
  preparation : StoredPreparation,
  configuration_handle : Int,
  configuration : StoredRunConfiguration,
  submission : Int,
) -> StoredMockProjectRequest? {
  guard preparation.kind == RETAINED_MOCK_REQUEST_KIND &&
    preparation.restoration is None &&
    preparation.project_request is Some(original) &&
    original.model_ready &&
    original.model_input is Some(_) &&
    original.parent is Some(_) &&
    original.portable_execution is Some(execution) &&
    !execution.members.is_empty() &&
    configuration.sdk is Some({ portable_model: Some(task), .. }) &&
    configuration.host_current is Some(current) &&
    installed_portable_model_task(value, task, current) is Some(provider) &&
    value.original_metadata.get(preparation.environment) is Some(metadata) &&
    project_request_configuration(value, preparation.environment)
    is Some((selected, check)) &&
    check.configuration == configuration_handle &&
    physical_equal(selected, configuration) &&
    sdk_whole_file_preparing_submission(
      value, preparation, configuration_handle, submission,
    )
    is Some(_) else {
    return None
  }
  match metadata.project {
    Some(PortableModelCheck(original)) if physical_equal(original, check) => ()
    Some(LocalCheck(original)) if physical_equal(original, check) &&
      configuration.local_project == Some(check.project) &&
      original_local_project_inputs(value, check.project) is Some(inputs) &&
      value.original_metadata.get(provider.parent)
      is Some({ project: Some(ModelTask(typed)), .. }) &&
      inputs.model_registry == Some(typed.parent) &&
      inputs.model_configuration == Some(task) => ()
    _ => return None
  }
  Some(original)
}

///|
/// Fund the original fixed-size identity before deriving it, on the same
/// Model Request reservation that already owns its checked members.
fn prepare_retained_portable_identity(
  value : Instance,
  original : StoredMockProjectRequest,
  prepared : @host.PreparedClientProgram,
  configuration : StoredRunConfiguration,
  saved : @host.ClientSubmittedJournalEncoding,
) -> Result[@host.ClientRequestIdentity, Int] {
  guard original.portable_execution is Some(held) else { return Err(-35) }
  if held.request is Some(request) {
    return if @host.client_submission_reference_matches_request(
        saved.reference,
        request,
      ) &&
      @host.client_request_input_cid(request) ==
      @host.client_submitted_intent_cid(saved.intent) {
      Ok(request)
    } else {
      Err(-35)
    }
  }
  guard @host.client_request_identity_construction_inventory()
    is Some((retained, execution)) &&
    @execution.preparation_representation_cost(retained) is Some(kept) &&
    @execution.preparation_representation_cost(execution) is Some(work) &&
    @execution.checked_preparation_add_product(held.retained_bytes, kept, 1L)
    is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, work, 1L) is Some(peak) &&
    @resources.grow_capacity_reservation(value.root, held.capacity, bytes, peak)
    is Ok(_) else {
    return Err(-4)
  }
  let request = match
    @host.prepare_client_request_identity(
      prepared,
      configuration.authority_scope_cid,
      @host.client_submission_reference_record_request_id(saved.reference),
      @host.client_submitted_intent_cid(saved.intent),
    ) {
    Ok(request) => request
    Err(_) => return Err(-31)
  }
  held.request = Some(request)
  guard @resources.shrink_capacity_reservation(
      value.root,
      held.capacity,
      bytes,
      bytes,
    )
    is Ok(_) else {
    return Err(-4)
  }
  held.retained_bytes = bytes
  Ok(request)
}

///|
// The copied wire carries the exact entered HTTP bytes behind a UTF-8
// locator and six integer bounds. Only the profile and installed selection
// supply those values. No request content is independently encoded here.
fn portable_model_http_wire_bound(
  run : StoredPortableModelRun,
  prepared : @model.ModelPreparedCallSet,
  entry : @model.ModelCallEntry,
) -> (Int, Int)? {
  let endpoint = run.profile.endpoint
  let limit = @environment.model_response_profile_limits(run.response_profile)
  guard !endpoint.contains("\n") &&
    !endpoint.contains("\r") &&
    @model.model_call_entry_http_request_bytes(entry, prepared) is Some(body) &&
    body > 0 &&
    body <= limit.request_bytes &&
    body <= 1048576 &&
    endpoint.length() <= 65536 else {
    return None
  }
  // UTF-16 endpoint units encode to at most three UTF-8 bytes each.
  // Six nonnegative signed-32 quantities, plus seven delimiters.
  let prefix = 3 * endpoint.length() + 67
  if body + 5 * prefix > 1048576 {
    return None
  }
  Some((body + prefix, prefix))
}

///|
fn portable_model_http_output_original(
  value : Instance,
  handle : Int,
  compute : Int,
) -> (StoredPortableModelRun, StoredPortableModelMember, Int, Int)? {
  guard value.tasks.get(handle) is Some(record) &&
    record.compute == compute &&
    portable_entry_original(value, record)
    is Some((run, selected_task, _, prepared, _, entry)) &&
    portable_model_http_wire_bound(run, prepared, entry)
    is Some((bytes, prefix)) &&
    selected_task.entry_journal is Some({ state: Confirmed, .. }) &&
    selected_task.capture is Some(_) &&
    selected_task.transport is None &&
    selected_task.request_material is None else {
    return None
  }
  Some((run, selected_task, bytes, prefix))
}

///|
/// Project only the original frame's capacity bound. No transport enters
/// until the exact output loan exists and the fresh clock has been checked.
pub fn portable_model_request_bound(
  nonce : Int64,
  handle : Int,
  compute : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    portable_model_http_output_original(value, handle, compute)
    is Some((_, _, bytes, _)) else {
    return -32
  }
  bytes
}

///|
pub fn reserve_portable_model_request(
  nonce : Int64,
  handle : Int,
  compute : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.computes.get(compute)
    is Some({ origin: SourceFree(run_handle, _), .. }) &&
    portable_model_http_output_original(value, handle, compute)
    is Some((_, selected_task, bytes, prefix)) &&
    physical_copy_bytes >= 2L * bytes.to_int64() else {
    return -32
  }
  // The prefix's UTF-16 builder and its UTF-8 copy retire synchronously.
  // Fund their overlap with the complete output in the same material loan.
  let result = reserve_material_record(
    value,
    run_handle,
    11,
    physical_ticket,
    physical_copy_bytes,
    wire_limit=bytes + 4 * prefix,
  )
  if result > 0 {
    selected_task.request_material = Some(result)
  }
  result
}

///|
fn portable_model_http_request_wire(
  run : StoredPortableModelRun,
  selected_task : StoredPortableModelMember,
  call : @model.ModelPhysicalCall,
  capture : @host.ClientModelRawCaptureRegistration,
) -> Bytes? {
  guard @model.entered_model_http_chat_material(call, capture)
    is Ok((endpoint, profile, body)) &&
    physical_equal(profile, run.response_profile) &&
    endpoint == run.profile.endpoint else {
    return None
  }
  let limit = @environment.model_response_profile_limits(profile)
  let timeout = selected_task.quantities.per_attempt.duration_ms
  guard timeout > 0L &&
    timeout <= 2147483647L &&
    body.length() <= limit.request_bytes else {
    return None
  }
  let prefix = @utf8.encode(
    "\{endpoint}\n\{timeout}\n\{limit.request_bytes}\n\{limit.header_bytes}\n\{limit.response_bytes}\n\{limit.chunk_bytes}\n\{limit.chunks}\n",
  )
  Some(prefix + body)
}

///|
/// Enter the same confirmed Call once under its original fresh reader, then
/// copy only its funded request into the already owned output material.
pub fn produce_portable_model_request(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    value.materials.get(material)
    is Some({ kind: 11, invoked: false, closing: false, .. } as output) &&
    portable_entry_original(value, record)
    is Some((run, selected_task, _, prepared, admission, entry)) &&
    portable_model_http_wire_bound(run, prepared, entry)
    is Some((bound, prefix)) &&
    @buffers.buffer_output_limit(value.pool, output.slot) ==
    Some(bound + 4 * prefix) &&
    selected_task.entry_journal is Some({ state: Confirmed, .. }) &&
    selected_task.capture is Some(capture) &&
    selected_task.transport is None &&
    selected_task.request_material == Some(material) &&
    selected_task.dispatch_clock.val is None &&
    portable_entry_clock(value, clock_input) is Some(at) else {
    return -32
  }
  selected_task.dispatch_clock.val = Some(at)
  defer {
    selected_task.dispatch_clock.val = None
  }
  match @host.check_client_infer_dispatch_current(admission) {
    Err(@host.Expired) => return -36
    Err(_) => return -32
    Ok(_) => ()
  }
  if @host.check_client_model_raw_capture_current(capture) is Err(_) {
    return -37
  }
  output.invoked = true
  let code = advance_managed_task(nonce, handle, 1)
  if code != 0 {
    return code
  }
  guard selected_task.transport is Some(call) &&
    portable_model_http_request_wire(run, selected_task, call, capture)
    is Some(wire) &&
    wire.length() <= bound else {
    return -32
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, output.slot, wire),
  )
  if code == 0 {
    output.produced = true
  }
  code
}

///|
/// Reobserve the selected Call and its output, without consuming another gate
/// or transferring another copy. The physical transport's late credential
/// read must use its own fresh instance of this observation.
pub fn check_portable_model_request(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    !record.closing &&
    !record.pending &&
    record.issue is None &&
    value.materials.get(material)
    is Some({ kind: 11, produced: true, closing: false, .. }) &&
    portable_model_task_original(value, record)
    is Ok(Some((_, selected_task, _))) &&
    selected_task.entry_journal is Some({ state: Confirmed, .. }) &&
    selected_task.dispatch is Some(admission) &&
    selected_task.request_material == Some(material) &&
    selected_task.transport is Some(call) &&
    selected_task.capture is Some(capture) &&
    selected_task.dispatch_clock.val is None &&
    portable_entry_clock(value, clock_input) is Some(at) else {
    return -32
  }
  selected_task.dispatch_clock.val = Some(at)
  defer {
    selected_task.dispatch_clock.val = None
  }
  match @host.check_client_infer_dispatch_current(admission) {
    Err(@host.Expired) => return -36
    Err(_) => return -32
    Ok(_) => ()
  }
  match @model.entered_model_http_chat_material(call, capture) {
    Ok(_) => 0
    Err(_) => -32
  }
}

///|
/// Grant exactly one physical worker the entered and durably confirmed request.
pub fn claim_portable_model_request(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
) -> Int {
  let code = check_portable_model_request(nonce, handle, clock_input, material)
  if code != 0 {
    return code
  }
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_task_retained(value, record)
    is Ok(Some((_, selected_task, _))) &&
    selected_task.transport_worker is Unclaimed &&
    !selected_task.transport_stop else {
    return -32
  }
  selected_task.transport_worker = Active
  0
}

///|
/// The trusted Host reports actual physical close for this one worker. A
/// complete body still needs its original Raw Store confirmation before Core
/// can observe a response. A lost body remains physically uncertain.
pub fn finish_portable_model_request(
  nonce : Int64,
  handle : Int,
  material : Int,
  input : Int,
  http_status : Int,
) -> Int {
  guard (
      (input == 0 && http_status == 0) ||
      (input > 0 && http_status >= 200 && http_status <= 599)
    ) &&
    selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    value.materials.get(material) is Some({ kind: 11, produced: true, .. }) &&
    portable_model_task_retained(value, record)
    is Ok(Some((_, selected_task, _))) &&
    selected_task.request_material == Some(material) &&
    selected_task.transport is Some(_) &&
    selected_task.transport_worker is Active else {
    return -32
  }
  if input == 0 {
    selected_task.transport_worker = ClosedUnknown
    return 0
  }
  guard value.copies.get(input) is Some((slot, _)) &&
    !slot.output_only &&
    !slot.input_complete &&
    !slot.retired &&
    slot.written == slot.wire_length else {
    selected_task.transport_worker = ClosedUnknown
    return -32
  }
  selected_task.transport_worker = ClosedAwaitingRaw(input, http_status)
  0
}

///|
fn portable_model_request_worker_active(
  value : Instance,
  run : Int,
  material : Int,
) -> Bool {
  guard value.runs.get(run) is Some(original) &&
    value.preparations.get(original.preparation)
    is Some({ project_request: Some({ model_run: Some(model), .. }), .. }) else {
    return false
  }
  model.members.any(selected_task => {
    selected_task.request_material == Some(material) &&
    selected_task.transport_worker is Active
  })
}
