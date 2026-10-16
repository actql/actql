///|
fn store_source_environment(kind : String) -> @check.CheckEnvironment {
  let (mappings, _) = store_target_fixture(kind)
  @check.checking_environment(
    @environment.mapping_shape_environment(mappings),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
}

///|
fn store_source_publication(environment : @check.CheckEnvironment) -> String {
  "{\"environmentCid\":\"" +
  @check.checking_environment_cid(environment) +
  "\",\"aliases\":[],\"storeTargets\":[{\"name\":\"storage.archive\",\"targetRef\":\"connector://storage/archive\",\"installationBindingCid\":\"sha256:" +
  "d".repeat(64) +
  "\",\"installationOwnerCid\":\"sha256:" +
  "e".repeat(64) +
  "\"}]}"
}

///|
test "Host STORE publication binds original Catalog Mapping and installation" {
  let environment = store_source_environment("object")
  let wire = store_source_publication(environment)
  let publication = @source_publication.published_store_targets(
      environment, wire,
    )
    .unwrap()
    .unwrap()
  let selected = resolve_store_target_binding(
    publication,
    store_target_alias().name,
    100,
  ).unwrap()
  assert_eq(
    resolved_store_target(selected),
    ("connector://storage/archive", "mapping:fixture.archive.v1"),
  )
  assert_true(
    physical_equal(
      store_target_publication_environment(publication),
      @check.checking_environment_wire(environment),
    ),
  )
  let command = @environment.store_command_target(
    resolved_store_target_command(selected).unwrap(),
  )
  assert_eq(
    @environment.command_target_id(command),
    "command:fixture.upload.v1",
  )
  assert_eq(
    resolved_store_target_identity(selected),
    (
      @check.checking_environment_cid(environment),
      "sha256:95de148023f83b5ef6a9a4f0e6453ef5a68b7bae5867d58b10feab0e6309d516",
      store_target_alias().installation_binding_cid,
      store_target_alias().installation_owner_cid,
    ),
  )
  // Actual source-context caller admits the complete section. No Source I/O,
  // Reference issuance or Effect execution occurs at this metadata boundary.
  assert_true(
    @source_publication.bind_published_query_context(environment, wire, None)
    is Ok(_),
  )
}

///|
test "Host STORE publication preserves canonical relation-store and ambiguity" {
  let environment = store_source_environment("relation")
  let publication = @source_publication.published_store_targets(
      environment,
      store_source_publication(environment),
    )
    .unwrap()
    .unwrap()
  let selected = resolve_store_target_binding(
    publication,
    store_target_alias().name,
    100,
  ).unwrap()
  assert_true(resolved_store_target_command(selected) is None)
  let environment = store_source_environment("ambiguous")
  let publication = @source_publication.published_store_targets(
      environment,
      store_source_publication(environment),
    )
    .unwrap()
    .unwrap()
  assert_eq(
    resolve_store_target_binding(publication, store_target_alias().name, 100).unwrap_err(),
    AmbiguousMapping,
  )
}

///|
test "Host STORE publication refuses malformed and foreign section before context" {
  let environment = store_source_environment("object")
  let wire = store_source_publication(environment)
  let name = "\"storage.archive\""
  for
    changed in [
      wire.replace(old="\"storeTargets\":[", new="\"unknownTargets\":["),
      wire.replace(old=name, new="null"),
      wire.replace(old=name, new="\"bad..path\""),
      wire.replace(old="\"targetRef\":", new="\"unknown\":true,\"targetRef\":"),
      wire.replace(
        old=store_target_alias().installation_binding_cid,
        new="not-a-cid",
      ),
      wire.replace(
        old=store_target_alias().installation_owner_cid,
        new="not-a-cid",
      ),
      wire.replace(
        old=@check.checking_environment_cid(environment),
        new="sha256:" + "a".repeat(64),
      ),
    ] {
    assert_true(
      @source_publication.published_store_targets(environment, changed)
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
  let prefix = "{\"environmentCid\":\"" +
    @check.checking_environment_cid(environment) +
    "\",\"aliases\":[],\"storeTargets\":"
  for section in ["null", "{}", "[null]", "[{}]"] {
    let changed = prefix + section + "}"
    assert_true(
      @source_publication.published_store_targets(environment, changed)
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
}

///|
test "Host STORE publication cannot hide invalid Command behind a read context" {
  let environment = store_source_environment("foreignCatalog")
  let wire = store_source_publication(environment)
  assert_true(
    @source_publication.published_store_targets(environment, wire) is Err(_),
  )
  assert_true(
    @source_publication.bind_published_query_context(environment, wire, None)
    is Err(_),
  )
}

///|
test "absent or empty Host STORE publication preserves old original inputs" {
  let environment = store_source_environment("foreignCatalog")
  let prefix = "{\"environmentCid\":\"" +
    @check.checking_environment_cid(environment) +
    "\",\"aliases\":[]"
  for wire in [prefix + "}", prefix + ",\"storeTargets\":[]}"] {
    assert_true(
      @source_publication.published_store_targets(environment, wire).unwrap()
      is None,
    )
    assert_true(
      @source_publication.published_update_targets(environment, wire).unwrap()
      is None,
    )
    assert_true(
      @source_publication.bind_published_query_context(environment, wire, None)
      is Ok(_),
    )
  }
}
