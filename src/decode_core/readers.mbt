///|
fn issue(cursor : Cursor, kind : IssueKind) -> Issue {
  let node = cursor.tree[cursor.index]
  at(cursor.tree, node.parent, node.edge, node.span, kind)
}

///|
pub fn cursor_span(cursor : Cursor) -> @span.Span {
  cursor.tree[cursor.index].span
}

///|
/// O(1) measurements of this cursor's entire admitted tree, even for a child
/// cursor. These are retained sizes, not work performed by this read.
pub fn admission_usage(cursor : Cursor) -> AdmissionUsage {
  cursor.usage
}

///|
/// The source key span of an object child, absent for roots and array elements.
/// This reads the owned edge directly without rebuilding the containing map.
pub fn cursor_key_span(cursor : Cursor) -> @span.Span? {
  match cursor.tree[cursor.index].edge {
    Field(_, span) => Some(span)
    _ => None
  }
}

///|
/// Return a fresh path; mutating it cannot change a cursor or later issue.
pub fn cursor_path(cursor : Cursor) -> Array[PathSegment] {
  let node = cursor.tree[cursor.index]
  path_at(cursor.tree, node.parent, node.edge)
}

///|
pub fn open_object(cursor : Cursor) -> Result[ObjectView, Issue] {
  match cursor.tree[cursor.index].value {
    ObjectValue(entries) => {
      let fields : Map[String, Int] = Map([])
      for entry in entries {
        fields[entry.key] = entry.index
      }
      Ok({ cursor, fields, })
    }
    _ => Err(issue(cursor, WrongType))
  }
}

///|
/// Check only the allowed names, in source order. Required fields are separate.
pub fn closed_object(
  cursor : Cursor,
  allowed : Array[String],
) -> Result[ObjectView, Issue] {
  match cursor.tree[cursor.index].value {
    ObjectValue(entries) =>
      match
        @shape.check_object_keys(entries.map(entry => entry.key), [], allowed) {
        Ok(_) => open_object(cursor)
        Err(key_issue) => {
          let (name, kind) = match key_issue {
            @shape.UnknownKey(name) => (name, UnknownField)
            @shape.DuplicateKey(name) => (name, DuplicateField)
            @shape.MissingKey(name) => (name, MissingField)
          }
          for entry in entries {
            if entry.key == name {
              return Err(
                at(
                  cursor.tree,
                  cursor.index,
                  Field(name, entry.span),
                  entry.span,
                  kind,
                ),
              )
            }
          }
          abort("key checker returned an absent name without required keys")
        }
      }
    _ => Err(issue(cursor, WrongType))
  }
}

///|
pub fn lookup(object : ObjectView, name : String) -> Cursor? {
  object.fields.get(name).map(index => { ..object.cursor, index, })
}

///|
pub fn is_null(cursor : Cursor) -> Bool {
  cursor.tree[cursor.index].value is Null
}

///|
pub fn field(object : ObjectView, name : String) -> Presence[Cursor] {
  match lookup(object, name) {
    None => Missing
    Some(cursor) => if is_null(cursor) { ExplicitNull } else { Present(cursor) }
  }
}

///|
/// Require presence and a non-null value. Use lookup/field for nullable fields.
pub fn required(object : ObjectView, name : String) -> Result[Cursor, Issue] {
  match lookup(object, name) {
    None => {
      let span = cursor_span(object.cursor)
      Err(
        at(
          object.cursor.tree,
          object.cursor.index,
          Field(name, span),
          span,
          MissingField,
        ),
      )
    }
    Some(cursor) =>
      if is_null(cursor) {
        Err(issue(cursor, UnexpectedNull))
      } else {
        Ok(cursor)
      }
  }
}

///|
pub fn elements(cursor : Cursor) -> Result[Array[Cursor], Issue] {
  match cursor.tree[cursor.index].value {
    ArrayValue(items) => Ok(items.map(index => { ..cursor, index, }))
    _ => Err(issue(cursor, WrongType))
  }
}

///|
pub fn object_field_names(cursor : Cursor) -> Result[Array[String], Issue] {
  match cursor.tree[cursor.index].value {
    ObjectValue(fields) => Ok(fields.map(field => field.key))
    _ => Err(issue(cursor, WrongType))
  }
}

///|
/// A shallow detached view, not an assertion of canonical or numeric validity.
pub fn view(cursor : Cursor) -> ValueView {
  match cursor.tree[cursor.index].value {
    Null => NullValue
    Bool(value) => BoolValue(value)
    Number(value) => NumberValue(value)
    Text(value) => TextValue(value)
    ArrayValue(items) => ArrayValue(items.map(index => { ..cursor, index, }))
    ObjectValue(_) => ObjectValue(open_object(cursor).unwrap())
  }
}

///|
pub fn text(cursor : Cursor) -> Result[String, Issue] {
  match cursor.tree[cursor.index].value {
    Text(value) => Ok(value)
    _ => Err(issue(cursor, WrongType))
  }
}

///|
pub fn boolean(cursor : Cursor) -> Result[Bool, Issue] {
  match cursor.tree[cursor.index].value {
    Bool(value) => Ok(value)
    _ => Err(issue(cursor, WrongType))
  }
}

///|
pub fn finite_number(cursor : Cursor) -> Result[Double, Issue] {
  match cursor.tree[cursor.index].value {
    Number(value) =>
      match @scalar.read_finite_number(value) {
        Some(value) => Ok(value)
        None => Err(issue(cursor, OutOfRange))
      }
    _ => Err(issue(cursor, WrongType))
  }
}

///|
pub fn safe_integer(cursor : Cursor) -> Result[Int64, Issue] {
  match finite_number(cursor) {
    Err(error) => Err(error)
    Ok(value) =>
      match @scalar.read_safe_integer(value) {
        Some(value) => Ok(value)
        None => Err(issue(cursor, OutOfRange))
      }
  }
}

///|
pub fn int32(cursor : Cursor) -> Result[Int, Issue] {
  match finite_number(cursor) {
    Err(error) => Err(error)
    Ok(value) =>
      match @scalar.read_int32(value) {
        Some(value) => Ok(value)
        None => Err(issue(cursor, OutOfRange))
      }
  }
}

///|
/// An internal decimal Int64 spelling, not an ActQL Decimal or safe-integer proof.
pub fn decimal_int64(cursor : Cursor) -> Result[Int64, Issue] {
  match text(cursor) {
    Err(error) => Err(error)
    Ok(value) =>
      match @scalar.read_decimal_int64(value) {
        Ok(value) => Ok(value)
        Err(_) => Err(issue(cursor, InvalidDecimal))
      }
  }
}
