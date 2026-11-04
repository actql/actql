///|
/// Select once during backed Plan construction, never while opening a read.
fn installed_direct_occurrences_owned(
  owner : ClientLocalSequenceOwner,
) -> Result[
  @publication_host.ClientDirectAcquisitionOccurrences,
  ClientInstalledManagedRunIssue,
] {
  let selected = match owner {
    Pure(prepared) =>
      @publication_host.select_client_direct_acquisition_occurrences(
        prepared, 1000000,
      )
    Effect(prepared) =>
      @publication_host.select_client_effect_direct_acquisition_occurrences(
        prepared, 1000000,
      )
  }
  selected.map_err(_ => Unsupported)
}

///|
fn installed_direct_occurrences_match_owner(
  selected : @publication_host.ClientDirectAcquisitionOccurrences,
  owner : ClientLocalSequenceOwner,
) -> Bool {
  match owner {
    Pure(prepared) =>
      @publication_host.client_direct_acquisition_occurrences_match_program(
        selected, prepared,
      )
    Effect(prepared) =>
      @publication_host.client_direct_acquisition_occurrences_match_effect_program(
        selected, prepared,
      )
  }
}

///|
/// Callback-free lookup into the same funded Plan. Whole-input legacy plans
/// do not claim a Query capture occurrence and deliberately return None.
fn installed_managed_run_direct_occurrence(
  run : ClientInstalledManagedRun,
  task : Int,
) -> (Int, Int, Int)? {
  let owner = match installed_managed_run_owner(run) {
    Ok(value) => value
    Err(_) => return None
  }
  let selected = match run.preparation {
    Some(PureManaged(_, prepared)) => {
      guard run.captured_preparation is Some(plan) &&
        physical_equal(plan.prepared, prepared) &&
        physical_equal(plan.request, run.request) else {
        return None
      }
      plan.direct_occurrences
    }
    Some(PlannedEffectManaged(_, plan)) => {
      if !physical_equal(plan.request, run.request) {
        return None
      }
      plan.direct_occurrences
    }
    _ => None
  }
  guard selected is Some(selected) &&
    installed_direct_occurrences_match_owner(selected, owner) else {
    return None
  }
  @publication_host.client_direct_acquisition_occurrence_at(selected, task)
}
