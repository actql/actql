///|
// Physical projection of the existing filesystem Owner, not an authority or
// compatibility issuer. Only this whole-member reader can construct it.
struct NativeLocalPackagedRuntime {
  mut manifest : @host.ClientNativeLocalRuntime?
  mut assets : @host.ClientLocalProductAssets?
  roots : Array[@filesystem.Root]
  directories : Array[@filesystem.NativeDirectoryObservation]
  witnesses : Array[@filesystem.NativeFileObservation]
  mut reader : @filesystem.Reader?
  mut reader_open_failure : @filesystem.NativeReaderOpenFailure?
  mut root_open_failure : @filesystem.NativeRootOpenFailure?
  original_read : (@arena.InstalledArenaHost, @arena.InstalledArenaOriginalRead)?
  mut original_resources : @arena.InstalledArenaLocalHostResources?
  mut selection : (String, String, String, String)?
  mut product : NativeLocalPackagedProductObservation?
  mut read_scope_entered : Bool
  mut sqlite : String
  mut crypto : String
  mut command_sqlite_member : @filesystem.NativeObservedComponentMember?
  mut command_crypto_member : @filesystem.NativeObservedComponentMember?
  mut ready : Bool
  mut closed : Bool
}

///|
pub(all) enum NativeLocalPackagedRuntimeIssue {
  InvalidInput
  InvalidManifest
  Changed
  Limit
  Physical(@filesystem.NativeFilesystemIssue)
  OriginalReadUnavailable
  OriginalRead(@arena.InstalledArenaOriginalReadIssue)
  CleanupPending
  OriginalHostResources(@arena.InstalledArenaLocalHostResourcesIssue)
}

///|
/// On cleanup failure the same opaque projection retains the open reader and
/// roots. Callers must retry its close rather than declaring completion.
pub(all) enum NativeLocalPackagedRuntimeOpenIssue {
  Refused(NativeLocalPackagedRuntimeIssue)
  Pending(NativeLocalPackagedRuntime, NativeLocalPackagedRuntimeIssue)
}

///|
priv suberror LocalRuntimeStop {
  LocalRuntimeStop(NativeLocalPackagedRuntimeIssue)
}

///|
fn[T] local_runtime_stop(
  issue : NativeLocalPackagedRuntimeIssue,
) -> T raise LocalRuntimeStop {
  raise LocalRuntimeStop(issue)
}

///|
fn[T] local_runtime_result(
  result : Result[T, NativeLocalPackagedRuntimeIssue],
) -> T raise LocalRuntimeStop {
  match result {
    Ok(value) => value
    Err(issue) => local_runtime_stop(issue)
  }
}

///|
fn local_runtime_read_begin(
  runtime : NativeLocalPackagedRuntime,
  cleanup? : Bool = false,
) -> Result[Unit, NativeLocalPackagedRuntimeIssue] {
  if !cleanup && runtime.closed {
    return Err(Changed)
  }
  if runtime.read_scope_entered {
    return Err(CleanupPending)
  }
  if runtime.original_resources is Some(resources) {
    guard runtime.original_read is Some((host, original)) else {
      return Err(OriginalReadUnavailable)
    }
    if !cleanup {
      match
        host.require_local_host_consuming_read_current(resources, original) {
        Err(issue) => return Err(OriginalHostResources(issue))
        Ok(_) => ()
      }
    }
    let entered = if cleanup {
      host.enter_local_host_cleanup(resources, @arena.HostRead)
    } else {
      host.enter_local_host_phase(resources, @arena.HostRead)
    }
    return match entered {
      Err(issue) => Err(OriginalHostResources(issue))
      Ok(_) => {
        runtime.read_scope_entered = true
        Ok(())
      }
    }
  }
  match runtime.original_read {
    None => Ok(())
    Some((host, original)) => {
      let result = if cleanup {
        host.enter_domain_original_read_cleanup(original)
      } else {
        host.enter_domain_original_read(original)
      }
      match result {
        Err(issue) => Err(OriginalRead(issue))
        Ok(_) => {
          runtime.read_scope_entered = true
          Ok(())
        }
      }
    }
  }
}

///|
// Keep a failed leave with this same runtime. Normal operations cannot enter
// again; close retries that original leave before starting cleanup.
fn[T] local_runtime_read_finish(
  runtime : NativeLocalPackagedRuntime,
  result : Result[T, NativeLocalPackagedRuntimeIssue],
) -> Result[T, NativeLocalPackagedRuntimeIssue] {
  if runtime.read_scope_entered {
    guard runtime.original_read is Some((host, original)) else {
      return Err(CleanupPending)
    }
    let left = match runtime.original_resources {
      Some(resources) =>
        host
        .leave_local_host_phase(resources)
        .map_err(issue => OriginalHostResources(issue))
      None =>
        host
        .leave_domain_original_read(original)
        .map_err(issue => OriginalRead(issue))
    }
    match left {
      Err(issue) => return Err(issue)
      Ok(_) => runtime.read_scope_entered = false
    }
  }
  result
}

///|
fn local_runtime_empty(
  original_read : (@arena.InstalledArenaHost, @arena.InstalledArenaOriginalRead)?,
  original_resources? : @arena.InstalledArenaLocalHostResources? = None,
) -> NativeLocalPackagedRuntime {
  {
    manifest: None,
    assets: None,
    roots: [],
    directories: [],
    witnesses: [],
    reader: None,
    reader_open_failure: None,
    root_open_failure: None,
    original_read,
    original_resources,
    selection: None,
    product: None,
    read_scope_entered: false,
    sqlite: "",
    crypto: "",
    command_sqlite_member: None,
    command_crypto_member: None,
    ready: false,
    closed: false,
  }
}

///|
fn local_runtime_path_valid(root_path : String) -> Bool {
  root_path.has_prefix("/") &&
  root_path.length() <= 4096 &&
  !root_path.contains("\u{0000}") &&
  !root_path.has_suffix("/") &&
  !root_path.contains("//") &&
  !root_path.split("/").any(part => part == "." || part == "..")
}

///|
// Retain the acquired Root before observing its namespace so that even a
// failed temporary namespace close stays with the original cleanup carrier.
fn local_runtime_retain_root(
  runtime : NativeLocalPackagedRuntime,
  root : @filesystem.Root,
) -> Unit raise LocalRuntimeStop {
  runtime.roots.push(root)
  if runtime.original_resources is Some(_) {
    root.require_current_original_read().map_err(issue => Physical(issue))
    |> local_runtime_result
  }
  let original = root.observe_directory().map_err(issue => Physical(issue))
    |> local_runtime_result
  runtime.directories.push(original)
}

///|
fn local_runtime_read_member(
  runtime : NativeLocalPackagedRuntime,
  root : @filesystem.Root,
  name : String,
  bytes : Int64,
  hash : String,
  collect : Bool,
  expected_mode? : Int? = None,
  allow_empty? : Bool = false,
) -> String raise LocalRuntimeStop {
  let original = root.observe_file(name).map_err(issue => Physical(issue))
    |> local_runtime_result
  let generation = original.generation().map_err(issue => Physical(issue))
    |> local_runtime_result
  if bytes < (if allow_empty { 0L } else { 1L }) ||
    generation.size != bytes ||
    bytes > 67108864L ||
    (collect && bytes > 65536L) {
    local_runtime_stop(Limit)
  }
  if expected_mode is Some(mode) &&
    (original.mode().map_err(issue => Physical(issue)) |> local_runtime_result) !=
    mode {
    local_runtime_stop(Changed)
  }
  let reader = match original.open_reader_with_custody() {
    Ok(reader) => reader
    Err(failure) => {
      runtime.reader_open_failure = Some(failure)
      local_runtime_stop(Physical(failure.issue()))
    }
  }
  runtime.reader = Some(reader)
  let hasher = @sha.hasher()
  let retained : Array[Byte] = []
  let mut done = false
  while !done {
    let chunk = reader.next(65536).map_err(issue => Physical(issue))
      |> local_runtime_result
    @sha.update(hasher, chunk.bytes) catch {
      _ => local_runtime_stop(Limit)
    }
    if collect {
      for byte in chunk.bytes {
        retained.push(byte)
      }
    }
    done = chunk.eof
  }
  // Compare the real opened Reader with the same full original stat before
  // acknowledging finish. On refusal runtime still retains this exact Reader.
  original.check_reader(reader).map_err(issue => Physical(issue))
  |> local_runtime_result
  reader.finish().map_err(issue => Physical(issue)) |> local_runtime_result
  runtime.reader = None
  let digest = @sha.finish_hex(hasher) catch { _ => local_runtime_stop(Limit) }
  if digest != hash {
    local_runtime_stop(Changed)
  }
  original.check_current().map_err(issue => Physical(issue))
  |> local_runtime_result
  runtime.witnesses.push(original)
  if collect {
    @utf8.decode(Bytes::from_array(retained)) catch {
      _ => local_runtime_stop(InvalidManifest)
    }
  } else {
    ""
  }
}

///|
/// Same finite recipe and bounded no-follow/generation-pinned reads as the
/// existing packaged CLI. This observes files; it does not adopt configuration,
/// load a library, grant authority, acquire a Source or create a Run.
pub fn open_native_local_packaged_runtime(
  root_path : String,
  source_sha : String,
  platform : String,
  manifest_sha256 : String,
) -> Result[NativeLocalPackagedRuntime, NativeLocalPackagedRuntimeOpenIssue] {
  if !local_runtime_path_valid(root_path) {
    return Err(Refused(InvalidInput))
  }
  let root = match @filesystem.open_root(root_path) {
    Ok(value) => value
    Err(issue) => return Err(Refused(Physical(issue)))
  }
  let runtime = local_runtime_empty(None)
  local_runtime_finish_open(
    runtime,
    local_runtime_capture(
      runtime, root, root_path, source_sha, platform, manifest_sha256,
    ),
  )
}

///|
/// Trusted installed supplier only. This borrows the same joined original;
/// it creates no Ledger, budget, profile or read authority. The outer owner
/// retains it through all Runtime/asset aliases and closes it only afterward.
/// Missing supply never falls back to the legacy Root constructor.
pub fn open_native_local_packaged_runtime_in_original_read(
  original_read : (@arena.InstalledArenaHost, @arena.InstalledArenaOriginalRead)?,
  root_path : String,
  source_sha : String,
  platform : String,
  manifest_sha256 : String,
  diagnostic_ceiling : Int,
) -> Result[NativeLocalPackagedRuntime, NativeLocalPackagedRuntimeOpenIssue] {
  guard original_read is Some((host, original)) else {
    return Err(Refused(OriginalReadUnavailable))
  }
  if !local_runtime_path_valid(root_path) || diagnostic_ceiling <= 0 {
    return Err(Refused(InvalidInput))
  }
  match host.enter_domain_original_read(original) {
    Err(issue) => return Err(Refused(OriginalRead(issue)))
    Ok(_) => ()
  }
  // The Runtime itself is managed by this context. Its close acknowledges its
  // Roots/readers, not its own last alias or the outer original-read carrier.
  let runtime = local_runtime_empty(original_read)
  runtime.read_scope_entered = true
  let result = match
    @filesystem.open_root_in_current_read_context_with_custody(
      root_path, diagnostic_ceiling,
    ) {
    Ok(root) =>
      local_runtime_capture(
        runtime, root, root_path, source_sha, platform, manifest_sha256,
      )
    Err(failure) => {
      let issue : NativeLocalPackagedRuntimeIssue = Physical(failure.issue())
      runtime.root_open_failure = Some(failure)
      Err(issue)
    }
  }
  local_runtime_finish_open(runtime, result)
}

///|
/// The same already claimed Host pair owns every Read phase in this Runtime.
/// The caller retains all three originals; no available-pair read, replacement
/// consumer or legacy Root is selected when this entrance refuses.
pub fn open_native_local_packaged_runtime_in_original_host_resources(
  original : (
    @arena.InstalledArenaHost,
    @arena.InstalledArenaOriginalRead,
    @arena.InstalledArenaLocalHostResources,
  )?,
  root_path : String,
  source_sha : String,
  platform : String,
  manifest_sha256 : String,
  diagnostic_ceiling : Int,
) -> Result[NativeLocalPackagedRuntime, NativeLocalPackagedRuntimeOpenIssue] {
  guard original is Some((host, read, resources)) else {
    return Err(Refused(OriginalReadUnavailable))
  }
  if !local_runtime_path_valid(root_path) || diagnostic_ceiling <= 0 {
    return Err(Refused(InvalidInput))
  }
  match host.require_local_host_consuming_read_current(resources, read) {
    Err(issue) => return Err(Refused(OriginalHostResources(issue)))
    Ok(_) => ()
  }
  match host.enter_local_host_phase(resources, @arena.HostRead) {
    Err(issue) => return Err(Refused(OriginalHostResources(issue)))
    Ok(_) => ()
  }
  let runtime = local_runtime_empty(
    Some((host, read)),
    original_resources=Some(resources),
  )
  runtime.read_scope_entered = true
  let result = match
    @filesystem.open_root_in_current_read_context_with_custody(
      root_path, diagnostic_ceiling,
    ) {
    Ok(root) =>
      local_runtime_capture(
        runtime, root, root_path, source_sha, platform, manifest_sha256,
      )
    Err(failure) => {
      runtime.root_open_failure = Some(failure)
      Err(Physical(failure.issue()))
    }
  }
  local_runtime_finish_open(runtime, result)
}

///|
fn local_runtime_capture(
  runtime : NativeLocalPackagedRuntime,
  root : @filesystem.Root,
  root_path : String,
  source_sha : String,
  platform : String,
  manifest_sha256 : String,
) -> Result[NativeLocalPackagedRuntime, NativeLocalPackagedRuntimeIssue] {
  let result = try {
    local_runtime_retain_root(runtime, root)
    let generation = local_runtime_result(
      root
      .inspect_generation("local-runtime.json")
      .map_err(issue => Physical(issue)),
    ).unwrap_or_else(() => local_runtime_stop(Changed))
    let wire = local_runtime_read_member(
      runtime,
      root,
      "local-runtime.json",
      generation.size,
      manifest_sha256,
      true,
    )
    let manifest = @host.admit_client_native_local_runtime(
        wire, source_sha, platform, manifest_sha256,
      ).map_err(_ => InvalidManifest)
      |> local_runtime_result
    runtime.manifest = Some(manifest)
    runtime.selection = Some((root_path, source_sha, platform, manifest_sha256))
    let bodies : Map[String, String] = Map([])
    // The existing admitted member Owner emits licenses, libraries, then
    // assets. Retain each group's original parent once, not once per file.
    // This is capture-local Root reuse, never a cached current/Allow result.
    let mut parent_name = ""
    let mut parent = root
    for entry in @host.client_native_local_runtime_members(manifest) {
      let parts = entry.path.split("/").map(part => part.to_owned()).to_array()
      if parts[0] != parent_name {
        parent = match runtime.original_read {
          None =>
            root.open_child(parts[0]).map_err(issue => Physical(issue))
            |> local_runtime_result
          Some(_) =>
            match root.open_child_with_custody(parts[0]) {
              Ok(value) => value
              Err(failure) => {
                runtime.root_open_failure = Some(failure)
                local_runtime_stop(Physical(failure.issue()))
              }
            }
        }
        local_runtime_retain_root(runtime, parent)
        parent_name = parts[0]
      }
      let collect = parts[0] == "data"
      let body = local_runtime_read_member(
        runtime,
        parent,
        parts[1],
        entry.bytes,
        entry.sha256,
        collect,
      )
      if collect {
        bodies[entry.role] = body
      }
      if runtime.original_read is Some(_) &&
        (entry.role == "sqlite" || entry.role == "crypto") {
        let observation = runtime.witnesses[runtime.witnesses.length() - 1]
        let component = observation.command_component_member(
          if entry.role == "sqlite" { 1 } else { 2 },
          source_sha, manifest_sha256, entry.sha256,
        ).map_err(issue => Physical(issue)) |> local_runtime_result
        if !local_runtime_bind_command_member(runtime, component) {
          local_runtime_stop(Changed)
        }
        if entry.role == "sqlite" {
          runtime.command_sqlite_member = Some(component)
        } else {
          runtime.command_crypto_member = Some(component)
        }
      }
      if entry.role == "sqlite" {
        runtime.sqlite = root_path + "/" + entry.path
      }
      if entry.role == "crypto" {
        runtime.crypto = root_path + "/" + entry.path
      }
    }
    runtime.assets = Some({
      environment: bodies.get("environment").unwrap(),
      registry: bodies.get("registry").unwrap(),
      values: bodies.get("values").unwrap(),
      fragment: bodies.get("fragment").unwrap(),
      ordered: bodies.get("ordered"),
      result_policy: bodies.get("result-policy").unwrap(),
    })
    runtime.ready = true
    match runtime.local_runtime_check_originals() {
      Ok(_) => Ok(runtime)
      Err(issue) => Err(issue)
    }
  } catch {
    LocalRuntimeStop(issue) => Err(issue)
  }
  result
}

///|
fn local_runtime_finish_open(
  runtime : NativeLocalPackagedRuntime,
  result : Result[NativeLocalPackagedRuntime, NativeLocalPackagedRuntimeIssue],
) -> Result[NativeLocalPackagedRuntime, NativeLocalPackagedRuntimeOpenIssue] {
  match local_runtime_read_finish(runtime, result) {
    Ok(value) => Ok(value)
    Err(issue) =>
      if runtime.close() is Ok(_) {
        Err(Refused(issue))
      } else {
        Err(Pending(runtime, issue))
      }
  }
}

///|
/// Verify both original named directories and opened file witnesses. An open
/// fd in a renamed package is not the package currently at its original path.
pub fn NativeLocalPackagedRuntime::check_current(
  self : NativeLocalPackagedRuntime,
) -> Result[Unit, NativeLocalPackagedRuntimeIssue] {
  match local_runtime_read_begin(self) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  local_runtime_read_finish(self, self.local_runtime_check_originals())
}

///|
/// Join the same already admitted Runtime Read to its same-Host consuming pair.
/// No Root, manifest, child, claim or byte allowance is recreated. The original
/// available Read may have observed the selected SQLite path before its one
/// consuming claim; every Runtime alias remains in that original inventory.
/// This exchange is one-shot and retains the pair even if the following whole
/// current check fails. Missing/foreign originals never select legacy reads.
pub fn NativeLocalPackagedRuntime::bind_original_host_resources(
  self : NativeLocalPackagedRuntime,
  resources : @arena.InstalledArenaLocalHostResources,
) -> Result[Unit, NativeLocalPackagedRuntimeIssue] {
  if !self.ready ||
    self.closed ||
    self.read_scope_entered ||
    self.original_resources is Some(_) ||
    self.reader is Some(_) ||
    self.reader_open_failure is Some(_) ||
    self.root_open_failure is Some(_) {
    return Err(Changed)
  }
  guard self.original_read is Some((host, read)) else {
    return Err(OriginalReadUnavailable)
  }
  match host.require_local_host_consuming_read_current(resources, read) {
    Err(issue) => return Err(OriginalHostResources(issue))
    Ok(_) => ()
  }
  self.original_resources = Some(resources)
  self.check_current()
}

///|
fn NativeLocalPackagedRuntime::local_runtime_check_originals(
  self : NativeLocalPackagedRuntime,
) -> Result[Unit, NativeLocalPackagedRuntimeIssue] {
  if !self.ready ||
    self.closed ||
    self.reader is Some(_) ||
    self.reader_open_failure is Some(_) ||
    self.root_open_failure is Some(_) {
    return Err(Changed)
  }
  if self.original_read is Some((host, original)) {
    let current = match self.original_resources {
      Some(resources) =>
        host
        .require_local_host_consuming_read_current(resources, original)
        .map_err(issue => OriginalHostResources(issue))
      None =>
        host
        .require_domain_original_read_current(original)
        .map_err(issue => OriginalRead(issue))
    }
    match current {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if self.original_resources is Some(_) {
    for root in self.roots {
      match root.require_current_original_read() {
        Err(issue) => return Err(Physical(issue))
        Ok(_) => ()
      }
    }
  }
  for directory in self.directories {
    match directory.check_current() {
      Err(issue) => return Err(Physical(issue))
      Ok(_) => ()
    }
  }
  for original in self.witnesses {
    match original.check_current() {
      Err(issue) => return Err(Physical(issue))
      Ok(_) => ()
    }
  }
  match self.local_runtime_product_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.original_read is Some((host, original)) {
    let current = match self.original_resources {
      Some(resources) =>
        host
        .require_local_host_consuming_read_current(resources, original)
        .map_err(issue => OriginalHostResources(issue))
      None =>
        host
        .require_domain_original_read_current(original)
        .map_err(issue => OriginalRead(issue))
    }
    match current {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
pub fn NativeLocalPackagedRuntime::manifest(
  self : NativeLocalPackagedRuntime,
) -> Result[@host.ClientNativeLocalRuntime, NativeLocalPackagedRuntimeIssue] {
  match local_runtime_read_begin(self) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = self
    .local_runtime_check_originals()
    .bind(_ => {
      match self.manifest {
        Some(value) => Ok(value)
        None => Err(InvalidManifest)
      }
    })
  local_runtime_read_finish(self, result)
}

///|
pub fn NativeLocalPackagedRuntime::assets(
  self : NativeLocalPackagedRuntime,
) -> Result[@host.ClientLocalProductAssets, NativeLocalPackagedRuntimeIssue] {
  match local_runtime_read_begin(self) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = self
    .local_runtime_check_originals()
    .bind(_ => {
      match self.assets {
        Some(value) => Ok(value)
        None => Err(InvalidManifest)
      }
    })
  local_runtime_read_finish(self, result)
}

///|
pub fn NativeLocalPackagedRuntime::library_paths(
  self : NativeLocalPackagedRuntime,
) -> Result[(String, String), NativeLocalPackagedRuntimeIssue] {
  match local_runtime_read_begin(self) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = self
    .local_runtime_check_originals()
    .map(_ => (self.sqlite, self.crypto))
  local_runtime_read_finish(self, result)
}

///|
/// Success is recorded after each actual close. A failed reader/root remains
/// held by this projection for retry; successful roots are never closed twice.
pub fn NativeLocalPackagedRuntime::close(
  self : NativeLocalPackagedRuntime,
) -> Result[Unit, NativeLocalPackagedRuntimeIssue] {
  if self.closed {
    return Ok(())
  }
  if self.read_scope_entered {
    match local_runtime_read_finish(self, Ok(())) {
      Err(_) => return Err(CleanupPending)
      Ok(_) => ()
    }
  }
  match local_runtime_read_begin(self, cleanup=true) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = local_runtime_read_finish(
    self,
    self.local_runtime_close_originals(),
  )
  if result is Ok(_) {
    self.closed = true
  }
  result
}

///|
// Root/Reader acknowledgement only. The outer installer must drop this
// Runtime and every escaped asset/result alias before closing original_read.
// Closing that carrier here would try to retire our own live managed receiver.
fn NativeLocalPackagedRuntime::local_runtime_close_originals(
  self : NativeLocalPackagedRuntime,
) -> Result[Unit, NativeLocalPackagedRuntimeIssue] {
  self.ready = false
  if self.reader_open_failure is Some(failure) {
    if failure.retry_cleanup() is Err(_) {
      return Err(CleanupPending)
    }
    self.reader_open_failure = None
  }
  if self.reader is Some(reader) {
    if reader.close() is Err(_) {
      return Err(CleanupPending)
    }
    self.reader = None
  }
  if self.root_open_failure is Some(failure) {
    if failure.retry_cleanup() is Err(_) {
      return Err(CleanupPending)
    }
    self.root_open_failure = None
  }
  while !self.roots.is_empty() {
    let root = self.roots[self.roots.length() - 1]
    if root.close() is Err(_) {
      return Err(CleanupPending)
    }
    ignore(self.roots.pop())
  }
  // Drop transient observations/material only after every original physical
  // close is acknowledged. Pending cleanup above keeps the same references.
  self.witnesses.clear()
  self.directories.clear()
  self.manifest = None
  self.assets = None
  self.selection = None
  self.product = None
  self.sqlite = ""
  self.crypto = ""
  Ok(())
}

///|
#borrow(runtime, component)
extern "C" fn local_runtime_bind_command_member(
  runtime : NativeLocalPackagedRuntime,
  component : @filesystem.NativeObservedComponentMember,
) -> Bool = "actql_native_client_bind_component_runtime"

///|
/// The exact two already hashed members of this same retained Runtime. These
/// observations cannot issue initial control coverage or permit a load without
/// the original trusted command bootstrap. Retain this Runtime through all
/// component users; normal close/current rules remain unchanged.
pub fn NativeLocalPackagedRuntime::command_library_members(
  self : NativeLocalPackagedRuntime,
) -> Result[
  (@filesystem.NativeObservedComponentMember, @filesystem.NativeObservedComponentMember),
  NativeLocalPackagedRuntimeIssue,
] {
  match self.check_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.command_sqlite_member is Some(sqlite) &&
    self.command_crypto_member is Some(crypto) else { return Err(Changed) }
  Ok((sqlite, crypto))
}
