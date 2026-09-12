///|
// Explicit opt-in: normal regression runs do not execute the measurement loop.
// Each benchmark process warms and observes the same case before measuring it.
test "profile the fixed legacy sequence with independent output assertions" {
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
  sequence_scale(rows, columns, same)
  sequence_scale(rows, columns, same, profile=true)
}
