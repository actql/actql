///|
// Fresh authored request fields on the existing Source/Effect fixture. The
// original declaration generator builds inputs, never publication expectations.
fn canonical_source_request_test_declaration(
  connector : String,
) -> @row_host.RowDeclaration {
  let registration = if connector == "crm/main" {
    "fixture_main"
  } else {
    "fixture_right"
  }
  match
    @row_host.generate_relation_row_declaration(
      connector,
      registration,
      registration + "/0.1",
      [
        {
          resource: "r",
          resource_kind: "record",
          schema_wire: "{\"amount\":{\"nullable\":true,\"type\":\"number\"},\"id\":{\"nullable\":false,\"type\":\"number\"}}",
          schema_cid: "sha256:bfa97ad45a64359561649b04e9e23326736ce2c4eefa22d6ac95dc112984093c",
          request_schema_wire: Some(
            "{\"additional_properties\":false,\"fields\":{\"a\":{\"nullable\":true,\"type\":\"string\"},\"z\":{\"nullable\":true,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}",
          ),
          facts_wire: None,
          acquisition_wire: None,
        },
      ],
      {
        max_bytes: 1000000,
        max_nodes: 100000,
        max_depth: 100,
        max_views: 1,
        max_fields: 10,
      },
    ) {
    Ok(value) => value
    Err(Declaration(issue)) => {
      println(@debug.to_string(issue))
      abort("canonical Source declaration")
    }
    Err(_) => abort("canonical Source declaration contracts")
  }
}

///|
fn canonical_source_request_test_document(document : String) -> String {
  document
  .replace_all(
    old="\"resource\":\"r\"",
    new="\"resource\":\"r\",\"request\":{\"z\":7,\"a\":null}",
  )
  .replace(old=",\"view\":\"v\"", new="")
}

///|
fn canonical_source_request_test_environment() -> @checked.CheckEnvironment {
  try {
    let declarations = [
      canonical_source_request_test_declaration("crm/main"),
      canonical_source_request_test_declaration("crm/right"),
    ]
    guard @json.parse(bound_effect_source_environment) is Object(base) else {
      fail("original Source environment")
    }
    base.remove("evidence_bundle_cid") |> ignore
    // Keep the original Effect catalogue, Mapping and manifest. Replace only
    // the two Source declarations, including their own original schema/policy.
    guard base["connector_catalogs"] is Array(old) else { fail("catalogues") }
    let catalogs = old.filter(value => {
      match value {
        Object(fields) => fields["connector_id"] == @json.parse("\"crm\"")
        _ => false
      }
    })
    let contracts = []
    let views = []
    let schemas = []
    let capabilities = []
    for declaration in declarations {
      catalogs.push(@json.parse(declaration.catalog))
      for body in declaration.contracts {
        contracts.push(body)
      }
      for body in declaration.view_bodies {
        views.push(body)
      }
      let (schema, capability) = @row_host.row_declaration_evidence_members(
        declaration,
      )
      for body in schema {
        schemas.push(body)
      }
      for body in capability {
        capabilities.push(body)
      }
    }
    fn sorted(bodies : Array[String]) -> Json raise {
      let ordered = bodies.map(body => {
        let value = parse_plan_identity_value(body, 1000000, 100000, 100).unwrap()
        (
          @canonical.cid_value(value, 1000000, 100000, 100),
          @canonical.stringify_value(value, 1000000, 100000, 100),
        )
      })
      ordered.sort_by((a, b) => a.0.compare(b.0))
      let unique : Array[(String, String)] = []
      for entry in ordered {
        if !unique.any(previous => previous.0 == entry.0) {
          unique.push(entry)
        }
      }
      @json.parse("[" + unique.map(value => value.1).join(",") + "]")
    }
    guard base["connector_manifest"] is Object(manifest) &&
      manifest["connectors"] is Array(old_entries) else {
      fail("original manifest")
    }
    let entries = old_entries.filter(value => {
      match value {
        Object(fields) => fields["connector_id"] == @json.parse("\"crm\"")
        _ => false
      }
    })
    for declaration in declarations {
      entries.push(@json.parse(declaration.manifest_entry))
    }
    manifest["connectors"] = sorted(entries.map(value => value.stringify()))
    base["connector_catalogs"] = sorted(
      catalogs.map(value => value.stringify()),
    )
    base["contract_registry"] = sorted(contracts)
    base["source_views"] = sorted(views)
    base["schema_snapshots"] = sorted(schemas)
    base["connector_capabilities"] = sorted(capabilities)
    let unsigned = parse_plan_identity_value(
      Json::object(base).stringify(),
      1000000,
      100000,
      100,
    ).unwrap()
    let cid = @canonical.cid_value(unsigned, 1000000, 100000, 100)
    let wire = @canonical.stringify_value(
      @canonical.object_with_string_field(unsigned, "evidence_bundle_cid", cid).unwrap(),
      1000000,
      100000,
      100,
    )
    let admitted = match
      @environment.read(@utf8.encode(wire), cid, {
        max_bytes: 65536,
        max_nodes: 4096,
        max_depth: 64,
        max_members: 256,
      }) {
      Ok(value) => value
      Err(issue) => {
        println(@debug.to_string(issue))
        abort("canonical Source environment admission")
      }
    }
    admit_client_check_environment_from_wire(
      admitted,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    ).unwrap()
  } catch {
    _ => abort("canonical Source authored environment")
  }
}

///|
fn assert_canonical_source_request_test_body(
  document : @encode.EncodedDocument,
  cid : String,
) -> Unit raise {
  assert_eq(@encode.document_text(document), "{\"a\":null,\"z\":7}")
  assert_eq(
    cid, "sha256:1344e3f27322825f05b46d7fba21c95001899fd297e9000ad0b3ba15c5f553c8",
  )
  assert_true(
    @publication.admit_hashed_effect_dependency_body(
      "request_values",
      cid,
      @encode.document_text(document),
      100000,
      10000,
      100,
    )
    is Ok(_),
  )
}

///|
test "whole Source Unit publishes canonical Request without moving original fields" {
  let (compilation, _, _, _, _) = bound_effect_source_fixture(
    canonical_request=true,
  )
  let prepared = client_effect_compilation_owner(compilation)
  let source = combined_unit_whole_capture(prepared, Ref(true), 0)
  let direct = select_client_effect_direct_acquisition_occurrences(
    prepared, 1000000,
  ).unwrap()
  let request = @acquisition.source_acquisition_request(source.2)
  let first = @acquisition.parameterized_request_field_at(request, 0).unwrap()
  let second = @acquisition.parameterized_request_field_at(request, 1).unwrap()
  assert_eq(
    @acquisition.parameterized_request_wire(request, 100000, 10000, 100).unwrap(),
    "{\"z\":7,\"a\":null}",
  )
  let acquired = issue_client_whole_native_effect_source_unit(
    prepared,
    direct,
    0,
    source.0,
    source.1,
    source.2,
    source.4,
    source.3,
    "sha256:" + "a".repeat(64),
    product_expiry_original_retention(product_test_originals()),
    100000,
    10000,
    100,
  ).unwrap()
  assert_canonical_source_request_test_body(
    acquired.request,
    acquired.request_cid,
  )
  assert_true(
    physical_equal(
      first,
      @acquisition.parameterized_request_field_at(request, 0).unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      second,
      @acquisition.parameterized_request_field_at(request, 1).unwrap(),
    ),
  )
}

///|
test "whole Request ordering scratch is admitted on its original Source before construction" {
  let (compilation, _, _, _, _) = bound_effect_source_fixture(
    canonical_request=true,
  )
  let prepared = client_effect_compilation_owner(compilation)
  let graph = @strategy.checked_effect_computation_graph(prepared.graph)
  let owner = @strategy.graph_task_owner(graph, 0).unwrap()
  let original = prepare_client_effect_source_acquisition(prepared, 0, 0).unwrap()
  let declaration = canonical_source_request_test_declaration("crm/main")
  let sequence = @lower.prepare_sequence(owner, run_materials_limits().sequence).unwrap()
  let selected = @row_host.prepare_row_input_acquisition(
    original,
    @checked.source_identity(@strategy.graph_program(graph)),
    sequence,
    whole_source_capture_contracts(),
    declaration,
    {
      max_rows: 1,
      page: { max_bytes: 20000, max_nodes: 1000, max_depth: 20, max_rows: 1, },
      retention: {
        max_nodes: 10000,
        max_text_bytes: 20000,
        max_depth: 20,
        max_work: 1000000,
      },
      wire: {
        max_columns: 2,
        max_order_work: 10000,
        max_bytes: 20000,
        max_nodes: 10000,
        max_depth: 20,
      },
    },
  ).unwrap()
  let capacity = @row_host.row_input_acquisition_capacity(selected, None).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let execution = @execution.execution_capacity_execution_bytes(capacity)
  for fits in [false, true] {
    let ledger = @resources.create_ledger({
      planning_work: 100,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 20000L,
      retained_bytes: retained - (if fits { 0L } else { 1L }),
      execution_bytes: execution + 20000L,
    }).unwrap()
    let callbacks = Ref(0)
    let result = @row_host.start_accounted_row_input_acquisition(
      selected,
      None,
      "canonical-original-request",
      _ => {
        callbacks.val += 1
        true
      },
      ledger,
      20000L,
      20000L,
    )
    // Resource refusal/constructor admission precedes any provider callback.
    assert_eq(callbacks.val, 0)
    if fits {
      let run = result.unwrap()
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        retained,
      )
      @row_host.close_accounted_row_run(run).unwrap()
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    } else {
      assert_true(result is Err(Physical(RetentionLimit)))
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    }
  }
}
