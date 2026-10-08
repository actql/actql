import {connect, type EmbeddedHostInstallation} from '@actql/node';
const installation: EmbeddedHostInstallation = {
  modelInstallation: {}, registerModelProviders: () => [],
  inferEvidence: {
    target: 'named', destination: 'local:independent-evaluator', maxBytes: 65536,
    authorize: binding => binding.purpose === 'capture',
    sink: {capture: async () => ({status: 'incomplete', reason: 'RequiredEvidenceUnavailable'}), record: async () => {}},
  },
};
void connect({mode: 'local', owner: 'local', durability: 'durable', installation});
