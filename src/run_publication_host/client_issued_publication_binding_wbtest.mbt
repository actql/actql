///|
fn issued_binding_documents() -> Array[String] {
  [
    input_result_document,
    input_result_document
    .replace(old="\"results\":{\"rows\":", new="\"results\":{\"é/~\":")
    .replace(old="\"result\":\"rows\"", new="\"result\":\"é/~\""),
    input_result_document
    .replace(old="\"results\":{\"rows\":", new="\"results\":{\"e\u0301/~\":")
    .replace(old="\"result\":\"rows\"", new="\"result\":\"e\u0301/~\""),
  ]
}

///|
test "issued publication fields equal the unchanged reader for original Unicode and escaped Result ports" {
  for document in issued_binding_documents() {
    let prepared = input_result_prepared(document)
    for unit in 0..<2 {
      for scope in [Rows, Bytes] {
        let (wire, fields) = emit_client_publication_binding_material(
          prepared, unit, 0, scope, 65536, 4096, 64,
        ).unwrap()
        assert_true(fields is Some(_))
        assert_eq(
          fields,
          parse_client_publication_binding(wire, 65536, 4096, 64),
        )
        assert_eq(
          emit_prepared_client_publication_binding(
            prepared, unit, 0, scope, 65536, 4096, 64,
          ),
          Ok(wire),
        )
        // Root, seven fields, and four target fields are twelve value nodes.
        let bytes = @utf8.encode(wire).length()
        let exact = emit_client_publication_binding_material(
          prepared, unit, 0, scope, bytes, 12, 2,
        ).unwrap()
        assert_eq(exact, (wire, fields))
        assert_eq(fields, parse_client_publication_binding(wire, bytes, 12, 2))
        for
          (max_bytes, nodes, depth) in [
            (bytes - 1, 12, 2),
            (bytes, 11, 2),
            (bytes, 12, 1),
          ] {
          assert_true(
            emit_client_publication_binding_material(
              prepared, unit, 0, scope, max_bytes, nodes, depth,
            )
            is Err(Encoding),
          )
          assert_true(
            parse_client_publication_binding(wire, max_bytes, nodes, depth)
            is None,
          )
        }
      }
    }
  }
}

///|
test "fresh publication facts retain the complete checked inventory and saved-reader semantics" {
  for document in issued_binding_documents() {
    let prepared = input_result_prepared(document)
    let facts = issue_prepared_client_publication_plan_facts(
      prepared, 4, 65536, 4096, 64,
    ).unwrap()
    assert_eq(facts.limits.length(), 4)
    assert_eq(facts.bindings.length(), 4)
    assert_eq(facts.entries.length(), 4)
    admit_prepared_client_publication_plan_facts(
      prepared,
      facts.limits,
      facts.bindings,
      4,
      65536,
      4096,
      64,
    ).unwrap()
    let reversed = facts.bindings.rev()
    admit_prepared_client_publication_binding_set(
      prepared, reversed, 4, 65536, 4096, 64,
    ).unwrap()
    assert_true(
      issue_prepared_client_publication_plan_facts(prepared, 3, 65536, 4096, 64)
      is Err(Limits(BudgetExceeded)),
    )
    assert_eq(
      admit_prepared_client_publication_binding_set(
        prepared,
        [facts.bindings[0]],
        4,
        65536,
        4096,
        64,
      ),
      Err(MissingBinding),
    )
  }
}

///|
test "saved publication strings still reject unknown fields and unsafe Number values" {
  let prepared = input_result_prepared(input_result_document)
  let (wire, fields) = emit_client_publication_binding_material(
    prepared,
    0,
    0,
    Rows,
    65536,
    4096,
    64,
  ).unwrap()
  let fields = fields.unwrap()
  let unknown = wire.replace(old="{", new="{\"unknown\":0,")
  let outside_domain = wire.replace(
    old="\"effective_max\":" + fields.effective_max.to_string(),
    new="\"effective_max\":9007199254740992",
  )
  for invalid in [unknown, outside_domain] {
    assert_eq(
      admit_prepared_client_publication_binding(
        prepared,
        0,
        0,
        Rows,
        invalid,
        65536,
        4096,
        64,
      ),
      Err(InvalidBinding),
    )
  }
}
