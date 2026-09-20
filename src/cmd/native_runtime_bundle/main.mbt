///|
fn option(matches : @argparse.Matches, name : String) -> Result[String, String] {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => Ok(value)
    _ => Err("missing or repeated option --" + name)
  }
}

///|
fn optional_option(
  matches : @argparse.Matches,
  name : String,
) -> Result[String?, String] {
  match matches.values.get(name) {
    None => Ok(None)
    Some([value]) if !value.is_empty() => Ok(Some(value))
    _ => Err("invalid or repeated option --" + name)
  }
}

///|
priv suberror TrustConfigurationStop {
  TrustConfigurationStop
}

///|
fn[T] trust_decoded(
  value : Result[T, @decode.Issue],
) -> T raise TrustConfigurationStop {
  match value {
    Ok(result) => result
    Err(_) => raise TrustConfigurationStop
  }
}

///|
fn trust_text(
  object : @decode.ObjectView,
  key : String,
) -> String raise TrustConfigurationStop {
  trust_decoded(@decode.text(trust_decoded(@decode.required(object, key))))
}

///|
fn parse_int64(value : String, name : String) -> Result[Int64, String] {
  let parsed : Int64 = @string.from_str(value) catch {
    _ => return Err("invalid integer option --" + name)
  }
  Ok(parsed)
}

///|
fn parse_int(value : String, name : String) -> Result[Int, String] {
  let parsed : Int = @string.from_str(value) catch {
    _ => return Err("invalid integer option --" + name)
  }
  Ok(parsed)
}

///|
fn trim_file_text(value : String) -> String {
  let without_newline = match value.strip_suffix("\n") {
    Some(text) => text.to_owned()
    None => value
  }
  match without_newline.strip_suffix("\r") {
    Some(text) => text.to_owned()
    None => without_newline
  }
}

///|
fn filesystem_issue_code(issue : @filesystem.NativeFilesystemIssue) -> String {
  match issue {
    @filesystem.UnsupportedTarget => "unsupported-target"
    @filesystem.InvalidName => "invalid-name"
    @filesystem.InvalidLimit => "invalid-limit"
    @filesystem.RootOpen(_) => "root-open"
    @filesystem.Lock(_) => "lock"
    @filesystem.WriterCreate(_) => "writer-create"
    @filesystem.CapacityExceeded => "capacity-exceeded"
    @filesystem.WriterClosed => "writer-closed"
    @filesystem.Write(_) => "write"
    @filesystem.Conflict => "conflict"
    @filesystem.GenerationMismatch => "generation-mismatch"
    @filesystem.InvalidReadSize => "invalid-read-size"
    @filesystem.IncompleteRead => "incomplete-read"
    @filesystem.ReaderClosed => "reader-closed"
    @filesystem.Read(_) => "read"
    @filesystem.Seal(_) => "seal"
    @filesystem.Cleanup(_) => "cleanup"
  }
}

///|
fn store_issue_code(
  issue : @runtime_bundle.NativeRuntimeBundleStoreIssue,
) -> String {
  match issue {
    @runtime_bundle.UnsupportedTarget => "unsupported-target"
    @runtime_bundle.Closed => "closed"
    @runtime_bundle.InvalidConfiguration => "invalid-configuration"
    @runtime_bundle.AdmissionRejected => "admission-rejected"
    @runtime_bundle.MissingBundle => "missing-bundle"
    @runtime_bundle.ExistingBundle => "existing-bundle"
    @runtime_bundle.BundleLimit => "bundle-limit"
    @runtime_bundle.CapacityExceeded => "capacity-exceeded"
    @runtime_bundle.HoldCollision => "hold-collision"
    @runtime_bundle.StateCollision => "state-collision"
    @runtime_bundle.ComponentMismatch => "component-mismatch"
    @runtime_bundle.RecoveryRequired => "recovery-required"
    @runtime_bundle.CleanupPending => "cleanup-pending"
    @runtime_bundle.Bundle(_) => "bundle"
    @runtime_bundle.Signature(_) => "signature"
    @runtime_bundle.Filesystem(value) =>
      "filesystem-" + filesystem_issue_code(value)
    @runtime_bundle.Database(_) => "database"
  }
}

///|
fn read_text_file(
  root_path : String,
  name : String,
  max_bytes : Int64,
) -> Result[String, String] {
  if max_bytes <= 0L {
    return Err("invalid text input limit")
  }
  let root = match @filesystem.open_root(root_path) {
    Ok(value) => value
    Err(issue) => return Err("input " + filesystem_issue_code(issue))
  }
  let generation = match root.inspect_generation(name) {
    Ok(Some(value)) => value
    Ok(None) => return Err("input missing")
    Err(issue) => return Err("input " + filesystem_issue_code(issue))
  }
  if generation.size < 0L || generation.size > max_bytes {
    return Err("input capacity exceeded")
  }
  let reader = match root.open_reader(name, generation) {
    Ok(value) => value
    Err(issue) => return Err("input " + filesystem_issue_code(issue))
  }
  let bytes : Array[Byte] = []
  let mut done = false
  while !done {
    let chunk = match reader.next(65536) {
      Ok(value) => value
      Err(issue) => {
        let cleanup = reader.close()
        return match cleanup {
          Ok(_) => Err("input " + filesystem_issue_code(issue))
          Err(cleanup_issue) =>
            Err(
              "input " +
              filesystem_issue_code(issue) +
              "; close " +
              filesystem_issue_code(cleanup_issue),
            )
        }
      }
    }
    for byte in chunk.bytes {
      bytes.push(byte)
    }
    done = chunk.eof
  }
  match reader.finish() {
    Ok(_) => ()
    Err(issue) => {
      ignore(reader.close())
      return Err("input " + filesystem_issue_code(issue))
    }
  }
  let text = @utf8.decode(Bytes::from_array(bytes)) catch {
    _ => return Err("input is not valid UTF-8")
  }
  Ok(trim_file_text(text))
}

///|
fn load_trust_configuration(
  authority_root : String,
  configuration_name : String,
) -> Result[Array[@runtime_bundle.NativeRuntimeBundleTrust], String] {
  let body = match
    read_text_file(authority_root, configuration_name, 1048576L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  try {
    let source = match
      @source.parse_json_bytes(@utf8.encode(body), {
        max_input_bytes: 1048576,
        max_nodes: 8192,
        max_depth: 4,
      }) {
      Ok(value) => value
      Err(_) => raise TrustConfigurationStop
    }
    let cursor = trust_decoded(
      @decode.admit(source, {
        max_nodes: 8192,
        max_depth: 4,
        max_string_bytes: 16384,
        max_total_string_bytes: 1048576,
      }),
    )
    let object = trust_decoded(
      @decode.closed_object(cursor, ["authorities", "version"]),
    )
    if trust_text(object, "version") != "actql-native-runtime-bundle-trust/0.1" {
      raise TrustConfigurationStop
    }
    let authorities = trust_decoded(@decode.required(object, "authorities"))
    let count = match @decode.array_length(authorities) {
      Some(value) if value > 0 && value <= 1024 => value
      _ => raise TrustConfigurationStop
    }
    let result : Array[@runtime_bundle.NativeRuntimeBundleTrust] = []
    for index = 0; index < count; index = index + 1 {
      guard @decode.element_at(authorities, index) is Some(value) else {
        raise TrustConfigurationStop
      }
      let entry = trust_decoded(
        @decode.closed_object(value, [
          "admit_new_bundles", "issuer_authority", "key_id", "public_key_name",
        ]),
      )
      let public_key = match
        read_text_file(
          authority_root,
          trust_text(entry, "public_key_name"),
          16384L,
        ) {
        Ok(key) => key
        Err(_) => raise TrustConfigurationStop
      }
      result.push({
        authority: {
          issuer_authority: trust_text(entry, "issuer_authority"),
          key_id: trust_text(entry, "key_id"),
          public_key_pem: public_key,
        },
        admit_new_bundles: trust_decoded(
          @decode.boolean(
            trust_decoded(@decode.required(entry, "admit_new_bundles")),
          ),
        ),
      })
    }
    Ok(result)
  } catch {
    TrustConfigurationStop => Err("invalid runtime bundle trust configuration")
  }
}

///|
fn write_snapshot(
  writer : @encode.Writer,
  value : @runtime_bundle.NativeRuntimeBundleSnapshot,
) -> Unit raise {
  @encode.begin_object(writer)
  @encode.key(writer, "artifact_name")
  @encode.string_value(writer, value.artifact_name)
  @encode.key(writer, "generation")
  @encode.begin_object(writer)
  @encode.key(writer, "device")
  @encode.string_value(writer, value.generation.device.to_string())
  @encode.key(writer, "inode")
  @encode.string_value(writer, value.generation.inode.to_string())
  @encode.key(writer, "size")
  @encode.string_value(writer, value.generation.size.to_string())
  @encode.end_object(writer)
  @encode.key(writer, "manifest")
  @encode.string_value(writer, value.manifest_json)
  @encode.key(writer, "reclaim_pending")
  @encode.bool_value(writer, value.reclaim_pending)
  @encode.key(writer, "runtime_bundle_cid")
  @encode.string_value(writer, value.runtime_bundle_cid)
  @encode.key(writer, "state")
  @encode.begin_array(writer)
  for state in value.state {
    @encode.string_value(writer, state)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
}

///|
fn snapshot_json(
  value : @runtime_bundle.NativeRuntimeBundleSnapshot,
) -> Result[String, String] {
  try {
    let writer = @encode.writer(131072, 64, 8)
    write_snapshot(writer, value)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err("result encoding failed")
  }
}

///|
fn optional_snapshot_json(
  value : @runtime_bundle.NativeRuntimeBundleSnapshot?,
) -> Result[String, String] {
  match value {
    Some(snapshot) => snapshot_json(snapshot)
    None => Ok("null")
  }
}

///|
fn snapshots_json(
  values : Array[@runtime_bundle.NativeRuntimeBundleSnapshot],
) -> Result[String, String] {
  let output_limit = match snapshots_output_limit(values.length()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let node_limit = match snapshots_node_limit(values) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  write_snapshots_with_limits(values, output_limit, node_limit)
}

///|
fn snapshots_output_limit(count : Int) -> Result[Int, String] {
  if count < 0 || count > (2147483647 - 2) / 131073 {
    return Err("result size overflow")
  }
  Ok(2 + count * 131073)
}

///|
// A snapshot has ten fixed JSON nodes plus one node for each state value.
// The enclosing array contributes one more node.
fn snapshots_node_limit(
  values : Array[@runtime_bundle.NativeRuntimeBundleSnapshot],
) -> Result[Int, String] {
  let mut nodes = 1
  for value in values {
    let states = value.state.length()
    if states > 2147483637 || nodes > 2147483647 - 10 - states {
      return Err("result node count overflow")
    }
    nodes = nodes + 10 + states
  }
  Ok(nodes)
}

///|
fn write_snapshots_with_limits(
  values : Array[@runtime_bundle.NativeRuntimeBundleSnapshot],
  output_limit : Int,
  node_limit : Int,
) -> Result[String, String] {
  try {
    let writer = @encode.writer(output_limit, node_limit, 10)
    @encode.begin_array(writer)
    for value in values {
      write_snapshot(writer, value)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err("result encoding failed")
  }
}

///|
fn install_bundle(
  store : @runtime_bundle.NativeRuntimeBundleStore,
  matches : @argparse.Matches,
  signature_key_id : String,
) -> Result[@runtime_bundle.NativeRuntimeBundleSnapshot, String] {
  let input_root_path = match option(matches, "input-root") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let component_name = match option(matches, "component-name") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let input_root = match @filesystem.open_root(input_root_path) {
    Ok(value) => value
    Err(issue) => return Err("component " + filesystem_issue_code(issue))
  }
  let generation = match input_root.inspect_generation(component_name) {
    Ok(Some(value)) => value
    Ok(None) => return Err("component missing")
    Err(issue) => return Err("component " + filesystem_issue_code(issue))
  }
  let reader = match input_root.open_reader(component_name, generation) {
    Ok(value) => value
    Err(issue) => return Err("component " + filesystem_issue_code(issue))
  }
  let manifest_name = match option(matches, "manifest-name") {
    Ok(value) => value
    Err(issue) => {
      ignore(reader.close())
      return Err(issue)
    }
  }
  let signature_name = match option(matches, "signature-name") {
    Ok(value) => value
    Err(issue) => {
      ignore(reader.close())
      return Err(issue)
    }
  }
  let manifest = match read_text_file(input_root_path, manifest_name, 65536L) {
    Ok(value) => value
    Err(issue) => {
      ignore(reader.close())
      return Err(issue)
    }
  }
  let signature = match read_text_file(input_root_path, signature_name, 4096L) {
    Ok(value) => value
    Err(issue) => {
      ignore(reader.close())
      return Err(issue)
    }
  }
  let installer = match
    store.begin_install(
      match option(matches, "install-id") {
        Ok(value) => value
        Err(issue) => {
          ignore(reader.close())
          return Err(issue)
        }
      },
      match option(matches, "signature-version") {
        Ok(value) => value
        Err(issue) => {
          ignore(reader.close())
          return Err(issue)
        }
      },
      signature_key_id,
      match option(matches, "bundle-cid") {
        Ok(value) => value
        Err(issue) => {
          ignore(reader.close())
          return Err(issue)
        }
      },
      manifest,
      signature,
    ) {
    Ok(value) => value
    Err(issue) => {
      let close_result = reader.close()
      return match close_result {
        Ok(_) => Err("install " + store_issue_code(issue))
        Err(close_issue) =>
          Err(
            "install " +
            store_issue_code(issue) +
            "; source close " +
            filesystem_issue_code(close_issue),
          )
      }
    }
  }
  let mut eof = false
  while !eof {
    let chunk = match reader.next(65536) {
      Ok(value) => value
      Err(issue) => {
        let source_close = reader.close()
        let destination_cancel = installer.cancel()
        let mut message = "component " + filesystem_issue_code(issue)
        if source_close is Err(close_issue) {
          message = message +
            "; source close " +
            filesystem_issue_code(close_issue)
        }
        if destination_cancel is Err(cancel_issue) {
          message = message +
            "; destination cleanup " +
            store_issue_code(cancel_issue)
        }
        return Err(message)
      }
    }
    if !chunk.bytes.is_empty() {
      match installer.append(chunk.bytes) {
        Ok(_) => ()
        Err(issue) => {
          let source_close = reader.close()
          let destination_cancel = installer.cancel()
          let mut message = "install " + store_issue_code(issue)
          if source_close is Err(close_issue) {
            message = message +
              "; source close " +
              filesystem_issue_code(close_issue)
          }
          if destination_cancel is Err(cancel_issue) {
            message = message +
              "; destination cleanup " +
              store_issue_code(cancel_issue)
          }
          return Err(message)
        }
      }
    }
    eof = chunk.eof
  }
  match reader.finish() {
    Ok(_) => ()
    Err(issue) => {
      ignore(reader.close())
      let destination_cancel = installer.cancel()
      let mut message = "component " + filesystem_issue_code(issue)
      if destination_cancel is Err(cancel_issue) {
        message = message +
          "; destination cleanup " +
          store_issue_code(cancel_issue)
      }
      return Err(message)
    }
  }
  match installer.seal() {
    Ok(value) => Ok(value)
    Err(issue) => {
      let cleanup = installer.cancel()
      match cleanup {
        Ok(_) => Err("install " + store_issue_code(issue))
        Err(cleanup_issue) =>
          Err(
            "install " +
            store_issue_code(issue) +
            "; destination cleanup " +
            store_issue_code(cleanup_issue),
          )
      }
    }
  }
}

///|
fn command() -> @argparse.Command {
  let cid = @argparse.OptionArg(
    "bundle-cid",
    about="Exact runtime bundle CID",
    required=true,
  )
  @argparse.Command(
    "actql-native-runtime-bundle",
    about="Operate the durable native ActQL runtime bundle Store",
    version="0.1",
    subcommand_required=true,
    options=[
      @argparse.OptionArg(
        "store-root",
        about="Durable runtime bundle Store root",
        required=true,
        global=true,
      ),
      @argparse.OptionArg(
        "sqlite-library",
        about="SQLite shared library selected by the Host",
        required=true,
        global=true,
      ),
      @argparse.OptionArg(
        "crypto-library",
        about="Crypto shared library selected by the Host",
        required=true,
        global=true,
      ),
      @argparse.OptionArg(
        "target-triple",
        about="Exact target triple admitted by this Site",
        required=true,
        global=true,
      ),
      @argparse.OptionArg(
        "issuer-authority",
        about="Legacy single-key runtime bundle issuer authority",
        global=true,
      ),
      @argparse.OptionArg(
        "key-id",
        about="Install signature key ID or legacy trusted key ID",
        global=true,
      ),
      @argparse.OptionArg(
        "authority-root",
        about="Root containing the trusted public key",
        required=true,
        global=true,
      ),
      @argparse.OptionArg(
        "public-key-name",
        about="Legacy single-key public key below the authority root",
        global=true,
      ),
      @argparse.OptionArg(
        "trust-config-name",
        about="Versioned trust configuration below the authority root",
        global=true,
      ),
      @argparse.OptionArg(
        "capacity-bytes",
        default_values=["1073741824"],
        about="Maximum retained component bytes",
        global=true,
      ),
      @argparse.OptionArg(
        "max-bundles",
        default_values=["128"],
        about="Maximum installed and staging bundle count",
        global=true,
      ),
      @argparse.OptionArg(
        "max-owners",
        default_values=["4096"],
        about="Maximum holds per bundle",
        global=true,
      ),
      @argparse.OptionArg(
        "max-record-bytes",
        default_values=["1048576"],
        about="Maximum durable catalog record size",
        global=true,
      ),
    ],
    subcommands=[
      @argparse.Command(
        "install",
        about="Verify and stream one signed bundle into the Store",
        options=[
          @argparse.OptionArg("install-id", required=true),
          @argparse.OptionArg(
            "signature-key-id",
            about="Key ID declared by the signed bundle envelope",
          ),
          @argparse.OptionArg("signature-version", default_values=[
            "actql-remote-runtime-bundle-signature/0.1",
          ]),
          cid,
          @argparse.OptionArg("input-root", required=true),
          @argparse.OptionArg("manifest-name", required=true),
          @argparse.OptionArg("signature-name", required=true),
          @argparse.OptionArg("component-name", required=true),
        ],
      ),
      @argparse.Command("activate", options=[cid]),
      @argparse.Command("rollback", options=[cid]),
      @argparse.Command("drain", options=[cid]),
      @argparse.Command("reclaim", options=[cid]),
      @argparse.Command("verify", options=[cid]),
      @argparse.Command("inspect", options=[cid]),
      @argparse.Command("active"),
      @argparse.Command("list"),
      @argparse.Command("recover"),
      @argparse.Command("recover-install", options=[
        @argparse.OptionArg("install-id", required=true),
      ]),
      @argparse.Command("retain", options=[
        cid,
        @argparse.OptionArg("hold-id", required=true),
        @argparse.OptionArg("hold-kind", required=true),
      ]),
      @argparse.Command("release", options=[
        @argparse.OptionArg("hold-id", required=true),
      ]),
      @argparse.Command("capacity"),
    ],
  )
}

///|
fn execute(matches : @argparse.Matches) -> Result[String, String] {
  let store_root = match option(matches, "store-root") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let sqlite_library = match option(matches, "sqlite-library") {
    Ok(path) =>
      match @sqlite.load_library(path) {
        Ok(value) => value
        Err(_) => return Err("SQLite library load failed")
      }
    Err(issue) => return Err(issue)
  }
  let crypto_library = match option(matches, "crypto-library") {
    Ok(path) =>
      match @signature.load_library(path) {
        Ok(value) => value
        Err(_) => return Err("crypto library load failed")
      }
    Err(issue) => return Err(issue)
  }
  let authority_root = match option(matches, "authority-root") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let capacity_bytes = match option(matches, "capacity-bytes") {
    Ok(value) =>
      match parse_int64(value, "capacity-bytes") {
        Ok(parsed) => parsed
        Err(issue) => return Err(issue)
      }
    Err(issue) => return Err(issue)
  }
  let max_bundles = match option(matches, "max-bundles") {
    Ok(value) =>
      match parse_int(value, "max-bundles") {
        Ok(parsed) => parsed
        Err(issue) => return Err(issue)
      }
    Err(issue) => return Err(issue)
  }
  let max_owners = match option(matches, "max-owners") {
    Ok(value) =>
      match parse_int(value, "max-owners") {
        Ok(parsed) => parsed
        Err(issue) => return Err(issue)
      }
    Err(issue) => return Err(issue)
  }
  let max_record_bytes = match option(matches, "max-record-bytes") {
    Ok(value) =>
      match parse_int64(value, "max-record-bytes") {
        Ok(parsed) => parsed
        Err(issue) => return Err(issue)
      }
    Err(issue) => return Err(issue)
  }
  let target_triple = match option(matches, "target-triple") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let legacy_issuer = match optional_option(matches, "issuer-authority") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let legacy_key_id = match optional_option(matches, "key-id") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let legacy_public_key = match optional_option(matches, "public-key-name") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let trust_configuration = match
    optional_option(matches, "trust-config-name") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let trust = match trust_configuration {
    Some(name) => {
      if legacy_issuer is Some(_) ||
        legacy_key_id is Some(_) ||
        legacy_public_key is Some(_) {
        return Err(
          "--trust-config-name cannot be combined with legacy trust options",
        )
      }
      match load_trust_configuration(authority_root, name) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    }
    None => {
      guard legacy_issuer is Some(issuer_authority) else {
        return Err("missing option --issuer-authority")
      }
      guard legacy_key_id is Some(key_id) else {
        return Err("missing option --key-id")
      }
      guard legacy_public_key is Some(public_key_name) else {
        return Err("missing option --public-key-name")
      }
      let public_key = match
        read_text_file(authority_root, public_key_name, 16384L) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      [
        {
          authority: { issuer_authority, key_id, public_key_pem: public_key, },
          admit_new_bundles: true,
        },
      ]
    }
  }
  let store = match
    @runtime_bundle.open_runtime_bundle_store_with_trust(
      sqlite_library, crypto_library, store_root, trust, target_triple, capacity_bytes,
      max_bundles, max_owners, max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err("Store open " + store_issue_code(issue))
  }
  let operation = match matches.subcommand {
    Some(value) => value
    None => {
      ignore(store.close())
      return Err("missing operation")
    }
  }
  let result : Result[String, String] = match operation {
    ("install", child) => {
      let signature_key_id = match optional_option(child, "signature-key-id") {
        Ok(Some(value)) => Ok(value)
        Ok(None) =>
          match legacy_key_id {
            Some(value) => Ok(value)
            None => Err("missing option --signature-key-id")
          }
        Err(issue) => Err(issue)
      }
      match signature_key_id {
        Ok(value) =>
          match install_bundle(store, child, value) {
            Ok(snapshot) => snapshot_json(snapshot)
            Err(issue) => Err(issue)
          }
        Err(issue) => Err(issue)
      }
    }
    ("activate", child) =>
      match option(child, "bundle-cid") {
        Ok(cid) =>
          match store.activate(cid) {
            Ok(value) => snapshot_json(value)
            Err(issue) => Err("activate " + store_issue_code(issue))
          }
        Err(issue) => Err(issue)
      }
    ("rollback", child) =>
      match option(child, "bundle-cid") {
        Ok(cid) =>
          match store.rollback(cid) {
            Ok(value) => snapshot_json(value)
            Err(issue) => Err("rollback " + store_issue_code(issue))
          }
        Err(issue) => Err(issue)
      }
    ("drain", child) =>
      match option(child, "bundle-cid") {
        Ok(cid) =>
          match store.drain(cid) {
            Ok(value) => snapshot_json(value)
            Err(issue) => Err("drain " + store_issue_code(issue))
          }
        Err(issue) => Err(issue)
      }
    ("reclaim", child) =>
      match option(child, "bundle-cid") {
        Ok(cid) =>
          match store.reclaim(cid) {
            Ok(value) => snapshot_json(value)
            Err(issue) => Err("reclaim " + store_issue_code(issue))
          }
        Err(issue) => Err(issue)
      }
    ("verify", child) =>
      match option(child, "bundle-cid") {
        Ok(cid) =>
          match store.verify(cid) {
            Ok(value) => snapshot_json(value)
            Err(issue) => Err("verify " + store_issue_code(issue))
          }
        Err(issue) => Err(issue)
      }
    ("inspect", child) =>
      match option(child, "bundle-cid") {
        Ok(cid) =>
          match store.inspect(cid) {
            Ok(value) => optional_snapshot_json(value)
            Err(issue) => Err("inspect " + store_issue_code(issue))
          }
        Err(issue) => Err(issue)
      }
    ("active", _) =>
      match store.active() {
        Ok(value) => optional_snapshot_json(value)
        Err(issue) => Err("active " + store_issue_code(issue))
      }
    ("list", _) =>
      match store.list() {
        Ok(values) => snapshots_json(values)
        Err(issue) => Err("list " + store_issue_code(issue))
      }
    ("recover", _) =>
      match store.recover() {
        Ok(values) => snapshots_json(values)
        Err(issue) => Err("recover " + store_issue_code(issue))
      }
    ("recover-install", child) =>
      match option(child, "install-id") {
        Ok(install_id) =>
          match store.recover_install(install_id) {
            Ok(value) => Ok(if value { "true" } else { "false" })
            Err(issue) => Err("recover-install " + store_issue_code(issue))
          }
        Err(issue) => Err(issue)
      }
    ("retain", child) => {
      let cid = option(child, "bundle-cid")
      let hold_id = option(child, "hold-id")
      let hold_kind = option(child, "hold-kind")
      match (cid, hold_id, hold_kind) {
        (Ok(cid), Ok(hold_id), Ok(hold_kind)) =>
          match store.retain(cid, hold_id, hold_kind) {
            Ok(value) => snapshot_json(value)
            Err(issue) => Err("retain " + store_issue_code(issue))
          }
        (Err(issue), _, _) | (_, Err(issue), _) | (_, _, Err(issue)) =>
          Err(issue)
      }
    }
    ("release", child) =>
      match option(child, "hold-id") {
        Ok(hold_id) =>
          match store.release(hold_id) {
            Ok(value) => Ok(if value { "true" } else { "false" })
            Err(issue) => Err("release " + store_issue_code(issue))
          }
        Err(issue) => Err(issue)
      }
    ("capacity", _) =>
      match store.capacity_usage() {
        Ok(value) =>
          Ok(
            "{\"reserved_bytes\":\"" +
            value.reserved_bytes.to_string() +
            "\",\"reserved_objects\":\"" +
            value.reserved_objects.to_string() +
            "\"}",
          )
        Err(issue) => Err("capacity " + store_issue_code(issue))
      }
    (name, _) => Err("unsupported operation " + name)
  }
  let close_result = store.close()
  match (result, close_result) {
    (Ok(value), Ok(_)) => Ok(value)
    (Ok(_), Err(close_issue)) =>
      Err("Store close " + store_issue_code(close_issue))
    (Err(issue), Ok(_)) => Err(issue)
    (Err(issue), Err(close_issue)) =>
      Err(issue + "; Store close " + store_issue_code(close_issue))
  }
}

///|
fn main {
  let matches = command().parse() catch { error => abort(error.to_string()) }
  match execute(matches) {
    Ok(value) => println(value)
    Err(issue) => abort("actql-native-runtime-bundle: " + issue)
  }
}
