///|
fn role_name(source : @decode.Cursor) -> @row.FieldName raise Stop {
  let name = decoded(@decode.text(source))
  let parts = name.split(".").to_array()
  match parts {
    ["left", field] if !field.is_empty() =>
      @row.Qualified(Left, field.to_owned())
    ["right", field] if !field.is_empty() =>
      @row.Qualified(Right, field.to_owned())
    [_] if !name.is_empty() => @row.Unqualified(name)
    _ => fail(source, InvalidBody)
  }
}
