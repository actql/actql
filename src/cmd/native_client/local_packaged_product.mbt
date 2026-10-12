///|
// The launcher supplies installation metadata, never execution authority.
// Every file still passes the existing no-follow generation-pinned Owner.
priv struct LocalPackagedRuntime {
  manifest : @run_host.ClientNativeLocalRuntime
  sqlite : String
  crypto : String
  assets : @run_host.ClientLocalProductAssets
  witnesses : Array[
    (@local_filesystem.Root, String, @local_filesystem.NativeFileGeneration),
  ]
}

///|
fn local_product_operation(operation : String) -> Bool {
  [
    "adopt", "connect", "check", "new-submission", "lookup-submission", "checkpoint-state",
    "lookup-preparation-grant", "lookup-preparation-raw", "lookup-cancellation",
    "cancel", "delivery-attempt", "read", "start", "aql",
  ].contains(operation)
}

///|
fn local_product_path(path : String) -> Bool {
  if !path.has_prefix("/") ||
    path.length() < 2 ||
    path.length() > 4096 ||
    path.has_suffix("/") ||
    path.contains("\u{0000}") {
    return false
  }
  let parts = path.split("/").to_array()
  for index in 1..<parts.length() {
    if parts[index].is_empty() || parts[index] == "." || parts[index] == ".." {
      return false
    }
  }
  true
}

///|
fn local_product_context(
  wire : String,
) -> (String, String, String, String) raise ClientStop {
  if @utf8.encode(wire).length() > 8192 {
    stop("PackagedLocalRuntimeInvalid")
  }
  let object = @decode.closed_object(local_input_cursor(wire), [
    "root", "sourceSha", "platform", "manifestSha256",
  ]).unwrap_or_else(() => stop("PackagedLocalRuntimeInvalid"))
  let get = fn(key : String) -> String raise ClientStop {
    @decode.lookup(object, key)
    .bind(value => @decode.text(value).to_option())
    .unwrap_or_else(() => stop("PackagedLocalRuntimeInvalid"))
  }
  let root = get("root")
  if !local_product_path(root) {
    stop("PackagedLocalRuntimeInvalid")
  }
  (root, get("sourceSha"), get("platform"), get("manifestSha256"))
}

///|
fn local_product_read_member(
  root : @local_filesystem.Root,
  name : String,
  bytes : Int64,
  hash : String,
  collect : Bool,
) -> (String, @local_filesystem.NativeFileGeneration) raise ClientStop {
  let generation = root
    .inspect_generation(name)
    .unwrap_or_else(() => stop("PackagedLocalRuntimeUnavailable"))
    .unwrap_or_else(() => stop("PackagedLocalRuntimeUnavailable"))
  if bytes < 1L ||
    generation.size != bytes ||
    bytes > 67108864L ||
    (collect && bytes > 65536L) {
    stop("PackagedLocalRuntimeLimit")
  }
  let reader = root
    .open_reader(name, generation)
    .unwrap_or_else(() => stop("PackagedLocalRuntimeChanged"))
  let hasher = @sha.hasher()
  let retained : Array[Byte] = []
  try {
    let mut done = false
    while !done {
      let chunk = reader
        .next(65536)
        .unwrap_or_else(() => stop("PackagedLocalRuntimeChanged"))
      @sha.update(hasher, chunk.bytes) catch {
        _ => stop("PackagedLocalRuntimeLimit")
      }
      if collect {
        for byte in chunk.bytes {
          retained.push(byte)
        }
      }
      done = chunk.eof
    }
    reader.finish().unwrap_or_else(() => stop("PackagedLocalRuntimeChanged"))
  } catch {
    error => {
      if reader.close() is Err(_) {
        stop("PackagedLocalRuntimeCleanupPending")
      }
      raise error
    }
  }
  let digest = @sha.finish_hex(hasher) catch {
    _ => stop("PackagedLocalRuntimeLimit")
  }
  if digest != hash || !root.verify_generation(name, generation) {
    stop("PackagedLocalRuntimeChanged")
  }
  let wire = if collect {
    @utf8.decode(Bytes::from_array(retained)) catch {
      _ => stop("PackagedLocalRuntimeInvalid")
    }
  } else {
    ""
  }
  (wire, generation)
}

///|
fn local_packaged_runtime(
  context_wire : String,
) -> LocalPackagedRuntime raise ClientStop {
  let (root_path, source_sha, platform, manifest_hash) = local_product_context(
    context_wire,
  )
  let root = @local_filesystem.open_root(root_path).unwrap_or_else(() => {
    stop("PackagedLocalRuntimeUnavailable")
  })
  let generation = root
    .inspect_generation("local-runtime.json")
    .unwrap_or_else(() => stop("PackagedLocalRuntimeUnavailable"))
    .unwrap_or_else(() => stop("PackagedLocalRuntimeUnavailable"))
  let (wire, manifest_generation) = local_product_read_member(
    root,
    "local-runtime.json",
    generation.size,
    manifest_hash,
    true,
  )
  let manifest = @run_host.admit_client_native_local_runtime(
    wire, source_sha, platform, manifest_hash,
  ).unwrap_or_else(() => stop("PackagedLocalRuntimeInvalid"))
  let witnesses = [(root, "local-runtime.json", manifest_generation)]
  let bodies : Map[String, String] = Map([])
  let mut sqlite = ""
  let mut crypto = ""
  for entry in @run_host.client_native_local_runtime_members(manifest) {
    let parts = entry.path.split("/").map(part => part.to_owned()).to_array()
    let parent = root
      .open_child(parts[0])
      .unwrap_or_else(() => stop("PackagedLocalRuntimeUnavailable"))
    let collect = parts[0] == "data"
    let (body, generation) = local_product_read_member(
      parent,
      parts[1],
      entry.bytes,
      entry.sha256,
      collect,
    )
    witnesses.push((parent, parts[1], generation))
    if collect {
      bodies[entry.role] = body
    }
    if entry.role == "sqlite" {
      sqlite = root_path + "/" + entry.path
    }
    if entry.role == "crypto" {
      crypto = root_path + "/" + entry.path
    }
  }
  {
    manifest,
    sqlite,
    crypto,
    witnesses,
    assets: {
      environment: bodies.get("environment").unwrap(),
      registry: bodies.get("registry").unwrap(),
      values: bodies.get("values").unwrap(),
      fragment: bodies.get("fragment").unwrap(),
      ordered: bodies.get("ordered"),
      result_policy: bodies.get("result-policy").unwrap(),
    },
  }
}

///|
fn local_product_runtime_current(runtime : LocalPackagedRuntime) -> Bool {
  runtime.witnesses.all(witness => {
    witness.0.verify_generation(witness.1, witness.2)
  })
}

///|
fn execute_native_local_product(
  matches : @argparse.Matches,
  operation : String,
) -> String raise ClientStop {
  // An explicit configuration remains its own profile. Do not silently replace
  // a user's selected root or repair an absent original configuration there.
  if !(matches.sources.get("config-root") is Some(@argparse.Default)) {
    stop("ExplicitLocalRootRequiresConfiguration")
  }
  let context = @env.get_env_var("ACTQL_NATIVE_LOCAL_RUNTIME").unwrap_or_else(() => {
    stop("PackagedLocalRuntimeUnavailable")
  })
  let runtime = local_packaged_runtime(context)
  let home = @env.get_env_var("HOME").unwrap_or_else(() => {
    stop("LocalProductHomeUnavailable")
  })
  if !local_product_path(home) {
    stop("LocalProductHomeUnavailable")
  }
  let parent = @local_filesystem.open_root(home).unwrap_or_else(() => {
    stop("LocalProductHomeUnavailable")
  })
  ignore(
    parent
    .bootstrap_parent_ownership()
    .unwrap_or_else(() => stop("LocalProductHomeUntrusted")),
  )
  let intent = parent
    .inspect_generation("product-initialization.json")
    .unwrap_or_else(() => stop("LocalProductCustodyUnavailable"))
  if !local_product_runtime_current(runtime) {
    stop("PackagedLocalRuntimeChanged")
  }
  let crypto = @local_crypto.load_library(runtime.crypto).unwrap_or_else(() => {
    stop("NativeLocalSignatureUnavailable")
  })
  if !local_product_runtime_current(runtime) {
    stop("PackagedLocalRuntimeChanged")
  }
  let configuration_root = home + "/.actql-local"
  let session = if intent is Some(_) {
    // Even repeated adopt restores the original clock and selection. Missing
    // witness/body/intent never triggers factory regeneration or new custody.
    local_host_result(
      @local_host.restore_native_local_product_configuration(
        home, ".actql-local", crypto,
      ),
    )
  } else {
    if operation != "adopt" {
      stop("ExplicitLocalAdoptionRequired")
    }
    // An existing child without its original intent is lost custody, not a
    // fresh initialization. Refuse before even assembling replacement bodies.
    if parent
      .inspect_directory(".actql-local")
      .unwrap_or_else(() => stop("LocalProductCustodyUnavailable"))
      is Some(_) {
      stop("LocalProductCustodyLost")
    }
    let originals = @run_host.client_native_local_product_originals(
      configuration_root,
      runtime.sqlite,
      runtime.crypto,
      local_utc_now(),
      runtime.assets,
      runtime.manifest,
    ).unwrap_or_else(() => stop("LocalProductDefaultsNotAdmitted"))
    local_host_result(
      @local_host.begin_native_local_product_configuration(
        home, ".actql-local", originals, crypto,
      ),
    )
  }
  let reply = try {
    local_host_result(session.stage_configuration())
    if text_file(configuration_root, "runtime.json", 65536L) !=
      @run_host.client_native_local_runtime_original(runtime.manifest) {
      stop("PackagedLocalRuntimeChanged")
    }
    let settings = local_host_settings(
      text_file(configuration_root, "config.json", 65536L),
    )
    if settings.sqlite_library != runtime.sqlite ||
      settings.signature_library != runtime.crypto ||
      !settings.installation_files.contains("runtime.json") ||
      !local_product_runtime_current(runtime) {
      stop("PackagedLocalRuntimeChanged")
    }
    if optional(matches, "input-root") is None {
      let input = @env.current_dir().unwrap_or_else(() => {
        stop("LocalDocumentRootUnavailable")
      })
      matches.values["input-root"] = [input]
    }
    matches.values["config-root"] = [configuration_root]
    matches.values["config-file"] = ["config.json"]
    execute_native_local(matches)
  } catch {
    error => {
      if !session.close() {
        stop("LocalProductCleanupPending")
      }
      raise error
    }
  }
  if !session.close() {
    stop("LocalProductCleanupPending")
  }
  reply
}
