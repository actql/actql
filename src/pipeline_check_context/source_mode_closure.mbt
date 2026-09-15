///|
pub(all) enum SourceModeClosureIssue {
  InvalidLimits
  BudgetExceeded
  Unresolved(Int, Int, @sourceviews.ModeObligation)
} derive(Eq, Debug)

///|
/// Runtime support must be rechecked before acquisition; failure prevents the
/// request and any output. This does not authorize the request or admit rows.
pub struct SourceModeExecutionCheck {
  stage : Int
  input : Int
  request : @sourceviews.AcquisitionRequest
}

///|
struct ProgramSourceModeClosure {
  owner : ProgramIncomingLinks
  checks : Array[SourceModeExecutionCheck]
  work : Int
}

///|
fn check_source_mode_obligation(
  stage : Int,
  input : Int,
  obligation : @sourceviews.ModeObligation,
) -> Result[Unit, SourceModeClosureIssue] {
  match obligation {
    @sourceviews.RuntimeModeSupport => Ok(())
    @sourceviews.BoundedChangesRange | @sourceviews.SourceStateRequirement =>
      Err(Unresolved(stage, input, obligation))
  }
}

///|
/// Close the selected mode inventory only. Changes state is static planning
/// material and must not be converted into an unspecified future runtime check.
pub fn close_program_source_modes(
  owner : ProgramIncomingLinks,
  max_work : Int,
  max_checks : Int,
) -> Result[ProgramSourceModeClosure, SourceModeClosureIssue] {
  if max_work < 0 || max_checks < 0 {
    return Err(InvalidLimits)
  }
  let requests = owner.incoming.identity.requests
  let mut work = owner.work
  if work >= max_work {
    return Err(BudgetExceeded)
  }
  work += 1
  let checks = []
  for stage in 0..<requests.stages.length() {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let selected = requests.stages[stage]
    for input in 0..<@sourceviews.pipeline_requests_count(selected) {
      if work == max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      let request = @sourceviews.pipeline_request_at(selected, input).unwrap()
      let obligations = match request {
        @sourceviews.Direct(mode, _) => @sourceviews.mode_obligations(mode)
        @sourceviews.Keyed(mode, _) => @sourceviews.keyed_mode_obligations(mode)
      }
      for obligation in obligations {
        if work == max_work {
          return Err(BudgetExceeded)
        }
        work += 1
        match check_source_mode_obligation(stage, input, obligation) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
        if checks.length() == max_checks {
          return Err(BudgetExceeded)
        }
        checks.push({ stage, input, request, })
      }
    }
  }
  Ok({ owner, checks, work, })
}

///|
pub fn source_mode_closure_owner(
  v : ProgramSourceModeClosure,
) -> ProgramIncomingLinks {
  v.owner
}

///|
pub fn source_mode_closure_count(v : ProgramSourceModeClosure) -> Int {
  v.checks.length()
}

///|
pub fn source_mode_closure_at(
  v : ProgramSourceModeClosure,
  index : Int,
) -> SourceModeExecutionCheck? {
  v.checks.get(index)
}

///|
pub fn source_mode_closure_work(v : ProgramSourceModeClosure) -> Int {
  v.work
}
