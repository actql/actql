///|
fn file_listing_page_fixture() -> (
  NativeRelationFilePreparedProvider,
  @rows.RelationDocument,
  NativeRelationFileListingFields,
) {
  let declaration = match
    @rows.generate_row_declaration(
      "declared-file-fixture",
      "fixture",
      "fixture/0.1",
      [
        {
          resource: "files_data",
          resource_kind: "file",
          fields: [
            { name: "id", value_type: "string", nullable: false, },
            { name: "name", value_type: "string", nullable: false, },
            { name: "version", value_type: "string", nullable: false, },
            { name: "media_type", value_type: "string", nullable: false, },
            { name: "body", value_type: "string", nullable: false, },
            { name: "path", value_type: "string", nullable: true, },
          ],
        },
      ],
      {
        max_bytes: 65536,
        max_nodes: 8192,
        max_depth: 32,
        max_views: 1,
        max_fields: 6,
      },
    ) {
    Ok(value) => value
    Err(_) => abort("listing fixture declaration refused")
  }
  let selected : NativeRelationFileSelection = {
    directory: "/never-opened",
    name: "fixture.json",
    resource: "files_data",
    items_path: ["items"],
    key_path: None,
    primary_identity: "id",
  }
  let limits : NativeRelationFileLimits = {
    page: { max_bytes: 8192, max_nodes: 512, max_depth: 16, max_rows: 2, },
    max_work: 1000000,
    chunk_bytes: 7,
    diagnostic_ceiling: 128,
  }
  let provider = match
    prepare_native_relation_file_provider(declaration, selected, limits) {
    Ok(value) => value
    Err(Mapping(issue)) =>
      abort("listing fixture provider mapping: " + @debug.to_string(issue))
    Err(Capacity) => abort("listing fixture provider capacity")
    Err(_) => abort("listing fixture provider refused")
  }
  let document = match
    @rows.admit_relation_document(
      @utf8.encode(
        (
          #|{"items":[{"id":"first","name":"Acme🌱","version":"label","media_type":"text/plain","body":"first\nnotes","path":null},{"id":"second","name":"Globex","version":"label","media_type":"text/plain","body":"second notes","path":"notes/globex"}]}
        ),
      ),
      limits.page,
      limits.max_work,
    ) {
    Ok(value) => value
    Err(issue) =>
      abort("listing fixture raw document: " + @debug.to_string(issue))
  }
  (
    provider,
    document,
    {
      name: "name",
      version: "version",
      media_type: "media_type",
      path: Some("path"),
    },
  )
}

///|
fn file_listing_test_resource(
  identity : String,
  live : Ref[Bool],
) -> @admitted.CheckedValue {
  let suffix = if identity == "first" { "1" } else { "2" }
  let wire = "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:" +
    "b".repeat(64) +
    "\",\"boundary_cid\":\"sha256:" +
    "c".repeat(64) +
    "\",\"identity_cid\":\"sha256:" +
    suffix.repeat(64) +
    "\",\"provider_identity_cid\":\"sha256:" +
    "a".repeat(64) +
    "\",\"provider_namespace\":\"fixture\",\"resource_kind\":\"file\",\"version\":\"actql-resource-ref/0.1\"}"
  let source = @source.parse_json(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"file\"}",
    { max_input_bytes: 1024, max_nodes: 32, max_depth: 4, },
  ).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 32,
    max_depth: 4,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  let contract = @contract.read_checked(cursor, {
    max_nodes: 32,
    max_depth: 4,
    max_text_bytes: 1024,
  }).unwrap()
  // Explicit component issuer only; no Account or Native Source permission.
  @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      live.val
    }),
    contract,
    wire,
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
}

///|
test "Native file listing projects original rows with Source-issued refs and row-bound versions" {
  let (provider, document, fields) = file_listing_page_fixture()
  let live = Ref(true)
  let first = file_listing_test_resource("first", live)
  let second = file_listing_test_resource("second", live)
  let seen = []
  let bytes = match
    project_native_relation_file_listing_page(provider, document, fields, identity => {
      seen.push(identity)
      Ok(if identity == "first" { first } else { second })
    }) {
    Ok(value) => value
    Err(Document(issue)) =>
      abort("listing projection document: " + @debug.to_string(issue))
    Err(InvalidInput) => abort("listing projection invalid physical fields")
    Err(ForeignOriginal) => abort("listing projection original/reference fence")
    Err(FileLimit) => abort("listing projection output bound")
    Err(_) => abort("listing projection refused")
  }
  assert_eq(seen, ["first", "second"])
  guard @json.parse(@utf8.decode(bytes)) is Object(page) &&
    page.get("items") is Some(Array(items)) &&
    items[0] is Object(a) &&
    items[1] is Object(b) else {
    abort("bounded listing envelope")
  }
  assert_eq(page.get("request_token"), Some(Json::null()))
  assert_eq(page.get("next_token"), Some(Json::null()))
  assert_eq(a.get("name"), Some(Json::string("Acme🌱")))
  assert_eq(a.get("path"), Some(Json::null()))
  assert_eq(b.get("path"), Some(Json::string("notes/globex")))
  assert_eq(a.get("media_type"), Some(Json::string("text/plain")))
  assert_true(a.get("resource") != b.get("resource"))
  assert_true(a.get("version") != b.get("version"))
  assert_true(a.get("version") != Some(Json::string("label")))
  assert_false(a.contains("body"))
  assert_true(@rows.relation_document_usage(document) is Some(_))
  assert_true(@rows.discard_relation_document_original(document))
}

///|
test "Native file listing refuses unavailable nominal refs and parent retirement during issuance" {
  let (provider, document, fields) = file_listing_page_fixture()
  let live = Ref(true)
  let resource = file_listing_test_resource("first", live)
  live.val = false
  assert_true(
    project_native_relation_file_listing_page(provider, document, fields, _ => {
      Ok(resource)
    })
    is Err(ForeignOriginal),
  )
  live.val = true
  assert_true(
    project_native_relation_file_listing_page(provider, document, fields, _ => {
      @rows.discard_relation_document_original(document) |> ignore
      Ok(resource)
    })
    is Err(ForeignOriginal),
  )
}

///|
test "Native file listing validates physical roles before issuance and quotes bounded construction" {
  let (provider, document, fields) = file_listing_page_fixture()
  let calls = Ref(0)
  assert_true(
    project_native_relation_file_listing_page(
      provider,
      document,
      { ..fields, path: Some("absent"), },
      _ => {
        calls.val += 1
        Err(Unavailable)
      },
    )
    is Err(InvalidInput),
  )
  assert_eq(calls.val, 0)
  let units = native_relation_file_listing_construction_inventory(provider).unwrap()
  assert_true(@execution.preparation_representation_cost(units) is Some(_))
  assert_true(
    units.owned_wire_bytes >= provider.limits.page.max_bytes.to_int64(),
  )
  assert_true(@rows.discard_relation_document_original(document))
}

///|
test "Native file listing canonical version keeps the full admitted raw byte boundary" {
  let (provider, document, _) = file_listing_page_fixture()
  let target = @rows.project_relation_target_document(
    document,
    provider.declaration,
    provider.selection.resource,
    provider.selection.items_path,
    None,
    "id",
    [],
    prepared_contract=Some(provider.prepared_contract),
  ).unwrap()
  let row = @rows.observe_relation_target(target, provider.declaration, "first").unwrap()
  // Independently authored canonical JSON/SHA-256 vectors, not product output.
  assert_eq(
    @rows.relation_target_version(row),
    Some(
      "sha256:7a175e90b1ae4fbf0980e70a2fd9feb2039b8f31634e1bd4a3e32eee81c34a7c",
    ),
  )
  assert_eq(
    file_listing_row_version(row, "version", provider.limits.page),
    Some(
      "sha256:6df0c833b85e3417b5b3ba80ac25b48da0b2fc09287c54015e6e76d34c141b3a",
    ),
  )
  assert_true(@rows.discard_relation_target_row_original(row))
  assert_true(@rows.discard_relation_target_document_original(target))
  assert_true(@rows.discard_relation_document_original(document))
  let prefix = "{\"items\":[{\"id\":\"x\",\"name\":\"\",\"version\":\""
  let suffix = "\",\"media_type\":\"\",\"body\":\"\",\"path\":null}]}"
  let body = @utf8.encode(
    prefix +
    "x".repeat(
      provider.limits.page.max_bytes - prefix.length() - suffix.length(),
    ) +
    suffix,
  )
  assert_eq(body.length(), provider.limits.page.max_bytes)
  let raw = @rows.admit_relation_document(
    body,
    provider.limits.page,
    provider.limits.max_work,
  ).unwrap()
  let projected = @rows.project_relation_target_document(
    raw,
    provider.declaration,
    provider.selection.resource,
    provider.selection.items_path,
    None,
    "id",
    [],
    prepared_contract=Some(provider.prepared_contract),
  ).unwrap()
  let full = @rows.observe_relation_target(projected, provider.declaration, "x").unwrap()
  assert_true(
    file_listing_row_version(full, "version", provider.limits.page) is Some(_),
  )
  assert_true(@rows.discard_relation_target_row_original(full))
  assert_true(@rows.discard_relation_target_document_original(projected))
  assert_true(@rows.discard_relation_document_original(raw))
}
