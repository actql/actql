///|
fn transfer_window(
  b : Budget,
  source : @decode.Cursor,
  input : Target,
  steps : Array[CheckedStep],
  operation : CheckedOperation,
) -> WindowEvidence? raise Stop {
  let previous = match input {
    Step(index) => steps[index].window
    Input(_) => None
  }
  guard previous is Some(roles) else { return None }
  if operation is WindowGroup(_) {
    return Some(roles)
  }
  guard operation is Unary(op) else { return None }
  match @relation.operation(op) {
    Filter | Sort | Take | AssertRows | DedupeRows | TopK | TopKBy =>
      Some(roles)
    Derive => {
      spend(b, source, @relation.binding_count(op))
      for i in 0..<@relation.binding_count(op) {
        if @relation.binding_at(op, i).unwrap().name is Some(name) {
          if @schema.Unqualified(name) == roles.start ||
            @schema.Unqualified(name) == roles.end {
            return None
          }
        }
      }
      Some(roles)
    }
    Select | Rename | Drop | Distinct => {
      let projection = @relation.projection(op)
      spend(b, source, projection.length())
      let mut start = None
      let mut end = None
      for field in projection {
        if field.input == roles.start && start is None {
          start = Some(field.output)
        }
        if field.input == roles.end && end is None {
          end = Some(field.output)
        }
      }
      match (start, end) {
        (Some(start), Some(end)) => Some({ start, end, })
        _ => None
      }
    }
    _ => None
  }
}
