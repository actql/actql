///|
/// A requested Debug boundary is a physical capability, not a language rule.
/// Normal preparation keeps its original fusion strategy and GraphIssue.
pub(all) enum DebugTaskGraphIssue {
  Graph(GraphIssue)
  BoundaryUnavailable(Int, Int)
  InputBoundaryUnavailable(Int, Int)
} derive(Eq, Debug)

///|
/// Prepare physical per-operation tasks BEFORE this Run's compilation and any
/// work. Reuse the SAME checked owners and the existing complete task/edge/
/// Result remapper; this neither compiles nor executes or funds a Run. Captured
/// acquisition prefixes remain owned acquisitions, not logical step controls.
pub fn prepare_checked_debug_dag(
  program : @checked.CheckedProgram,
  owners : Array[@lower.BoundPrepared],
  max_tasks : Int,
  max_work : Int,
  source_free_root? : Bool = false,
  captured_prefix? : Int = 1,
) -> Result[CheckedDAG, DebugTaskGraphIssue] {
  if @checked.checked_program_has_effects(program) {
    return Err(Graph(EffectGraphOwnerRequired))
  }
  let (logical, remaining) = match
    prepare_checked_logical_dag_owned(
      program,
      owners,
      max_tasks,
      max_work,
      source_free_root~,
      captured_prefix~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Graph(issue))
  }
  expand_debug_logical_dag(logical, max_tasks, remaining)
}

///|
// Both callers admit their original program owner before sharing this split.
// For Effects the checked private Result inputs are already roots here.
fn expand_debug_logical_dag(
  logical : CheckedDAG,
  max_tasks : Int,
  remaining : Int,
) -> Result[CheckedDAG, DebugTaskGraphIssue] {
  let program = logical.program
  let work = Ref(remaining)
  try {
    let boundaries : Array[Int?] = []
    for stage in 0..<logical.owners.length() {
      carrier_work(work)
      let prepared = @lower.bound_preparation(logical.owners[stage])
      let count = @pipeline.step_count(@lower.pipeline(prepared))
      if stage < logical.captured_prefix || count <= 1 {
        boundaries.push(None)
        continue
      }
      // The current selected-task remapper has no independently owned raw
      // Input output in a split multi-operation Stage. Inspect ORIGINAL
      // checked exports before remapping; never relabel a legal authored
      // Input as a foreign port or insert a synthetic projection/identity.
      guard @results.stage_at(@checked.checked_stage_results(program), stage)
        is Some(stage_results) else {
        return Err(Graph(ForeignPort(stage, 0)))
      }
      for index in 0..<@ports.count(stage_results) {
        carrier_work(work)
        let result = @ports.result_at(stage_results, index).unwrap()
        if @ports.target(result) is @pipeline.Input(input) {
          return Err(InputBoundaryUnavailable(stage, input))
        }
      }
      let mut selected_relation_dag : Bool? = None
      for step in 0..<count {
        carrier_work(work)
        guard @lower.node_at(prepared, step) is Some(node) else {
          return Err(BoundaryUnavailable(stage, step))
        }
        // Use the SAME bounded whole-sequence proof as Normal. A Relation
        // prefix or a Debug request alone cannot admit an analytic provider.
        if @lower.payload(node) is @lower.Analytic(_) &&
          selected_relation_dag is None {
          guard carrier_segment_shape(prepared, work) is Some(shape) else {
            return Err(BoundaryUnavailable(stage, step))
          }
          selected_relation_dag = Some(shape.relation_dag)
        }
        if !carrier_node_supports_selected_execution(
            node,
            work,
            analytic=selected_relation_dag == Some(true),
          ) {
          return Err(BoundaryUnavailable(stage, step))
        }
        for input in 0..<@lower.node_input_count(node) {
          carrier_work(work)
          guard @lower.node_input_target(node, input) is Some(target) &&
            @lower.preparation_carrier_at(prepared, target) is Some(carrier) else {
            return Err(BoundaryUnavailable(stage, step))
          }
          let supported = if @carrier.kind(carrier) == @carrier.RelationKind {
            @lower.node_accepts_managed_relation_view(node, input)
          } else {
            @lower.node_accepts_managed_carrier_view(node, input)
          }
          if !supported {
            return Err(BoundaryUnavailable(stage, step))
          }
        }
      }
      boundaries.push(Some(-1))
    }
    expand_internal_carrier_tasks_with_work(
      logical,
      max_tasks,
      work,
      split_override=Some(boundaries),
    ).map_err(issue => Graph(issue))
  } catch {
    CarrierWorkStop => Err(Graph(WorkLimit))
  }
}
