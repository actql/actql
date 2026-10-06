///|
fn identity_fixture_preparation(
  builder : Builder,
  keys : Array[@value.CheckedValue],
) -> PropertyIdentityPreparation {
  let profile = @carrier.graph_definition(builder.graph)
  start_property_identity(
    builder,
    profile,
    @carrier.graph_node_at(profile, 0).unwrap(),
    keys,
    1,
  ).unwrap()
}

///|
fn completed_identity(
  preparation : PropertyIdentityPreparation,
  quantum : Int,
) -> Result[(@value.CheckedValue?, Int), Issue] raise {
  for _ in 0..<10000 {
    match advance_property_identity(preparation, quantum) {
      PropertyIdentityContinue(work~) =>
        assert_true(work > 0 && work <= quantum)
      PropertyIdentityComplete(value, construction_work~, work~) => {
        assert_true(work >= 0 && work <= quantum)
        cleanup_property_identity(preparation)
        return Ok((value, construction_work))
      }
      PropertyIdentityFailed(issue, work~) => {
        assert_true(work >= 0 && work <= quantum)
        cleanup_property_identity(preparation)
        return Err(issue)
      }
    }
  }
  cleanup_property_identity(preparation)
  abort("identity conversion did not terminate")
}

///|
test "Graph storage identity conversion resumes canonical composite keys" {
  for quantum in [1, 7, 64] {
    let builder = prepare(
      property_fixture(composite=true),
      DeclaredNodes,
      property_limits(),
    ).unwrap()
    let preparation = identity_fixture_preparation(builder, [
      number(1),
      text("a"),
    ])
    let (identity, work) = completed_identity(preparation, quantum).unwrap()
    let out = @encode.writer(1000, 100, 10)
    @value.emit_checked_wire_value(identity.unwrap(), out)
    assert_eq(
      @encode.finish(out),
      "{\"$json\":{\"definition\":\"N\",\"domain\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"key\":[1,\"a\"],\"key_types\":[{\"kind\":\"number\"},{\"kind\":\"string\"}]}}",
    )
    // Independently counted document: 11 value nodes and two key components.
    assert_eq(work, 46)
    assert_eq(builder_node_count(builder), 0)
    assert_eq(builder_construction_work(builder), 0)
    assert_true(cancel(builder))
  }
}

///|
test "Graph storage identity conversion preserves exact constructor work ceiling" {
  for (work, expected) in [(34, true), (33, false)] {
    let builder = prepare(property_fixture(), DeclaredNodes, {
      ..property_limits(),
      max_work: work,
    }).unwrap()
    match
      completed_identity(identity_fixture_preparation(builder, [number(1)]), 1) {
      Ok((Some(_), construction_work)) => {
        assert_true(expected)
        assert_eq(construction_work, 33)
      }
      Err(issue) => {
        assert_true(!expected)
        assert_eq(issue, WorkLimit)
      }
      _ => abort("non-null key was excluded")
    }
    assert_true(cancel(builder))
  }
  let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
  let (identity, work) = completed_identity(
    identity_fixture_preparation(builder, [nullable_null()]),
    1,
  ).unwrap()
  assert_true(identity is None)
  assert_eq(work, 1)
  assert_eq(builder_node_count(builder), 0)
  assert_true(cancel(builder))
}

///|
test "Graph storage identity conversion retains type and encoding refusal" {
  let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
  assert_true(
    completed_identity(identity_fixture_preparation(builder, [text("1")]), 1)
    is Err(InvalidIdentity),
  )
  assert_true(cancel(builder))
  let limited = prepare(property_fixture(), DeclaredNodes, {
    ..property_limits(),
    max_value_bytes: 1,
  }).unwrap()
  assert_true(
    completed_identity(identity_fixture_preparation(limited, [number(1)]), 1)
    is Err(ValueLimit),
  )
  assert_true(cancel(limited))
}

///|
test "Graph storage identity invalid quantum is non-mutating and failure is terminal" {
  let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
  let preparation = identity_fixture_preparation(builder, [number(1)])
  assert_true(
    advance_property_identity(preparation, 0)
    is PropertyIdentityFailed(InvalidLimits, work=0),
  )
  assert_true(preparation.phase == CheckIdentityKeys)
  assert_true(preparation.keys.is_empty())
  assert_true(completed_identity(preparation, 1) is Ok((Some(_), 33)))
  let rejected = identity_fixture_preparation(builder, [text("1")])
  assert_true(
    advance_property_identity(rejected, 1)
    is PropertyIdentityFailed(InvalidIdentity, work=1),
  )
  assert_true(
    advance_property_identity(rejected, 1)
    is PropertyIdentityFailed(Closed, work=0),
  )
  cleanup_property_identity(rejected)
  assert_true(builder.open)
  assert_true(cancel(builder))
}

///|
test "Graph storage identity conversion cancellation releases every data owner" {
  for stop in [IdentityKeys, ParseIdentity, DecodeIdentity, AdmitIdentity] {
    let builder = prepare(
      property_fixture(composite=true),
      DeclaredNodes,
      property_limits(),
    ).unwrap()
    let input_keys = [number(1), text("a")]
    let preparation = identity_fixture_preparation(builder, input_keys)
    let mut reached = false
    for _ in 0..<10000 {
      if preparation.phase == stop {
        reached = true
        break
      }
      guard advance_property_identity(preparation, 1)
        is PropertyIdentityContinue(work~) else {
        abort("conversion ended before its cancellation boundary")
      }
      assert_eq(work, 1)
    }
    assert_true(reached)
    cleanup_property_identity(preparation)
    cleanup_property_identity(preparation)
    assert_true(preparation.writer is None)
    assert_true(preparation.parser is None)
    assert_true(preparation.source is None)
    assert_true(preparation.decoder is None)
    assert_true(preparation.decoded is None)
    assert_true(preparation.admission is None)
    assert_true(preparation.input_keys is None)
    assert_true(preparation.keys.is_empty())
    assert_true(
      advance_property_identity(preparation, 1)
      is PropertyIdentityFailed(Closed, work=0),
    )
    // Cancelling temporary conversion must not clear a caller's key tuple or
    // release the provisional builder owned by the enclosing operation.
    assert_eq(input_keys.length(), 2)
    assert_eq(builder_workspace_slots(builder), 0)
    assert_true(builder.open)
    assert_true(builder.owns_private)
    assert_true(cancel(builder))
  }
}

///|
test "Graph storage resumed identity projects reference CID without minting authority" {
  let contract = @contract.read_checked(
    cursor(
      "{\"nullable\":false,\"resource_kind\":\"Issue\",\"type\":\"resource_ref\"}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let empty = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let definition = @carrier.graph_node_definition(
    "N",
    [contract],
    empty,
    [],
    max_fields=1,
    max_name_bytes=16,
  ).unwrap()
  let graph = @carrier.graph(
    "sha256:" + "0".repeat(64),
    [definition],
    [],
    max_definitions=1,
    max_contract_work=1000,
  ).unwrap()
  let authorized = Ref(true)
  let issuer = @value.bind_reference_issuer((_, _) => true, _ => authorized.val)
  let key = @value.issue_reference(
    issuer,
    contract,
    "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:" +
    "1".repeat(64) +
    "\",\"boundary_cid\":\"sha256:" +
    "2".repeat(64) +
    "\",\"identity_cid\":\"sha256:" +
    "4".repeat(64) +
    "\",\"provider_identity_cid\":\"sha256:" +
    "3".repeat(64) +
    "\",\"provider_namespace\":\"fixture\",\"resource_kind\":\"Issue\",\"version\":\"actql-resource-ref/0.1\"}",
    { max_bytes: 1000, max_nodes: 100, max_depth: 10, max_text_units: 1000, },
  ).unwrap()
  let builder = prepare(graph, DeclaredNodes, property_limits()).unwrap()
  let (identity, work) = completed_identity(
    identity_fixture_preparation(builder, [key]),
    1,
  ).unwrap()
  let out = @encode.writer(1000, 100, 10)
  @value.emit_checked_wire_value(identity.unwrap(), out)
  assert_eq(
    @encode.finish(out),
    "{\"$json\":{\"definition\":\"N\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[{\"identity\":\"sha256:" +
    "4".repeat(64) +
    "\"}],\"key_types\":[{\"kind\":\"resource_ref\",\"resource_kind\":\"Issue\"}]}}",
  )
  assert_eq(work, 41)
  authorized.val = false
  assert_true(
    completed_identity(identity_fixture_preparation(builder, [key]), 1)
    is Err(InvalidIdentity),
  )
  assert_eq(builder_node_count(builder), 0)
  assert_true(cancel(builder))
}
