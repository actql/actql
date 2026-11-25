import type {ProtocolSchema} from './interactive-run-control-schema.mjs';

export declare function checkInstallationPublicationStorageSchema(registry: Readonly<{
  artifact_schemas: Record<string, ProtocolSchema>;
  artifact_schema_cids: Record<string, string>;
  artifact_registry_cid: string;
}>): void;
