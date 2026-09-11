///|
pub struct NormalizedParameterReference {
  name : String
  cursor : @decode.Cursor
}

///|
struct ParameterOccurrences {
  expression : Expression
  entries : Array[NormalizedParameterReference]
  work : Int
}

///|
priv enum ReferenceFrame {
  Visit(@decode.Cursor, Role)
  ArrayNext(@decode.Cursor, Role, Int, Int)
  ObjectNext(@decode.Cursor, Role, Int, Int)
}

///|
/// Grammar-aware positions in the normalized expression, not diagnostic paths.
/// Work bounds frame visits; retained input text and paths are not recopied.
pub fn collect_parameter_occurrences(
  expression : Expression,
  max_work~ : Int,
) -> Result[ParameterOccurrences, Issue] {
  try {
    if max_work < 0 {
      invalid(expression.cursor, Authored, InvalidLimits)
    }
    let pending : Array[ReferenceFrame] = [
      ReferenceFrame::Visit(expression.cursor, Expr),
    ]
    let entries = []
    let mut work = 0
    while pending.pop() is Some(frame) {
      if work == max_work {
        invalid(expression.cursor, Authored, BudgetExceeded)
      }
      work += 1
      match frame {
        ReferenceFrame::Visit(cursor, initial) => {
          let role = match initial {
            Data | CastTarget | ItemContract => continue
            InItem =>
              if @decode.object_length(cursor) is Some(_) {
                Expr
              } else {
                continue
              }
            _ => initial
          }
          if @decode.object_length(cursor) is Some(count) {
            match role {
              Expr | InRight => {
                let (tag, body) = @decode.field_at(cursor, 0).unwrap()
                if tag == "$param" {
                  entries.push({ name: @decode.text(body).unwrap(), cursor, })
                } else {
                  let child_role = if role is InRight && tag == "literal" {
                    InList
                  } else {
                    expression_role(tag, cursor, Authored)
                  }
                  pending.push(ReferenceFrame::Visit(body, child_role))
                }
              }
              _ => pending.push(ObjectNext(cursor, role, 0, count))
            }
          } else if @decode.array_length(cursor) is Some(count) {
            pending.push(ArrayNext(cursor, role, 0, count))
          }
        }
        ObjectNext(cursor, role, i, count) =>
          if i < count {
            let (name, child) = @decode.field_at(cursor, i).unwrap()
            let child_role = match role {
              Body(tag) => body_role(tag, name)
              ObjectFields | Branch => Expr
              _ => Data
            }
            pending.push(ObjectNext(cursor, role, i + 1, count))
            pending.push(ReferenceFrame::Visit(child, child_role))
          }
        ArrayNext(cursor, role, i, count) =>
          if i < count {
            let child_role = match role {
              Arguments("in" | "not_in") if i == 1 => InRight
              Arguments(_) => Expr
              Branches => Branch
              InList => InItem
              _ => Data
            }
            pending.push(ArrayNext(cursor, role, i + 1, count))
            pending.push(
              ReferenceFrame::Visit(
                @decode.element_at(cursor, i).unwrap(),
                child_role,
              ),
            )
          }
      }
    }
    Ok({ expression, entries, work, })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn parameter_occurrence_count(v : ParameterOccurrences) -> Int {
  v.entries.length()
}

///|
pub fn parameter_occurrence_at(
  v : ParameterOccurrences,
  index : Int,
) -> NormalizedParameterReference? {
  v.entries.get(index)
}

///|
pub fn parameter_occurrence_expression(v : ParameterOccurrences) -> Expression {
  v.expression
}

///|
pub fn parameter_occurrence_work(v : ParameterOccurrences) -> Int {
  v.work
}
