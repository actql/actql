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
  }
}
