///|
priv enum BeforePhase {
  AdmitBefore
  RecheckActual
  CompareBefore
  BeforeFinished
}

///|
/// Complete-before equality uses the same Value admission and comparison owners
/// as Diff. It compares ordinary wire data, never reference authority.
priv struct BeforeAdmission {
  limits : @value.Limits
  mut phase : BeforePhase
  mut actual : @value.Value?
  mut admission : @value.JsonAdmission?
  mut recheck : @value.RecheckCursor?
  mut before : @value.CheckedValue?
  mut comparison : @value.CompleteEquality?
}

///|
priv enum BeforePoll {
  BeforeContinue(work~ : Int)
  BeforeComplete(work~ : Int)
  BeforeFailed(Issue, work~ : Int)
}

///|
fn before_workspace_slots(limits : Limits) -> Int? {
  // The admitted record and its object-name/sort indexes coexist with the base
  // body. Recheck/equality continuations also coexist with the checked record.
  guard checked_add(limits.max_identity_nodes, limits.max_identity_nodes)
    is Some(n2) &&
    checked_add(n2, n2) is Some(n4) &&
    checked_add(n4, n4) is Some(n8) &&
    checked_add(limits.max_identity_depth, limits.max_identity_depth)
    is Some(d2) &&
    checked_add(d2, d2) is Some(d4) &&
    checked_add(n8, d4) is Some(records) else {
    return None
  }
  checked_add(records, 32)
}

///|
fn start_before(
  before : @decode.Cursor,
  actual : @value.Value,
  limits : Limits,
) -> BeforeAdmission? {
  let limits : @value.Limits = {
    max_nodes: limits.max_identity_nodes,
    max_depth: limits.max_identity_depth,
    max_text_bytes: limits.max_identity_bytes,
  }
  guard @value.start_json_admission(before, limits) is Ok(admission) else {
    return None
  }
  Some({
    limits,
    phase: AdmitBefore,
    actual: Some(actual),
    admission: Some(admission),
    recheck: None,
    before: None,
    comparison: None,
  })
}

///|
fn advance_before(check : BeforeAdmission, quantum : Int) -> BeforePoll {
  let mut used = 0
  while used < quantum {
    match check.phase {
      AdmitBefore => {
        guard check.admission is Some(admission) else {
          return BeforeFailed(Terminal, work=used)
        }
        used += 1
        match @value.advance_json_admission(admission) {
          @value.JsonAdmissionContinue => ()
          @value.JsonAdmissionComplete(before, _, _) => {
            check.admission = None
            check.before = Some(before)
            guard check.actual is Some(actual) &&
              @value.start_recheck_runtime_value(
                actual,
                json_contract(),
                check.limits,
              )
              is Some(recheck) else {
              return BeforeFailed(BeforeMismatch, work=used)
            }
            check.actual = None
            check.recheck = Some(recheck)
            check.phase = RecheckActual
          }
          @value.JsonAdmissionFailed(_) =>
            return BeforeFailed(BeforeMismatch, work=used)
          @value.JsonAdmissionTerminal =>
            return BeforeFailed(Terminal, work=used)
        }
      }
      RecheckActual => {
        guard check.recheck is Some(recheck) else {
          return BeforeFailed(Terminal, work=used)
        }
        used += 1
        match @value.advance_recheck_runtime_value(recheck) {
          @value.RecheckContinue => ()
          @value.RecheckComplete(actual, _, _) => {
            check.recheck = None
            guard check.before is Some(before) else {
              return BeforeFailed(Terminal, work=used)
            }
            check.comparison = match
              @value.start_complete_equality(before, actual, check.limits) {
              Ok(comparison) => Some(comparison)
              Err(issue) => return BeforeFailed(Comparison(issue), work=used)
            }
            check.before = None
            check.phase = CompareBefore
          }
          @value.RecheckFailed => return BeforeFailed(BeforeMismatch, work=used)
        }
      }
      CompareBefore => {
        guard check.comparison is Some(comparison) else {
          return BeforeFailed(Terminal, work=used)
        }
        match @value.advance_complete_equality(comparison, quantum - used) {
          @value.EqualityContinue(work~) => used += work
          @value.EqualityComplete(equal~, work~) => {
            used += work
            check.comparison = None
            check.phase = BeforeFinished
            return if equal {
              BeforeComplete(work=used)
            } else {
              BeforeFailed(BeforeMismatch, work=used)
            }
          }
          @value.EqualityFailed(issue, work~) =>
            return BeforeFailed(Comparison(issue), work=used + work)
        }
      }
      BeforeFinished => return BeforeFailed(Terminal, work=used)
    }
  }
  BeforeContinue(work=used)
}

///|
fn cleanup_before(check : BeforeAdmission) -> Unit {
  if check.admission is Some(admission) {
    @value.cancel_json_admission(admission)
  }
  if check.recheck is Some(recheck) {
    @value.cancel_recheck_runtime_value(recheck)
  }
  check.actual = None
  check.admission = None
  check.recheck = None
  check.before = None
  check.comparison = None
  check.phase = BeforeFinished
}
