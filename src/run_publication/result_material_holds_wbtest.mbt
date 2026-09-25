///|
test "published Result waits for two consumers and a stopped reader" {
  let binding = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let material = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let second = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let reader = "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  let initial = begin_result_material_holds(binding, material).unwrap()
  let restored = admit_result_material_holds(
    result_material_holds_wire(initial).unwrap(),
  ).unwrap()
  assert_eq(result_material_holds_revision(restored), 0)
  let two = prepare_result_material_holds_step(restored, "add_consumer", second).unwrap()
  let active = prepare_result_material_holds_step(two, "begin_reader", reader).unwrap()
  let one = prepare_result_material_holds_step(
    active, "release_consumer", binding,
  ).unwrap()
  assert_false(result_material_holds_reclaimable(one))
  let stopped = prepare_result_material_holds_step(one, "stop_readers", "").unwrap()
  assert_true(
    prepare_result_material_holds_step(stopped, "begin_reader", second)
    is Err(_),
  )
  let released = prepare_result_material_holds_step(
    stopped, "release_consumer", second,
  ).unwrap()
  assert_false(result_material_holds_reclaimable(released))
  let ended = prepare_result_material_holds_step(released, "end_reader", reader).unwrap()
  assert_true(result_material_holds_reclaimable(ended))
  assert_eq(
    result_material_holds_wire(
      prepare_result_material_holds_step(ended, "end_reader", reader).unwrap(),
    ).unwrap(),
    result_material_holds_wire(ended).unwrap(),
  )
  assert_true(
    prepare_result_material_holds_step(ended, "begin_reader", reader) is Err(_),
  )
  assert_true(
    prepare_result_material_holds_step(ended, "add_consumer", binding) is Err(_),
  )
}

///|
test "Result hold admission rejects malformed and noncanonical records" {
  let binding = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let material = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let initial = begin_result_material_holds(binding, material).unwrap()
  let wire = result_material_holds_wire(initial).unwrap()
  assert_true(admit_result_material_holds("{}") is Err(_))
  assert_true(
    admit_result_material_holds(
      wire.replace(old="actql-result-material-holds/0.1", new="unknown"),
    )
    is Err(_),
  )
  assert_true(
    admit_result_material_holds(
      wire.replace(
        old="\"consumer_holds\":[",
        new="\"consumer_holds\":[\"bad\",",
      ),
    )
    is Err(_),
  )
  assert_true(
    admit_result_material_holds(
      wire.replace(old="\"revision\":0", new="\"revision\":00"),
    )
    is Err(_),
  )
}
