///|
/// Structural dimensions retained by the original envelope construction.
/// Container shapes only: no expression/type/schema acceptance or permission.
pub(all) struct ProgramPreparationData {
  operations : Int
  effect_members : Int
  results : Int
  external_inputs : Int
  initial_fields : Int
  possible_growth : Int
  projected_fields : Int
  max_label_utf16 : Int
  may_contain_expression_syntax : Bool
} derive(Eq, Debug)

///|
priv struct ProgramPreparationState {
  mut operations : Int
  mut effect_members : Int
  mut results : Int
  mut external_inputs : Int
  mut initial_fields : Int
  mut possible_growth : Int
  mut projected_fields : Int
  mut max_label_utf16 : Int
  mut may_contain_expression_syntax : Bool
}

///|
fn preparation_member(root : @wire.Cursor, name : String) -> @wire.Cursor? {
  for index in 0..<@wire.object_length(root).unwrap_or(0) {
    let (key, value) = @wire.field_at(root, index).unwrap()
    if key == name {
      return Some(value)
    }
  }
  None
}

///|
fn preparation_schema(
  root : @wire.Cursor,
  state : ProgramPreparationState,
) -> Unit {
  if preparation_member(root, "schema") is Some(schema) {
    state.initial_fields = Int::max(
      state.initial_fields,
      @wire.object_length(schema).unwrap_or(0),
    )
  }
}

///|
// Called inside the original Stage/steps construction, never by a later quote.
// Literal row bodies stay linear data; they cannot become a pipeline width or
// a generated-identifier length. Other object operand sizes follow only the
// last-child spine of the existing index, not every row/node/field.
fn preparation_step(
  step : @wire.Cursor,
  state : ProgramPreparationState,
) -> Unit {
  for index in 0..<@wire.object_length(step).unwrap_or(0) {
    let (key, value) = @wire.field_at(step, index).unwrap()
    if key == "as" {
      if @wire.text(value) is Ok(label) {
        state.max_label_utf16 = Int::max(state.max_label_utf16, label.length())
      }
      continue
    }
    if key == "meta" || key == "from" {
      continue
    }
    if key == "values" {
      preparation_schema(value, state)
      continue
    }
    // Literal Values and their annotations cannot introduce expression parser
    // nodes. Keep every other operand conservative, including unknown syntax;
    // this cached construction fact does not admit or validate an operation.
    state.may_contain_expression_syntax = true
    if @wire.object_length(value) is Some(_) {
      state.possible_growth += @wire.observe_subtree_size(value).0
      if key == "rename" {
        for field in 0..<@wire.object_length(value).unwrap() {
          if @wire.text(@wire.field_at(value, field).unwrap().1) is Ok(label) {
            state.max_label_utf16 = Int::max(
              state.max_label_utf16,
              label.length(),
            )
          }
        }
      }
    } else if @wire.array_length(value) is Some(count) {
      state.projected_fields = Int::max(state.projected_fields, count)
      // Object specifications can introduce named fields; flat projection
      // arrays merely repeat an existing width, not width * step count.
      if count > 0 &&
        @wire.object_length(@wire.element_at(value, 0).unwrap()) is Some(_) {
        state.possible_growth += count
        for item in 0..<count {
          let specification = @wire.element_at(value, item).unwrap()
          if preparation_member(specification, "as") is Some(output_name) &&
            @wire.text(output_name) is Ok(label) {
            state.max_label_utf16 = Int::max(
              state.max_label_utf16,
              label.length(),
            )
          }
        }
      }
    }
  }
}

///|
pub fn program_preparation_data(program : Program) -> ProgramPreparationData {
  program.preparation
}
