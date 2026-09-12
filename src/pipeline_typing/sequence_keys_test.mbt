///|
test "sequence disallow keys survive aliases for Relation and Events inputs" {
  for events in [false, true] {
    for overlap in ["allow", "disallow"] {
      for contiguity in ["adjacent", "subsequence"] {
        let prefix = if events {
          "{\"to_events\":{\"id\":\"id\",\"time\":\"amount\"}},"
        } else {
          ""
        }
        let text = "[" +
          prefix +
          "{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"amount\",\"pattern\":[{\"as\":\"begin\",\"where\":\"true\"},{\"as\":\"end\",\"where\":\"true\"}],\"within\":1000,\"overlap\":\"" +
          overlap +
          "\",\"contiguity\":\"" +
          contiguity +
          "\"}}," +
          "{\"select\":[{\"a\":\"begin_id\"},{\"b\":\"begin_id\"},\"end_id\"]},{\"drop\":[\"a\",\"end_id\"]},{\"sort\":[{\"b\":\"asc\"}]},{\"take\":1}]"
        let source = cursor(text)
        let p = @pipeline_typing.check(
          source,
          [("rows", schema())],
          None,
          None,
          limits(),
        ).unwrap()
        let at = if events { 1 } else { 0 }
        let keys = @pipeline_typing.candidate_keys(p, Step(at)).unwrap()
        assert_eq(
          @evidence.key_witness_count(keys),
          if overlap == "disallow" {
            2
          } else {
            0
          },
        )
        let checked = match @pipeline_typing.step_at(p, at).unwrap().operation {
          Sequence(op) => op
          _ => abort("sequence")
        }
        assert_eq(@relation.sequence_pattern_count(checked), 2)
        assert_true(@relation.sequence_pattern_at(checked, 2) is None)
        assert_true(@relation.sequence_pattern_at(checked, -1) is None)
        if overlap == "disallow" {
          for i, name in ["begin_id", "end_id"] {
            let key = @evidence.key_witness_at(keys, i).unwrap()
            assert_eq(@evidence.key_origin(key), SequenceResult)
            assert_eq(
              @evidence.key_field_at(key, 0).unwrap().name,
              Unqualified(name),
            )
            assert_true(
              physical_equal(
                @evidence.key_sequence_producer(key).unwrap(),
                checked,
              ),
            )
          }
          let key = @pipeline_typing.candidate_key(p, Step(at + 2)).unwrap()
          assert_eq(
            @evidence.key_field_at(key, 0).unwrap().name,
            Unqualified("b"),
          )
          assert_eq(
            @evidence.declared_key_field_at(key, 0).unwrap().name,
            Unqualified("begin_id"),
          )
          let producer = @evidence.key_sequence_producer(key).unwrap()
          assert_true(
            @relation.sequence_obligations(producer).contains(
              UniqueEventIdentity,
            ),
          )
          assert_true(
            @relation.sequence_obligations(producer).contains(AtomicMatchLimits),
          )
          assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
          assert_true(
            @pipeline_typing.resolve_contextual_orders(
              p,
              max_steps=10,
              max_work=10000,
              max_text_bytes=10000,
            )
            is Ok(_),
          )
          let cap : @evidence.TransferLimits = {
            max_work: 3,
            max_name_bytes: 14,
          }
          assert_true(@evidence.sequence_keys(checked, cap) is Ok(_))
          assert_true(
            @evidence.sequence_keys(checked, { ..cap, max_work: 2, }) is Err(_),
          )
          assert_true(
            @evidence.sequence_keys(checked, { ..cap, max_name_bytes: 13, })
            is Err(_),
          )
        } else {
          assert_true(@pipeline_typing.candidate_key(p, Step(at + 2)) is None)
          // Sequence still establishes occurrence order; sort uses it only for ties.
          assert_true(
            @pipeline_typing.resolve_contextual_orders(
              p,
              max_steps=10,
              max_work=10000,
              max_text_bytes=10000,
            )
            is Ok(_),
          )
          assert_true(
            @pipeline_typing.sort_order_strategy(
              @pipeline_typing.sort_order(p, at + 3).unwrap(),
            )
            is ExistingTotal(_),
          )
          assert_true(
            @evidence.sequence_keys(checked, { max_work: 1, max_name_bytes: 0, })
            is Ok(_),
          )
        }
        let u = @pipeline_typing.usage(p)
        let exact = {
          ..limits(),
          max_work: u.work,
          max_text_bytes: u.text_bytes,
          max_nodes: u.nodes,
          max_tokens: u.tokens,
        }
        assert_true(
          @pipeline_typing.check(
            source,
            [("rows", schema())],
            None,
            None,
            exact,
          )
          is Ok(_),
        )
        assert_true(
          @pipeline_typing.check(source, [("rows", schema())], None, None, {
            ..exact,
            max_work: u.work - 1,
          })
          is Err(_),
        )
      }
    }
  }
}
