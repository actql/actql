///|
test "nearest completes sole string identities on both sides with bounded obligations" {
  let declaration = keyed_pool_input("[\"code\"]", false)
  let set = @evidence.singleton_key(declaration)
  let source = cursor("{\"queries\":\"q\",\"metric\":\"dot\",\"k\":2}")
  let c = @vector_typing.check_nearest_sources(
    source,
    KeySource(set),
    KeySource(set),
    limits(),
  ).unwrap()
  let pair = @vector_typing.nearest_pair(c)
  let sides : Array[@vector_typing.NearestSide] = [Candidates, Queries]
  for side in sides {
    let input = @vector_typing.nearest_pair_input(pair, side)
    let completed = @vector_typing.nearest_completed_identity(input).unwrap()
    assert_eq(
      @evidence.key_field_at(completed, 0).unwrap().name,
      Unqualified("code"),
    )
    assert_true(
      @vector_typing.nearest_pending(c).contains(
        JournalIdentityFieldCompletion(side, Unqualified("code")),
      ),
    )
    assert_true(
      @vector_typing.nearest_pending(c).contains(
        ValidateNearestKey(
          side,
          ValidateWholeTupleUniquenessAfterInputNormalization,
        ),
      ),
    )
  }
  let u = @vector_typing.nearest_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @vector_typing.check_nearest_sources(
      source,
      KeySource(set),
      KeySource(set),
      exact,
    )
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(
      @vector_typing.check_nearest_sources(
        source,
        KeySource(set),
        KeySource(set),
        cap,
      )
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}

///|
test "nearest does not choose among multiple implicit IDs or override explicit identity" {
  let declaration = keyed_pool_input("[\"code\"]", false)
  let relation = @carrier.relation(@evidence.keyed_records(declaration))
  let second = @evidence.declare_primary_key(cursor("[\"group\"]"), relation, {
    max_fields: 1,
    max_name_bytes: 100,
  }).unwrap()
  let set = @evidence.collect_keys(
    cursor("null"),
    relation,
    [declaration, second],
    { max_keys: 2, max_work: 100, max_name_bytes: 100, },
  ).unwrap()
  let options = @vector_typing.read_nearest_options(
    cursor("{\"queries\":\"q\",\"metric\":\"dot\",\"k\":1}"),
    limits(),
  ).unwrap()
  assert_true(
    @vector_typing.check_nearest_source(
      options,
      Candidates,
      KeySource(set),
      limits(),
    )
    is Err({ kind: MissingNearestRole("candidate_id"), .. }),
  )
  let options = @vector_typing.read_nearest_options(
    cursor(
      "{\"queries\":\"q\",\"metric\":\"dot\",\"k\":1,\"candidate_id\":\"number\"}",
    ),
    limits(),
  ).unwrap()
  let c = @vector_typing.check_nearest_source(
    options,
    Candidates,
    KeySource(set),
    limits(),
  ).unwrap()
  assert_true(@vector_typing.nearest_completed_identity(c) is None)
  assert_eq(
    @carrier.vector_identity_at(
      @vector_typing.nearest_input_vectors(c).unwrap(),
      0,
    ).unwrap().name,
    Unqualified("number"),
  )
  let no_id = @vector_typing.read_nearest_options(
    cursor("{\"queries\":\"q\",\"metric\":\"dot\",\"k\":1}"),
    limits(),
  ).unwrap()
  for primary in ["[\"number\"]", "[\"code\",\"number\"]"] {
    let set = @evidence.singleton_key(keyed_pool_input(primary, false))
    assert_true(
      @vector_typing.check_nearest_source(
        no_id,
        Candidates,
        KeySource(set),
        limits(),
      )
      is Err({ kind: MissingNearestRole("candidate_id"), .. }),
    )
  }
}
