///|
fn target_original_quote(value : String) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(
    CLIENT_EFFECT_TARGET_ORIGINAL_ENVELOPE_MAX_BYTES,
    1,
    1,
  )
  @encode.string_value(writer, value)
  @encode.finish(writer)
}

///|
test "complete prepared original has a distinct bounded envelope without widening installation metadata" {
  let installation = "{\"cid\":\"sha256:9ee844e04eda0aa8f6e901a0fdc3fcd2694aa4bf94ad053b2308a5ae3ef4a2ca\",\"wire\":" +
    target_original_quote(target_original_installation_wire()) +
    "}"
  let material = "\"".repeat(60000)
  let original = "{\"preparedWire\":" +
    target_original_quote(material) +
    ",\"compiledPlanCid\":\"sha256:" +
    "a".repeat(64) +
    "\",\"installations\":[" +
    installation +
    "]}"
  assert_true(original.length() > 65536)
  assert_true(client_effect_target_prepared_original_shape(original))
  assert_true(
    client_effect_target_original_data_equal(original, " " + original),
  )
  assert_false(
    client_effect_target_prepared_original_shape(
      original.replace(
        old=target_original_quote(material),
        new=target_original_quote("a".repeat(262145)),
      ),
    ),
  )
  assert_false(
    client_effect_target_prepared_original_shape(
      original.replace(
        old="\"installations\":[",
        new="\"extra\":0,\"installations\":[",
      ),
    ),
  )
  assert_true(
    client_effect_target_original_envelope_capacity(2, index => {
      if index == 0 {
        material
      } else {
        target_original_installation_wire()
      }
    })
    is Some(_),
  )
  assert_true(
    client_effect_target_original_envelope_capacity(2, index => {
      if index == 0 {
        material
      } else {
        "a".repeat(65536)
      }
    })
    is None,
  )
  assert_false(
    client_effect_target_installations_shape(
      "[" + " ".repeat(65536) + installation + "]",
    ),
  )
}

///|
fn target_original_installation_wire() -> String {
  // Independent structural preimage, matching the pre-refactor Host Owner.
  let wire =
    #|{"binding_cid":"sha256:8888888888888888888888888888888888888888888888888888888888888888","connection":"fixture","connector_registration":"update_target_fixture","connector_revision":"update_target_fixture/0.1","continuation_binding":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","profile":{"continuation":"actql-installed-row-effect-continuation/0.1","continuationBinding":"binding_cid","dispatch":"actql-installed-row-effect-dispatch/0.1","recovery":"actql-installed-row-effect-recovery/0.1","source":"actql-installed-row-effect-source/0.1","targetCheck":"actql-installed-row-effect-check/0.1","unit":"actql-installed-row-effect-unit/0.1"},"runtime_bundle_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}
  wire
}

///|
fn target_original_installation_facts() -> Array[String] {
  [
    "sha256:" + "8".repeat(64),
    "fixture",
    "update_target_fixture",
    "update_target_fixture/0.1",
    "sha256:" + "e".repeat(64),
    "actql-installed-row-effect-continuation/0.1",
    "binding_cid",
    "actql-installed-row-effect-dispatch/0.1",
    "actql-installed-row-effect-recovery/0.1",
    "actql-installed-row-effect-source/0.1",
    "actql-installed-row-effect-check/0.1",
    "actql-installed-row-effect-unit/0.1",
    "sha256:" + "d".repeat(64),
  ]
}

///|
test "typed physical installation keeps independent canonical identity normalization and original raw bounds" {
  let facts = target_original_installation_facts()
  let (cid, wire, data) = issue_client_effect_target_installation_data(facts).unwrap()
  assert_eq(
    cid, "sha256:9ee844e04eda0aa8f6e901a0fdc3fcd2694aa4bf94ad053b2308a5ae3ef4a2ca",
  )
  assert_eq(wire, target_original_installation_wire())
  assert_eq(issue_client_effect_target_installation(wire).unwrap(), (cid, wire))
  facts[0] = "different"
  assert_eq(data.binding_cid, "sha256:" + "8".repeat(64))
  let unicode = target_original_installation_facts()
  unicode[1] = "e\u{0301}\r\n"
  assert_eq(
    issue_client_effect_target_installation_data(unicode).unwrap().1,
    target_original_installation_wire().replace(
      old="\"connection\":\"fixture\"",
      new="\"connection\":\"é\\r\\n\"",
    ),
  )
  assert_true(
    issue_client_effect_target_installation_data([]) is Err(InvalidMaterials),
  )
  let large = target_original_installation_facts()
  large[1] = "a".repeat(65536)
  assert_true(
    issue_client_effect_target_installation_data(large) is Err(InvalidMaterials),
  )
}

///|
test "same-call typed installation shares full current purpose Mapping and unchanged virtual wire bounds" {
  let (cid, _, data) = issue_client_effect_target_installation_data(
    target_original_installation_facts(),
  ).unwrap()
  let (prepared, _, _, _) = target_selection_fixture(owner_cid=cid)
  let (foreign, _, _, _) = target_selection_fixture()
  let original = client_effect_target_selection_original(prepared)[0]
  let compact =
    #|[{"update":true,"mappings":[{"target":"connector://crm/account","mappingRef":"mapping:crm.account.v1","mappingCid":"sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283","update":true}]}]
  assert_true(
    client_effect_target_selection_current_data(
      original,
      prepared,
      [data],
      compact,
    ),
  )
  assert_false(
    client_effect_target_selection_current_data(
      original,
      foreign,
      [data],
      compact,
    ),
  )
  assert_false(
    client_effect_target_selection_current_data(original, prepared, [], compact),
  )
  assert_false(
    client_effect_target_selection_current_data(
      original,
      prepared,
      [{ ..data, origin: Ref(0), }],
      compact,
    ),
  )
  for
    changed in [
      compact.replace(old="mapping:crm.account.v1", new="mapping:foreign"),
      compact.replace(old="\"update\":true", new="\"update\":false"),
      compact.replace(old="\"update\":true", new="\"store\":true"),
    ] {
    assert_false(
      client_effect_target_selection_current_data(
        original,
        prepared,
        [data],
        changed,
      ),
    )
  }
  let repeated = "[" +
    compact[1:compact.length() - 1].to_owned() +
    "," +
    compact[1:compact.length() - 1].to_owned() +
    "]"
  assert_false(
    client_effect_target_selection_current_data(
      original,
      prepared,
      [data, data],
      repeated,
    ),
  )
  let extra = data.observation_extra_bytes
  let full = compact.replace(
    old="{\"update\":true",
    new="{\"installation\":{\"cid\":\"" +
      cid +
      "\",\"wire\":" +
      target_original_quote(data.wire) +
      "},\"update\":true",
  )
  assert_eq(@utf8.encode(full).length(), @utf8.encode(compact).length() + extra)
  let pad = 65536 - @utf8.encode(full).length()
  assert_true(
    client_effect_target_selection_current_data(
      original,
      prepared,
      [data],
      compact + " ".repeat(pad),
    ),
  )
  assert_true(
    client_effect_target_selection_current(
      original,
      prepared,
      full + " ".repeat(pad),
    ),
  )
  assert_false(
    client_effect_target_selection_current_data(
      original,
      prepared,
      [data],
      compact + " ".repeat(pad + 1),
    ),
  )
  assert_false(
    client_effect_target_selection_current(
      original,
      prepared,
      full + " ".repeat(pad + 1),
    ),
  )
}

///|
test "virtual installation bytes preserve empty unrelated objects exactly at original limit" {
  let (cid, _, data) = issue_client_effect_target_installation_data(
    target_original_installation_facts(),
  ).unwrap()
  let unrelated_facts = target_original_installation_facts()
  unrelated_facts[1] = "unrelated"
  let (unrelated_cid, _, unrelated) = issue_client_effect_target_installation_data(
    unrelated_facts,
  ).unwrap()
  let (prepared, _, _, _) = target_selection_fixture(owner_cid=cid)
  let original = client_effect_target_selection_original(prepared)[0]
  let selected_observation =
    #|{"update":true,"mappings":[{"target":"connector://crm/account","mappingRef":"mapping:crm.account.v1","mappingCid":"sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283","update":true}]}
  let compact = "[" + selected_observation + ",{}]"
  let full_member = selected_observation.replace(
    old="{\"update\":true",
    new="{\"installation\":{\"cid\":\"" +
      cid +
      "\",\"wire\":" +
      target_original_quote(data.wire) +
      "},\"update\":true",
  )
  let full = "[" +
    full_member +
    ", {\"installation\":{\"cid\":\"" +
    unrelated_cid +
    "\",\"wire\":" +
    target_original_quote(unrelated.wire) +
    "}}]"
  // The unrelated installation is valid DATA but has no selected occurrence,
  // so the existing raw path lawfully skips its absent purpose and Mapping.
  // Keep the one space in BOTH representations for exact enclosing bytes.
  let compact = compact.replace(old=",{}]", new=", {}]")
  assert_eq(
    @utf8.encode(full).length(),
    @utf8.encode(compact).length() +
    data.observation_extra_bytes +
    unrelated.observation_extra_bytes -
    1,
  )
  let pad = 65536 - @utf8.encode(full).length()
  for over in [0, 1] {
    let padding = " ".repeat(pad + over)
    assert_eq(
      client_effect_target_selection_current(original, prepared, full + padding),
      over == 0,
    )
    assert_eq(
      client_effect_target_selection_current_data(
        original,
        prepared,
        [data, unrelated],
        compact + padding,
      ),
      over == 0,
    )
  }
}

///|
test "admitted installation DATA equality borrows complete ordered cid and wire strings" {
  let cid = "sha256:9ee844e04eda0aa8f6e901a0fdc3fcd2694aa4bf94ad053b2308a5ae3ef4a2ca"
  let wire = target_original_installation_wire()
  assert_true(
    client_effect_target_installations_data_equal([cid, wire], [cid, wire]),
  )
  assert_false(
    client_effect_target_installations_data_equal([cid, wire], [cid, wire + " "]),
  )
  assert_false(
    client_effect_target_installations_data_equal([cid, wire], [
      "sha256:" + "a".repeat(64),
      wire,
    ]),
  )
  assert_false(client_effect_target_installations_data_equal([], []))
  assert_false(client_effect_target_installations_data_equal([cid], [cid]))
  assert_false(
    client_effect_target_installations_data_equal([cid, wire], [
      cid, wire, cid, wire,
    ]),
  )
  assert_false(
    client_effect_target_installations_data_equal([wire, cid], [cid, wire]),
  )
  let too_large = "x".repeat(65537)
  assert_false(
    client_effect_target_installations_data_equal([cid, too_large], [
      cid, too_large,
    ]),
  )
  let aggregate = [cid, "x".repeat(32768), cid, "x".repeat(32768)]
  assert_false(
    client_effect_target_installations_data_equal(aggregate, aggregate),
  )
  assert_false(
    client_effect_target_installations_data_equal(
      Array::make(2050, cid),
      Array::make(2050, cid),
    ),
  )
}

///|
test "original DATA Owner retains independent installation bytes CID and NFC without newline rewriting" {
  let wire = target_original_installation_wire()
  // Node crypto SHA-256 over the independently authored literal, not an
  // expectation regenerated by the product issuer.
  assert_eq(
    issue_client_effect_target_installation(wire).unwrap(),
    (
      "sha256:9ee844e04eda0aa8f6e901a0fdc3fcd2694aa4bf94ad053b2308a5ae3ef4a2ca",
      wire,
    ),
  )
  let old = wire.replace(
    old="sha256:" + "8".repeat(64),
    new="sha256:" + "c".repeat(64),
  )
  assert_eq(
    issue_client_effect_target_installation(old).unwrap().0,
    "sha256:82b29228f604437218a51df3d6504e813219649a14e80c4b7c24f505eea6c1e9",
  )
  let unicode = wire.replace(
    old="\"connection\":\"fixture\"",
    new="\"connection\":\"e\\u0301\\r\\n\"",
  )
  assert_eq(
    issue_client_effect_target_installation(unicode).unwrap().1,
    wire.replace(
      old="\"connection\":\"fixture\"",
      new="\"connection\":\"é\\r\\n\"",
    ),
  )
  assert_true(
    issue_client_effect_target_installation("{}") is Err(InvalidMaterials),
  )
  assert_true(
    issue_client_effect_target_installation(
      wire.replace(old="\"connection\":\"fixture\"", new="\"connection\":null"),
    )
    is Err(InvalidMaterials),
  )
}

///|
test "original DATA Owner checks opaque prepared occurrence installation generation and Run together" {
  let installation_cid = "sha256:9ee844e04eda0aa8f6e901a0fdc3fcd2694aa4bf94ad053b2308a5ae3ef4a2ca"
  let (prepared, allowed, definition, _) = target_selection_fixture(
    owner_cid=installation_cid,
  )
  let (foreign, _, foreign_run, _) = target_selection_fixture()
  let original = client_effect_target_selection_original(prepared)[0]
  assert_true(
    client_effect_target_selection_matches_prepared(original, prepared),
  )
  assert_false(
    client_effect_target_selection_matches_prepared(original, foreign),
  )
  assert_true(
    client_effect_target_selection_matches_run(original, prepared, definition),
  )
  assert_false(
    client_effect_target_selection_matches_run(
      original,
      prepared,
      client_effect_compilation_compiled_plan(allowed.compilation),
    ),
  )
  assert_false(
    client_effect_target_selection_matches_run(original, prepared, foreign_run),
  )
  let wire = target_original_installation_wire()
  let installation = "{\"cid\":\"" +
    installation_cid +
    "\",\"wire\":" +
    target_original_quote(wire) +
    "}"
  let mappings =
    #|[{"target":"connector://crm/account","mappingRef":"mapping:crm.account.v1","mappingCid":"sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283","update":true}]
  let observations = "[{\"installation\":" +
    installation +
    ",\"update\":true,\"mappings\":" +
    mappings +
    "}]"
  assert_true(
    client_effect_target_selection_current(original, prepared, observations),
  )
  assert_false(
    client_effect_target_selection_current(original, foreign, observations),
  )
  for
    changed in [
      observations.replace(old=installation_cid, new="sha256:" + "f".repeat(64)),
      observations.replace(
        old="mapping:crm.account.v1",
        new="mapping:crm.account.v2",
      ),
      observations.replace(
        old="\\\"continuation_binding\\\":\\\"sha256:" + "e".repeat(64),
        new="\\\"continuation_binding\\\":\\\"sha256:" + "f".repeat(64),
      ),
      observations.replace(old="\"update\":true", new="\"update\":false"),
    ] {
    assert_false(
      client_effect_target_selection_current(original, prepared, changed),
    )
  }
  let members =
    #|[{"stage_index":0,"effect_id":"save","target_ref":"connector://crm/account","mapping_ref":"mapping:crm.account.v1","mapping_cid":"sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283"}]
  assert_true(
    client_effect_target_selection_members_current(original, prepared, members),
  )
  assert_false(
    client_effect_target_selection_members_current(original, foreign, members),
  )
  assert_false(
    client_effect_target_selection_members_current(
      original,
      prepared,
      members.replace(old="\"stage_index\":0", new="\"stage_index\":1"),
    ),
  )
  let saved = "{\"preparedWire\":\"prepared\",\"compiledPlanCid\":\"sha256:" +
    "a".repeat(64) +
    "\",\"installations\":[" +
    installation +
    "]}"
  assert_true(client_effect_target_prepared_original_shape(saved))
  assert_false(
    client_effect_target_prepared_original_shape(
      saved.replace(old=installation_cid, new="sha256:" + "f".repeat(64)),
    ),
  )
  assert_true(client_effect_target_original_data_equal(saved, " " + saved))
  assert_false(
    client_effect_target_original_data_equal(
      saved,
      saved.replace(old="prepared", new="substituted"),
    ),
  )
}
