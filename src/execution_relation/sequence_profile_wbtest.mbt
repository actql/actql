///|
// Explicit opt-in: normal regression runs do not execute the measurement loop.
// Each benchmark process warms and observes the same case before measuring it.
test "profile fixed layout sequences with independent output assertions" {
  if @env.get_env_var("ACTQL_LAYOUT_ADDITIONAL_CASE") is Some(text) {
    let mut index = -1
    for i in 0..<13 {
      if text == i.to_string() {
        index = i
      }
    }
    let candidate = match @env.get_env_var("ACTQL_LAYOUT_CANDIDATE") {
      None | Some("A") => RowLayout
      Some("B") => ValueColumns
      Some("C") => TypedColumns
      Some(_) => fail("unknown layout candidate")
    }
    if @env.get_env_var("ACTQL_LAYOUT_PREPARED") == Some("1") {
      profile_prepared_additional_layout(index, candidate)
      return
    }
    profile_additional_layout(index, candidate)
    profile_additional_layout(index, candidate, emit=true)
    return
  }
  guard @env.get_env_var("ACTQL_LAYOUT_CASE") is Some(text) else { return }
  let cases = [
    (100, 2, true),
    (100, 2, false),
    (100, 64, true),
    (100, 64, false),
    (1000, 2, true),
    (1000, 2, false),
    (1000, 64, true),
    (1000, 64, false),
    (10000, 2, true),
    (10000, 2, false),
    (10000, 64, true),
    (10000, 64, false),
  ]
  let mut index = -1
  for i = 0; i < cases.length(); i = i + 1 {
    if text == i.to_string() {
      index = i
    }
  }
  guard cases.get(index) is Some((rows, columns, same)) else {
    fail("unknown layout measurement case")
  }
  let candidate = match @env.get_env_var("ACTQL_LAYOUT_CANDIDATE") {
    None | Some("A") => RowLayout
    Some("B") => ValueColumns
    Some("C") => TypedColumns
    Some(_) => fail("unknown layout candidate")
  }
  sequence_scale(rows, columns, same, candidate~)
  sequence_scale(rows, columns, same, profile=true, candidate~)
}
