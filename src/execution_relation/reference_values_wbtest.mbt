///|
fn issued_resource_value(
  contract : @contract.Contract,
  identity : String,
  live : Ref[Bool],
) -> @admitted.CheckedValue {
  let wire = "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"" +
    identity +
    "\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"mail\",\"resource_kind\":\"mail/message\",\"version\":\"actql-resource-ref/0.1\"}"
  issued_reference_value(contract, wire, live)
}

///|
fn issued_reference_value(
  contract : @contract.Contract,
  wire : String,
  live : Ref[Bool],
) -> @admitted.CheckedValue {
  @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      live.val
    }),
    contract,
    wire,
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
}

///|
fn issued_artifact_value(
  contract : @contract.Contract,
  live : Ref[Bool],
) -> @admitted.CheckedValue {
  let wire = "{\"$actql_ref\":\"artifact\",\"artifact_ref_cid\":\"sha256:15e902418023a2de574d29d716f3b643825e19afa1fa3a5a46e049ffb1606eff\",\"media_type\":\"application/json\",\"metadata\":{\"artifact_store_id\":\"fixture\",\"availability_evidence_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"capture_authority\":\"read_content\",\"content_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"issuer_evidence\":{},\"media_type\":\"application/json\",\"retention_class\":\"fixture\",\"size_bytes\":3,\"storage_scope\":\"workspace\",\"truncated\":false},\"version\":\"actql-artifact-ref/0.1\"}"
  issued_reference_value(contract, wire, live)
}

///|
test "owned references preserve identity equality and current authorization" {
  let contract = select_checked_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let live = Ref(true)
  let first = issued_resource_value(
    contract, "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    live,
  )
  let same = issued_resource_value(
    contract, "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    live,
  )
  let other = issued_resource_value(
    contract, "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    live,
  )
  assert_true(
    binary(Equal, capture(first.value), capture(same.value)).unwrap()
    is Boolean(true),
  )
  assert_true(
    binary(Equal, capture(first.value), capture(other.value)).unwrap()
    is Boolean(false),
  )
  guard compare_admitted_value(first.value, same.value, {
      remaining: 10000,
      max_frames: 10,
    })
    is Ok(ordering) else {
    fail("reference ordering")
  }
  assert_eq(ordering, 0)
  live.val = false
  assert_true(
    binary(Equal, capture(first.value), capture(same.value))
    is Err(InvalidOperand),
  )
}

///|
test "select preserves owned resource and artifact references and NULL" {
  let owner = capture_fixture()
  for kind in ["resource", "artifact"] {
    let contract = select_checked_contract(
      if kind == "resource" {
        "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"mail/message\"}"
      } else {
        "{\"type\":\"artifact_ref\",\"nullable\":true,\"media_type\":\"application/json\"}"
      },
    )
    let schema = @schema.from_fields(
      [(@schema.Unqualified("input"), contract)],
      max_fields=1,
      max_name_bytes=100,
    ).unwrap()
    let live = Ref(true)
    let value = if kind == "resource" {
      issued_resource_value(
        contract, "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        live,
      ).value
    } else {
      issued_artifact_value(contract, live).value
    }
    let null = @admitted.admit(contract, input_cursor("null"), {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 0,
      }).unwrap().value
    let table : CompletedTable = AdmittedTable({
      owner,
      id: "source",
      names: ["input"],
      rows: [[value], [null]],
    })
    let result = evaluate_completed_body(
      Projection(select_projection(schema, "[{\"output\":\"input\"}]")),
      table,
      "selected",
      2,
      { remaining: 100000, max_frames: 100, },
      value_budget({
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 10,
        max_work: 100000,
      }).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
      None,
    ).unwrap()
    guard result is AdmittedTable(projected) else {
      fail("select changed the admitted representation")
    }
    assert_true(physical_equal(projected.rows[0][0], value))
    assert_true(projected.rows[1][0] is @admitted.Null)
    live.val = false
    assert_false(
      @admitted.reference_available(
        match projected.rows[0][0] {
          @admitted.Reference(reference) => reference
          _ => fail("reference output")
        },
      ),
    )
  }
}

///|
test "append preserves owned resource and artifact references and NULL" {
  for kind in ["resource", "artifact"] {
    let contract = append_contract(
      if kind == "resource" {
        "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"mail/message\"}"
      } else {
        "{\"type\":\"artifact_ref\",\"nullable\":true,\"media_type\":\"application/json\"}"
      },
    )
    let owner = append_input_owner(contract)
    guard @lower.sequence_step(prepared_sequence(owner), 0)
      is Some(@lower.AppendStep(kernel)) else {
      fail("append kernel")
    }
    let live = Ref(true)
    let value = if kind == "resource" {
      issued_resource_value(
        contract, "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        live,
      ).value
    } else {
      issued_artifact_value(contract, live).value
    }
    let null = @admitted.admit(contract, input_cursor("null"), {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 0,
      }).unwrap().value
    let result = evaluate_append_rows(
      kernel,
      AdmittedTable({ owner, id: "input_0", names: ["value"], rows: [[value]], }),
      AdmittedTable({ owner, id: "input_1", names: ["value"], rows: [[null]], }),
      2,
      { remaining: 100000, max_frames: 100, },
      value_budget({
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 10,
        max_work: 100000,
      }).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
    ).unwrap()
    assert_eq(result.rows.length(), 2)
    assert_true(
      result.rows[0][0] is Captured(actual) && physical_equal(actual, value),
    )
    assert_true(result.rows[1][0] is Null)
    live.val = false
    assert_true(
      result.rows[0][0] is Captured(@admitted.Reference(reference)) &&
      !@admitted.reference_available(reference),
    )
  }
}
