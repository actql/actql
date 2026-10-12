///|
fn row_reference_wire() -> String {
  // These fixed tokens are an admission fixture, not provider evidence.
  "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"file-fixture\",\"resource_kind\":\"file\",\"version\":\"actql-resource-ref/0.1\"}"
}

///|
fn row_reference_owner() -> (@lower.BoundPrepared, @schema.Schema) {
  let resource = @contract.read_checked(
    row_presence_cursor(
      "{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":false}",
    ),
    { max_nodes: 256, max_depth: 16, max_text_bytes: 4096, },
  ).unwrap()
  let schema = @schema.from_presence_fields(
    [
      (@schema.Unqualified("resource"), resource, @schema.Required),
      (
        @schema.Unqualified("name"),
        @contract.primitive(@contract.StringType, nullable=false),
        @schema.Required,
      ),
      (
        @schema.Unqualified("p"),
        @contract.primitive(@contract.NumberType, nullable=true),
        @schema.Conditional,
      ),
    ],
    max_fields=3,
    max_name_bytes=32,
  ).unwrap()
  let checked = @pipeline.check(
    row_presence_cursor("[{\"select\":[\"name\"]}]"),
    [("files", schema)],
    None,
    Some(row_presence_cursor("\"files\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 4096,
      max_nodes: 256,
      max_tokens: 256,
      max_depth: 16,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 4096,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  (
    owner,
    @lower.preparation_input_schema(@lower.bound_preparation(owner), 0).unwrap(),
  )
}

///|
fn row_reference_limits() -> @admitted.ReferenceLimits {
  { max_bytes: 4096, max_nodes: 256, max_depth: 16, max_text_units: 4096, }
}

///|
fn row_reference_append(
  input : @execution.AdmittedInput,
  schema : @schema.Schema,
  suffix : String,
  references? : (@admitted.ReferenceIssuer, @admitted.ReferenceLimits)? = None,
) -> Result[Unit, RowSourceIssue] {
  append_row_source_object(
    input,
    schema,
    ["resource", "name", "p"],
    row_presence_cursor(
      "{\"resource\":" +
      row_reference_wire() +
      ",\"name\":\"é/%2F\"" +
      suffix +
      "}",
    ),
    { max_nodes: 256, max_depth: 16, max_text_bytes: 4096, },
    row_presence_retention(),
    references~,
  )
}

///|
test "row reference envelopes require Host provenance and current authorization" {
  let (owner, schema) = row_reference_owner()
  let live = Ref(true)
  let expected = row_reference_wire()
  let issuer = @admitted.bind_reference_issuer((_, wire) => wire == expected, _ => {
    live.val
  })
  let input = @execution.prepare_admitted_input(
    owner,
    0,
    3,
    row_presence_retention(),
  ).unwrap()
  assert_true(row_reference_append(input, schema, "") is Err(Value("resource")))
  for suffix in ["", ",\"p\":null", ",\"p\":7"] {
    row_reference_append(
      input,
      schema,
      suffix,
      references=Some((issuer, row_reference_limits())),
    ).unwrap()
  }
  let captured = @execution.finish_admitted_input(input).unwrap()
  assert_eq(@execution.captured_row_count(captured), 3)
  assert_eq(
    [0, 1, 2].map(index => {
      @schema.field_reference_name(@schema.field_at(schema, index).unwrap())
    }),
    ["name", "p", "resource"],
  )
  for row in 0..<3 {
    guard @execution.captured_presence_cell(captured, row, 2)
      is Ok(@execution.Present(@admitted.Reference(reference))) else {
      abort("issued reference")
    }
    assert_true(@admitted.reference_available(reference))
    assert_eq(
      @admitted.reference_identity_cid(reference),
      "sha256:" + "d".repeat(64),
    )
    assert_true(
      @execution.captured_presence_cell(captured, row, 0)
      is Ok(@execution.Present(@admitted.Text("é/%2F"))),
    )
  }
  assert_true(
    @execution.captured_presence_cell(captured, 0, 1) is Ok(@execution.Absent),
  )
  assert_true(
    @execution.captured_presence_cell(captured, 1, 1)
    is Ok(@execution.Present(@admitted.Null)),
  )
  assert_true(
    @execution.captured_presence_cell(captured, 2, 1)
    is Ok(@execution.Present(@admitted.Number(7))),
  )
  live.val = false
  guard @execution.captured_presence_cell(captured, 0, 2)
    is Ok(@execution.Present(@admitted.Reference(reference))) else {
    abort("retained reference")
  }
  assert_false(@admitted.reference_available(reference))
  let next = @execution.prepare_admitted_input(
    owner,
    0,
    1,
    row_presence_retention(),
  ).unwrap()
  assert_true(
    row_reference_append(
      next,
      schema,
      "",
      references=Some((issuer, row_reference_limits())),
    )
    is Err(Value("resource")),
  )
  assert_true(@execution.cancel_admitted_input(next))
  assert_true(@execution.finish_admitted_input(next) is Err(_))
}

///|
test "row reference admission preserves issuer and envelope bounds refusal" {
  let (owner, schema) = row_reference_owner()
  let expected = row_reference_wire()
  let issuer = @admitted.bind_reference_issuer((_, wire) => wire == expected, _ => {
    true
  })
  let rejecting = @admitted.bind_reference_issuer((_, _) => false, _ => true)
  for
    (capability, limits) in [
      (rejecting, row_reference_limits()),
      (issuer, { ..row_reference_limits(), max_bytes: expected.length() - 1, }),
      (issuer, { ..row_reference_limits(), max_nodes: 1, }),
    ] {
    let input = @execution.prepare_admitted_input(
      owner,
      0,
      1,
      row_presence_retention(),
    ).unwrap()
    assert_true(
      row_reference_append(
        input,
        schema,
        "",
        references=Some((capability, limits)),
      )
      is Err(Value("resource")),
    )
    assert_true(@execution.cancel_admitted_input(input))
    assert_false(@execution.cancel_admitted_input(input))
    assert_true(@execution.finish_admitted_input(input) is Err(_))
  }
}
