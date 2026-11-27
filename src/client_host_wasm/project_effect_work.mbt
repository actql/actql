///|
const MOCK_EFFECT_SOURCE_EVIDENCE_KIND : Int = 15

///|
const MOCK_EFFECT_COMPUTE_KIND : Int = 16

///|
priv struct StoredMockEffectSourceEvidence {
  ledger : @resources.Ledger
  capacity : @resources.CapacityReservation
  mut publication : @host.ClientEffectDirectSourcesPublication?
}

///|
priv struct StoredMockEffectTaskDrive {
  ledger : @resources.Ledger
  capacity : @resources.CapacityReservation
  mut charged : @execution.ExecutionCapacity
  mut body_workspace : @resources.CapacityReservation?
  mut body : StoredMockEffectArtifactBody?
  mut artifact_capture : @local_host.InstalledEffectResultCapture?
  mut artifacts : Array[StoredMockEffectArtifact]?
  mut targets : StoredMockEffectTargetDrive?
  mut tasks : @local_host.LocalEffectTaskExecution?
  mut result : @local_host.LocalValuesExecution?
  mut inputs : @strategy.CapturedEffectInputs?
  mut source_unit : @host.ClientEffectCombinedSourceUnit?
  mut stepping : Bool
  mut failed : Bool
}

///|
priv struct StoredMockEffectArtifact {
  capture : @local_host.InstalledEffectResultCapture
  artifact : @host.ClientEffectLocalResultArtifact
  logical_body : String
}

///|
priv struct StoredMockEffectArtifactBody {
  artifact : @host.ClientEffectLocalResultArtifact
  snapshot : @execution.CompletedRelationSnapshotPreparation
}

///|
fn mock_effect_descriptor_field(wire : Bytes, offset : Int) -> Int {
  wire[offset].to_int() |
  (wire[offset + 1].to_int() << 8) |
  (wire[offset + 2].to_int() << 16) |
  (wire[offset + 3].to_int() << 24)
}

///|
// Input arrays are references to accounted Source/identity backing. The
// quote covers the new ordinal table, the Common issuer's metadata and the
// Source-specific logical/observation constructors through the handoff.
fn mock_effect_source_evidence_capacity(count : Int) -> Int64? {
  guard count > 0 && count <= 1024 else { return None }
  let slots = count.to_int64()
  guard @execution.preparation_array_representation(9L, 9L * slots, true)
    is Some(arrays) &&
    @execution.preparation_representation_cost({
      record_headers: 23L + arrays.record_headers + 5L * slots,
      reference_slots: 57L + arrays.reference_slots + 9L * slots,
      scalar_words: 25L + arrays.scalar_words + 5L * slots,
      owned_utf16_units: 24L,
      owned_wire_bytes: 24L,
    })
    is Some(controls) &&
    @host.client_protocol_metadata_construction_bytes(
      16384,
      1024L,
      extra_controls=controls,
      copies=2 * count + 2,
    )
    is Some((metadata, _)) else {
    return None
  }
  Some(metadata)
}

///|
fn seal_original_mock_effect_sources(
  value : Instance,
  start : Int,
  completed : String,
  record : StoredOriginalMetadata,
) -> Int {
  guard value.physical_starts.get(start) is Some(custody) &&
    custody.mock_effect_compute is Some(compute) &&
    compute.source_evidence is None else {
    return -33
  }
  let (original, managed) = match mock_effect_claimed_current(value, start) {
    Ok(pair) => pair
    Err(code) => return code
  }
  let materials = original.journal.materials
  guard @host.client_effect_run_start_current(
    materials.allowed,
    materials.run_definition,
    completed,
  ) else {
    return -32
  }
  let count = original.effect.sources.length()
  let prepared = materials.prepared
  let request = original.effect.request
  guard mock_effect_source_evidence_capacity(count) is Some(quote) else {
    return -4
  }
  let ledger = match
    @local_host.installed_effect_managed_sources_ledger(
      managed, prepared, request,
    ) {
    Ok(ledger) => ledger
    Err(issue) => return mock_effect_work_issue(issue)
  }
  let capacity = match @resources.reserve_capacity(ledger, quote, quote) {
    Ok(capacity) => capacity
    Err(_) => return -4
  }
  // The attempt remains owned before constructing any publication members.
  let evidence : StoredMockEffectSourceEvidence = {
    ledger,
    capacity,
    publication: None,
  }
  compute.source_evidence = Some(evidence)
  match
    issue_original_mock_effect_sources(
      value, start, original, managed, compute, completed,
    ) {
    Ok(publication) => {
      // Constructors have returned. Keep the complete original Source
      // evidence, with the same Invocation and observation used by Compute.
      // Only their stopped construction inventory leaves the reservation.
      guard @host.client_effect_direct_sources_publication_retained_bytes(
          publication, 1024, 20,
        )
        is Some(retained) &&
        retained <= quote else {
        return -4
      }
      if @resources.shrink_capacity_reservation(
          ledger, capacity, retained, retained,
        )
        is Err(_) {
        return -9
      }
      // Enable Compute only after the final current check and output succeeds.
      match mock_effect_claimed_current(value, start) {
        Ok(_) => ()
        Err(code) => return code
      }
      let supplied = status(
        @buffers.supply_buffer_output(value.pool, record.slot, b""),
      )
      if supplied == 0 {
        evidence.publication = Some(publication)
        record.produced = true
      }
      supplied
    }
    Err(code) => code
  }
}

///|
fn issue_original_mock_effect_sources(
  value : Instance,
  start : Int,
  original : MockEffectJournalObservationOriginal,
  managed : @local_host.ClientInstalledManagedRun,
  compute : StoredMockEffectCompute,
  completed : String,
) -> Result[@host.ClientEffectDirectSourcesPublication, Int] {
  let materials = original.journal.materials
  let prepared = materials.prepared
  let request = original.effect.request
  let count = original.effect.sources.length()
  let plan = match
    @local_host.installed_effect_managed_operation_plan(
      managed, prepared, request,
    ) {
    Ok(plan) => plan
    Err(issue) => return Err(mock_effect_work_issue(issue))
  }
  guard @local_host.prepared_installed_effect_source_occurrences(
      plan, prepared, request,
    )
    is Ok(Some(occurrences)) &&
    @host.client_direct_acquisition_occurrence_count(occurrences) == count &&
    @host.prepared_client_effect_publication_data_policy_cid(prepared)
    is Some(policy) else {
    return Err(-32)
  }
  let ordered = FixedArray::make(count, None)
  for record in value.original_metadata.values() {
    if record.produced &&
      record.project is Some(MockEffectCapture(child)) &&
      child.start == start {
      guard child.occurrence >= 0 &&
        child.occurrence < count &&
        ordered[child.occurrence] is None else {
        return Err(-32)
      }
      ordered[child.occurrence] = Some(child)
    }
  }
  let scope = @host.client_request_authority_scope_cid(request)
  let graph = @strategy.captured_dag_graph(
    @strategy.captured_effect_run_dag(compute.dag),
  )
  let sources = Array(capacity=count)
  let identities = Array(capacity=count)
  let logicals = Array(capacity=count)
  let observations = Array(capacity=count)
  let mut started = completed
  for occurrence, entry in ordered {
    guard entry is Some(child) &&
      child.started_at.lexical_compare(completed) <= 0 &&
      original.effect.sources.get(occurrence) is Some(selected) &&
      authorize_mock_effect_source(original, selected) &&
      child.rows is Some(rows) &&
      child.captured is Some(capture) &&
      child.acquisition is Some(acquisition) &&
      child.identity is Some(identity) &&
      @row_host.check_row_input_capture_run(capture, rows) is Ok(_) &&
      @row_host.row_capture_input(capture) is Some(input) &&
      @row_host.row_captured_input_source(input) is Some(source) &&
      @row_host.row_captured_input_source_original(input)
      is Some(source_acquisition) &&
      @query.captured_source_relation_identity_matches_source(identity, source) &&
      @host.client_direct_acquisition_occurrence_at(occurrences, occurrence)
      is Some((_, _, task)) else {
      return Err(-32)
    }
    if child.started_at.lexical_compare(started) < 0 {
      started = child.started_at
    }
    let logical = match
      @host.issue_captured_whole_source_input_logical(
        graph,
        source,
        identity,
        source_acquisition,
        task~,
      ) {
      Ok(value) => value
      Err(_) => return Err(-31)
    }
    let facts = @row_host.row_input_acquisition_facts(acquisition)
    let observation = match
      @row_host.issue_row_input_source_evidence(
        acquisition,
        capture,
        identity,
        logical,
        scope,
        facts.source_data_policy_cid,
        completed,
      ) {
      Ok(value) => value
      Err(issue) => return Err(mock_effect_capture_issue(issue))
    }
    sources.push(source)
    identities.push(identity)
    logicals.push(logical)
    observations.push(observation)
  }
  match
    @local_host.begin_installed_effect_operation_controls(
      managed, prepared, request, plan,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(mock_effect_work_issue(issue))
  }
  @local_host.issue_installed_effect_direct_sources_invocation(
    managed,
    prepared,
    request,
    plan,
    compute.bound,
    compute.dag,
    materials.compilation,
    @host.client_effect_allowed_run_admission(materials.allowed),
    materials.run_definition,
    sources,
    identities,
    observations,
    logicals,
    scope,
    policy,
    started,
    completed,
    16384,
    1024,
    20,
  ).map_err(issue => {
    match issue {
      Installed(cause) => mock_effect_work_issue(cause)
      _ => -32
    }
  })
}

///|
fn mock_effect_work_issue(
  issue : @local_host.ClientInstalledManagedRunIssue,
) -> Int {
  match issue {
    ForeignOriginal | Retired => -32
    InsufficientCapacity
    | MetadataCapacityUnavailable
    | Ledger(RetentionLimit | ExecutionLimit | TransferLimit)
    | Preparation(Resource(RetentionLimit | ExecutionLimit | TransferLimit)) =>
      -4
    CleanupPending => -9
    Unsupported => -20
    _ => -31
  }
}

///|
fn begin_original_mock_effect_task_drive(
  compute : StoredMockEffectCompute,
  evidence : StoredMockEffectSourceEvidence,
) -> Int {
  compute.attempted = true
  let graph = @strategy.captured_dag_graph(
    @strategy.captured_effect_run_dag(compute.dag),
  )
  guard @local_host.stepped_effect_local_tasks_control_capacity(graph)
    is Some(base) &&
    @execution.preparation_representation_cost({
      // Include the Source Unit and input aliases and the single original
      // publication constructor's transient selector/result carriers.
      record_headers: 38L,
      reference_slots: 98L,
      scalar_words: 20L,
      owned_utf16_units: 24L,
      owned_wire_bytes: 0L,
    })
    is Some(bridge) &&
    @execution.execution_capacity(bridge, bridge) is Some(extra) &&
    @execution.add_execution_capacity(base, extra) is Some(quote) else {
    return -4
  }
  let capacity = match
    @resources.reserve_capacity(
      evidence.ledger,
      quote.retained_bytes,
      quote.execution_bytes,
    ) {
    Ok(capacity) => capacity
    Err(_) => return -4
  }
  let drive : StoredMockEffectTaskDrive = {
    ledger: evidence.ledger,
    capacity,
    charged: quote,
    body_workspace: None,
    body: None,
    artifact_capture: None,
    artifacts: None,
    targets: None,
    tasks: None,
    result: None,
    inputs: None,
    source_unit: None,
    stepping: false,
    failed: false,
  }
  compute.task_drive = Some(drive)
  match
    @local_host.begin_stepped_effect_local_tasks(compute.host, compute.dag) {
    Ok(tasks) => {
      drive.tasks = Some(tasks)
      0
    }
    Err(issue) => mock_effect_task_issue(issue)
  }
}

///|
fn mock_effect_task_issue(issue : @local_host.LocalValuesExecutionIssue) -> Int {
  match issue {
    Fenced => -32
    Driver(issue) => -managed_task_dispatch_issue_code(issue)
    _ => -31
  }
}

///|
fn advance_original_mock_effect_tasks(
  value : Instance,
  start : Int,
  at : String,
) -> Int {
  guard value.physical_starts.get(start) is Some(custody) &&
    custody.mock_effect_compute is Some(compute) &&
    compute.source_evidence is Some(evidence) &&
    evidence.publication is Some(publication) else {
    return -33
  }
  let (original, managed) = match mock_effect_claimed_current(value, start) {
    Ok(pair) => pair
    Err(code) => return fail_original_mock_effect_tasks(compute, code)
  }
  let materials = original.journal.materials
  if !@host.client_effect_run_start_current(
      materials.allowed,
      materials.run_definition,
      at,
    ) {
    return fail_original_mock_effect_tasks(compute, -32)
  }
  if !compute.attempted {
    let begun = begin_original_mock_effect_task_drive(compute, evidence)
    if begun != 0 {
      return begun
    }
  }
  guard compute.task_drive is Some(drive) &&
    !drive.failed &&
    !drive.stepping &&
    drive.tasks is Some(tasks) else {
    return -33
  }
  let first = Ref(0)
  let current = () => {
    if first.val == 0 {
      first.val = match mock_effect_claimed_current(value, start) {
        Ok(_) if custody.mock_effect_compute is Some(active) &&
          physical_equal(active, compute) => 0
        Ok(_) => -33
        Err(code) => code
      }
    }
    first.val == 0
  }
  // A completed Compute uses a fresh original Read for Source Unit issue.
  // Keep its successful output and the selected inputs on this same drive.
  drive.stepping = true
  let code = if drive.source_unit is Some(unit) &&
    drive.result is Some(result) &&
    drive.inputs is Some(inputs) {
    let advanced = advance_original_mock_effect_artifacts(
      compute, drive, managed, original, publication, result, inputs, unit,
    )
    if advanced < 0 {
      advanced
    } else if !current() {
      first.val
    } else if advanced != 0 {
      advanced
    } else {
      let observed = advance_original_mock_effect_targets(
        value, compute, drive, managed, original, inputs, publication, unit, at,
      )
      if observed >= 0 && !current() {
        first.val
      } else {
        observed
      }
    }
  } else if drive.result is Some(_) {
    match drive.inputs {
      Some(inputs) =>
        match
          prepare_original_mock_effect_source_unit(
            managed, original, publication, inputs,
          ) {
          Ok(unit) => {
            drive.source_unit = Some(unit)
            if current() {
              1
            } else {
              first.val
            }
          }
          Err(Run(issue)) => mock_effect_work_issue(issue)
          Err(_) => -31
        }
      None => -33
    }
  } else {
    match tasks.advance(256, current) {
      Ok(false) => 1
      Ok(true) =>
        match tasks.result() {
          Some(result) =>
            if !current() {
              first.val
            } else {
              match
                retain_original_mock_effect_inputs(original, managed, compute) {
                Err(code) => code
                Ok(inputs) => {
                  drive.inputs = Some(inputs)
                  if !current() {
                    first.val
                  } else {
                    drive.result = Some(result)
                    1
                  }
                }
              }
            }
          None => -31
        }
      Err(issue) =>
        if first.val == 0 {
          mock_effect_task_issue(issue)
        } else {
          first.val
        }
    }
  }
  drive.stepping = false
  drive.failed = code < 0
  code
}

///|
fn advance_original_mock_effect_artifacts(
  compute : StoredMockEffectCompute,
  drive : StoredMockEffectTaskDrive,
  managed : @local_host.ClientInstalledManagedRun,
  original : MockEffectJournalObservationOriginal,
  publication : @host.ClientEffectDirectSourcesPublication,
  result : @local_host.LocalValuesExecution,
  inputs : @strategy.CapturedEffectInputs,
  unit : @host.ClientEffectCombinedSourceUnit,
) -> Int {
  let count = @strategy.captured_effect_local_result_count(inputs)
  guard count > 0 else { return -31 }
  guard drive.artifacts is Some(artifacts) else {
    guard @builtin.configured_local_module(
        @builtin.configured_host_modules(compute.host),
      )
      is Some(installed) &&
      @managed.local_publication_bridge_limits(
        installed,
        @strategy.captured_effect_run_dag(compute.dag),
      )
      is Some(bridge) &&
      count <= bridge.entries &&
      @execution.preparation_array_representation(1L, count.to_int64(), true)
      is Some(array) &&
      @execution.preparation_representation_cost({
        record_headers: array.record_headers + count.to_int64(),
        reference_slots: array.reference_slots + 3L * count.to_int64(),
        scalar_words: array.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
      is Some(bytes) &&
      @execution.execution_capacity(bytes, bytes) is Some(extra) &&
      @execution.add_execution_capacity(drive.charged, extra) is Some(capacity) &&
      @resources.grow_capacity_reservation(
        drive.ledger,
        drive.capacity,
        capacity.retained_bytes,
        capacity.execution_bytes,
      )
      is Ok(_) else {
      return -4
    }
    drive.charged = capacity
    drive.artifacts = Some(Array(capacity=count))
    return 1
  }
  if artifacts.length() == count {
    return if @host.client_effect_unit_artifact_original_definition(
        artifacts[count - 1].artifact,
      )
      is Some(_) &&
      artifacts[count - 1].logical_body.length() > 0 {
      0
    } else {
      -32
    }
  }
  let plan = original.effect.plan
  let request = original.effect.request
  if drive.body is Some(body) {
    return advance_original_mock_effect_artifact_body(
      drive, body, artifacts, count,
    )
  }
  // A refused start retains its own scratch until serialized close.
  if drive.body_workspace is Some(_) {
    return -9
  }
  guard drive.artifact_capture is Some(capture) else {
    match
      @local_host.begin_installed_effect_result_capture(
        managed,
        plan,
        request,
        result,
        compute.dag,
        inputs,
        artifacts.length(),
      ) {
      Ok(capture) => {
        drive.artifact_capture = Some(capture)
        return 1
      }
      Err(issue) => return mock_effect_artifact_issue(issue)
    }
  }
  match capture.advance() {
    Ok(false) => return 1
    Err(issue) => return mock_effect_artifact_issue(issue)
    Ok(true) => ()
  }
  guard capture.original() is Some((exported, stream, receipt)) else {
    return -32
  }
  let materials = original.journal.materials
  match
    @local_host.prepare_installed_effect_combined_source_result_artifact(
      managed,
      plan,
      request,
      publication,
      inputs,
      exported,
      unit,
      receipt,
      @host.client_effect_allowed_run_admission(materials.allowed),
      16384,
      1024,
      20,
    ) {
    Ok(artifact) =>
      begin_original_mock_effect_artifact_body(drive, artifact, stream, receipt)
    Err(Run(issue)) => mock_effect_work_issue(issue)
    Err(_) => -31
  }
}

///|
fn mock_effect_artifact_issue(
  issue : @local_host.InstalledEffectResultCaptureIssue,
) -> Int {
  match issue {
    Unit(Run(issue)) => mock_effect_work_issue(issue)
    _ => -31
  }
}

///|
fn retire_original_mock_effect_artifacts(
  drive : StoredMockEffectTaskDrive,
) -> Bool {
  if !retire_original_mock_effect_targets(drive) {
    return false
  }
  if drive.body is Some(body) {
    body.snapshot.cancel_after_unwind()
    drive.body = None
  }
  if !retire_original_mock_effect_body_workspace(drive) {
    return false
  }
  if drive.artifact_capture is Some(active) {
    active.close()
    drive.artifact_capture = None
  }
  if drive.artifacts is Some(artifacts) {
    for index = artifacts.length() - 1; index >= 0; index = index - 1 {
      let selected = artifacts[index]
      selected.capture.close()
    }
    drive.artifacts = None
  }
  true
}

///|
fn retain_original_mock_effect_inputs(
  original : MockEffectJournalObservationOriginal,
  managed : @local_host.ClientInstalledManagedRun,
  compute : StoredMockEffectCompute,
) -> Result[@strategy.CapturedEffectInputs, Int] {
  guard @builtin.configured_local_module(
      @builtin.configured_host_modules(compute.host),
    )
    is Some(installed) &&
    @managed.local_publication_bridge_limits(
      installed,
      @strategy.captured_effect_run_dag(compute.dag),
    )
    is Some(bridge) else {
    return Err(-32)
  }
  let prepared = original.journal.materials.prepared
  let request = original.effect.request
  let plan = original.effect.plan
  let inputs = match
    @local_host.pin_installed_effect_sources(
      managed,
      prepared,
      request,
      plan,
      compute.dag,
      bridge.entries,
    ) {
    Ok(inputs) => inputs
    Err(issue) => return Err(mock_effect_work_issue(issue))
  }
  match
    @local_host.retain_installed_effect_captured_input_inventory(
      managed, prepared, request, plan, inputs,
    ) {
    Ok(_) => Ok(inputs)
    Err(issue) => Err(mock_effect_work_issue(issue))
  }
}

///|
// The result and its dependency pins already belong to this exact Run.
// The selected direct Effect unit has one stage and no imported Result.
fn prepare_original_mock_effect_source_unit(
  managed : @local_host.ClientInstalledManagedRun,
  original : MockEffectJournalObservationOriginal,
  publication : @host.ClientEffectDirectSourcesPublication,
  inputs : @strategy.CapturedEffectInputs,
) -> Result[
  @host.ClientEffectCombinedSourceUnit,
  @local_host.ClientEffectUnitPreparationIssue,
] {
  let materials = original.journal.materials
  let request = original.effect.request
  let prepared = materials.prepared
  guard @strategy.captured_effect_input_at(inputs, 0) is Some(first) else {
    return Err(Run(Unsupported))
  }
  let stage = @strategy.captured_effect_input_stage(first)
  for index in 1..<@strategy.captured_effect_inputs_count(inputs) {
    guard @strategy.captured_effect_input_at(inputs, index) is Some(other) &&
      @strategy.captured_effect_input_stage(other) == stage else {
      return Err(Run(Unsupported))
    }
  }
  let program = @checked.effect_program_static_checked_computation(
    @host.prepared_client_effect_computation_candidate(prepared),
  )
  guard @checked.unit_result_import_count(program, stage) == Some(0) else {
    return Err(Run(Unsupported))
  }
  let invocation = @host.client_effect_direct_sources_publication_invocation(
    publication,
  )
  let observation = @host.client_effect_direct_sources_publication_observation(
    publication,
  )
  guard @publication.resolve_run_local_result_context(
      @host.client_effect_allowed_run_admission(materials.allowed),
      materials.run_definition,
      invocation,
      observation,
    )
    is Ok((_, policy, _)) else {
    return Err(Run(ForeignOriginal))
  }
  let plan = original.effect.plan
  @local_host.rebind_installed_effect_result_retention(
    managed,
    prepared,
    request,
    plan,
    original.journal.retention,
    policy,
    16384,
    1024,
    20,
  ).bind(retention => {
    @local_host.prepare_installed_effect_combined_source_unit(
      managed, plan, request, publication, stage, retention, 16384, 1024, 20,
    )
  })
}

///|
fn fail_original_mock_effect_tasks(
  compute : StoredMockEffectCompute,
  code : Int,
) -> Int {
  compute.attempted = true
  if compute.task_drive is Some(drive) {
    drive.failed = true
  }
  code
}

///|
fn produce_original_mock_effect_work(
  value : Instance,
  record : StoredOriginalMetadata,
) -> Int {
  if record.invoked {
    return -33
  }
  record.invoked = true
  guard record.borrow is Ok(borrow) &&
    @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(wire) &&
    wire.length() == 28 else {
    return -31
  }
  let start = mock_effect_descriptor_field(wire, 0)
  let at = @utf8.decode(wire[4:]) catch { _ => return -31 }
  if value.physical_starts.get(start) is Some({ model_file: Some(_), .. }) {
    if record.kind != MOCK_EFFECT_SOURCE_EVIDENCE_KIND { return -20 }
    return seal_original_portable_model_file_source(value, start, at, record)
  }
  if value.physical_starts.get(start) is Some({ file_managed: Some(_), .. }) {
    if record.kind == MOCK_EFFECT_SOURCE_EVIDENCE_KIND {
      return open_sdk_file_capture_work(value, start, at, record)
    }
    return advance_sdk_file_tasks(value, start, at, record)
  }
  if record.kind == MOCK_EFFECT_SOURCE_EVIDENCE_KIND {
    return seal_original_mock_effect_sources(value, start, at, record)
  }
  let code = advance_original_mock_effect_tasks(value, start, at)
  if code != 0 {
    return code
  }
  let supplied = status(
    @buffers.supply_buffer_output(value.pool, record.slot, b""),
  )
  if supplied == 0 {
    record.produced = true
  }
  supplied
}

///|
fn stop_original_mock_effect_work(start : StoredPhysicalStart) -> Bool {
  guard start.mock_effect_compute is Some(compute) &&
    compute.source_evidence is Some(evidence) else {
    return true
  }
  if compute.task_drive is Some(drive) {
    drive.failed = true
    if drive.tasks is Some(tasks) && !tasks.close() {
      return false
    }
    drive.result = None
    drive.tasks = None
    if @resources.settle_capacity(evidence.ledger, drive.capacity) is Err(_) {
      return false
    }
    compute.task_drive = None
  }
  // Its Source identity aliases must disappear before the original Source Reads.
  // The Common owner's separate Invocation alias still holds the funded scope.
  evidence.publication = None
  true
}

///|
fn retire_original_mock_effect_evidence(start : StoredPhysicalStart) -> Bool {
  if start.mock_effect_compute is Some(compute) &&
    compute.source_evidence is Some(evidence) {
    if compute.task_drive is Some(_) ||
      evidence.publication is Some(_) ||
      @resources.settle_capacity(evidence.ledger, evidence.capacity) is Err(_) {
      return false
    }
  }
  start.mock_effect_compute = None
  true
}
