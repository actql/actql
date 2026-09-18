///|
fn top_k_checked(
  body : String,
  declarations : @parameter.Declarations?,
) -> @pipeline.CheckedPipeline {
  let row = @schema.from_fields(
    [
      (
        @schema.Unqualified("amount"),
        @contract.primitive(NumberType, nullable=true),
      ),
      (
        @schema.Unqualified("group"),
        @contract.primitive(StringType, nullable=true),
      ),
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
    ],
    max_fields=3,
    max_name_bytes=13,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  @pipeline.check_with_evidence(
    cursor("[{" + body + "}]"),
    [("rows", @pipeline.KeyedInput(key))],
    declarations,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn top_k_owner(body : String) -> @lowering_relation.BoundPrepared {
  let checked = top_k_checked(body, None)
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "top-k emits the checked total order without a sort-limit substitute" {
  let owner = top_k_owner(
    "\"top_k\":{\"k\":2,\"by\":[{\"field\":\"amount\",\"dir\":\"desc\",\"nulls\":\"first\"}]}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("top-k")
  }
  assert_eq(@lowering_relation.kernel_top_k_count(kernel), Some(2L))
  assert_false(@lowering_relation.kernel_is_partitioned_top_k(kernel))
  assert_eq(@lowering_relation.kernel_top_k_partition_count(kernel), 0)
  assert_eq(@lowering_relation.kernel_sort_term_count(kernel), 2)
  assert_eq(
    @lowering_relation.kernel_sort_term_at(kernel, 0),
    Some((@schema.Unqualified("amount"), true, true)),
  )
  assert_eq(
    @lowering_relation.kernel_sort_term_at(kernel, 1),
    Some((@schema.Unqualified("id"), false, false)),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"top_k_0\",\"in\":[\"input_0\"],\"op\":\"REL.topk\",\"params\":{\"by\":[{\"dir\":\"desc\",\"field\":\"amount\",\"nulls\":\"first\"},{\"dir\":\"asc\",\"field\":\"id\",\"nulls\":\"last\"}],\"k\":2}}",
  )
}

///|
test "partitioned top-k retains repeated partitions and completed rank order" {
  let owner = top_k_owner(
    "\"top_k_by\":{\"partition_by\":[\"group\",\"group\"],\"k\":1,\"by\":[{\"amount\":\"desc\"}]}",
  )
  let exact = { ..sequence_limits(), max_bindings: 4, max_name_bytes: 18, }
  let sequence = @lowering_relation.prepare_sequence(owner, exact).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("partitioned top-k")
  }
  assert_eq(@lowering_relation.kernel_top_k_count(kernel), Some(1L))
  assert_true(@lowering_relation.kernel_is_partitioned_top_k(kernel))
  assert_eq(@lowering_relation.kernel_top_k_partition_count(kernel), 2)
  for i = 0; i < 2; i = i + 1 {
    assert_eq(
      @lowering_relation.kernel_top_k_partition_at(kernel, i),
      Some(@schema.Unqualified("group")),
    )
  }
  assert_eq(@lowering_relation.kernel_sort_term_count(kernel), 2)
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"top_k_by_0\",\"in\":[\"input_0\"],\"op\":\"REL.topk_partitioned\",\"params\":{\"by\":[{\"dir\":\"desc\",\"field\":\"amount\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"id\",\"nulls\":\"last\"}],\"k\":1,\"partition_by\":[\"group\",\"group\"]}}",
  )
  for
    limited in [
      { ..exact, max_bindings: 3, },
      { ..exact, max_name_bytes: 17, },
      { ..exact, expressions: { ..exact.expressions, max_work: 3, }, },
    ] {
    assert_true(
      @lowering_relation.prepare_sequence(owner, limited)
      is Err(
        @lowering_relation.KernelFailure(
          0,
          @lowering_relation.KernelBudgetExceeded
        )
      ),
    )
  }
}

///|
test "top-k binds a whole positive safe-integer Parameter before execution" {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"k\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let prepared = @lowering_relation.prepare(
    top_k_checked(
      "\"top_k\":{\"k\":{\"$param\":\"k\"},\"by\":[{\"id\":\"asc\"}]}",
      Some(declarations),
    ),
    limits(),
  ).unwrap()
  for
    (wire, expected) in [
      ("{\"k\":2}", Some(2L)),
      ("{\"k\":0}", None),
      ("{\"k\":1.5}", None),
      ("{\"k\":9007199254740992}", None),
    ] {
    guard @parameter.bind(declarations, Some(cursor(wire)), {
        max_nodes: 10,
        max_depth: 10,
        max_text_bytes: 1000,
      }).unwrap()
      is Ready(values) else {
      fail("complete parameter fixture")
    }
    let bound = @lowering_relation.bind_parameters(
      prepared,
      Some(values),
      max_parameters=1,
      max_name_bytes=1,
    ).unwrap()
    let result = @lowering_relation.prepare_sequence(bound, sequence_limits())
    match expected {
      Some(count) => {
        guard @lowering_relation.sequence_step(result.unwrap(), 0)
          is Some(@lowering_relation.RowStep(kernel)) else {
          fail("parameter top-k")
        }
        assert_eq(@lowering_relation.kernel_top_k_count(kernel), Some(count))
      }
      None =>
        assert_true(
          result
          is Err(
            @lowering_relation.KernelFailure(
              0,
              @lowering_relation.InvalidTopKCount
            )
          ),
        )
    }
  }
}
