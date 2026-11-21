type Scalar = string | bigint | number | boolean | undefined | null;
interface OriginalRuntime {
    clientProgramReadModelResponseProfile?(wire: string, cid: string, maxBytes: number, maxNodes: number, maxDepth: number, maxMembers: number, maxWork: number): unknown;
    clientProgramAdmitEffectDependencyBody?(kind: string, cid: string, wire: string, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
}
export declare function snapshotOpenAIOriginalMaterials(value: unknown): Readonly<{
    responseProfile: Readonly<{
        cid: string;
        wire: string;
    } & Partial<{}>>;
    policyOriginals: Readonly<{
        retention: Readonly<{
            cid: string;
            wire: string;
        } & Partial<{}>>;
        metadata: Readonly<{
            cid: string;
            wire: string;
        } & Partial<{}>>;
        clock: Readonly<{
            cid: string;
            wire: string;
        } & Partial<{}>>;
        data: Readonly<{
            cid: string;
            wire: string;
        } & Partial<{}>>;
    } & Partial<{}>>;
    readerLimits: Readonly<Record<"maxBytes" | "maxNodes" | "maxDepth" | "maxMembers" | "maxWork", number>>;
    installation: Readonly<{
        sdk: Readonly<{
            interface: Scalar;
            lock_artifact_cid: Scalar;
            package_name: Scalar;
            version: Scalar;
        } & Partial<{}>>;
        build_artifact_cid: Scalar;
        builder_id: Scalar;
        builder_revision: Scalar;
        codec_id: Scalar;
        codec_revision: Scalar;
        completion_basis: Scalar;
        endpoint: Scalar;
        http_method: Scalar;
        streaming: Scalar;
        validator_artifact_cid: Scalar;
        validator_id: Scalar;
        validator_revision: Scalar;
    } & Partial<{}>>;
    rawCaptureSelection: Readonly<{
        selectionAvailable: Function;
        availableUntil: Scalar;
        deleteBy: Scalar;
        extensionCeilingAt: Scalar;
        metadataDeleteBy: Scalar;
        selectedAt: Scalar;
    } & Partial<{}>>;
} & {
    [key: string]: Readonly<{
        cid: string;
        wire: string;
    } & Partial<{}>> | Readonly<{
        retention: Readonly<{
            cid: string;
            wire: string;
        } & Partial<{}>>;
        metadata: Readonly<{
            cid: string;
            wire: string;
        } & Partial<{}>>;
        clock: Readonly<{
            cid: string;
            wire: string;
        } & Partial<{}>>;
        data: Readonly<{
            cid: string;
            wire: string;
        } & Partial<{}>>;
    } & Partial<{}>> | Readonly<Record<"maxBytes" | "maxNodes" | "maxDepth" | "maxMembers" | "maxWork", number>> | Readonly<{
        bootstrap: Readonly<{
            maxDelegations: number;
            maxHoldings: number;
            maxReservations: number;
            bootstrapExecutionBytes: bigint;
            bootstrapRetainedBytes: bigint;
        } & Partial<{}>>;
        modelExecutionBytes: bigint;
        modelRetainedBytes: bigint;
        nodeInstallation: Readonly<{
            runtimeArtifactCid: string;
            layoutArtifactCid: string;
            layout: Readonly<({
                execution_bytes: bigint;
                prepared_rows: bigint;
                retained_bytes: bigint;
                layout_artifact_cid: string;
                runtime_artifact_cid: string;
            } | {
                execution_bytes: bigint;
                prepared_rows: bigint;
                retained_bytes: bigint;
                layout_artifact_cid: string;
                runtime_artifact_cid: string;
                barrier_cid: string;
                parameter_values_cid: string;
                program_definition_cid: string;
            }) & Partial<{}>>;
        } & Partial<{}>>;
    } & Partial<{
        storeBootstrap: Readonly<{
            maxDirectoryEntries: number;
            maxWireBytes: number;
        } & Partial<{}>>;
        publicationCapacity: Readonly<{
            retainedBytes: bigint;
            workspaceBytes: bigint;
        } & Partial<{}>>;
        metadataAcquisition: Readonly<{
            retainedBytes: bigint;
            workspaceBytes: bigint;
            metadata: Readonly<{
                maxWireBytes: number;
                maxLedgerEntries: number;
            } & Partial<{}>>;
            directory: Readonly<{
                maxDirectoryEntries: number;
                maxWireBytes: number;
            } & Partial<{}>>;
        } & Partial<{}>>;
        currentStateCodec: Readonly<{
            quantum: number;
            comparisonWork: number;
            decode: Readonly<{
                maxWork: number;
                parse: Readonly<{
                    max_depth: number;
                    max_input_bytes: number;
                    max_nodes: number;
                } & Partial<{}>>;
                tree: Readonly<{
                    max_depth: number;
                    max_nodes: number;
                    max_string_bytes: number;
                    max_total_string_bytes: number;
                } & Partial<{}>>;
            } & Partial<{}>>;
        } & Partial<{}>>;
    }>> | Readonly<{
        selectionAvailable: Function;
        availableUntil: Scalar;
        deleteBy: Scalar;
        extensionCeilingAt: Scalar;
        metadataDeleteBy: Scalar;
        selectedAt: Scalar;
    } & Partial<{}>> | Readonly<{
        sdk: Readonly<{
            interface: Scalar;
            lock_artifact_cid: Scalar;
            package_name: Scalar;
            version: Scalar;
        } & Partial<{}>>;
        build_artifact_cid: Scalar;
        builder_id: Scalar;
        builder_revision: Scalar;
        codec_id: Scalar;
        codec_revision: Scalar;
        completion_basis: Scalar;
        endpoint: Scalar;
        http_method: Scalar;
        streaming: Scalar;
        validator_artifact_cid: Scalar;
        validator_id: Scalar;
        validator_revision: Scalar;
    } & Partial<{}>> | undefined;
} & Partial<{}>>;
export declare function admitOpenAIOriginalMaterials(moon: OriginalRuntime, materials: ReturnType<typeof snapshotOpenAIOriginalMaterials>): Readonly<{
    [x: string]: Readonly<{
        nodeInstallation: Readonly<{
            installation: Readonly<{
                sdk: Readonly<{
                    interface: Scalar;
                    lock_artifact_cid: Scalar;
                    package_name: Scalar;
                    version: Scalar;
                } & Partial<{}>>;
                build_artifact_cid: Scalar;
                builder_id: Scalar;
                builder_revision: Scalar;
                codec_id: Scalar;
                codec_revision: Scalar;
                completion_basis: Scalar;
                endpoint: Scalar;
                http_method: Scalar;
                streaming: Scalar;
                validator_artifact_cid: Scalar;
                validator_id: Scalar;
                validator_revision: Scalar;
            } & Partial<{}>>;
            probability: undefined;
            layout: Readonly<{
                response_profile: unknown;
                execution_bytes: bigint;
                prepared_rows: bigint;
                retained_bytes: bigint;
                layout_artifact_cid: string;
                runtime_artifact_cid: string;
            } | {
                response_profile: unknown;
                execution_bytes: bigint;
                prepared_rows: bigint;
                retained_bytes: bigint;
                layout_artifact_cid: string;
                runtime_artifact_cid: string;
                barrier_cid: string;
                parameter_values_cid: string;
                program_definition_cid: string;
            }>;
            runtimeArtifactCid: string;
            layoutArtifactCid: string;
        }>;
        bootstrap: Readonly<{
            maxDelegations: number;
            maxHoldings: number;
            maxReservations: number;
            bootstrapExecutionBytes: bigint;
            bootstrapRetainedBytes: bigint;
        } & Partial<{}>>;
        modelExecutionBytes: bigint;
        modelRetainedBytes: bigint;
        storeBootstrap?: Readonly<{
            maxDirectoryEntries: number;
            maxWireBytes: number;
        } & Partial<{}>> | undefined;
        publicationCapacity?: Readonly<{
            retainedBytes: bigint;
            workspaceBytes: bigint;
        } & Partial<{}>> | undefined;
        metadataAcquisition?: Readonly<{
            retainedBytes: bigint;
            workspaceBytes: bigint;
            metadata: Readonly<{
                maxWireBytes: number;
                maxLedgerEntries: number;
            } & Partial<{}>>;
            directory: Readonly<{
                maxDirectoryEntries: number;
                maxWireBytes: number;
            } & Partial<{}>>;
        } & Partial<{}>> | undefined;
        currentStateCodec?: Readonly<{
            quantum: number;
            comparisonWork: number;
            decode: Readonly<{
                maxWork: number;
                parse: Readonly<{
                    max_depth: number;
                    max_input_bytes: number;
                    max_nodes: number;
                } & Partial<{}>>;
                tree: Readonly<{
                    max_depth: number;
                    max_nodes: number;
                    max_string_bytes: number;
                    max_total_string_bytes: number;
                } & Partial<{}>>;
            } & Partial<{}>>;
        } & Partial<{}>> | undefined;
    }> | Readonly<{
        profile: unknown;
        installation: Readonly<{
            sdk: Readonly<{
                interface: Scalar;
                lock_artifact_cid: Scalar;
                package_name: Scalar;
                version: Scalar;
            } & Partial<{}>>;
            build_artifact_cid: Scalar;
            builder_id: Scalar;
            builder_revision: Scalar;
            codec_id: Scalar;
            codec_revision: Scalar;
            completion_basis: Scalar;
            endpoint: Scalar;
            http_method: Scalar;
            streaming: Scalar;
            validator_artifact_cid: Scalar;
            validator_id: Scalar;
            validator_revision: Scalar;
        } & Partial<{}>>;
        probability: undefined;
        selectionAvailable: Function;
        availableUntil: Scalar;
        deleteBy: Scalar;
        extensionCeilingAt: Scalar;
        metadataDeleteBy: Scalar;
        selectedAt: Scalar;
    }>;
    rawCaptureSelection: Readonly<{
        profile: unknown;
        installation: Readonly<{
            sdk: Readonly<{
                interface: Scalar;
                lock_artifact_cid: Scalar;
                package_name: Scalar;
                version: Scalar;
            } & Partial<{}>>;
            build_artifact_cid: Scalar;
            builder_id: Scalar;
            builder_revision: Scalar;
            codec_id: Scalar;
            codec_revision: Scalar;
            completion_basis: Scalar;
            endpoint: Scalar;
            http_method: Scalar;
            streaming: Scalar;
            validator_artifact_cid: Scalar;
            validator_id: Scalar;
            validator_revision: Scalar;
        } & Partial<{}>>;
        probability: undefined;
        selectionAvailable: Function;
        availableUntil: Scalar;
        deleteBy: Scalar;
        extensionCeilingAt: Scalar;
        metadataDeleteBy: Scalar;
        selectedAt: Scalar;
    }>;
}>;
export {};
