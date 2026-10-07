///|
fn reference_snapshot_contract(resource : Bool) -> @value_contract.Contract {
  @value_contract.read_checked(
    input_cursor(
      if resource {
        "{\"nullable\":false,\"resource_kind\":\"Issue\",\"type\":\"resource_ref\"}"
      } else {
        "{\"media_type\":\"text/plain\",\"nullable\":false,\"type\":\"artifact_ref\"}"
      },
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
}

///|
fn reference_snapshot_wire(resource : Bool) -> String {
  if resource {
    "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:" +
    "1".repeat(64) +
    "\",\"boundary_cid\":\"sha256:" +
    "2".repeat(64) +
    "\",\"identity_cid\":\"sha256:" +
    "4".repeat(64) +
    "\",\"provider_identity_cid\":\"sha256:" +
    "3".repeat(64) +
    "\",\"provider_namespace\":\"fixture\",\"resource_kind\":\"Issue\",\"version\":\"actql-resource-ref/0.1\"}"
  } else {
    "{\"$actql_ref\":\"artifact\",\"artifact_ref_cid\":\"sha256:" +
    "5".repeat(64) +
    "\",\"media_type\":\"text/plain\",\"metadata\":{},\"version\":\"actql-artifact-ref/0.1\"}"
  }
}

///|
fn reference_snapshot_source_owner(resource_key : Bool) -> @lower.BoundPrepared {
  let program = @syntax.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"a\",\"inputs\":{\"source\":{\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{\"select\":[\"key\",\"property\"]}],\"results\":{\"r\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}",
    {
      source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
      tree: {
        max_nodes: 100000,
        max_depth: 100,
        max_string_bytes: 1000000,
        max_total_string_bytes: 1000000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let source = @stages.prepare(program, {
    max_parameters: 100,
    max_nodes: 100,
    max_depth: 100,
    max_text_bytes: 1000,
  }).unwrap()
  let inputs = @source_inputs.collect(source, {
    max_work: 1000000,
    max_order_keys: 100,
  }).unwrap()
  let resolved = @acquisition.resolve(
    inputs,
    reference_snapshot_catalog(resource_key),
    { max_work: 1000000, max_inputs: 100, max_views: 100, },
  ).unwrap()
  let registered = @acquisition.prepare_pipeline_inputs(resolved, 1000000).unwrap()
  let body = @decode.open_object(
    @syntax.stage_body(@stages.stage_at(source, 0).unwrap()),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    @decode.required(body, "steps").unwrap(),
    [@acquisition.pipeline_input_at(registered, 0, 0).unwrap()],
    Some(@stages.declarations(source)),
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn reference_snapshot_graph_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      (
        #|[{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"property","to":"property"}]}}]}],"edges":[]},"as":"g"}]
      ),
    ),
    [
      (
        "nodes",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn reference_snapshot_source(
  owner : @lower.BoundPrepared,
  key : @admitted.CheckedValue,
  property : @admitted.CheckedValue,
) -> @execution.CompletedOutput raise {
  let output = @execution.prepare_admitted_output(owner, @pipeline.Step(0), 1, {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }).unwrap()
  @execution.append_admitted_output(output, [key, property]).unwrap()
  let rows = @execution.finish_admitted_output(output).unwrap()
  let port = @execution.prepare_trusted_output_port(
    task_test_completion(owner),
    @pipeline.Step(0),
    1000,
    10000,
    (proof : @execution.AdmittedOutputRows) => {
      if physical_equal(proof, rows) {
        Some(rows)
      } else {
        None
      }
    },
  ).unwrap()
  @execution.complete_trusted_output(port, rows).unwrap()
}

///|
fn reference_snapshot_provider(
  generated : @execution.GeneratedSequence,
  issuer : @admitted.ReferenceIssuer?,
) -> @local_connector.ManagedProvider {
  @local_sga_provider.provider(
    {
      ..carrier_graph_storage_limits(),
      max_value_bytes: 10000,
      max_total_value_bytes: 10000,
      max_retained_value_bytes: 10000,
      max_value_nodes: 10000,
      max_work: 100000,
    },
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
    snapshot_policy=Some({
      serialization: snapshot_caps(),
      read: {
        max_nodes: 10000,
        max_depth: 100,
        max_string_bytes: 100000,
        max_total_string_bytes: 100000,
      },
      maximum_bytes: 100000,
      maximum_frame_bytes: 100000,
      workspace_bytes: 1000000L,
    }),
    reference_issuer=issuer,
  )
}

///|
fn reference_snapshot_complete(
  active : @local_connector.ManagedProviderExecution,
) -> @carrier_runtime.Material raise {
  for _ in 0..<10000 {
    match @local_connector.advance_managed_provider(active, 7).unwrap() {
      @local_connector.Continue(..) => ()
      @local_connector.CarrierComplete(material, ..) => return material
      _ => fail("reference Graph provider did not complete")
    }
  }
  fail("reference Graph provider exceeded fixture bound")
}

///|
fn reference_snapshot_assert_value(
  actual : @admitted.CheckedValue,
  expected : @admitted.CheckedValue,
) -> Unit raise {
  guard actual.value is @admitted.Reference(restored) &&
    expected.value is @admitted.Reference(original) else {
    fail("snapshot lost its reference value")
  }
  assert_true(@admitted.reference_same_issuer(original, restored))
  assert_eq(
    @admitted.reference_wire(restored),
    @admitted.reference_wire(original),
  )
  assert_eq(
    @admitted.reference_identity_cid(restored),
    @admitted.reference_identity_cid(original),
  )
  assert_true(@admitted.reference_available(restored))
}

///|
// Every case runs through the installed provider and its exact material factory.
// Swapping key/property domains covers both opaque reference types in each role.
fn reference_snapshot_provider_case(
  resource_key : Bool,
  normalized : Bool,
  mode : Int,
) -> Unit raise {
  let current = Ref(true)
  let issuer = @admitted.bind_reference_issuer(
    (_, wire) => {
      wire == reference_snapshot_wire(true) ||
      wire == reference_snapshot_wire(false)
    },
    _ => current.val,
  )
  let source_owner = reference_snapshot_source_owner(resource_key)
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let issue = fn(column, resource) {
    @admitted.issue_reference(
      issuer,
      @schema.field_at(schema, column).unwrap().contract,
      reference_snapshot_wire(resource),
      { max_bytes: 1000, max_nodes: 100, max_depth: 10, max_text_units: 1000, },
    ).unwrap()
  }
  let key = issue(0, resource_key)
  let property = issue(1, !resource_key)
  // A capable foreign Host authorizes only its own independent scope. Matching
  // Graph schema and snapshot CID cannot grant authority for the saved refs.
  let foreign_wire = "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:" +
    "a".repeat(64) +
    "\",\"boundary_cid\":\"sha256:" +
    "b".repeat(64) +
    "\",\"identity_cid\":\"sha256:" +
    "c".repeat(64) +
    "\",\"provider_identity_cid\":\"sha256:" +
    "d".repeat(64) +
    "\",\"provider_namespace\":\"foreign\",\"resource_kind\":\"Issue\",\"version\":\"actql-resource-ref/0.1\"}"
  let foreign = @admitted.bind_reference_issuer(
    (_, wire) => wire == foreign_wire,
    _ => true,
  )
  assert_true(
    @admitted.issue_reference(
      foreign,
      reference_snapshot_contract(true),
      foreign_wire,
      { max_bytes: 1000, max_nodes: 100, max_depth: 10, max_text_units: 1000, },
    )
    is Ok(_),
  )
  let reissuer = @admitted.bind_reference_reissuer((required, wire) => {
    for value in [key, property] {
      if value.value is @admitted.Reference(reference) &&
        @admitted.reference_wire(reference) == wire &&
        @admitted.reference_compatible(reference, required) {
        return Some(reference)
      }
    }
    None
  })
  let installed = if mode == 1 {
    None
  } else if mode == 2 {
    Some(foreign)
  } else if mode == 5 {
    Some(reissuer)
  } else {
    Some(issuer)
  }
  let source = reference_snapshot_source(source_owner, key, property)
  let graph_owner = reference_snapshot_graph_owner(source_owner)
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(graph_owner),
    0,
  ).unwrap()
  let input = @execution.prepare_producer_read(
    graph_owner,
    @execution.bind_completed_input(graph_owner, 0, source_owner, source).unwrap(),
    1000,
    10000,
  ).unwrap()
  let constructing = @local_connector.start_managed_provider_with_inputs(
    reference_snapshot_provider(generated, installed),
    generated,
    [@local_connector.managed_provider_relation_input(input)],
    10,
    10000,
  ).unwrap()
  let constructed = reference_snapshot_complete(constructing)
  let (owner, material, normalizing) = if normalized {
    let receiver = keyed_graph_receiver(
      graph_owner,
      body="[{\"from\":\"g\",\"normalize_graph\":true,\"as\":\"normalized\"}]",
    )
    let selected = @execution.select_generated_sequence_step(
      task_test_generated(receiver),
      0,
    ).unwrap()
    let view = @carrier_runtime.material_prepare_view(
      constructed, receiver, 0, graph_owner,
    ).unwrap()
    let active = @local_connector.start_managed_provider_with_inputs(
      reference_snapshot_provider(selected, installed),
      selected,
      [@local_connector.managed_provider_carrier_input(view)],
      10,
      10000,
    ).unwrap()
    (receiver, reference_snapshot_complete(active), Some(active))
  } else {
    (graph_owner, constructed, None)
  }
  let consumer = keyed_graph_receiver(owner)
  let before = @carrier_runtime.material_prepare_view(
    material, consumer, 0, owner,
  ).unwrap()
  reference_snapshot_assert_value(
    @carrier_runtime.producer_view_node_key(before, 0, 0).unwrap(),
    key,
  )
  reference_snapshot_assert_value(
    @carrier_runtime.producer_view_node_property(before, 0, 0).unwrap(),
    property,
  )
  let operation = @carrier_runtime.material_prepare_snapshot(material)
    .unwrap()
    .unwrap()
  let saved = StringBuilder()
  let mut saved_complete = false
  for _ in 0..<10000 {
    let advanced = (operation.advance_save)(7).unwrap()
    saved.write_string((operation.take_output)().unwrap())
    if advanced.complete {
      saved_complete = true
      break
    }
  }
  assert_true(saved_complete)
  let content = (operation.content)().unwrap()
  (operation.release_source)(content.cid).unwrap()
  assert_false(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.producer_view_node_count(before) is None)
  if mode == 3 {
    current.val = false
  }
  // Cleanup releases only provider scratch. The material factory retains the
  // exact Host capability needed after the provider's own handle is cleared.
  assert_true(@local_connector.cleanup_managed_provider(constructing).unwrap())
  if normalizing is Some(active) {
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  }
  (operation.begin_reload)(saved.to_string(), () => true).unwrap()
  if mode == 4 {
    let partial = (operation.advance_reload)(1).unwrap()
    assert_false(partial.complete)
    assert_true(partial.issue is None)
    @carrier_runtime.reclaim_material(material) |> ignore
    assert_false(@carrier_runtime.material_cleanup_pending(material))
    assert_true((operation.take_material)() is Err(_))
    @carrier_runtime.reclaim_material(material) |> ignore
    assert_false(@carrier_runtime.material_cleanup_pending(material))
    assert_true(@execution.producer_read_available(input))
    if normalized {
      assert_true(@carrier_runtime.material_available(constructed))
      @carrier_runtime.reclaim_material(constructed) |> ignore
    }
    return
  }

  let mut completed = false
  let mut failure = None
  for _ in 0..<10000 {
    let advanced = (operation.advance_reload)(7).unwrap()
    if advanced.issue is Some(issue) {
      failure = Some(issue)
      break
    }
    if advanced.complete {
      completed = true
      break
    }
  }
  if mode == 0 || mode == 5 {
    assert_true(
      failure is None,
      msg="installed material factory lost the current Host issuer",
    )
    assert_true(completed)
    let restored = (operation.take_material)().unwrap()
    @carrier_runtime.reclaim_material(material) |> ignore
    assert_false(@carrier_runtime.material_cleanup_pending(material))
    assert_true(
      @local_connector.cleanup_managed_provider(constructing).unwrap(),
    )
    if normalizing is Some(active) {
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_true(@carrier_runtime.material_available(constructed))
    }
    let view = @carrier_runtime.material_prepare_view(
      restored, consumer, 0, owner,
    ).unwrap()
    assert_eq(@carrier_runtime.producer_view_node_count(view), Some(1))
    assert_eq(@carrier_runtime.producer_view_edge_count(view), Some(0))
    reference_snapshot_assert_value(
      @carrier_runtime.producer_view_node_key(view, 0, 0).unwrap(),
      key,
    )
    reference_snapshot_assert_value(
      @carrier_runtime.producer_view_node_property(view, 0, 0).unwrap(),
      property,
    )
    current.val = false
    guard key.value is @admitted.Reference(original) else { fail("reference") }
    assert_false(@admitted.reference_available(original))
    guard @carrier_runtime.producer_view_node_key(view, 0, 0).unwrap().value
      is @admitted.Reference(revoked) else {
      fail("restored reference")
    }
    assert_false(@admitted.reference_available(revoked))
    @carrier_runtime.reclaim_material(restored) |> ignore
    assert_false(@carrier_runtime.material_available(restored))
  } else {
    assert_false(completed)
    assert_true(failure is Some(@carrier_runtime.SnapshotFamilyFailure(_)))
    assert_true((operation.take_material)() is Err(_))
    @carrier_runtime.reclaim_material(material) |> ignore
    assert_false(@carrier_runtime.material_cleanup_pending(material))
    assert_true(
      @local_connector.cleanup_managed_provider(constructing).unwrap(),
    )
    if normalizing is Some(active) {
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    }
  }
  // Provider cleanup never takes borrowed input custody, including failed reloads.
  current.val = true
  assert_true(@execution.producer_read_available(input))
  if normalized {
    @carrier_runtime.reclaim_material(constructed) |> ignore
  }
}

///|
test "Graph constructor snapshot preserves current resource and artifact key property issuers" {
  for resource_key in [true, false] {
    reference_snapshot_provider_case(resource_key, false, 0)
  }
}

///|
test "Graph normalize snapshot preserves current resource and artifact key property issuers" {
  for resource_key in [true, false] {
    reference_snapshot_provider_case(resource_key, true, 0)
  }
}

///|
test "Graph snapshot material rejects missing and foreign Host reference authority" {
  for normalized in [false, true] {
    for mode in [1, 2] {
      reference_snapshot_provider_case(true, normalized, mode)
    }
  }
}

///|
test "Graph snapshot material rechecks revoked Host authority after releasing its source" {
  for normalized in [false, true] {
    reference_snapshot_provider_case(false, normalized, 3)
  }
}

///|
test "Graph snapshot material retains the exact Host reissuer after provider cleanup" {
  for normalized in [false, true] {
    reference_snapshot_provider_case(true, normalized, 5)
  }
}

///|
test "Graph reference reload cleanup releases partial output without reclaiming borrowed inputs" {
  for normalized in [false, true] {
    reference_snapshot_provider_case(false, normalized, 4)
  }
}
