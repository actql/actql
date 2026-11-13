///|
// Installed role DATA only. It is not an Account decision, signing grant or
// physical use. The existing initialization row authenticates all fields.
fn initial_host_signing_subject_valid(
  subject : (String, String, String),
) -> Bool {
  for text in [subject.0, subject.1, subject.2] {
    if text.is_empty() || text.length() > 256 || text.contains("\u{0}") {
      return false
    }
  }
  true
}

///|
fn initial_host_signing_subject_payload(
  initialization : String,
  issuer : String,
  policy : String,
  host_key : String,
  subject : (String, String, String),
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  if !initial_host_signing_subject_valid(subject) {
    return Err(InvalidInput)
  }
  local_adoption_record([
    ("connection", subject.1),
    ("host_key_cid", host_key),
    ("initialization_intent_cid", initialization),
    ("issuer_authority", issuer),
    ("policy_cid", policy),
    ("principal", subject.0),
    ("resource", subject.2),
    ("version", "actql-native-local-installation-original/0.1"),
  ])
}

///|
// Closed authenticated alternative of the same control row. It binds only
// this first issuer/policy/Host key and cannot repair or extend old controls.
fn read_initial_host_signing_subject(
  host : NativeLocalHostConnection,
  control : Bytes,
  fields : NativeLocalInitialSigningFields,
  signing_original? : NativeLocalInitialSigningOriginal? = None,
) -> Result[(String, String, String)?, NativeLocalAdoptionIssue] {
  let header = match local_initial_signing_control_header(control) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  read_initial_host_signing_subject_after_header(
    host,
    header,
    fields,
    signing_original~,
  )
}

///|
// Immediate DATA handoff from this same control's closed canonical reader.
// This reuses no HMAC result: the original packet, subject and role checks below
// still run. Independent callers retain complete header admission above.
fn read_initial_host_signing_subject_after_header(
  host : NativeLocalHostConnection,
  header : Array[String],
  fields : NativeLocalInitialSigningFields,
  signing_original? : NativeLocalInitialSigningOriginal? = None,
) -> Result[(String, String, String)?, NativeLocalAdoptionIssue] {
  if header.length() != 4 {
    return Ok(None)
  }
  let packet = @base64.decode(header[3]) catch { _ => return Err(CustodyLost) }
  if @base64.encode(packet) != header[3] {
    return Err(CustodyLost)
  }
  let payload = match
    read_local_installation_authenticated_payload(
      host,
      packet,
      signing_original~,
    ) {
    Ok(value) if value.length() <= 2048 => value
    _ => return Err(CustodyLost)
  }
  let values = match
    local_adoption_fields(payload, [
      "connection", "host_key_cid", "initialization_intent_cid", "issuer_authority",
      "policy_cid", "principal", "resource", "version",
    ]) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let subject = (values[5], values[0], values[6])
  if !initial_host_signing_subject_valid(subject) ||
    values[1] != fields.public_key.cid() ||
    values[2] != host.session.intent_cid ||
    values[3] != fields.issuer ||
    values[4] != fields.policy.cid() ||
    values[7] != "actql-native-local-installation-original/0.1" {
    return Err(CustodyLost)
  }
  Ok(Some(subject))
}
