///|
// Empty admitted installation metadata exercises the actual Common parser and
// Catalog reader. It is not a live installation or execution permission.
fn publication_parts_environment() -> @program_check.CheckEnvironment {
  let body =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:bf3e299a7386f7442aa04abc23901a1b3f580b490e6c625fe4ea686dce61032c","host_policy_profile":{},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let wire = @check_environment.read(
    @utf8.encode(body),
    "sha256:bf3e299a7386f7442aa04abc23901a1b3f580b490e6c625fe4ea686dce61032c",
    { max_bytes: 1048576, max_nodes: 16384, max_depth: 32, max_members: 32768, },
  ).unwrap()
  @program_check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
}

///|
fn publication_parts_wire(
  environment : @program_check.CheckEnvironment,
) -> String {
  "{\"environmentCid\":\"" +
  @program_check.checking_environment_cid(environment) +
  "\",\"aliases\":[],\"tableWrites\":[],\"updateTargets\":[],\"storeTargets\":[],\"commandTargets\":[]}"
}

///|
test "publication parts read the original wire once for all five projections" {
  let environment = publication_parts_environment()
  let wire = publication_parts_wire(environment)
  let reads = Ref(0)
  let seen = Ref("")
  let (context, tables, updates, stores, commands, catalog) = bind_published_query_parts_with_reader(
    environment,
    wire,
    None,
    original => {
      reads.val += 1
      seen.val = original
      source_publication_cursor(original)
    },
  ).unwrap()
  assert_eq(reads.val, 1)
  assert_eq(seen.val, wire)
  assert_true(context.inputs.is_empty())
  assert_true(context.source_catalog is Some(_))
  assert_true(tables.is_empty())
  assert_true(updates is None)
  assert_true(stores is None)
  assert_true(commands is None)
  assert_true(
    physical_equal(@program_check.source_catalog_owner(catalog), environment),
  )
  let legacy = bind_published_query_context(environment, wire, None).unwrap()
  assert_eq(context.program_id, legacy.program_id)
  assert_eq(context.result_name, legacy.result_name)
}

///|
test "publication parts refuse malformed unused sections after one actual read" {
  let environment = publication_parts_environment()
  let wire = publication_parts_wire(environment)
  for name in ["tableWrites", "updateTargets", "storeTargets", "commandTargets"] {
    for invalid in ["null", "{}", "[{}]"] {
      let changed = wire.replace(
        old="\"\{name}\":[]",
        new="\"\{name}\":\{invalid}",
      )
      let reads = Ref(0)
      assert_true(
        bind_published_query_parts_with_reader(environment, changed, None, original => {
          reads.val += 1
          source_publication_cursor(original)
        })
        is Err(_),
      )
      assert_eq(reads.val, 1)
    }
  }
}

///|
test "publication parts retain foreign environment closed shape and declarations refusals" {
  let environment = publication_parts_environment()
  let wire = publication_parts_wire(environment)
  let foreign = wire.replace(
    old=@program_check.checking_environment_cid(environment),
    new="sha256:" + "0".repeat(64),
  )
  assert_true(bind_published_query_parts(environment, foreign, None) is Err(_))
  assert_true(
    bind_published_query_parts(
      environment,
      wire.replace(old="\"aliases\":[]", new="\"aliases\":[],\"extra\":0"),
      None,
    )
    is Err(_),
  )
  assert_true(
    bind_published_query_parts(environment, wire, Some("null"))
    is Err(Declarations),
  )
  assert_true(
    bind_published_query_parts(environment, wire + "x", None) is Err(_),
  )
}
