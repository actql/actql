///|
// The original filesystem/adoption failure carrier retains these same partial
// Roots and Lock before opening. No separate Owner or cleanup authority exists.
priv enum NativeLocalProductConfigurationOpening {
  ProductNotAttempted
  ProductOpenUnconfirmed
  ProductAcquired(NativeLocalProductConfigurationSession)
  ProductRefused
}

///|
/// Trusted installed preparation only. The optional originals select explicit
/// initialization versus restore, not permission or evidence of first use.
/// The same original product marker and exclusive constructor still decide.
struct NativeLocalProductConfigurationCapture {
  parent_path : String
  directory_name : String
  crypto : @crypto.Library
  originals : Array[(String, Bytes)]?
  root_opening : NativeLocalAdoptionRootOpening
  original : NativeLocalAdoptionOpenFailure
  mut opening : NativeLocalProductConfigurationOpening
  mut operation_failed : Bool
  mut closing : Bool
  mut cleanup_acknowledged : Bool
}

///|
fn local_product_open_parent(
  path : String,
  custody : NativeLocalAdoptionOpenFailure?,
  opening : NativeLocalAdoptionRootOpening,
) -> Result[@filesystem.Root, NativeLocalAdoptionIssue] {
  match opening {
    LegacyPrivateRoots =>
      @filesystem.open_root(path).map_err(issue => Filesystem(issue))
    CurrentOriginalReadRoots(ceiling) => {
      guard custody is Some(original) else { return Err(InvalidInput) }
      @filesystem.open_root_in_current_read_context_with_custody(path, ceiling).map_err(failure => {
          original.root_acquisition = Some(failure)
          Filesystem(failure.issue())
        },
      )
    }
  }
}

///|
/// Retain this actual capture before open. No I/O, key generation, Resource
/// claim or configuration authority is issued by the selection DATA itself.
pub fn prepare_native_local_product_configuration_capture_in_current_read_context(
  parent_path : String,
  directory_name : String,
  crypto : @crypto.Library,
  diagnostic_ceiling : Int,
  originals? : Array[(String, Bytes)]? = None,
) -> Result[NativeLocalProductConfigurationCapture, NativeLocalAdoptionIssue] {
  if !local_adoption_name(directory_name) ||
    parent_path.length() > 4096 ||
    diagnostic_ceiling <= 0 {
    return Err(InvalidInput)
  }
  let snapshot = match originals {
    None => None
    Some(values) => {
      let values = values.copy()
      values.sort_by((a, b) => a.0.compare(b.0))
      if !product_original_names(values) {
        return Err(InvalidInput)
      }
      Some(values)
    }
  }
  Ok({
    parent_path,
    directory_name,
    crypto,
    originals: snapshot,
    root_opening: CurrentOriginalReadRoots(diagnostic_ceiling),
    original: new_local_adoption_open_failure(),
    opening: ProductNotAttempted,
    operation_failed: false,
    closing: false,
    cleanup_acknowledged: false,
  })
}

///|
// Publish the original before entering constructor work. Failed return cannot
// replace it or turn an uncertain creation into restore/initialization retry.
pub fn NativeLocalProductConfigurationCapture::open(
  self : NativeLocalProductConfigurationCapture,
) -> Result[NativeLocalProductConfigurationSession, NativeLocalAdoptionIssue] {
  if self.closing {
    return Err(Closed)
  }
  if self.opening is ProductNotAttempted {
    self.opening = ProductOpenUnconfirmed
    let result = match self.originals {
      None =>
        restore_native_local_product_configuration_original(
          self.parent_path,
          self.directory_name,
          self.crypto,
          custody=Some(self.original),
          root_opening=self.root_opening,
        )
      Some(values) =>
        begin_native_local_product_configuration_original(
          self.parent_path,
          self.directory_name,
          values,
          self.crypto,
          custody=Some(self.original),
          root_opening=self.root_opening,
        )
    }
    self.opening = match result {
      Ok(session) => ProductAcquired(session)
      Err(issue) => {
        self.original.original_issue = issue
        ProductRefused
      }
    }
  }
  match self.opening {
    ProductAcquired(session) => Ok(session)
    ProductRefused => Err(self.original.issue())
    _ => Err(OriginalResourceScopePending)
  }
}

///|
/// Keep a failed original Reader/Writer in the same capture through cleanup.
/// A durable claim already attempted by stage_configuration is never reset.
pub fn NativeLocalProductConfigurationCapture::stage_configuration(
  self : NativeLocalProductConfigurationCapture,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.closing {
    return Err(Closed)
  }
  if self.operation_failed {
    return Err(self.original.issue())
  }
  guard self.opening is ProductAcquired(session) else {
    return Err(InvalidInput)
  }
  match session.stage_configuration() {
    Ok(_) => Ok(())
    Err(issue) => {
      self.original.original_issue = issue
      self.operation_failed = true
      Err(issue)
    }
  }
}

///|
/// No read or staging replay. The same partial I/O must acknowledge cleanup
/// before the original Roots and Lock can retire. A lost operation stays open.
pub fn NativeLocalProductConfigurationCapture::close(
  self : NativeLocalProductConfigurationCapture,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  self.closing = true
  if self.cleanup_acknowledged {
    return Ok(())
  }
  if self.opening is ProductOpenUnconfirmed {
    return Err(OriginalResourceScopePending)
  }
  match self.original.retry_cleanup() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.opening is ProductAcquired(session) {
    // The original carrier has already retired child I/O and Roots before
    // checking this same Lock. Its checked entrance preserves the actual ACK;
    // the legacy first-close Bool must not be invoked a second time.
    match session.lock.close_checked() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => {
        session.closed = true
        session.close_pending = false
      }
    }
  }
  self.cleanup_acknowledged = true
  Ok(())
}

///|
/// Descriptor acknowledgement only. Returned Session/material aliases, the
/// physical Read and Library/domain/Host remain their actual owner's duties.
pub fn NativeLocalProductConfigurationCapture::descriptor_cleanup_acknowledged(
  self : NativeLocalProductConfigurationCapture,
) -> Bool {
  self.cleanup_acknowledged
}
