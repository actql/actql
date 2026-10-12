///|
test "OpenAI original projection child yields without repeat work and returns one result" {
  let (provider, request, calls) = openai_projection_fixture()
  let expected = project_openai_chat_request(
    provider, request, 10000, 1000, 40, 100, 10000,
  ).unwrap()
  let mut previous_work = None
  for quantum in [1, 7, 64] {
    let cursor = start_openai_chat_projection(
      provider, request, 10000, 1000, 40, 100, 10000,
    ).unwrap()
    let mut result = None
    for _ in 0..<1000 {
      for _ in 0..<quantum {
        if result is None {
          result = advance_openai_chat_projection(cursor).unwrap()
        }
      }
      if result is Some(_) {
        break
      }
    }
    assert_eq(result, Some(expected))
    let work = openai_chat_projection_work(cursor)
    if previous_work is Some(prior) {
      assert_eq(work, prior)
    }
    previous_work = Some(work)
    let again = advance_openai_chat_projection(cursor).unwrap().unwrap()
    assert_true(physical_equal(result.unwrap(), again))
    assert_eq(openai_chat_projection_work(cursor), work)
    retire_openai_chat_projection(cursor)
    retire_openai_chat_projection(cursor)
    assert_true(cursor.request is None && cursor.instructions is None)
    assert_true(advance_openai_chat_projection(cursor) is Err(ForeignRequest))
    assert_eq(openai_chat_projection_work(cursor), work)
  }
  assert_eq(calls(), 0)
}

///|
test "OpenAI original projection child retires schema key and value borrows on interruption" {
  let (provider, request, calls) = openai_projection_fixture()
  for phase in [0, 1, 2] {
    let cursor = start_openai_chat_projection(
      provider, request, 10000, 1000, 40, 100, 10000,
    ).unwrap()
    let mut found = false
    for _ in 0..<1000 {
      let selected = match cursor.phase {
        Schema(_, _) => phase == 0
        InputKey(_, _, _, _) => phase == 1
        InputValue(_, _, _, _) => phase == 2
        _ => false
      }
      if selected {
        found = true
        break
      }
      assert_true(advance_openai_chat_projection(cursor) is Ok(None))
    }
    assert_true(found)
    let work = openai_chat_projection_work(cursor)
    retire_openai_chat_projection(cursor)
    retire_openai_chat_projection(cursor)
    assert_true(cursor.phase is Retired)
    assert_true(cursor.request is None && cursor.instructions is None)
    assert_true(advance_openai_chat_projection(cursor) is Err(ForeignRequest))
    assert_eq(openai_chat_projection_work(cursor), work)
  }
  assert_eq(calls(), 0)
}

///|
test "OpenAI original projection child exhaustion is durable within the same child" {
  let (provider, request, calls) = openai_projection_fixture()
  let limit = 40
  let cursor = start_openai_chat_projection(
    provider, request, 10000, 1000, 40, 100, limit,
  ).unwrap()
  let mut refused = false
  for _ in 0..<1000 {
    match advance_openai_chat_projection(cursor) {
      Err(Limit) => {
        refused = true
        break
      }
      Ok(None) => ()
      _ => fail("work ceiling unexpectedly complete")
    }
  }
  assert_true(refused && cursor.phase is Failed(Limit))
  assert_eq(openai_chat_projection_work(cursor), limit)
  assert_true(cursor.request is None && cursor.instructions is None)
  assert_true(advance_openai_chat_projection(cursor) is Err(Limit))
  assert_eq(openai_chat_projection_work(cursor), limit)
  assert_eq(calls(), 0)
}
