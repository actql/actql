///|
// Physical metadata retained by the existing Runtime Owner. The same Runtime
// owns every Root, original observation and failed cleanup. This is not an
// installation original, compatibility issuer, numerical profile or permission.
priv struct NativeLocalPackagedProductObservation {
  placement : @host.ClientNativeProductPlacement
  directories : Array[(@filesystem.Root, @host.ClientNativeProductPart, String)]
  launcher_descriptor_sha256 : String
  platform_descriptor_sha256 : String
  mut native_image_sha256 : String?
  mut launcher_image_sha256 : String?
}

///|
fn NativeLocalPackagedRuntime::local_runtime_product_current(
  self : NativeLocalPackagedRuntime,
) -> Result[Unit, NativeLocalPackagedRuntimeIssue] {
  guard self.product is Some(product) else { return Ok(()) }
  for (root, part, parent) in product.directories {
    let census = match
      @host.client_native_product_placement_census(
        product.placement,
        part,
        parent,
      ) {
      Ok(value) => value
      Err(_) => return Err(InvalidManifest)
    }
    match local_product_check_census(root, census, self.command_preparation) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn local_product_check_census(
  root : @filesystem.Root,
  census : @host.ClientNativeProductCensus,
  command_preparation : Bool,
) -> Result[Unit, NativeLocalPackagedRuntimeIssue] {
  let expected : Array[@filesystem.NativeDirectoryMember] = []
  for index in 0..<@host.client_native_product_census_count(census) {
    guard @host.client_native_product_census_at(census, index) is Some(entry) else {
      return Err(InvalidManifest)
    }
    expected.push({
      name: entry.name,
      kind: match entry.kind {
        ProductFile => @filesystem.File
        ProductDirectory => @filesystem.Directory
      },
    })
  }
  root
  .check_directory_members(expected, command_preparation~)
  .map_err(issue => Physical(issue))
}

///|
fn local_product_open_root(
  runtime : NativeLocalPackagedRuntime,
  path : String,
  diagnostic_ceiling : Int,
) -> @filesystem.Root raise LocalRuntimeStop {
  let root = match
    @filesystem.open_root_in_current_read_context_with_custody(
      path, diagnostic_ceiling,
    ) {
    Ok(value) => value
    Err(failure) => {
      runtime.root_open_failure = Some(failure)
      local_runtime_stop(Physical(failure.issue()))
    }
  }
  local_runtime_retain_root(runtime, root)
  root
}

///|
fn local_product_read_descriptor(
  runtime : NativeLocalPackagedRuntime,
  root : @filesystem.Root,
  source_sha : String,
  platform : String,
  package_name : String,
  digest : String,
) -> @host.ClientNativeProductMembers raise LocalRuntimeStop {
  let original = root
    .inspect_generation("local-product-members.json")
    .map_err(issue => Physical(issue))
    |> local_runtime_result
  guard original is Some(generation) else { local_runtime_stop(Changed) }
  let wire = local_runtime_read_member(
    runtime,
    root,
    "local-product-members.json",
    generation.size,
    digest,
    true,
    // The formal descriptor writer explicitly chmods this one self-hash
    // exception. Its exact bytes still bind the independent expected digest.
    expected_mode=Some(0o644),
  )
  @host.admit_client_native_product_members(
    wire, source_sha, platform, package_name,
  ).map_err(_ => InvalidManifest)
  |> local_runtime_result
}

///|
// The original runtime capture retains root, licenses, lib, data in this exact
// closed group order. Reuse those Roots and their file observations; do not
// reissue an observation cache for members already hashed by that same Owner.
fn local_product_runtime_parent(
  runtime : NativeLocalPackagedRuntime,
  parent : String,
) -> @filesystem.Root? {
  match parent {
    "" => runtime.roots.get(0)
    "licenses" => runtime.roots.get(1)
    "lib" => runtime.roots.get(2)
    "data" => runtime.roots.get(3)
    _ => None
  }
}

///|
fn local_product_reuse_member(
  runtime : NativeLocalPackagedRuntime,
  declared : Array[@host.ClientNativeLocalRuntimeMember],
  entry : @host.ClientNativeProductMember,
  manifest_sha256 : String,
) -> Bool raise LocalRuntimeStop {
  let mut original_index = -1
  if entry.path == "local-runtime.json" {
    if entry.sha256 != manifest_sha256 {
      local_runtime_stop(Changed)
    }
    original_index = 0
  } else {
    for index, original in declared {
      if original.path == entry.path {
        if original.sha256 != entry.sha256 || original.bytes != entry.bytes {
          local_runtime_stop(Changed)
        }
        original_index = index + 1
        break
      }
    }
  }
  if original_index < 0 {
    return false
  }
  guard runtime.witnesses.get(original_index) is Some(original) else {
    local_runtime_stop(Changed)
  }
  let generation = original.generation().map_err(issue => Physical(issue))
    |> local_runtime_result
  let mode = original.mode().map_err(issue => Physical(issue))
    |> local_runtime_result
  if generation.size != entry.bytes || mode != entry.mode {
    local_runtime_stop(Changed)
  }
  original.check_current().map_err(issue => Physical(issue))
  |> local_runtime_result
  true
}

///|
fn local_product_capture_part(
  runtime : NativeLocalPackagedRuntime,
  product : NativeLocalPackagedProductObservation,
  members : @host.ClientNativeProductMembers,
  part : @host.ClientNativeProductPart,
  original_root : @filesystem.Root,
  declared : Array[@host.ClientNativeLocalRuntimeMember],
  manifest_sha256 : String,
  diagnostic_ceiling : Int,
) -> Unit raise LocalRuntimeStop {
  let root_path = @host.client_native_product_placement_root(
    product.placement,
    part,
  )
  let parents : Array[(String, @filesystem.Root)] = []
  for
    index in 0..<@host.client_native_product_placement_parent_count(
      product.placement,
      part,
    ) {
    guard @host.client_native_product_placement_parent_at(
        product.placement,
        part,
        index,
      )
      is Some(parent) else {
      local_runtime_stop(InvalidManifest)
    }
    let root = if parent.is_empty() {
      original_root
    } else if part == @host.PlatformProduct &&
      local_product_runtime_parent(runtime, parent) is Some(known) {
      known
    } else {
      // The closed placement may contain node_modules/@actql. It is an exact
      // metadata-selected namespace, not a relaxation of generic object names.
      // This scoped constructor pins every namespace component no-follow;
      // before/after directory observations also retain the original chain.
      local_product_open_root(
        runtime,
        root_path + "/" + parent,
        diagnostic_ceiling,
      )
    }
    let census = @host.client_native_product_placement_census(
        product.placement,
        part,
        parent,
      ).map_err(_ => InvalidManifest)
      |> local_runtime_result
    local_product_check_census(root, census, runtime.command_preparation)
    |> local_runtime_result
    parents.push((parent, root))
    product.directories.push((root, part, parent))
  }
  for index in 0..<@host.client_native_product_members_count(members) {
    guard @host.client_native_product_members_at(members, index) is Some(entry) else {
      local_runtime_stop(InvalidManifest)
    }
    if part == @host.PlatformProduct &&
      local_product_reuse_member(runtime, declared, entry, manifest_sha256) {
      continue
    }
    let parts = entry.path.split("/").map(part => part.to_owned()).to_array()
    let parent = if parts.length() == 1 { "" } else { parts[0] }
    let name = parts[parts.length() - 1]
    guard parents.iter().find_first(value => value.0 == parent)
      is Some((_, root)) else {
      local_runtime_stop(InvalidManifest)
    }
    ignore(
      local_runtime_read_member(
        runtime,
        root,
        name,
        entry.bytes,
        entry.sha256,
        false,
        expected_mode=Some(entry.mode),
        allow_empty=true,
      ),
    )
    // These exact formal entry paths have just passed mode/bytes/hash/current
    // checks. A generic package census alone is not a verified CLI image.
    if entry.mode == 0o755 {
      if part == @host.PlatformProduct &&
        entry.path == "bin/actql-native-client" {
        product.native_image_sha256 = Some(entry.sha256)
      } else if part == @host.LauncherProduct && entry.path == "bin/actql.mjs" {
        product.launcher_image_sha256 = Some(entry.sha256)
      }
    }
  }
}

///|
/// Observe the formal two-package payload through this same scoped Runtime.
/// The trusted installer selects expected descriptor digests independently;
/// self-described labels/digests do not authenticate a release or compatibility.
/// This method cannot adopt configuration, issue permission or create a Run.
/// Refusal leaves every acquired Root/Reader with this same Runtime for close.
pub fn NativeLocalPackagedRuntime::observe_product_members(
  self : NativeLocalPackagedRuntime,
  launcher_root : String,
  launcher_descriptor_sha256 : String,
  platform_descriptor_sha256 : String,
  diagnostic_ceiling : Int,
) -> Result[Unit, NativeLocalPackagedRuntimeIssue] {
  if self.original_read is None {
    return Err(OriginalReadUnavailable)
  }
  if self.product is Some(_) || diagnostic_ceiling <= 0 {
    return Err(Changed)
  }
  match local_runtime_read_begin(self) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = try {
    self.local_runtime_check_originals() |> local_runtime_result
    guard self.selection
      is Some((platform_root, source, platform, manifest_hash)) &&
      self.manifest is Some(manifest) &&
      self.roots.get(0) is Some(platform_original) else {
      local_runtime_stop(Changed)
    }
    if !local_runtime_path_valid(launcher_root) {
      local_runtime_stop(InvalidInput)
    }
    let launcher_original = local_product_open_root(
      self, launcher_root, diagnostic_ceiling,
    )
    let launcher = local_product_read_descriptor(
      self, launcher_original, source, platform, "actql", launcher_descriptor_sha256,
    )
    let platform_members = local_product_read_descriptor(
      self,
      platform_original,
      source,
      platform,
      "@actql/cli-" + platform,
      platform_descriptor_sha256,
    )
    let placement = @host.prepare_client_native_product_placement(
        launcher, platform_members, launcher_root, platform_root,
      ).map_err(_ => InvalidManifest)
      |> local_runtime_result
    let product = {
      placement,
      directories: [],
      launcher_descriptor_sha256,
      platform_descriptor_sha256,
      native_image_sha256: None,
      launcher_image_sha256: None,
    }
    let declared = @host.client_native_local_runtime_members(manifest)
    local_product_capture_part(
      self,
      product,
      launcher,
      @host.LauncherProduct,
      launcher_original,
      declared,
      manifest_hash,
      diagnostic_ceiling,
    )
    local_product_capture_part(
      self,
      product,
      platform_members,
      @host.PlatformProduct,
      platform_original,
      declared,
      manifest_hash,
      diagnostic_ceiling,
    )
    self.product = Some(product)
    self.local_runtime_check_originals() |> local_runtime_result
    Ok(())
  } catch {
    LocalRuntimeStop(issue) => {
      self.ready = false
      Err(issue)
    }
  }
  local_runtime_read_finish(self, result)
}

///|
/// Current physical fact only. A runtime-only reader cannot issue this fact,
/// and saved metadata cannot replace current release/adoption/Account checks.
pub fn NativeLocalPackagedRuntime::check_product_current(
  self : NativeLocalPackagedRuntime,
) -> Result[Unit, NativeLocalPackagedRuntimeIssue] {
  if self.product is None {
    return Err(Changed)
  }
  self.check_current()
}
