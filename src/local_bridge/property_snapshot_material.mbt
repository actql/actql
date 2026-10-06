///|
/// Attach a lazy, exact-generation operation to the existing Graph material.
/// Bounds are installed by the selected provider before execution; a persisted
/// header cannot increase them or supply the expected owner/domain.
pub fn completed_property_snapshot_material(
  control : @bounded.Control,
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  source : @graph.Completed,
  storage_limits : @graph_storage.Limits,
  snapshot_limits : @snapshot.Limits,
  read_limits : @decode.Limits,
  maximum_bytes : Int,
  maximum_frame_bytes : Int,
  workspace_bytes : Int64,
  available : () -> Bool,
) -> Result[@lifecycle.Material, GraphBridgeIssue] {
  let reference = @graph.completed_carrier_reference(source)
  if !@lifecycle.completion_reference_matches_port(reference, owner, target) ||
    !available() ||
    maximum_bytes < 1 ||
    maximum_frame_bytes < 1 ||
    maximum_frame_bytes > 16777216 ||
    workspace_bytes < 0L ||
    read_limits.max_nodes < 1 ||
    read_limits.max_depth < 1 ||
    read_limits.max_string_bytes < 0 ||
    read_limits.max_total_string_bytes < 0 {
    return Err(GraphInputUnavailable)
  }
  let factory = @lifecycle.prepare_snapshot_factory(reference, () => {
    let handoff = match
      prepare_property_snapshot_handoff(
        control,
        owner,
        target,
        source,
        storage_limits,
        snapshot_limits,
        storage_limits.max_workspace_slots,
        available,
      ) {
      Ok(handoff) => handoff
      Err(issue) =>
        return Err(@lifecycle.SnapshotFamilyFailure(@debug.to_string(issue)))
    }
    let emitted_bytes = Ref(0)
    let saved_cid : Ref[String?] = Ref(None)
    let ready_for_content = Ref(false)
    let restored : Ref[@graph.Completed?] = Ref(None)
    let byte_failure = Ref(false)
    let operation = @lifecycle.prepare_snapshot_io(
      reference,
      maximum_bytes,
      maximum_frame_bytes,
      workspace_bytes,
      quantum => {
        if byte_failure.val {
          return Err(@lifecycle.SnapshotByteLimit)
        }
        match advance_property_snapshot_save(handoff, quantum) {
          Err(issue) =>
            Err(@lifecycle.SnapshotFamilyFailure(@debug.to_string(issue)))
          Ok(Saving(progress~, work~)) =>
            Ok({ complete: false, progress, work, issue: None, })
          Ok(Saved(cid, progress~, work~)) => {
            saved_cid.val = Some(cid)
            Ok({ complete: true, progress, work, issue: None, })
          }
          Ok(SaveFailed(issue, progress~, work~)) =>
            Ok({
              complete: false,
              progress,
              work,
              issue: Some(
                @lifecycle.SnapshotFamilyFailure(@debug.to_string(issue)),
              ),
            })
          Ok(SaveStopped(_, progress~, work~)) =>
            Ok({
              complete: false,
              progress,
              work,
              issue: Some(@lifecycle.SnapshotUnavailable),
            })
        }
      },
      () => {
        if byte_failure.val {
          return Err(@lifecycle.SnapshotByteLimit)
        }
        match take_property_snapshot_save_output(handoff) {
          Err(issue) =>
            Err(@lifecycle.SnapshotFamilyFailure(@debug.to_string(issue)))
          Ok(text) => {
            let size = @utf8.encode(text).length()
            if size > maximum_frame_bytes ||
              size > maximum_bytes - emitted_bytes.val {
              byte_failure.val = true
              return Err(@lifecycle.SnapshotByteLimit)
            }
            emitted_bytes.val += size
            if saved_cid.val is Some(_) {
              ready_for_content.val = true
            }
            Ok(text)
          }
        }
      },
      () => {
        guard !byte_failure.val &&
          ready_for_content.val &&
          saved_cid.val is Some(cid) else {
          return Err(@lifecycle.SnapshotUnavailable)
        }
        Ok({ cid, bytes: emitted_bytes.val, })
      },
      cid => {
        guard !byte_failure.val && ready_for_content.val else {
          return Err(@lifecycle.SnapshotUnavailable)
        }
        release_property_snapshot_source(handoff, cid).map_err(issue => {
          @lifecycle.SnapshotFamilyFailure(@debug.to_string(issue))
        })
      },
      (text, input_available) => {
        if !input_available() || handoff.phase != Released {
          return Err(@lifecycle.SnapshotUnavailable)
        }
        let parsed = match
          @source.parse_json_bytes_preserving(
            @utf8.encode(text),
            {
              max_input_bytes: maximum_bytes,
              max_nodes: read_limits.max_nodes,
              max_depth: read_limits.max_depth,
            },
            source_path="local-graph-snapshot",
          ) {
          Ok(parsed) => parsed
          Err(_) =>
            return Err(
              @lifecycle.SnapshotFamilyFailure("snapshot input admission"),
            )
        }
        let cursor = match @decode.admit(parsed, read_limits) {
          Ok(cursor) => cursor
          Err(_) =>
            return Err(
              @lifecycle.SnapshotFamilyFailure("snapshot structural admission"),
            )
        }
        start_property_snapshot_handoff_reload(handoff, cursor, input_available).map_err(issue => {
            @lifecycle.SnapshotFamilyFailure(@debug.to_string(issue))
          },
        )
      },
      quantum => {
        match advance_property_snapshot_handoff_reload(handoff, quantum) {
          Err(issue) =>
            Err(@lifecycle.SnapshotFamilyFailure(@debug.to_string(issue)))
          Ok(Continue(progress~, work~)) =>
            Ok({ complete: false, progress, work, issue: None, })
          Ok(Complete(output, progress~, work~)) => {
            restored.val = Some(output)
            Ok({ complete: true, progress, work, issue: None, })
          }
          Ok(Failed(issue, progress~, work~)) =>
            Ok({
              complete: false,
              progress,
              work,
              issue: Some(
                @lifecycle.SnapshotFamilyFailure(@debug.to_string(issue)),
              ),
            })
          Ok(Stopped(_, progress~, work~)) =>
            Ok({
              complete: false,
              progress,
              work,
              issue: Some(@lifecycle.SnapshotUnavailable),
            })
        }
      },
      () => {
        guard restored.val is Some(output) && @graph.completed_available(output) else {
          return Err(@lifecycle.SnapshotUnavailable)
        }
        // Prepare the consumer material before transferring private custody.
        let material = match @graph.completed_material(output) {
          Ok(material) => material
          Err(issue) =>
            return Err(
              @lifecycle.SnapshotFamilyFailure(@debug.to_string(issue)),
            )
        }
        match take_property_snapshot_restored(handoff) {
          Err(issue) =>
            Err(@lifecycle.SnapshotFamilyFailure(@debug.to_string(issue)))
          Ok(_) => {
            restored.val = None
            Ok(material)
          }
        }
      },
      () => {
        cleanup_property_snapshot_handoff(handoff)
        .map_err(issue => {
          @lifecycle.SnapshotFamilyFailure(@debug.to_string(issue))
        })
        .map(_ => !property_snapshot_handoff_cleanup_pending(handoff))
      },
    )
    match operation {
      Ok(operation) => Ok(operation)
      Err(issue) => {
        // Preparation checks above make invalid operation bounds unreachable.
        // No callback or Store I/O has run; release serializer/source custody.
        cleanup_property_snapshot_handoff(handoff) |> ignore
        Err(issue)
      }
    }
  })
  let factory = match factory {
    Ok(factory) => factory
    Err(_) => return Err(GraphInputUnavailable)
  }
  @graph.completed_material(source, snapshot_factory=Some(factory)).map_err(issue => {
    GraphSnapshotOutput(issue)
  })
}
