///|
fn catalog_fixture(
  connector : String,
  contracts : Array[String],
  views? : Array[String] = [],
  commands? : Array[String] = [],
) -> String {
  let core = "\"commands\":[" +
    commands.join(",") +
    "],\"connector_id\":\"" +
    connector +
    "\",\"connector_version\":\"external-7\",\"contracts\":[" +
    contracts.join(",") +
    "],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[" +
    views.join(",") +
    "]}"
  let cid = "sha256:" + @sha.hex(@utf8.encode("{" + core))
  "{\"catalog_cid\":\"" + cid + "\"," + core
}

///|
fn sorted_body_array(values : Array[String]) -> String {
  let values = values.copy()
  values.sort_by((a, b) => {
    @sha.hex(@utf8.encode(a)).compare(@sha.hex(@utf8.encode(b)))
  })
  "[" + values.join(",") + "]"
}

///|
fn catalog_environment(
  catalogs : Array[String],
  contracts : Array[String],
  views? : Array[String] = [],
  commands? : Array[String] = [],
) -> ContractRegistry {
  let prefix = "{\"command_contracts\":" +
    sorted_body_array(commands) +
    ",\"connector_capabilities\":[],\"connector_catalogs\":" +
    sorted_body_array(catalogs) +
    ",\"contract_registry\":" +
    sorted_body_array(contracts) +
    ","
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":" +
    sorted_body_array(views) +
    ",\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    caps(),
  ).unwrap()
  check_contract_registry(environment, caps()).unwrap()
}

///|
test "catalog empty identity is independently fixed and exact owner is retained" {
  let body = catalog_fixture("example", [])
  let registry = catalog_environment([body], [])
  let contents = check_catalog_contents(registry, caps()).unwrap()
  assert_true(physical_equal(catalog_registry(contents), registry))
  let catalog = catalog_at(contents, 0).unwrap()
  // Node crypto, canonical closed core excluding only catalog_cid.
  assert_eq(
    catalog_identity(catalog),
    (
      "example", "external-7", "sha256:b815fd0d63f5b0713f3f0e5234334fa5fc3f65bd34486e87b842bf208094eb82",
    ),
  )
  assert_true(
    physical_equal(
      member_environment(catalog_member(catalog)),
      contract_registry_environment(registry),
    ),
  )
  assert_true(catalog_at(contents, 1) is None)
  assert_true(catalog_view_at(catalog, 0) is None)
  assert_true(catalog_command_at(catalog, 0) is None)
  let (bytes, nodes, items) = catalog_usage(contents)
  assert_eq(bytes, body.length())
  assert_eq(items, 1)
  let exact = {
    ..caps(),
    max_bytes: bytes,
    max_nodes: nodes,
    max_members: items,
  }
  assert_true(check_catalog_contents(registry, exact) is Ok(_))
  assert_true(
    check_catalog_contents(registry, { ..exact, max_bytes: bytes - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_catalog_contents(registry, { ..exact, max_nodes: nodes - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_catalog_contents(registry, { ..exact, max_members: 0, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_catalog_contents(registry, { ..exact, max_depth: 0, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_catalog_contents(registry, { ..exact, max_depth: -1, })
    is Err(InvalidLimits),
  )
}

///|
test "shared envelope is deduplicated only in derived registry and references remain local" {
  let shared = envelope("null", null_contract_cid())
  let first = catalog_fixture("first", [shared])
  let second = catalog_fixture("second", [shared])
  let registry = catalog_environment([first, second], [shared])
  let contents = check_catalog_contents(registry, caps()).unwrap()
  for i in 0..<2 {
    let catalog = catalog_at(contents, i).unwrap()
    let entry = resolve_catalog_contract(
      catalog,
      "example",
      "external-7",
      null_contract_cid(),
      "request_schema",
    ).unwrap()
    assert_true(
      physical_equal(
        member_environment(contract_member(entry)),
        contract_registry_environment(registry),
      ),
    )
    assert_true(
      resolve_catalog_contract(
        catalog,
        "example",
        "external-7",
        null_contract_cid(),
        "carrier_schema",
      )
      is Err(Contract(WrongKind(_, _))),
    )
  }
  let (bytes, nodes, items) = catalog_usage(contents)
  assert_eq(items, 4)
  let exact = {
    ..caps(),
    max_bytes: bytes,
    max_nodes: nodes,
    max_members: items,
  }
  assert_true(check_catalog_contents(registry, exact) is Ok(_))
  assert_true(
    check_catalog_contents(registry, { ..exact, max_bytes: bytes - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_catalog_contents(registry, { ..exact, max_nodes: nodes - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_catalog_contents(registry, { ..exact, max_members: items - 1, })
    is Err(BudgetExceeded),
  )
  let contents = check_catalog_contents(
    catalog_environment([first, catalog_fixture("empty", [])], [shared]),
    caps(),
  ).unwrap()
  for i in 0..<2 {
    let catalog = catalog_at(contents, i).unwrap()
    if catalog_identity(catalog).0 == "empty" {
      assert_true(
        resolve_catalog_contract(
          catalog,
          "example",
          "external-7",
          null_contract_cid(),
          "request_schema",
        )
        is Err(OutsideCatalog("example", "external-7")),
      )
    }
  }
}

///|
test "catalog membership detects extras omissions inner tampering and duplicate connectors" {
  let entry = envelope("null", null_contract_cid())
  assert_true(
    check_catalog_contents(catalog_environment([], [entry]), caps())
    is Err(DerivedMismatch(ContractRegistry)),
  )
  assert_true(
    check_catalog_contents(
      catalog_environment([catalog_fixture("example", [entry])], []),
      caps(),
    )
    is Err(DerivedMismatch(ContractRegistry)),
  )
  let tampered = catalog_fixture("example", []).replace(
    old="example",
    new="changed",
  )
  assert_true(
    check_catalog_contents(catalog_environment([tampered], []), caps())
    is Err(IdentityMismatch(0)),
  )
  assert_true(
    check_catalog_contents(
      catalog_environment(
        [catalog_fixture("example", []), catalog_fixture("example", [entry])],
        [entry],
      ),
      caps(),
    )
    is Err(DuplicateConnector("example")),
  )
  assert_true(
    check_catalog_contents(
      catalog_environment([catalog_fixture("example", [entry, entry])], [entry]),
      caps(),
    )
    is Err(UnsortedContents(0, ContractRegistry)),
  )
  let other = envelope(
    "null", "sha256:0cd9ea53bd35ffe3bca321f4d2b4e725bddf9f885f9333570f197727e1cbd048",
  ).replace(old="example", new="other")
  assert_true(
    check_catalog_contents(
      catalog_environment([catalog_fixture("example", [entry, other])], [
        entry, other,
      ]),
      caps(),
    )
    is Err(UnsortedContents(0, ContractRegistry)),
  )
  assert_true(
    check_catalog_contents(
      catalog_environment([catalog_fixture("example", [other, entry])], [
        entry, other,
      ]),
      caps(),
    )
    is Ok(_),
  )
}

///|
// This fixture covers identity/membership, deliberately not full SourceView
// admission. CatalogContents cannot be used as an admitted SourceView proof.
fn view_fixture(
  connector : String,
  name : String,
  version? : String = "external-1",
) -> String {
  let before = "{\"connector_id\":\"" +
    connector +
    "\",\"connector_version\":\"external-7\","
  let after = "\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"" +
    name +
    "\",\"view_version\":\"" +
    version +
    "\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(before + after))
  before + "\"contract_cid\":\"" + cid + "\"," + after
}

///|
fn command_fixture(connector : String) -> String {
  let before = "{\"command_id\":\"command\",\"connector_id\":\"" +
    connector +
    "\","
  let after = "\"schema\":\"actql.command_contract/0.1\",\"version\":\"external-1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(before + after))
  before + "\"contract_cid\":\"" + cid + "\"," + after
}

///|
test "view and command copies preserve selectors ownership and their own self identities" {
  let view = view_fixture("example", "main")
  let command = command_fixture("example")
  let catalog = catalog_fixture("example", [], views=[view], commands=[command])
  let registry = catalog_environment([catalog], [], views=[view], commands=[
    command,
  ])
  let contents = check_catalog_contents(registry, caps()).unwrap()
  let selected = catalog_at(contents, 0).unwrap()
  assert_eq(member_section(catalog_view_at(selected, 0).unwrap()), SourceViews)
  assert_eq(
    member_section(catalog_command_at(selected, 0).unwrap()),
    CommandContracts,
  )
  assert_true(
    check_catalog_contents(
      catalog_environment([catalog], [], commands=[command]),
      caps(),
    )
    is Err(DerivedMismatch(SourceViews)),
  )
  assert_true(
    check_catalog_contents(catalog_environment([], [], views=[view]), caps())
    is Err(DerivedMismatch(SourceViews)),
  )
  assert_true(
    check_catalog_contents(
      catalog_environment([], [], commands=[command]),
      caps(),
    )
    is Err(DerivedMismatch(CommandContracts)),
  )
  let wrong_owner = catalog_fixture("other", [], views=[view])
  assert_true(
    check_catalog_contents(
      catalog_environment([wrong_owner], [], views=[view]),
      caps(),
    )
    is Err(OwnershipMismatch(0)),
  )
  let changed = view.replace(old="main", new="changed")
  assert_true(
    check_catalog_contents(
      catalog_environment(
        [catalog_fixture("example", [], views=[changed])],
        [],
        views=[changed],
      ),
      caps(),
    )
    is Err(IdentityMismatch(0)),
  )
  let wrong_command = catalog_fixture("other", [], commands=[command])
  assert_true(
    check_catalog_contents(
      catalog_environment([wrong_command], [], commands=[command]),
      caps(),
    )
    is Err(OwnershipMismatch(0)),
  )
  let another_command = command_fixture("other")
  assert_true(
    check_catalog_contents(
      catalog_environment(
        [
          catalog_fixture("example", [], commands=[command]),
          catalog_fixture("other", [], commands=[another_command]),
        ],
        [],
        commands=[command, another_command],
      ),
      caps(),
    )
    is Err(DuplicateSelector("command")),
  )
}
