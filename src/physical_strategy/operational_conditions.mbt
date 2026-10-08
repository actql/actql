///|
/// Conditions remain separate from request authority. A Host must compare these
/// with its owned input/Program and trusted runtime configuration before use.
pub(all) struct OperationalEstimateConditions {
  host : String
  realization : String
  capture_mode : String
  runtime_revision : String
  binary_digest : String
  input_digest : String
  program_digest : String
  input_rows : Int
  schema_layout : String
  limits_digest : String
  instrumentation_revision : String
  measurement_scope_revision : String
  environment_digest : String
  control_digest : String
  concurrency : Int
  process_state : String
  os_cache : String
  authorized_scope : String
} derive(Eq, Debug)

///|
fn decode_operational_conditions(
  object : @decode.ObjectView,
) -> OperationalEstimateConditions raise PolicyWireStop {
  let value : OperationalEstimateConditions = {
    host: policy_wire_text(object, "host"),
    realization: policy_wire_text(object, "realization"),
    capture_mode: policy_wire_text(object, "captureMode"),
    runtime_revision: policy_wire_text(object, "runtimeRevision"),
    binary_digest: policy_wire_text(object, "binaryDigest"),
    input_digest: policy_wire_text(object, "inputDigest"),
    program_digest: policy_wire_text(object, "programDigest"),
    input_rows: policy_wire_int(object, "inputRows"),
    schema_layout: policy_wire_text(object, "schemaLayout"),
    limits_digest: policy_wire_text(object, "limitsDigest"),
    instrumentation_revision: policy_wire_text(
      object, "instrumentationRevision",
    ),
    measurement_scope_revision: policy_wire_text(
      object, "measurementScopeRevision",
    ),
    environment_digest: policy_wire_text(object, "environmentDigest"),
    control_digest: policy_wire_text(object, "controlDigest"),
    concurrency: policy_wire_int(object, "concurrency"),
    process_state: policy_wire_text(object, "processState"),
    os_cache: policy_wire_text(object, "osCache"),
    authorized_scope: policy_wire_text(object, "authorizedScope"),
  }
  for
    text in [
      value.host,
      value.realization,
      value.capture_mode,
      value.runtime_revision,
      value.binary_digest,
      value.input_digest,
      value.program_digest,
      value.schema_layout,
      value.limits_digest,
      value.instrumentation_revision,
      value.measurement_scope_revision,
      value.environment_digest,
      value.control_digest,
      value.process_state,
      value.os_cache,
      value.authorized_scope,
    ] {
    if text.is_empty() || @utf8.encode(text).length() > 128 {
      raise PolicyWireStop
    }
  }
  if value.host != "native" ||
    value.concurrency != 1 ||
    value.input_rows < 1 ||
    !["off", "metadata-only", "evidence-enabled"].contains(value.capture_mode) ||
    !["fresh", "resident"].contains(value.realization) {
    raise PolicyWireStop
  }
  value
}

///|
/// Bounded nonsecret diagnostic body; no candidate or request is created.
pub fn operational_estimate_conditions_json(
  conditions : OperationalEstimateConditions,
) -> Result[String, SearchIssue] {
  let writer = @encode.writer(8192, 64, 2) catch {
    _ => return Err(InvalidPreference)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "host")
    @encode.string_value(writer, conditions.host)
    @encode.key(writer, "realization")
    @encode.string_value(writer, conditions.realization)
    @encode.key(writer, "captureMode")
    @encode.string_value(writer, conditions.capture_mode)
    @encode.key(writer, "runtimeRevision")
    @encode.string_value(writer, conditions.runtime_revision)
    @encode.key(writer, "binaryDigest")
    @encode.string_value(writer, conditions.binary_digest)
    @encode.key(writer, "inputDigest")
    @encode.string_value(writer, conditions.input_digest)
    @encode.key(writer, "programDigest")
    @encode.string_value(writer, conditions.program_digest)
    @encode.key(writer, "inputRows")
    @encode.number_value(writer, conditions.input_rows.to_double())
    @encode.key(writer, "schemaLayout")
    @encode.string_value(writer, conditions.schema_layout)
    @encode.key(writer, "limitsDigest")
    @encode.string_value(writer, conditions.limits_digest)
    @encode.key(writer, "instrumentationRevision")
    @encode.string_value(writer, conditions.instrumentation_revision)
    @encode.key(writer, "measurementScopeRevision")
    @encode.string_value(writer, conditions.measurement_scope_revision)
    @encode.key(writer, "environmentDigest")
    @encode.string_value(writer, conditions.environment_digest)
    @encode.key(writer, "controlDigest")
    @encode.string_value(writer, conditions.control_digest)
    @encode.key(writer, "concurrency")
    @encode.number_value(writer, conditions.concurrency.to_double())
    @encode.key(writer, "processState")
    @encode.string_value(writer, conditions.process_state)
    @encode.key(writer, "osCache")
    @encode.string_value(writer, conditions.os_cache)
    @encode.key(writer, "authorizedScope")
    @encode.string_value(writer, conditions.authorized_scope)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidPreference)
  }
}
