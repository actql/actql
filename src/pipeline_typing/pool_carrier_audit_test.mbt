///|
fn pool_audit_rows(
  identity : @contract.Contract,
  group : @contract.Contract,
  dimensions : Double,
) -> @carrier.Knowledge {
  @carrier.rows(
    [
      (Unqualified("id"), Some(identity)),
      (Unqualified("group"), Some(group)),
      (
        Unqualified("embedding"),
        Some(@contract.vector_contract(dimensions, nullable=false).unwrap()),
      ),
      (
        Unqualified("discard"),
        Some(@contract.primitive(BooleanType, nullable=true)),
      ),
    ],
    field_set=Closed,
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
}

///|
test "pool Carrier alternatives preserve group identity and order through projection and take" {
  let groups = [
    @contract.primitive(StringType, nullable=false),
    @contract.primitive(NumberType, nullable=false),
    @contract.decimal_contract(38, 7, nullable=false).unwrap(),
    @contract.read_checked(
      cursor(
        "{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":false}",
      ),
      { max_nodes: 20, max_depth: 5, max_text_bytes: 100, },
    ).unwrap(),
  ]
  let mut cases = 0
  for numeric_member in [false, true] {
    let identity = @contract.primitive(
      if numeric_member {
        NumberType
      } else {
        StringType
      },
      nullable=false,
    )
    let dimensions = if numeric_member { 2.0 } else { 3.0 }
    for group in groups {
      let rows = pool_audit_rows(identity, group, dimensions)
      for as_vectors in [false, true] {
        let input : @pipeline_typing.InputContract = if as_vectors {
          @pipeline_typing.CarrierInput(
            @carrier.vectors(
              rows,
              ids=[Unqualified("id")],
              components=Unqualified("embedding"),
              max_identity_fields=1,
            ).unwrap(),
          )
        } else {
          @pipeline_typing.KeyedInput(
            @evidence.declare_primary_key(
              cursor("[\"id\"]"),
              @carrier.relation(rows),
              { max_fields: 1, max_name_bytes: 10, },
            ).unwrap(),
          )
        }
        for reduction in ["mean", "sum", "max"] {
          for renamed in [false, true] {
            let option = if renamed { ",\"output_id\":\"id\"" } else { "" }
            let fields = if renamed {
              "[\"group\",\"id\",\"member_count\"]"
            } else {
              "[\"group\",\"member_count\"]"
            }
            let body = cursor(
              "[{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"group\"],\"method\":\"" +
              reduction +
              "\"" +
              option +
              "}},{\"vectors\":true},{\"select\":" +
              fields +
              "},{\"take\":1}]",
            )
            let inputs = [("rows", input)]
            let p = @pipeline_typing.check_with_evidence(
              body,
              inputs,
              None,
              None,
              limits(),
            ).unwrap()
            guard @pipeline_typing.step_at(p, 0).unwrap().operation
              is Pool(pool) else {
              abort("pool")
            }
            assert_eq(
              @vector.pool_encodes_member_key(pool),
              !as_vectors && numeric_member,
            )
            assert_eq(
              @vector.pool_key_declaration(pool) is Some(_),
              !as_vectors,
            )
            let pending = @vector.pool_pending(pool)
            assert_true(pending.contains(ValidatePoolMemberIdentityGlobally))
            assert_true(pending.contains(QuantizeBeforeAndAfterPoolFold))
            assert_true(pending.contains(ResolvePoolResources))
            guard @vector.pooled_output(pool) is @carrier.VectorValue(v) else {
              abort("Vectors")
            }
            assert_eq(@carrier.vector_dimensions(v), dimensions)
            assert_eq(
              @carrier.vector_identity_at(v, 0).unwrap().name,
              Unqualified(if renamed { "id" } else { "group" }),
            )
            let output = @pipeline_typing.output_schema(p).unwrap()
            assert_true(
              @contract.type_equal(
                @schema.lookup(output, Unqualified("group")).unwrap(),
                group,
                100,
              ),
            )
            if renamed {
              assert_true(
                @contract.type_equal(
                  @schema.lookup(output, Unqualified("id")).unwrap(),
                  group,
                  100,
                ),
              )
            }
            assert_true(@schema.lookup(output, Unqualified("discard")) is None)
            assert_true(
              @schema.lookup(output, Unqualified("embedding")) is None,
            )
            assert_eq(@schema.field_count(output), if renamed { 3 } else { 2 })
            assert_true(@pipeline_typing.take_order(p, 3) is Some(_))
            assert_eq(
              @pipeline_typing.order_origin(
                @pipeline_typing.logical_order(p, Step(2)).unwrap(),
              ),
              Step(0),
            )
            let used = @pipeline_typing.usage(p)
            let exact = {
              ..limits(),
              max_work: used.work,
              max_nodes: used.nodes,
              max_text_bytes: used.text_bytes,
            }
            assert_true(
              @pipeline_typing.check_with_evidence(
                body,
                inputs,
                None,
                None,
                exact,
              )
              is Ok(_),
            )
            for
              cap in [
                { ..exact, max_work: used.work - 1, },
                { ..exact, max_nodes: used.nodes - 1, },
                { ..exact, max_text_bytes: used.text_bytes - 1, },
              ] {
              assert_true(
                @pipeline_typing.check_with_evidence(
                  body,
                  inputs,
                  None,
                  None,
                  cap,
                )
                is Err(_),
              )
            }
            cases += 1
          }
        }
      }
    }
  }
  assert_eq(cases, 96)
}

///|
test "pool closed bodies and identity constraints reject before downstream use" {
  let group = @contract.primitive(StringType, nullable=false)
  for as_vectors in [false, true] {
    let rows = pool_audit_rows(group, group, 2.0)
    let input : @pipeline_typing.InputContract = if as_vectors {
      @pipeline_typing.CarrierInput(
        @carrier.vectors(
          rows,
          ids=[Unqualified("id")],
          components=Unqualified("embedding"),
          max_identity_fields=1,
        ).unwrap(),
      )
    } else {
      @pipeline_typing.KeyedInput(
        @evidence.declare_primary_key(
          cursor("[\"id\"]"),
          @carrier.relation(rows),
          { max_fields: 1, max_name_bytes: 10, },
        ).unwrap(),
      )
    }
    for
      text in [
        "{\"by\":[],\"method\":\"sum\",\"vector\":\"embedding\"}", "{\"by\":[\"group\",\"group\"],\"method\":\"sum\",\"vector\":\"embedding\"}",
        "{\"by\":[\"group\"],\"method\":\"avg\",\"vector\":\"embedding\"}", "{\"by\":[\"group\"],\"method\":\"sum\",\"vector\":\"missing\"}",
        "{\"by\":[\"group\"],\"method\":\"sum\",\"vector\":\"embedding\",\"output_id\":\"member_count\"}",
        "{\"by\":[\"group\"],\"method\":\"sum\",\"vector\":\"embedding\",\"id\":\"id\"}",
        "{\"by\":[\"group\",\"id\"],\"method\":\"sum\",\"vector\":\"embedding\",\"output_id\":\"combined\"}",
        "{\"by\":[\"discard\"],\"method\":\"sum\",\"vector\":\"embedding\"}",
      ] {
      let e = @pipeline_typing.check_with_evidence(
        cursor("[{\"pool_vectors\":" + text + "}]"),
        [("rows", input)],
        None,
        None,
        limits(),
      ).unwrap_err()
      assert_eq(e.path[0], @source.Index(0))
    }
  }
}
