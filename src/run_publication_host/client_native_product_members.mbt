///|
/// Private packaging metadata, not a physical witness, funding or authority.
struct ClientNativeProductMembers {
  wire : String
  source_sha : String
  platform : String
  package_name : String
  members : Array[ClientNativeProductMember]
}

///|
pub(all) struct ClientNativeProductMember {
  path : String
  bytes : Int64
  mode : Int
  sha256 : String
} derive(Eq, Debug)

///|
fn product_inventory_name(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 128 &&
  value != "." &&
  value != ".." &&
  value
  .iter()
  .all(c => {
    (c >= 'A' && c <= 'Z') ||
    (c >= 'a' && c <= 'z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '.' ||
    c == '-'
  })
}

///|
// Formal paths are ASCII. Compare character order explicitly, not the Core
// String length-first ordering. This matches the existing package inventory.
fn product_inventory_path_before(a : String, b : String) -> Bool {
  let limit = if a.length() < b.length() { a.length() } else { b.length() }
  for index = 0; index < limit; index = index + 1 {
    if a[index] != b[index] {
      return a[index] < b[index]
    }
  }
  a.length() < b.length()
}

///|
fn product_inventory_wire(
  source_sha : String,
  platform : String,
  package_name : String,
  members : Array[ClientNativeProductMember],
) -> Result[String, ClientNativeLocalRuntimeIssue] {
  try {
    let writer = @encode.writer(65536, 8192, 64)
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "files")
    @encode.begin_array(writer)
    for entry in members {
      @encode.begin_ordered_object(writer)
      @encode.ordered_key(writer, "bytes")
      @encode.number_value(writer, entry.bytes.to_double())
      @encode.ordered_key(writer, "mode")
      @encode.number_value(writer, entry.mode.to_double())
      @encode.ordered_key(writer, "path")
      @encode.string_value(writer, entry.path)
      @encode.ordered_key(writer, "sha256")
      @encode.string_value(writer, entry.sha256)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.ordered_key(writer, "packageName")
    @encode.string_value(writer, package_name)
    @encode.ordered_key(writer, "platform")
    @encode.string_value(writer, platform)
    @encode.ordered_key(writer, "sourceSha")
    @encode.string_value(writer, source_sha)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(CapacityExceeded)
  }
}

///|
fn product_inventory_read(
  wire : String,
  source_sha : String,
  platform : String,
  package_name : String,
) -> ClientNativeProductMembers raise ProductRuntimeFailure {
  if !runtime_hex(source_sha, 40) ||
    !(platform == "darwin-arm64" || platform == "linux-x64-gnu") ||
    !(package_name == "actql" || package_name == "@actql/cli-" + platform) {
    runtime_refuse(InvalidIdentity)
  }
  let bytes = @utf8.encode(wire)
  if bytes.length() > 65536 {
    runtime_refuse(CapacityExceeded)
  }
  let source = @source.parse_json_bytes_preserving(bytes, {
    max_input_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
  }).unwrap_or_else(() => runtime_refuse(InvalidManifest))
  let cursor = @decode.admit(source, {
    max_nodes: 8192,
    max_depth: 64,
    max_string_bytes: 65536,
    max_total_string_bytes: 65536,
  }).unwrap_or_else(() => runtime_refuse(InvalidManifest))
  let root = runtime_object(cursor, [
    "files", "packageName", "platform", "sourceSha",
  ])
  if runtime_text(root, "sourceSha") != source_sha ||
    runtime_text(root, "platform") != platform ||
    runtime_text(root, "packageName") != package_name {
    runtime_refuse(InvalidIdentity)
  }
  let members : Array[ClientNativeProductMember] = []
  let mut previous = ""
  for item in runtime_elements(root, "files", 1, (8192 - 5) / 5) {
    let entry = runtime_object(item, ["bytes", "mode", "path", "sha256"])
    let path = runtime_text(entry, "path")
    let parts = path.split("/").to_array()
    let hash = runtime_text(entry, "sha256")
    let size = @decode.lookup(entry, "bytes")
      .bind(value => @decode.safe_integer(value).to_option())
      .unwrap_or_else(() => runtime_refuse(InvalidMember))
    let mode = @decode.lookup(entry, "mode")
      .bind(value => @decode.safe_integer(value).to_option())
      .unwrap_or_else(() => runtime_refuse(InvalidMember))
    if parts.length() < 1 ||
      parts.length() > 2 ||
      !parts.all(part => product_inventory_name(part.to_owned())) ||
      path == "local-product-members.json" ||
      !product_inventory_path_before(previous, path) ||
      !runtime_hex(hash, 64) ||
      size < 0L ||
      size > 67108864L ||
      mode < 0L ||
      mode > 511L {
      runtime_refuse(InvalidMember)
    }
    previous = path
    members.push({ path, bytes: size, mode: mode.to_int(), sha256: hash, })
  }
  let canonical = product_inventory_wire(
    source_sha, platform, package_name, members,
  ).unwrap_or_else(() => runtime_refuse(CapacityExceeded))
  if canonical != wire {
    runtime_refuse(InvalidManifest)
  }
  { wire, source_sha, platform, package_name, members, }
}

///|
/// Read the existing formal package descriptor without a second Native codec.
/// Expected labels compare metadata only; copied labels cannot issue a witness.
pub fn admit_client_native_product_members(
  wire : String,
  source_sha : String,
  platform : String,
  package_name : String,
) -> Result[ClientNativeProductMembers, ClientNativeLocalRuntimeIssue] {
  Ok(product_inventory_read(wire, source_sha, platform, package_name)) catch {
    ProductRuntimeFailure(issue) => Err(issue)
  }
}

///|
pub fn client_native_product_members_wire(
  value : ClientNativeProductMembers,
) -> String {
  value.wire
}

///|
pub fn client_native_product_members_source(
  value : ClientNativeProductMembers,
) -> String {
  value.source_sha
}

///|
pub fn client_native_product_members_platform(
  value : ClientNativeProductMembers,
) -> String {
  value.platform
}

///|
pub fn client_native_product_members_package(
  value : ClientNativeProductMembers,
) -> String {
  value.package_name
}

///|
pub fn client_native_product_members_count(
  value : ClientNativeProductMembers,
) -> Int {
  value.members.length()
}

///|
pub fn client_native_product_members_at(
  value : ClientNativeProductMembers,
  index : Int,
) -> ClientNativeProductMember? {
  value.members.get(index)
}
