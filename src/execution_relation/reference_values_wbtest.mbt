///|
fn issued_resource_value(
  contract : @contract.Contract,
  identity : String,
  live : Ref[Bool],
) -> @admitted.CheckedValue {
  let wire = "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"" +
    identity +
    "\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"mail\",\"resource_kind\":\"mail/message\",\"version\":\"actql-resource-ref/0.1\"}"
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
test "select preserves an exact owned reference without exposing its issuer" {
  let owner = capture_fixture()
  let contract = select_checked_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let schema = @schema.from_fields(
    [(@schema.Unqualified("input"), contract)],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let live = Ref(true)
  let value = issued_resource_value(
      contract, "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      live,
    ).value
  let table : CompletedTable = AdmittedTable({
    owner,
    id: "source",
    names: ["input"],
    rows: [[value]],
  })
  let result = evaluate_completed_body(
    Projection(select_projection(schema, "[{\"output\":\"input\"}]")),
    table,
    "selected",
    1,
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
