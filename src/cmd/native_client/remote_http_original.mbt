///|
priv struct RemoteHttpOriginal {
  raw_reply : Bool
  mut read_open : Bool
  mut library : @http.Library?
  mut client : @http.Client?
  mut failed_library : @http.NativeHttpLibraryLoadFailure?
  mut failed_client : @http.NativeHttpClientCreateFailure?
}

///|
priv enum RemoteHttpTransport {
  Compatibility(@http.Client)
  Scoped(LocalCommandPreparationOriginal, RemoteHttpOriginal)
}

///|
extern "C" fn native_remote_http_requires_original_ffi() -> Bool = "actql_native_remote_http_requires_original"

///|
#borrow(original)
extern "C" fn native_remote_http_copy_body(original : Bytes) -> Bytes = "actql_native_remote_http_copy_body"

///|
// Fund the transport separately from protocol parsing. During one request the
// native receive buffer can overlap its replacement, or its exact MoonBit
// copy. Parsing and rendering consume only detached DATA after Read leave.
fn remote_http_budget(
  limits : @initial_arena.InstalledArenaOriginalReadBudget,
  response_max : Int,
) -> @initial_arena.InstalledArenaOriginalReadBudget? {
  if response_max <= 0 || response_max > 16777216 {
    return None
  }
  let execution = 33554432L + 3L * response_max.to_int64()
  if execution > limits.read_execution {
    return None
  }
  Some({ ..limits, read_execution: execution, })
}

///|
fn RemoteHttpOriginal::enter(
  self : RemoteHttpOriginal,
  owner : LocalCommandPreparationOriginal,
  cleanup? : Bool = false,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard !self.read_open && owner.host is Some(host) && owner.read is Some(read) else {
    return Err(CommandUnavailable)
  }
  let entered = if cleanup {
    host.enter_domain_original_read_cleanup(read)
  } else {
    host.enter_domain_original_read(read)
  }
  match entered {
    Err(issue) => Err(CommandRead(issue))
    Ok(_) => {
      self.read_open = true
      Ok(())
    }
  }
}

///|
fn RemoteHttpOriginal::leave(
  self : RemoteHttpOriginal,
  owner : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  if !self.read_open {
    return Ok(())
  }
  guard owner.host is Some(host) && owner.read is Some(read) else {
    return Err(CommandUnavailable)
  }
  match host.leave_domain_original_read(read) {
    Err(issue) => Err(CommandRead(issue))
    Ok(_) => {
      self.read_open = false
      Ok(())
    }
  }
}

///|
fn RemoteHttpOriginal::acquire_library(
  self : RemoteHttpOriginal,
  path : String,
  diagnostic_ceiling : Int,
) -> Bool {
  match
    @http.load_library_with_custody(
      path,
      diagnostic_ceiling=Some(diagnostic_ceiling),
    ) {
    Ok(library) => {
      self.library = Some(library)
      true
    }
    Err(CleanupRequired(original)) => {
      self.failed_library = Some(original)
      false
    }
    Err(RefusedBeforeAcquisition(_)) => false
  }
}

///|
fn RemoteHttpOriginal::acquire_client(
  self : RemoteHttpOriginal,
  ca : String,
  certificate : String,
  key : String,
  response_max : Int,
) -> Bool {
  guard self.library is Some(library) else { return false }
  match
    library.create_client_with_custody(
      ca,
      certificate,
      key,
      response_max.to_int64(),
      5000,
      30000,
    ) {
    Ok(client) => {
      self.client = Some(client)
      true
    }
    Err(CleanupRequired(original)) => {
      self.failed_client = Some(original)
      false
    }
    Err(RefusedBeforeAcquisition(_)) => false
  }
}

///|
fn RemoteHttpOriginal::close(
  self : RemoteHttpOriginal,
  owner : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  try {
    command_preparation_value(self.leave(owner))
    if self.failed_library is None &&
      self.failed_client is None &&
      self.client is None &&
      self.library is None {
      return Ok(())
    }
    command_preparation_value(self.enter(owner, cleanup=true))
    if self.failed_library is Some(original) {
      command_preparation_value(
        original.retry_cleanup().map_err(_ => CommandRemoteHttpCleanup),
      )
      self.failed_library = None
    }
    if self.failed_client is Some(original) {
      guard self.library is Some(library) else {
        return Err(CommandRemoteHttpCleanup)
      }
      let returned = command_preparation_value(
        original.retry_cleanup().map_err(_ => CommandRemoteHttpCleanup),
      )
      if !physical_equal(returned, library) {
        return Err(CommandRemoteHttpCleanup)
      }
      self.failed_client = None
    }
    if self.client is Some(client) {
      command_preparation_value(
        client.close_checked().map_err(_ => CommandRemoteHttpCleanup),
      )
      self.client = None
    }
    if self.library is Some(library) {
      command_preparation_value(
        library.close_checked().map_err(_ => CommandRemoteHttpCleanup),
      )
      self.library = None
    }
    command_preparation_value(self.leave(owner))
    Ok(())
  } catch {
    LocalCommandPreparationStop(issue) => Err(issue)
  }
}

///|
fn begin_remote_http_transport(
  matches : @argparse.Matches,
  response_max : Int,
) -> RemoteHttpTransport raise ClientStop {
  let path = required(matches, "http-library")
  let ca = required(matches, "ca")
  let certificate = required(matches, "cert")
  let key = required(matches, "key")
  if !native_remote_http_requires_original_ffi() {
    let library = @http.load_library(path).unwrap_or_else(() => {
      stop("native HTTPS library unavailable")
    })
    let client = library
      .create_client(ca, certificate, key, response_max.to_int64(), 5000, 30000)
      .unwrap_or_else(() => stop("native HTTPS client unavailable"))
    return Compatibility(client)
  }
  guard command_preparation_invocation.val is None &&
    command_preargument_retained_context() is Ok(Some(context)) &&
    command_preargument_source() is Ok(compiled) else {
    stop("RemoteHttpOriginalUnavailable")
  }
  let (_, source, platform, manifest) = local_product_context(context)
  if compiled != source || !command_compiled_platform_matches(platform) {
    stop("RemoteHttpOriginalUnavailable")
  }
  let profile = local_command_installed_profile(compiled, manifest)
  // All caps and the installer-owned backing profile precede the constructor.
  let budget = remote_http_budget(profile.read_budget, response_max).unwrap_or_else(() => {
      stop("RemoteHttpCapacityUnavailable")
    },
  )
  let owner = command_preparation_result(
    prepare_local_command_preparation_original(profile),
  )
  let original : RemoteHttpOriginal = {
    raw_reply: matches.subcommand is Some(("read", _)),
    read_open: false,
    library: None,
    client: None,
    failed_library: None,
    failed_client: None,
  }
  owner.remote_http = Some(original)
  command_preparation_invocation.val = Some(owner)
  command_preparation_result(
    owner.acquire_physical_read(remote_budget=Some(budget)),
  )
  command_preparation_result(original.enter(owner))
  let library_ready = original.acquire_library(path, profile.diagnostic_ceiling)
  let client_ready = library_ready &&
    original.acquire_client(ca, certificate, key, response_max)
  command_preparation_result(original.leave(owner))
  if !library_ready {
    stop("native HTTPS library unavailable")
  }
  if !client_ready {
    stop("native HTTPS client unavailable")
  }
  Scoped(owner, original)
}

///|
fn RemoteHttpTransport::post(
  self : RemoteHttpTransport,
  url : String,
  headers : Array[@http.NativeHttpHeader],
  body : Bytes,
) -> @http.NativeHttpResponse? {
  match self {
    Compatibility(client) =>
      client.request(@http.Post, url, headers, body).to_option()
    Scoped(owner, original) => {
      guard original.client is Some(client) &&
        owner.host is Some(host) &&
        owner.read is Some(read) &&
        original.enter(owner) is Ok(_) else {
        return None
      }
      let issued = client.request(@http.Post, url, headers, body)
      let current = host.require_domain_original_read_current(read) is Ok(_)
      if original.leave(owner) is Err(_) || !current {
        // The original operation may have reached the Host. Let the existing
        // request-specific Unknown path keep its reference and do not resend.
        return None
      }
      match issued {
        Err(_) => None
        Ok(response) =>
          Some({
            status: response.status,
            body: native_remote_http_copy_body(response.body),
          })
      }
    }
  }
}

///|
fn RemoteHttpTransport::finish_compatibility(
  self : RemoteHttpTransport,
) -> Unit {
  if self is Compatibility(client) {
    ignore(client.close())
  }
}
