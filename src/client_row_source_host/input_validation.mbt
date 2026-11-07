///|
/// Existing input fact validators, retained by this same RowRun before any
/// callback can cancel their construction or advancement. This is no Reader,
/// acquisition issuer or independent resource/lifecycle owner.
priv struct RowInputValidation {
  input : @execution.AdmittedInput
  read : @execution.SuppliedRelationRead
  control : @bounded.Control
  max_entries : Int
  max_frames : Int
  mut remaining : Int
  mut work : Int64
  mut score_base : Int64
  mut keys : @execution.SuppliedKeyValidation?
  mut scores : @execution.SuppliedScoreValidation?
  mut phase : Int
  mut constructing : Bool
}

///|
fn begin_input_row_capture(run : RowRun) -> Result[Unit, RowHostIssue] {
  guard !run.closed &&
    run.configuration is InputConfiguration(acquisition) &&
    run.attempt.state is InputAwaitingCleanup(rows, input) else {
    return Err(InvalidState)
  }
  if !input_row_capture_live(run) {
    return Err(Evidence(UnverifiedTransport))
  }
  if run.physical is Some(_) {
    match fund_row_input_capture(run, acquisition, rows) {
      Ok(_) => ()
      Err(issue) => {
        abort_row_run(run)
        return Err(issue)
      }
    }
    guard input_row_capture_live(run) &&
      run.attempt.state is InputAwaitingCleanup(current, _) &&
      physical_equal(current, rows) else {
      return Err(InvalidState)
    }
  }
  let original = acquisition.preparation
  let read = match
    @execution.prepare_supplied_relation_read(
      original.owner,
      original.input_index,
      rows,
      () => input_row_capture_live(run),
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidState)
  }
  let admitted = @execution.captured_usage(rows).work
  if admitted > original.limits.retention.max_work {
    return Err(Source(InvalidPage))
  }
  guard !run.closed &&
    run.attempt.state is InputAwaitingCleanup(actual, _) &&
    physical_equal(actual, rows) else {
    return Err(InvalidState)
  }
  run.attempt.state = InputValidating({
    input,
    read,
    control: @bounded.control(),
    max_entries: original.limits.retention.max_nodes,
    max_frames: original.limits.retention.max_depth,
    remaining: original.limits.retention.max_work - admitted,
    work: 0L,
    score_base: 0L,
    keys: None,
    scores: None,
    phase: 0,
    constructing: false,
  })
  Ok(())
}

///|
fn input_validation_current(
  run : RowRun,
  validation : RowInputValidation,
) -> Bool {
  !run.closed &&
  run.attempt.state is InputValidating(actual) &&
  physical_equal(actual, validation) &&
  input_row_capture_live(run) &&
  !run.closed &&
  run.attempt.state is InputValidating(after) &&
  physical_equal(after, validation)
}

///|
fn advance_input_row_capture(
  run : RowRun,
  quantum : Int,
) -> Result[(Bool, Int64), RowHostIssue] {
  if quantum <= 0 {
    return Err(InvalidState)
  }
  if run.attempt.state is InputValidated(value) {
    return if input_row_capture_live(run) {
      Ok((true, value.work))
    } else {
      Err(InvalidState)
    }
  }
  guard run.attempt.state is InputValidating(value) &&
    input_validation_current(run, value) else {
    return Err(InvalidState)
  }
  match value.phase {
    0 => {
      value.constructing = true
      let started = @execution.start_supplied_key_validation(
        value.control,
        value.read,
        value.remaining,
        value.max_frames,
        value.max_entries,
      )
      match started {
        Ok(cursor) => {
          value.keys = cursor
          value.phase = if cursor is Some(_) { 1 } else { 3 }
        }
        Err(issue) => {
          value.constructing = false
          abort_row_run(run)
          return Err(InputKeys(issue))
        }
      }
      value.constructing = false
    }
    1 => {
      guard value.keys is Some(cursor) else { return Err(InvalidState) }
      match @execution.advance_supplied_key_validation(cursor, quantum) {
        Ok(@bounded.ContinueWith(_, work~, ..)) => value.work = work
        Ok(@bounded.Completed(remaining, work~, ..)) => {
          value.remaining = remaining
          value.work = work
          value.phase = 2
        }
        Ok(@bounded.FailedWith(issue, ..)) => {
          abort_row_run(run)
          return Err(InputKeys(issue))
        }
        Ok(@bounded.StoppedWith(_, ..)) => {
          abort_row_run(run)
          return Err(InvalidState)
        }
        Err(issue) => {
          abort_row_run(run)
          return Err(InputValidationWork(issue))
        }
      }
    }
    2 => {
      guard value.keys is Some(cursor) else { return Err(InvalidState) }
      match @execution.cleanup_supplied_key_validation(cursor) {
        Ok(true) => {
          value.keys = None
          value.phase = 3
        }
        Ok(false) => ()
        Err(issue) => {
          abort_row_run(run)
          return Err(InputValidationWork(issue))
        }
      }
    }
    3 => {
      value.score_base = value.work
      value.constructing = true
      let started = @execution.start_supplied_score_validation(
        value.control,
        value.read,
        value.remaining,
        value.max_frames,
        value.max_entries,
      )
      match started {
        Ok(cursor) => {
          value.scores = cursor
          value.phase = if cursor is Some(_) { 4 } else { 6 }
        }
        Err(issue) => {
          value.constructing = false
          abort_row_run(run)
          return Err(InputScores(issue))
        }
      }
      value.constructing = false
    }
    4 => {
      guard value.scores is Some(cursor) else { return Err(InvalidState) }
      match @execution.advance_supplied_score_validation(cursor, quantum) {
        Ok(@bounded.ContinueWith(_, work~, ..)) =>
          value.work = value.score_base + work
        Ok(@bounded.Completed(remaining, work~, ..)) => {
          value.remaining = remaining
          value.work = value.score_base + work
          value.phase = 5
        }
        Ok(@bounded.FailedWith(issue, ..)) => {
          abort_row_run(run)
          return Err(InputScores(issue))
        }
        Ok(@bounded.StoppedWith(_, ..)) => {
          abort_row_run(run)
          return Err(InvalidState)
        }
        Err(issue) => {
          abort_row_run(run)
          return Err(InputValidationWork(issue))
        }
      }
    }
    5 => {
      guard value.scores is Some(cursor) else { return Err(InvalidState) }
      match @execution.cleanup_supplied_score_validation(cursor) {
        Ok(true) => {
          value.scores = None
          value.phase = 6
        }
        Ok(false) => ()
        Err(issue) => {
          abort_row_run(run)
          return Err(InputValidationWork(issue))
        }
      }
    }
    _ => ()
  }
  if !input_validation_current(run, value) {
    return Err(InvalidState)
  }
  if value.phase == 6 {
    run.attempt.state = InputValidated(value)
    Ok((true, value.work))
  } else {
    Ok((false, value.work))
  }
}

///|
fn cleanup_input_validation(value : RowInputValidation) -> Bool {
  if value.constructing {
    return false
  }
  @bounded.request_cancel(value.control) |> ignore
  if value.keys is Some(cursor) {
    match @execution.cleanup_supplied_key_validation(cursor) {
      Ok(true) => value.keys = None
      Ok(false) => return false
      Err(@bounded.NotStopped) => {
        @execution.advance_supplied_key_validation(cursor, 1) |> ignore
        return false
      }
      Err(_) => return false
    }
  }
  if value.scores is Some(cursor) {
    match @execution.cleanup_supplied_score_validation(cursor) {
      Ok(true) => value.scores = None
      Ok(false) => return false
      Err(@bounded.NotStopped) => {
        @execution.advance_supplied_score_validation(cursor, 1) |> ignore
        return false
      }
      Err(_) => return false
    }
  }
  true
}
