///|
fn assert_infer_label_refusal_origin(
  result : Result[@program.Program, Issue],
  offset : Int,
) -> Unit raise {
  guard result
    is Err(
      Expression({ issue: @expression.InvalidArguments, origin: Some(at), })
    ) else {
    fail("expected the existing located InvalidArguments diagnostic")
  }
  assert_eq(@origin.start(at).byte_offset, offset)
  assert_eq(@origin.span(at).source_path, "defaults.sql")
  assert_true(@origin.kind(at) is @origin.Authored)
}

///|
test "case-colliding historical labels refuse at their original INFER" {
  let environment = infer_member_environment()
  let context = infer_input_field_context(environment)
  let prefix = "FROM tickets |> SET `ID` = secret |> ASSERT UNIQUE BY (id, `ID`)"
  for script in [false, true] {
    assert_infer_label_refusal_origin(
      compile_infer_defaults(
        prefix +
        " |> INFER `model-task:risk-score.v1` INPUT (text) AS assessment",
        context,
        script,
      ),
      prefix.length() + 4,
    )
  }
}

///|
// Authored Number identity and time fields; the Model and Common checker use
// the existing task context. No physical Source or Model is executed.
fn infer_lineage_watermark_context() -> (@check.CheckEnvironment, Context) {
  let environment = infer_member_environment()
  let source = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"at":{"type":"number","nullable":false},"text":{"type":"string","nullable":false}},"rows":[{"id":7,"at":10,"text":"urgent"},{"id":8,"at":5,"text":"normal"}]},"as":"tickets"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  (
    environment,
    {
      ..infer_member_context(environment),
      inputs: [
        {
          relation: [{ value: "tickets", quoted: false, }],
          name: "tickets",
          source: GeneratedValues(source),
          visible_fields: ["id", "at", "text"],
          graph_bindings: [],
        },
      ],
    },
  )
}

///|
test "omitted key after flat row watermark agrees with the same explicit prefix" {
  let (environment, context) = infer_lineage_watermark_context()
  let prefix = "FROM tickets |> watermark_rows(time: at, late_policy: 'mark', watermark_ms: 0) |> ASSERT UNIQUE BY (id)"
  let explicit = compile_infer_defaults(
    prefix +
    " |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (text) KEEP (*) AS assessment",
    context,
    true,
  ).unwrap()
  let omitted = compile_infer_defaults(
    prefix + " |> INFER `model-task:risk-score.v1` INPUT (text) AS assessment",
    context,
    true,
  ).unwrap()
  assert_eq(semantic(omitted), semantic(explicit))
  assert_shorthand_checked_identity(
    check_shorthand_identity_program(omitted, environment),
    check_shorthand_identity_program(explicit, environment),
  )
}

///|
test "WITH row watermark retains the actual surviving key label correspondence" {
  let (environment, context) = infer_lineage_watermark_context()
  for
    prefix in [
      "FROM (FROM tickets |> RENAME id AS ticket) |> watermark_rows(time: at, late_policy: 'mark', watermark_ms: 0) |> ASSERT UNIQUE BY (ticket)",
      "WITH marked AS (FROM (FROM tickets |> RENAME id AS ticket) |> watermark_rows(time: at, late_policy: 'mark', watermark_ms: 0)) FROM marked |> ASSERT UNIQUE BY (ticket)",
    ] {
    let explicit = compile_infer_defaults(
      prefix +
      " |> INFER `model-task:risk-score.v1` ITEM KEY (ticket) INPUT (text) KEEP (*) AS assessment",
      context,
      true,
    ).unwrap()
    let omitted = compile_infer_defaults(
      prefix + " |> INFER `model-task:risk-score.v1` INPUT (text) AS assessment",
      context,
      true,
    ).unwrap()
    assert_eq(semantic(omitted), semantic(explicit))
    assert_shorthand_checked_identity(
      check_shorthand_identity_program(omitted, environment),
      check_shorthand_identity_program(explicit, environment),
    )
    let key = infer_defaults_checked_input_key(
      check_shorthand_identity_program(omitted, environment),
    )
    assert_true(
      infer_defaults_object_field(key, "ticket").shape is @contract.Number,
    )
  }
}
