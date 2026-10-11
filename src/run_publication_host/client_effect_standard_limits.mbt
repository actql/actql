///|
/// Standard Client static preparation bounds shared by installed Host
/// bindings. They grant no physical capacity, approval or dispatch authority.
pub fn client_standard_effect_computation_limits() -> ClientEffectComputationLimits {
  {
    program: client_standard_program_preparation_limits(),
    max_members: 1024,
    max_header_work: 1000000,
    mapping: {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    },
    max_mapping_work: 100000,
    effects: {
      max_members: 1024,
      max_work: 1000000,
      max_admission_nodes: 100000,
      max_admission_depth: 64,
      max_admission_text_bytes: 1000000,
    },
  }
}
