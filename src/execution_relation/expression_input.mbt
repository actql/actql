///|
priv enum ExpressionInput {
  MapExpressionInput(Map[String, Value])
  IndexedExpressionInput(Array[(String, Value)], Bool)
}

///|
/// Borrow the enclosing row's immutable entries. Only a statically small row
/// can use synchronous equality; wide or long-name rows use the frame cursor.
fn indexed_expression_input(
  entries : Array[(String, Value)],
) -> ExpressionInput {
  let small = entries.length() <= 8 &&
    entries.all(entry => entry.0.length() <= 64)
  IndexedExpressionInput(entries, small)
}

///|
fn expression_input_entries(input : ExpressionInput) -> Iter[(String, Value)] {
  match input {
    MapExpressionInput(values) => values.iter()
    IndexedExpressionInput(values, _) => values.iter()
  }
}

///|
fn expression_input_small_get(input : ExpressionInput, name : String) -> Value? {
  match input {
    MapExpressionInput(values) => values.get(name)
    IndexedExpressionInput(values, small) => {
      if !small {
        return None
      }
      for (actual, value) in values {
        if actual == name {
          return Some(value)
        }
      }
      None
    }
  }
}
