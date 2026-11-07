// Test input construction shared in meaning with the Native Row fixture.
// Common generates all contracts and identities; no expected query result is
// derived here. The output is later observed by the real Native Owners.

///|
fn capture_fixture_declaration() -> @rows.RowDeclaration {
  @rows.generate_row_declaration(
    "native-file-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        fields: [
          { name: "id", value_type: "string", nullable: false, },
          { name: "value", value_type: "number", nullable: false, },
        ],
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 1,
      max_fields: 2,
    },
  ).unwrap()
}

///|
// Environment sections are ordered by each complete canonical member CID.
// This creates checking inputs, never an expected capture or physical result.
fn capture_fixture_members(bodies : Array[String]) -> Json raise {
  let ordered = bodies.map(wire => {
    let body = @identity.from_json(@json.parse(wire), 100000, 100, 1000000)
    (@identity.cid_value(body, 1000000, 100000, 100), @json.parse(wire))
  })
  ordered.sort_by((left, right) => left.0.compare(right.0))
  Json::array(ordered.map(entry => entry.1))
}

///|
fn capture_fixture_environment(
  declaration : @rows.RowDeclaration,
) -> (String, String) raise {
  let (schemas, capabilities) = @rows.row_declaration_evidence_members(
    declaration,
  )
  let body : Json = {
    "version": "actql-check-environment/0.1",
    "connector_manifest": {
      "version": "actql-connectors/0.1",
      "connectors": [@json.parse(declaration.manifest_entry)],
    },
    "connector_catalogs": [@json.parse(declaration.catalog)],
    "contract_registry": capture_fixture_members(declaration.contracts),
    "source_views": capture_fixture_members(declaration.view_bodies),
    "schema_snapshots": capture_fixture_members(schemas),
    "connector_capabilities": capture_fixture_members(capabilities),
    "command_contracts": [],
    "mapping_contracts": [],
    "model_task_contracts": [],
    "host_policy_profile": {
      "capacity": {
        "version": "actql-capacity-host-policy/0.1",
        "max_aggregate_array_items": 10000,
        "max_artifact_bytes": 10000,
        "max_artifact_rows": 10000,
        "max_effect_items": 10000,
        "max_graph_input_edges": 10000,
        "max_graph_input_nodes": 10000,
        "max_graph_output_rows": 10000,
        "max_graph_paths": 10000,
        "max_infer_items": 10000,
        "max_model_input_tokens_per_item": 10000,
        "max_model_request_bytes_per_item": 10000,
        "max_model_total_duration_ms": 10000,
        "max_nested_value_bytes": 10000,
        "max_nested_value_depth": 10000,
        "max_relation_output_rows": 10000,
        "max_temporal_matches_per_key": 10000,
        "max_temporal_output_rows": 10000,
      },
    },
  }
  let canonical = @identity.from_json(body, 100000, 100, 1000000)
  let cid = @identity.cid_value(canonical, 1000000, 100000, 100)
  let enveloped = @identity.object_with_string_field(
    canonical, "evidence_bundle_cid", cid,
  ).unwrap()
  (@identity.stringify_value(enveloped, 1000000, 100000, 100), cid)
}

///|
// Optional external setup output. Ordinary tests do not write files; the
// diagnostic selects a fresh private path and never replaces existing bytes.
extern "js" fn emit_fixture_environment(wire : String) -> Unit =
  #|(wire) => {
  #|  const path = process.env.ACTQL_TEST_NATIVE_RELATION_ENVIRONMENT_OUTPUT;
  #|  if (path === undefined) return;
  #|  const fs = process.getBuiltinModule('node:fs');
  #|  const paths = process.getBuiltinModule('node:path');
  #|  if (!paths.isAbsolute(path)) throw new Error('Fixture output must be absolute');
  #|  const parent = fs.lstatSync(paths.dirname(path));
  #|  if (!parent.isDirectory() || parent.isSymbolicLink() || (parent.mode & 0o777) !== 0o700)
  #|    throw new Error('Fixture output requires its own private parent');
  #|  fs.writeFileSync(path, wire, {flag: 'wx', mode: 0o600});
  #|}

///|
test "Common constructs exact Native relation fixture input" {
  let declaration = capture_fixture_declaration()
  let (wire, cid) = capture_fixture_environment(declaration)
  assert_eq(declaration.connector_id, "native-file-fixture")
  assert_eq(declaration.views.length(), 1)
  assert_eq(
    declaration.views[0].source_ref,
    "connector://native-file-fixture/records#records",
  )
  assert_eq(declaration.views[0].classification, "unknown")
  assert_true(wire.length() < 65536)
  assert_true(wire.contains(cid))
  emit_fixture_environment(wire)
}

///|
// An explicitly selected setup array is data, never an adopted configuration.
extern "js" fn fixture_configuration_inputs() -> FixedArray[String] =
  #|() => {
  #|  const path = process.env.ACTQL_TEST_NATIVE_RELATION_CONFIGURATION_INPUTS;
  #|  if (path === undefined) return [];
  #|  const fs = process.getBuiltinModule('node:fs');
  #|  const paths = process.getBuiltinModule('node:path');
  #|  if (!paths.isAbsolute(path)) throw new Error('Configuration input must be absolute');
  #|  const info = fs.lstatSync(path);
  #|  if (!info.isFile() || info.isSymbolicLink() || info.size > 65536)
  #|    throw new Error('Invalid finite configuration input');
  #|  const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  #|  let inputs;
  #|  try {
  #|    const opened = fs.fstatSync(fd);
  #|    if (!opened.isFile() || opened.dev !== info.dev || opened.ino !== info.ino || opened.size !== info.size)
  #|      throw new Error('Configuration original changed');
  #|    const bytes = Buffer.alloc(opened.size + 1);
  #|    let count = 0;
  #|    while (count < bytes.length) {
  #|      const next = fs.readSync(fd, bytes, count, bytes.length - count, null);
  #|      if (next === 0) break;
  #|      count += next;
  #|    }
  #|    const after = fs.fstatSync(fd), named = fs.lstatSync(path);
  #|    if (count !== opened.size || after.size !== opened.size || after.mtimeMs !== opened.mtimeMs ||
  #|        after.ctimeMs !== opened.ctimeMs || named.isSymbolicLink() || named.dev !== opened.dev || named.ino !== opened.ino)
  #|      throw new Error('Configuration original changed during read');
  #|    inputs = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes.subarray(0, count)));
  #|  } finally { fs.closeSync(fd); }
  #|  if (!Array.isArray(inputs) || inputs.length !== 9 || inputs.some(value => typeof value !== 'string'))
  #|    throw new Error('Invalid configuration fields');
  #|  return inputs;
  #|}

///|
extern "js" fn emit_fixture_run(root : String, wire : String) -> Unit =
  #|(root, wire) => {
  #|  const fs = process.getBuiltinModule('node:fs');
  #|  const paths = process.getBuiltinModule('node:path');
  #|  if (!paths.isAbsolute(root)) throw new Error('Fixture output must be absolute');
  #|  const info = fs.lstatSync(root);
  #|  if (!info.isDirectory() || info.isSymbolicLink() || (info.mode & 0o777) !== 0o700)
  #|    throw new Error('Fixture output requires its own private parent');
  #|  const names = fs.readdirSync(root).sort();
  #|  if (JSON.stringify(names) !== JSON.stringify(['account.json', 'environment.json', 'records.json', 'row-declaration.json', 'runtime.json']))
  #|    throw new Error('Fixture configuration already attempted or initialized');
  #|  fs.writeFileSync(paths.join(root, 'run.json'), wire, {flag: 'wx', mode: 0o600});
  #|}

///|
// The CI fixture recipe needs the current Common inputs, never a retained
// workspace asset set or a handwritten substitute for the run contracts.
extern "js" fn emit_fixture_baseline_assets(
  environment : String,
  registry : String,
  values : String,
  fragment : String,
  ordered : String,
  result_policy : String,
) -> Unit =
  #|(environment, registry, values, fragment, ordered, resultPolicy) => {
  #|  const path = process.env.ACTQL_TEST_NATIVE_RELATION_BASELINE_ASSETS_OUTPUT;
  #|  if (path === undefined) return;
  #|  const fs = process.getBuiltinModule('node:fs');
  #|  const paths = process.getBuiltinModule('node:path');
  #|  if (!paths.isAbsolute(path)) throw new Error('Fixture asset output must be absolute');
  #|  const parent = fs.lstatSync(paths.dirname(path));
  #|  if (!parent.isDirectory() || parent.isSymbolicLink() || (parent.mode & 0o777) !== 0o700)
  #|    throw new Error('Fixture asset output requires its own private parent');
  #|  const bytes = JSON.stringify([environment, registry, values, fragment, ordered, resultPolicy]);
  #|  if (Buffer.byteLength(bytes) > 65536) throw new Error('Fixture assets exceed finite input bound');
  #|  fs.writeFileSync(path, bytes, {flag: 'wx', mode: 0o600});
  #|}

///|
test "Common constructs baseline run packet without relaxing Source guard" {
  let selected = fixture_configuration_inputs()
  let assets = if selected.is_empty() {
    @host.client_local_product_assets()
  } else {
    {
      environment: selected[3],
      registry: selected[4],
      values: selected[5],
      fragment: selected[6],
      ordered: Some(selected[7]),
      result_policy: selected[8],
    }
  }
  emit_fixture_baseline_assets(
    assets.environment,
    assets.registry,
    assets.values,
    assets.fragment,
    assets.ordered.unwrap(),
    assets.result_policy,
  )
  let (root, sqlite, crypto) = if selected.is_empty() {
    ("/fixture", "/fixture/sqlite", "/fixture/crypto")
  } else {
    (selected[0], selected[1], selected[2])
  }
  let originals = @host.client_local_product_originals(
    root, sqlite, crypto, "2026-11-06T00:00:00.000Z", assets,
  ).unwrap()
  let run = originals.iter().find_first(pair => pair.0 == "run.json").unwrap().1
  let (source_environment, _) = capture_fixture_environment(
    capture_fixture_declaration(),
  )
  assert_true(
    @host.client_local_product_originals(
      root,
      sqlite,
      crypto,
      "2026-11-06T00:00:00.000Z",
      { ..assets, environment: source_environment, },
    )
    is Err(InvalidEnvironment),
  )
  assert_true(run.length() > 0 && run.length() <= 65536)
  if !selected.is_empty() {
    emit_fixture_run(root, @utf8.decode(run))
  }
}
