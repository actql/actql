///|
/// Read-only transport of the same existing whole-product Runtime Owner.
/// Metadata is neither installed origin, release trust, nor Host authority.
struct NativeLocalPackagedProductReply {
  runtime : NativeLocalPackagedRuntime
  operation : Int
  issue : NativeLocalPackagedRuntimeIssue?
  metadata : String?
}

///|
pub fn observe_native_local_packaged_product_reply(
  runtime : NativeLocalPackagedRuntime,
  launcher_root : String,
  launcher_descriptor_sha256 : String,
  platform_descriptor_sha256 : String,
  diagnostic_ceiling : Int,
) -> NativeLocalPackagedProductReply {
  let result = if runtime.original_read is None {
    Err(OriginalReadUnavailable)
  } else {
    runtime.observe_product_members(
      launcher_root, launcher_descriptor_sha256, platform_descriptor_sha256, diagnostic_ceiling,
    )
  }
  {
    runtime,
    operation: 4,
    metadata: None,
    issue: match result {
      Ok(_) => None
      Err(issue) => Some(issue)
    },
  }
}

///|
/// The selected command consumes its already observed immutable product.
/// An internal FFI projection is not another package-validation boundary.
/// The separate unscoped entrance observes current product originals once.
pub fn read_native_local_packaged_product_reply(
  runtime : NativeLocalPackagedRuntime,
) -> NativeLocalPackagedProductReply {
  let result = if runtime.original_read is None {
    Err(OriginalReadUnavailable)
  } else if runtime.command_preparation {
    runtime.verified_product_identity().bind(identity => identity.wire())
  } else {
    runtime
    .check_product_current()
    .bind(_ => {
      runtime.verified_product_identity().bind(identity => identity.wire())
    })
  }
  let (metadata, issue) = match result {
    Ok(wire) => (Some(wire), None)
    Err(issue) => (None, Some(issue))
  }
  { runtime, operation: 5, metadata, issue, }
}

///|
pub fn NativeLocalPackagedProductReply::original_host(
  self : NativeLocalPackagedProductReply,
) -> @arena.InstalledArenaHost? {
  self.runtime.original_read.map(value => value.0)
}

///|
pub fn NativeLocalPackagedProductReply::original_read(
  self : NativeLocalPackagedProductReply,
) -> @arena.InstalledArenaOriginalRead? {
  self.runtime.original_read.map(value => value.1)
}

///|
pub fn NativeLocalPackagedProductReply::original_runtime(
  self : NativeLocalPackagedProductReply,
) -> NativeLocalPackagedRuntime {
  self.runtime
}

///|
pub fn NativeLocalPackagedProductReply::operation_tag(
  self : NativeLocalPackagedProductReply,
) -> Int {
  self.operation
}

///|
pub fn NativeLocalPackagedProductReply::issue_family(
  self : NativeLocalPackagedProductReply,
) -> Int {
  local_packaged_runtime_issue_tag(self.issue)
}

///|
/// The existing closed metadata intake is at most4096 bytes. Its canonical
/// ASCII fields also fit4096 UTF-16 units; this is transport, not read permission.
pub fn NativeLocalPackagedProductReply::metadata_units(
  self : NativeLocalPackagedProductReply,
) -> Int {
  guard self.operation == 5 &&
    self.issue is None &&
    self.metadata is Some(wire) &&
    wire.length() > 0 &&
    wire.length() <= 4096 else {
    return -1
  }
  wire.length()
}

///|
pub fn NativeLocalPackagedProductReply::metadata_unit_at(
  self : NativeLocalPackagedProductReply,
  index : Int,
) -> Int {
  let length = self.metadata_units()
  guard index >= 0 && index < length && self.metadata is Some(wire) else {
    return -1
  }
  wire.at(index).to_int()
}
