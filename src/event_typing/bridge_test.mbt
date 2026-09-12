///|
test "bridge validates clock roles and retains partial payload knowledge" {
  for
    kind in [
      @contract.NumberType,
      @contract.TimestampType,
      @contract.StringType,
      @contract.DateType,
    ] {
    for nullable in [false, true] {
      let rows = @carrier.rows(
        [
          (
            @row.Unqualified("key"),
            Some(@contract.decimal_contract(38, 9, nullable=false).unwrap()),
          ),
          (@row.Unqualified("time"), Some(@contract.primitive(kind, nullable~))),
          (@row.Unqualified("payload"), None),
        ],
        field_set=Open,
        max_fields=3,
        max_name_bytes=100,
      ).unwrap()
      let body = cursor("{\"id\":\"key\",\"time\":\"time\"}")
      let result = @event_typing.check_bridge(
        body,
        @carrier.relation(rows),
        limits(),
      )
      if nullable ||
        (kind != @contract.NumberType && kind != @contract.TimestampType) {
        let issue = result.unwrap_err()
        assert_eq(issue.path, [@source.Key("time")])
        assert_true(issue.kind is InvalidRole(InvalidRole(Unqualified("time"))))
      } else {
        let checked = result.unwrap()
        assert_true(@event_typing.options(checked) is ToEvents)
        assert_true(@event_typing.watermark(checked) is None)
        let pending = indexed_obligation_copy(
          @event_typing.pending_validations(checked),
          @event_typing.pending_validation_count(checked),
          i => @event_typing.pending_validation_at(checked, i),
          (a, b) => a == b,
        )
        assert_eq(
          pending.contains(ConvertTimestampClock),
          kind == @contract.TimestampType,
        )
        assert_true(!pending.contains(WatermarkClassification))
        guard @event_typing.output(checked) is @carrier.EventValue(e) else {
          abort("events")
        }
        assert_true(
          @carrier.lookup(e.records, Unqualified("payload"))
          is Present({ contract: None, .. }),
        )
        let used = @event_typing.usage(checked)
        let cap = limits()
        let exact : @event_typing.Limits = {
          ..cap,
          max_work: used.work,
          max_nodes: used.nodes,
          max_text_bytes: used.text_bytes,
        }
        assert_true(
          @event_typing.check_bridge(body, @carrier.relation(rows), exact)
          is Ok(_),
        )
        assert_true(
          @event_typing.check_bridge(body, @carrier.relation(rows), {
            ..exact,
            max_work: used.work - 1,
          })
          is Err(_),
        )
      }
    }
  }
}
