// Maintained tests execute the real Vite-built module. Derive these static
// field views from the existing public component declarations; no duplicate
// prop schema or TSX runtime emit is introduced into root preparation.
declare module '*dist/plan-explorer.js' {
  const CheckpointPanel: typeof import('actql-explorer-test-contracts/checkpoint-panel').CheckpointPanel;
  const CancellationPanel: typeof import('actql-explorer-test-contracts/cancellation-panel').CancellationPanel;
  export {CheckpointPanel, CancellationPanel};
}
