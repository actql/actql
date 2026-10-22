///|
// Explicit installed Run/Result settings, retained by the adoption Owner.
// Admission opens no Store, executes no Program, and issues no delivery grant.
priv struct LocalRunInstallation {
  namespace_id : String
  store_name : String
  store_authority_cid : String
  store_capacity_bytes : Int64
  store_objects : Int64
  store_record_bytes : Int64
  result_payload_bytes : Int64
  retention : @publication.PublicationContract
  source_free : LocalValuesInstallation?
}

///|
fn run_setting(
  object : @decode.ObjectView,
  key : String,
) -> @decode.Cursor raise ClientStop {
  @decode.lookup(object, key).unwrap_or_else(() => {
    stop("InvalidLocalRunInstallation")
  })
}

///|
fn run_text(
  object : @decode.ObjectView,
  key : String,
  maximum? : Int = 4096,
) -> String raise ClientStop {
  guard @decode.text(run_setting(object, key)) is Ok(value) &&
    !value.is_empty() &&
    value.length() <= maximum else {
    stop("InvalidLocalRunInstallation")
  }
  value
}

///|
fn run_quantity(
  object : @decode.ObjectView,
  key : String,
  maximum : Int64,
  minimum? : Int64 = 0L,
) -> Int64 raise ClientStop {
  guard @decode.safe_integer(run_setting(object, key)) is Ok(value) &&
    value >= minimum &&
    value <= maximum else {
    stop("InvalidLocalRunLimits")
  }
  value
}

///|
fn local_run_installation(
  text : String,
) -> LocalRunInstallation raise ClientStop {
  // Actual decode/policy-admission attempts, never uses of retained DATA.
  native_timing_count(31)
  let cursor = local_input_cursor(text)
  let root = @decode.closed_object(cursor, ["version", "native"]).unwrap_or_else(() => {
      stop("InvalidLocalRunInstallation")
    },
  )
  guard run_text(root, "version") == "actql-config/0.1" else {
    stop("InvalidLocalRunInstallation")
  }
  let native = @decode.closed_object(run_setting(root, "native"), ["run"]).unwrap_or_else(() => {
      stop("InvalidLocalRunInstallation")
    },
  )
  let run = @decode.closed_object(run_setting(native, "run"), [
    "namespace_id", "store_name", "store_authority_cid", "store_capacity_bytes",
    "store_objects", "store_record_bytes", "result_payload_bytes", "retention_policy_wire",
    "source_free",
  ]).unwrap_or_else(() => stop("InvalidLocalRunInstallation"))
  let component = run_text(run, "store_name", maximum=128)
  if component == "." ||
    component == ".." ||
    component.contains("/") ||
    component.contains("\\") ||
    component.contains("\u{0000}") {
    stop("InvalidLocalRunLocation")
  }
  let authority = run_text(run, "store_authority_cid", maximum=71)
  if !authority.has_prefix("sha256:") || authority.length() != 71 {
    stop("InvalidLocalRunInstallation")
  }
  for index in 7..<authority.length() {
    let unit = authority[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      stop("InvalidLocalRunInstallation")
    }
  }
  let payload = run_quantity(run, "store_capacity_bytes", 536870912L)
  let record = run_quantity(run, "store_record_bytes", 536870912L, minimum=1L)
  let result = run_quantity(run, "result_payload_bytes", 536870912L)
  if result > payload {
    stop("InvalidLocalRunLimits")
  }
  // A complete original is admitted, including its self CID. The CLI never
  // seals a caller body with a newly generated identity to hide a mismatch.
  let retention = @publication.admit_publication_contract(
    "result_retention_policy",
    run_text(run, "retention_policy_wire", maximum=8192),
    8192,
    64,
    8,
  ).unwrap_or_else(() => stop("InvalidLocalResultRetentionPolicy"))
  {
    namespace_id: run_text(run, "namespace_id", maximum=128),
    store_name: component,
    store_authority_cid: authority,
    store_capacity_bytes: payload,
    store_objects: run_quantity(run, "store_objects", 2147483647L, minimum=1L),
    store_record_bytes: record,
    result_payload_bytes: result,
    retention,
    source_free: @decode.lookup(run, "source_free").map(
      local_values_installation,
    ),
  }
}

///|
// Installed Compute contract bodies and Result Policy are configuration
// originals selected by the adoption Owner. They confer no I/O or read grant.
priv struct LocalValuesInstallation {
  registry_body : String
  values_body : String
  fragment_body : String?
  ordered_body : String?
  result_policy_cid : String
  result_policy_wire : String
}

///|
fn local_values_installation(
  cursor : @decode.Cursor,
) -> LocalValuesInstallation raise ClientStop {
  let settings = @decode.closed_object(cursor, [
    "registry", "values", "fragment", "ordered", "result_policy_cid", "result_policy_wire",
  ]).unwrap_or_else(() => stop("InvalidLocalValuesInstallation"))
  let cid = run_text(settings, "result_policy_cid", maximum=71)
  let wire = run_text(settings, "result_policy_wire", maximum=8192)
  @run_host.admit_source_free_result_policy_body(cid, wire, 8192, 512, 8).unwrap_or_else(() => {
      stop("InvalidLocalValuesResultPolicyOriginal")
    },
  )
  |> ignore
  {
    registry_body: run_text(settings, "registry", maximum=65536),
    values_body: run_text(settings, "values", maximum=65536),
    fragment_body: match @decode.lookup(settings, "fragment") {
      None => None
      Some(_) => Some(run_text(settings, "fragment", maximum=65536))
    },
    ordered_body: match @decode.lookup(settings, "ordered") {
      None => None
      Some(_) => Some(run_text(settings, "ordered", maximum=65536))
    },
    result_policy_cid: cid,
    result_policy_wire: wire,
  }
}

///|
// Called only after the Host's original unaccepted intent, saved runtime
// correspondence and typed scalar profile have passed their existing Owners.
// This retains the selected Result Policy rather than renewing or replacing it.
fn local_current_values_installation(
  original : LocalValuesInstallation,
  assets : @run_host.ClientLocalProductAssets,
) -> LocalValuesInstallation raise ClientStop {
  if assets.result_policy != original.result_policy_wire {
    stop("LocalValuesResultPolicyOriginalChanged")
  }
  {
    ..original,
    registry_body: assets.registry,
    values_body: assets.values,
    fragment_body: Some(assets.fragment),
    ordered_body: assets.ordered,
  }
}
