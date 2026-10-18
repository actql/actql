///|
// Code roots only. Matching regular Native C must establish callback types and
// ownership before a C shim can be linked. No callback loads Crypto or keys.
extern "C" fn register_local_adoption_binding_roots_ffi(
  prepare : FuncRef[
    (
      @arena.InstalledArenaHost,
      @arena.InstalledArenaLocalHostResources,
      @arena.InstalledArenaOriginalRead,
      @crypto.Library,
      String,
      String,
      String,
      String,
      String,
      FixedArray[String],
      String,
      Bool,
      Int,
    ) -> NativeLocalAdoptionBinding,
  ],
  operate : FuncRef[
    (NativeLocalAdoptionBinding, Int) -> NativeLocalAdoptionBindingReply,
  ],
  journal : FuncRef[
    (NativeLocalAdoptionBinding, Double, Int, Int64) -> NativeLocalAdoptionBindingReply,
  ],
  original : FuncRef[
    (NativeLocalAdoptionBindingReply) -> NativeLocalAdoptionBinding,
  ],
  host : FuncRef[(NativeLocalAdoptionBinding) -> @arena.InstalledArenaHost],
  pair : FuncRef[
    (NativeLocalAdoptionBinding) -> @arena.InstalledArenaLocalHostResources,
  ],
  read : FuncRef[
    (NativeLocalAdoptionBinding) -> @arena.InstalledArenaOriginalRead,
  ],
  crypto : FuncRef[(NativeLocalAdoptionBinding) -> @crypto.Library],
  session : FuncRef[(NativeLocalAdoptionBinding) -> NativeLocalAdoptionSession?],
  original_journal : FuncRef[
    (NativeLocalAdoptionBinding) -> NativeLocalJournalCapture?,
  ],
  cleanup_ack : FuncRef[(NativeLocalAdoptionBinding) -> Bool],
  operation : FuncRef[(NativeLocalAdoptionBindingReply) -> Int],
  issue : FuncRef[(NativeLocalAdoptionBindingReply) -> Int],
) -> Unit = "actql_native_control_register_local_adoption_binding_roots"

///|
/// Register the private same-provider transport without opening any resource.
/// Actual Crypto and the independently admitted Host/pair/Read are inputs;
/// selection text and code registration cannot manufacture those originals.
pub fn register_native_local_adoption_binding_roots() -> Unit {
  register_local_adoption_binding_roots_ffi(
    fn(
      host,
      pair,
      read,
      crypto,
      parent_path,
      state_name,
      source_path,
      source_name,
      account_id,
      configuration_files,
      managed_root_path,
      has_managed_root,
      diagnostic_ceiling,
    ) {
      let files : Array[String] = []
      for name in configuration_files {
        files.push(name)
      }
      prepare_local_adoption_binding(
        host,
        pair,
        read,
        crypto,
        {
          parent_path,
          state_name,
          source_path,
          source_name,
          account_id,
          configuration_files: files,
          managed_root_path: if has_managed_root {
            Some(managed_root_path)
          } else {
            None
          },
        },
        diagnostic_ceiling,
      )
    },
    fn(original, operation) { original.operate(operation) },
    fn(original, ttl, records, snapshot) {
      original.capture_journal(ttl, records, snapshot)
    },
    fn(reply) { reply.original },
    fn(original) { original.host },
    fn(original) { original.pair },
    fn(original) { original.read },
    fn(original) { original.crypto },
    fn(original) {
      match original.capture {
        Some(capture) => capture.original_session()
        None => None
      }
    },
    fn(original) {
      match original.capture {
        Some(capture) => capture.original_journal()
        None => None
      }
    },
    fn(original) { original.descriptor_cleanup_acknowledged() },
    fn(reply) { reply.operation },
    fn(reply) { reply.issue_family() },
  )
}
