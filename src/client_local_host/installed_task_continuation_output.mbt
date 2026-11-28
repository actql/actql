///|
pub(all) enum InstalledTaskContinuationOutputIssue {
  ForeignOriginal
  DriverOutputUnavailable
  BindingLimit
  BindingEncoding
  Resource(@resources.LedgerIssue)
  Capture(@strategy.CapturedTaskContinuationIssue)
} derive(Eq, Debug)

///|
/// A live export binding for the original Store owner. The manifest CID
/// binds both canonical components. The callback must transfer the data
/// into funded Store custody before the original borrow ends.
pub struct InstalledTaskContinuationOutput {
  manifest : String
  manifest_cid : String
  relation : @strategy.CapturedContinuationRelation
}

///|
pub fn installed_task_continuation_output_parts(
  value : InstalledTaskContinuationOutput,
) -> (String, String, String, Int, String, Int) {
  (
    value.manifest_cid,
    value.manifest,
    value.relation.relation_wire,
    value.relation.relation_bytes,
    value.relation.schema_wire,
    value.relation.schema_bytes,
  )
}

///|
/// Select the receiver for an authenticated Store manifest. This borrows the
/// original Local sequence; the Store evidence and the funded output decoder
/// still have to prove the occurrence and produce a verified Relation.
pub fn installed_task_continuation_relation_receiver(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  captured : @strategy.CapturedDAG,
  task : Int,
  step_id : String,
  output_port_id : String,
  carrier_cid : String,
) -> (@execution.GeneratedSequence, @pipeline.Target)? {
  guard physical_equal(profile.captured, captured) &&
    profile.start_mode is (PausedEntry | PausedBeforeBreakpoint(_, _, _, _)) &&
    installed_relation_sample_profile_current(owner, profile) &&
    profile.driver_outputs.get(task) is Some((step, port, carrier)) &&
    step == step_id &&
    port == output_port_id &&
    carrier == carrier_cid &&
    owner.source_free_preparation is Some(preparation) &&
    preparation.configuration is Some(configuration) else {
    return None
  }
  let graph = @strategy.captured_dag_graph(captured)
  guard @strategy.graph_task_target(graph, task) is Some(Step(index)) &&
    @local_driver.local_dispatch_preparation_selected_sequence(
      configuration.dispatch,
      graph,
      task,
    )
    is Some(sequence) else {
    return None
  }
  Some((sequence, Step(index)))
}

///|
let installed_task_continuation_manifest_nodes = 20

///|
fn installed_task_continuation_manifest_backing(bytes : Int) -> Int64? {
  guard @encode.text_writer_construction_inventory(
      bytes, installed_task_continuation_manifest_nodes, 3,
    )
    is Some(writer) else {
    return None
  }
  // The closed writer frames, ordered key cursor, SHA state and
  // output digest coexist with the final manifest in the scoped visit.
  @execution.preparation_representation_cost({
    record_headers: writer.record_headers + 64L,
    reference_slots: writer.reference_slots + 128L,
    scalar_words: writer.scalar_words + 256L,
    owned_utf16_units: writer.owned_utf16_units + 128L,
    owned_wire_bytes: 256L,
  })
}

///|
fn write_continuation_manifest_field(
  writer : @encode.Writer,
  name : String,
  value : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.ordered_key(writer, name)
  @encode.string_value(writer, value)
}

///|
fn installed_task_continuation_manifest(
  profile : ClientCheckedRelationSampleProfile,
  namespace_id : String,
  port : (String, String, String),
  value : @strategy.CapturedContinuationRelation,
  bytes : Int,
) -> InstalledTaskContinuationOutput? {
  let (step, port_id, carrier) = port
  let compiled = @publication_host.client_compiled_run_plan(profile.compiled)
  let manifest = try {
    let writer = @encode.writer(
      bytes, installed_task_continuation_manifest_nodes, 3,
    )
    @encode.begin_ordered_object(writer)
    write_continuation_manifest_field(
      writer,
      "attempt_sequence",
      value.attempt.to_string(),
    )
    write_continuation_manifest_field(writer, "carrier_contract_cid", carrier)
    write_continuation_manifest_field(
      writer,
      "committed_generation",
      value.committed_generation.to_string(),
    )
    write_continuation_manifest_field(
      writer,
      "compiled_plan_cid",
      @publication.publication_contract_identity(compiled),
    )
    write_continuation_manifest_field(
      writer,
      "control_revision",
      value.pause_revision.to_string(),
    )
    write_continuation_manifest_field(
      writer,
      "logical_map_cid",
      profile.logical_map_cid,
    )
    write_continuation_manifest_field(writer, "output_port_id", port_id)
    write_continuation_manifest_field(
      writer,
      "relation_bytes",
      value.relation_bytes.to_string(),
    )
    write_continuation_manifest_field(
      writer,
      "relation_cid",
      value.relation_cid,
    )
    write_continuation_manifest_field(writer, "rows", value.rows.to_string())
    @encode.ordered_key(writer, "run_ref")
    @encode.begin_ordered_object(writer)
    write_continuation_manifest_field(
      writer,
      "authorityScopeCid",
      @publication_host.client_request_authority_scope_cid(profile.request),
    )
    write_continuation_manifest_field(writer, "namespaceId", namespace_id)
    write_continuation_manifest_field(
      writer,
      "runDefinitionCid",
      @publication.publication_contract_identity(profile.definition),
    )
    @encode.end_object(writer)
    write_continuation_manifest_field(
      writer,
      "schema_bytes",
      value.schema_bytes.to_string(),
    )
    write_continuation_manifest_field(writer, "schema_cid", value.schema_cid)
    write_continuation_manifest_field(
      writer,
      "start_revision",
      value.start_revision.to_string(),
    )
    write_continuation_manifest_field(writer, "step_id", step)
    write_continuation_manifest_field(
      writer, "version", "actql-debug-continuation-output/0.1",
    )
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return None
  }
  guard @sha.text_hex(manifest) is Ok(hash) else { return None }
  Some({ manifest, manifest_cid: "sha256:" + hash, relation: value, })
}

///|
/// Bind this complete original Relation to the installed original Run,
/// checked compiler output port, and acknowledged pause on the same Run.
/// The data remains borrowed; an asynchronous Store handoff needs its own
/// funded ownership, and the manifest conveys no recovery permission.
pub fn[T] with_installed_task_continuation_output(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  cut : @strategy.CapturedTaskContinuation,
  task : Int,
  completed : @execution.ManagedCompletedOutput[T],
  original : @execution.CompletedOutput,
  require_current : () -> Bool,
  limits : @strategy.CapturedContinuationRelationLimits,
  consume : (InstalledTaskContinuationOutput, () -> Bool) -> Bool,
) -> Result[Unit, InstalledTaskContinuationOutputIssue] {
  with_installed_task_continuation_relation(
    owner,
    profile,
    cut,
    task,
    require_current,
    consume,
    (current, visit, backing) => {
      @strategy.with_captured_task_continuation_relation(
        profile.captured,
        cut,
        task,
        completed,
        original,
        current,
        limits,
        visit,
        handoff_bytes=backing,
      )
    },
  )
}

///|
fn with_installed_task_continuation_relation(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  cut : @strategy.CapturedTaskContinuation,
  task : Int,
  require_current : () -> Bool,
  consume : (InstalledTaskContinuationOutput, () -> Bool) -> Bool,
  read : (
    () -> Bool,
    (@strategy.CapturedContinuationRelation, () -> Bool) -> Bool,
    Int64,
  ) -> Result[Unit, @strategy.CapturedTaskContinuationIssue],
) -> Result[Unit, InstalledTaskContinuationOutputIssue] {
  let run = profile.captured
  guard @strategy.captured_task_continuation_position(run, cut)
    is Some((start, revision, generation, _, _)) &&
    installed_debug_task_control(profile, owner, run, start) is Ok(_) &&
    profile.driver_outputs.get(task) is Some(port) &&
    @publication.run_definition_namespace(profile.definition)
    is Some(namespace_id) else {
    return Err(ForeignOriginal)
  }
  // The closed manifest is at most 1107 ASCII bytes without the namespace:
  // nine 71-byte CIDs, seven decimal Ints of up to 10 digits, and 398 bytes
  // of keys, punctuation and the version. Bound namespace escaping separately.
  let fixed_bytes = 1107
  if namespace_id.length() > (131072 - fixed_bytes) / 6 {
    return Err(BindingLimit)
  }
  let bytes = fixed_bytes + 6 * namespace_id.length()
  guard installed_task_continuation_manifest_backing(bytes) is Some(backing) else {
    return Err(BindingLimit)
  }
  let ledger = @strategy.captured_dag_ledger(run)
  let current = () => {
    require_current() &&
    installed_debug_task_control(profile, owner, run, start) is Ok(_) &&
    @strategy.captured_task_continuation_position(run, cut)
    is Some((actual_start, actual_revision, actual_generation, _, _)) &&
    actual_start == start &&
    actual_revision == revision &&
    actual_generation == generation
  }
  let issue : Ref[InstalledTaskContinuationOutputIssue?] = Ref(None)
  let captured = read(
    current,
    (value, live) => {
      if @resources.charge_planning(ledger, 3 * bytes) is Err(failure) {
        issue.val = Some(Resource(failure))
        return false
      }
      if !live() {
        return false
      }
      guard installed_task_continuation_manifest(
          profile, namespace_id, port, value, bytes,
        )
        is Some(manifest) else {
        issue.val = Some(BindingEncoding)
        return false
      }
      live() && consume(manifest, live)
    },
    backing,
  )
  match captured {
    Err(OutputRefused) if issue.val is Some(failure) => Err(failure)
    Err(failure) => Err(Capture(failure))
    Ok(_) => Ok(())
  }
}

///|
/// Export through the same retained task driver that owns the original
/// completion and its current cell projection. A closed or foreign driver
/// cannot substitute an output, even if its transport bytes are identical.
pub fn[T] with_installed_task_continuation_driver_output(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  cut : @strategy.CapturedTaskContinuation,
  task : Int,
  operations : @local_driver.LocalManagedDispatchOperations[T],
  require_current : () -> Bool,
  limits : @strategy.CapturedContinuationRelationLimits,
  consume : (InstalledTaskContinuationOutput, () -> Bool) -> Bool,
) -> Result[Unit, InstalledTaskContinuationOutputIssue] {
  let result : Ref[Result[Unit, InstalledTaskContinuationOutputIssue]] = Ref(
    Err(DriverOutputUnavailable),
  )
  let held = @local_driver.with_local_managed_continuation_relation(
    operations,
    (completed, original, active) => {
      result.val = with_installed_task_continuation_output(
        owner,
        profile,
        cut,
        task,
        completed,
        original,
        () => active() && require_current(),
        limits,
        consume,
      )
    },
  )
  match result.val {
    Ok(_) if !held => Err(DriverOutputUnavailable)
    value => value
  }
}

///|
/// Read one same-owner pause cut and deliver each completed occurrence in
/// task order. An occurrence required by unfinished work or Results borrows
/// the original Driver or the restored DAG's typed cells. Each output borrow
/// end before this returns. Success conveys no Store or Journal adoption.
pub fn[T] visit_installed_task_continuation_cut(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  captured : @strategy.CapturedDAG,
  start_revision : Int,
  control_revision : Int,
  committed_generation : Int,
  step_id : String,
  next_step_id : String,
  max_work : Int,
  limits : @strategy.CapturedContinuationRelationLimits,
  require_current : () -> Bool,
  driver : (Int) -> @local_driver.LocalManagedDispatchOperations[T]?,
  visit : (Int, Int, Int, InstalledTaskContinuationOutput?, () -> Bool) -> Bool,
  reuse? : ((Int, Int, Int, () -> Bool) -> Bool)? = None,
) -> Result[Unit, InstalledTaskContinuationOutputIssue] {
  guard installed_debug_task_control(profile, owner, captured, start_revision)
    is Ok(hooks) &&
    require_current() &&
    installed_relation_sample_debug_task_pause(
      profile, owner, captured, start_revision,
    )
    is Ok((revision, completed_step, next_step, generation)) &&
    revision == control_revision &&
    generation == committed_generation &&
    step_id == completed_step &&
    next_step_id == next_step else {
    return Err(ForeignOriginal)
  }
  let tasks = @strategy.graph_task_count(@strategy.captured_dag_graph(captured))
  if max_work < tasks {
    return Err(Capture(WorkLimit))
  }
  // Bridge arguments, visit parameters and the current/revocation controls.
  // One output route and visitor coexist with the cut. Relation material
  // and the Store's owned copies quote separately.
  let visitor_backing = @execution.preparation_representation_cost({
    record_headers: 22L,
    reference_slots: 44L,
    scalar_words: 31L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let cut = match
    @strategy.read_captured_task_continuation(
      captured,
      hooks,
      control_revision,
      committed_generation,
      max_work - tasks,
      visitor_backing~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let ledger = @strategy.captured_dag_ledger(captured)
  let result = match @resources.charge_planning(ledger, tasks) {
    Err(issue) => Err(InstalledTaskContinuationOutputIssue::Resource(issue))
    Ok(_) =>
      visit_installed_task_continuation_occurrences(
        owner, profile, captured, cut, limits, require_current, driver, visit, reuse,
      )
  }
  match @strategy.return_captured_task_continuation(cut) {
    Err(issue) if result is Ok(_) => Err(Capture(@strategy.Boundary(issue)))
    _ => result
  }
}

///|
fn[T] visit_installed_task_continuation_occurrences(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  captured : @strategy.CapturedDAG,
  cut : @strategy.CapturedTaskContinuation,
  limits : @strategy.CapturedContinuationRelationLimits,
  require_current : () -> Bool,
  driver : (Int) -> @local_driver.LocalManagedDispatchOperations[T]?,
  visit : (Int, Int, Int, InstalledTaskContinuationOutput?, () -> Bool) -> Bool,
  reuse : ((Int, Int, Int, () -> Bool) -> Bool)?,
) -> Result[Unit, InstalledTaskContinuationOutputIssue] {
  guard @strategy.captured_task_continuation_position(captured, cut)
    is Some(position) else {
    return Err(Capture(StalePause))
  }
  let active : Ref[(() -> Bool)?] = Ref(
    Some(() => {
      require_current() &&
      installed_debug_task_control(profile, owner, captured, position.0)
      is Ok(_) &&
      @strategy.captured_task_continuation_position(captured, cut) ==
      Some(position)
    }),
  )
  let current = () => {
    match active.val {
      Some(check) => check()
      None => false
    }
  }
  defer {
    active.val = None
  }
  for task in 0..<position.4 {
    if !current() {
      return Err(Capture(StalePause))
    }
    let completion = @strategy.captured_task_continuation_completion(
      captured, cut, task,
    )
    guard completion is Some((generation, attempt, keep)) else { continue }
    if !keep {
      let accepted = visit(task, generation, attempt, None, current)
      if !current() {
        return Err(Capture(StalePause))
      }
      if !accepted {
        return Err(Capture(OutputRefused))
      }
      continue
    }
    // The Host can select its already durable output for this exact needed
    // occurrence. It must authenticate the holding before adopting the new cut.
    let reused = match reuse {
      Some(accept) => accept(task, generation, attempt, current)
      None => false
    }
    if !current() {
      return Err(Capture(StalePause))
    }
    if reused {
      continue
    }
    let operations = driver(task)
    if !current() {
      return Err(Capture(StalePause))
    }
    let consume = (output, live) => {
      visit(task, generation, attempt, Some(output), live)
    }
    let result = match operations {
      Some(original) =>
        with_installed_task_continuation_driver_output(
          owner, profile, cut, task, original, current, limits, consume,
        )
      None =>
        with_installed_task_continuation_relation(
          owner,
          profile,
          cut,
          task,
          current,
          consume,
          (current, read, backing) => {
            @strategy.with_captured_task_continuation_materialized_relation(
              captured,
              cut,
              task,
              current,
              limits,
              read,
              handoff_bytes=backing,
            )
          },
        )
    }
    if result is Err(issue) {
      return Err(issue)
    }
  }
  if current() {
    Ok(())
  } else {
    Err(Capture(StalePause))
  }
}

///|
/// The installed Host's owned staging and Journal scratch stay on the same
/// paused Run's Ledger after the synchronous output visitor returns.
pub struct InstalledTaskContinuationCapacity {
  owner : ClientInstalledManagedRun
  profile : ClientCheckedRelationSampleProfile
  captured : @strategy.CapturedDAG
  start_revision : Int
  control_revision : Int
  generation : Int
  ledger : @resources.Ledger
  reservation : @resources.CapacityReservation
}

///|
fn installed_task_continuation_capacity_current(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  captured : @strategy.CapturedDAG,
  start_revision : Int,
  control_revision : Int,
  generation : Int,
) -> Bool {
  match
    installed_relation_sample_debug_task_pause(
      profile, owner, captured, start_revision,
    ) {
    Ok((revision, _, _, committed)) =>
      revision == control_revision && committed == generation
    Err(_) => false
  }
}

///|
pub fn reserve_installed_task_continuation_capacity(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  captured : @strategy.CapturedDAG,
  start_revision : Int,
  control_revision : Int,
  generation : Int,
  retained : Int64,
  execution : Int64,
) -> Result[
  InstalledTaskContinuationCapacity,
  InstalledTaskContinuationOutputIssue,
] {
  guard installed_task_continuation_capacity_current(
    owner, profile, captured, start_revision, control_revision, generation,
  ) else {
    return Err(ForeignOriginal)
  }
  let ledger = @strategy.captured_dag_ledger(captured)
  let reservation = match
    @resources.reserve_capacity(ledger, retained, execution) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  Ok({
    owner,
    profile,
    captured,
    start_revision,
    control_revision,
    generation,
    ledger,
    reservation,
  })
}

///|
pub fn grow_installed_task_continuation_capacity(
  capacity : InstalledTaskContinuationCapacity,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, InstalledTaskContinuationOutputIssue] {
  guard installed_task_continuation_capacity_current(
    capacity.owner,
    capacity.profile,
    capacity.captured,
    capacity.start_revision,
    capacity.control_revision,
    capacity.generation,
  ) else {
    return Err(ForeignOriginal)
  }
  @resources.grow_capacity_reservation(
    capacity.ledger,
    capacity.reservation,
    retained,
    execution,
  ).map_err(issue => InstalledTaskContinuationOutputIssue::Resource(issue))
}

///|
/// Settlement returns the same lease. The Host still owns physical Store
/// cleanup on every failure and can return scratch after the pause goes stale.
pub fn return_installed_task_continuation_capacity(
  capacity : InstalledTaskContinuationCapacity,
) -> Result[Unit, InstalledTaskContinuationOutputIssue] {
  @resources.settle_capacity(capacity.ledger, capacity.reservation).map_err(issue => {
    InstalledTaskContinuationOutputIssue::Resource(issue)
  })
}

///|
/// Obtain a Store lookup coordinate from the checked receiving task. The
/// original cut supplies the Run and occurrence; this supplies the exact
/// compiled Plan, Map and port without rebuilding or interpreting raw SQL.
pub fn installed_task_continuation_store_port(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  captured : @strategy.CapturedDAG,
  task : Int,
) -> (String, String, String, String, String)? {
  guard profile.driver_outputs.get(task) is Some((step, port, carrier)) &&
    installed_task_continuation_relation_receiver(
      owner, profile, captured, task, step, port, carrier,
    )
    is Some(_) else {
    return None
  }
  Some(
    (
      @publication.publication_contract_identity(
        @publication_host.client_compiled_run_plan(profile.compiled),
      ),
      profile.logical_map_cid,
      step,
      port,
      carrier,
    ),
  )
}
