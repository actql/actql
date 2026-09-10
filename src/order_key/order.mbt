///|
pub(all) enum Direction {
  Asc
  Desc
} derive(Eq, Debug)

///|
pub(all) enum NullPlacement {
  First
  Last
} derive(Eq, Debug)

///|
pub struct Key {
  field : String
  direction : Direction
  nulls : NullPlacement
  explicit_nulls : Bool
  source : @decode.Cursor
  field_source : @decode.Cursor
  work : Int
}

///|
pub(all) enum IssueKind {
  InvalidOrder
  Decode(@decode.IssueKind)
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
  diagnostic : @decode.Issue?
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(source : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({ source, kind, diagnostic: None, })
}

///|
fn[T] decoded(
  value : Result[T, @decode.Issue],
  source : @decode.Cursor,
) -> T raise Stop {
  match value {
    Ok(v) => v
    Err(e) => raise Stop({ source, kind: Decode(e.kind), diagnostic: Some(e), })
  }
}

///|
fn direction(source : @decode.Cursor) -> Direction raise Stop {
  match decoded(@decode.text(source), source) {
    "asc" => Asc
    "desc" => Desc
    _ => fail(source, InvalidOrder)
  }
}

///|
/// Leaf shape reader. Caller preflights the owned source and charges work;
/// this does not resolve fields, normalize names or establish order evidence.
pub fn read(source : @decode.Cursor) -> Result[Key, Issue] {
  try {
    let obj = decoded(@decode.open_object(source), source)
    let names = @decode.object_field_names(source).unwrap()
    let (field, dir, nulls, explicit_nulls, field_source) = if names.length() ==
      1 {
      let key = names[0]
      (key, direction(@decode.lookup(obj, key).unwrap()), Last, false, source)
    } else {
      let obj = decoded(
        @decode.closed_object(source, ["field", "dir", "nulls"]),
        source,
      )
      let field_source = decoded(@decode.required(obj, "field"), source)
      let field = decoded(@decode.text(field_source), field_source)
      let dir = direction(decoded(@decode.required(obj, "dir"), source))
      let null_source = decoded(@decode.required(obj, "nulls"), source)
      let nulls = match decoded(@decode.text(null_source), null_source) {
        "first" => First
        "last" => Last
        _ => fail(null_source, InvalidOrder)
      }
      (field, dir, nulls, true, field_source)
    }
    Ok({
      field,
      direction: dir,
      nulls,
      explicit_nulls,
      source,
      field_source,
      work: names.length() + 1,
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn author_orderable(contract : @contract.Contract) -> Bool {
  match contract.shape {
    @contract.Text(_) | Number | Boolean | Decimal(..) | Date | Timestamp =>
      true
    _ => false
  }
}
