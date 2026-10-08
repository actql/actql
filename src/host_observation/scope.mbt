///|
/// Observation purposes never supply execution or disclosure authority.
pub(all) enum ObservationPurpose {
  CustomerTelemetry
  ServiceOperations
} derive(Eq, Debug)

///|
/// The Host has already authorized these installation references. This owner
/// binds them before optional aggregation; it does not authorize a destination.
struct ObservationScope {
  workspace : String
  authority : String
  destination_revision : String
  disclosure_revision : String
  purpose : ObservationPurpose
} derive(Eq)

///|
fn scope_label(value : String) -> Bool {
  if value.length() == 0 || value.length() > 128 {
    return false
  }
  for index in 0..<value.length() {
    let ch = value[index]
    if !((ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '_' ||
      ch == '.' ||
      ch == '/') {
      return false
    }
  }
  true
}

///|
fn observation_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<71 {
    let ch = value[index]
    if !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) {
      return false
    }
  }
  true
}

///|
/// Existing request labels also identify rejected pre-Run checks. Requiring a
/// Program/Run CID here would force the Host to fabricate one for bad source.
fn observation_subject(value : String) -> Bool {
  if value.length() == 0 || value.length() > 128 {
    return false
  }
  for index in 0..<value.length() {
    let ch = value[index]
    if !((ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '_' ||
      ch == '.' ||
      ch == '/' ||
      ch == ':') {
      return false
    }
  }
  true
}

///|
pub fn admit_observation_scope(
  workspace : String,
  authority : String,
  destination_revision : String,
  disclosure_revision : String,
  purpose : ObservationPurpose,
) -> ObservationScope? {
  if !scope_label(workspace) ||
    !observation_cid(authority) ||
    !scope_label(destination_revision) ||
    !scope_label(disclosure_revision) {
    return None
  }
  Some({
    workspace,
    authority,
    destination_revision,
    disclosure_revision,
    purpose,
  })
}

///|
/// A diagnostic key, not a CID, Run identity, or authority token. The admitted
/// labels cannot contain the separator, so each component remains distinct.
pub fn observation_scope_key(value : ObservationScope) -> String {
  let purpose = match value.purpose {
    CustomerTelemetry => "customer_telemetry"
    ServiceOperations => "service_operations"
  }
  value.workspace +
  "|" +
  value.authority +
  "|" +
  value.destination_revision +
  "|" +
  value.disclosure_revision +
  "|" +
  purpose
}
