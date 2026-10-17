///|
/// This is validation of an original Result traversal, never declaration of
/// a KeySet, a Source binding, a Reference issuer or an Effect dispatch permit.
pub(all) enum CompletedResultKeyIssue {
  Unavailable
  View(CompletedResultViewIssue)
  Key(InputKeyIssue)
}

///|
priv struct CompletedResultKeyState {
  mut original : CompletedResultRelationExportPreparation?
  mut field : @schema.Field?
  mut view : CompletedResultRowsPreparation?
  mut cursor : InputKeyCursor?
  max_work : Int
  max_frames : Int
  max_entries : Int
  mut completed : Bool
  mut retired : Bool
}

///|
/// The existing bounded Owner retains the original export and exact typed
/// field. Only whole-input completion plus private workspace retirement can
/// match that same pair. Raw/Artifact/physical custody is not retired here.
struct CompletedResultKeyValidation {
  state : CompletedResultKeyState
  session : @bounded.Session[
    CompletedResultKeyState,
    Int,
    CompletedResultKeyIssue,
  ]
  mut token : @bounded.Token
}

///|
fn clear_completed_result_key_state(state : CompletedResultKeyState) -> Bool {
  if state.cursor is Some(cursor) {
    if !clear_input_key_cursor(cursor) {
      return false
    }
    state.cursor = None
  }
  if state.view is Some(view) {
    cancel_completed_result_rows(view) |> ignore
    state.view = None
  }
  if !state.completed {
    state.original = None
    state.field = None
  }
  state.retired = true
  true
}

///|
/// Borrow the exact already checked Result export, including its original
/// occurrence/projection/order. No caller-supplied rows or key witness enters
/// this port. The view's original bounded row maps overlap the key workspace;
/// these structural ceilings are not a normal byte-capacity supplier.
pub fn start_completed_result_key_validation(
  engine : @bounded.Control,
  original : CompletedResultRelationExportPreparation,
  field : @schema.Field,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
) -> Result[CompletedResultKeyValidation, CompletedResultKeyIssue] {
  if max_work < 0 || max_frames < 0 || max_entries < 0 {
    return Err(Key(InvalidLimits))
  }
  if field.contract.nullable {
    return Err(Key(NullableWitnessPending))
  }
  if !@contract.key_comparable(field.contract, field.contract) {
    return Err(Key(UnsupportedKeyDomain))
  }
  let view = match
    start_completed_result_rows(
      original.rows.source,
      original.rows.occurrence,
      original.rows.limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(View(issue))
  }
  let state : CompletedResultKeyState = {
    original: Some(original),
    field: Some(field),
    view: Some(view),
    cursor: None,
    max_work,
    max_frames,
    max_entries,
    completed: false,
    retired: false,
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    (state, quantum, reader) -> @bounded.KernelStep[Int, CompletedResultKeyIssue] => {
      let mut used = 0
      while used < quantum {
        if @bounded.stop_requested(reader) is Some(reason) {
          return @bounded.Stopped(reason, used, used)
        }
        guard state.original is Some(original) && state.field is Some(field) else {
          return @bounded.Failed(Unavailable, used, used)
        }
        let available = completed_output_available(original.rows.source)
        if !available || state.retired || state.original is None {
          return @bounded.Failed(Unavailable, used, used)
        }
        used += 1
        if state.view is Some(view) {
          let done = match advance_completed_result_rows(view, 1) {
            Ok((done, _)) => done
            Err(issue) => return @bounded.Failed(View(issue), used, used)
          }
          if done {
            let rows = match finish_completed_result_rows(view) {
              Ok(rows) => rows
              Err(issue) => return @bounded.Failed(View(issue), used, used)
            }
            if IndexedRows::row_count(rows) > original.max_rows {
              return @bounded.Failed(Key(Limit), used, used)
            }
            let cursor = match
              input_key_rows_cursor(
                ResultKeyRows(rows),
                None,
                Some(field),
                { remaining: state.max_work, max_frames: state.max_frames, },
                row_workspace(state.max_entries),
              ) {
              Ok(cursor) => cursor
              Err(issue) => return @bounded.Failed(Key(issue), used, used)
            }
            state.cursor = Some(cursor)
            state.view = None
          }
        } else {
          let cursor = state.cursor.unwrap()
          match step_input_key_cursor(cursor) {
            Err(issue) => return @bounded.Failed(Key(issue), used, used)
            Ok(false) => ()
            Ok(true) => {
              if !completed_output_available(original.rows.source) ||
                state.retired ||
                state.original is None {
                return @bounded.Failed(Unavailable, used, used)
              }
              state.completed = true
              return @bounded.Complete(cursor.control.remaining, used, used)
            }
          }
        }
      }
      @bounded.Continue(used, used)
    },
    clear_completed_result_key_state,
    _ => true,
  )
  Ok({ state, session, token, })
}

///|
pub fn advance_completed_result_key_validation(
  value : CompletedResultKeyValidation,
  quantum : Int,
) -> Result[@bounded.Observation[Int, CompletedResultKeyIssue], @bounded.Issue] {
  let poll = match @bounded.advance(value.session, value.token, quantum) {
    Ok(poll) => poll
    Err(issue) => return Err(issue)
  }
  if poll is @bounded.ContinueWith(token, ..) {
    value.token = token
  }
  Ok(poll)
}

///|
pub fn cleanup_completed_result_key_validation(
  value : CompletedResultKeyValidation,
) -> Result[Bool, @bounded.Issue] {
  match @bounded.cleanup(value.session) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(!@bounded.cleanup_pending(value.session))
}

///|
/// Exact original references and current source remain necessary after all
/// values were checked. Equal schema/rows/CIDs cannot replace this pair.
pub fn completed_result_key_validation_matches(
  value : CompletedResultKeyValidation,
  original : CompletedResultRelationExportPreparation,
  field : @schema.Field,
) -> Bool {
  let state = value.state
  if !state.completed ||
    !state.retired ||
    !state.original
    .map(actual => physical_equal(actual, original))
    .unwrap_or(false) ||
    !state.field.map(actual => physical_equal(actual, field)).unwrap_or(false) {
    return false
  }
  let available = completed_output_available(original.rows.source)
  available && state.completed && state.retired && state.original is Some(_)
}
