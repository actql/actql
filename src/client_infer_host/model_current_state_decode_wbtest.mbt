///|
fn model_current_decode_test_start() -> (
  Execution,
  @publication_host.ClientModelReadScope,
  @publication_host.ClientModelResourcePark,
  String,
) raise {
  let (active, scope, _, _, _, _, _) = model_resource_park_test_start()
  require_model_call_entry(active).unwrap()
  assert_true(fixture_finish(active) is Waiting(..))
  prepared_call_set(active).unwrap() |> ignore
  let park = park_original_model_resources_for_state_write(active, scope).unwrap()
  let writer = prepare_original_model_current_state_writer(
    active, scope, park, 10000, 1000, 20,
  ).unwrap()
  assert_true(
    advance_original_model_current_state_writer(active, scope, park, writer, 19)
    is @resources.StateWriteComplete(work=19),
  )
  let wire = finish_original_model_current_state_writer(
    active, scope, park, writer,
  ).unwrap()
  // Actual Writer/caller integration input, not the independent census oracle.
  (active, scope, park, "{\"resource_state\":" + wire + "}")
}

///|
fn model_current_decode_test_limits() -> @decode.Limits {
  {
    max_nodes: 1000,
    max_depth: 20,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }
}

///|
test "Model current decoder shares bounded work and exact current comparison across quantum" {
  let mut expected_work = None
  for quantum in [1, 7, 64, 10000] {
    let (active, scope, park, wire) = model_current_decode_test_start()
    let work = active.work
    let value = start_original_model_current_state_decode(
      active,
      scope,
      park,
      wire,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 20, },
      model_current_decode_test_limits(),
      20000,
    ).unwrap()
    let (document, total) = for spent = 0 {
      match
        advance_original_model_current_state_decode(
          active, scope, park, value, quantum,
        ) {
        CurrentDecodeContinue(work=n) => {
          assert_true(n > 0 && n <= quantum)
          continue spent + n
        }
        CurrentDecodeComplete(document, work=n) => {
          assert_true(n >= 0 && n <= quantum)
          break (document, spent + n)
        }
        _ => abort("current decode unexpectedly refused")
      }
    }
    if expected_work is Some(previous) {
      assert_eq(total, previous)
    } else {
      expected_work = Some(total)
    }
    assert_true(value.park is None && value.phase is Retired)
    // Original read + Model capacity + one attempt + bootstrap/final = 5
    // comparison units, independent of parser/owned-tree work and Model work.
    let comparison = start_original_model_current_state_comparison(
      active, scope, park, document, 5,
    ).unwrap()
    assert_true(
      advance_original_model_current_state_comparison(
        active, scope, park, comparison, 5,
      ).unwrap()
      is @resources.ComparisonComplete(work=5),
    )
    assert_eq(active.work, work)
    @resources.retire_original_current_state_document(document)
    assert_true(
      original_model_resource_park_current(active, scope, park) is Some(_),
    )
  }
}

///|
test "Model current decoder budget cancel foreign and parent-tree bounds keep park" {
  let (active, scope, park, wire) = model_current_decode_test_start()
  let decode = fn(text, work, tree) {
    start_original_model_current_state_decode(
      active,
      scope,
      park,
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 20, },
      tree,
      work,
    ).unwrap()
  }
  let limited = decode(wire, 5, model_current_decode_test_limits())
  assert_true(
    advance_original_model_current_state_decode(
      active, scope, park, limited, 10000,
    )
    is CurrentDecodeFailed(WorkLimit, work=5),
  )
  assert_true(limited.park is None && limited.phase is Retired)
  let value = decode(wire, 20000, model_current_decode_test_limits())
  let (other, foreign, _, _) = model_current_decode_test_start()
  assert_true(
    advance_original_model_current_state_decode(other, foreign, park, value, 1)
    is CurrentDecodeFailed(Original(@resources.ChangedOriginalState), work=0),
  )
  assert_true(value.park is Some(_))
  assert_true(
    advance_original_model_current_state_decode(active, scope, park, value, 1)
    is CurrentDecodeContinue(work=1),
  )
  cancel_original_model_current_state_decode(value)
  cancel_original_model_current_state_decode(value)
  assert_true(value.park is None && value.phase is Retired)
  let sibling = "s".repeat(101)
  let parent = wire.replace(old="{", new="{\"sibling\":\"" + sibling + "\",")
  let constrained = decode(parent, 20000, {
    ..model_current_decode_test_limits(),
    max_string_bytes: 100,
  })
  let failure = for _ in 0..<20000 {
    match
      advance_original_model_current_state_decode(
        active, scope, park, constrained, 1,
      ) {
      CurrentDecodeContinue(..) => continue
      poll => break poll
    }
  } nobreak {
    abort("bounded parent-tree case did not terminate")
  }
  assert_true(failure is CurrentDecodeFailed(Admission(_), ..))
  assert_true(constrained.park is None && constrained.phase is Retired)
  assert_true(
    original_model_resource_park_current(active, scope, park) is Some(_),
  )
}
