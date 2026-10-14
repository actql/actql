///|
// Physical projection of the existing filesystem Owner, not an authority or
// compatibility issuer. Only this whole-member reader can construct it.
struct NativeLocalPackagedRuntime {
  mut manifest : @host.ClientNativeLocalRuntime?
  mut assets : @host.ClientLocalProductAssets?
  roots : Array[@filesystem.Root]
  witnesses : Array[
    (@filesystem.Root, String, @filesystem.NativeFileGeneration),
  ]
  mut reader : @filesystem.Reader?
  mut reader_open_failure : @filesystem.NativeReaderOpenFailure?
  mut sqlite : String
  mut crypto : String
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
  CleanupPending
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
fn local_runtime_read_member(
  runtime : NativeLocalPackagedRuntime,
  root : @filesystem.Root,
  name : String,
  bytes : Int64,
  hash : String,
  collect : Bool,
) -> String raise LocalRuntimeStop {
  let generation = local_runtime_result(
    root.inspect_generation(name).map_err(issue => Physical(issue)),
  ).unwrap_or_else(() => local_runtime_stop(Changed))
  if bytes < 1L ||
    generation.size != bytes ||
    bytes > 67108864L ||
    (collect && bytes > 65536L) {
    local_runtime_stop(Limit)
  }
  let reader = match root.open_reader_with_custody(name, generation) {
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
  reader.finish().map_err(issue => Physical(issue)) |> local_runtime_result
  runtime.reader = None
  let digest = @sha.finish_hex(hasher) catch { _ => local_runtime_stop(Limit) }
  if digest != hash || !root.verify_generation(name, generation) {
    local_runtime_stop(Changed)
  }
  runtime.witnesses.push((root, name, generation))
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
  if !root_path.has_prefix("/") ||
    root_path.length() > 4096 ||
    root_path.contains("\u{0000}") ||
    root_path.has_suffix("/") ||
    root_path.contains("//") ||
    root_path.split("/").any(part => part == "." || part == "..") {
    return Err(Refused(InvalidInput))
  }
  let root = match @filesystem.open_root(root_path) {
    Ok(value) => value
    Err(issue) => return Err(Refused(Physical(issue)))
  }
  let runtime : NativeLocalPackagedRuntime = {
    manifest: None,
    assets: None,
    roots: [root],
    witnesses: [],
    reader: None,
    reader_open_failure: None,
    sqlite: "",
    crypto: "",
    ready: false,
    closed: false,
  }
  let result = try {
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
    let bodies : Map[String, String] = Map([])
    for entry in @host.client_native_local_runtime_members(manifest) {
      let parts = entry.path.split("/").map(part => part.to_owned()).to_array()
      let parent = root.open_child(parts[0]).map_err(issue => Physical(issue))
        |> local_runtime_result
      runtime.roots.push(parent)
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
    match runtime.check_current() {
      Ok(_) => Ok(runtime)
      Err(issue) => Err(issue)
    }
  } catch {
    LocalRuntimeStop(issue) => Err(issue)
  }
  match result {
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
/// Verify the original opened file witnesses, never fresh-stat replacement.
pub fn NativeLocalPackagedRuntime::check_current(
  self : NativeLocalPackagedRuntime,
) -> Result[Unit, NativeLocalPackagedRuntimeIssue] {
  if !self.ready ||
    self.closed ||
    self.reader is Some(_) ||
    self.reader_open_failure is Some(_) ||
    !self.witnesses.all(w => w.0.verify_generation(w.1, w.2)) {
    Err(Changed)
  } else {
    Ok(())
  }
}

///|
pub fn NativeLocalPackagedRuntime::manifest(
  self : NativeLocalPackagedRuntime,
) -> Result[@host.ClientNativeLocalRuntime, NativeLocalPackagedRuntimeIssue] {
  self
  .check_current()
  .bind(_ => {
    match self.manifest {
      Some(value) => Ok(value)
      None => Err(InvalidManifest)
    }
  })
}

///|
pub fn NativeLocalPackagedRuntime::assets(
  self : NativeLocalPackagedRuntime,
) -> Result[@host.ClientLocalProductAssets, NativeLocalPackagedRuntimeIssue] {
  self
  .check_current()
  .bind(_ => {
    match self.assets {
      Some(value) => Ok(value)
      None => Err(InvalidManifest)
    }
  })
}

///|
pub fn NativeLocalPackagedRuntime::library_paths(
  self : NativeLocalPackagedRuntime,
) -> Result[(String, String), NativeLocalPackagedRuntimeIssue] {
  self.check_current().map(_ => (self.sqlite, self.crypto))
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
  self.manifest = None
  self.assets = None
  self.sqlite = ""
  self.crypto = ""
  self.closed = true
  Ok(())
}
