///|
/// Read-only projection of the existing Runtime Owner's current originals.
/// No public JSON/CID/Bool constructor exists. It retains the same Runtime and
/// read carrier; this projection is not release trust or a successor admission.
struct NativeLocalVerifiedProductIdentity {
  runtime : NativeLocalPackagedRuntime
  metadata : @host.ClientNativeProductIdentity
}

///|
/// Obtain metadata only from the same successfully observed formal images,
/// descriptor digests and original runtime selection. Every allocation and
/// return value remains inside that Runtime's original read context.
pub fn NativeLocalPackagedRuntime::verified_product_identity(
  self : NativeLocalPackagedRuntime,
) -> Result[NativeLocalVerifiedProductIdentity, NativeLocalPackagedRuntimeIssue] {
  if self.original_read is None {
    return Err(OriginalReadUnavailable)
  }
  match local_runtime_read_begin(self) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = try {
    self.local_runtime_require_live() |> local_runtime_result
    guard self.product is Some(product) &&
      self.selection is Some((_, source, platform, manifest_hash)) &&
      product.native_image_sha256 is Some(image_hash) &&
      product.launcher_image_sha256 is Some(_) else {
      local_runtime_stop(InvalidManifest)
    }
    let metadata = @host.client_native_product_identity(
        product.launcher_descriptor_sha256,
        image_hash,
        platform,
        product.platform_descriptor_sha256,
        manifest_hash,
        source,
      ).map_err(_ => InvalidManifest)
      |> local_runtime_result
    Ok({ runtime: self, metadata, })
  } catch {
    LocalRuntimeStop(issue) => Err(issue)
  }
  local_runtime_read_finish(self, result)
}

///|
/// Return the same immutable metadata under its actual Read lifetime. The
/// explicit runtime observation owns package validation before this pure work;
/// a stored copy supplies no Host/Account/release authority.
pub fn NativeLocalVerifiedProductIdentity::wire(
  self : NativeLocalVerifiedProductIdentity,
) -> Result[String, NativeLocalPackagedRuntimeIssue] {
  match local_runtime_read_begin(self.runtime) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = try {
    self.runtime.local_runtime_require_live() |> local_runtime_result
    let wire = @host.client_native_product_identity_wire(self.metadata)
    Ok(wire)
  } catch {
    LocalRuntimeStop(issue) => Err(issue)
  }
  local_runtime_read_finish(self.runtime, result)
}
