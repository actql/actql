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
const multiple: EmbeddedHostInstallation = {...installation, inferEvidence: {
  ...installation.inferEvidence!, target: ['first_assessment', 'second_assessment'] as const,
}};
void connect({mode: 'local', owner: 'local', durability: 'durable', installation: multiple});
const invalid: EmbeddedHostInstallation = {...installation, inferEvidence: {
  ...installation.inferEvidence!,
  // @ts-expect-error Logical target names cannot be physical row offsets.
  target: ['first_assessment', 1],
}};
void invalid;

const typedInput: EmbeddedHostInstallation = {...installation, inferEvidence: {
  ...installation.inferEvidence!, kind: 'typed-input',
}};
void connect({mode: 'local', owner: 'local', installation: typedInput});
const invalidKind: EmbeddedHostInstallation = {...installation, inferEvidence: {
  ...installation.inferEvidence!,
  // @ts-expect-error Only an explicit typed-input projection extends the full default.
  kind: 'reconstructed-physical',
}};
void invalidKind;
