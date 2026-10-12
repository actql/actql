///|
test "serialize cannot fall through the ordinary pure kernel preparation" {
  let owner = expression_pipeline(
    ",{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"id\"],\"preserve_order\":true,\"name\":\"out.jsonl\"}}",
  )
  let prepared = @lowering_relation.bound_preparation(owner)
  let node = @lowering_relation.node_at(prepared, 1).unwrap()
  guard @lowering_relation.payload(node) is Serialize(checked) else {
    fail("checked content barrier")
  }
  assert_eq(@lowering_relation.operation(node), "Content.serialize")
  assert_eq(@lowering_relation.node_input_target(node, 0), Some(Step(0)))
  assert_true(
    physical_equal(
      @pipeline.serialization_input_schema(checked),
      @lowering_relation.node_output_schema(
        @lowering_relation.node_at(prepared, 0).unwrap(),
      ),
    ),
  )
  assert_true(
    @pipeline.serialization_order(@lowering_relation.pipeline(prepared), 1)
    is Some(_),
  )
  let barrier = @lowering_relation.prepare_serialization(owner, 1, max_work=3).unwrap()
  assert_true(
    physical_equal(@lowering_relation.serialization_owner(barrier), owner),
  )
  assert_true(
    physical_equal(@lowering_relation.serialization_checked(barrier), checked),
  )
  assert_eq(@lowering_relation.serialization_step(barrier), 1)
  assert_eq(
    @pipeline.serialization_order_input(
      @lowering_relation.serialization_order(barrier),
    ),
    Step(0),
  )
  assert_eq(
    @lowering_relation.serialization_author_guards(barrier),
    (None, None),
  )
  assert_eq(@lowering_relation.serialization_preparation_work(barrier), 3)
  assert_eq(
    @lowering_relation.prepare_serialization(owner, 1, max_work=2).unwrap_err().kind,
    BudgetExceeded,
  )
  assert_eq(
    @lowering_relation.prepare_serialization(owner, 0, max_work=3).unwrap_err().kind,
    NotSerialization,
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, sequence_limits())
    is Err(KernelFailure(1, MissingKernelNode)),
  )
  assert_true(
    @lowering_relation.prepare_kernel(
      owner,
      1,
      max_bindings=10,
      max_name_bytes=100,
      expression_limits(),
    )
    is Err(MissingKernelNode),
  )
  assert_eq(
    @lowering_relation.sequence_count(
      @lowering_relation.prepare_sequence_prefix(owner, 0, sequence_limits()).unwrap(),
    ),
    1,
  )
}

///|
test "serialize internal sort prepares the common kernel and keeps input schema" {
  let owner = expression_pipeline(
    ",{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"id\"],\"order_by\":[{\"id\":\"desc\"}],\"name\":\"out.jsonl\"}}",
  )
  let barrier = @lowering_relation.prepare_serialization(owner, 1, max_work=3).unwrap()
  let sequence = @lowering_relation.prepare_serialization_input_sequence(
    barrier,
    sequence_limits(),
  ).unwrap()
  assert_true(
    physical_equal(@lowering_relation.sequence_owner(sequence), owner),
  )
  assert_eq(@lowering_relation.sequence_count(sequence), 2)
  guard @lowering_relation.sequence_step(sequence, 1) is Some(RowStep(kernel)) else {
    fail("common sort kernel")
  }
  assert_true(
    @lowering_relation.kernel_body(kernel) is StableSort(Some(ExistingTotal(_))),
  )
  assert_eq(@lowering_relation.kernel_sort_term_count(kernel), 1)
  assert_eq(
    @lowering_relation.kernel_sort_term_at(kernel, 0),
    Some((Unqualified("id"), true, false)),
  )
  assert_eq(
    @schema.field_count(@lowering_relation.kernel_output_schema(kernel)),
    1,
  )
  assert_true(
    @schema.lookup_reference(
      @lowering_relation.kernel_output_schema(kernel),
      "content",
    )
    is None,
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, sequence_limits())
    is Err(KernelFailure(1, MissingKernelNode)),
  )
  assert_true(
    @lowering_relation.prepare_serialization_input_sequence(barrier, {
      ..sequence_limits(),
      max_bindings: 0,
    })
    is Err(KernelFailure(1, KernelBudgetExceeded)),
  )
  assert_true(
    @lowering_relation.prepare_serialization_input_sequence(barrier, {
      ..sequence_limits(),
      max_name_bytes: 1,
    })
    is Err(KernelFailure(1, KernelBudgetExceeded)),
  )
}
