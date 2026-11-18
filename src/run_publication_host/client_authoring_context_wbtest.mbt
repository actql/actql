///|
test "Local authoring sidecar keeps original grammar metadata outside semantics" {
  let document = local_normalization_document
    .replace(
      old="\"id\":\"local.normalization\"",
      new="\"id\":\"local.normalization\",\"meta\":{\"note\":\"root\"}",
    )
    .replace(
      old="\"id\":\"source\"",
      new="\"id\":\"source\",\"meta\":{\"note\":\"stage\"}",
    )
    .replace(
      old="\"view\":\"v\"",
      new="\"view\":\"v\",\"meta\":{\"note\":\"input\"}",
    )
    .replace(
      old="\"as\":\"derived\"",
      new="\"as\":\"derived\",\"meta\":{\"note\":\"step\"}",
    )
  let original = local_normalization_fixture()
  let owner = local_normalization_fixture(document~)
  assert_eq(prepared_client_identity(owner), prepared_client_identity(original))
  let value = issue_prepared_client_authoring_context(owner, 65536, 4096, 64).unwrap()
  // Independently assembled grammar targets and canonical preimage; neither
  // the annotations nor their expectation are obtained from the new issuer.
  let annotations =
    #|[{"meta":{"note":"root"},"target":{"kind":"program","name":"local.normalization","source_path":"$"}},{"meta":{"note":"stage"},"target":{"kind":"stage","name":"source","source_path":"$[\"stages\"][0]"}},{"meta":{"note":"input"},"target":{"kind":"input","name":"table","source_path":"$[\"stages\"][0][\"inputs\"][\"table\"]"}},{"meta":{"note":"step"},"target":{"kind":"step","name":"derived","source_path":"$[\"stages\"][2][\"steps\"][0]"}}]
  let cid = prepared_client_identity(original).program_definition_cid
  let preimage = "{\"annotations\":" +
    annotations +
    ",\"program_definition_cid\":\"" +
    cid +
    "\",\"version\":\"actql-authoring-context/0.1\"}"
  let identity = "sha256:" + @sha.hex(@utf8.encode(preimage))
  let expected = "{\"annotations\":" +
    annotations +
    ",\"authoring_context_cid\":\"" +
    identity +
    "\",\"program_definition_cid\":\"" +
    cid +
    "\",\"version\":\"actql-authoring-context/0.1\"}"
  assert_eq(@publication.run_evidence_value_json(value), expected)
  assert_eq(@publication.run_evidence_value_identity(value), identity)
  let changed = local_normalization_fixture(
    document=document.replace(old="root", new="changed"),
  )
  assert_eq(prepared_client_identity(owner), prepared_client_identity(changed))
  assert_true(
    @publication.run_evidence_value_identity(
      issue_prepared_client_authoring_context(changed, 65536, 4096, 64).unwrap(),
    ) !=
    identity,
  )
}

///|
test "Local authoring sidecar does not extract business meta or truncate annotations" {
  let document = local_normalization_document
    .replace(old="\"value\":\"id + 1\"", new="\"meta\":\"id + 1\"")
    .replace(old="\"id\",\"value\"", new="\"id\",\"meta\"")
    .replace(old="value * 2 - 1", new="meta * 2 - 1")
  let owner = local_normalization_fixture(document~)
  let value = issue_prepared_client_authoring_context(owner, 65536, 4096, 64).unwrap()
  let wire = @publication.run_evidence_value_json(value)
  assert_true(wire.contains("\"annotations\":[]"))
  assert_true(!wire.contains("\"meta\""))
  assert_true(
    issue_prepared_client_authoring_context(owner, 1, 4096, 64) is Err(_),
  )
  assert_true(
    issue_prepared_client_authoring_context(owner, 65536, 1, 64) is Err(_),
  )
}

///|
test "retained authoring preparation measures and finishes the same original once" {
  let document = local_normalization_document.replace(
    old="\"id\":\"local.normalization\"",
    new="\"id\":\"local.normalization\",\"meta\":{\"note\":\"n\\u0303\\n\\ud83d\\ude00\"}",
  )
  let owner = local_normalization_fixture(document~)
  let preparation = prepare_client_authoring_context(owner, 65536, 4096, 64).unwrap()
  let geometry = measure_prepared_client_authoring_context(preparation).unwrap()
  let actual = finish_prepared_client_authoring_context(preparation).unwrap()
  let repeated = finish_prepared_client_authoring_context(preparation).unwrap()
  assert_true(physical_equal(actual, repeated))
  assert_true(preparation.items is None && preparation.writer is None)
  let annotations =
    #|[{"meta":{"note":"ñ\n😀"},"target":{"kind":"program","name":"local.normalization","source_path":"$"}}]
  let definition = prepared_client_identity(owner).program_definition_cid
  let body = "{\"annotations\":" +
    annotations +
    ",\"program_definition_cid\":\"" +
    definition +
    "\",\"version\":\"actql-authoring-context/0.1\"}"
  let identity = "sha256:" + @sha.hex(@utf8.encode(body))
  let expected = "{\"annotations\":" +
    annotations +
    ",\"authoring_context_cid\":\"" +
    identity +
    "\",\"program_definition_cid\":\"" +
    definition +
    "\",\"version\":\"actql-authoring-context/0.1\"}"
  assert_eq(@publication.run_evidence_value_json(actual), expected)
  assert_eq(@publication.run_evidence_value_identity(actual), identity)
  assert_eq(geometry.body.bytes, @utf8.encode(body).length())
  assert_eq(geometry.complete.bytes, @utf8.encode(expected).length())
  assert_true(
    @publication.run_evidence_value_fits(
      actual,
      geometry.complete.bytes,
      geometry.complete.nodes,
      geometry.complete.depth,
    ),
  )
  assert_true(
    !@publication.run_evidence_value_fits(
      actual,
      geometry.complete.bytes - 1,
      geometry.complete.nodes,
      geometry.complete.depth,
    ),
  )
  assert_true(
    !@publication.run_evidence_value_fits(
      actual,
      geometry.complete.bytes,
      geometry.complete.nodes - 1,
      geometry.complete.depth,
    ),
  )
  assert_true(
    !@publication.run_evidence_value_fits(
      actual,
      geometry.complete.bytes,
      geometry.complete.nodes,
      geometry.complete.depth - 1,
    ),
  )
}

///|
test "retained authoring constructor keeps its exact complete-wire refusal" {
  let owner = local_normalization_fixture()
  let generous = prepare_client_authoring_context(owner, 65536, 4096, 64).unwrap()
  let geometry = measure_prepared_client_authoring_context(generous).unwrap()
  let exact = prepare_client_authoring_context(
    owner,
    geometry.complete.bytes,
    geometry.complete.nodes,
    geometry.complete.depth,
  ).unwrap()
  let actual = finish_prepared_client_authoring_context(exact).unwrap()
  let small = prepare_client_authoring_context(
    owner,
    geometry.complete.bytes - 1,
    geometry.complete.nodes,
    geometry.complete.depth,
  ).unwrap()
  assert_true(measure_prepared_client_authoring_context(small) is Err(Encoding))
  let failure = finish_prepared_client_authoring_context(small)
  assert_true(failure is Err(_))
  assert_true(
    physical_equal(failure, finish_prepared_client_authoring_context(small)),
  )
  assert_true(
    physical_equal(
      actual,
      finish_prepared_client_authoring_context(exact).unwrap(),
    ),
  )
}

///|
test "authoring collection geometry observes grammar paths without collecting business meta" {
  let document = local_normalization_document
    .replace(
      old="\"id\":\"local.normalization\"",
      new="\"id\":\"local.normalization\",\"meta\":{\"note\":\"root\"}",
    )
    .replace(
      old="\"id\":\"source\"",
      new="\"id\":\"source\",\"meta\":{\"note\":\"stage\"}",
    )
    .replace(
      old="\"view\":\"v\"",
      new="\"view\":\"v\",\"meta\":{\"note\":\"input\"}",
    )
    .replace(
      old="\"as\":\"derived\"",
      new="\"as\":\"derived\",\"meta\":{\"note\":\"step\"}",
    )
  let owner = local_normalization_fixture(document~)
  let (result, work) = observe_client_authoring_collection_geometry(
    owner, 100000L,
  )
  let actual = result.unwrap()
  assert_eq(actual.items, 4)
  assert_eq(actual.path_utf16, 74L)
  assert_eq(actual.max_path_utf16, 33)
  assert_eq(actual.max_quoted_key_bytes, 10)
  assert_eq(actual.meta_nodes, 8)
  assert_eq(actual.meta_fields, 4)
  assert_eq(actual.work, work)
  let prepared = prepare_client_authoring_context(owner, 65536, 4096, 64).unwrap()
  let items = prepared.items.unwrap()
  assert_eq(items.length(), actual.items)
  let mut paths = 0L
  for item in items {
    paths += item.path.length().to_int64()
  }
  assert_eq(paths, 74L)
  let empty = local_normalization_fixture()
  let (empty_result, _) = observe_client_authoring_collection_geometry(
    empty, 100000L,
  )
  assert_eq(empty_result.unwrap().items, 0)
  assert_eq(empty_result.unwrap().path_utf16, 0L)
  let (short, spent) = observe_client_authoring_collection_geometry(owner, 0L)
  assert_true(short is Err(Encoding))
  assert_eq(spent, 0L)
}
