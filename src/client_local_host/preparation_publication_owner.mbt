///|
/// A typed continuation of the original adopted preparation, not a new lease.
/// No raw Prepared is retained here: the manager token and original owner cut
/// their aliases together during retirement, invalidating escaped handles.
struct ClientProgramPublication[I] {
  owner : ClientClosedValuesPreparation[I]
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ]
  _observed_base_retained : Int64
  _observed_snapshot_retained : Int64
  _observed_snapshot_execution : Int64
  mut run : @strategy.CapturedDAG?
  mut snapshot : ClientProgramSnapshot[I]?
  mut snapshot_starting : Bool
  completed_snapshots : Array[@publication.CapturedResultSnapshot]
  mut next_snapshot_index : Int
  mut capture_started : Bool
  mut capture : ClientProgramCapture[I]?
}

///|
fn[I] publication_original_body(
  value : ClientProgramPublication[I],
) -> @publication_host.PreparedClientProgram? {
  let owner = value.owner
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.publication is Some(issued) &&
    physical_equal(issued, value) &&
    owner.manager_original is Some(holder) &&
    physical_equal(holder, value.holder) &&
    owner.adopted &&
    !owner.retiring &&
    owner.prepared is Some(prepared) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, prepared) &&
    !@resources.preparation_body_retirement_started(holder) else {
    return None
  }
  Some(prepared)
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
pub fn[I] reserve_program_publication(
  owner : ClientClosedValuesPreparation[I],
  prepared : @publication_host.PreparedClientProgram,
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
) -> Result[ClientProgramPublication[I], ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.input is Some(input) &&
    owner.prepared is Some(body) &&
    physical_equal(body, prepared) &&
    owner.manager_original is Some(issued) &&
    physical_equal(issued, holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(held) &&
    physical_equal(held, prepared) else {
    return Err(ForeignOriginal)
  }
  if !owner.adopted ||
    owner.retiring ||
    owner.publication_started ||
    owner.publication is Some(_) ||
    @resources.preparation_body_retirement_started(holder) {
    return Err(WrongPhase)
  }
  guard owner.source_free is Some(source_free) else {
    return Err(ForeignOriginal)
  }
  let plan = source_free.capacity_plan
  guard plan.scalar_demand is Some(demand) &&
    plan.schema_inventory is Some(inventory) &&
    physical_equal(demand.original, inventory) &&
    plan.graph is Some(graph) &&
    owner.publication_definition is Some(_) &&
    owner.publication_invocation is Some(_) else {
    return Err(Policy)
  }
  guard owner.adopted_run is Some(adopted_run) else {
    return Err(ForeignOriginal)
  }
  let captured = match
    installed_managed_publication_dag(adopted_run, prepared) {
    Err(issue) => return Err(Installed(issue))
    Ok(value) => value
  }
  owner.publication_started = true
  // The fixed future descriptor/control packet is separate from row payloads:
  // input bag/Plan/extent/empty arrays616, getter112, issued capture handle and
  // result/Option/transition carriers <=512; 808 explicit conservative slack.
  let baseline = owner.retained_quote
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
    owner.execution_quote,
    publication_projection_execution,
  )
  match
    @resources.reserve_preparation_publication_phase(
      owner.capacity,
      input,
      prepared,
      controls_retained,
      quote_execution,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => {
      owner.retained_quote = controls_retained
      owner.execution_quote = quote_execution
    }
  }
  guard @resources.preparation_body_borrow_value(holder) is Some(current) &&
    physical_equal(current, prepared) &&
    !owner.retiring else {
    return Err(ForeignOriginal)
  }
  guard scalar_snapshot_layout(inventory.fields, inventory.names, demand.rows)
    is Some(task) &&
    preparation_representation_cost(task.retained) is Some(task_r) &&
    preparation_representation_cost(task.temporary) is Some(task_e) else {
    return Err(Policy)
  }
  let mut retained = task_r
  let mut execution = task_e
  for index in 0..<count {
    guard @strategy.graph_result_occurrence(graph, index) is Some(occurrence) else {
      return Err(Policy)
    }
    let schema = @results.port_schema(
      @execution.managed_result_occurrence_port(occurrence),
    )
    guard scalar_snapshot_layout(
        @schema.field_count(schema),
        @schema.field_reference_name_bytes(schema),
        demand.rows,
      )
      is Some(snapshot) &&
      preparation_representation_cost(snapshot.retained) is Some(r) &&
      preparation_representation_cost(snapshot.temporary) is Some(e) else {
      return Err(Policy)
    }
    if r > 9223372036854775807L - retained - 96L {
      return Err(Policy)
    }
    retained += r + 96L
    execution = Int64::max(execution, e)
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
  match
    @resources.reserve_preparation_publication_phase(
      owner.capacity,
      input,
      prepared,
      total_r,
      total_e,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  // Recheck the exact token after imported callbacks, not merely borrower count.
  guard @resources.preparation_body_borrow_value(holder) is Some(current) &&
    physical_equal(current, prepared) &&
    !owner.retiring else {
    return Err(ForeignOriginal)
  }
  let value : ClientProgramPublication[I] = {
    owner,
    holder,
    _observed_base_retained: controls_retained,
    _observed_snapshot_retained: retained,
    _observed_snapshot_execution: total_e,
    capture_started: false,
    capture: None,
    run: Some(captured),
    snapshot: None,
    snapshot_starting: false,
    next_snapshot_index: 0,
    completed_snapshots: [],
  }
  owner.retained_quote = total_r
  owner.execution_quote = total_e
  owner.publication = Some(value)
  Ok(value)
}

///|
/// Refresh the original admission before any resumed publication constructor.
/// A zero-delta check still rejects stopping, and exact custody is rechecked
/// after the imported callback even while other role borrowers remain live.
fn[I] refresh_publication_original(
  value : ClientProgramPublication[I],
) -> Result[
  @publication_host.PreparedClientProgram,
  ClientClosedValuesPreparationIssue,
] {
  let owner = value.owner
  guard publication_original_body(value) is Some(prepared) &&
    owner.input is Some(input) else {
    return Err(ForeignOriginal)
  }
  match
    @resources.reserve_preparation_publication_phase(
      owner.capacity,
      input,
      prepared,
      owner.retained_quote,
      owner.execution_quote,
    ) {
    Err(issue) => return Err(Capacity(issue))
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
fn[I] reserve_publication_constructor(
  value : ClientProgramPublication[I],
  retained_add : Int64,
  temporary : Int64,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  let owner = value.owner
  guard publication_original_body(value) is Some(prepared) &&
    owner.input is Some(input) else {
    return Err(ForeignOriginal)
  }
  if retained_add < 0L ||
    temporary < 0L ||
    retained_add > 9223372036854775807L - owner.retained_quote ||
    temporary > 9223372036854775807L - publication_projection_execution {
    return Err(Policy)
  }
  let retained = owner.retained_quote + retained_add
  let execution = Int64::max(
    owner.execution_quote,
    temporary + publication_projection_execution,
  )
  match
    @resources.reserve_preparation_publication_phase(
      owner.capacity,
      input,
      prepared,
      retained,
      execution,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => {
      owner.retained_quote = retained
      owner.execution_quote = execution
    }
  }
  guard publication_original_body(value) is Some(_) else {
    return Err(ForeignOriginal)
  }
  Ok(())
}
