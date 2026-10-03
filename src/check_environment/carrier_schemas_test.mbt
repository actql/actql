///|
fn carrier_modes(
  body : Json,
  kind : String,
  unused? : Json? = None,
) -> SourceReadModes raise {
  let bodies = value_bodies("{\"type\":\"number\",\"nullable\":false}")
  bodies["carrier_schema"] = body
  let contents = reference_fixture(
    complete_view=true,
    carrier=kind,
    bodies~,
    unused_carrier=unused,
    policy_body=Some(policy_body_fixture("unknown")),
  )
  let refs = check_catalog_references(contents, reference_caps()).unwrap()
  let policies = check_source_data_policies(refs, policy_limits()).unwrap()
  let values = check_protocol_value_contracts(policies, protocol_value_limits()).unwrap()
  let shapes = check_source_view_shapes(values, {
    max_views: 10,
    max_work: 100000,
  }).unwrap()
  check_source_read_modes(shapes, 100000).unwrap()
}

///|
fn carrier_limits() -> CarrierSchemaLimits {
  {
    max_schemas: 10,
    max_work: 100000,
    bodies: { max_nodes: 10000, max_bytes: 100000, max_depth: 100, },
  }
}

///|
fn record_body() -> Json raise {
  @json.parse(
    (
      #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"id":{"type":"number","nullable":false},"other":{"type":"decimal","precision":38,"scale":19,"nullable":false},"at":{"type":"timestamp","nullable":false},"v":{"type":"vector","element_type":"f32","dimensions":3,"nullable":false}}}
    ),
  )
}

///|
test "Property Graph schema comparisons share the enclosing work owner, not its structural node count" {
  let body = @json.parse(
    (
      #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[],"identity_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","node_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":["id","name"],"Person":["id","name"]},"name":"N","properties":{"id":{"nullable":false,"type":"number"},"name":{"nullable":true,"type":"string"}}}],"value_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","version":"actql-property-graph-contract/0.1"}
    ),
  )
  let modes = carrier_modes(body, "graph")
  let admitted = check_carrier_schemas(modes, carrier_limits()).unwrap()
  let (bytes, nodes, work, count) = carrier_schema_usage(admitted)
  assert_eq(count, 1)
  let exact : CarrierSchemaLimits = {
    max_schemas: 1,
    max_work: work,
    bodies: { max_bytes: bytes, max_nodes: nodes, max_depth: 100, },
  }
  assert_true(check_carrier_schemas(modes, exact) is Ok(_))
  assert_true(
    check_carrier_schemas(modes, { ..exact, max_work: work - 1, }) is Err(_),
  )
  // Checking an unused second schema must charge its same validation work;
  // a Catalog can neither reset the owner nor hide a non-output definition.
  let doubled = carrier_modes(body, "graph", unused=Some(body))
  let both = check_carrier_schemas(doubled, carrier_limits()).unwrap()
  let (double_bytes, double_nodes, double_work, _) = carrier_schema_usage(both)
  assert_eq((double_bytes, double_nodes), (bytes * 2, nodes * 2))
  assert_true(double_work > work)
  assert_true(
    check_carrier_schemas(doubled, {
      ..carrier_limits(),
      max_work: double_work,
    })
    is Ok(_),
  )
  assert_true(
    check_carrier_schemas(doubled, {
      ..carrier_limits(),
      max_work: double_work - 1,
    })
    is Err(_),
  )
}

///|
fn role_body(kind : String) -> Json raise {
  if kind == "relation" {
    return record_body()
  }
  let body = if kind == "events" {
    @json.parse(
      "{\"version\":\"actql-events-contract/0.1\",\"id\":\"id\",\"time\":\"at\"}",
    )
  } else {
    @json.parse(
      "{\"version\":\"actql-vectors-contract/0.1\",\"ids\":[\"other\",\"id\"],\"components\":\"v\"}",
    )
  }
  guard body is Object(fields) else { abort("fixture") }
  fields["records"] = record_body()
  body
}

///|
test "Carrier schema proof links complete Catalogs through modes and exact output owners" {
  for kind in ["relation", "events", "vectors"] {
    let body = role_body(kind)
    let modes = carrier_modes(body, kind)
    let admitted = check_carrier_schemas(modes, carrier_limits()).unwrap()
    assert_true(physical_equal(carrier_schema_modes(admitted), modes))
    let view = read_mode_member(read_mode_view_at(modes, 0).unwrap())
    let linked = source_view_carrier(admitted, view).unwrap()
    let schema = source_view_carrier_schema(linked)
    assert_true(physical_equal(schema, carrier_schema_at(admitted, 0).unwrap()))
    assert_true(
      physical_equal(
        reference_member(source_view_carrier_reference(linked)),
        view,
      ),
    )
    let envelope = carrier_schema_envelope(schema)
    assert_true(
      physical_equal(carrier_schema_for(admitted, envelope).unwrap(), schema),
    )
    assert_true(
      physical_equal(
        reference_contract(source_view_carrier_reference(linked)),
        envelope,
      ),
    )
    assert_true(
      carrier_schema_body_cid(schema) != contract_identity(envelope).2,
    )
    match carrier_schema_value(schema) {
      @carrier.Relation(rows) => assert_eq(@carrier.field_count(rows), 4)
      @carrier.EventValue(events) => {
        assert_eq(events.identity.name, @row.Unqualified("id"))
        assert_eq(events.time.name, @row.Unqualified("at"))
        assert_eq(events.clock_encoding, @carrier.UtcTimestamp)
      }
      @carrier.VectorValue(vectors) => {
        assert_eq(
          @carrier.vector_identity_at(vectors, 0).unwrap().name,
          @row.Unqualified("other"),
        )
        assert_eq(
          @carrier.vector_identity_at(vectors, 1).unwrap().name,
          @row.Unqualified("id"),
        )
        assert_eq(@carrier.vector_dimensions(vectors), 3.0)
      }
      _ => abort("wrong Carrier")
    }
    let other_modes = carrier_modes(body, kind)
    let other = check_carrier_schemas(other_modes, carrier_limits()).unwrap()
    assert_true(
      source_view_carrier(
        admitted,
        read_mode_member(read_mode_view_at(other_modes, 0).unwrap()),
      )
      is None,
    )
    assert_true(
      carrier_schema_for(
        admitted,
        carrier_schema_envelope(carrier_schema_at(other, 0).unwrap()),
      )
      is None,
    )
    assert_true(carrier_schema_at(admitted, -1) is None)
    assert_true(carrier_schema_at(admitted, 1) is None)
    let (bytes, nodes, work, count) = carrier_schema_usage(admitted)
    assert_eq(count, 1)
    let exact : CarrierSchemaLimits = {
      max_schemas: 1,
      max_work: work,
      bodies: { max_bytes: bytes, max_nodes: nodes, max_depth: 100, },
    }
    assert_true(check_carrier_schemas(modes, exact) is Ok(_))
    for
      cap in [
        { ..exact, max_schemas: 0, },
        { ..exact, max_work: work - 1, },
        { ..exact, bodies: { ..exact.bodies, max_bytes: bytes - 1, }, },
        { ..exact, bodies: { ..exact.bodies, max_nodes: nodes - 1, }, },
        { ..exact, bodies: { ..exact.bodies, max_depth: 0, }, },
      ] {
      assert_true(check_carrier_schemas(modes, cap) is Err(_))
    }
  }
}

///|
test "unused carrier bodies are checked and shared budgets never reset" {
  let record = record_body()
  let once = check_carrier_schemas(
    carrier_modes(record, "relation"),
    carrier_limits(),
  ).unwrap()
  let (bytes, nodes, _, _) = carrier_schema_usage(once)
  let modes = carrier_modes(record, "relation", unused=Some(record))
  let twice = check_carrier_schemas(modes, carrier_limits()).unwrap()
  let (b, n, _, count) = carrier_schema_usage(twice)
  assert_eq((b, n, count), (bytes * 2, nodes * 2, 2))
  assert_true(
    check_carrier_schemas(modes, {
      ..carrier_limits(),
      bodies: { max_bytes: bytes, max_nodes: nodes, max_depth: 100, },
    })
    is Err(e) &&
    e.kind == BudgetExceeded,
  )
  assert_true(
    check_carrier_schemas(
      carrier_modes(record, "relation", unused=Some(Json::null())),
      carrier_limits(),
    )
    is Err(e) &&
    e.kind == InvalidBody,
  )
  for kind in ["graph", "events", "vectors"] {
    let result = check_carrier_schemas(
      carrier_modes(record, kind),
      carrier_limits(),
    )
    assert_true(result is Err(e) && e.kind == CarrierMismatch)
    if result is Err(e) {
      let path = @decode.cursor_path(e.source.unwrap())
      assert_eq(path[path.length() - 1], @source.Key("carrier"))
    }
  }
}
