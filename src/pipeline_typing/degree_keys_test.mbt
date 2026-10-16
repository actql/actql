///|
test "degree node_id key retains its checked Graph producer for every direction" {
  let graph = query_graph()
  for direction in ["in", "out", "both"] {
    let pipeline = @pipeline_typing.check_carriers(
      cursor("[{\"degree\":{\"direction\":\"" + direction + "\"}}]"),
      [("g", graph)],
      None,
      None,
      limits(),
    ).unwrap()
    let keys = @pipeline_typing.candidate_keys(pipeline, Step(0)).unwrap()
    assert_eq(@evidence.key_witness_count(keys), 1)
    let key = @evidence.key_witness_at(keys, 0).unwrap()
    assert_eq(@evidence.key_origin(key), GraphQueryResult)
    assert_eq(@evidence.key_field_count(key), 1)
    let identity = @evidence.key_field_at(key, 0).unwrap()
    assert_eq(identity.name, Unqualified("node_id"))
    assert_false(identity.contract.unwrap().nullable)
    assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
    guard @evidence.key_graph_query_producer(key) is Some(DegreeOperation(op)) else {
      abort("the actual checked degree producer must own the key")
    }
    assert_true(physical_equal(@graph.degree_input(op), graph))
    let used = @evidence.graph_query_keys(DegreeOperation(op), {
      max_work: 100,
      max_name_bytes: 1000,
    }).unwrap()
    assert_true(
      @evidence.graph_query_keys(DegreeOperation(op), {
        max_work: used.work,
        max_name_bytes: used.name_bytes,
      })
      is Ok(_),
    )
    assert_true(
      @evidence.graph_query_keys(DegreeOperation(op), {
        max_work: used.work - 1,
        max_name_bytes: used.name_bytes,
      })
      is Err(_),
    )
    assert_true(
      @evidence.graph_query_keys(DegreeOperation(op), {
        max_work: used.work,
        max_name_bytes: used.name_bytes - 1,
      })
      is Err(_),
    )
  }
}

///|
test "degree projection transfers only the retained semantic node identity" {
  for
    (fields, expected) in [
      ("[{\"identity\":\"node_id\"}]", 1),
      ("[\"degree\"]", 0),
    ] {
    let pipeline = @pipeline_typing.check_carriers(
      cursor(
        "[{\"degree\":{\"direction\":\"out\"}},{\"select\":" + fields + "}]",
      ),
      [("g", query_graph())],
      None,
      None,
      limits(),
    ).unwrap()
    let keys = @pipeline_typing.candidate_keys(pipeline, Step(1)).unwrap()
    assert_eq(@evidence.key_witness_count(keys), expected)
    if expected == 1 {
      let key = @evidence.key_witness_at(keys, 0).unwrap()
      assert_eq(
        @evidence.key_field_at(key, 0).unwrap().name,
        Unqualified("identity"),
      )
      assert_eq(
        @evidence.declared_key_field_at(key, 0).unwrap().name,
        Unqualified("node_id"),
      )
      assert_true(
        @evidence.key_graph_query_producer(key) is Some(DegreeOperation(_)),
      )
    }
  }
}
