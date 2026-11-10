///|
// Presentation only. The existing saved-State Owner has already checked the
// original and current permission. No displayed field issues state or authority.
priv struct LocalRunStateText {
  buffer : StringBuilder
  mut remaining_bytes : Int
}

///|
fn LocalRunStateText::append(
  self : LocalRunStateText,
  text : String,
) -> Unit raise ClientStop {
  let bytes = @utf8.encode(text).length()
  if bytes > self.remaining_bytes {
    stop("LocalRunStateDisplayLimit")
  }
  self.remaining_bytes -= bytes
  self.buffer.write_string(text)
}

///|
fn local_run_display_field(
  object : @decode.ObjectView,
  name : String,
) -> @decode.Cursor raise ClientStop {
  @decode.required(object, name).unwrap_or_else(() => {
    stop("LocalRunStateDisplayUnavailable")
  })
}

///|
fn local_run_display_text(value : @decode.Cursor) -> String raise ClientStop {
  @decode.text(value).unwrap_or_else(() => {
    stop("LocalRunStateDisplayUnavailable")
  })
}

///|
// Quote original names and diagnostics so control characters remain terminal
// data. The quoted value is never passed back as a resource selector.
fn local_run_display_literal(value : @decode.Cursor) -> String raise ClientStop {
  encode_request_json(Json::string(local_run_display_text(value)), 65536)
}

///|
fn local_run_display_integer(value : @decode.Cursor) -> String raise ClientStop {
  @decode.safe_integer(value)
  .unwrap_or_else(() => stop("LocalRunStateDisplayUnavailable"))
  .to_string()
}

///|
fn local_run_display_object(
  value : @decode.Cursor,
) -> @decode.ObjectView raise ClientStop {
  @decode.open_object(value).unwrap_or_else(() => {
    stop("LocalRunStateDisplayUnavailable")
  })
}

///|
fn local_run_display_boolean(value : @decode.Cursor) -> String raise ClientStop {
  @decode.boolean(value)
  .unwrap_or_else(() => stop("LocalRunStateDisplayUnavailable"))
  .to_string()
}

///|
// This bounded projection is not a second Run-state validator. Its input at
// the public boundary is the existing opaque saved-State wire. A legacy reply
// which cannot be displayed retains its original response instead of becoming
// a fabricated State, a completed Run or an available Result.
fn local_run_state_display(
  original : String,
  maximum? : Int = 65536,
) -> String? {
  if maximum < 0 || maximum > 65536 {
    return None
  }
  try {
    let root = local_run_display_object(local_input_cursor(original))
    if local_run_display_text(local_run_display_field(root, "version")) !=
      "actql-run-state/0.1" {
      return None
    }
    let output : LocalRunStateText = {
      buffer: StringBuilder(),
      remaining_bytes: maximum,
    }
    output.append(
      "Run: " +
      local_run_display_literal(local_run_display_field(root, "run_id")) +
      "\nState: " +
      local_run_display_literal(local_run_display_field(root, "status")) +
      "\n",
    )
    // A saved waiting Checkpoint may precede the first observation counter.
    // Show only a revision actually supplied by that same State owner; the
    // independent control/SQL revision is never a presentation substitute.
    if @decode.lookup(root, "revision") is Some(revision) {
      output.append(
        "State revision: " + local_run_display_integer(revision) + "\n",
      )
    }
    output.append(
      "Updated: " +
      local_run_display_literal(local_run_display_field(root, "updated_at")) +
      "\n",
    )
    if @decode.lookup(root, "checkpoint") is Some(value) {
      let checkpoint = local_run_display_object(value)
      output.append(
        "Checkpoint: " +
        local_run_display_literal(
          local_run_display_field(checkpoint, "checkpoint_id"),
        ) +
        "\n  Kind: " +
        local_run_display_literal(local_run_display_field(checkpoint, "kind")) +
        "\n  Original CID: " +
        local_run_display_literal(
          local_run_display_field(checkpoint, "checkpoint_cid"),
        ) +
        "\n",
      )
    }
    let next = local_run_display_object(
      local_run_display_field(root, "next_action"),
    )
    output.append(
      "Next action: " +
      local_run_display_literal(local_run_display_field(next, "kind")) +
      "\n",
    )
    for name in ["checkpoint_id", "reason"] {
      if @decode.lookup(next, name) is Some(value) {
        output.append(
          "  " + name + ": " + local_run_display_literal(value) + "\n",
        )
      }
    }
    for name in ["results", "effects"] {
      if @decode.lookup(next, name) is Some(value) {
        let items = @decode.elements(value).unwrap_or_else(() => {
          stop("LocalRunStateDisplayUnavailable")
        })
        for item in items {
          output.append(
            "  " + name + ": " + local_run_display_literal(item) + "\n",
          )
        }
      }
    }
    output.append(
      "Result available: " +
      local_run_display_boolean(
        local_run_display_field(root, "result_available"),
      ) +
      "\n",
    )
    let inventory = local_run_display_field(root, "result_availability")
    ignore(local_run_display_object(inventory))
    let count = @decode.object_length(inventory).unwrap_or(0)
    if count == 0 {
      output.append("Result observations: none\n")
    }
    for index in 0..<count {
      let (name, value) = @decode.field_at(inventory, index).unwrap_or_else(() => {
        stop("LocalRunStateDisplayUnavailable")
      })
      let observation = local_run_display_object(value)
      output.append(
        "Result " +
        encode_request_json(Json::string(name), 65536) +
        ": " +
        local_run_display_literal(local_run_display_field(observation, "state")) +
        "\n  Reason: " +
        local_run_display_literal(
          local_run_display_field(observation, "reason"),
        ) +
        "\n  Observed: " +
        local_run_display_literal(
          local_run_display_field(observation, "observed_at"),
        ) +
        "\n",
      )
    }
    if @decode.lookup(root, "control") is Some(value) {
      let control = local_run_display_object(value)
      output.append(
        "Control revision: " +
        local_run_display_integer(local_run_display_field(control, "revision")) +
        "\nCancellation requested: " +
        local_run_display_boolean(
          local_run_display_field(control, "cancellation_requested"),
        ) +
        "\nPhysical stop: " +
        local_run_display_literal(
          local_run_display_field(control, "physical_stop"),
        ) +
        "\n",
      )
    }
    if @decode.lookup(root, "terminal_error") is Some(value) {
      let error = local_run_display_object(value)
      output.append(
        "Error: " +
        local_run_display_literal(local_run_display_field(error, "code")) +
        "\n  Message: " +
        local_run_display_literal(local_run_display_field(error, "message")) +
        "\n",
      )
    }
    Some(output.buffer.to_string())
  } catch {
    ClientStop(_) => None
  }
}
