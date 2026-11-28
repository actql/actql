///|
fn advance_original_mock_effect_public_snapshots(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  run : @strategy.CapturedDAG,
) -> Int {
  guard targets.public_results is Some(results) &&
    targets.public_manifest is Some(manifest) &&
    manifest.definitions.length() == results.length() &&
    manifest.artifacts.length() == results.length() else {
    return -32
  }
  let count = results.length()
  guard targets.public_snapshots is Some(snapshots) else {
    guard @execution.preparation_array_representation(
        1L,
        count.to_int64(),
        false,
      )
      is Some(array) &&
      fund_original_mock_effect_target_data(drive, array) else {
      return -4
    }
    targets.public_snapshots = Some(Array(capacity=count))
    return 1
  }
  let ordinal = snapshots.length()
  if ordinal == count {
    return if targets.public_snapshot is None && targets.workspace is None {
      0
    } else {
      -32
    }
  }
  guard ordinal < count else { return -32 }
  if targets.public_snapshot is Some(issuer) {
    guard targets.workspace is Some(_) else { return -32 }
    match issuer.advance(64) {
      Ok((false, _)) => return 1
      Err(_) => return -31
      Ok((true, _)) => ()
    }
    guard issuer.finish() is Ok(snapshot) &&
      physical_equal(
        @publication.captured_result_snapshot_definition(snapshot),
        manifest.definitions[ordinal],
      ) &&
      physical_equal(
        @publication.captured_result_snapshot_artifact(snapshot),
        manifest.artifacts[ordinal],
      ) else {
      return -32
    }
    snapshots.push(snapshot)
    targets.public_snapshot = None
    return if release_original_mock_effect_target_document(drive, targets) {
      1
    } else {
      -9
    }
  }
  let graph = @strategy.captured_dag_graph(run)
  let output = results[ordinal].output
  guard targets.workspace is None &&
    @strategy.graph_result_occurrence(graph, ordinal) is Some(occurrence) &&
    output.snapshot_original_extent(run, occurrence)
    is Ok((bytes, nodes, _, depth)) else {
    return -32
  }
  guard @local_host.original_recursive_result_snapshot_capacity(
      occurrence, bytes, nodes, depth,
    )
    is Some((retained, temporary)) &&
    @resources.reserve_capacity(drive.ledger, 0L, temporary) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  if !fund_original_mock_effect_target_bytes(drive, retained) {
    return -4
  }
  guard output.start_captured_snapshot(bytes, nodes, depth) is Ok(issuer) else {
    return -31
  }
  targets.public_snapshot = Some(issuer)
  1
}
