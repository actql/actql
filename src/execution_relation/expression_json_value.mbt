///|
// Selection and emission each borrow the original input. The quoted scanner
// retains only its active parent stack, funded separately from this cursor.
const JSON_VALUE_CURSOR_SLOTS : Int = 32

///|
priv enum JsonValueInput {
  JsonScalarRaw(JsonRawScalarCursor)
  JsonScalarData(@admitted.Value)
}

///|
priv enum JsonValueSelection {
  JsonCompilePath
  JsonScanRaw
  JsonSelectData(@admitted.Value, Int)
  JsonFindDataMember(@admitted.FrozenArray[(String, @admitted.Value)], Int, Int)
  JsonCompareDataKey(
    @admitted.FrozenArray[(String, @admitted.Value)],
    Int,
    Int,
    Int,
    Int
  )
  JsonEmitSelected(String, Int, Int, Bool, Int)
}

///|
priv struct JsonValueQuery {
  path : JsonValuePath
  input : JsonValueInput
  mut selection : JsonValueSelection
  mut scalar_slots : Int
}

///|
fn json_value_query(input : Value, path : String) -> JsonValueQuery? {
  let original = match input {
    Text(text) =>
      JsonScalarRaw({
        text,
        parents: [],
        phase: JsonRawValue(0),
        position: 0,
        highwater: 0,
      })
    Captured(@admitted.JsonData(value)) => JsonScalarData(value)
    _ => return None
  }
  Some({
    path: { text: path, parts: [], position: 0, phase: JsonPathRoot, },
    input: original,
    selection: JsonCompilePath,
    scalar_slots: 0,
  })
}

///|
fn release_json_value_query(
  query : JsonValueQuery,
  workspace : RowWorkspace,
) -> Unit {
  release_slots(workspace, query.path.parts.length() * JSON_VALUE_PART_SLOTS)
  if query.input is JsonScalarRaw(cursor) {
    release_slots(workspace, cursor.highwater * JSON_RAW_PARENT_SLOTS)
  }
  release_slots(workspace, query.scalar_slots)
}

///|
fn select_json_value_text(
  query : JsonValueQuery,
  state : TextFunctionState,
  scope : ExpressionRoots?,
  text : String,
  start : Int,
  end : Int,
  escaped : Bool,
) -> Result[Value?, EvalIssue] {
  match admit_text_expression_output(state.expression, scope) {
    Err(issue) => return Err(issue)
    Ok(root) => state.output_root = root
  }
  query.selection = JsonEmitSelected(text, start, end, escaped, start)
  Ok(None)
}

///|
fn advance_json_value_query(
  state : TextFunctionState,
  query : JsonValueQuery,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
) -> Result[Value?, EvalIssue] {
  let invalid = { kind: Scalar(InvalidOperand), expression: state.expression, }
  let path = query.path
  match query.selection {
    JsonCompilePath =>
      match advance_json_value_path(path, workspace, state.expression) {
        Err(issue) => return Err(issue)
        Ok(false) => ()
        Ok(true) =>
          query.selection = match query.input {
            JsonScalarRaw(_) => JsonScanRaw
            JsonScalarData(value) => JsonSelectData(value, 0)
          }
      }
    JsonScanRaw => {
      guard query.input is JsonScalarRaw(cursor) else { return Err(invalid) }
      match advance_json_raw_scalar(cursor, path, workspace, state.expression) {
        Ok(JsonRawContinue) => ()
        Ok(JsonRawMissing) => {
          release_json_value_query(query, workspace)
          return Ok(Some(Null))
        }
        Ok(JsonRawSelected(start~, end~, quoted~)) =>
          return select_json_value_text(
            query,
            state,
            scope,
            cursor.text,
            start,
            end,
            quoted,
          )
        Err(issue) => return Err(issue)
      }
    }
    JsonSelectData(value, level) =>
      match path.parts.get(level) {
        Some(JsonIndex(index)) if value is @admitted.Array(items) &&
          index >= 0L &&
          index < @admitted.element_count(items).to_int64() => {
          guard @admitted.element_at(items, index.to_int()) is Some(child) else {
            return Err(invalid)
          }
          query.selection = JsonSelectData(child, level + 1)
        }
        Some(JsonMember(..)) if value is @admitted.Object(fields) =>
          query.selection = JsonFindDataMember(fields, level, 0)
        Some(_) => {
          release_json_value_query(query, workspace)
          return Ok(Some(Null))
        }
        None =>
          match value {
            @admitted.Text(text) =>
              return select_json_value_text(
                query,
                state,
                scope,
                text,
                0,
                text.length(),
                false,
              )
            @admitted.Boolean(value) => {
              let text = if value { "true" } else { "false" }
              return select_json_value_text(
                query,
                state,
                scope,
                text,
                0,
                text.length(),
                false,
              )
            }
            @admitted.Number(number) => {
              // The common finite decimal formatter owns at most 25 units
              // and its fixed spelling controls before returning this token.
              if !reserve_slots(workspace, 29) {
                return Err({
                  kind: WorkspaceLimit,
                  expression: state.expression,
                })
              }
              query.scalar_slots = 29
              let text = number.to_string()
              return select_json_value_text(
                query,
                state,
                scope,
                text,
                0,
                text.length(),
                false,
              )
            }
            _ => {
              release_json_value_query(query, workspace)
              return Ok(Some(Null))
            }
          }
      }
    JsonFindDataMember(fields, level, at) => {
      if at == @admitted.element_count(fields) {
        release_json_value_query(query, workspace)
        return Ok(Some(Null))
      }
      guard path.parts.get(level) is Some(JsonMember(start~, ..)) else {
        return Err(invalid)
      }
      query.selection = JsonCompareDataKey(fields, level, at, 0, start)
    }
    JsonCompareDataKey(fields, level, at, field_offset, path_offset) => {
      guard @admitted.element_at(fields, at) is Some((name, value)) &&
        path.parts.get(level) is Some(JsonMember(end~, ..)) else {
        return Err(invalid)
      }
      if field_offset == name.length() && path_offset == end {
        query.selection = JsonSelectData(value, level + 1)
      } else if text_function_scalar(name, field_offset)
        is Some((scalar, next, _, _)) &&
        json_value_key_scalar(path, level, path_offset)
        is Some((expected, after)) &&
        scalar == expected {
        query.selection = JsonCompareDataKey(fields, level, at, next, after)
      } else {
        query.selection = JsonFindDataMember(fields, level, at + 1)
      }
    }
    JsonEmitSelected(text, start, end, escaped, position) => {
      if position == end {
        if state.building {
          release_json_value_query(query, workspace)
          return finish_measured_text_output(state).map(value => Some(value))
        }
        match begin_measured_text_output(state, workspace) {
          Err(issue) => return Err(issue)
          Ok(_) =>
            query.selection = JsonEmitSelected(text, start, end, escaped, start)
        }
        return Ok(None)
      }
      let scalar = if escaped {
        json_value_quoted_scalar(text, position)
      } else {
        text_function_scalar(text, position).map(item => (item.0, item.1))
      }
      guard scalar is Some((char, after)) && after <= end else {
        return Err(invalid)
      }
      let (units, bytes, wire) = text_function_scalar_widths(char)
      match append_text_function_codepoint(state, char, units, bytes, wire) {
        Err(issue) => return Err(issue)
        Ok(_) =>
          query.selection = JsonEmitSelected(text, start, end, escaped, after)
      }
    }
  }
  Ok(None)
}
