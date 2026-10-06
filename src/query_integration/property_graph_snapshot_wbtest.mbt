///|
fn snapshot_fixture_schema() -> String {
  (
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"R":[]},"name":"E","properties":{},"source_definition":"N","target_definition":"N"}],"identity_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","node_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":["name"],"Person":[]},"name":"N","properties":{"name":{"nullable":true,"type":"string"}}}],"value_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","version":"actql-property-graph-contract/0.1"}
  )
}

///|
fn snapshot_fixture_identity(definition : String, key : Int) -> String {
  "{\"definition\":\"" +
  definition +
  "\",\"domain\":\"sha256:" +
  "0".repeat(64) +
  "\",\"key\":[" +
  key.to_string() +
  "],\"key_types\":[{\"kind\":\"number\"}]}"
}

///|
fn snapshot_fixture_body(keys? : Array[Int] = [10, 11]) -> String {
  let node = snapshot_fixture_identity("N", 1)
  let edges = keys.map(key => {
    "{\"dst\":" +
    node +
    ",\"id\":" +
    snapshot_fixture_identity("E", key) +
    ",\"key\":[" +
    key.to_string() +
    "],\"props\":{},\"src\":" +
    node +
    "}"
  })
  "[\"actql-property-graph-snapshot/0.1\",\"sha256:6a0fe1664c431e3b0835ccaf2fff3569e99492ae427eab4ccb65d34096ce604d\"," +
  snapshot_fixture_schema() +
  ",[{\"id\":" +
  node +
  ",\"key\":[1],\"props\":{\"name\":\"one\"}}],[" +
  edges.join(",") +
  "]]"
}

///|
fn snapshot_fixture_cid() -> String {
  // SHA-256 of the independently authored canonical fixture, computed with
  // Node crypto separately from the implementation's encoder/hash function.
  "sha256:8d1360c290b9f6d48863bb6efb464b688506bae9751a10f257184723e9f69bd6"
}

///|
fn snapshot_material_fixture(
  control : @bounded.Control,
  owner : @lower.BoundPrepared,
  source : @graphs.Completed,
  maximum_bytes? : Int = 100000,
  maximum_frame_bytes? : Int = 100000,
) -> @carrier_runtime.Material {
  @local_bridge.completed_property_snapshot_material(
    control,
    owner,
    @pipeline.Input(0),
    source,
    carrier_graph_storage_limits(),
    snapshot_caps(),
    {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
    maximum_bytes,
    maximum_frame_bytes,
    1000000L,
    () => true,
  ).unwrap()
}

///|
test "material snapshot port transfers only the verified restored generation" {
  let owner = snapshot_fixture_owner()
  let source = snapshot_handoff_source(owner)
  let material = snapshot_material_fixture(@bounded.control(), owner, source)
  let operation = @carrier_runtime.material_prepare_snapshot(material)
    .unwrap()
    .unwrap()
  assert_true(
    @carrier_runtime.material_prepare_snapshot(material)
    is Err(@carrier_runtime.SnapshotAlreadyClaimed),
  )
  assert_true((operation.content)() is Err(_))
  let saved = StringBuilder()
  let mut complete = false
  for _ in 0..<1000 {
    let advanced = (operation.advance_save)(1).unwrap()
    saved.write_string((operation.take_output)().unwrap())
    if advanced.complete {
      complete = true
      break
    }
  }
  assert_true(complete)
  let content = (operation.content)().unwrap()
  assert_eq(content.cid, snapshot_fixture_cid())
  assert_eq(saved.to_string(), snapshot_fixture_body())
  assert_true((operation.begin_reload)(saved.to_string(), () => true) is Err(_))
  (operation.release_source)(content.cid).unwrap()
  assert_false(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.material_cleanup_pending(material))
  (operation.begin_reload)(saved.to_string(), () => true).unwrap()
  complete = false
  for _ in 0..<1000 {
    if (operation.advance_reload)(1).unwrap().complete {
      complete = true
      break
    }
  }
  assert_true(complete)
  let restored = (operation.take_material)().unwrap()
  assert_true(@carrier_runtime.material_available(restored))
  assert_false(
    @carrier_runtime.completion_reference_same(
      @carrier_runtime.material_reference(restored),
      @carrier_runtime.material_reference(material),
    ),
  )
  assert_true((operation.take_material)() is Err(_))
  @carrier_runtime.reclaim_material(material) |> ignore
  assert_false(@carrier_runtime.material_cleanup_pending(material))
  @carrier_runtime.reclaim_material(material) |> ignore
  assert_true(@carrier_runtime.material_available(restored))
  assert_true(@carrier_runtime.reclaim_material(restored))
}

///|
test "material snapshot byte limit refuses save without completing or dropping custody" {
  let owner = snapshot_fixture_owner()
  let source = snapshot_handoff_source(owner)
  let material = snapshot_material_fixture(
    @bounded.control(),
    owner,
    source,
    maximum_bytes=1,
    maximum_frame_bytes=1,
  )
  let operation = @carrier_runtime.material_prepare_snapshot(material)
    .unwrap()
    .unwrap()
  (operation.advance_save)(1).unwrap() |> ignore
  assert_true(
    (operation.take_output)() is Err(@carrier_runtime.SnapshotByteLimit),
  )
  assert_true(
    (operation.advance_save)(1) is Err(@carrier_runtime.SnapshotByteLimit),
  )
  assert_true((operation.content)() is Err(_))
  assert_true(@graphs.completed_available(source))
  assert_true(
    @carrier_runtime.material_prepare_snapshot(material)
    is Err(@carrier_runtime.SnapshotAlreadyClaimed),
  )
  @carrier_runtime.reclaim_material(material) |> ignore
  assert_false(@carrier_runtime.material_cleanup_pending(material))
  assert_false(@graphs.completed_available(source))
  @carrier_runtime.reclaim_material(material) |> ignore
}

///|
test "material snapshot terminal failure preserves reported work and cannot publish a partial Graph" {
  for cancel_save in [true, false] {
    let owner = snapshot_fixture_owner()
    let source = snapshot_handoff_source(owner)
    let control = @bounded.control()
    let material = snapshot_material_fixture(control, owner, source)
    let operation = @carrier_runtime.material_prepare_snapshot(material)
      .unwrap()
      .unwrap()
    let first = (operation.advance_save)(1).unwrap()
    assert_eq(first.work, 1L)
    assert_true(first.issue is None)
    let saved = StringBuilder()
    saved.write_string((operation.take_output)().unwrap())
    if cancel_save {
      @bounded.request_cancel(control) |> ignore
      let stopped = (operation.advance_save)(1).unwrap()
      assert_eq(stopped.work, first.work)
      assert_true(stopped.issue is Some(@carrier_runtime.SnapshotUnavailable))
      assert_false(stopped.complete)
      assert_true((operation.content)() is Err(_))
      assert_true((operation.take_material)() is Err(_))
    } else {
      let mut saved_complete = false
      for _ in 0..<1000 {
        let advanced = (operation.advance_save)(1).unwrap()
        saved.write_string((operation.take_output)().unwrap())
        assert_true(advanced.issue is None)
        if advanced.complete {
          saved_complete = true
          break
        }
      }
      assert_true(saved_complete)
      (operation.release_source)((operation.content)().unwrap().cid).unwrap()
      (operation.begin_reload)(
        saved.to_string().replace(old="\"one\"", new="\"two\""),
        () => true,
      ).unwrap()
      let mut last_work = 0L
      let mut failed = false
      for _ in 0..<1000 {
        let advanced = (operation.advance_reload)(1).unwrap()
        assert_true(advanced.work >= last_work)
        assert_true(advanced.work - last_work <= 1L)
        last_work = advanced.work
        if advanced.issue is Some(@carrier_runtime.SnapshotFamilyFailure(_)) {
          assert_false(advanced.complete)
          failed = true
          break
        }
        assert_false(advanced.complete)
      }
      assert_true(failed)
      assert_true(last_work > 0L)
      assert_true((operation.take_material)() is Err(_))
    }
    @carrier_runtime.reclaim_material(material) |> ignore
    assert_false(@carrier_runtime.material_cleanup_pending(material))
    @carrier_runtime.reclaim_material(material) |> ignore
    assert_false(@graphs.completed_available(source))
  }
}

///|
fn snapshot_handoff_source(owner : @lower.BoundPrepared) -> @graphs.Completed {
  let active = snapshot_start(owner, snapshot_fixture_body()).unwrap()
  guard snapshot_terminal(active) is @local_bridge.Complete(output, ..) else {
    abort("initial snapshot fixture")
  }
  @local_bridge.cleanup_rows_to_graph(active).unwrap() |> ignore
  output
}

///|
fn snapshot_handoff_save(
  value : @local_bridge.PropertySnapshotHandoff,
) -> (String, String) raise {
  let text = StringBuilder()
  let mut previous_work = 0L
  for _ in 0..<1000 {
    let poll = @local_bridge.advance_property_snapshot_save(value, 1).unwrap()
    text.write_string(
      @local_bridge.take_property_snapshot_save_output(value).unwrap(),
    )
    match poll {
      @local_bridge.Saving(work~, ..) => {
        assert_eq(work - previous_work, 1L)
        previous_work = work
      }
      @local_bridge.Saved(cid, work~, ..) => {
        assert_eq(work - previous_work, 1L)
        return (cid, text.to_string())
      }
      _ => abort("saving must complete")
    }
  }
  abort("bounded fixture must finish")
}

///|
test "snapshot handoff saves exact bytes and revokes the original before restoring a distinct completion" {
  let owner = snapshot_fixture_owner()
  let source = snapshot_handoff_source(owner)
  let old_material = @graphs.completed_material(source).unwrap()
  let control = @bounded.control()
  let handoff = @local_bridge.prepare_property_snapshot_handoff(
    control,
    owner,
    @pipeline.Input(0),
    source,
    carrier_graph_storage_limits(),
    snapshot_caps(),
    1000,
    () => true,
  ).unwrap()
  assert_true(
    @local_bridge.release_property_snapshot_source(
      handoff,
      snapshot_fixture_cid(),
    )
    is Err(_),
  )
  assert_true(@graphs.completed_available(source))
  let (cid, body) = snapshot_handoff_save(handoff)
  assert_eq((cid, body), (snapshot_fixture_cid(), snapshot_fixture_body()))
  assert_true(
    @local_bridge.release_property_snapshot_source(
      handoff,
      "sha256:" + "1".repeat(64),
    )
    is Err(_),
  )
  assert_true(@graphs.completed_available(source))
  @local_bridge.release_property_snapshot_source(handoff, cid).unwrap()
  assert_false(@graphs.completed_available(source))
  assert_false(@carrier_runtime.material_available(old_material))
  assert_true(@graphs.completed_storage(source) is None)
  assert_true(@local_bridge.take_property_snapshot_restored(handoff) is Err(_))
  @local_bridge.start_property_snapshot_handoff_reload(
    handoff,
    input_cursor(body),
    () => true,
  ).unwrap()
  let mut finished = false
  for _ in 0..<1000 {
    match
      @local_bridge.advance_property_snapshot_handoff_reload(handoff, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(_, ..) => {
        finished = true
        break
      }
      _ => fail("restoration")
    }
  }
  assert_true(finished)
  let restored = @local_bridge.take_property_snapshot_restored(handoff).unwrap()
  assert_true(@local_bridge.take_property_snapshot_restored(handoff) is Err(_))
  assert_false(
    @carrier_runtime.completion_reference_same(
      @carrier_runtime.material_reference(old_material),
      @graphs.completed_carrier_reference(restored),
    ),
  )
  assert_eq(
    snapshot_capture(@graphs.completed_storage(restored).unwrap()),
    (cid, body),
  )
  assert_true(@local_bridge.cleanup_property_snapshot_handoff(handoff).unwrap())
  assert_false(
    @local_bridge.cleanup_property_snapshot_handoff(handoff).unwrap(),
  )
  assert_true(@graphs.completed_available(restored))
  // Successful cleanup does not poison the shared bounded control. Subsequent
  // consumption of the restored generation remains possible under that owner.
  assert_true(@bounded.request_cancel(control))
  assert_true(@graphs.discard_completed(restored))
}

///|
test "snapshot handoff refuses equal-schema foreign owners and preserves cleanup on cancelled saving" {
  let owner = snapshot_fixture_owner()
  let foreign = snapshot_fixture_owner()
  let source = snapshot_handoff_source(owner)
  assert_true(
    @local_bridge.prepare_property_snapshot_handoff(
      @bounded.control(),
      foreign,
      @pipeline.Input(0),
      source,
      carrier_graph_storage_limits(),
      snapshot_caps(),
      1000,
      () => true,
    )
    is Err(@local_bridge.GraphInputUnavailable),
  )
  assert_true(@graphs.completed_available(source))
  let control = @bounded.control()
  let handoff = @local_bridge.prepare_property_snapshot_handoff(
    control,
    owner,
    @pipeline.Input(0),
    source,
    carrier_graph_storage_limits(),
    snapshot_caps(),
    1000,
    () => true,
  ).unwrap()
  assert_true(
    @local_bridge.advance_property_snapshot_save(handoff, 1).unwrap()
    is @local_bridge.Saving(work=1L, ..),
  )
  @bounded.request_cancel(control) |> ignore
  assert_true(
    @local_bridge.advance_property_snapshot_save(handoff, 1).unwrap()
    is @local_bridge.SaveStopped(@bounded.Cancelled, work=1L, ..),
  )
  assert_true(
    @local_bridge.take_property_snapshot_save_output(handoff) is Err(_),
  )
  assert_true(
    @local_bridge.release_property_snapshot_source(
      handoff,
      snapshot_fixture_cid(),
    )
    is Err(_),
  )
  assert_true(@graphs.completed_available(source))
  assert_true(@local_bridge.cleanup_property_snapshot_handoff(handoff).unwrap())
  assert_false(@graphs.completed_available(source))
  assert_false(
    @local_bridge.cleanup_property_snapshot_handoff(handoff).unwrap(),
  )
}

///|
test "snapshot handoff keeps trusted schema and never hands off corrupted or interrupted reload" {
  for corrupted in [false, true] {
    let owner = snapshot_fixture_owner()
    let source = snapshot_handoff_source(owner)
    let control = @bounded.control()
    let handoff = @local_bridge.prepare_property_snapshot_handoff(
      control,
      owner,
      @pipeline.Input(0),
      source,
      carrier_graph_storage_limits(),
      snapshot_caps(),
      1000,
      () => true,
    ).unwrap()
    let (cid, body) = snapshot_handoff_save(handoff)
    @local_bridge.release_property_snapshot_source(handoff, cid).unwrap()
    assert_true(
      @local_bridge.start_property_snapshot_handoff_reload(
        handoff,
        input_cursor(body.replace(old="\"Person\":[]", new="\"Company\":[]")),
        () => true,
      )
      is Err(@local_bridge.GraphSnapshot(@snapshot.SnapshotContractMismatch)),
    )
    @local_bridge.start_property_snapshot_handoff_reload(
      handoff,
      input_cursor(
        if corrupted {
          body.replace(old="\"one\"", new="\"two\"")
        } else {
          body
        },
      ),
      () => true,
    ).unwrap()
    if !corrupted {
      @bounded.request_cancel(control) |> ignore
    }
    let mut stopped = false
    for _ in 0..<1000 {
      match
        @local_bridge.advance_property_snapshot_handoff_reload(handoff, 1).unwrap() {
        @local_bridge.Continue(..) => ()
        @local_bridge.Failed(
          @local_bridge.GraphSnapshot(@snapshot.SnapshotIdentityMismatch),
          ..
        ) if corrupted => {
          stopped = true
          break
        }
        @local_bridge.Stopped(@bounded.Cancelled, ..) if !corrupted => {
          stopped = true
          break
        }
        _ => fail("must reject or stop")
      }
    }
    assert_true(stopped)
    assert_true(
      @local_bridge.take_property_snapshot_restored(handoff) is Err(_),
    )
    assert_false(@graphs.completed_available(source))
    assert_true(
      @local_bridge.cleanup_property_snapshot_handoff(handoff).unwrap(),
    )
    assert_false(
      @local_bridge.cleanup_property_snapshot_handoff(handoff).unwrap(),
    )
  }
}

///|
fn snapshot_caps() -> @snapshot.Limits {
  {
    max_workspace_slots: 1000,
    max_identity_bytes: 100000,
    max_identity_nodes: 10000,
    max_identity_depth: 100,
    value_limits: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  }
}

///|
fn snapshot_fixture_owner() -> @lower.BoundPrepared {
  // This separately trusted schema is not extracted from received snapshot
  // data; changing that data cannot replace the expected domain or definition.
  let schema = @graph_contract.read_property_graph_cursor(
    input_cursor(snapshot_fixture_schema()),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
  ).unwrap()
  let checked = @pipeline.check_carriers(
    input_cursor("[]"),
    [
      (
        "g",
        @carrier_contract.graph_carrier(@graph_contract.property_graph(schema)),
      ),
    ],
    None,
    Some(input_cursor("\"g\"")),
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
fn snapshot_start(
  owner : @lower.BoundPrepared,
  body : String,
  control? : @bounded.Control = @bounded.control(),
  expected? : String = snapshot_fixture_cid(),
  limits? : @graph_storage.Limits = carrier_graph_storage_limits(),
  caps? : @snapshot.Limits = snapshot_caps(),
  live? : Ref[Bool] = Ref(true),
  control_work_limit? : Int? = None,
) -> Result[@local_bridge.RowsToGraphExecution, @local_bridge.GraphBridgeIssue] {
  @local_bridge.start_property_snapshot_reload(
    control,
    owner,
    @pipeline.Input(0),
    input_cursor(body),
    expected,
    limits,
    caps,
    4096L,
    1000,
    () => live.val,
    () => true,
    control_work_limit~,
  )
}

///|
fn snapshot_terminal(
  active : @local_bridge.RowsToGraphExecution,
  quantum? : Int = 1,
) -> @local_bridge.RowsToGraphPoll {
  for _ in 0..<1000 {
    match @local_bridge.advance_rows_to_graph(active, quantum).unwrap() {
      @local_bridge.Continue(..) => ()
      terminal => return terminal
    }
  }
  abort("snapshot restore must finish within its bounded fixture")
}

///|
fn snapshot_capture(storage : @graph_storage.Storage) -> (String, String) {
  let active = @snapshot.prepare_property(storage, snapshot_caps()).unwrap()
  let text = StringBuilder()
  for _ in 0..<1000 {
    let poll = @snapshot.advance(active, 1).unwrap()
    text.write_string(@snapshot.take_property_output(active).unwrap())
    match poll {
      @snapshot.Continue(..) => ()
      @snapshot.Complete(value, ..) => {
        let cid = @snapshot.cid(value)
        @snapshot.cleanup(value) |> ignore
        return (cid, text.to_string())
      }
    }
  }
  abort("snapshot must finish")
}

///|
test "property snapshot reload preserves independent bytes CID keys labels and exact managed custody" {
  let owner = snapshot_fixture_owner()
  for quantum in [1, 7] {
    let active = snapshot_start(owner, snapshot_fixture_body()).unwrap()
    guard snapshot_terminal(active, quantum~)
      is @local_bridge.Complete(output, ..) else {
      fail("snapshot reload")
    }
    let storage = @graphs.completed_storage(output).unwrap()
    assert_eq(
      snapshot_capture(storage),
      (snapshot_fixture_cid(), snapshot_fixture_body()),
    )
    assert_eq(@graph_storage.node_count(storage), 1)
    assert_eq(@graph_storage.edge_count(storage), 2)
    assert_true(
      @graph_storage.node_typed_key_at(storage, 0, 0).unwrap().value
      is @admitted.Number(1.0),
    )
    for index in 0..<2 {
      assert_true(
        @graph_storage.edge_typed_key_at(storage, index, 0).unwrap().value
        is @admitted.Number(value) &&
        value == (index + 10).to_double(),
      )
      assert_eq(@graph_storage.edge_endpoints(storage, index), Some((0, 0)))
    }
    let receiver = snapshot_fixture_receiver(owner, "[]")
    let read = @graphs.prepare_producer_read(receiver, 0, owner, output).unwrap()
    assert_true(physical_equal(@graphs.producer_read_receiver(read), receiver))
    assert_true(@graphs.producer_read_available(read))
    assert_true(@local_bridge.cleanup_rows_to_graph(active).unwrap())
    assert_false(@local_bridge.cleanup_rows_to_graph(active).unwrap())
    assert_false(@local_bridge.rows_to_graph_cleanup_pending(active))
    assert_true(@graphs.producer_read_available(read))
    assert_true(@graphs.discard_completed(output))
    assert_false(@graphs.producer_read_available(read))
  }
}

///|
fn snapshot_fixture_receiver(
  owner : @lower.BoundPrepared,
  body : String,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(body),
    [
      (
        "g",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(owner)),
            @pipeline.Input(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"g\"")),
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
test "property snapshot reload refuses schema substitution malformed records and incomplete identity" {
  let owner = snapshot_fixture_owner()
  for
    body in [
      snapshot_fixture_body().replace(
        old="actql-property-graph-snapshot/0.1",
        new="actql-graph-snapshot/0.1",
      ),
      snapshot_fixture_body().replace(
        old="actql-property-graph-contract/0.1",
        new="actql-graph-contract/0.1",
      ),
      snapshot_fixture_body().replace(old="\"Person\":[]", new="\"Company\":[]"),
      snapshot_fixture_body().replace(
        old="\"domain\":\"sha256:" + "0".repeat(64),
        new="\"domain\":\"sha256:" + "1".repeat(64),
      ),
    ] {
    assert_true(
      snapshot_start(owner, body) is Err(@local_bridge.GraphSnapshot(_)),
    )
  }
  for
    body in [
      snapshot_fixture_body(keys=[11, 10]),
      snapshot_fixture_body(keys=[10, 10]),
      snapshot_fixture_body().replace(
        old="\"key\":[1],\"props\"",
        new="\"key\":[null],\"props\"",
      ),
      snapshot_fixture_body().replace(
        old="\"key\":[10],\"props\"",
        new="\"key\":[99],\"props\"",
      ),
      snapshot_fixture_body().replace(old="\"name\":\"one\"", new="\"name\":1"),
      snapshot_fixture_body().replace(
        old="\"name\":\"one\"",
        new="\"missing\":\"one\"",
      ),
      snapshot_fixture_body().replace(
        old="\"src\":" + snapshot_fixture_identity("N", 1),
        new="\"src\":" + snapshot_fixture_identity("N", 2),
      ),
      snapshot_fixture_body().replace(
        old="\"dst\":" + snapshot_fixture_identity("N", 1),
        new="\"dst\":" + snapshot_fixture_identity("E", 1),
      ),
    ] {
    let active = snapshot_start(owner, body).unwrap()
    assert_true(
      snapshot_terminal(active)
      is @local_bridge.Failed(@local_bridge.GraphSnapshotOutput(_), ..),
    )
    assert_true(@local_bridge.rows_to_graph_cleanup_pending(active))
    assert_true(@local_bridge.cleanup_rows_to_graph(active).unwrap())
    assert_false(@local_bridge.rows_to_graph_cleanup_pending(active))
    assert_false(@local_bridge.cleanup_rows_to_graph(active).unwrap())
  }
  let mismatch = snapshot_start(
    owner,
    snapshot_fixture_body(),
    expected="sha256:" + "1".repeat(64),
  ).unwrap()
  assert_true(
    snapshot_terminal(mismatch)
    is @local_bridge.Failed(
      @local_bridge.GraphSnapshot(@snapshot.SnapshotIdentityMismatch),
      ..
    ),
  )
  assert_true(@local_bridge.rows_to_graph_cleanup_pending(mismatch))
  assert_true(@local_bridge.cleanup_rows_to_graph(mismatch).unwrap())
  assert_false(@local_bridge.rows_to_graph_cleanup_pending(mismatch))
}

///|
test "property snapshot reload capacity cancellation input loss and work exhaustion never hand off partial material" {
  let owner = snapshot_fixture_owner()
  for stop_after in [0, 1, 4, 6, 8, 15] {
    for input_loss in [false, true] {
      let control = @bounded.control()
      let live = Ref(true)
      let active = snapshot_start(
        owner,
        snapshot_fixture_body(),
        control~,
        live~,
      ).unwrap()
      for _ in 0..<stop_after {
        assert_true(
          @local_bridge.advance_rows_to_graph(active, 1).unwrap()
          is @local_bridge.Continue(..),
        )
      }
      if input_loss {
        live.val = false
      } else {
        @bounded.request_cancel(control) |> ignore
      }
      let terminal = snapshot_terminal(active)
      assert_true(
        if input_loss {
          terminal
          is @local_bridge.Failed(@local_bridge.GraphInputUnavailable, ..)
        } else {
          terminal is @local_bridge.Stopped(@bounded.Cancelled, ..)
        },
      )
      assert_true(@local_bridge.rows_to_graph_cleanup_pending(active))
      assert_true(@local_bridge.cleanup_rows_to_graph(active).unwrap())
      assert_false(@local_bridge.rows_to_graph_cleanup_pending(active))
      assert_false(@local_bridge.cleanup_rows_to_graph(active).unwrap())
      assert_true(@local_bridge.advance_rows_to_graph(active, 1) is Err(_))
    }
  }
  for
    active in [
      snapshot_start(owner, snapshot_fixture_body(), limits={
        ..carrier_graph_storage_limits(),
        max_edges: 1,
      }).unwrap(),
      snapshot_start(owner, snapshot_fixture_body(), caps={
        ..snapshot_caps(),
        max_identity_bytes: 1911,
      }).unwrap(),
      snapshot_start(owner, snapshot_fixture_body(), control_work_limit=Some(1)).unwrap(),
    ] {
    assert_true(snapshot_terminal(active) is @local_bridge.Failed(_, ..))
    assert_true(@local_bridge.cleanup_rows_to_graph(active).unwrap())
    assert_false(@local_bridge.rows_to_graph_cleanup_pending(active))
    assert_false(@local_bridge.cleanup_rows_to_graph(active).unwrap())
  }
}

///|
test "constructor snapshot reload feeds existing MATCH and TRAIL with independent composite identities" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source(
    rows="[{\"key\":11,\"tenant\":\"a\",\"src\":1,\"dst\":1},{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":1}]",
  )
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction)
    is @local_bridge.Complete(original, ..) else {
    fail("constructor")
  }
  let (cid, body) = snapshot_capture(
    @graphs.completed_storage(original).unwrap(),
  )
  let reload = @local_bridge.start_property_snapshot_reload(
    @bounded.control(),
    graph_owner,
    @pipeline.Step(0),
    input_cursor(body),
    cid,
    carrier_graph_storage_limits(),
    snapshot_caps(),
    4096L,
    1000,
    () => true,
    () => true,
  ).unwrap()
  guard snapshot_terminal(reload) is @local_bridge.Complete(restored, ..) else {
    fail("reload")
  }
  // Release the original before querying: no read may silently fall back to it.
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(original))
  assert_true(@local_bridge.cleanup_rows_to_graph(reload).unwrap())
  let (path_owner, domain) = keyed_path_owner(graph_owner, "trail")
  let node = "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[\"a\",1],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}"
  let edge = fn(key : Int) {
    "{\"definition\":\"E\",\"domain\":\"" +
    domain +
    "\",\"key\":[" +
    key.to_string() +
    "],\"key_types\":[{\"kind\":\"number\"}]}"
  }
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  let match_owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"label\":\"node\",\"bindings\":{\"identity\":\"element\"},\"where\":\"display = 'one'\",\"fields\":[\"display\",\"element\"]}}]",
  )
  let match_read = @graphs.prepare_producer_read(
    match_owner, 0, graph_owner, restored,
  ).unwrap()
  let matched = @local_sga.start_match_nodes(
    @bounded.control(),
    task_test_completion(match_owner),
    prepared_sequence(match_owner),
    0,
    match_read,
    10,
    limits,
    20000,
    10000,
    10000,
    [],
  ).unwrap()
  let matched_output = finish_match_nodes(matched).unwrap()
  assert_eq(@execution.completed_row_count(matched_output), 1)
  assert_eq(
    @execution.completed_output_row_wire(matched_output, 0, 10000, 10000, 50).unwrap(),
    "{\"display\":\"one\",\"element\":" +
    property_graph_expected_json_wire(node) +
    "}",
  )
  assert_true(@local_sga.cleanup_match_nodes(matched).unwrap())
  let read = @graphs.prepare_producer_read(path_owner, 0, graph_owner, restored).unwrap()
  let path = @local_sga.start_traverse(
    @bounded.control(),
    task_test_completion(path_owner),
    prepared_sequence(path_owner),
    0,
    read,
    10,
    limits,
    20000,
    10000,
    10000,
    [],
  ).unwrap()
  let mut output = None
  for _ in 0..<10000 {
    match @local_sga.advance_traverse(path, 1).unwrap() {
      @local_sga.TraverseContinue(..) => ()
      @local_sga.TraverseComplete(rows, ..) => {
        output = Some(rows)
        break
      }
      _ => fail("restored TRAIL must complete")
    }
  }
  let output = output.unwrap()
  // Distinct self-loop keys allow two trails, never the repeated edge (10,10)
  // or (11,11). These expectations do not come from the encoded snapshot.
  assert_eq(@execution.completed_row_count(output), 2)
  for row, (first, second) in [(10, 11), (11, 10)] {
    assert_eq(
      @execution.completed_output_row_wire(output, row, 10000, 10000, 50).unwrap(),
      "{\"edge_ids\":[" +
      property_graph_expected_json_wire(edge(first)) +
      "," +
      property_graph_expected_json_wire(edge(second)) +
      "],\"end_id\":" +
      property_graph_expected_json_wire(node) +
      ",\"hop_count\":2,\"node_ids\":[" +
      property_graph_expected_json_wire(node) +
      "," +
      property_graph_expected_json_wire(node) +
      "," +
      property_graph_expected_json_wire(node) +
      "],\"start_id\":" +
      property_graph_expected_json_wire(node) +
      "}",
    )
  }
  assert_true(@local_sga.cleanup_traverse(path).unwrap())
  assert_false(@local_sga.cleanup_traverse(path).unwrap())
  assert_true(@graphs.producer_read_available(read))
  assert_true(@graphs.discard_completed(restored))
  assert_false(@graphs.producer_read_available(read))
}

///|
test "empty constructor snapshot reload retains its typed definition schema" {
  let nodes = keyed_node_source(rows="[]")
  let edges = keyed_edge_source(rows="[]")
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction)
    is @local_bridge.Complete(original, ..) else {
    fail("empty constructor")
  }
  let (cid, body) = snapshot_capture(
    @graphs.completed_storage(original).unwrap(),
  )
  let reload = @local_bridge.start_property_snapshot_reload(
    @bounded.control(),
    graph_owner,
    @pipeline.Step(0),
    input_cursor(body),
    cid,
    carrier_graph_storage_limits(),
    snapshot_caps(),
    4096L,
    1000,
    () => true,
    () => true,
  ).unwrap()
  guard snapshot_terminal(reload) is @local_bridge.Complete(restored, ..) else {
    fail("empty reload")
  }
  assert_eq(
    snapshot_capture(@graphs.completed_storage(restored).unwrap()),
    (cid, body),
  )
  let owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"where\":\"display = 'one'\",\"fields\":[\"display\"]}}]",
  )
  let read = @graphs.prepare_producer_read(owner, 0, graph_owner, restored).unwrap()
  let matched = @local_sga.start_match_nodes(
    @bounded.control(),
    task_test_completion(owner),
    prepared_sequence(owner),
    0,
    read,
    10,
    {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 50,
    },
    20000,
    10000,
    10000,
    [],
  ).unwrap()
  assert_eq(
    @execution.completed_row_count(finish_match_nodes(matched).unwrap()),
    0,
  )
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Step(0),
    )
    is Some(carrier) else {
    fail("empty result schema")
  }
  let rows = @carrier_contract.relation_rows(carrier).unwrap()
  assert_eq(@carrier_contract.field_count(rows), 1)
  let schema = @carrier_contract.complete_schema(rows).unwrap()
  let contract = @schema.lookup(schema, @schema.Unqualified("display")).unwrap()
  assert_false(contract.nullable)
  assert_true(contract.shape is @value_contract.Text(_))
  assert_true(@local_sga.cleanup_match_nodes(matched).unwrap())
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@local_bridge.cleanup_rows_to_graph(reload).unwrap())
  assert_true(@graphs.discard_completed(original))
  assert_true(@graphs.discard_completed(restored))
}
