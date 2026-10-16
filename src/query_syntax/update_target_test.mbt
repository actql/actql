///|
test "logical UPDATE retains static qualified names and optional exact Mapping" {
  let suffix = " FROM RESULT updates ID id SET (Name = notes)"
  for
    text in [
      "salesforce.Account", "salesforce.Account MAPPING `mapping:crm.account.v1`",
    ] {
    let query = parse_query(
      "FROM t |> RESULT updates |> EFFECT UPDATE " + text + suffix,
      query_limits(),
    ).unwrap()
    let clause = terminal_effect(query).unwrap()
    guard clause.target is LogicalTarget(path) else { fail("logical target") }
    assert_eq(path, [
      { value: "salesforce", quoted: false, },
      { value: "Account", quoted: false, },
    ])
    assert_eq(
      clause.mapping.map(part => part.value),
      if text.contains("MAPPING") {
        Some("mapping:crm.account.v1")
      } else {
        None
      },
    )
  }
  let full = parse_query(
    "FROM t |> RESULT updates |> EFFECT UPDATE TARGET 'connector://crm/account' MAPPING `mapping:crm.account.v1`" +
    suffix,
    query_limits(),
  ).unwrap()
  guard terminal_effect(full).unwrap().target is ConcreteTarget(target) else {
    fail("concrete target")
  }
  assert_eq(target, "connector://crm/account")
}

///|
test "logical UPDATE cannot interpret rows expressions or URL strings as targets" {
  let prefix = "FROM t |> RESULT updates |> EFFECT UPDATE "
  let suffix = " FROM RESULT updates ID id SET (Name = notes)"
  for
    target in [
      "Account", "'salesforce.Account'", "@target", "(salesforce.Account)", "salesforce.Account + 1",
      "salesforce.Account()", "TARGET id MAPPING m", "TARGET 'connector://crm/account'",
    ] {
    assert_true(
      parse_query(prefix + target + suffix, query_limits()) is Err(_),
      msg=target,
    )
  }
  assert_true(
    parse_query(
      prefix + "salesforce.Account ID id SET (Name = notes)",
      query_limits(),
    )
    is Ok(_),
  )
}

///|
test "logical UPDATE target arrays retain parser custody" {
  let query = parse_query(
    "FROM t |> RESULT updates |> EFFECT UPDATE `Salesforce`.`Account` FROM RESULT updates ID id SET (Name = notes)",
    query_limits(),
  ).unwrap()
  guard terminal_effect(query).unwrap().target is LogicalTarget(path) else {
    fail("logical target")
  }
  path.clear()
  guard terminal_effect(query).unwrap().target is LogicalTarget(original) else {
    fail("logical target")
  }
  assert_eq(original, [
    { value: "Salesforce", quoted: true, },
    { value: "Account", quoted: true, },
  ])
}

///|
test "logical UPDATE keyword qualifiers do not become Effect or Table syntax" {
  let suffix = " FROM RESULT updates ID id SET (Name = notes)"
  for
    target in [
      "UPDATE.Account", "CREATE.Account", "TARGET.Account", "`UPDATE`.Account", "`CREATE`.Account",
      "`TARGET`.Account",
    ] {
    let query = parse_query(
      "FROM t |> RESULT updates |> EFFECT UPDATE " + target + suffix,
      query_limits(),
    ).unwrap()
    let clause = terminal_effect(query).unwrap()
    assert_eq(clause.name, None)
    guard clause.target is LogicalTarget(path) else {
      fail("logical qualifier")
    }
    assert_eq(path.length(), 2)
  }
  let named = parse_query(
    "FROM t |> RESULT updates |> EFFECT UPDATE UPDATE TARGET 'connector://crm/account' MAPPING m" +
    suffix,
    query_limits(),
  ).unwrap()
  assert_eq(
    terminal_effect(named).unwrap().name.map(name => name.value),
    Some("UPDATE"),
  )
}
