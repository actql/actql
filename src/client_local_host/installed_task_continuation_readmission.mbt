///|
/// A separately funded decoded output that can later be moved into the
/// receiving graph. The holder never grants authority to accept a command.
struct InstalledRestoredTaskRelation {
  owner : ClientInstalledManagedRun
  captured : @strategy.CapturedDAG
  task : Int
  occurrence : InstalledRestoredTaskOccurrence
  prepared : @execution.CompletionPreparation
  target : @pipeline.Target
  expected : @execution.RetainedLogicalRelationIdentity
  limits : @strategy.CapturedContinuationRelationLimits
  backing : @resources.CapacityReservation
  kept : Int64
  total : Int64
  decode_work : Int
  retained : Ref[@execution.AdmittedOutputRows?]
  mut receiving : Bool
  mut attempted : Bool
  mut attached : Bool
  mut output : @execution.CompletedOutput?
}

///|
pub(all) enum InstalledTaskContinuationReadIssue {
  ForeignOriginal
  InvalidExtent
  Capacity
  InvalidRelation
  Resource(@resources.LedgerIssue)
  Work(@resources.LedgerIssue)
  Output(@execution.TrustedOutputIssue)
  Cut(@strategy.CapturedTaskContinuationIssue)
}

///|
pub(all) struct InstalledRestoredTaskOccurrence {
  start_revision : Int
  control_revision : Int
  generation : Int
  attempt : Int
} derive(Eq)

///|
/// The Store read funds its own buffers. This quotation covers the separate
/// preserving parser/index, typed row construction and checked identity on
/// the original receiving Run. It excludes the caller's stored wire, graph
/// slots and Store lifetime. Quoting does not inspect the Relation text.
pub fn installed_task_continuation_relation_backing(
  expected : @execution.RetainedLogicalRelationIdentity,
  width : Int,
  limits : @strategy.CapturedContinuationRelationLimits,
) -> (Int64, Int64, Int)? {
  let bytes = expected.relation_bytes
  let nodes = Int::min(bytes, limits.wire.max_nodes)
  let depth = Int::min(nodes, limits.wire.max_depth)
  if bytes <= 0 ||
    bytes >= 2147483647 ||
    bytes > limits.wire.max_bytes ||
    width < 0 ||
    width > limits.wire.max_columns ||
    expected.rows < 0 ||
    expected.rows > limits.rows ||
    expected.rows > nodes ||
    expected.schema_bytes <= 0 ||
    expected.schema_bytes > limits.schema.max_bytes ||
    width > limits.schema.max_fields ||
    nodes <= 0 ||
    depth <= 0 ||
    depth > 64 ||
    limits.work < 0 ||
    limits.workspace_bytes <= 0L {
    return None
  }
  let schema_nodes = Int::min(expected.schema_bytes, limits.schema.max_nodes)
  let schema_depth = Int::min(schema_nodes, limits.schema.max_depth)
  guard @decode.preserving_json_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(parser) &&
    @encode.hash_writer_construction_inventory(nodes, depth) is Some(relation) &&
    @encode.hash_writer_construction_inventory(schema_nodes, schema_depth)
    is Some(schema) else {
    return None
  }
  let n = nodes.to_int64()
  let rows = expected.rows.to_int64()
  let columns = width.to_int64()
  // Rows may have absent fields, so their dense storage still uses the full
  // width. Each present node can own a Value and a nested collection item.
  // Bound the typed tree and its backing before expanding any row.
  let cells = rows * columns
  if cells > 2147483647L {
    return None
  }
  // Fixed retention also covers the single adopted task resource entry,
  // empty parent list, and release closure which survive the cut workspace.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 42L + 12L * n + 6L * rows + 3L * cells,
    reference_slots: 80L + 24L * n + 6L * rows + 8L * cells + 8L * columns,
    scalar_words: 40L + 18L * n + 2L * rows + 4L * cells + 4L * columns,
    owned_utf16_units: 4L * bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  // Typed admission keeps the whole preserving parser/index and at most
  // one active cell traversal with its dynamic stack, checked/refusal
  // carriers, and object field/key indexing. Count both hash frames even
  // though each emitter drops its own sink before the other can start.
  let workspace : @execution.PreparationRepresentationUnits = {
    record_headers: parser.record_headers +
    relation.record_headers +
    schema.record_headers +
    96L +
    32L * n +
    4L * columns,
    reference_slots: parser.reference_slots +
    relation.reference_slots +
    schema.reference_slots +
    192L +
    64L * n +
    16L * columns,
    scalar_words: parser.scalar_words +
    relation.scalar_words +
    schema.scalar_words +
    128L +
    24L * n +
    16L * columns,
    owned_utf16_units: parser.owned_utf16_units +
    relation.owned_utf16_units +
    schema.owned_utf16_units +
    8L * bytes.to_int64(),
    owned_wire_bytes: relation.owned_wire_bytes +
    schema.owned_wire_bytes +
    bytes.to_int64(),
  }
  // Strict UTF-16 preflight, byte encode/decode and parse, indexed admission,
  // checked row visits including missing fields, and value traversal. The
  // subsequent canonical schema and row passes debit their own actual work.
  let decode_work = 8L * bytes.to_int64() +
    24L * n +
    8L * cells +
    4L * rows +
    1L
  guard decode_work <= limits.work.to_int64() &&
    @execution.preparation_representation_cost(retained) is Some(kept) &&
    @execution.preparation_representation_cost(workspace) is Some(scratch) &&
    @execution.checked_preparation_add_product(kept, scratch, 1L) is Some(total) &&
    total <= limits.workspace_bytes else {
    return None
  }
  Some((kept, total, decode_work.to_int()))
}

///|
fn read_installed_restored_relation_rows(
  prepared : @execution.CompletionPreparation,
  target : @pipeline.Target,
  expected : @execution.RetainedLogicalRelationIdentity,
  relation : String,
  limits : @strategy.CapturedContinuationRelationLimits,
  current : () -> Bool,
) -> @execution.AdmittedOutputRows? {
  let bytes = expected.relation_bytes
  let nodes = Int::min(bytes, limits.wire.max_nodes)
  let depth = Int::min(nodes, limits.wire.max_depth)
  guard @scalar.admit_utf8_length(relation, bytes) == Ok(bytes) &&
    @source.parse_json_bytes_preserving(
      @utf8.encode(relation),
      { max_input_bytes: bytes, max_nodes: nodes, max_depth: depth, },
      source_path="<debug-continuation>",
    )
    is Ok(node) &&
    @decode.admit(node, {
      max_nodes: nodes,
      max_depth: depth,
      max_string_bytes: bytes,
      max_total_string_bytes: bytes,
    })
    is Ok(cursor) &&
    @execution.read_retained_logical_relation(
      @execution.completion_preparation_owner(prepared),
      target,
      cursor,
      expected.rows,
      {
        max_bytes: bytes,
        max_nodes: nodes,
        max_depth: depth,
        max_text_bytes: bytes,
      },
      limits.values,
      current,
    )
    is Ok(rows) else {
    return None
  }
  Some(rows)
}

///|
/// Reserve one original output before decoding. The opaque custody is returned
/// even when the subsequent import refuses, so its owner can retry cleanup.
pub fn reserve_installed_task_continuation_relation(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  captured : @strategy.CapturedDAG,
  task : Int,
  port : (String, String, String),
  occurrence : InstalledRestoredTaskOccurrence,
  expected : @execution.RetainedLogicalRelationIdentity,
  limits : @strategy.CapturedContinuationRelationLimits,
  max_execution : Int64,
  require_current : () -> Bool,
) -> Result[InstalledRestoredTaskRelation, InstalledTaskContinuationReadIssue] {
  let (step, output_port, carrier) = port
  guard occurrence.start_revision > 0 &&
    occurrence.control_revision >= 2 &&
    occurrence.generation > 0 &&
    occurrence.attempt >= occurrence.generation &&
    require_current() &&
    installed_task_continuation_relation_receiver(
      owner, profile, captured, task, step, output_port, carrier,
    )
    is Some((sequence, target)) else {
    return Err(ForeignOriginal)
  }
  let ledger = @strategy.captured_dag_ledger(captured)
  let prepared = @execution.generated_completion_preparation(sequence)
  let original = @execution.completion_preparation_owner(prepared)
  guard @lower.preparation_schema_at(@lower.bound_preparation(original), target)
    is Some(schema) &&
    installed_task_continuation_relation_backing(
      expected,
      @schema.field_count(schema),
      limits,
    )
    is Some((kept, total, decode_work)) else {
    return Err(InvalidExtent)
  }
  if total > max_execution {
    return Err(Capacity)
  }
  let backing = match @resources.reserve_capacity(ledger, kept, total) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  Ok({
    owner,
    captured,
    task,
    occurrence,
    prepared,
    target,
    expected,
    limits,
    backing,
    kept,
    total,
    decode_work,
    retained: Ref(None),
    receiving: false,
    attempted: false,
    attached: false,
    output: None,
  })
}

///|
fn installed_restored_task_relation_available(
  value : InstalledRestoredTaskRelation,
) -> Bool {
  let owner = value.owner
  let ledger = @strategy.captured_dag_ledger(value.captured)
  !owner.source_free_opening &&
  owner.source_free_captured is Some(run) &&
  physical_equal(run, value.captured) &&
  owner.ledger is Some(actual) &&
  physical_equal(actual, ledger) &&
  @resources.capacity_reservation_covers(
    ledger,
    value.backing,
    value.kept,
    value.kept,
  )
}

///|
/// Decode the reserved output once. The Store guard covers this synchronous
/// import, and the receiving Run's custody covers later uses after the
/// original pause is consumed.
pub fn readmit_installed_task_continuation_relation(
  value : InstalledRestoredTaskRelation,
  cut : InstalledRestoredTaskCut,
  relation : String,
  require_current : () -> Bool,
) -> Result[Unit, InstalledTaskContinuationReadIssue] {
  guard physical_equal(value.owner, cut.owner) &&
    physical_equal(value.captured, cut.captured) &&
    installed_relation_sample_profile_current(cut.owner, cut.profile) &&
    !cut.applying &&
    !cut.installed &&
    @resources.capacity_reservation_open(cut.backing) else {
    return Err(ForeignOriginal)
  }
  cut.applying = true
  defer {
    cut.applying = false
  }
  if !require_current() {
    return Err(ForeignOriginal)
  }
  let work = match cut.work {
    Some(original) => {
      if @resources.resume_preparation_phase_work_continuation64(original)
        is Err(_) {
        return Err(ForeignOriginal)
      }
      original
    }
    None => {
      let original = match
        begin_installed_task_continuation_read_work(
          cut.owner,
          cut.captured,
          cut.maximum_work,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      cut.work = Some(original)
      original
    }
  }
  let result = read_installed_task_continuation_relation(
    value, work, relation, require_current,
  )
  // The next physical Store read can await. Park the original Work receipt
  // after the constructor unwinds, with its cumulative consumption intact.
  let returned = @resources.return_preparation_phase_work_continuation64(work)
  match result {
    Err(issue) => Err(issue)
    Ok(_) =>
      returned.map_err(_ => InstalledTaskContinuationReadIssue::ForeignOriginal)
  }
}

///|
fn begin_installed_task_continuation_read_work(
  owner : ClientInstalledManagedRun,
  captured : @strategy.CapturedDAG,
  maximum : Int64,
) -> Result[
  @resources.PreparationPhaseWorkContinuation64,
  InstalledTaskContinuationReadIssue,
] {
  guard owner.preparation is Some(PureManaged(admission, prepared)) else {
    return Err(ForeignOriginal)
  }
  // Readmission proves the stored output bytes. The same receiving Run's
  // preparation owns this work; its durable dispatch counter is for graph
  // selection and execution. This source-free path has no Effect proof phase.
  @resources.begin_prepared_run_publication_work(
    admission,
    prepared,
    @strategy.captured_dag_ledger(captured),
    maximum,
  ).map_err(_ => InstalledTaskContinuationReadIssue::ForeignOriginal)
}

///|
fn read_installed_task_continuation_relation(
  value : InstalledRestoredTaskRelation,
  work : @resources.PreparationPhaseWorkContinuation64,
  relation : String,
  require_current : () -> Bool,
) -> Result[Unit, InstalledTaskContinuationReadIssue] {
  let ledger = @strategy.captured_dag_ledger(value.captured)
  let funded = () => {
    installed_restored_task_relation_available(value) &&
    @resources.capacity_reservation_covers(
      ledger,
      value.backing,
      value.kept,
      value.total,
    )
  }
  if value.attempted || !funded() {
    return Err(ForeignOriginal)
  }
  value.attempted = true
  value.receiving = true
  defer {
    value.receiving = false
  }
  let current = () => funded() && require_current() && funded()
  if !current() {
    return Err(ForeignOriginal)
  }
  if @resources.spend_preparation_phase_work_continuation64(
      work,
      value.decode_work.to_int64(),
    )
    is Err(_) {
    return Err(Work(PlanningLimit))
  }
  guard current() &&
    read_installed_restored_relation_rows(
      value.prepared,
      value.target,
      value.expected,
      relation,
      value.limits,
      current,
    )
    is Some(rows) else {
    return Err(if current() { InvalidRelation } else { ForeignOriginal })
  }
  let retained = value.retained
  retained.val = Some(rows)
  let mut remaining = value.limits.work - value.decode_work
  let issue : Ref[@resources.LedgerIssue?] = Ref(None)
  let spend = fn(units : Int) {
    if units < 0 || units > remaining || !current() {
      return false
    }
    match
      @resources.spend_preparation_phase_work_continuation64(
        work,
        units.to_int64(),
      ) {
      Err(_) => {
        issue.val = Some(PlanningLimit)
        false
      }
      Ok(_) => {
        remaining -= units
        current()
      }
    }
  }
  let backing = value.backing
  let kept = value.kept
  let verified = fn(original : Ref[@execution.AdmittedOutputRows?]) {
    if @resources.capacity_reservation_covers(ledger, backing, kept, kept) {
      original.val
    } else {
      None
    }
  }
  let result : Result[Unit, InstalledTaskContinuationReadIssue] = match
    @execution.readmit_trusted_retained_relation(
      value.prepared,
      value.target,
      value.expected,
      value.limits.wire,
      value.limits.schema,
      spend,
      retained,
      verified,
    ) {
    Ok(output) if current() => {
      value.output = Some(output)
      Ok(())
    }
    Err(_) if issue.val is Some(failure) => Err(Work(failure))
    Err(failure) if current() => Err(Output(failure))
    _ => Err(ForeignOriginal)
  }
  if result is Err(_) {
    retained.val = None
  }
  result
}

///|
/// Only the receiving graph can use this proof and only for its exact task.
/// Cell access remains fenced by the original reservation through cleanup.
fn installed_restored_task_relation_output(
  value : InstalledRestoredTaskRelation,
  captured : @strategy.CapturedDAG,
  task : Int,
) -> @execution.CompletedOutput? {
  guard physical_equal(value.captured, captured) &&
    value.task == task &&
    !value.receiving &&
    installed_restored_task_relation_available(value) else {
    return None
  }
  value.output
}

///|
/// Return the exact reservation once the caller has stopped its borrowers.
/// A resource refusal leaves the original custody available for cleanup.
pub fn return_installed_restored_task_relation(
  value : InstalledRestoredTaskRelation,
) -> Result[Unit, InstalledTaskContinuationReadIssue] {
  if value.attached {
    return Err(ForeignOriginal)
  }
  release_installed_restored_task_relation(value)
}

///|
fn release_installed_restored_task_relation(
  value : InstalledRestoredTaskRelation,
) -> Result[Unit, InstalledTaskContinuationReadIssue] {
  if value.receiving {
    return Err(ForeignOriginal)
  }
  value.attempted = true
  value.output = None
  value.retained.val = None
  @resources.settle_capacity(
    @strategy.captured_dag_ledger(value.captured),
    value.backing,
  ).map_err(issue => InstalledTaskContinuationReadIssue::Resource(issue))
}

///|
/// Metadata workspace for an original stopped cut. The output holders remain
/// separately funded and are transferred only when exact DAG restoration wins.
struct InstalledRestoredTaskCut {
  owner : ClientInstalledManagedRun
  profile : ClientCheckedRelationSampleProfile
  captured : @strategy.CapturedDAG
  backing : @resources.CapacityReservation
  maximum_work : Int64
  mut work : @resources.PreparationPhaseWorkContinuation64?
  mut applying : Bool
  mut installed : Bool
}

///|
pub fn reserve_installed_restored_task_cut(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  captured : @strategy.CapturedDAG,
  maximum_work : Int,
) -> Result[InstalledRestoredTaskCut, InstalledTaskContinuationReadIssue] {
  let ledger = @strategy.captured_dag_ledger(captured)
  guard maximum_work > 0 &&
    profile.start_mode is (PausedEntry | PausedBeforeBreakpoint(_, _, _, _)) &&
    physical_equal(profile.captured, captured) &&
    installed_relation_sample_profile_current(owner, profile) &&
    @resources.restored_ledger_attempts(ledger) is Some(_) &&
    @strategy.captured_task_boundary_hooks(captured) is Some(hooks) &&
    @strategy.captured_task_control_state(captured, hooks) is Ok((0, Paused)) else {
    return Err(ForeignOriginal)
  }
  let tasks = @strategy.graph_task_count(@strategy.captured_dag_graph(captured))
  let proof = @resources.preparation_phase_work_continuation64_construction_inventory()
  let proof_bytes = @execution.preparation_representation_cost({
    record_headers: proof.record_headers + 1L,
    reference_slots: proof.reference_slots + 1L,
    scalar_words: proof.scalar_words + 2L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let bytes = @strategy.restored_task_cut_backing(tasks) + proof_bytes
  let backing = match @resources.reserve_capacity(ledger, bytes, bytes) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  Ok({
    owner,
    profile,
    captured,
    backing,
    maximum_work: maximum_work.to_int64(),
    work: None,
    applying: false,
    installed: false,
  })
}

///|
/// One original task entry from the retained Journal cut. A materialized row
/// body must already hold its Store-verified occurrence on the same setup.
pub(all) struct InstalledRestoredTaskCutEntry {
  task : Int
  generation : Int
  attempt : Int
  relation : InstalledRestoredTaskRelation?
}

///|
/// Install the original stopped position and its independently backed outputs.
/// The existing Debug command boundary will later decide when this DAG can run.
pub fn install_restored_task_cut(
  cut : InstalledRestoredTaskCut,
  start_revision : Int,
  control_revision : Int,
  generation : Int,
  step_id : String,
  next_step_id : String,
  original : ReadOnlyArray[InstalledRestoredTaskCutEntry],
  current : () -> Bool,
) -> Result[Unit, InstalledTaskContinuationReadIssue] {
  if cut.applying ||
    cut.installed ||
    !@resources.capacity_reservation_open(cut.backing) {
    return Err(ForeignOriginal)
  }
  cut.applying = true
  defer {
    cut.applying = false
  }
  let captured = cut.captured
  let ledger = @strategy.captured_dag_ledger(captured)
  let tasks = @strategy.graph_task_count(@strategy.captured_dag_graph(captured))
  guard generation > 0 &&
    generation < tasks &&
    original.length() == generation &&
    physical_equal(cut.profile.captured, captured) &&
    installed_relation_sample_profile_current(cut.owner, cut.profile) &&
    @strategy.captured_task_boundary_hooks(captured) is Some(hooks) &&
    current() &&
    @strategy.captured_task_control_state(captured, hooks) is Ok((0, Paused)) else {
    return Err(ForeignOriginal)
  }
  // Bind the independently selected original Step IDs to the task order.
  // Fund the one forward scan and per-Task correspondence before visiting.
  if tasks > (2147483647 - 1) / 10 {
    return Err(InvalidExtent)
  }
  match @resources.charge_planning(ledger, 1 + 10 * tasks) {
    Ok(_) => ()
    Err(issue) => return Err(Work(issue))
  }
  let mut completed_task = -1
  let mut next_task = -1
  for task in 0..<tasks {
    if cut.profile.driver_outputs.get(task) is Some((step, _, _)) {
      if step == step_id {
        if completed_task >= 0 {
          return Err(ForeignOriginal)
        }
        completed_task = task
      }
      if step == next_step_id {
        if next_task >= 0 {
          return Err(ForeignOriginal)
        }
        next_task = task
      }
    }
  }
  if completed_task < 0 ||
    next_task < 0 ||
    completed_task == next_task ||
    !current() {
    return Err(ForeignOriginal)
  }
  let completed : Array[@strategy.RestoredTaskOccurrence] = []
  let mut previous = -1
  for entry in original {
    if entry.task <= previous || entry.task >= tasks {
      return Err(ForeignOriginal)
    }
    previous = entry.task
    match entry.relation {
      None =>
        completed.push({
          task: entry.task,
          generation: entry.generation,
          attempt: entry.attempt,
          output: None,
          retire: None,
        })
      Some(relation) => {
        guard !relation.attached &&
          physical_equal(cut.owner, relation.owner) &&
          relation.occurrence ==
          {
            start_revision,
            control_revision,
            generation: entry.generation,
            attempt: entry.attempt,
          } &&
          installed_restored_task_relation_output(
            relation,
            captured,
            entry.task,
          )
          is Some(output) else {
          return Err(ForeignOriginal)
        }
        completed.push({
          task: entry.task,
          generation: entry.generation,
          attempt: entry.attempt,
          output: Some(output),
          retire: Some(() => {
            release_installed_restored_task_relation(relation) is Ok(_)
          }),
        })
      }
    }
  }
  // Until the callback-safe DAG install completes, do not let a caller
  // revoke any of its output aliases. A refused install relinquishes all
  // staged holds back to their original caller.
  for entry in original {
    if entry.relation is Some(relation) {
      relation.attached = true
    }
  }
  let restored = @strategy.restore_captured_task_cut(
    captured,
    hooks,
    {
      start_revision,
      control_revision,
      generation,
      completed_task,
      next_task,
      completed: ReadOnlyArray::from_array(completed),
    },
    cut.backing,
    current,
  )
  if restored is Err(issue) {
    for entry in original {
      if entry.relation is Some(relation) {
        relation.attached = false
      }
    }
    return Err(Cut(issue))
  }
  cut.installed = true
  Ok(())
}

///|
/// Only the cut metadata is returned here. The graph now holds the output
/// retirement callbacks through their ordinary Task cleanup.
pub fn return_installed_restored_task_cut(
  cut : InstalledRestoredTaskCut,
) -> Result[Unit, InstalledTaskContinuationReadIssue] {
  if cut.applying {
    return Err(ForeignOriginal)
  }
  if cut.work is Some(work) {
    match @resources.finish_preparation_phase_work_continuation64(work) {
      Err(_) => return Err(ForeignOriginal)
      Ok(_) => cut.work = None
    }
  }
  @resources.settle_capacity(
    @strategy.captured_dag_ledger(cut.captured),
    cut.backing,
  ).map_err(issue => InstalledTaskContinuationReadIssue::Resource(issue))
}
