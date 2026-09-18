///|
fn lag_owner(
  body : String,
  declarations? : @parameter.Declarations? = None,
  values? : @parameter.BoundValues? = None,
) -> @lowering_relation.BoundPrepared {
  let checked = top_k_checked(body, declarations)
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    values,
    max_parameters=1,
    max_name_bytes=32,
  ).unwrap()
}

///|
test "lag emits owned partition order navigation and key completion" {
  let owner = lag_owner(
    "\"lag\":{\"partition_by\":[\"group\",\"group\"]," +
    "\"order_by\":[{\"amount\":\"desc\"}],\"field\":\"amount\"," +
    "\"output\":\"previous\",\"offset\":2}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("lag")
  }
  assert_eq(
    @lowering_relation.kernel_lag(kernel),
    Some((@schema.Unqualified("amount"), "previous", 2L)),
  )
  assert_eq(@lowering_relation.kernel_lag_partition_count(kernel), 2)
  assert_eq(@lowering_relation.kernel_sort_term_count(kernel), 2)
  assert_eq(
    @lowering_relation.kernel_sort_term_at(kernel, 0),
    Some((@schema.Unqualified("amount"), true, false)),
  )
  assert_eq(
    @lowering_relation.kernel_sort_term_at(kernel, 1),
    Some((@schema.Unqualified("id"), false, false)),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"lag_0\",\"in\":[\"input_0\"],\"op\":" +
    "\"REL.window.lag\",\"params\":{\"as\":\"previous\"," +
    "\"field\":\"amount\",\"offset\":2,\"order_by\":[{" +
    "\"column\":\"amount\",\"dir\":\"desc\",\"nulls\":" +
    "\"last\"},{\"column\":\"id\",\"dir\":\"asc\"," +
    "\"nulls\":\"last\"}],\"partition_by\":[\"group\"," +
    "\"group\"]}}",
  )
}

///|
test "lag binds a positive safe integer offset before kernel publication" {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"offset\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for
    (wire, expected) in [("{\"offset\":3}", Some(3L)), ("{\"offset\":0}", None)] {
    let values = match
      @parameter.bind(declarations, Some(cursor(wire)), {
        max_nodes: 10,
        max_depth: 10,
        max_text_bytes: 1000,
      }).unwrap() {
      Ready(values) => values
      NeedsBindings(_) => abort("fixture is complete")
    }
    let owner = lag_owner(
      "\"lag\":{\"partition_by\":[],\"order_by\":[{\"id\":" +
      "\"asc\"}],\"field\":\"amount\",\"output\":\"previous\"," +
      "\"offset\":{\"$param\":\"offset\"}}",
      declarations=Some(declarations),
      values=Some(values),
    )
    let prepared = @lowering_relation.prepare_sequence(owner, sequence_limits())
    match expected {
      Some(value) => {
        guard prepared is Ok(sequence) &&
          @lowering_relation.sequence_step(sequence, 0)
          is Some(@lowering_relation.RowStep(kernel)) else {
          fail("lag parameter")
        }
        assert_eq(
          @lowering_relation.kernel_lag(kernel).map(view => view.2),
          Some(value),
        )
      }
      None =>
        assert_true(
          prepared
          is Err(
            @lowering_relation.KernelFailure(
              0,
              @lowering_relation.InvalidLagOffset
            )
          ),
        )
    }
  }
}
