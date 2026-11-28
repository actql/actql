///|
/// Read the computation component of the retained Effect compilation. The
/// private checked view remains owned by that original compilation; neither
/// this projection nor its capability metadata admits an executable Run.
/// Effect declarations, gates and sealed Preview require separate projections
/// before a Host can advertise a complete Effectful static Plan response.
pub fn client_effect_static_computation_plan_view(
  prepared : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientInteractivePlanIssue] {
  if !physical_equal(compiled.owner, prepared) {
    return Err(ClientInteractivePlanIssue::ForeignCompilation)
  }
  issue_client_static_plan_view(
    compiled.compiled.owner,
    compiled.compiled.compiled_plan,
    max_bytes,
    max_nodes,
    max_depth,
    false,
  )
}

///|
/// Find the first Step of the already authenticated original Map before the
/// bound Effect computation opens. Graph geometry must let every physical
/// task stop on an independent checked operation.
pub fn preflight_client_effect_compute_steps(
  bound : PreparedClientEffectRun,
  ledger : @resources.Ledger,
  map : @publication.RunEvidenceValue,
  map_cid : String,
  max_work : Int,
  observe_step? : ((Int, String) -> Unit)? = None,
) -> Result[String?, @strategy.CapturedTaskControlIssue] {
  let checked = prepared_client_effect_run_graph(bound)
  let graph = @strategy.checked_effect_run_graph(checked)
  let admission = @effect_binding.effect_program_run_admission(
    @strategy.checked_effect_run_owner(checked),
  )
  let plan_cid = @publication.run_publication_compiled_plan_cid(admission)
  let program_cid = prepared_client_effect_identity(
      prepared_client_effect_run_computation(bound),
    ).program_definition_cid
  guard @publication.run_evidence_value_identity(map) == map_cid &&
    @publication.interactive_logical_map_original(map) is Some(value) &&
    @canonical.object_field(value, "compiled_plan_cid")
    is Some(@canonical.String(map_plan)) &&
    map_plan == plan_cid &&
    @canonical.object_field(value, "program_definition_cid")
    is Some(@canonical.String(map_program)) &&
    map_program == program_cid &&
    @canonical.object_field(value, "steps") is Some(@canonical.Array(steps)) else {
    return Err(ForeignOwner)
  }
  // Each original Step costs at most one forward lookup, plus one scan of
  // the data/control predecessors of task 0. No operation searches all tasks.
  let work = 1L +
    12L * @canonical.array_count(steps).to_int64() +
    @strategy.graph_data_count(graph).to_int64() +
    @strategy.graph_control_count(graph).to_int64()
  if work > max_work.to_int64() {
    return Err(Resource(@resources.PlanningLimit))
  }
  match @resources.charge_planning(ledger, work.to_int()) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if !@strategy.checked_source_free_effect_control_has_entry(graph) {
    return Ok(None)
  }
  scan_effect_compute_entry(
    steps,
    @strategy.graph_task_count(graph),
    (stage, ordinal) => {
      @strategy.checked_task_control_operation_task(graph, stage, ordinal)
    },
    observe_step~,
  )
}

///|
fn scan_effect_compute_entry(
  steps : @canonical.FrozenArray[@canonical.CanonicalValue],
  task_count : Int,
  find_task : (Int, Int) -> Int?,
  observe_step? : ((Int, String) -> Unit)? = None,
) -> Result[String?, @strategy.CapturedTaskControlIssue] {
  let mut entry_step = None
  let mut matched = 0
  let mut prior_stage = -1
  let mut prior_ordinal = -1
  try {
    for index in 0..<@canonical.array_count(steps) {
      let step = @canonical.array_at(steps, index).unwrap()
      let key = explanation_original_field(step, "key")
      let occurrence = explanation_original_field(key, "occurrence")
      if explanation_original_text(occurrence, "kind") != "operation" {
        continue
      }
      let stage = explanation_original_ordinal(key, "stage_ordinal")
      let ordinal = explanation_original_ordinal(
        occurrence, "operation_ordinal",
      )
      if stage < prior_stage ||
        (stage == prior_stage && ordinal <= prior_ordinal) {
        return Err(ForeignOwner)
      }
      prior_stage = stage
      prior_ordinal = ordinal
      if find_task(stage, ordinal) is Some(task) {
        matched += 1
        let step_id = explanation_original_text(step, "step_id")
        if task == 0 {
          entry_step = Some(step_id)
        }
        if observe_step is Some(observe) {
          observe(task, step_id)
        }
      }
    }
    if matched == task_count {
      Ok(entry_step)
    } else {
      Ok(None)
    }
  } catch {
    _ => Err(ForeignOwner)
  }
}
