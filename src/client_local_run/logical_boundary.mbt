///|
/// Explicit observation setup on this configured Run's existing Ledger and
/// original checked graph, before its first Compute activation. No field is
/// added to the Normal Host or Run. The installed caller separately backs its
/// pre-Source construction and checks current read/egress authorization.
pub fn prepare_local_compute_task_boundaries(
  host : LocalComputeHost,
) -> Result[
  @strategy.CapturedTaskBoundaryHooks,
  @strategy.CapturedTaskBoundaryIssue,
] {
  let run = local_compute_run(host)
  @strategy.prepare_captured_task_boundary_hooks(
    run,
    @host.prepared_client_graph(local_run_prepared(host.plan)),
    @strategy.captured_dag_strategy_revision(run),
  )
}

///|
/// The configured Compute owner supplies its original compilation/Run binding;
/// the caller cannot select another graph, generation or logical Step identity.
/// A projected result owns a separately reserved fork and must be explicitly
/// returned with return_client_logical_task_boundary after disposing its view.
pub fn read_local_compute_logical_boundary(
  host : LocalComputeHost,
  original : @host.ClientStructuralExplanationOriginal,
  phase : @strategy.CapturedTaskBoundaryPhase,
  max_nodes : Int,
) -> Result[
  @host.ClientLogicalTaskBoundaryProjection,
  @host.ClientLogicalTaskBoundaryIssue,
] {
  @host.read_client_logical_task_boundary(
    original,
    host.plan.compiled,
    local_run_prepared(host.plan),
    local_compute_run(host),
    phase,
    max_nodes,
  )
}
