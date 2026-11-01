///|
/// Same original rows/current/Store and Common nominal proof. Neither this
/// transport nor confirmation is a publication index or durable ACK.
priv struct StoredSDKPublicationBinding {
  rows_material : Int
  step : @local_run.LocalRunPublicationBindingStep[Ref[Int], Int]?
  mut original : @local_run.LocalRunPublicationBinding[Ref[Int], Int]?
}

///|
fn sdk_publication_binding_issue(
  issue : @local_run.LocalRunPublicationBindingIssue[Int],
) -> Int {
  match issue {
    Current(issue) => host_current_issue(issue)
    AuthorizationMismatch | ForeignScope => -32
    ForeignPreparation | CustodyLost | MissingOriginal => -35
    CapacityExceeded => -4
    SavedRows(_) | Policy(_) | Encoding(_) | StoreEncoding(_) => -31
  }
}

///|
/// Readmit the genuine saved original under the existing trusted current port.
/// Saved text alone cannot replace Store adoption or publication permission.
fn sdk_saved_publication_binding(
  value : Instance,
  run : Int,
  plan : @local_run.LocalRunPlan,
  snapshot : @host.ClientSavedSubmissionSnapshot,
  row : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
) -> Result[@local_run.LocalRunPublicationBindingPlan[Ref[Int], Int], Int] {
  guard value.runs.get(run) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    configuration.sdk is Some(sdk) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    current.material is Some(adopted) &&
    current.generation is Some((device, inode)) else {
    return Err(-2)
  }
  @local_run.prepare_local_saved_run_publication_binding(
    plan,
    snapshot,
    adopted,
    current.store,
    configuration.run_namespace,
    sdk.store_authority_cid,
    device,
    inode,
    row,
    submitted,
  ).map_err(sdk_publication_binding_issue)
}

///|
fn sdk_publication_material_wire(
  value : Instance,
  material : StoredMaterial,
  plan : @local_run.LocalRunPlan,
) -> Result[String, Int] {
  guard value.runs.get(material.run) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    configuration.sdk is Some(sdk) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    current.material is Some(adopted) &&
    current.generation is Some((device, inode)) else {
    return Err(-2)
  }
  let (row, submitted, rows, rows_material) = match
    sdk_saved_original_rows(value, material.run, plan) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  // These facts come from the trusted same-Store current port and saved
  // configuration, never a new SDK policy/scope/permission parameter.
  let candidate = match rows {
    Submitted(rows, preparation) =>
      @local_run.prepare_local_run_publication_binding(
        plan,
        rows,
        preparation,
        adopted,
        current.store,
        configuration.run_namespace,
        sdk.store_authority_cid,
        device,
        inode,
        row,
        submitted,
      ).map_err(sdk_publication_binding_issue)
    Saved(snapshot) =>
      sdk_saved_publication_binding(
        value,
        material.run,
        plan,
        snapshot,
        row,
        submitted,
      )
  }
  let candidate = match candidate {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  let (kind, key, revision, body, held) = match candidate {
    Retained(original) =>
      (
        "retained",
        row.key,
        row.revision,
        row.body,
        { rows_material, step: None, original: Some(original), },
      )
    Append(step) => {
      let (key, revision, body) = @local_run.local_run_publication_binding_rows(
        step,
      )
      (
        "publication",
        key,
        revision,
        body,
        { rows_material, step: Some(step), original: None, },
      )
    }
  }
  let wire = try {
    let writer = @encode.writer(1048576, 6, 1)
    @encode.begin_object(writer)
    for
      (key, text) in [
        ("kind", kind),
        ("key", key),
        ("revision", revision.to_string()),
        ("body", @utf8.decode(body)),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(-34)
  }
  material.sdk_publication = Some(held)
  Ok(wire)
}

///|
/// Reobserve original saved rows in the actual Host transaction. Candidate
/// validation cannot complete a write or authorize dispatch by itself.
pub fn validate_sdk_publication_material(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    !value.closing &&
    !value.runtime_closing &&
    value.materials.get(handle) is Some(material) &&
    material.produced &&
    material.kind == 9 &&
    material.sdk_publication is Some(held) &&
    value.runs.get(material.run) is Some({ outcome: Some(Ok(plan)), .. }) else {
    return -2
  }
  let (row, submitted, _, rows_material) = match
    sdk_saved_original_rows(value, material.run, plan) {
    Ok(value) => value
    Err(code) => return code
  }
  if rows_material != held.rows_material {
    return -35
  }
  let result = match held.original {
    Some(original) =>
      @local_run.validate_local_run_publication_binding_original(
        original, row, submitted,
      )
    None =>
      match held.step {
        Some(step) =>
          @local_run.validate_local_run_publication_binding(
            step, row, submitted,
          )
        None => return -2
      }
  }
  match result {
    Ok(_) => 0
    Err(issue) => sdk_publication_binding_issue(issue)
  }
}

///|
/// Adopt only an actual same-Store successor through the Common Owner. A
/// saved candidate, physical response or generation alone is insufficient.
pub fn confirm_sdk_publication_material(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    !value.closing &&
    !value.runtime_closing &&
    value.materials.get(handle) is Some(material) &&
    material.kind == 9 &&
    material.produced &&
    material.sdk_publication is Some(held) &&
    value.runs.get(material.run) is Some({ outcome: Some(Ok(plan)), .. }) else {
    return -2
  }
  if held.original is Some(_) {
    return validate_sdk_publication_material(nonce, handle)
  }
  guard held.step is Some(step) else { return -2 }
  let (row, submitted, _, rows_material) = match
    sdk_saved_original_rows(value, material.run, plan) {
    Ok(value) => value
    Err(code) => return code
  }
  if rows_material != held.rows_material {
    return -35
  }
  match @local_run.confirm_local_run_publication_binding(step, row, submitted) {
    Ok(original) => {
      held.original = Some(original)
      0
    }
    Err(issue) => sdk_publication_binding_issue(issue)
  }
}
