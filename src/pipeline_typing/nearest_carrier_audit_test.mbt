///|
fn nearest_audit_input(
  identity : @contract.Contract,
  name : String,
  dimensions : Double,
  as_vectors : Bool,
) -> @carrier.Carrier {
  let rows = @carrier.rows(
    [
      (Unqualified(name), Some(identity)),
      (
        Unqualified("embedding"),
        Some(@contract.vector_contract(dimensions, nullable=false).unwrap()),
      ),
    ],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  if as_vectors {
    @carrier.vectors(
      rows,
      ids=[Unqualified(name)],
      components=Unqualified("embedding"),
      max_identity_fields=1,
    ).unwrap()
  } else {
    @carrier.relation(rows)
  }
}

///|
fn nearest_audit_body(metric : String, k : String) -> String {
  "{\"queries\":\"q\",\"candidate_id\":\"cid\",\"candidate_vector\":\"embedding\",\"query_id\":\"qid\",\"query_vector\":\"embedding\",\"metric\":\"" +
  metric +
  "\",\"k\":" +
  k +
  "}"
}

///|
test "nearest mixed Carriers keep independent ID types and alias evidence through take" {
  let identities = [
    @contract.primitive(StringType, nullable=false),
    @contract.primitive(NumberType, nullable=false),
    @contract.decimal_contract(38, 9, nullable=false).unwrap(),
    @contract.read_checked(
      cursor(
        "{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":false}",
      ),
      { max_nodes: 20, max_depth: 5, max_text_bytes: 100, },
    ).unwrap(),
  ]
  let mut cases = 0
  for candidate_type in identities {
    for query_type in identities {
      for candidate_vectors in [false, true] {
        for query_vectors in [false, true] {
          let inputs = [
            (
              "c",
              nearest_audit_input(candidate_type, "cid", 3, candidate_vectors),
            ),
            ("q", nearest_audit_input(query_type, "qid", 3, query_vectors)),
          ]
          for metric in ["cosine", "dot", "l2"] {
            let body = cursor(
              "[{\"from\":\"c\",\"nearest\":" +
              nearest_audit_body(metric, "2") +
              "},{\"select\":[{\"a\":\"candidate_id\"},{\"b\":\"candidate_id\"},\"query_id\",\"rank\"]},{\"drop\":[\"a\"]},{\"take\":1}]",
            )
            let p = @pipeline_typing.check_carriers(
              body,
              inputs,
              None,
              None,
              limits(),
            ).unwrap()
            let step = @pipeline_typing.step_at(p, 0).unwrap()
            guard step.operation is Nearest(checked~, ..) else {
              abort("nearest")
            }
            assert_eq(@pipeline_typing.input_occurrence_count(step), 2)
            assert_eq(
              @pipeline_typing.input_occurrence_at(step, 0).unwrap().target,
              Input(0),
            )
            assert_eq(
              @pipeline_typing.input_occurrence_at(step, 1).unwrap().target,
              Input(1),
            )
            let output = @pipeline_typing.output_schema(p).unwrap()
            assert_true(
              @contract.type_equal(
                @schema.lookup(output, Unqualified("b")).unwrap(),
                candidate_type,
                100,
              ),
            )
            assert_true(
              @contract.type_equal(
                @schema.lookup(output, Unqualified("query_id")).unwrap(),
                query_type,
                100,
              ),
            )
            let rank = @schema.lookup(output, Unqualified("rank")).unwrap()
            assert_true(rank.shape is Number && !rank.nullable)
            assert_eq(@schema.field_count(output), 3)
            let keys = @pipeline_typing.candidate_keys(p, Step(2)).unwrap()
            assert_eq(@evidence.key_witness_count(keys), 1)
            let key = @evidence.key_witness_at(keys, 0).unwrap()
            assert_eq(@evidence.key_field_count(key), 2)
            assert_true(
              physical_equal(
                @evidence.key_nearest_producer(key).unwrap(),
                checked,
              ),
            )
            assert_true(@pipeline_typing.take_order(p, 3) is Some(_))
            assert_eq(
              @pipeline_typing.order_origin(
                @pipeline_typing.logical_order(p, Step(2)).unwrap(),
              ),
              Step(0),
            )
            let pending = @vector.nearest_pending(checked)
            assert_true(pending.contains(ValidateBothUniqueIdentities))
            assert_true(pending.contains(AssignContiguousOneBasedRanks))
            assert_true(pending.contains(EvaluateExactNearestScores))
            let used = @pipeline_typing.usage(p)
            let exact = {
              ..limits(),
              max_work: used.work,
              max_nodes: used.nodes,
              max_text_bytes: used.text_bytes,
            }
            assert_true(
              @pipeline_typing.check_carriers(body, inputs, None, None, exact)
              is Ok(_),
            )
            for
              cap in [
                { ..exact, max_work: used.work - 1, },
                { ..exact, max_nodes: used.nodes - 1, },
                { ..exact, max_text_bytes: used.text_bytes - 1, },
              ] {
              assert_true(
                @pipeline_typing.check_carriers(body, inputs, None, None, cap)
                is Err(_),
              )
            }
            cases += 1
          }
        }
      }
    }
  }
  assert_eq(cases, 192)
}

///|
test "nearest rejects dimension and source option failures across mixed Carriers" {
  let identity = @contract.primitive(NumberType, nullable=false)
  for candidate_vectors in [false, true] {
    for query_vectors in [false, true] {
      let candidates = nearest_audit_input(
        identity, "cid", 2, candidate_vectors,
      )
      let wrong = nearest_audit_input(identity, "qid", 3, query_vectors)
      let source = cursor(
        "[{\"from\":\"c\",\"nearest\":" + nearest_audit_body("dot", "1") + "}]",
      )
      let e = @pipeline_typing.check_carriers(
        source,
        [("c", candidates), ("q", wrong)],
        None,
        None,
        limits(),
      ).unwrap_err()
      assert_eq(e.kind, Vector(DimensionMismatch(2, 3)))
      assert_eq(e.path, [
        @source.Index(0),
        @source.Key("nearest"),
        @source.Key("query_vector"),
      ])
      let queries = nearest_audit_input(identity, "qid", 2, query_vectors)
      for
        (metric, k) in [
          ("dot", "0"),
          ("dot", "1.5"),
          ("dot", "9007199254740992"),
          ("dot", "{\"$param\":\"k\"}"),
          ("approximate", "1"),
        ] {
        assert_true(
          @pipeline_typing.check_carriers(
            cursor(
              "[{\"from\":\"c\",\"nearest\":" +
              nearest_audit_body(metric, k) +
              "}]",
            ),
            [("c", candidates), ("q", queries)],
            None,
            None,
            limits(),
          )
          is Err(_),
        )
      }
    }
  }
}
