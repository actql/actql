///|
/// Admitted, homogeneous key fields keep their type domains. Arrays used as
/// compound keys are private and never mutated while retained by the map.
/// Retirement removes each map key before clearing its owned tuple.
priv enum KeyAtom {
  KeyNumber(Double)
  KeyBoolean(Bool)
  KeyText(String)
  KeyDate(String)
  KeyTimestamp(String)
  KeyDecimal(String, Int)
  KeyReference(String)
} derive(Eq, Hash)

///|
pub(all) enum InputKeyIssue {
  WrongOrigin
  MissingField
  NullKey(Int)
  UnsupportedKeyDomain
  NullableWitnessPending
  DuplicateKey(Int, Int)
  InvalidLimits
  Limit
}

///|
priv enum InputKeyPhase {
  KeyStart
  FieldStart
  FindField
  SchemaNameCharge
  KeyNameCharge
  CompareField
  CompareKeyType
  RowStart
  CellStart
  AtomCharge
  CommitTuple
  RetireKey
  KeyDone
}

///|
/// Private adapters over already admitted original rows. Neither variant is
/// an input declaration, a key witness or permission to read another owner.
priv enum InputKeyRows {
  CapturedKeyRows(CapturedRows)
  ResultKeyRows(CompletedExportRows)
}

///|
fn input_key_rows_schema(rows : InputKeyRows) -> @schema.Schema {
  match rows {
    CapturedKeyRows(value) => value.schema
    ResultKeyRows(value) => value.schema
  }
}

///|
fn input_key_rows_count(rows : InputKeyRows) -> Int {
  match rows {
    CapturedKeyRows(value) => captured_row_count(value)
    ResultKeyRows(value) => IndexedRows::row_count(value)
  }
}

///|
fn input_key_rows_cell(rows : InputKeyRows, row : Int, column : Int) -> Value? {
  match rows {
    CapturedKeyRows(value) => captured_cell(value, row, column).map(capture)
    ResultKeyRows(value) =>
      if row < 0 ||
        row >= IndexedRows::row_count(value) ||
        column < 0 ||
        column >= IndexedRows::column_count(value) ||
        !IndexedRows::cell_present(value, row, column) {
        None
      } else {
        Some(IndexedRows::read_cell(value, row, column))
      }
  }
}

///|
// The original key validator's state. Both the synchronous sequence driver
// and the supplied-input bounded driver use this same domain and algorithm.
priv struct InputKeyCursor {
  mut input : InputKeyRows?
  mut supplied : SuppliedRelationRead?
  mut keys : @evidence.KeySet?
  mut explicit_field : @schema.Field?
  mut type_equality : @contract.TypeEquality?
  mut type_frames : Int
  control : ControlBudget
  workspace : RowWorkspace
  baseline : Int
  columns : Array[Int]
  mut seen : Map[Array[KeyAtom], Int]
  mut retiring_entries : Iter[(Array[KeyAtom], Int)]?
  mut retiring_tuple : Array[KeyAtom]?
  mut tuple : Array[KeyAtom]
  mut field : @evidence.KeyField?
  mut atom : KeyAtom?
  text_charge : BoundedTextCharge
  mut phase : InputKeyPhase
  mut key_index : Int
  mut field_index : Int
  mut schema_index : Int
  mut row_index : Int
  mut cell_index : Int
}

///|
fn input_key_cursor(
  input : CapturedRows,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[InputKeyCursor, InputKeyIssue] {
  if control.remaining < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit {
    return Err(InvalidLimits)
  }
  guard input.origin is SuppliedInput(index) else { return Err(WrongOrigin) }
  let keys = @lower.preparation_input_keys(
    @lower.bound_preparation(input.owner),
    index,
  )
  input_key_rows_cursor(CapturedKeyRows(input), keys, None, control, workspace)
}

///|
fn input_key_rows_cursor(
  input : InputKeyRows,
  keys : @evidence.KeySet?,
  explicit_field : @schema.Field?,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[InputKeyCursor, InputKeyIssue] {
  if control.remaining < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit {
    return Err(InvalidLimits)
  }
  Ok({
    input: Some(input),
    supplied: None,
    keys,
    explicit_field,
    type_equality: None,
    type_frames: 0,
    control,
    workspace,
    baseline: workspace.live,
    columns: [],
    seen: Map([]),
    retiring_entries: None,
    retiring_tuple: None,
    tuple: [],
    field: None,
    atom: None,
    text_charge: { offset: 0, next: 0, remaining: 0, },
    phase: if keys is None && explicit_field is None {
      KeyDone
    } else {
      KeyStart
    },
    key_index: 0,
    field_index: 0,
    schema_index: 0,
    row_index: 0,
    cell_index: 0,
  })
}

///|
fn input_key_selected_name(state : InputKeyCursor) -> @schema.FieldName {
  match state.field {
    Some(field) => field.name
    None => state.explicit_field.unwrap().name
  }
}

///|
fn input_key_atom(cell : Value, row : Int) -> Result[KeyAtom, InputKeyIssue] {
  match cell {
    Null => Err(NullKey(row))
    Number(n) => Ok(KeyNumber(n))
    Boolean(b) => Ok(KeyBoolean(b))
    Text(s) => Ok(KeyText(s))
    Captured(value) => input_key_admitted_atom(value, row)
  }
}

///|
fn input_key_admitted_atom(
  cell : @admitted.Value,
  row : Int,
) -> Result[KeyAtom, InputKeyIssue] {
  match cell {
    @admitted.Null => Err(NullKey(row))
    @admitted.Number(n) => Ok(KeyNumber(n))
    @admitted.Boolean(b) => Ok(KeyBoolean(b))
    @admitted.Text(s) => Ok(KeyText(s))
    @admitted.Date(s) => Ok(KeyDate(s))
    @admitted.Timestamp(s) => Ok(KeyTimestamp(s))
    @admitted.Decimal(d) => Ok(KeyDecimal(d.coefficient, d.scale))
    @admitted.Reference(reference) =>
      if @admitted.reference_available(reference) {
        Ok(KeyReference(@admitted.reference_identity_cid(reference)))
      } else {
        Err(Limit)
      }
    @admitted.Array(_)
    | @admitted.Object(_)
    | @admitted.Vector(_)
    | @admitted.JsonData(_) => Err(UnsupportedKeyDomain)
  }
}

///|
fn input_key_atom_text(atom : KeyAtom) -> String? {
  match atom {
    KeyText(text)
    | KeyDate(text)
    | KeyTimestamp(text)
    | KeyDecimal(text, _)
    | KeyReference(text) => Some(text)
    KeyNumber(_) | KeyBoolean(_) => None
  }
}

///|
// Retire one owned tuple atom, map entry or column reference. Removing a map
// key precedes mutating its private tuple. The insertion-order iterator keeps
// only the next entry, so no duplicate array of all keys is allocated.
fn retire_input_key_entry(state : InputKeyCursor) -> Bool {
  if state.tuple.pop() is Some(_) {
    release_slots(state.workspace, 1)
    return false
  }
  if state.retiring_tuple is Some(tuple) {
    if tuple.pop() is Some(_) {
      release_slots(state.workspace, 1)
      return false
    }
    state.retiring_tuple = None
    release_slots(state.workspace, 1)
    return false
  }
  if state.retiring_entries is None {
    state.retiring_entries = Some(state.seen.iter())
  }
  if state.retiring_entries.unwrap().next() is Some((tuple, _)) {
    state.seen.remove(tuple)
    state.retiring_tuple = Some(tuple)
    return false
  }
  if state.columns.pop() is Some(_) {
    release_slots(state.workspace, 1)
    return false
  }
  state.retiring_entries = None
  state.seen = Map([])
  state.field = None
  if state.type_equality is Some(cursor) {
    @contract.cancel_type_equality(cursor)
    state.type_equality = None
  }
  if state.type_frames > 0 {
    release_slots(state.workspace, state.type_frames)
    state.type_frames = 0
  }
  state.atom = None
  reset_bounded_text_charge(state.text_charge)
  state.workspace.live == state.baseline && workspace_healthy(state.workspace)
}

///|
fn clear_input_key_cursor(state : InputKeyCursor) -> Bool {
  if !retire_input_key_entry(state) {
    return false
  }
  state.input = None
  state.supplied = None
  state.keys = None
  state.explicit_field = None
  state.phase = KeyDone
  true
}

///|
// One continuation transition. Existing control charges and live key entries
// are retained; text uses the shared resumable UTF-8 charge, without NFC/LF
// repair. The map's typed equality is the original key-equality contract.
fn step_input_key_cursor(state : InputKeyCursor) -> Result[Bool, InputKeyIssue] {
  let input = state.input.unwrap()
  match state.phase {
    KeyStart => {
      let count = match state.keys {
        Some(keys) => @evidence.key_witness_count(keys)
        None => if state.explicit_field is Some(_) { 1 } else { 0 }
      }
      if state.key_index == count {
        state.phase = KeyDone
        return Ok(true)
      }
      if !spend_control(state.control, 1) {
        return Err(Limit)
      }
      state.field_index = 0
      state.phase = FieldStart
    }
    FieldStart => {
      let key = state.keys.bind(keys => {
        @evidence.key_witness_at(keys, state.key_index)
      })
      let count = match key {
        Some(key) => @evidence.key_field_count(key)
        None => 1
      }
      if state.field_index == count {
        state.row_index = 0
        state.phase = RowStart
        return Ok(false)
      }
      if !spend_control(state.control, 1) || !reserve_slots(state.workspace, 1) {
        return Err(Limit)
      }
      let field = key.bind(key => @evidence.key_field_at(key, state.field_index))
      // The field's reserved column slot exists even if schema lookup fails.
      state.columns.push(-1)
      let contract = match field {
        Some(field) => field.contract
        None => state.explicit_field.map(field => field.contract)
      }
      if contract is Some(contract) && contract.nullable {
        return Err(NullableWitnessPending)
      }
      state.field = field
      state.schema_index = 0
      state.phase = FindField
    }
    FindField => {
      if state.schema_index == @schema.field_count(input_key_rows_schema(input)) {
        return Err(MissingField)
      }
      if !spend_control(state.control, 1) {
        return Err(Limit)
      }
      reset_bounded_text_charge(state.text_charge)
      state.phase = SchemaNameCharge
    }
    SchemaNameCharge | KeyNameCharge => {
      let text = if state.phase is SchemaNameCharge {
        @schema.reference_name(
          @schema.field_at(input_key_rows_schema(input), state.schema_index).unwrap().name,
        )
      } else {
        @schema.reference_name(input_key_selected_name(state))
      }
      let done = match
        advance_bounded_text_charge(state.text_charge, state.control, text) {
        Ok(done) => done
        Err(_) => return Err(Limit)
      }
      if done {
        reset_bounded_text_charge(state.text_charge)
        state.phase = if state.phase is SchemaNameCharge {
          KeyNameCharge
        } else {
          CompareField
        }
      }
    }
    CompareField => {
      let field = @schema.field_at(
        input_key_rows_schema(input),
        state.schema_index,
      ).unwrap()
      if field.name == input_key_selected_name(state) {
        if field.presence != @schema.Required {
          return Err(MissingField)
        }
        state.columns[state.columns.length() - 1] = state.schema_index
        if state.explicit_field is Some(selected) {
          if state.control.max_frames < 1 || !reserve_slots(state.workspace, 1) {
            return Err(Limit)
          }
          state.type_frames = 1
          let cursor = @contract.start_type_equality(
            field.contract,
            selected.contract,
            state.control.remaining,
          ) catch {
            _ => return Err(Limit)
          }
          state.type_equality = Some(cursor)
          state.phase = CompareKeyType
        } else {
          state.field_index += 1
          state.phase = FieldStart
        }
      } else {
        state.schema_index += 1
        state.phase = FindField
      }
    }
    CompareKeyType => {
      if !spend_control(state.control, 1) {
        return Err(Limit)
      }
      let cursor = state.type_equality.unwrap()
      let frames = @contract.type_equality_next_frames(cursor)
      if frames > state.control.max_frames ||
        (
          frames > state.type_frames &&
          !reserve_slots(state.workspace, frames - state.type_frames)
        ) {
        return Err(Limit)
      }
      state.type_frames = Int::max(state.type_frames, frames)
      let done = @contract.advance_type_equality(cursor) catch {
        _ => return Err(Limit)
      }
      if done is Some(equal) {
        @contract.cancel_type_equality(cursor)
        state.type_equality = None
        release_slots(state.workspace, state.type_frames)
        state.type_frames = 0
        if !equal {
          return Err(UnsupportedKeyDomain)
        }
        state.field_index += 1
        state.phase = FieldStart
      }
    }
    RowStart => {
      if state.row_index == input_key_rows_count(input) {
        state.phase = RetireKey
        return Ok(false)
      }
      if !spend_control(state.control, 1) {
        return Err(Limit)
      }
      state.cell_index = 0
      state.phase = CellStart
    }
    CellStart => {
      if state.cell_index == state.columns.length() {
        state.phase = CommitTuple
        return Ok(false)
      }
      if !spend_control(state.control, 1) || !reserve_slots(state.workspace, 1) {
        return Err(Limit)
      }
      // Keep a reserved slot visible to failure cleanup before cell admission.
      state.tuple.push(KeyBoolean(false))
      guard input_key_rows_cell(
          input,
          state.row_index,
          state.columns[state.cell_index],
        )
        is Some(cell) else {
        return Err(MissingField)
      }
      let atom = match input_key_atom(cell, state.row_index) {
        Ok(atom) => atom
        Err(issue) => return Err(issue)
      }
      state.tuple[state.tuple.length() - 1] = atom
      if input_key_atom_text(atom) is Some(_) {
        state.atom = Some(atom)
        reset_bounded_text_charge(state.text_charge)
        state.phase = AtomCharge
      } else {
        state.cell_index += 1
      }
    }
    AtomCharge => {
      let done = match
        advance_bounded_text_charge(
          state.text_charge,
          state.control,
          input_key_atom_text(state.atom.unwrap()).unwrap(),
        ) {
        Ok(done) => done
        Err(_) => return Err(Limit)
      }
      if done {
        state.atom = None
        state.cell_index += 1
        state.phase = CellStart
      }
    }
    CommitTuple => {
      if state.seen.get(state.tuple) is Some(previous) {
        return Err(DuplicateKey(previous, state.row_index))
      }
      if !reserve_slots(state.workspace, 1) {
        return Err(Limit)
      }
      state.seen[state.tuple] = state.row_index
      state.tuple = []
      state.row_index += 1
      state.phase = RowStart
    }
    RetireKey =>
      if retire_input_key_entry(state) {
        state.key_index += 1
        state.phase = KeyStart
      }
    KeyDone => return Ok(true)
  }
  Ok(false)
}

///|
fn validate_captured_keys(
  input : CapturedRows,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Unit, InputKeyIssue] {
  let state = match input_key_cursor(input, control, workspace) {
    Ok(state) => state
    Err(issue) => return Err(issue)
  }
  let mut failure : InputKeyIssue? = None
  while !(state.phase is KeyDone) {
    match step_input_key_cursor(state) {
      Ok(true) => break
      Ok(false) => ()
      Err(issue) => {
        failure = Some(issue)
        break
      }
    }
  }
  while !clear_input_key_cursor(state) {
    ()
  }
  match failure {
    Some(issue) => Err(issue)
    None => Ok(())
  }
}

///|
/// The same conditional input-key validation, resumed by its existing Owner.
/// It borrows one exact complete supplied input and issues no Source evidence.
struct SuppliedKeyValidation {
  state : InputKeyCursor
  session : @bounded.Session[InputKeyCursor, Int, InputKeyIssue]
  mut token : @bounded.Token
}

///|
pub fn start_supplied_key_validation(
  engine : @bounded.Control,
  input : SuppliedRelationRead,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
) -> Result[SuppliedKeyValidation?, InputKeyIssue] {
  if max_work < 0 || max_frames < 0 || max_entries < 0 {
    return Err(InvalidLimits)
  }
  if !supplied_relation_read_available(input) {
    return Err(WrongOrigin)
  }
  let state = match
    input_key_cursor(
      input.rows,
      { remaining: max_work, max_frames, },
      row_workspace(max_entries),
    ) {
    Ok(state) => state
    Err(issue) => return Err(issue)
  }
  if state.keys is None {
    return Ok(None)
  }
  state.supplied = Some(input)
  let (session, token) = @bounded.start(
    engine,
    state,
    (state, quantum, reader) => {
      let mut used = 0
      while used < quantum {
        if @bounded.stop_requested(reader) is Some(reason) {
          return @bounded.Stopped(reason, used, used)
        }
        guard state.supplied is Some(read) &&
          supplied_relation_read_available(read) else {
          return @bounded.Failed(InputKeyIssue::WrongOrigin, used, used)
        }
        used += 1
        match step_input_key_cursor(state) {
          Err(issue) => return @bounded.Failed(issue, used, used)
          Ok(true) =>
            return @bounded.Complete(state.control.remaining, used, used)
          Ok(false) => ()
        }
      }
      @bounded.Continue(used, used)
    },
    clear_input_key_cursor,
    _ => true,
  )
  Ok(Some({ state, session, token, }))
}

///|
pub fn advance_supplied_key_validation(
  validation : SuppliedKeyValidation,
  quantum : Int,
) -> Result[@bounded.Observation[Int, InputKeyIssue], @bounded.Issue] {
  let poll = match
    @bounded.advance(validation.session, validation.token, quantum) {
    Ok(poll) => poll
    Err(issue) => return Err(issue)
  }
  if poll is @bounded.ContinueWith(token, ..) {
    validation.token = token
  }
  Ok(poll)
}

///|
pub fn cleanup_supplied_key_validation(
  validation : SuppliedKeyValidation,
) -> Result[Bool, @bounded.Issue] {
  match @bounded.cleanup(validation.session) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(!@bounded.cleanup_pending(validation.session))
}

///|
pub fn supplied_key_validation_peak_entries(
  validation : SuppliedKeyValidation,
) -> Int {
  validation.state.workspace.peak
}
