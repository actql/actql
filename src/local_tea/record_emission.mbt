///|
/// Reserve the common append cursor, live caller scratch, and the next retained
/// record together. Dynamic contract and collision stacks use the same custody.
fn event_emission_workspace(
  fields : Int,
  identities : Int,
  depth : Int,
  owned : Int,
) -> Int? {
  guard @storage.append_workspace_slots(fields, identities, depth)
    is Some(cursor) &&
    owned >= 0 &&
    fields <= 2147483645 &&
    owned <= 2147483647 - cursor &&
    fields + 2 <= 2147483647 - cursor - owned else {
    return None
  }
  Some(cursor + owned + fields + 2)
}
