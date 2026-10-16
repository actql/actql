///|
fn command_publication_alias() -> CommandTargetAlias {
  {
    name: [{ value: "mail", quoted: false, }, { value: "send", quoted: false, }],
    target_ref: "connector://example/mailbox",
    command_ref: "command:mail.send.v1",
    installation_binding_cid: "sha256:" + "d".repeat(64),
    installation_owner_cid: "sha256:" + "e".repeat(64),
  }
}

///|
fn command_publication_limits() -> @contract.Limits {
  { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, }
}

///|
fn command_publication_bind(
  mode : String,
  aliases? : Array[CommandTargetAlias] = [command_publication_alias()],
) -> CommandTargetPublication {
  bind_command_target_publication(
    @environment.reference_contents(command_publication_references(mode)),
    aliases,
    command_publication_limits(),
    10000,
  ).unwrap()
}

///|
test "Command publication retains original declared modes Catalog and installation identity" {
  for
    (mode, expected) in [
      ("installation", @environment.Installation),
      ("identifier", @environment.Identifier),
    ] {
    let catalogs = @environment.reference_contents(
      command_publication_references(mode),
    )
    let publication = bind_command_target_publication(
      catalogs,
      [command_publication_alias()],
      command_publication_limits(),
      10000,
    ).unwrap()
    let selected = resolve_command_target_binding(
      publication,
      command_publication_alias().name,
      100,
    ).unwrap()
    let binding = resolved_command_target_binding(selected).unwrap()
    let target = @environment.published_command_binding_target(binding)
    assert_true(
      physical_equal(resolved_command_target_contract(selected), target),
    )
    assert_eq(@environment.published_command_binding_mode(binding), expected)
    assert_eq(
      resolved_command_target(selected),
      (
        command_publication_alias().target_ref,
        command_publication_alias().command_ref,
      ),
    )
    assert_true(
      physical_equal(command_target_publication_catalogs(publication), catalogs),
    )
    assert_true(
      physical_equal(
        @environment.command_target_catalog(target),
        @environment.catalog_at(catalogs, 0).unwrap(),
      ),
    )
    assert_true(
      physical_equal(
        command_target_publication_environment(publication),
        @environment.member_environment(
          @environment.command_target_member(target),
        ),
      ),
    )
    assert_eq(
      resolved_command_target_identity(selected),
      (
        @environment.cid(command_target_publication_environment(publication)),
        @environment.command_target_cid(target),
        command_publication_alias().installation_binding_cid,
        command_publication_alias().installation_owner_cid,
      ),
    )
    let concrete = resolve_concrete_command_target_binding(
      publication,
      command_publication_alias().target_ref,
      command_publication_alias().command_ref,
      1000,
    ).unwrap()
    assert_true(
      physical_equal(
        resolved_command_target_binding(concrete).unwrap(),
        binding,
      ),
    )
  }
}

///|
test "Command publication copies mutable alias paths and does not infer a suffix target" {
  let original = command_publication_alias()
  let publication = command_publication_bind("installation", aliases=[original])
  original.name[0] = { value: "changed", quoted: false, }
  let selected = resolve_command_target_binding(
    publication,
    command_publication_alias().name,
    100,
  ).unwrap()
  assert_eq(
    resolved_command_target(selected).1,
    command_publication_alias().command_ref,
  )
  assert_eq(
    resolve_command_target_binding(
      publication,
      [{ value: "send", quoted: false, }],
      100,
    ).unwrap_err(),
    UnresolvedTarget,
  )
  assert_eq(
    resolve_command_target_binding(publication, original.name, 100).unwrap_err(),
    UnresolvedTarget,
  )
  assert_true(
    resolve_concrete_command_target_binding(
      publication,
      "connector://other/mailbox",
      command_publication_alias().command_ref,
      1000,
    )
    is Err(UnresolvedTarget),
  )
  assert_true(
    resolve_concrete_command_target_binding(
      publication,
      command_publication_alias().target_ref,
      "command:other.send.v1",
      1000,
    )
    is Err(UnresolvedTarget),
  )
}

///|
test "Command publication rejects logical ambiguity and conflicting concrete installation originals" {
  let first = command_publication_alias()
  let other = { ..first, installation_owner_cid: "sha256:" + "f".repeat(64), }
  let publication = command_publication_bind("installation", aliases=[
    first, other,
  ])
  assert_eq(
    resolve_command_target_binding(publication, first.name, 100).unwrap_err(),
    AmbiguousTarget,
  )
  assert_eq(
    resolve_concrete_command_target_binding(
      publication,
      first.target_ref,
      first.command_ref,
      1000,
    ).unwrap_err(),
    AmbiguousTarget,
  )
  let same = command_publication_bind("installation", aliases=[
    first,
    { ..first, name: [{ value: "other", quoted: false, }], },
  ])
  assert_true(
    resolve_concrete_command_target_binding(
      same,
      first.target_ref,
      first.command_ref,
      1000,
    )
    is Ok(_),
  )
}

///|
test "Command publication admits every alias and retains legacy field selection without a default" {
  let catalogs = @environment.reference_contents(
    command_publication_references("installation"),
  )
  let first = command_publication_alias()
  let missing = {
    ..first,
    name: [{ value: "unused", quoted: false, }],
    command_ref: "command:missing.v1",
  }
  assert_eq(
    bind_command_target_publication(
      catalogs,
      [first, missing],
      command_publication_limits(),
      10000,
    ).unwrap_err(),
    UnresolvedCommand,
  )
  let legacy = @environment.reference_contents(
    command_publication_references("legacy-field"),
  )
  let legacy_publication = bind_command_target_publication(
    legacy,
    [first],
    command_publication_limits(),
    10000,
  ).unwrap()
  let legacy_selection = resolve_command_target_binding(
    legacy_publication,
    first.name,
    100,
  ).unwrap()
  assert_true(resolved_command_target_binding(legacy_selection) is None)
  let legacy_contract = resolved_command_target_contract(legacy_selection)
  assert_eq(@environment.command_target_id(legacy_contract), first.command_ref)
  assert_true(
    physical_equal(
      @environment.command_target_catalog(legacy_contract),
      @environment.catalog_at(legacy, 0).unwrap(),
    ),
  )
  for
    invalid in [
      { ..first, target_ref: "mailbox", },
      { ..first, command_ref: "", },
      { ..first, installation_binding_cid: "not-a-cid", },
      { ..first, installation_owner_cid: "sha256:" + "e".repeat(63), },
      { ..first, name: [], },
    ] {
    assert_eq(
      bind_command_target_publication(
        catalogs,
        [invalid],
        command_publication_limits(),
        10000,
      ).unwrap_err(),
      InvalidPublication,
    )
  }
}

///|
test "Command publication shares work and checked domain budgets across every occurrence" {
  let catalogs = @environment.reference_contents(
    command_publication_references("identifier"),
  )
  let aliases = [
    command_publication_alias(),
    {
      ..command_publication_alias(),
      name: [{ value: "other", quoted: false, }],
    },
  ]
  let publication = bind_command_target_publication(
    catalogs,
    aliases,
    command_publication_limits(),
    10000,
  ).unwrap()
  let exact = command_target_publication_work(publication)
  let (nodes, text) = command_target_publication_usage(publication)
  let limits : @contract.Limits = {
    max_nodes: nodes,
    max_text_bytes: text,
    max_depth: 10,
  }
  assert_true(
    bind_command_target_publication(catalogs, aliases, limits, exact) is Ok(_),
  )
  assert_eq(
    bind_command_target_publication(catalogs, aliases, limits, exact - 1).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    bind_command_target_publication(
      catalogs,
      aliases,
      { ..limits, max_nodes: nodes - 1, },
      exact,
    ).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    bind_command_target_publication(
      catalogs,
      aliases,
      { ..limits, max_text_bytes: text - 1, },
      exact,
    ).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    resolve_command_target_binding(publication, aliases[0].name, 0).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    resolve_concrete_command_target_binding(
      publication,
      aliases[0].target_ref,
      aliases[0].command_ref,
      0,
    ).unwrap_err(),
    WorkLimit,
  )
  assert_true(
    bind_command_target_publication(
      catalogs,
      [],
      { max_nodes: 0, max_depth: 0, max_text_bytes: 0, },
      0,
    )
    is Ok(_),
  )
}

///|
test "equal Command declaration identities do not merge separate original environments" {
  let first = command_publication_bind("installation")
  let second = command_publication_bind("installation")
  let a = resolve_command_target_binding(
    first,
    command_publication_alias().name,
    100,
  ).unwrap()
  let b = resolve_command_target_binding(
    second,
    command_publication_alias().name,
    100,
  ).unwrap()
  assert_eq(
    resolved_command_target_identity(a),
    resolved_command_target_identity(b),
  )
  assert_true(
    !physical_equal(
      command_target_publication_environment(first),
      command_target_publication_environment(second),
    ),
  )
  assert_true(
    !physical_equal(
      resolved_command_target_binding(a).unwrap(),
      resolved_command_target_binding(b).unwrap(),
    ),
  )
}

///|
test "legacy Command publication budget and concrete lookup keep the original ResourceRef contract" {
  let publication = command_publication_bind("legacy-field")
  let target_alias = command_publication_alias()
  let selected = resolve_command_target_binding(publication, target_alias.name, 100).unwrap()
  let concrete = resolve_concrete_command_target_binding(
    publication,
    target_alias.target_ref,
    target_alias.command_ref,
    1000,
  ).unwrap()
  assert_true(resolved_command_target_binding(selected) is None)
  assert_true(resolved_command_target_binding(concrete) is None)
  assert_true(
    physical_equal(
      resolved_command_target_contract(selected),
      resolved_command_target_contract(concrete),
    ),
  )
  let (nodes, text) = command_target_publication_usage(publication)
  assert_eq((nodes, text), (0, 0))
  let catalogs = command_target_publication_catalogs(publication)
  let exact = command_target_publication_work(publication)
  let limits : @contract.Limits = {
    max_nodes: 0,
    max_depth: 0,
    max_text_bytes: 0,
  }
  assert_true(
    bind_command_target_publication(catalogs, [target_alias], limits, exact) is Ok(_),
  )
  assert_true(
    bind_command_target_publication(catalogs, [target_alias], limits, exact - 1)
    is Err(WorkLimit),
  )
  let copy = command_publication_bind("legacy-field")
  let other = resolve_command_target_binding(copy, target_alias.name, 100).unwrap()
  assert_eq(
    resolved_command_target_identity(selected),
    resolved_command_target_identity(other),
  )
  assert_true(
    !physical_equal(
      @environment.member_environment(
        @environment.command_target_member(
          resolved_command_target_contract(selected),
        ),
      ),
      @environment.member_environment(
        @environment.command_target_member(
          resolved_command_target_contract(other),
        ),
      ),
    ),
  )
}
