///|
pub(all) enum InputScoreIssue {
  WrongOrigin
  MissingField
  InvalidScore(Int)
  InvalidLimits
  Limit
}

///|
priv enum InputScorePhase {
  Declaration
  FindField
  SchemaName
  ScoreName
  CompareField
  Row
  Done
}

///|
// Original supplied-input obligations, not a ranking evaluator. The iterator
// borrows admitted field assertions; one declaration and no row copy are held.
priv struct InputScoreCursor {
  mut input : CapturedRows?
  mut supplied : SuppliedRelationRead?
  mut declarations : Iter[@evidence.DeclaredScore]?
  mut declaration : @evidence.DeclaredScore?
  control : ControlBudget
  workspace : RowWorkspace
  text_charge : BoundedTextCharge
  mut schema_index : Int
  mut row_index : Int
  mut phase : InputScorePhase
}

///|
fn input_score_cursor(
  input : CapturedRows,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[InputScoreCursor?, InputScoreIssue] {
  if control.remaining < 0 || workspace.limit < 0 || workspace.live != 0 {
    return Err(InvalidLimits)
  }
  guard input.origin is SuppliedInput(index) else { return Err(WrongOrigin) }
  let prepared = @lower.bound_preparation(input.owner)
  // A transferred producer input is already owned by its completed producer.
  // Its current aliases must not be mistaken for the original captured schema.
  if @lower.preparation_input_is_produced(prepared, index) { return Ok(None) }
  guard @lower.preparation_input_ranking(
    prepared, index,
  ) is Some(ranking) && @evidence.ranking_score_count(ranking) > 0 else {
    return Ok(None)
  }
  // Iterator and current assertion are charged to the existing operation space.
  if !reserve_slots(workspace, 2) { return Err(Limit) }
  Ok(Some({
    input: Some(input), supplied: None,
    declarations: Some(@evidence.ranking_score_declarations(ranking)),
    declaration: None, control, workspace,
    text_charge: { offset: 0, next: 0, remaining: 0, },
    schema_index: 0, row_index: 0, phase: Declaration,
  }))
}

///|
fn clear_input_score_cursor(state : InputScoreCursor) -> Bool {
  state.input = None
  state.supplied = None
  state.declarations = None
  state.declaration = None
  reset_bounded_text_charge(state.text_charge)
  if state.workspace.live > 0 { release_slots(state.workspace, 2) }
  state.phase = Done
  workspace_healthy(state.workspace) && state.workspace.live == 0
}

///|
fn step_input_score_cursor(state : InputScoreCursor) -> Result[Bool, InputScoreIssue] {
  if !spend_control(state.control, 1) { return Err(Limit) }
  let input = state.input.unwrap()
  match state.phase {
    Declaration => {
      guard state.declarations.unwrap().next() is Some(declaration) else {
        state.phase = Done
        return Ok(true)
      }
      state.declaration = Some(declaration)
      state.schema_index = 0
      state.phase = FindField
    }
    FindField => {
      if state.schema_index == @schema.field_count(input.schema) {
        return Err(MissingField)
      }
      reset_bounded_text_charge(state.text_charge)
      state.phase = SchemaName
    }
    SchemaName | ScoreName => {
      let field = if state.phase is SchemaName {
        @schema.field_at(input.schema, state.schema_index).unwrap().name
      } else {
        @evidence.declared_score_field(state.declaration.unwrap())
      }
      let done = match advance_bounded_text_charge(
        state.text_charge, state.control, @schema.reference_name(field),
      ) {
        Ok(done) => done
        Err(_) => return Err(Limit)
      }
      if done {
        reset_bounded_text_charge(state.text_charge)
        state.phase = if state.phase is SchemaName { ScoreName } else { CompareField }
      }
    }
    CompareField => {
      let field = @schema.field_at(input.schema, state.schema_index).unwrap()
      if field.name == @evidence.declared_score_field(state.declaration.unwrap()) {
        if field.presence != @schema.Required ||
          field.contract.nullable || !(field.contract.shape is Number) {
          return Err(MissingField)
        }
        state.row_index = 0
        state.phase = Row
      } else {
        state.schema_index += 1
        state.phase = FindField
      }
    }
    Row => {
      if state.row_index == captured_row_count(input) {
        state.declaration = None
        state.phase = Declaration
        return Ok(false)
      }
      let contract = @evidence.declared_score_contract(state.declaration.unwrap())
      guard captured_cell(input, state.row_index, state.schema_index)
        is Some(@admitted.Number(value)) && !value.is_nan() && !value.is_inf() &&
        value >= @evidence.score_contract_minimum(contract) &&
        value <= @evidence.score_contract_maximum(contract) else {
        return Err(InvalidScore(state.row_index))
      }
      state.row_index += 1
    }
    Done => return Ok(true)
  }
  Ok(false)
}

///|
fn validate_captured_scores(
  input : CapturedRows, control : ControlBudget, workspace : RowWorkspace,
) -> Result[Unit, InputScoreIssue] {
  let state = match input_score_cursor(input, control, workspace) {
    Ok(None) => return Ok(())
    Ok(Some(state)) => state
    Err(issue) => return Err(issue)
  }
  let mut result = Ok(())
  while !(state.phase is Done) {
    match step_input_score_cursor(state) {
      Ok(true) => break
      Ok(false) => ()
      Err(issue) => { result = Err(issue); break }
    }
  }
  clear_input_score_cursor(state) |> ignore
  result
}

///|
struct SuppliedScoreValidation {
  state : InputScoreCursor
  session : @bounded.Session[InputScoreCursor, Int, InputScoreIssue]
  mut token : @bounded.Token
}

///|
pub fn start_supplied_score_validation(
  engine : @bounded.Control, input : SuppliedRelationRead,
  max_work : Int, max_frames : Int, max_entries : Int,
) -> Result[SuppliedScoreValidation?, InputScoreIssue] {
  if max_work < 0 || max_frames < 0 || max_entries < 0 { return Err(InvalidLimits) }
  if !supplied_relation_read_available(input) { return Err(WrongOrigin) }
  let state = match input_score_cursor(
    input.rows, { remaining: max_work, max_frames, }, row_workspace(max_entries),
  ) {
    Ok(None) => return Ok(None)
    Ok(Some(state)) => state
    Err(issue) => return Err(issue)
  }
  state.supplied = Some(input)
  let (session, token) = @bounded.start(
    engine, state,
    (state, quantum, reader) => {
      let mut used = 0
      while used < quantum {
        if @bounded.stop_requested(reader) is Some(reason) {
          return @bounded.Stopped(reason, used, used)
        }
        guard state.supplied is Some(read) && supplied_relation_read_available(read) else {
          return @bounded.Failed(WrongOrigin, used, used)
        }
        used += 1
        match step_input_score_cursor(state) {
          Err(issue) => return @bounded.Failed(issue, used, used)
          Ok(true) => return @bounded.Complete(state.control.remaining, used, used)
          Ok(false) => ()
        }
      }
      @bounded.Continue(used, used)
    }, clear_input_score_cursor, _ => true,
  )
  Ok(Some({ state, session, token, }))
}

///|
pub fn advance_supplied_score_validation(
  validation : SuppliedScoreValidation, quantum : Int,
) -> Result[@bounded.Observation[Int, InputScoreIssue], @bounded.Issue] {
  let poll = match @bounded.advance(validation.session, validation.token, quantum) {
    Ok(poll) => poll
    Err(issue) => return Err(issue)
  }
  if poll is @bounded.ContinueWith(token, ..) { validation.token = token }
  Ok(poll)
}

///|
pub fn cleanup_supplied_score_validation(validation : SuppliedScoreValidation) -> Result[Bool, @bounded.Issue] {
  match @bounded.cleanup(validation.session) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(!@bounded.cleanup_pending(validation.session))
}
