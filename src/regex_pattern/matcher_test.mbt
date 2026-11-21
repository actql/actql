///|
fn search_options() -> SearchOptions {
  { from: 0, multiline: false, dot_all: false, max_entries: 5000, }
}

///|
fn search(
  pattern : String,
  text : String,
  options : SearchOptions,
) -> Result[Match?, SearchIssue] raise {
  let matcher = start_search(parse(pattern, limits()).unwrap(), text, options, reserve=_ => {
    true
  })
  match matcher {
    Err(issue) => Err(issue)
    Ok(matcher) => {
      for _ in 0..<20000 {
        match matcher.advance() {
          SearchContinue => ()
          SearchComplete(result) => {
            assert_true(matcher.advance() is SearchTerminal)
            return Ok(result)
          }
          SearchFailed(issue) => {
            assert_true(matcher.advance() is SearchTerminal)
            return Err(issue)
          }
          SearchTerminal => abort("Regex matcher stopped without an outcome")
        }
      }
      abort("Regex matcher exceeded the test work budget")
    }
  }
}

///|
test "regex search applies leftmost-first alternation and greedy continuations" {
  let options = search_options()
  let first = search("(a|ab)", "zab", options).unwrap().unwrap()
  assert_eq(match_span(first), { start: 1, end: 2, })
  assert_eq(capture_span(first, 1), Some({ start: 1, end: 2, }))
  let resumed = search("(a|ab)b$", "zabb", options).unwrap().unwrap()
  assert_eq(match_span(resumed), { start: 1, end: 4, })
  assert_eq(capture_span(resumed, 1), Some({ start: 1, end: 3, }))
  let greedy = search("(a{1,3})a", "aaaaaa", options).unwrap().unwrap()
  assert_eq(capture_span(greedy, 0), Some({ start: 0, end: 4, }))
  assert_eq(capture_span(greedy, 1), Some({ start: 0, end: 3, }))
  let give_back = search("(a*)a$", "aaa", options).unwrap().unwrap()
  assert_eq(capture_span(give_back, 1), Some({ start: 0, end: 2, }))
  let optional = search("(a)|(b)", "b", options).unwrap().unwrap()
  assert_eq(capture_span(optional, 1), None)
  assert_eq(capture_span(optional, 2), Some({ start: 0, end: 1, }))
  let repeated = search("([ab])+", "ab", options).unwrap().unwrap()
  assert_eq(capture_span(repeated, 1), Some({ start: 1, end: 2, }))
  assert_true(search("a{9007199254740994}", "aaa", options) is Ok(None))
}

///|
test "regex search reads original Unicode scalars and exact LF and ASCII classes" {
  let options = search_options()
  let unanchored = search(".([🙂-🙃])", "a🙂b", options).unwrap().unwrap()
  assert_eq(capture_span(unanchored, 1), Some({ start: 1, end: 3, }))
  let second = search("b", "a🙂b", { ..options, from: 1, }).unwrap().unwrap()
  assert_eq(match_span(second), { start: 3, end: 4, })
  assert_true(
    search("b", "a🙂b", { ..options, from: 2, }) is Err(MalformedInput(2)),
  )
  assert_true(search("^a$", "a\n", options) is Ok(None))
  assert_true(
    search("^a$", "z\na\n", { ..options, multiline: true, }) is Ok(Some(_)),
  )
  assert_true(
    search("^a$", "z\na\r\n", { ..options, multiline: true, }) is Ok(None),
  )
  assert_true(search("^a.b$", "a\rb", options) is Ok(Some(_)))
  assert_true(search("^a.b$", "a\nb", options) is Ok(None))
  assert_true(
    search("^a.b$", "a\nb", { ..options, dot_all: true, }) is Ok(Some(_)),
  )
  assert_true(search("^[^\\d]\\s\\w$", "９\r_", options) is Ok(Some(_)))
  assert_true(search("^\\w$", "é", options) is Ok(None))
  let empty = search("a*$", "🙂", options).unwrap().unwrap()
  assert_eq(match_span(empty), { start: 2, end: 2, })
}

///|
test "regex search bounds frame storage and retires after cancellation or limit" {
  let options = search_options()
  assert_true(
    search("a", "a", { ..options, max_entries: 0, })
    is Err(SearchWorkspaceLimit),
  )
  assert_true(search("a", "a", { ..options, max_entries: 1, }) is Ok(Some(_)))
  assert_true(
    search("[ab]", "b", { ..options, max_entries: 2, })
    is Err(SearchWorkspaceLimit),
  )
  assert_true(
    search("[ab]", "b", { ..options, max_entries: 3, }) is Ok(Some(_)),
  )
  let matcher = start_search(
    parse("(a|aa)+b", limits()).unwrap(),
    "a".repeat(200),
    options,
    reserve=_ => true,
  ).unwrap()
  for _ in 0..<12 {
    assert_true(matcher.advance() is SearchContinue)
  }
  matcher.cancel()
  assert_true(matcher.advance() is SearchTerminal)
  assert_true(
    search("(a|aa)+b", "a".repeat(200), { ..options, max_entries: 32, })
    is Err(SearchWorkspaceLimit),
  )
}

///|
test "regex search reserves overlapping backing before constructing captures" {
  let pattern = parse("(a)", limits()).unwrap()
  for limit in [4, 5] {
    let requested : Array[Int] = []
    let mut complete_geometry = true
    let matcher = start_search(pattern, "a", search_options(), reserve=extent => {
      // Independently price the retained wrappers, four Array growth peaks,
      // one work cell, quote controls and each live entry body.
      let entries = ((extent.reference_slots - 70L) / 4L).to_int()
      complete_geometry = complete_geometry &&
        extent.record_headers == 41L + 2L * entries.to_int64() &&
        extent.reference_slots == 70L + 4L * entries.to_int64() &&
        extent.scalar_words == 82L + 6L * entries.to_int64()
      requested.push(entries)
      entries <= limit
    }).unwrap()
    let mut ended = false
    for _ in 0..<32 {
      match matcher.advance() {
        SearchContinue => ()
        SearchComplete(Some(found)) => {
          assert_eq(limit, 5)
          assert_eq(capture_span(found, 1), Some({ start: 0, end: 1, }))
          ended = true
          break
        }
        SearchFailed(SearchWorkspaceLimit) => {
          assert_eq(limit, 4)
          ended = true
          break
        }
        _ => fail("unexpected matcher outcome")
      }
    }
    assert_true(ended && complete_geometry)
    assert_eq(requested, [0, 1, 2, 3, 4, 5])
    assert_true(matcher.advance() is SearchTerminal)
  }
}

///|
test "regex search reuses backing across misses and cancels before a refused write" {
  let pattern = parse("a", limits()).unwrap()
  let mut calls = 0
  let matcher = start_search(pattern, "zzza", search_options(), reserve=_ => {
    calls += 1
    true
  }).unwrap()
  let mut match_start = -1
  for _ in 0..<32 {
    if matcher.advance() is SearchComplete(Some(found)) {
      match_start = match_span(found).start
      break
    }
  }
  assert_eq((match_start, calls), (3, 2))
  let owner : Ref[Search?] = Ref(None)
  let matcher = start_search(pattern, "a", search_options(), reserve=_ => {
    if owner.val is Some(value) {
      value.cancel()
    }
    true
  }).unwrap()
  owner.val = Some(matcher)
  assert_true(matcher.advance() is SearchFailed(SearchCancelled))
  owner.val = None
  assert_true(matcher.advance() is SearchTerminal)
}
