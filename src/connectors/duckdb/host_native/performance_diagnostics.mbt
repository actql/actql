///|
fn performance_optional_number(
  writer : @encode.Writer,
  value : Double?,
) -> Unit raise @encode.EncodeFailure {
  match value {
    Some(value) => @encode.number_value(writer, value)
    None => @encode.null_value(writer)
  }
}

///|
/// Optional bounded serialization, outside execution/cleanup. A failure here
/// cannot change a Run outcome or release the Run's resources.
pub fn native_performance_decision_json(
  decision : NativePerformanceDecision,
  max_bytes? : Int = 65536,
) -> Result[String, NativeStandardPolicyIssue] {
  if max_bytes < 1 ||
    max_bytes > 65536 ||
    decision.references.length() > 64 ||
    decision.positions.length() > 64 {
    return Err(InvalidConfiguration)
  }
  let request = match
    @strategy.placement_policy_request_json(decision.request) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
  let conditions = match decision.conditions {
    None => None
    Some(value) =>
      match @strategy.operational_estimate_conditions_json(value) {
        Ok(value) => Some(value)
        Err(issue) => return Err(Wire(issue))
      }
  }
  let writer = @encode.writer(max_bytes, 2048, 4) catch {
    _ => return Err(InvalidConfiguration)
  }
  try {
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("version", "actql-native-performance-decision/0.1"),
        (
          "mode",
          if decision.mode == DiagnosticReference {
            "diagnostic-reference"
          } else {
            "select-reference"
          },
        ),
        ("objective", decision.objective),
        ("reason", decision.reason),
        ("request_json", request),
        ("load_applicability", decision.load_applicability),
        ("stable_improvement", decision.stable_improvement),
        ("net_benefit", decision.net_benefit),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    for
      (name, value) in [
        ("profile_revision", decision.profile_revision),
        ("conditions_json", conditions),
      ] {
      @encode.key(writer, name)
      match value {
        Some(value) => @encode.string_value(writer, value)
        None => @encode.null_value(writer)
      }
    }
    @encode.key(writer, "positions")
    @encode.begin_array(writer)
    for position in decision.positions {
      @encode.number_value(writer, position.to_double())
    }
    @encode.end_array(writer)
    @encode.key(writer, "evaluated_ms")
    @encode.string_value(writer, decision.evaluated_ms.to_string())
    @encode.key(writer, "task")
    @encode.number_value(writer, decision.task.to_double())
    for
      (name, value) in [
        ("selected_position", decision.selected_position),
        ("offline_position", decision.offline_position),
      ] {
      @encode.key(writer, name)
      performance_optional_number(writer, value.map(value => value.to_double()))
    }
    @encode.key(writer, "plan_changed")
    match decision.selected_position {
      Some(position) =>
        @encode.bool_value(writer, decision.offline_position != Some(position))
      None => @encode.bool_value(writer, false)
    }
    for
      (name, value) in [
        ("oldest_ms", decision.oldest_ms),
        ("newest_ms", decision.newest_ms),
        ("max_age_ms", decision.max_age_ms),
      ] {
      @encode.key(writer, name)
      match value {
        Some(value) => @encode.string_value(writer, value.to_string())
        None => @encode.null_value(writer)
      }
    }
    @encode.key(writer, "reused_profile")
    @encode.bool_value(writer, decision.reused_profile)
    @encode.key(writer, "costs")
    @encode.begin_object(writer)
    @encode.key(writer, "profile_creation_ms")
    performance_optional_number(writer, decision.profile_creation_ms)
    @encode.key(writer, "first_load_and_validation_microseconds")
    @encode.number_value(writer, decision.profile_read_microseconds)
    @encode.key(writer, "consultation_microseconds_including_load")
    @encode.number_value(writer, decision.consultation_microseconds)
    @encode.key(writer, "overlap")
    @encode.string_value(writer, "load is enclosed by consultation; do not add")
    @encode.end_object(writer)
    @encode.key(writer, "references")
    @encode.begin_array(writer)
    for reference in decision.references {
      @encode.begin_object(writer)
      for
        (name, value) in [
          ("position", reference.position),
          ("task", reference.task),
          ("sample_count", reference.sample_count),
        ] {
        @encode.key(writer, name)
        @encode.number_value(writer, value.to_double())
      }
      @encode.key(writer, "quantity")
      @encode.string_value(writer, reference.quantity)
      @encode.key(writer, "unknown_reason")
      match reference.unknown_reason {
        Some(value) => @encode.string_value(writer, value)
        None => @encode.null_value(writer)
      }
      for
        (name, value) in [
          ("median_ms", reference.median_ms),
          ("observed_minimum_ms", reference.minimum_ms),
          ("observed_maximum_ms", reference.maximum_ms),
        ] {
        @encode.key(writer, name)
        performance_optional_number(writer, value)
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "calibrated_eta_ms")
    @encode.null_value(writer)
    @encode.key(writer, "p90_ms")
    @encode.null_value(writer)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(EnvelopeTooLarge)
  }
}
