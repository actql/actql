// Maintained tests execute the real Vite-built module. Derive these static
// field views from the existing public component declarations; no duplicate
// prop schema or TSX runtime emit is introduced into root preparation.
declare module '*dist/plan-explorer.js' {
  function CheckpointPanel(props: import('actql-explorer-test-contracts/checkpoint-review').CheckpointPanelProps):
    import('react').JSX.Element;
  function CancellationPanel(props: import('actql-explorer-test-contracts/cancellation-types').CancellationPanelProps):
    import('react').JSX.Element;
  export {CheckpointPanel, CancellationPanel};
}
