///|
fn file_query_json(value : Json) -> String raise {
  @json_identity.stringify_value(
    @json_identity.from_json(value, 10000, 100, 100000),
    100000,
    10000,
    100,
  )
}

///|
fn file_query_seal(value : Json, name : String) -> Json raise {
  let cid = @json_identity.cid_value(
    @json_identity.from_json(value, 10000, 100, 100000),
    100000,
    10000,
    100,
  )
  guard value is Object(fields) else { abort("object fixture") }
  fields[name] = Json::string(cid)
  value
}

///|
fn file_query_ref(value : Json) -> Json {
  guard value is Object(fields) else { abort("envelope fixture") }
  Json::object(
    Map([
      ("id", fields["id"]),
      ("version", fields["version"]),
      ("cid", fields["cid"]),
    ]),
  )
}

///|
fn file_query_contract(kind : String, body : Json) -> Json raise {
  file_query_seal(
    Json::object(
      Map([
        ("schema", Json::string("actql.contract/0.1")),
        ("id", Json::string(kind)),
        ("kind", Json::string(kind)),
        ("version", Json::string("fixture")),
        ("body", body),
      ]),
    ),
    "cid",
  )
}

///|
fn file_query_environment(
  profile? : Bool = true,
  all? : Bool = false,
  glob? : Bool = true,
  native_metadata? : Bool = false,
) -> @check.CheckEnvironment raise {
  let schema_body = @json.parse(
    (
      #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"resource":{"type":"resource_ref","resource_kind":"file","nullable":false},"version":{"type":"string","nullable":false},"name":{"type":"string","nullable":false},"path":{"type":"string","nullable":true},"media_type":{"type":"string","nullable":true},"size_bytes":{"type":"number","nullable":true},"modified_at":{"type":"timestamp","nullable":true}}}
    ),
  )
  if native_metadata {
    guard schema_body is Object(body) && body["fields"] is Object(fields) else {
      abort("native listing schema fixture")
    }
    fields["size"] = ({ "type": "int64", "nullable": false } : Json)
    fields["modified_time"] = ({ "type": "timestamp", "nullable": false } : Json)
    fields["path"] = ({ "type": "string", "nullable": false } : Json)
  }
  let schema = file_query_contract("carrier_schema", schema_body)
  let request = file_query_contract(
    "request_schema",
    @json.parse(
      (
        #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"paths":{"type":"array","nullable":true,"max_items":8,"items":{"type":"string","nullable":false}},"glob":{"type":"string","nullable":true}}}
      ),
    ),
  )
  let policy = file_query_contract(
    "data_policy",
    @json.parse(
      (
        #|{"version":"actql-source-data-policy/0.1","source_ref":"connector://fixture/files/mount#listing","classification":"unknown"}
      ),
    ),
  )
  let declaration = @json.parse(
    (
      #|{"version":"actql-file-list/0.1","kind":"file_listing","selectable":["paths"],"allow_unfiltered_listing":false,"admitted_scope_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","max_listing_items":8,"max_examined_items":32,"max_listing_pages":4,"maximum_path_length":256,"version_capability":{"contract_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","required_nonnull":true}}
    ),
  )
  guard declaration is Object(fields) && schema is Object(schema_fields) else {
    abort("fixture")
  }
  fields["listing_schema_contract_cid"] = schema_fields["cid"]
  fields["allow_unfiltered_listing"] = Json::boolean(all)
  if glob {
    fields["selectable"] = @json.parse("[\"paths\",\"glob\"]")
  }
  let facts = file_query_contract(
    "carrier_facts",
    Json::object(
      if profile {
        Map([("file_listing", declaration)])
      } else {
        Map([])
      },
    ),
  )
  let pushdown = file_query_contract("pushdown", Json::object(Map([])))
  let contracts = [schema, request, policy, facts, pushdown]
  contracts.sort_by((a, b) => {
    guard a is Object(a) &&
      b is Object(b) &&
      a["cid"] is String(a) &&
      b["cid"] is String(b) else {
      abort("fixture")
    }
    a.compare(b)
  })
  let view = @json.parse(
    (
      #|{"schema":"actql.source_view/0.1","connector_id":"fixture/files","connector_version":"fixture","resource_kind":"file","view_id":"listing","view_version":"fixture","acquisition":{"kind":"scan","authority":"read_metadata","modes":[{"mode":"snapshot","bounded":true}],"default_mode":"snapshot"},"request_processing":{"mutates_business_state":false},"output":{"carrier":"relation"},"pushdown":{"operations":[]}}
    ),
  )
  guard view is Object(view_fields) &&
    view_fields["acquisition"] is Object(acquisition) &&
    view_fields["output"] is Object(output) &&
    view_fields["pushdown"] is Object(push) else {
    abort("fixture")
  }
  acquisition["request_schema"] = file_query_ref(request)
  output["schema"] = file_query_ref(schema)
  output["facts"] = file_query_ref(facts)
  output["data_policy"] = file_query_ref(policy)
  push["contract"] = file_query_ref(pushdown)
  let view = file_query_seal(view, "contract_cid")
  let catalog = file_query_seal(
    Json::object(
      Map([
        ("schema", Json::string("actql.connector_catalog/0.1")),
        ("connector_id", Json::string("fixture/files")),
        ("connector_version", Json::string("fixture")),
        ("contracts", Json::array(contracts)),
        ("source_views", Json::array([view])),
        ("commands", Json::array([])),
      ]),
    ),
    "catalog_cid",
  )
  // Catalog members are ordered by envelope CID. Environment evidence is
  // ordered by its full canonical member hash, including the envelope CID.
  let evidence = contracts.map(entry => {
    (
      @json_identity.cid_value(
        @json_identity.from_json(entry, 10000, 100, 100000),
        100000,
        10000,
        100,
      ),
      entry,
    )
  })
  evidence.sort_by((a, b) => a.0.compare(b.0))
  let registry = evidence.map(entry => entry.1)
  let environment = file_query_seal(
    Json::object(
      Map([
        ("version", Json::string("actql-check-environment/0.1")),
        ("host_policy_profile", Json::object(Map([]))),
        ("contract_registry", Json::array(registry)),
        ("connector_catalogs", Json::array([catalog])),
        ("source_views", Json::array([view])),
        ("command_contracts", Json::array([])),
        ("mapping_contracts", Json::array([])),
        ("model_task_contracts", Json::array([])),
        ("connector_capabilities", Json::array([])),
        ("schema_snapshots", Json::array([])),
      ]),
    ),
    "evidence_bundle_cid",
  )
  guard environment is Object(fields) &&
    fields["evidence_bundle_cid"] is String(cid) else {
    abort("fixture")
  }
  let wire = @environment.read(
    @utf8.encode(file_query_json(environment)),
    cid,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
  )
  let wire = match wire {
    Ok(value) => value
    Err(issue) => abort("file fixture environment: " + @debug.to_string(issue))
  }
  @check.checking_environment(wire, { text_time: false, veca: false, }, {
    rela: true,
    sga: false,
    tea: false,
    calendar: false,
    text_rank: false,
  })
}

///|
fn file_query_context(
  profile? : Bool = true,
  all? : Bool = false,
  glob? : Bool = true,
  native_metadata? : Bool = false,
) -> Context raise {
  let catalog = @check.source_catalog_contracts(
    @check.prepare_source_catalog(
      file_query_environment(profile~, all~, glob~, native_metadata~),
      {
        max_work: 1000000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
    ).unwrap(),
  )
  let fields = [
    "resource", "version", "name", "path", "media_type", "size_bytes", "modified_at",
  ]
  if native_metadata {
    fields.push("size")
    fields.push("modified_time")
  }
  let source = @wire.admit(
    @source.parse_json(
      "{\"connector\":\"fixture/files\",\"resource\":\"mount\",\"view\":\"listing\"}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..fixture_context(),
    captured_stage: None,
    source_catalog: Some(catalog),
    inputs: [
      {
        relation: [
          { value: "docs", quoted: false, },
          { value: "invoices", quoted: false, },
        ],
        name: "files",
        source: Captured(source),
        visible_fields: fields,
        graph_bindings: [],
      },
    ],
  }
}

///|
fn file_query_input_declarations(
  program : @program.Program,
) -> Array[Json] raise {
  guard @json.parse(semantic(program)) is Object(root) &&
    root["stages"] is Array(stages) else {
    abort("fixture")
  }
  let declarations = []
  for stage in stages {
    guard stage is Object(stage) &&
      stage["inputs"] is Object(inputs) &&
      stage["steps"] is Array(steps) else {
      abort("fixture")
    }
    // Input objects are unordered. Follow first use in the ordered stage
    // steps to check the Source-to-WITH correspondence, not Map iteration.
    let seen : Map[String, Bool] = Map([])
    for step in steps {
      if step is Object(fields) {
        let references = []
        if fields.get("from") is Some(String(name)) {
          references.push(name)
        }
        for operation in ["join", "cross_join"] {
          if fields.get(operation) is Some(Object(body)) &&
            body.get("with") is Some(String(name)) {
            references.push(name)
          }
        }
        for name in references {
          if !seen.contains(name) &&
            inputs.get(name) is Some(declaration) &&
            declaration is Object(source) &&
            source.contains("connector") {
            seen[name] = true
            declarations.push(declaration)
          }
        }
      }
    }
  }
  declarations
}

///|
test "LIST_FILES SQL and Pipe retain exact Request values through common source selection" {
  let context = file_query_context()
  let expected = @json.parse(
    "{\"connector\":\"fixture/files\",\"resource\":\"mount\",\"view\":\"listing\",\"request\":{\"paths\":[\"a.pdf\",\"é.pdf\"],\"glob\":null}}",
  )
  let programs = []
  for
    text in [
      "SELECT name FROM LIST_FILES(docs.invoices, paths => ['a.pdf', 'é.pdf'])",
      "FROM LIST_FILES(docs.invoices, paths => ['a.pdf', 'é.pdf']) |> SELECT name",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_eq(file_query_input_declarations(program), [expected])
    programs.push(semantic(program))
  }
  assert_eq(programs[0], programs[1])
}

///|
test "LIST_FILES exposes declared native metadata directly for SQL Pipe and empty selectors" {
  let context = file_query_context(native_metadata=true)
  let programs = []
  for
    text in [
      "SELECT f.size, f.modified_time FROM LIST_FILES(docs.invoices, paths => ARRAY<STRING>[]) AS f",
      "FROM LIST_FILES(docs.invoices, paths => ARRAY<STRING>[]) AS f |> SELECT f.size, f.modified_time",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_eq(file_query_input_declarations(program), [
      @json.parse(
        "{\"connector\":\"fixture/files\",\"resource\":\"mount\",\"view\":\"listing\",\"request\":{\"paths\":[],\"glob\":null}}",
      ),
    ])
    programs.push(semantic(program))
  }
  assert_eq(programs[0], programs[1])
}

///|
test "LIST_FILES typed empty paths and raw glob remain selector data not unfiltered listing" {
  let context = file_query_context()
  for
    (text, expected) in [
      (
        "FROM LIST_FILES(docs.invoices, paths => ARRAY<STRING>[]) |> SELECT name",
        "{\"paths\":[],\"glob\":null}",
      ),
      (
        "FROM LIST_FILES(docs.invoices, glob => r'a\\?.pdf') |> SELECT name", "{\"paths\":null,\"glob\":\"a\\\\?.pdf\"}",
      ),
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    guard file_query_input_declarations(program)[0] is Object(fields) else {
      abort("fixture")
    }
    assert_eq(fields["request"], @json.parse(expected))
  }
  let query = @query.parse_query(
    "FROM LIST_FILES(docs.invoices) |> SELECT name",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, context, construction_limits())
    is Err(FileListing(UnsupportedSelector)),
  )
  assert_true(
    compile(query, file_query_context(all=true), construction_limits()) is Ok(_),
  )
}

///|
test "LIST_FILES refuses ordinary schema hints absent profiles and incompatible selectors" {
  let query = @query.parse_query(
    "FROM LIST_FILES(docs.invoices, glob => '*.pdf') |> SELECT name",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, file_query_context(profile=false), construction_limits())
    is Err(FileListing(MissingProfile)),
  )
  assert_true(
    compile(query, file_query_context(glob=false), construction_limits())
    is Err(FileListing(UnsupportedSelector)),
  )
  let context = file_query_context()
  assert_true(
    compile(query, { ..context, source_catalog: None, }, construction_limits())
    is Err(FileListing(MissingCatalog)),
  )
  let derived = { ..context.inputs[0], source: StepReference, }
  assert_true(
    compile(query, { ..context, inputs: [derived], }, construction_limits())
    is Err(FileListing(InstalledSourceRequired)),
  )
  for
    text in [
      "FROM LIST_FILES(docs.invoices, paths => [1]) |> SELECT name", "FROM LIST_FILES(docs.invoices, glob => NULL) |> SELECT name",
      "FROM LIST_FILES(docs.invoices, glob => name) |> SELECT name",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        context,
        construction_limits(),
      )
      is Err(FileListing(InvalidSelector)),
    )
  }
}

///|
test "LIST_FILES distinct Requests of one Source do not reuse the first WITH capture" {
  let script = @query.parse_query_script(
    "WITH a AS (FROM LIST_FILES(docs.invoices, paths => ['a.pdf']) |> SELECT name), b AS (FROM LIST_FILES(docs.invoices, paths => ['b.pdf']) |> SELECT name) FROM a |> UNION ALL (FROM b |> SELECT name) |> SELECT name",
    syntax_limits(),
  ).unwrap()
  let program = compile_query_script(
    script,
    file_query_context(),
    construction_limits(),
  ).unwrap()
  let declarations = file_query_input_declarations(program)
  assert_eq(declarations.length(), 2)
  let paths = []
  for declaration in declarations {
    guard declaration is Object(fields) && fields["request"] is Object(request) else {
      abort("fixture")
    }
    paths.push(request["paths"])
  }
  assert_eq(paths, [@json.parse("[\"a.pdf\"]"), @json.parse("[\"b.pdf\"]")])
}

///|
test "LIST_FILES selected parameter type is checked and cannot become unfiltered through NULL" {
  let query = @query.parse_query(
    "FROM LIST_FILES(docs.invoices, glob => @Pattern) |> SELECT name",
    syntax_limits(),
  ).unwrap()
  for (kind, accepted) in [("string", true), ("number", false)] {
    let source = @wire.admit(
      @source.parse_json(
        "{\"pattern\":{\"type\":\"" + kind + "\",\"nullable\":false}}",
        construction_limits().source.source,
      ).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
    let parameters = @parameters.read_declarations(Some(source), {
      max_parameters: 10,
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    let result = compile(
      query,
      { ..file_query_context(), parameter_declarations: Some(parameters), },
      construction_limits(),
    )
    assert_eq(result is Ok(_), accepted)
    if result is Ok(program) {
      guard file_query_input_declarations(program)[0] is Object(fields) &&
        fields["request"] is Object(request) else {
        abort("fixture")
      }
      assert_eq(request["glob"], @json.parse("{\"$param\":\"pattern\"}"))
    }
  }
  let source = @wire.admit(
    @source.parse_json(
      "{\"pattern\":{\"type\":\"string\",\"nullable\":true}}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let parameters = @parameters.read_declarations(Some(source), {
    max_parameters: 10,
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
  assert_true(
    compile(
      query,
      {
        ..file_query_context(all=true),
        parameter_declarations: Some(parameters),
      },
      construction_limits(),
    )
    is Err(FileListing(Request(issue))) &&
    issue.kind == @source_resolution.InvalidFileListSelector,
  )
}

///|
fn file_query_direct_requests(
  program : @program.Program,
  context : Context,
) -> Array[
  Result[@source_resolution.DirectRequest, @source_resolution.RequestIssue],
] {
  let staged = @stage_parameters.prepare(program, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  let inputs = @sourceviews.collect(staged, {
    max_work: 100000,
    max_order_keys: 100,
  }).unwrap()
  let resolved = @source_resolution.resolve(
    inputs,
    context.source_catalog.unwrap(),
    { max_work: 100000, max_inputs: 100, max_views: 100, },
  ).unwrap()
  let binding = @bindings.prepare(program, {
    max_bindings: 100,
    max_work: 100000,
  }).unwrap()
  let slots = @request_slots.collect(staged, binding, {
    max_slots: 100,
    max_work: 100000,
  }).unwrap()
  let requests = @source_resolution.prepare_requests(resolved, slots, 100000).unwrap()
  let result = []
  for index in 0..<@source_resolution.count(resolved) {
    result.push(
      @source_resolution.check_direct_request(
        requests,
        @source_resolution.at(resolved, index).unwrap(),
        {
          max_work: 100000,
          max_pairs: 10000,
          values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
        },
      ),
    )
  }
  result
}

///|
test "JSON file-list Requests use the same selector exclusivity and NULL checks as SQL" {
  for
    (request, all, expected) in [
      ("{\"paths\":[],\"glob\":null}", false, true),
      ("{\"paths\":null,\"glob\":\"é/*.pdf\"}", false, true),
      ("{\"paths\":[\"a.pdf\"],\"glob\":\"*.pdf\"}", true, false),
      ("{\"paths\":null,\"glob\":null}", false, false),
      ("{\"paths\":null,\"glob\":null}", true, true),
    ] {
    let program = @program.parse(
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.file_listing\",\"stages\":[{\"id\":\"main\",\"inputs\":{\"files\":{\"connector\":\"fixture/files\",\"resource\":\"mount\",\"view\":\"listing\",\"request\":" +
      request +
      "}},\"steps\":[{\"from\":\"files\",\"select\":[\"name\"],\"as\":\"listed\"}],\"results\":{\"rows\":{\"from\":\"listed\",\"fields\":[\"name\"]}}}],\"results\":{\"files\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      construction_limits().program,
      format=Json,
    ).unwrap()
    let checked = file_query_direct_requests(program, file_query_context(all~))
    assert_eq(checked.length(), 1)
    assert_eq(checked[0] is Ok(_), expected)
    if !expected {
      assert_true(
        checked[0] is Err(issue) &&
        issue.kind == @source_resolution.InvalidFileListSelector,
      )
    }
  }
}

///|
test "compiled LIST_FILES Requests remain valid under their final Program owner" {
  for
    text in [
      "FROM LIST_FILES(docs.invoices, paths => ['a.pdf', 'é.pdf']) |> SELECT name",
      "WITH a AS (FROM LIST_FILES(docs.invoices, paths => ['a.pdf']) |> SELECT name), b AS (FROM LIST_FILES(docs.invoices, paths => ['b.pdf']) |> SELECT name) FROM a |> UNION ALL (FROM b |> SELECT name) |> SELECT name",
    ] {
    let context = file_query_context()
    let script = @query.parse_query_script(text, syntax_limits()).unwrap()
    let program = compile_query_script(script, context, construction_limits()).unwrap()
    let checked = file_query_direct_requests(program, context)
    assert_true(!checked.is_empty())
    assert_true(checked.iter().all(result => result is Ok(_)))
  }
}

///|
test "LIST_FILES nested CTE and both JOIN inputs keep their own checked selectors" {
  let context = file_query_context()
  for
    (text, expected) in [
      (
        "WITH a AS (SELECT name FROM LIST_FILES(docs.invoices, paths => ['a.pdf'])) SELECT name FROM a",
        ["a.pdf"],
      ),
      (
        "SELECT l.name AS lname, r.name AS rname FROM LIST_FILES(docs.invoices, paths => ['a.pdf']) AS l JOIN LIST_FILES(docs.invoices, paths => ['b.pdf']) AS r ON l.name = r.name",
        ["a.pdf", "b.pdf"],
      ),
    ] {
    let query = @query.parse_query_script(text, syntax_limits()).unwrap()
    let program = compile_query_script(query, context, construction_limits()).unwrap()
    let declarations = file_query_input_declarations(program)
    assert_eq(declarations.length(), expected.length())
    for index in 0..<expected.length() {
      guard declarations[index] is Object(fields) &&
        fields["request"] is Object(request) else {
        abort("fixture")
      }
      assert_eq(request["paths"], Json::array([Json::string(expected[index])]))
      assert_eq(request["glob"], Json::null())
    }
    let checked = file_query_direct_requests(program, context)
    assert_eq(checked.length(), expected.length())
    assert_true(checked.iter().all(result => result is Ok(_)))
  }
}

///|
test "LIST_FILES cannot replace a published Source's fixed selector" {
  let context = file_query_context(all=true)
  let source = @wire.admit(
    @source.parse_json(
      "{\"connector\":\"fixture/files\",\"resource\":\"mount\",\"view\":\"listing\",\"request\":{\"paths\":[\"only-authorized.pdf\"],\"glob\":null}}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = {
    ..context,
    inputs: [{ ..context.inputs[0], source: Captured(source), }],
  }
  for
    text in [
      "FROM LIST_FILES(docs.invoices) |> SELECT name", "FROM LIST_FILES(docs.invoices, paths => ['another.pdf']) |> SELECT name",
      "FROM LIST_FILES(docs.invoices, glob => '*.pdf') |> SELECT name",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(query, context, construction_limits())
      is Err(FileListing(FixedSelectorConflict)),
    )
  }
}
