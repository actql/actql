///|
// The borrowed operand array and one argument's progress. The existing text
// frame owns the operand roots and measures the complete output before writing.
const FORMAT_STRINGS_SLOTS : Int = 12

///|
priv enum FormatStringsPhase {
  FormatLiteral
  FormatFlags
  FormatWidth
  FormatPrecision
  FormatSpecifier
  FormatMeasureArgument
  FormatPadBefore
  FormatEmitArgument
  FormatPadAfter
}

///|
priv struct FormatStrings {
  values : Array[Value]
  mut template_position : Int
  mut argument : Int
  mut phase : FormatStringsPhase
  mut left : Bool
  mut width : Int
  // -1 means the template supplied no precision.
  mut precision : Int
  mut argument_position : Int
  mut argument_end : Int
  mut scalar_count : Int
  mut padding : Int
}

///|
fn advance_format_strings(
  state : TextFunctionState,
  format : FormatStrings,
  workspace : RowWorkspace,
) -> Result[Value?, EvalIssue] {
  let template = state.input
  let position = format.template_position
  let invalid = { kind: Scalar(InvalidOperand), expression: state.expression, }
  match format.phase {
    FormatLiteral =>
      if position == template.length() {
        if format.argument != format.values.length() {
          return Err(invalid)
        }
        if state.null_result {
          return Ok(Some(Null))
        }
        if state.building {
          return finish_measured_text_output(state).map(value => Some(value))
        }
        match begin_measured_text_output(state, workspace) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        format.template_position = 0
        format.argument = 1
      } else if template[position] != '%' {
        if state.null_result {
          guard text_function_scalar(template, position)
            is Some((_, next, _, _)) else {
            return Err(invalid)
          }
          format.template_position = next
        } else {
          format.template_position = match
            append_text_function_scalar(state, template, position) {
            Ok(next) => next
            Err(issue) => return Err(issue)
          }
        }
      } else if position + 1 < template.length() &&
        template[position + 1] == '%' {
        if !state.null_result {
          match append_text_function_codepoint(state, '%', 1, 1, 1) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
        }
        format.template_position += 2
      } else {
        format.template_position += 1
        format.phase = FormatFlags
        format.left = false
        format.width = 0
        format.precision = -1
      }
    FormatFlags => {
      if position == template.length() {
        return Err(invalid)
      }
      match template[position] {
        '-' => {
          format.left = true
          format.template_position += 1
        }
        '+' | ' ' | '0' | '#' | '\'' => format.template_position += 1
        _ => format.phase = FormatWidth
      }
    }
    FormatWidth | FormatPrecision => {
      if position == template.length() {
        return Err(invalid)
      }
      let digit = template[position].to_int() - 48
      if digit >= 0 && digit <= 9 {
        let current = if format.phase is FormatPrecision {
          format.precision
        } else {
          format.width
        }
        if current > (2147483647 - digit) / 10 {
          return Err({ kind: WorkspaceLimit, expression: state.expression, })
        }
        if format.phase is FormatPrecision {
          format.precision = current * 10 + digit
        } else {
          format.width = current * 10 + digit
        }
        format.template_position += 1
      } else if template[position] == '.' && format.phase is FormatWidth {
        format.precision = 0
        format.phase = FormatPrecision
        format.template_position += 1
      } else {
        format.phase = FormatSpecifier
      }
    }
    FormatSpecifier => {
      if position >= template.length() ||
        template[position] != 's' ||
        format.argument >= format.values.length() {
        return Err(invalid)
      }
      format.template_position += 1
      if state.null_result {
        format.argument += 1
        format.phase = FormatLiteral
      } else {
        format.argument_position = 0
        format.argument_end = 0
        format.scalar_count = 0
        format.phase = FormatMeasureArgument
      }
    }
    FormatMeasureArgument => {
      guard format.values[format.argument] is Text(value) else {
        return Err(invalid)
      }
      if format.argument_end < value.length() &&
        (format.precision < 0 || format.scalar_count < format.precision) {
        guard text_function_scalar(value, format.argument_end)
          is Some((_, next, _, _)) else {
          return Err(invalid)
        }
        format.argument_end = next
        format.scalar_count += 1
      } else {
        format.padding = Int::max(0, format.width - format.scalar_count)
        format.phase = if format.left {
          FormatEmitArgument
        } else {
          FormatPadBefore
        }
      }
    }
    FormatPadBefore | FormatPadAfter =>
      if format.padding > 0 {
        match append_text_function_codepoint(state, ' ', 1, 1, 1) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        format.padding -= 1
      } else if format.phase is FormatPadBefore {
        format.phase = FormatEmitArgument
      } else {
        format.argument += 1
        format.phase = FormatLiteral
      }
    FormatEmitArgument =>
      if format.argument_position < format.argument_end {
        guard format.values[format.argument] is Text(value) else {
          return Err(invalid)
        }
        format.argument_position = match
          append_text_function_scalar(state, value, format.argument_position) {
          Ok(next) => next
          Err(issue) => return Err(issue)
        }
      } else {
        format.phase = FormatPadAfter
      }
  }
  Ok(None)
}
