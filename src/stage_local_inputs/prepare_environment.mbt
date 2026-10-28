///|
pub enum PrepareEnvironmentIssue {
  InvalidLimits
  BudgetExceeded
  Index(@refs.Issue)
  Snapshot(Int, @snapshot.MembershipIssue)
  UnknownStage(Int, String)
  Stage(Int, Issue)
  Environment(Int, EnvironmentIssue)
  Collection(ProgramEnvironmentIssue)
  ForeignSourceViews
  ConnectorSnapshot(Int, @environment.SourceEvidenceMemberIssue)
}

///|
/// Prepare Local registrations before pipeline construction. Every supplied
/// schema snapshot is read and assigned to its source Stage, including unused
/// inputs. This is not whole-Environment admission or capacity authorization.
/// An optional SourceView declaration partition must belong to the exact source;
/// it is retained by each Stage, not resolved or admitted as Local row data.
pub fn prepare_environment(
  source : @stages.Source,
  environment : @environment.WireEnvironment,
  limits : Limits,
  sourceviews? : @sourceviews.Inputs? = None,
) -> Result[ProgramEnvironmentInputs, PrepareEnvironmentIssue] {
  let read = match
    begin_local_environment_preparation(
      source,
      environment,
      limits,
      sourceviews~,
    ) {
    Err(issue) => return Err(issue)
    Ok(read) => read
  }
  while true {
    match advance_local_environment_preparation(read) {
      LocalEnvironmentComplete | LocalEnvironmentFailed =>
        return take_local_environment_preparation_result(read).unwrap()
      LocalEnvironmentIndex
      | LocalEnvironmentGroups
      | LocalEnvironmentSnapshot
      | LocalEnvironmentDeclaration
      | LocalEnvironmentReconciliation
      | LocalEnvironmentAssembly => ()
      LocalEnvironmentTransferred | LocalEnvironmentRetired =>
        abort("unexposed original Local read cannot retire externally")
    }
  } nobreak {
    abort("original Local preparation returns at a terminal phase")
  }
}
