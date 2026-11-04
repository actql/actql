///|
/// A typed continuation of the original adopted preparation, not a new lease.
/// No raw Prepared or legacy preparation owner is retained here. The SAME
/// original body borrow controls liveness; retiring this existing controller
/// cuts its semantic aliases before the manager returns that borrow.
struct ClientProgramPublication {
  mut original : ClientProgramPublication?
  mut retiring : Bool
  mut publication_definition : @publication.PublicationContract?
  mut publication_invocation : @publication.PublicationContract?
  row_bound : Int?
  snapshot_prequoted : Bool
  mut retained_quote : Int64
  mut execution_quote : Int64
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ]
  mut run : @strategy.CapturedDAG?
  mut snapshot : ClientProgramSnapshot?
  mut snapshot_starting : Bool
  completed_snapshots : Array[@publication.CapturedResultSnapshot]
  mut next_snapshot_index : Int
  mut capture_started : Bool
  mut capture : ClientProgramCapture?
}

///|
fn publication_original_body(
  value : ClientProgramPublication,
) -> @publication_host.PreparedClientProgram? {
  guard value.original is Some(original) &&
    physical_equal(original, value) &&
    !value.retiring &&
    !@resources.preparation_body_retirement_started(value.holder) else {
    return None
  }
  @resources.preparation_body_borrow_value(value.holder)
}

///|
/// Static pre-quote allowance: snapshot projector H2552/R20371/W20791 =
/// 370128, plus wrapper H32/R64/W64 =1536 for original occurrence/port/Schema
/// Some carriers, running totals, cost results and the returned handle.
/// This is admitted BEFORE any projector constructor, including failed quotes.
let publication_projection_execution : Int64 = 371664L

///|
/// Fixed adopted-owner entry. No supplied row count, policy override or bytes.
/// One issued continuation fences the serial Result-publication invocation.
pub fn reserve_program_publication(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[ClientProgramPublication, ClientClosedValuesPreparationIssue] {
  let holder = match managed_run_publication_body(owner, prepared) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if owner.publication_started || owner.publication is Some(_) {
    return Err(WrongPhase)
  }
  let plan = match owner.captured_preparation {
    Some(captured) => {
      if !physical_equal(captured.prepared, prepared) ||
        !physical_equal(captured.request, owner.request) {
        return Err(ForeignOriginal)
      }
      captured.capacity_plan
    }
    None => {
      guard owner.source_free_preparation is Some(source_free) else {
        return Err(ForeignOriginal)
      }
      source_free.capacity_plan
    }
  }
  let mut snapshot_prequoted = plan.scalar_demand is Some(_) ||
    plan.value_node_demand is Some(_)
  let (inventory, rows, text) = match plan.scalar_demand {
    Some(demand) => {
      guard plan.schema_inventory is Some(inventory) &&
        physical_equal(demand.original, inventory) else {
        return Err(ForeignOriginal)
      }
      (Some(inventory), demand.rows, None)
    }
    None =>
      // This SAME Plan already checked its flat Number/Boolean/Text schemas
      // and retained their node demand. Do not repeat schema admission or
      // treat absence of the numeric-only specialization as a foreign Run.
      match plan.value_node_demand {
        Some(demand) => {
          guard plan.demand_inventory is Some(inventory) &&
            physical_equal(demand.original, inventory) else {
            return Err(ForeignOriginal)
          }
          (Some(inventory), demand.rows, Some(plan.values.max_text_bytes))
        }
        None => {
          // Derived outputs need not have an input schema-demand inventory.
          // Their same finished export supplies exact snapshot geometry; the
          // original publication policy still bounds its accepted row count.
          guard plan.publication is Some(publication) else {
            return Err(ForeignOriginal)
          }
          (None, publication.rows, None)
        }
      }
  }
  guard plan.graph is Some(graph) &&
    owner.publication_definition is Some(_) &&
    owner.publication_invocation is Some(_) &&
    !owner.source_free_opening &&
    owner.source_free_captured is Some(captured) &&
    owner.ledger is Some(ledger) &&
    physical_equal(ledger, @strategy.captured_dag_ledger(captured)) else {
    return Err(ForeignOriginal)
  }
  let (baseline, prior_execution) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  owner.publication_started = true
  // The fixed future descriptor/control packet is separate from row payloads:
  // input bag/Plan/extent/empty arrays616, getter112, issued capture handle and
  // result/Option/transition carriers <=512; 808 explicit conservative slack.
  if baseline > 9223372036854775807L - 2048L {
    return Err(Policy)
  }
  let count = @strategy.graph_result_count(graph)
  // Existing publication arrays4K + four token maps3K. Eight growing-array
  // envelopes and seven mapper closures; plus one original completed-snapshot
  // inventory. Shared growing Array recipe (3H,13+3K refs,2W) bounds each
  // backing overlap. Original row payloads are borrowed.
  let node_arrays = 1680L + 192L * count.to_int64()
  if node_arrays > 9223372036854775807L - baseline - 2048L {
    return Err(Policy)
  }
  let controls_retained = baseline + 2048L + node_arrays
  let quote_execution = Int64::max(
    prior_execution, publication_projection_execution,
  )
  match
    reserve_program_publication_phase(
      holder, prepared, controls_retained, quote_execution,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @resources.preparation_body_borrow_value(holder) is Some(current) &&
    physical_equal(current, prepared) &&
    managed_run_publication_body(owner, prepared) is Ok(_) else {
    return Err(ForeignOriginal)
  }
  let mut retained = 0L
  let mut execution = 0L
  if inventory is Some(inventory) {
    guard scalar_snapshot_layout(
        inventory.fields,
        inventory.names,
        rows,
        total_text_bytes=text,
      )
      is Some(task) &&
      @execution.preparation_representation_cost(task.retained) is Some(task_r) &&
      @execution.preparation_representation_cost(task.temporary) is Some(task_e) else {
      return Err(Policy)
    }
    retained = task_r
    execution = task_e
    for index in 0..<count {
      guard @strategy.graph_result_occurrence(graph, index) is Some(occurrence) else {
        return Err(Policy)
      }
      let schema = @results.port_schema(
        @execution.managed_result_occurrence_port(occurrence),
      )
      // A node-demand proof also covers bounded ARRAY/STRUCT. Only the
      // original leaf schemas justify this flat snapshot layout. Otherwise
      // keep the same Run/export and fund each recursive copy from its exact
      // completed writer extent before entering that snapshot constructor.
      if !client_local_json_leaf_schema(schema) {
        snapshot_prequoted = false
        retained = 0L
        execution = 0L
        break
      }
      guard scalar_snapshot_layout(
          @schema.field_count(schema),
          @schema.field_reference_name_bytes(schema),
          rows,
          total_text_bytes=text,
        )
        is Some(snapshot) &&
        @execution.preparation_representation_cost(snapshot.retained) is Some(r) &&
        @execution.preparation_representation_cost(snapshot.temporary)
        is Some(e) else {
        return Err(Policy)
      }
      if r > 9223372036854775807L - retained - 96L {
        return Err(Policy)
      }
      retained += r + 96L
      execution = Int64::max(execution, e)
    }
  }
  if retained > 9223372036854775807L - controls_retained ||
    execution > 9223372036854775807L - publication_projection_execution {
    return Err(Policy)
  }
  let total_r = controls_retained + retained
  let total_e = Int64::max(
    quote_execution,
    execution + publication_projection_execution,
  )
  match reserve_program_publication_phase(holder, prepared, total_r, total_e) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Recheck the exact token after imported callbacks, not merely borrower count.
  guard @resources.preparation_body_borrow_value(holder) is Some(current) &&
    physical_equal(current, prepared) &&
    managed_run_publication_body(owner, prepared) is Ok(_) else {
    return Err(ForeignOriginal)
  }
  let value : ClientProgramPublication = {
    original: None,
    retiring: false,
    publication_definition: owner.publication_definition,
    publication_invocation: owner.publication_invocation,
    row_bound: Some(rows),
    snapshot_prequoted,
    retained_quote: total_r,
    execution_quote: total_e,
    holder,
    capture_started: false,
    capture: None,
    run: Some(captured),
    snapshot: None,
    snapshot_starting: false,
    next_snapshot_index: 0,
    completed_snapshots: [],
  }
  value.original = Some(value)
  owner.publication = Some(value)
  Ok(value)
}

///|
/// Refresh the original admission before any resumed publication constructor.
/// A zero-delta check still rejects stopping, and exact custody is rechecked
/// after the imported callback even while other role borrowers remain live.
fn refresh_publication_original(
  value : ClientProgramPublication,
) -> Result[
  @publication_host.PreparedClientProgram,
  ClientClosedValuesPreparationIssue,
] {
  guard publication_original_body(value) is Some(prepared) else {
    return Err(ForeignOriginal)
  }
  match
    reserve_program_publication_phase(
      value.holder,
      prepared,
      value.retained_quote,
      value.execution_quote,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match publication_original_body(value) {
    Some(body) => Ok(body)
    None => Err(ForeignOriginal)
  }
}

///|
/// Internal constructor transition shared by capture and its deterministic
/// capacity tests. Dimensions come only from fixed original-plan recipes.
fn reserve_publication_constructor(
  value : ClientProgramPublication,
  retained_add : Int64,
  temporary : Int64,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  guard publication_original_body(value) is Some(prepared) else {
    return Err(ForeignOriginal)
  }
  if retained_add < 0L ||
    temporary < 0L ||
    retained_add > 9223372036854775807L - value.retained_quote ||
    temporary > 9223372036854775807L - publication_projection_execution {
    return Err(Policy)
  }
  let retained = value.retained_quote + retained_add
  let execution = Int64::max(
    value.execution_quote,
    temporary + publication_projection_execution,
  )
  match
    reserve_program_publication_phase(
      value.holder,
      prepared,
      retained,
      execution,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => {
      value.retained_quote = retained
      value.execution_quote = execution
    }
  }
  guard publication_original_body(value) is Some(_) else {
    return Err(ForeignOriginal)
  }
  Ok(())
}

///|
// The existing publication failure stays ForeignOriginal when its exact
// manager borrow was returned during currentness. This is one typed Result
// projection, not another check/current call or an error-code whitelist.
fn reserve_program_publication_phase(
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  @resources.reserve_preparation_publication_phase(
    holder, prepared, retained, execution,
  ).map_err(issue => {
    match issue {
      BorrowReturned => ForeignOriginal
      _ => Capacity(issue)
    }
  })
}

///|
/// The fixed actual Run supplies its existing private body holder. No caller
/// provides a substitute borrow, raw preparation input or second owner. This
/// is original correspondence DATA; the later Resource grow owns currentness.
fn managed_run_publication_body(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  ClientClosedValuesPreparationIssue,
] {
  guard value.original is Some(original) &&
    physical_equal(original, value) &&
    value.ledger is Some(_) &&
    value.preparation is Some(PureManaged(_, original_prepared)) &&
    physical_equal(original_prepared, prepared) &&
    value.preparation_retirement is Some(PurePreparation(custody)) &&
    custody.holder is Some(holder) &&
    !@resources.preparation_body_retirement_started(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, prepared) else {
    return Err(ForeignOriginal)
  }
  Ok(holder)
}

///|
/// Semantic alias retirement only, before returning the Run's same body role.
fn clear_managed_run_publication(value : ClientInstalledManagedRun) -> Unit {
  if value.publication is Some(publication) {
    clear_program_publication(publication)
  }
  value.publication = None
  value.publication_definition = None
  value.publication_invocation = None
}
