///|
fn watermark_body(source : String) -> String {
  "{\"time\":\"amount\",\"late_policy\":\"mark\"," + source + "}"
}

///|
test "watermark parameter domains remain unbound and duration-aware" {
  let params = @parameter.read_declarations(
    Some(
      cursor(
        "{\"t\":{\"type\":\"number\"},\"d\":{\"type\":\"string\",\"format\":\"duration\"},\"s\":{\"type\":\"string\"}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for
    source in [
      "\"watermark_ms\":{\"$param\":\"t\"}", "\"max_skew\":{\"$param\":\"t\"}", "\"max_skew\":{\"$param\":\"d\"}",
    ] {
    assert_true(
      check_row(
        WatermarkRows,
        cursor(watermark_body(source)),
        input(),
        Some(params),
        limits(),
      )
      is Ok(_),
    )
  }
  for
    source in [
      "\"watermark_ms\":{\"$param\":\"d\"}", "\"max_skew\":{\"$param\":\"s\"}", "\"max_skew\":{\"$param\":\"missing\"}",
    ] {
    assert_true(
      check_row(
        WatermarkRows,
        cursor(watermark_body(source)),
        input(),
        Some(params),
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "watermark fixed and prefix sources retain distinct order requirements" {
  for
    (source, prefix) in [
      ("\"watermark_ms\":-0.5", false),
      ("\"max_skew\":\"01S\"", true),
      ("\"max_skew\":1000", true),
    ] {
    let checked = row_checked(WatermarkRows, watermark_body(source))
    let out = output_row(checked)
    assert_true(field(out, "watermark_ms").shape is Number)
    assert_true(!field(out, "watermark_late").nullable)
    assert_true(field(out, "watermark_late").shape is Boolean)
    assert_true(field(out, "watermark_decision").shape is Text(_))
    assert_eq(
      indexed_obligation_copy(
        @relation_typing.pending_validations(checked),
        @relation_typing.pending_validation_count(checked),
        i => @relation_typing.pending_validation_at(checked, i),
        (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
      ).any(p => p.kind == WatermarkPrefixOrder),
      prefix,
    )
    match @relation_typing.row_operation(checked).unwrap() {
      Watermark(time~, timestamp~, threshold~, policy~) => {
        assert_eq(@schema.reference_name(time.field), "amount")
        assert_eq(timestamp, false)
        assert_true(policy is MarkLate)
        if prefix {
          assert_true(threshold is PrefixSkew(Literal(1000L), duration=false))
        } else {
          assert_true(threshold is FixedThreshold(-0.5))
        }
      }
      _ => fail("expected watermark")
    }
  }
}

///|
test "watermark rejects ambiguous thresholds invalid skew and bad time contracts" {
  for
    source in [
      "\"watermark_ms\":0,\"max_skew\":1", "\"max_skew\":0", "\"max_skew\":-1", "\"max_skew\":1.5",
      "\"max_skew\":\"1.5s\"", "\"watermark_ms\":\"0\"", "\"watermark_ms\":null",
    ] {
    assert_true(
      check_row(
        WatermarkRows,
        cursor(watermark_body(source)),
        input(),
        None,
        limits(),
      )
      is Err(_),
    )
  }
  assert_true(
    check_row(
      WatermarkRows,
      cursor("{\"time\":\"amount\",\"late_policy\":\"mark\"}"),
      input(),
      None,
      limits(),
    )
    is Err(_),
  )
  for ty in ["string", "date", "boolean"] {
    let row = schema(
      "{\"amount\":{\"type\":\"" + ty + "\",\"nullable\":false}}",
    )
    assert_true(
      check_row(
        WatermarkRows,
        cursor(watermark_body("\"watermark_ms\":0")),
        row,
        None,
        limits(),
      )
      is Err(_),
    )
  }
  let collision = schema(
    "{\"amount\":{\"type\":\"number\",\"nullable\":false},\"watermark_late\":{\"type\":\"boolean\",\"nullable\":false}}",
  )
  assert_true(
    check_row(
      WatermarkRows,
      cursor(watermark_body("\"watermark_ms\":0")),
      collision,
      None,
      limits(),
    )
    is Err(_),
  )
}
