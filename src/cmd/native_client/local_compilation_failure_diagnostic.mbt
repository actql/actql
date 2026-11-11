///|
// Closed existing compiler variants only. The original Result/cleanup stays
// authoritative; these optional counters carry no document, identity or message.
fn local_compilation_plan_tag(
  issue : @run_host.ClientValuesExecutablePlanIssue,
) -> Int64 {
  match issue {
    InvalidLimits => 1L
    Graph(_) => 2L
    TaskGraph(_) => 3L
    Material(_) => 4L
    Facts(_) => 5L
    Witnesses(_) => 6L
    FactManifest(_) => 7L
    Encoding => 8L
  }
}

///|
fn local_compilation_preparation_tag(
  issue : @local_values.ClientRequestPreparationIssue,
  emit : (Int, Int64) -> Unit,
) -> Int64 {
  match issue {
    ForeignOriginal => 1L
    WrongPhase => 2L
    Policy => 3L
    Initial(Resource(resource)) => {
      emit(13, local_submission_ledger_tag(resource))
      106L
    }
    Initial(_) => 100L
    Capacity(cause) | SnapshotCapacityExceeded(cause, _) =>
      match cause {
        ForeignOriginal => 201L
        WorkActive => 202L
        AlreadyCompleted => 203L
        AlreadyTransferred => 204L
        Retired => 205L
        BorrowReturned => 206L
        InvalidExtent => 207L
        Resource(resource) => {
          emit(13, local_submission_ledger_tag(resource))
          208L
        }
      }
    ProgramJson(_) => 4L
    ProgramCheck(_) => 5L
    Parameters(_) => 6L
    Intent(_) => 7L
    SourceInput(_) => 8L
    Work(cause) =>
      match cause {
        ForeignOriginal => 301L
        WrongPhase => 302L
        AlreadyClaimed => 303L
        Closed => 304L
        InvalidWork => 305L
        WorkLimit => 306L
        Stopping => 307L
      }
    ParameterDeclarations(_) => 9L
    ParameterSource(_) => 10L
  }
}

///|
fn local_compilation_failure_tags(
  issue : @local_values.ClientRequestProgramPlanIssue,
  emit : (Int, Int64) -> Unit,
) -> Unit {
  emit(10, 8L)
  let family = match issue {
    CapacityExceeded(_) => 1L
    Preparation(cause) => {
      emit(12, local_compilation_preparation_tag(cause, emit))
      2L
    }
    Installed(_) => 3L
    Construction(cause) => {
      emit(12, local_compilation_plan_tag(cause))
      4L
    }
    ValuesCompilation(cause) => {
      let tag = match cause {
        Plan(plan) => 100L + local_compilation_plan_tag(plan)
        Material(_) => 2L
        AoA(_) => 3L
        Fragment(_) => 4L
        Template(_) => 5L
        CompiledPlan(_) => 6L
      }
      emit(12, tag)
      5L
    }
    TaskCompilation(cause) => {
      let tag = match cause {
        Plan(plan) => 100L + local_compilation_plan_tag(plan)
        Material(_) => 2L
        Graph(_) => 3L
        Template(_) => 4L
        CompiledPlan(_) => 5L
        Encoding => 6L
        ForeignInferOwner => 7L
        ForeignSerializationOwner => 8L
      }
      emit(12, tag)
      6L
    }
    QueryTime(_) => 7L
    SerializationGraph(_) => 8L
    ModelGraph(_) => 9L
    ModelBinding(_) => 10L
    ModelQuery(_) => 11L
    ModelSource(_) => 12L
    ContentQuery(_) => 13L
    ContentSource(_) => 14L
  }
  emit(11, 6000L + family)
}
