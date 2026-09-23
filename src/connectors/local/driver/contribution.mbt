///|
pub fn local_dispatch_registration(
  installed : LocalDispatchModule,
) -> @connector.CapabilityRegistration {
  installed.registration
}

///|
/// Both pure entrypoints close over the same installed implementation. Error
/// projection is diagnostic only; it cannot supply work or completion evidence.
pub fn[E] local_compute_contribution(
  installed : LocalDispatchModule,
  dispatch_issue : (LocalDispatchIssue) -> E,
  estimate_issue : (LocalEstimateIssue) -> E,
) -> @host.ComputeContribution[Unit, E] {
  {
    exclusions: max_entries => {
      if max_entries < 0 {
        return None
      }
      let excluded = []
      let graph = @strategy.captured_dag_graph(installed.run)
      for
        task in @strategy.captured_compute_first_task(installed.run)..<@strategy.graph_task_count(
          graph,
        ) {
        if local_dispatch_rejection(installed, task) is Some(reason) {
          if excluded.length() >= max_entries {
            return None
          }
          excluded.push(
            (
              task,
              @connector.capability_description(installed.registration).name,
              reason,
            ),
          )
        }
      }
      Some(excluded)
    },
    prepare: fn(_context, task, revision, request) {
      prepare_local_dispatch(installed, task, revision, request).map_err(
        dispatch_issue,
      )
    },
    propose: fn(_context, task, quantities) {
      estimate_local_installed_offers(installed, task, quantities).map_err(
        estimate_issue,
      )
    },
  }
}
