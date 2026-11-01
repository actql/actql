///|
fn original_reference_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 100000, max_nodes: 10000, max_depth: 4000, },
      source_path="lowering-test.aql",
    ).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 4000,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn original_reference_checked(tail : String) -> @pipeline.CheckedPipeline {
  @pipeline.check(
    original_reference_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"}" +
      tail +
      "]",
    ),
    [],
    None,
    None,
    {
      max_steps: 100,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 4000,
    },
  ).unwrap()
}

///|
fn original_reference_lower_limits() -> Limits {
  {
    max_nodes: 100,
    max_references: 100,
    max_work: 1000,
    max_identifier_bytes: 1000,
  }
}

///|
fn original_reference_test_kernel(tail : String) -> PreparedKernel {
  let owner = bind_parameters(
    prepare(original_reference_checked(tail), original_reference_lower_limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  prepare_kernel(owner, 1, max_bindings=100, max_name_bytes=10000, {
    max_nodes: 1000,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 1000,
    max_literal_text_bytes: 10000,
  }).unwrap()
}

///|
test "complete original reference work runs once across runtime and compiler bounds" {
  let kernel = original_reference_test_kernel(
    ",{\"derive\":[{\"x\":\"id\"},{\"y\":\"id\"}]}",
  )
  let limits : OrderedReferenceLimits = {
    max_references: 10000,
    max_pointer_bytes: 100000,
    max_work: 10000,
    max_frames: 100,
  }
  let attempted = Ref(0)
  let completed = Ref(0)
  let prepare = (kernel, bindings, bounds) => {
    attempted.val += 1
    let result = prepare_ordered_reference_material(kernel, bindings, bounds)
    if result is Ok(_) {
      completed.val += 1
    }
    result
  }
  let first = prepare_ordered_references_owned(kernel, limits, prepare~).unwrap()
  assert_eq(attempted.val, 1)
  assert_eq(completed.val, 1)
  let material = kernel.ordered_reference_material.unwrap()
  assert_eq(material.work, 34)
  assert_eq(material.pointer_bytes, 32)
  assert_eq(material.frames, 1)
  let next = prepare_ordered_references_owned(
    kernel,
    {
      max_references: 100000,
      max_pointer_bytes: 1000000,
      max_work: 1000000,
      max_frames: 100,
    },
    prepare~,
  ).unwrap()
  assert_true(physical_equal(first.entries, next.entries))
  assert_eq(attempted.val, 1)
  assert_eq(completed.val, 1)
  let exact : OrderedReferenceLimits = {
    max_references: 2,
    max_pointer_bytes: 32,
    max_work: 34,
    max_frames: 1,
  }
  assert_true(
    prepare_ordered_references_owned(kernel, exact, prepare~) is Ok(_),
  )
  for
    short in [
      { ..exact, max_references: 1, },
      { ..exact, max_pointer_bytes: 31, },
      { ..exact, max_work: 33, },
      { ..exact, max_frames: 0, },
    ] {
    assert_true(
      prepare_ordered_references_owned(kernel, short, prepare~)
      is Err(ReferenceLimit),
    )
  }
  assert_true(
    prepare_ordered_references_owned(
      kernel,
      { ..exact, max_work: -1, },
      prepare~,
    )
    is Err(InvalidReferenceLimits),
  )
  assert_eq(attempted.val, 1)
  assert_eq(completed.val, 1)
  assert_true(
    physical_equal(kernel.ordered_reference_material.unwrap(), material),
  )
}

///|
test "independent and copied binding material cannot inherit original reference completion" {
  let kernel = original_reference_test_kernel(",{\"derive\":[{\"x\":\"id\"}]}")
  let bounds : OrderedReferenceLimits = {
    max_references: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
    max_frames: 100,
  }
  let completed = Ref(0)
  let prepare = (kernel, bindings, bounds) => {
    let result = prepare_ordered_reference_material(kernel, bindings, bounds)
    if result is Ok(_) {
      completed.val += 1
    }
    result
  }
  let first = prepare_ordered_references_owned(kernel, bounds, prepare~).unwrap()
  let independent = original_reference_test_kernel(
    ",{\"derive\":[{\"x\":\"id\"}]}",
  )
  let separate = prepare_ordered_references_owned(independent, bounds, prepare~).unwrap()
  assert_eq(completed.val, 2)
  assert_false(physical_equal(first.entries, separate.entries))
  guard kernel.body is OrderedBindings(bindings) else {
    fail("ordered original")
  }
  let copied = { ..kernel, body: OrderedBindings(bindings.copy()), }
  let rebuilt = prepare_ordered_references_owned(copied, bounds, prepare~).unwrap()
  assert_eq(completed.val, 3)
  assert_false(physical_equal(first.entries, rebuilt.entries))
  let rebased = { ..kernel, input_id: "input", }
  let same = prepare_ordered_references_owned(rebased, bounds, prepare~).unwrap()
  assert_true(physical_equal(first.entries, same.entries))
  assert_true(physical_equal(ordered_reference_kernel(same), rebased))
  assert_eq(completed.val, 3)
  let changed = { ..kernel, body: SnapshotMap(bindings), }
  assert_true(
    prepare_ordered_references_owned(changed, bounds, prepare~)
    is Err(NotOrderedKernel),
  )
  assert_eq(completed.val, 3)
}

///|
test "failed reference preparation never installs a partial completion" {
  let kernel = original_reference_test_kernel(
    ",{\"derive\":[{\"x\":\"id\"},{\"y\":\"id\"}]}",
  )
  let bounds : OrderedReferenceLimits = {
    max_references: 1,
    max_pointer_bytes: 10000,
    max_work: 100000,
    max_frames: 100,
  }
  assert_true(prepare_ordered_references(kernel, bounds) is Err(ReferenceLimit))
  assert_true(kernel.ordered_reference_material is None)
  let original = prepare_ordered_references(kernel, {
    ..bounds,
    max_references: 2,
  }).unwrap()
  assert_eq(original.entries.length(), 2)
  let material = kernel.ordered_reference_material.unwrap()
  assert_true(prepare_ordered_references(kernel, bounds) is Err(ReferenceLimit))
  assert_true(
    physical_equal(kernel.ordered_reference_material.unwrap(), material),
  )
}

///|
test "Unicode object pointer material preserves original escaped UTF8 requirements" {
  let kernel = original_reference_test_kernel(
    ",{\"derive\":[{\"v\":{\"object\":{\"é/x~\":{\"field\":\"id\"}}}}]}",
  )
  let bounds : OrderedReferenceLimits = {
    max_references: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
    max_frames: 100,
  }
  let first = prepare_ordered_references(kernel, bounds).unwrap()
  assert_eq(first.entries.length(), 1)
  let expected = "/bindings/0/expr/body/é~1x~0"
  assert_eq(first.entries[0].at, expected)
  assert_eq(
    kernel.ordered_reference_material.unwrap().pointer_bytes,
    @utf8.encode(expected).length(),
  )
  let second = prepare_ordered_references(kernel, {
    ..bounds,
    max_work: 100001,
  }).unwrap()
  assert_true(physical_equal(first.entries, second.entries))
}

///|
test "empty reference material still preserves original traversal and live frame guards" {
  let kernel = original_reference_test_kernel(
    ",{\"derive\":[{\"payload\":{\"literal\":{\"op\":\"field\",\"body\":\"missing\",\"$param\":\"business\"}}}]}",
  )
  let exact : OrderedReferenceLimits = {
    max_references: 0,
    max_pointer_bytes: 0,
    max_work: 17,
    max_frames: 1,
  }
  let first = prepare_ordered_references(kernel, exact).unwrap()
  assert_true(first.entries.is_empty())
  let material = kernel.ordered_reference_material.unwrap()
  assert_eq(material.work, 17)
  assert_eq(material.pointer_bytes, 0)
  assert_eq(material.frames, 1)
  assert_true(
    prepare_ordered_references(kernel, { ..exact, max_work: 16, })
    is Err(ReferenceLimit),
  )
  assert_true(
    prepare_ordered_references(kernel, { ..exact, max_frames: 0, })
    is Err(ReferenceLimit),
  )
  let same = prepare_ordered_references(kernel, { ..exact, max_work: 1000, }).unwrap()
  assert_true(physical_equal(first.entries, same.entries))
}
