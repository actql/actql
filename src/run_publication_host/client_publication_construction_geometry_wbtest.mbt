///|
fn publication_original_wire_geometry(wire : String) -> (Int, Int, Int) {
  let value = parse_plan_identity_value(wire, 100000, 10000, 100).unwrap()
  let writer = @encode.measuring_writer(100000, 10000, 100) catch {
    _ => abort("fixture writer")
  }
  @canonical.emit_value(value, writer) catch {
    _ => abort("fixture value")
  }
  @encode.finish_measurement_usage(writer) catch {
    _ => abort("fixture geometry")
  }
}

///|
test "publication construction measures every original Unit Result and Unicode subject" {
  let programs = issued_binding_documents().map(input_result_prepared)
  programs.push(complete_result_inventory_prepared())
  for prepared in programs {
    let measured = measure_prepared_client_publication_plan_facts(
      prepared, 32, 100000, 10000, 100,
    ).unwrap()
    let actual = issue_prepared_client_publication_plan_facts(
      prepared, 32, 100000, 10000, 100,
    ).unwrap()
    assert_eq(measured.limits.length(), 4)
    assert_eq(measured.bindings.length(), 4)
    assert_eq(measured.entries.length(), 4)
    assert_eq(
      measured.limits,
      actual.limits.map(publication_original_wire_geometry),
    )
    assert_eq(
      measured.bindings,
      actual.bindings.map(publication_original_wire_geometry),
    )
    assert_eq(
      measured.entries,
      actual.entries.map(publication_original_wire_geometry),
    )
    // Measurement has not installed a fact or weakened its independent saved
    // reader. All original bodies still pass that complete admission.
    admit_prepared_client_publication_plan_facts(
      prepared,
      actual.limits,
      actual.bindings,
      4,
      100000,
      10000,
      100,
    ).unwrap()
  }
}

///|
test "publication binding construction retains exact boundary and subject validation" {
  for document in issued_binding_documents() {
    let prepared = input_result_prepared(document)
    for unit in 0..<2 {
      for scope in [Rows, Bytes] {
        let (bytes, nodes, depth) = measure_client_publication_binding(
          prepared, unit, 0, scope, 65536, 4096, 64,
        ).unwrap()
        assert_eq(nodes, 12)
        assert_eq(depth, 2)
        let wire = emit_prepared_client_publication_binding(
          prepared, unit, 0, scope, bytes, nodes, depth,
        ).unwrap()
        assert_eq(@utf8.encode(wire).length(), bytes)
        for
          (b, n, d) in [
            (bytes - 1, nodes, depth),
            (bytes, nodes - 1, depth),
            (bytes, nodes, depth - 1),
          ] {
          assert_eq(
            measure_client_publication_binding(
              prepared, unit, 0, scope, b, n, d,
            ),
            Err(Encoding),
          )
          assert_true(
            emit_prepared_client_publication_binding(
              prepared, unit, 0, scope, b, n, d,
            )
            is Err(Encoding),
          )
        }
      }
    }
    assert_eq(
      measure_client_publication_binding(prepared, 2, 0, Rows, 65536, 4096, 64),
      Err(MissingPublication),
    )
  }
}

///|
test "publication fact construction retains finite inventory refusal and original issuer bytes" {
  let prepared = complete_result_inventory_prepared()
  for max_facts in [1, 3] {
    assert_eq(
      measure_prepared_client_publication_plan_facts(
        prepared, max_facts, 100000, 10000, 100,
      ),
      Err(Limits(BudgetExceeded)),
    )
    assert_true(
      issue_prepared_client_publication_plan_facts(
        prepared, max_facts, 100000, 10000, 100,
      )
      is Err(Limits(BudgetExceeded)),
    )
  }
  for
    (count, b, n, d) in [
      (0, 100000, 10000, 100),
      (4, 0, 10000, 100),
      (4, 100000, 0, 100),
      (4, 100000, 10000, 0),
    ] {
    assert_eq(
      measure_prepared_client_publication_plan_facts(prepared, count, b, n, d),
      Err(Limits(InvalidLimit)),
    )
  }
  let before = issue_prepared_client_publication_plan_facts(
    prepared, 4, 100000, 10000, 100,
  ).unwrap()
  let _ = measure_prepared_client_publication_plan_facts(
    prepared, 4, 100000, 10000, 100,
  ).unwrap()
  let after = issue_prepared_client_publication_plan_facts(
    prepared, 4, 100000, 10000, 100,
  ).unwrap()
  assert_eq(before.limits, after.limits)
  assert_eq(before.bindings, after.bindings)
  assert_eq(before.entries, after.entries)
}

///|
test "publication witness construction separates retained identities from repeated emitter work" {
  let prepared = complete_result_inventory_prepared()
  let measured = measure_prepared_client_publication_witnesses(
    prepared, 64, 100000, 10000, 100,
  ).unwrap()
  let actual = issue_prepared_client_publication_witnesses(
    prepared, 64, 100000, 10000, 100,
  ).unwrap()
  assert_eq(
    measured.bodies,
    actual.bodies.map(publication_original_wire_geometry),
  )
  assert_true(measured.occurrences > measured.bodies.length().to_int64())
  let program = @strategy.graph_program(prepared.graph)
  let mut expected = 0L
  let mut bytes = 0L
  let mut nodes = 0L
  for unit in 0..<@checked.unit_count(program) {
    for index in 0..<@checked.unit_publication_count(program, unit).unwrap() {
      let publication = @checked.unit_publication_at(program, unit, index).unwrap()
      expected += @capacity.claim_count(
        @capacity.limit_claims(@checked.publication_rows(publication)),
      ).to_int64()
      expected += @capacity.claim_count(
        @capacity.limit_claims(@checked.publication_bytes(publication)),
      ).to_int64()
      for
        claim in [
          @checked.publication_rows(publication),
          @checked.publication_bytes(publication),
        ] {
        let claims = @capacity.limit_claims(claim)
        for index in 0..<@capacity.claim_count(claims) {
          let witness = @capacity.claim_at(claims, index).unwrap()
          let writer = @encode.writer(100000, 10000, 100)
          @capacity.emit(witness, writer)
          let actual_body = @encode.finish(writer)
          let extent = publication_original_wire_geometry(actual_body)
          bytes += extent.0.to_int64()
          nodes += extent.1.to_int64()
        }
      }
    }
  }
  assert_eq(measured.occurrences, expected)
  assert_eq(measured.emitted_bytes, bytes)
  assert_eq(measured.emitted_nodes, nodes)
  let unique = actual.bodies.length()
  assert_eq(
    measure_prepared_client_publication_witnesses(
      prepared, unique, 100000, 10000, 100,
    ).unwrap(),
    measured,
  )
  assert_true(unique > 1)
  assert_eq(
    measure_prepared_client_publication_witnesses(
      prepared,
      unique - 1,
      100000,
      10000,
      100,
    ),
    Err(BudgetExceeded),
  )
  assert_true(
    issue_prepared_client_publication_witnesses(
      prepared,
      unique - 1,
      100000,
      10000,
      100,
    )
    is Err(BudgetExceeded),
  )
  let _ = admit_prepared_client_publication_witnesses(
    prepared,
    actual.bodies,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(
    measure_prepared_client_publication_witnesses(
      prepared, 0, 100000, 10000, 100,
    ),
    Err(InvalidLimits),
  )
}
