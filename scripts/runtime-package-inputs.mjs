// The ordinary runtime builder and interface inventory read the same inputs.
import {localNodePackageInputs} from './local-node-package-inputs.mjs';

export function runtimePackageInputs(root) {
return {
  'run-host-core': {sources: ['client_values_host_abi', 'checkpoint_runtime_node',
    'connectors_workers_bridge'],
    script: 'build-run-host-core-package', args: ['--runtime-only'],
    files: ['packages/run-host-core/dist/client_values_host_abi.js',
      'packages/run-host-core/dist/checkpoint_runtime_node.js',
      'packages/run-host-core/dist/workers_finite.js',
      'packages/run-host-core/dist/workers_finite_payload.js']},
  'coordinator-core': {sources: ['remote_coordinator_abi'],
    script: 'build-remote-coordinator-package',
    files: ['packages/coordinator-core/dist/remote_coordinator_abi.js']},
  'transfer-core': {sources: ['remote_transfer_abi'],
    script: 'build-remote-transfer-package',
    files: ['packages/transfer-core/dist/remote_transfer_abi.js']},
  get 'local-node'() {
    const local = localNodePackageInputs(root);
    return {sources: local.runtimePackages, script: 'build-local-node-assets',
      files: local.runtimeFiles.map(path => `packages/local-node/_build/js/release/build/${path}`)};
  },
};
}
