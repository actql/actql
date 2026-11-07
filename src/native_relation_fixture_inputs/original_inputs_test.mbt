///|
// Default inputs are construction smoke only. An explicit root selects actual
// originals for Common admission, never Native custody or physical execution.
extern "js" fn audit_relation_inputs(
  environment : String,
  run : String,
) -> FixedArray[String] =
  #|(environment, run) => {
  #|  const fs = process.getBuiltinModule('node:fs');
  #|  const path = process.getBuiltinModule('node:path');
  #|  const crypto = process.getBuiltinModule('node:crypto');
  #|  const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
  #|  const root = process.env.ACTQL_TEST_NATIVE_RELATION_AUDIT_ROOT;
  #|  if (root !== undefined) {
  #|    if (!path.isAbsolute(root)) throw new Error('Audit root must be absolute');
  #|    return ['environment.json', 'run.json', 'runtime.json', 'row-declaration.json', 'records.json'].map(name => {
  #|      const file = path.join(root, name), before = fs.lstatSync(file);
  #|      if (!before.isFile() || before.isSymbolicLink() || before.size < 1 || before.size > 65536)
  #|        throw new Error('Invalid finite audit original');
  #|      const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  #|      try {
  #|        const opened = fs.fstatSync(fd);
  #|        if (opened.dev !== before.dev || opened.ino !== before.ino || opened.size !== before.size)
  #|          throw new Error('Audit original changed');
  #|        const bytes = Buffer.alloc(opened.size + 1);
  #|        let count = 0;
  #|        while (count < bytes.length) {
  #|          const next = fs.readSync(fd, bytes, count, bytes.length - count, null);
  #|          if (!next) break;
  #|          count += next;
  #|        }
  #|        const after = fs.fstatSync(fd), named = fs.lstatSync(file);
  #|        if (count !== opened.size || after.size !== opened.size || after.mtimeMs !== opened.mtimeMs ||
  #|            after.ctimeMs !== opened.ctimeMs || named.isSymbolicLink() || named.ino !== opened.ino || named.dev !== opened.dev)
  #|          throw new Error('Audit original changed during read');
  #|        return new TextDecoder('utf-8', {fatal:true}).decode(bytes.subarray(0, count));
  #|      } finally { fs.closeSync(fd); }
  #|    });
  #|  }
  #|  const values = JSON.parse(run).native.run.source_free;
  #|  const assets = {environment, registry:values.registry, values:values.values, fragment:values.fragment,
  #|    ordered:values.ordered, 'result-policy':values.result_policy_wire};
  #|  const runtime = {sourceSha:'a'.repeat(40), platform:'linux-x64-gnu',
  #|    libraries:['sqlite','crypto'].map(role => ({role,path:`lib/${role}.bin`,bytes:64,sha256:'0'.repeat(64),
  #|      license:'licenses/fixture.txt',dependencies:['libc.so.6'],abi:{minimumGlibc:'2.34'}})),
  #|    assets:Object.entries(assets).map(([role,wire]) => ({role,path:`data/${role}.json`,bytes:Buffer.byteLength(wire),sha256:hash(wire)})),
  #|    licenses:[{path:'licenses/fixture.txt',bytes:1,sha256:'0'.repeat(64)}]};
  #|  return [environment, run, JSON.stringify(runtime),
  #|    '{"connector_id":"native-file-fixture","connector_registration":"fixture","connector_version":"fixture/0.1","views":[{"fields":[{"name":"id","nullable":false,"type":"string"},{"name":"value","nullable":false,"type":"number"}],"resource":"records","resource_kind":"record"}]}',
  #|    '{"items":[{"id":"first","value":1},{"id":"second","value":2}]}'];
  #|}

///|
fn audit_relation_field(value : Json, name : String) -> Json raise {
  guard value is Object(fields) && fields.get(name) is Some(found) else {
    fail("missing audit field: " + name)
  }
  found
}

///|
fn audit_relation_text(value : Json, name : String) -> String raise {
  guard audit_relation_field(value, name) is String(text) else {
    fail("invalid audit text: " + name)
  }
  text
}

///|
test "Common admits serialized Native relation inputs without physical execution" {
  let assets = @host.client_local_product_assets()
  let originals = @host.client_local_product_originals(
    "/fixture", "/fixture/sqlite", "/fixture/crypto", "2026-11-06T00:00:00.000Z",
    assets,
  ).unwrap()
  let run = originals.iter().find_first(pair => pair.0 == "run.json").unwrap().1
  let (environment, _) = capture_fixture_environment(
    capture_fixture_declaration(),
  )
  let selected = audit_relation_inputs(environment, @utf8.decode(run))
  assert_eq(selected.length(), 5)
  let environment_body = @json.parse(selected[0])
  let _ = @host.admit_client_check_environment(
    selected[0],
    audit_relation_text(environment_body, "evidence_bundle_cid"),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let runtime = @json.parse(selected[2])
  let _ = @host.admit_client_native_local_runtime(
    selected[2],
    audit_relation_text(runtime, "sourceSha"),
    audit_relation_text(runtime, "platform"),
    @sha.hex(@utf8.encode(selected[2])),
  ).unwrap()
  let authored = @json.parse(selected[3])
  let views : Json = { "views": audit_relation_field(authored, "views") }
  let declaration = @rows.restore_row_declaration(
    audit_relation_text(authored, "connector_id"),
    audit_relation_text(authored, "connector_registration"),
    audit_relation_text(authored, "connector_version"),
    views.stringify(),
    None,
  ).unwrap()
  assert_eq(
    @rows.row_declaration_catalog_cid(declaration),
    @rows.row_declaration_catalog_cid(capture_fixture_declaration()),
  )
  let document = @rows.admit_relation_document(
    @utf8.encode(selected[4]),
    { max_bytes: 8192, max_nodes: 512, max_depth: 8, max_rows: 2, },
    1000000,
  ).unwrap()
  let _ = @rows.project_relation_target_document(
    document,
    declaration,
    "records",
    ["items"],
    None,
    "id",
    [],
  ).unwrap()
  let _ = @host.client_local_run_policy_metadata_cursor(
    @utf8.encode(selected[1]),
  ).unwrap()
  let run_body = @json.parse(selected[1])
  assert_eq(audit_relation_text(run_body, "version"), "actql-config/0.1")
  let run_settings = audit_relation_field(
    audit_relation_field(run_body, "native"),
    "run",
  )
  let _ = @publication.admit_publication_contract(
    "result_retention_policy",
    audit_relation_text(run_settings, "retention_policy_wire"),
    8192,
    64,
    8,
  ).unwrap()
  let values = audit_relation_field(
    audit_relation_field(audit_relation_field(run_body, "native"), "run"),
    "source_free",
  )
  let _ = @local.prepare_installed_sequence_contracts(
    audit_relation_text(values, "registry"),
    audit_relation_text(values, "values"),
    Some(audit_relation_text(values, "fragment")),
    Some(audit_relation_text(values, "ordered")),
  ).unwrap()
  let _ = @host.admit_source_free_result_policy_body(
    audit_relation_text(values, "result_policy_cid"),
    audit_relation_text(values, "result_policy_wire"),
    8192,
    512,
    8,
  ).unwrap()
}
