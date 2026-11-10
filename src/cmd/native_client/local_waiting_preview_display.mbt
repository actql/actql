///|
// This selector consumes the existing saved State, never issues one.
fn local_waiting_effect_checkpoint(wire : String) -> (String, String)? {
  try {
    let state = local_run_display_object(local_input_cursor(wire))
    if local_run_display_text(local_run_display_field(state, "status")) !=
      "waiting_checkpoint" {
      return None
    }
    let checkpoint = local_run_display_object(
      local_run_display_field(state, "checkpoint"),
    )
    if local_run_display_text(local_run_display_field(checkpoint, "kind")) !=
      "effect_set" {
      return None
    }
    Some(
      (
        local_run_display_text(
          local_run_display_field(checkpoint, "checkpoint_id"),
        ),
        local_run_display_text(
          local_run_display_field(checkpoint, "checkpoint_cid"),
        ),
      ),
    )
  } catch {
    ClientStop(_) => None
  }
}

///|
fn local_preview_field(
  value : @canonical.CanonicalValue,
  name : String,
) -> @canonical.CanonicalValue raise ClientStop {
  @canonical.object_field(value, name).unwrap_or_else(() => {
    stop("LocalEffectReviewDisplayUnavailable")
  })
}

///|
fn local_preview_literal(
  value : @canonical.CanonicalValue,
) -> String raise ClientStop {
  @canonical.stringify_value(value, 65536, 8192, 64) catch {
    _ => stop("LocalEffectReviewDisplayUnavailable")
  }
}

///|
// Whitelist displayed evidence, never print the private continuation, guard,
// request/credential handles or authoring evidence. Canonical JSON literals
// preserve precision and escape terminal control characters in original DATA.
fn local_waiting_preview_display(
  state : String,
  preview : String,
  maximum? : Int = 65536,
) -> String? {
  if maximum < 0 ||
    maximum > 65536 ||
    local_waiting_effect_checkpoint(state) is None {
    return None
  }
  try {
    let source = @source.parse_json_bytes_preserving(@utf8.encode(preview), {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }).unwrap_or_else(() => stop("LocalEffectReviewDisplayUnavailable"))
    let root = @canonical.from_source(source, 8192, 64, 65536, data_keys=true) catch {
      _ => stop("LocalEffectReviewDisplayUnavailable")
    }
    guard local_preview_field(root, "effects") is @canonical.Array(effects) else {
      return None
    }
    let output : LocalRunStateText = {
      buffer: StringBuilder(),
      remaining_bytes: maximum,
    }
    output.append(
      local_run_state_display(state).unwrap_or_else(() => {
        stop("LocalRunStateDisplayUnavailable")
      }),
    )
    output.append("Stored Effect Preview (read-only; not approval):\n")
    for effect in @canonical.array_values(effects) {
      output.append(
        "  Effect: " +
        local_preview_literal(local_preview_field(effect, "effect_kind")) +
        "  Target: " +
        local_preview_literal(local_preview_field(effect, "target")) +
        "\n  Items: " +
        local_preview_literal(local_preview_field(effect, "count")) +
        "\n  Preview strength: " +
        local_preview_literal(local_preview_field(effect, "preview_strength")) +
        "\n  Changes:\n",
      )
      guard local_preview_field(effect, "changes") is @canonical.Array(rows) else {
        return None
      }
      for row in @canonical.array_values(rows) {
        output.append(
          "    Row: " +
          local_preview_literal(local_preview_field(row, "target_row_identity")) +
          "\n      Before: " +
          local_preview_literal(local_preview_field(row, "before")) +
          "\n      After: " +
          local_preview_literal(local_preview_field(row, "after")) +
          "\n",
        )
      }
    }
    Some(output.buffer.to_string())
  } catch {
    ClientStop(_) => None
  }
}

///|
// status opens only the original Store and retains its reader before any
// fallible restoration. The normal command cleanup retires every read alias.
fn LocalCommandPreparationOriginal::display_saved_waiting_run(
  self : Self,
  capture : @local_host.NativeLocalJournalCapture,
  configuration : LocalCommandConfiguration,
  wire : String,
) -> String raise ClientStop {
  let base = local_run_state_display(wire).unwrap_or_else(() => {
    stop("LocalRunStateDisplayUnavailable")
  })
  guard local_waiting_effect_checkpoint(wire) is Some((id, cid)) else {
    return base
  }
  let settings = configuration.settings
  let selected = match
    local_host_result(
      capture.lookup_original_checkpoint_by_id_in_original_read(
        settings.principal,
        settings.connection,
        id,
        @env.now().to_double(),
      ),
    ) {
    Ok(Some(value)) if value.checkpoint_cid() == cid => value
    _ => stop("LocalOriginalCheckpointUnavailable")
  }
  guard self.run_observation is Some(existing) else {
    stop("LocalEffectReviewDisplayUnavailable")
  }
  if existing.saved_effect_review is None {
    self.restore_checkpoint_review(capture, configuration, selected)
  }
  guard self.run_observation is Some(observation) &&
    observation.saved_effect_review is Some(reader) else {
    stop("LocalEffectReviewDisplayUnavailable")
  }
  let policy = @run_host.client_standard_effect_computation_limits()
  let run_file = settings.run_file.unwrap_or_else(() => {
    stop("LocalRunOriginalNotSelected")
  })
  let installation = configuration.run_installation(
    run_file,
    local_host_result(capture.selected_configuration_in_original_read(run_file)),
  )
  let preview = local_host_result(
    reader.display_preview_in_original_read(
      @env.now().to_double(),
      {
        max_wire_bytes: native_mock_effect_record_bytes(installation),
        max_nodes: policy.effects.max_admission_nodes,
        max_depth: policy.effects.max_admission_depth,
      },
      id,
      cid,
    ),
  )
  local_waiting_preview_display(wire, preview).unwrap_or_else(() => {
    stop("LocalEffectReviewDisplayUnavailable")
  })
}

///|
// Fresh run reuses the SAME ModelWork's persisted Preview and waiting record.
// This observer does not restore a second Store, approve or repeat the Model.
fn LocalCommandPreparationOriginal::display_fresh_waiting_run(
  self : Self,
  settings : LocalHostSettings,
  wire : String,
) -> String raise ClientStop {
  let base = local_run_state_display(wire).unwrap_or_else(() => {
    "Local run response (original Submission preserved):\n" + wire
  })
  guard local_waiting_effect_checkpoint(wire) is Some((id, cid)) else {
    return base
  }
  guard self.business is Some(business) && business.model_work.length() == 1 else {
    stop("LocalEffectReviewDisplayUnavailable")
  }
  let preview = local_host_result(
    business.model_work[0].display_preview_in_original_read(
      settings.connection,
      id,
      cid,
    ),
  )
  local_waiting_preview_display(wire, preview).unwrap_or_else(() => {
    stop("LocalEffectReviewDisplayUnavailable")
  })
}
