///|
/// An explicit first-compilation physical selection, not a read, control or
/// Resource grant. Normal remains the original compiler path.
pub(all) enum ClientExecutionProfile {
  Normal
  Debug
} derive(Eq, Debug)

///|
// The existing collection quote expands 21H/2R/42W. The bounded original
// pipeline/step/count getters co-count eight Some alternatives (8H/5R/8W).
// Inventory, expanded extent, tariff input and returned pair/Result add
// 5H/2R/21W. Five tariff sums plus two resize sums add7H/7W; the observed
// work Ref and two original quote/Some alternatives add5H/2R/7W. No input
// arrays, copied text, graph or lowered owner is allocated by this observer.
let client_debug_graph_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 21L + 8L + 5L + 7L + 5L,
  reference_slots: 2L + 5L + 2L + 2L,
  scalar_words: 42L + 8L + 21L + 7L + 7L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
/// Caller must reserve this fixed observation envelope before invoking the
/// bounded original-geometry read. It is DATA, not evidence of that reserve.
let client_debug_graph_quote_control_bytes : Int64 = {
  let work = @resources.preparation_phase_work_continuation64_construction_inventory()
  // Complete SAME staged receipt plus caller Some and Debug-only quoted-phase
  // payload. The unconstructed Normal work receipt is not spare funding.
  @execution.preparation_representation_cost({
    record_headers: client_debug_graph_quote_controls.record_headers +
    work.record_headers +
    2L,
    reference_slots: client_debug_graph_quote_controls.reference_slots +
    work.reference_slots +
    1L,
    scalar_words: client_debug_graph_quote_controls.scalar_words +
    work.scalar_words +
    3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
pub fn client_debug_graph_quotation_control_bytes() -> Int64 {
  client_debug_graph_quote_control_bytes
}

///|
// Full simultaneous logical and expanded Graph containers. Original checked
// ports, lowered preparations, numeric bodies, Result occurrences and String
// backing stay on the unchanged compiler body quote; they are not copied here.
// The two Graph records are2H/28R/6W. Eight Array initializer closures and the
// map_err closure are9H/16R, Work Ref1H/1W, logical pair1H/1R/1W and three Result
// shells3H/3R/3W: total16H/48R/11W. Per-edge/slot alternatives below co-count
// both data and supplied realization; no unsupported shape buys spare bytes.
fn client_debug_graph_collection_inventory(
  stages : Int64,
  tasks : Int64,
  imports : Int64,
  inputs : Int64,
  gates : Int64,
  obligations : Int64,
  numeric : Int64,
  results : Int64,
) -> @shape.CollectionConstructionInventory {
  // Each count is bounded by the same signed32 graph-work balance before
  // conversion. These finite affine sums cannot overflow signed64; the
  // collection/tariff owners still check their own products and totals.
  {
    records: 16L +
    3L * imports +
    9L * inputs +
    2L * gates +
    obligations +
    2L * numeric +
    2L * results +
    stages +
    3L * tasks,
    record_references: 48L +
    4L * imports +
    7L * inputs +
    2L * gates +
    2L * obligations +
    6L * numeric +
    2L * results +
    tasks,
    record_words: 11L +
    8L * imports +
    19L * inputs +
    4L * gates +
    3L * numeric +
    2L * results +
    2L * stages +
    5L * tasks,
    // Original and expanded per-task operation/numeric arrays coexist;
    // Debug's requested and remapper-selected boundary vectors coexist too.
    reference_arrays: 25L + 2L * stages + 2L * tasks,
    reference_items: 11L * stages +
    6L * tasks +
    2L * imports +
    3L * inputs +
    2L * gates +
    2L * obligations +
    2L * numeric +
    2L * results,
    scalar_arrays: 6L + 2L * stages,
    scalar_items: 5L * stages + 3L * tasks,
    maps: 0L,
    map_entries: 0L,
  }
}

///|
/// Read only the SAME checked geometry before lowering/Graph construction.
/// Price source-free Pure Values or the original single Effect-bearing Unit.
/// Other checked shapes receive a physical capability refusal. No second
/// checker, parser, owner array, Result binding or selected graph is built.
pub fn measure_client_debug_graph_construction(
  checked : @checked.CheckedProgram,
  max_tasks : Int,
  max_work : Int,
  observed_work : Ref[Int64],
  effect? : @checked.EffectComputationCandidate? = None,
) -> Result[(Int64, Int), ClientProgramPreparationIssue] {
  if max_tasks < 0 || max_work < 0 {
    return Err(Graph(InvalidLimits))
  }
  let has_effects = @checked.checked_program_has_effects(checked)
  let private_roots = match effect {
    Some(original) => {
      if !has_effects ||
        !physical_equal(
          @checked.effect_computation_checked_program(original),
          checked,
        ) ||
        @checked.unit_count(checked) != 1 {
        return Err(DebugProfileUnsupported)
      }
      @syntax.effect_header_count(@checked.effect_computation_headers(original)).to_int64()
    }
    None => {
      if has_effects {
        return Err(DebugProfileUnsupported)
      }
      0L
    }
  }
  measure_original_debug_graph_construction(
    checked, max_tasks, max_work, observed_work, private_roots,
  )
}

///|
/// Price the temporary Debug graph against the original completed static
/// Effect preparation, including its private Result roots.
pub fn measure_client_static_effect_debug_graph_construction(
  prepared : PreparedClientEffectComputation,
  max_tasks : Int,
  max_work : Int,
  observed_work : Ref[Int64],
) -> Result[(Int64, Int), ClientProgramPreparationIssue] {
  if max_tasks < 0 || max_work < 0 {
    return Err(Graph(InvalidLimits))
  }
  let candidate = prepared.candidate
  let checked = @checked.effect_program_static_checked_computation(candidate)
  if @checked.unit_count(checked) != 1 {
    return Err(DebugProfileUnsupported)
  }
  let roots = @syntax.effect_header_count(
    @checked.effect_program_static_headers(candidate),
  )
  measure_original_debug_graph_construction(
    checked,
    max_tasks,
    max_work,
    observed_work,
    roots.to_int64(),
  )
}

///|
fn measure_original_debug_graph_construction(
  checked : @checked.CheckedProgram,
  max_tasks : Int,
  max_work : Int,
  observed_work : Ref[Int64],
  private_roots : Int64,
) -> Result[(Int64, Int), ClientProgramPreparationIssue] {
  if @checked.source_execution_count(checked) != 0 ||
    @checked.unit_count(checked) < 1 {
    return Err(DebugProfileUnsupported)
  }
  let mut remaining = max_work
  let stages = @checked.unit_count(checked)
  let mut tasks = 0L
  let mut imports = 0L
  let mut inputs = 0L
  let mut gates = 0L
  let mut numeric = 0L
  for stage in 0..<stages {
    if remaining == 0 {
      return Err(Graph(WorkLimit))
    }
    remaining -= 1
    observed_work.val += 1L
    guard @checked.unit_pipeline(checked, stage) is Some(pipeline) else {
      return Err(MissingCheckedStage(stage))
    }
    if stage == 0 &&
      (
        @pipeline.input_count(pipeline) != 0 ||
        !@pipeline.starts_with_values(pipeline)
      ) {
      return Err(DebugProfileUnsupported)
    }
    let steps = @pipeline.step_count(pipeline)
    tasks += Int::max(1, steps).to_int64()
    if tasks > max_tasks.to_int64() {
      return Err(Graph(TaskLimit))
    }
    let incoming = @pipeline.input_count(pipeline)
    guard @context.program_incoming_gates_count(
        @checked.incoming_gates(checked),
        stage,
      )
      is Some(gate_count) &&
      @checked.unit_group_numeric_slot_count(checked, stage)
      is Some(group_slots) &&
      @checked.unit_analytic_numeric_slot_count(checked, stage)
      is Some(analytic_slots) &&
      @checked.unit_pivot_numeric_slot_count(checked, stage)
      is Some(pivot_slots) else {
      return Err(MissingCheckedStage(stage))
    }
    let slots = group_slots.to_int64() +
      analytic_slots.to_int64() +
      pivot_slots.to_int64()
    let entries = incoming.to_int64() + gate_count.to_int64() + slots
    if entries > remaining.to_int64() {
      return Err(Graph(WorkLimit))
    }
    remaining -= entries.to_int()
    observed_work.val += entries
    imports += incoming.to_int64()
    gates += gate_count.to_int64()
    numeric += slots
    for index in 0..<steps {
      if remaining == 0 {
        return Err(Graph(WorkLimit))
      }
      remaining -= 1
      observed_work.val += 1L
      let step = @pipeline.step_at(pipeline, index).unwrap()
      match step.operation {
        @pipeline.Infer(_) | @pipeline.Serialize(_) =>
          return Err(DebugProfileUnsupported)
        _ => ()
      }
      let count = @pipeline.input_occurrence_count(step)
      if count > remaining {
        return Err(Graph(WorkLimit))
      }
      remaining -= count
      observed_work.val += count.to_int64()
      inputs += count.to_int64()
    }
  }
  let closure = @context.stage_requirement_operations(
    @checked.requirements(checked),
  )
  let obligations = @context.operation_closure_count(closure)
  let incoming = @context.incoming_links_requirements(
    @context.program_incoming_gates_owner(@checked.incoming_gates(checked)),
  )
  let results = @stage_results.export_count(
    @context.program_incoming_wiring(incoming),
  )
  // The retained Effect bindings may add a private Result root per member.
  // Price their complete vector, including roots sharing a public port.
  let roots = results.to_int64() + private_roots
  let entries = obligations.to_int64() + roots
  if entries > remaining.to_int64() {
    return Err(Graph(WorkLimit))
  }
  remaining -= entries.to_int()
  observed_work.val += entries
  let inventory = client_debug_graph_collection_inventory(
    stages.to_int64(),
    tasks,
    imports,
    inputs,
    gates,
    obligations.to_int64(),
    numeric,
    roots,
  )
  guard @shape.collection_construction_extent(inventory) is Some(extent) &&
    @execution.preparation_representation_cost({
      record_headers: extent.record_headers,
      reference_slots: extent.reference_slots,
      scalar_words: extent.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) else {
    return Err(DebugGraphConstructionOverflow)
  }
  Ok((bytes, remaining))
}
