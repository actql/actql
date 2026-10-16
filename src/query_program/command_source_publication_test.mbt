///|
fn command_source_environment(mode : String) -> @check.CheckEnvironment {
  let catalogs = @environment.reference_contents(
    command_publication_references(mode),
  )
  @check.checking_environment(
    @environment.contract_registry_environment(
      @environment.catalog_registry(catalogs),
    ),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
}

///|
fn command_source_publication(environment : @check.CheckEnvironment) -> String {
  "{\"environmentCid\":\"" +
  @check.checking_environment_cid(environment) +
  "\",\"aliases\":[],\"commandTargets\":[{\"name\":\"mail.send\",\"targetRef\":\"connector://example/mailbox\",\"commandRef\":\"command:mail.send.v1\",\"installationBindingCid\":\"sha256:" +
  "d".repeat(64) +
  "\",\"installationOwnerCid\":\"sha256:" +
  "e".repeat(64) +
  "\"}]}"
}

///|
test "Host Command publication keeps exact fixed or identifier declaration and installation" {
  for
    (mode, expected) in [
      ("installation", @environment.Installation),
      ("identifier", @environment.Identifier),
    ] {
    let environment = command_source_environment(mode)
    let wire = command_source_publication(environment)
    let publication = @source_publication.published_command_targets(
        environment, wire,
      )
      .unwrap()
      .unwrap()
    let selected = resolve_command_target_binding(
      publication,
      command_publication_alias().name,
      100,
    ).unwrap()
    assert_eq(
      @environment.published_command_binding_mode(
        resolved_command_target_binding(selected),
      ),
      expected,
    )
    assert_true(
      physical_equal(
        command_target_publication_environment(publication),
        @check.checking_environment_wire(environment),
      ),
    )
    assert_eq(
      resolved_command_target(selected),
      (
        command_publication_alias().target_ref,
        command_publication_alias().command_ref,
      ),
    )
    assert_eq(
      resolved_command_target_identity(selected).2,
      command_publication_alias().installation_binding_cid,
    )
    assert_eq(
      resolved_command_target_identity(selected).3,
      command_publication_alias().installation_owner_cid,
    )
    assert_true(
      @source_publication.bind_published_query_context(environment, wire, None)
      is Ok(_),
    )
    assert_true(
      @source_publication.published_store_targets(environment, wire).unwrap()
      is None,
    )
    assert_true(
      @source_publication.published_update_targets(environment, wire).unwrap()
      is None,
    )
  }
}

///|
test "Host Command section is closed required and refuses malformed unused entries before read context" {
  let environment = command_source_environment("installation")
  let wire = command_source_publication(environment)
  for
    changed in [
      wire.replace(
        old="\"commandTargets\":[",
        new="\"commandTargets\":null,\"unexpected\":[",
      ),
      wire.replace(old="\"commandRef\":\"command:mail.send.v1\",", new=""),
      wire.replace(
        old="\"commandRef\":\"command:mail.send.v1\"",
        new="\"commandRef\":null",
      ),
      wire.replace(
        old="\"commandRef\":\"command:mail.send.v1\"",
        new="\"commandRef\":\"command:missing.v1\"",
      ),
      wire.replace(
        old="\"name\":\"mail.send\"",
        new="\"name\":\"mail.send\",\"mappingRef\":\"mapping:invented\"",
      ),
      wire.replace(
        old="\"installationOwnerCid\":\"sha256:" + "e".repeat(64) + "\"",
        new="\"installationOwnerCid\":\"not-a-cid\"",
      ),
      wire.replace(
        old="\"commandTargets\":[",
        new="\"commandTargets\":{} ,\"extra\":[",
      ),
    ] {
    assert_true(
      @source_publication.published_command_targets(environment, changed)
      is Err(_),
    )
    assert_true(
      @source_publication.bind_published_query_context(
        environment,
        changed,
        None,
      )
      is Err(_),
    )
  }
  let second = wire
    .replace(old="\"name\":\"mail.send\"", new="\"name\":\"unused\"")
    .replace(old="command:mail.send.v1", new="command:missing.v1")
  let entry = second.split("\"commandTargets\":[")[1].replace(old="]}", new="")
  let mixed = wire.replace(old="]}", new="," + entry + "]}")
  assert_true(
    @source_publication.published_command_targets(environment, mixed) is Err(_),
  )
  assert_true(
    @source_publication.bind_published_query_context(environment, mixed, None)
    is Err(_),
  )
}

///|
test "Host Command publication refuses foreign environment and legacy declaration default" {
  let environment = command_source_environment("installation")
  let wire = command_source_publication(environment)
  let changed = wire.replace(
    old=@check.checking_environment_cid(environment),
    new="sha256:" + "a".repeat(64),
  )
  assert_true(
    @source_publication.published_command_targets(environment, changed)
    is Err(_),
  )
  assert_true(
    @source_publication.bind_published_query_context(environment, changed, None)
    is Err(_),
  )
  let legacy = command_source_environment("legacy-field")
  let legacy_wire = command_source_publication(legacy)
  assert_true(
    @source_publication.published_command_targets(legacy, legacy_wire) is Err(_),
  )
  assert_true(
    @source_publication.bind_published_query_context(legacy, legacy_wire, None)
    is Err(_),
  )
}

///|
test "absent and empty Host Command sections preserve original read and STORE context admission" {
  let environment = command_source_environment("installation")
  let prefix = "{\"environmentCid\":\"" +
    @check.checking_environment_cid(environment) +
    "\",\"aliases\":[]"
  for suffix in ["}", ",\"commandTargets\":[]}"] {
    let wire = prefix + suffix
    assert_true(
      @source_publication.published_command_targets(environment, wire).unwrap()
      is None,
    )
    assert_true(
      @source_publication.bind_published_query_context(environment, wire, None)
      is Ok(_),
    )
  }
  let store = store_source_environment("object")
  let original = store_source_publication(store)
  let with_empty = original.replace(
    old="\"aliases\":[]",
    new="\"aliases\":[],\"commandTargets\":[]",
  )
  assert_true(
    @source_publication.published_command_targets(store, with_empty).unwrap()
    is None,
  )
  assert_true(
    @source_publication.published_store_targets(store, with_empty).unwrap()
    is Some(_),
  )
  assert_true(
    @source_publication.bind_published_query_context(store, with_empty, None)
    is Ok(_),
  )
}
