///|
fn key_projection_graph() -> @carrier.Carrier {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let names = @carrier.graph_row_names(
    Unqualified("node"),
    Unqualified("source"),
    Unqualified("target"),
    Some(Unqualified("label")),
    max_name_bytes=100,
  ).unwrap()
  @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
  ).unwrap()
}

///|
test "graph edge identity supports whole-tuple join coverage without a non-null label claim" {
  for complete in [false, true] {
    let on = if complete {
      "[\"source\",\"target\",\"label\"]"
    } else {
      "[\"source\",\"target\"]"
    }
    let source = cursor(
      "[{\"edge_rows\":true,\"as\":\"edges\"},{\"join\":{\"with\":\"edges\",\"kind\":\"inner\",\"on\":" +
      on +
      "}}]",
    )
    let p = graph_count_checked(
      @pipeline_typing.check_carriers(
        source,
        [("g", key_projection_graph())],
        None,
        None,
        limits(),
      ),
    )
    let joined = @pipeline_typing.join_evidence(p, 1).unwrap()
    if complete {
      assert_eq(joined.cardinality, Some(@join.Cardinality::OneToOne))
      for key in [joined.left.unwrap(), joined.right.unwrap()] {
        assert_eq(@evidence.key_origin(key), GraphProjectionResult)
        assert_true(@evidence.key_graph_projection_producer(key) is Some(_))
        assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
      }
    } else {
      assert_true(
        joined.left is None &&
        joined.right is None &&
        joined.cardinality is None,
      )
    }
  }
}

///|
test "graph projection keys retain role aliases and exact graph admission origin" {
  for
    (body, removed, size) in [
      ("node_rows", "[\"id\"]", 1),
      ("edge_rows", "[\"src\",\"dst\",\"rel\"]", 3),
    ] {
    let source = cursor("[{\"" + body + "\":true},{\"drop\":" + removed + "}]")
    let inputs = [("g", key_projection_graph())]
    let p = graph_count_checked(
      @pipeline_typing.check_carriers(source, inputs, None, None, limits()),
    )
    let original = @pipeline_typing.candidate_key(p, Step(0)).unwrap()
    let retained = @pipeline_typing.candidate_key(p, Step(1)).unwrap()
    assert_eq(@evidence.key_origin(retained), GraphProjectionResult)
    assert_eq(@evidence.key_field_count(retained), size)
    for i in 0..<size {
      assert_eq(@evidence.key_alias_count(original, i), 2)
      assert_eq(@evidence.key_alias_count(retained, i), 1)
    }
    let operation = @evidence.key_graph_projection_producer(retained).unwrap()
    assert_eq(@projection.graph_pending(operation), [
      ValidateGraphRecords,
      RejectRuntimeColumnCollisions,
      RestoreSemanticIdentityNames,
      ResolveGraphProjectionResources,
    ])
    assert_eq(@evidence.key_pending(retained), [ValidateKeyProducer])
    assert_true(@evidence.key_vector_projection_producer(retained) is None)
    if size == 1 {
      assert_eq(
        @evidence.key_field_at(retained, 0).unwrap().name,
        Unqualified("node"),
      )
      assert_eq(
        @evidence.declared_key_field_at(retained, 0).unwrap().name,
        Unqualified("id"),
      )
    } else {
      assert_eq(
        @evidence.key_field_at(retained, 2).unwrap().name,
        Unqualified("label"),
      )
      assert_true(
        @evidence.key_field_at(retained, 2).unwrap().contract.unwrap().nullable,
      )
      // The nullable label cannot silently become a non-null ordering key.
      assert_true(
        @evidence.select_key(
          source,
          @pipeline_typing.candidate_keys(p, Step(1)).unwrap(),
          CanonicalOrder,
          { max_work: 100, max_name_bytes: 100, },
        ).unwrap().key
        is None,
      )
    }
    let used = @pipeline_typing.usage(p)
    let cap = {
      ..limits(),
      max_work: used.work,
      max_nodes: used.nodes,
      max_text_bytes: used.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, cap) is Ok(_),
    )
    for
      small in [
        { ..cap, max_work: used.work - 1, },
        { ..cap, max_text_bytes: used.text_bytes - 1, },
      ] {
      assert_true(
        @pipeline_typing.check_carriers(source, inputs, None, None, small)
        is Err(_),
      )
    }
    let transfer = @evidence.graph_projection_keys(operation, {
      max_work: 100,
      max_name_bytes: 100,
    }).unwrap()
    let exact : @evidence.TransferLimits = {
      max_work: transfer.work,
      max_name_bytes: transfer.name_bytes,
    }
    assert_true(@evidence.graph_projection_keys(operation, exact) is Ok(_))
    assert_true(
      @evidence.graph_projection_keys(operation, {
        ..exact,
        max_work: exact.max_work - 1,
      })
      is Err({ kind: LimitExceeded, .. }),
    )
    assert_true(
      @evidence.graph_projection_keys(operation, {
        ..exact,
        max_name_bytes: exact.max_name_bytes - 1,
      })
      is Err({ kind: LimitExceeded, .. }),
    )
  }
}

///|
test "graph key transfer loses missing components and never invents opaque keys" {
  let p = @pipeline_typing.check_carriers(
    cursor("[{\"edge_rows\":true},{\"drop\":[\"rel\",\"label\"]}]"),
    [("g", key_projection_graph())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @evidence.key_witness_count(
      @pipeline_typing.candidate_keys(p, Step(1)).unwrap(),
    ),
    0,
  )
  for body in ["node_rows", "edge_rows"] {
    let unknown = @pipeline_typing.check_carriers(
      cursor("[{\"" + body + "\":true}]"),
      [("g", @carrier.unknown_carrier(GraphKind))],
      None,
      None,
      limits(),
    ).unwrap()
    assert_eq(
      @evidence.key_witness_count(
        @pipeline_typing.candidate_keys(unknown, Step(0)).unwrap(),
      ),
      0,
    )
  }
  let vector = @pipeline_typing.check_carriers(
    cursor("[{\"vectors\":true}]"),
    [("v", vector_input())],
    None,
    None,
    limits(),
  ).unwrap()
  guard @pipeline_typing.step_at(vector, 0).unwrap().operation
    is Projection(operation) else {
    abort("projection")
  }
  assert_true(
    @evidence.graph_projection_keys(operation, {
      max_work: 100,
      max_name_bytes: 100,
    })
    is Err({ kind: InputContractMismatch, .. }),
  )
}
