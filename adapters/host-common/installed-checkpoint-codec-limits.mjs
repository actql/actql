// Private codec bounds of the existing installed Checkpoint Owner. The review
// byte ceiling is the installed Host default; node/depth ceilings come from the
// existing checkpoint_runtime_node reader. These grant no resource capacity.
export const INSTALLED_EFFECT_CHECKPOINT_LIMITS = Object.freeze({
  maxWireBytes: 256 * 1024, maxNodes: 65536, maxDepth: 64,
});
