///|
test "nearest retains original keyed sources even when explicit roles bypass completion" {
  let declaration = keyed_pool_input("[\"code\"]", false)
  let keys = @evidence.singleton_key(declaration)
  for explicit in [false, true] {
    let body = if explicit {
      "{\"queries\":\"q\",\"metric\":\"dot\",\"k\":1,\"candidate_id\":\"number\",\"query_id\":\"number\"}"
    } else {
      "{\"queries\":\"q\",\"metric\":\"dot\",\"k\":1}"
    }
    let checked = @vector_typing.check_nearest_sources(
      cursor(body),
      KeySource(keys),
      KeySource(keys),
      limits(),
    ).unwrap()
    let ranking = @vector_typing.ranking_from_nearest(checked)
    let retained = @vector_typing.ranking_input_nearest(ranking).unwrap()
    assert_true(physical_equal(checked, retained))
    let sides : Array[@vector_typing.NearestSide] = [Candidates, Queries]
    for side in sides {
      let input = @vector_typing.nearest_pair_input(
        @vector_typing.nearest_pair(retained),
        side,
      )
      guard @vector_typing.nearest_input_source(input) is KeySource(original) else {
        abort("original keyed source")
      }
      assert_true(physical_equal(original, keys))
      assert_eq(
        @vector_typing.nearest_completed_identity(input) is None,
        explicit,
      )
      assert_true(
        physical_equal(
          @carrier.vector_records(
            @vector_typing.nearest_input_vectors(input).unwrap(),
          ),
          @evidence.key_set_records(original),
        ),
      )
    }
    assert_true(
      indexed_obligation_copy(
        @vector_typing.nearest_pending(retained),
        @vector_typing.nearest_pending_count(retained),
        i => @vector_typing.nearest_pending_at(retained, i),
        (a, b) => a == b,
      ).contains(ValidateBothUniqueIdentities),
    )
  }
}

///|
test "nearest retains original Relation Vectors and opaque sources without reconstruction" {
  let rows = nearest_rows(3)
  let relation = @carrier.relation(rows)
  let typed_vectors = @carrier.vectors(
    rows,
    ids=[Unqualified("id")],
    components=Unqualified("v"),
    max_identity_fields=1,
  ).unwrap()
  let unknown = @carrier.unknown_carrier(VectorsKind)
  let options = @vector_typing.read_nearest_options(
    cursor(
      "{\"queries\":\"q\",\"metric\":\"dot\",\"k\":1,\"candidate_id\":\"id\",\"candidate_vector\":\"v\",\"query_id\":\"id\",\"query_vector\":\"v\"}",
    ),
    limits(),
  ).unwrap()
  let sides : Array[@vector_typing.NearestSide] = [Candidates, Queries]
  for supplied in [relation, typed_vectors, unknown] {
    for side in sides {
      let checked = @vector_typing.check_nearest_input(
        options,
        side,
        supplied,
        limits(),
      ).unwrap()
      guard @vector_typing.nearest_input_source(checked)
        is CarrierSource(original) else {
        abort("original Carrier source")
      }
      assert_true(physical_equal(original, supplied))
      assert_true(@vector_typing.nearest_completed_identity(checked) is None)
      if @carrier.kind(supplied) == RelationKind {
        assert_true(
          physical_equal(@carrier.relation_rows(original).unwrap(), rows),
        )
        assert_true(@vector_typing.nearest_input_vectors(checked) is Some(_))
      }
      if supplied is @carrier.Opaque(_) {
        assert_true(@vector_typing.nearest_input_vectors(checked) is None)
      }
      let usage = @vector_typing.nearest_input_usage(checked)
      assert_true(
        @vector_typing.check_nearest_input(options, side, supplied, {
          ..limits(),
          max_work: usage.work,
          max_nodes: usage.nodes,
          max_text_bytes: usage.text_bytes,
        })
        is Ok(_),
      )
    }
  }
}
