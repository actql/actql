///|
fn listing_glob_fixture(
  pattern : String,
  path : String,
  quantum : Int,
) -> (Bool, Int) raise {
  let glob = compile_listing_glob(pattern, 4096).unwrap()
  let cursor = begin_listing_glob(glob, path, 4096L).unwrap()
  let mut work = 0
  for steps = 0; steps < 100000; steps = steps + 1 {
    match step_listing_glob(cursor, quantum).unwrap() {
      Continue(spent) => {
        assert_true(spent > 0 && spent <= quantum)
        work += spent
      }
      Complete(matched, spent) => {
        work += spent
        assert_true(step_listing_glob(cursor, quantum) is Ok(Complete(_, 0)))
        return (matched, work)
      }
    }
  }
  fail("glob cursor did not terminate")
}

///|
test "listing glob matches exact scalars slash components and literal syntax" {
  // These expectations are the declared language, not another matcher oracle.
  for
    (pattern, path, expected) in [
      ("*", "", true),
      ("*", "a/b", false),
      ("?", "😀", true),
      ("?", "é", false),
      ("??", "é", true),
      ("é", "é", false),
      ("%2F", "/", false),
      ("%2F", "%2F", true),
      ("a/*", "a/x", true),
      ("a/*", "a/x/y", false),
      ("**/x", "x", true),
      ("**/x", "a/b/x", true),
      ("**/x", "a/b/xx", false),
      ("a/**/x", "a/x", true),
      ("a/**/x", "a/b/c/x", true),
      ("a/**", "a", true),
      ("a/**", "a/b/c", true),
      ("a/**", "ab/c", false),
      ("**/**/x", "a/b/x", true),
      ("[ab]{x}", "[ab]{x}", true),
      ("[ab]{x}", "ax", false),
      ("\\*\\?\\\\", "*?\\", true),
      ("a/", "a/", true),
      ("a/", "a", false),
      ("", "", true),
    ] {
    let (matched, work) = listing_glob_fixture(pattern, path, 1)
    assert_eq(matched, expected)
    assert_eq(listing_glob_fixture(pattern, path, 7), (expected, work))
    assert_eq(listing_glob_fixture(pattern, path, 10000), (expected, work))
  }
}

///|
test "listing glob fixed work bounds and cancellation are independent of quantum" {
  // a/* has four states including accepting state. Three path scalars take
  // three closure/transfer pairs and a final closure: 4 * (2 * 3 + 1) = 28.
  assert_eq(listing_glob_fixture("a/*", "a/x", 1), (true, 28))
  assert_eq(listing_glob_fixture("?", "😀", 1), (true, 6))
  let cursor = begin_listing_glob(
    compile_listing_glob("**/x", 20).unwrap(),
    "a/b/x",
    20L,
  ).unwrap()
  assert_true(step_listing_glob(cursor, 1) is Ok(Continue(1)))
  cancel_listing_glob(cursor)
  assert_eq(cursor.path, "")
  assert_eq(cursor.active.length(), 0)
  assert_eq(cursor.next.length(), 0)
  assert_true(step_listing_glob(cursor, 1) is Ok(Complete(false, 0)))
  cancel_listing_glob(cursor)
  assert_true(step_listing_glob(cursor, 1) is Ok(Complete(false, 0)))
}

///|
test "listing glob rejects invalid syntax and bound breaches before matching" {
  for pattern in ["a**b", "***", "\\x", "\\", "a/\\/"] {
    assert_true(compile_listing_glob(pattern, 100) is Err(ListingGlobInvalid))
  }
  assert_true(
    compile_listing_glob("abcd", 3) is Err(ListingLimit("glob_pattern_units")),
  )
  let glob = compile_listing_glob("*", 1).unwrap()
  assert_true(
    begin_listing_glob(glob, "abcd", 3L)
    is Err(ListingLimit("maximum_path_length")),
  )
  let cursor = begin_listing_glob(glob, "x", 1L).unwrap()
  assert_true(step_listing_glob(cursor, 0) is Err(ListingLimit("glob_work")))
}
