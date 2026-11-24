// Each plural installation owns at least one distinct Mapping. The standard
// Check Environment admits at most 256 members in all sections together
// (run_publication_host/client_environment.mbt), so more installations cannot
// be admitted. Its byte/node/depth limits still apply to every composition.
// This is neither the source authority limit nor a Run's Effect Set limit.
export const MAX_INSTALLED_EFFECT_PROFILES = 256;
