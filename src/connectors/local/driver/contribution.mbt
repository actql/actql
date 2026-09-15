///|
/// Both pure entrypoints close over the same installed implementation. Error
/// projection is diagnostic only; it cannot supply work or completion evidence.
pub fn[E] local_compute_contribution(
  installed : LocalDispatchModule,
  dispatch_issue : (LocalDispatchIssue) -> E,
  estimate_issue : (LocalEstimateIssue) -> E,
) -> @host.ComputeContribution[Unit, E] {
  {
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
