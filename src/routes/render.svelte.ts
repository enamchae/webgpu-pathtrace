import { RenderTiming, type Store } from "./Store.svelte";
import { ilog2ceil } from "./util";


const WORKGROUP_SIZE = 256;


export const createRenderer = ({
    store,

    device,
    context,
    bindGroupLayout,

    vertBuffer,
    trianglesBuffer,
    materialsBuffer,
    boundingBoxesBuffer,
    uniformsBuffer,
    envTexture,

    renderPipeline,
    computeFullPipeline,
    computeSinglePassPipeline,
    computeBeginPassPipeline,
    computeIntersectPipeline,
    computeShadePipeline,
    computeFinishPassPipeline,
    computeCompactBoolsPipeline,
    computeCompactUpsweepPipeline,
    computeCompactDownsweepPipeline,
    computeCompactScatterPipeline,
    computeCompactCopyBackPipeline,
    computeMaterialBoolsPipeline,
    computeMaterialUpsweepPipeline,
    computeMaterialDownsweepPipeline,
    computeMaterialScatterPipeline,
    computeMaterialCopyBackPipeline,

    onStatusChange,
}: {
    store: Store,

    device: GPUDevice,
    context: GPUCanvasContext,
    bindGroupLayout: GPUBindGroupLayout,

    vertBuffer: GPUBuffer,
    trianglesBuffer: GPUBuffer,
    materialsBuffer: GPUBuffer,
    boundingBoxesBuffer: GPUBuffer,
    uniformsBuffer: GPUBuffer,
    envTexture: GPUTexture,

    renderPipeline: GPURenderPipeline,
    computeFullPipeline: GPUComputePipeline,
    computeSinglePassPipeline: GPUComputePipeline,
    computeBeginPassPipeline: GPUComputePipeline,
    computeIntersectPipeline: GPUComputePipeline,
    computeShadePipeline: GPUComputePipeline,
    computeFinishPassPipeline: GPUComputePipeline,
    computeCompactBoolsPipeline: GPUComputePipeline,
    computeCompactUpsweepPipeline: GPUComputePipeline,
    computeCompactDownsweepPipeline: GPUComputePipeline,
    computeCompactScatterPipeline: GPUComputePipeline,
    computeCompactCopyBackPipeline: GPUComputePipeline,
    computeMaterialBoolsPipeline: GPUComputePipeline,
    computeMaterialUpsweepPipeline: GPUComputePipeline,
    computeMaterialDownsweepPipeline: GPUComputePipeline,
    computeMaterialScatterPipeline: GPUComputePipeline,
    computeMaterialCopyBackPipeline: GPUComputePipeline,

    onStatusChange: (status: string) => void,
}) => {
    let bindGroup: GPUBindGroup;

    const addRenderPass = (commandEncoder: GPUCommandEncoder) => {
        const renderPassEncoder = commandEncoder.beginRenderPass({
            colorAttachments: [
                {
                    clearValue: {
                        r: 0,
                        g: 0,
                        b: 0,
                        a: 0,
                    },
                    loadOp: "clear",
                    storeOp: "store",
                    view: context.getCurrentTexture().createView(),
                },
            ],
        });

        renderPassEncoder.setBindGroup(0, bindGroup);
        renderPassEncoder.setVertexBuffer(0, vertBuffer);
        renderPassEncoder.setPipeline(renderPipeline);
        renderPassEncoder.draw(6);
        renderPassEncoder.end();
    };


    let lastNPixels = -1;
    let lastDestroy = () => {};

    let outputBuffer: GPUBuffer | null = null;
    let intersectionsBuffer: GPUBuffer | null = null;
    let raysBuffer: GPUBuffer | null = null;

    let compactBoolsBuffer: GPUBuffer | null = null;
    let compactOutBuffer: GPUBuffer | null = null;
    let radixBoolsBuffer: GPUBuffer | null = null;
    let materialOutBuffer: GPUBuffer | null = null;


    const createOutputBuffers = (nPixels: number) => {
        const nCeil = 1 << ilog2ceil(nPixels);

        const buffers = [
            outputBuffer = device.createBuffer({
                size: nPixels * 16,
                usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
            }),

            intersectionsBuffer = device.createBuffer({
                size: nPixels * 64,
                usage: GPUBufferUsage.STORAGE,
            }),

            raysBuffer = device.createBuffer({
                size: nPixels * 64,
                usage: GPUBufferUsage.STORAGE,
            }),

            compactBoolsBuffer = device.createBuffer({
                size: nCeil * 8,
                usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
            }),

            compactOutBuffer = device.createBuffer({
                size: nCeil * 64,
                usage: GPUBufferUsage.STORAGE,
            }),

            radixBoolsBuffer = device.createBuffer({
                size: nCeil * 16,
                usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
            }),

            materialOutBuffer = device.createBuffer({
                size: nCeil * 64,
                usage: GPUBufferUsage.STORAGE,
            }),
        ];

        return () => {
            for (const buffer of buffers) {
                buffer.destroy();
            }
        };
    };


    let renderId = 0n;
    return async (nextWidth: number, nextHeight: number) => {
        renderId++;
        const currentRenderId = renderId;

        const nPixels = nextWidth * nextHeight;
        const nPixelsNextPowerOfTwo = 1 << ilog2ceil(nPixels);

        if (nPixels !== lastNPixels) {
            lastDestroy();
            lastNPixels = nPixels;
        }
        const destroy = lastDestroy = createOutputBuffers(nPixels);


        bindGroup = device.createBindGroup({
            layout: bindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: {
                        buffer: trianglesBuffer,
                    },
                },

                {
                    binding: 1,
                    resource: {
                        buffer: materialsBuffer,
                    },
                },

                {
                    binding: 2,
                    resource: {
                        buffer: uniformsBuffer,
                    },
                },

                {
                    binding: 3,
                    resource: {
                        buffer: outputBuffer!,
                    },
                },

                {
                    binding: 4,
                    resource: {
                        buffer: intersectionsBuffer!,
                    },
                },

                {
                    binding: 5,
                    resource: {
                        buffer: raysBuffer!,
                    },
                },

                {
                    binding: 6,
                    resource: {
                        buffer: compactBoolsBuffer!,
                    },
                },

                {
                    binding: 7,
                    resource: {
                        buffer: compactOutBuffer!,
                    },
                },

                {
                    binding: 8,
                    resource: {
                        buffer: radixBoolsBuffer!,
                    },
                },

                {
                    binding: 9,
                    resource: {
                        buffer: materialOutBuffer!,
                    },
                },

                {
                    binding: 10,
                    resource: envTexture.createView(),
                },

                {
                    binding: 11,
                    resource: {
                        buffer: boundingBoxesBuffer,
                    },
                },
            ],
        });


        device.queue.writeBuffer(uniformsBuffer, 0, new Uint32Array([nextWidth, nextHeight]));
        device.queue.writeBuffer(uniformsBuffer, 12, new Uint32Array([
            store.supersampleRate,
            store.nSamplesPerGridCell,
            store.nMaxBounces,
        ]));

        device.queue.writeBuffer(uniformsBuffer, 24, new Float32Array([
            store.dofRadius,
            store.dofDistance,
        ]));

        device.queue.writeBuffer(uniformsBuffer, 32, store.orbit.mat());

        device.queue.writeBuffer(uniformsBuffer, 104, new Uint32Array([Number(store.useBoundingBoxes)]));

        onStatusChange("rendering");

        store.nRenderedSamples = 0;
        store.cumulativeSampleTime = 0;

        await new Promise(resolve => setTimeout(resolve));

        const queueComputeShaders = (...entries: [GPUComputePipeline, number][]) => {
            const encoder = device.createCommandEncoder();

            const pass = encoder.beginComputePass();
            pass.setBindGroup(0, bindGroup);

            for (const [pipeline, nItems] of entries) {
                pass.setPipeline(pipeline);
                pass.dispatchWorkgroups(Math.ceil(nItems / 256));
            }

            pass.end();

            device.queue.submit([encoder.finish()]);
        };


        store.nRenderedSamples = 0;
        store.cumulativeSampleTime = 0;
        const start = performance.now();


        try {
            switch (store.renderTiming) {
                case RenderTiming.afterEverySampleCoherent: {
                    for (let i = 0; i < store.nTargetSamples; i++) {
                        device.queue.writeBuffer(uniformsBuffer, 8, new Uint32Array([i]));
                        queueComputeShaders([computeBeginPassPipeline, nPixels]);

                        for (let depth = 0; depth < store.nMaxBounces; depth++) {
                            queueComputeShaders([computeIntersectPipeline, nPixels]);

                            for (let shift = 0; shift < 16; shift += 2) {
                                device.queue.writeBuffer(uniformsBuffer, 100, new Uint32Array([shift]));
                                queueComputeShaders([computeMaterialBoolsPipeline, nPixelsNextPowerOfTwo]);
    
                                for (let step = 2; step <= nPixelsNextPowerOfTwo; step <<= 1) {
                                    device.queue.writeBuffer(uniformsBuffer, 96, new Uint32Array([step]));
                                    queueComputeShaders([computeMaterialUpsweepPipeline, nPixelsNextPowerOfTwo / step]);
                                }
    
                                device.queue.writeBuffer(radixBoolsBuffer!, (nPixelsNextPowerOfTwo - 1) * 16, new Uint32Array([0, 0, 0, 0]));
    
                                for (let step = nPixelsNextPowerOfTwo; step >= 2; step >>= 1) {
                                    device.queue.writeBuffer(uniformsBuffer, 96, new Uint32Array([step]));
                                    queueComputeShaders([computeMaterialDownsweepPipeline, nPixelsNextPowerOfTwo / step]);
                                }
    
                                queueComputeShaders(
                                    [computeMaterialScatterPipeline, nPixelsNextPowerOfTwo],
                                    [computeMaterialCopyBackPipeline, nPixelsNextPowerOfTwo],
                                );
                            }

                            queueComputeShaders(
                                [computeShadePipeline, nPixels],
                                [computeCompactBoolsPipeline, nPixelsNextPowerOfTwo],
                            );


                            for (let step = 2; step <= nPixelsNextPowerOfTwo; step <<= 1) {
                                device.queue.writeBuffer(uniformsBuffer, 96, new Uint32Array([step]));
                                queueComputeShaders([computeCompactUpsweepPipeline, nPixelsNextPowerOfTwo / step]);
                            }

                            device.queue.writeBuffer(compactBoolsBuffer!, (nPixelsNextPowerOfTwo - 1) * 8, new Uint32Array([0, 0]));

                            for (let step = nPixelsNextPowerOfTwo; step >= 2; step >>= 1) {
                                device.queue.writeBuffer(uniformsBuffer, 96, new Uint32Array([step]));
                                queueComputeShaders([computeCompactDownsweepPipeline, nPixelsNextPowerOfTwo / step]);
                            }

                            queueComputeShaders(
                                [computeCompactScatterPipeline, nPixelsNextPowerOfTwo],
                                [computeCompactCopyBackPipeline, nPixelsNextPowerOfTwo],
                            );
                        }

                        const finishPassCommandEncoder = device.createCommandEncoder();

                        const computeFinishPassEncoder = finishPassCommandEncoder.beginComputePass();
                        computeFinishPassEncoder.setBindGroup(0, bindGroup);
                        computeFinishPassEncoder.setPipeline(computeFinishPassPipeline);
                        computeFinishPassEncoder.dispatchWorkgroups(Math.ceil(nPixels / WORKGROUP_SIZE));
                        computeFinishPassEncoder.end();

                        addRenderPass(finishPassCommandEncoder);

                        device.queue.submit([finishPassCommandEncoder.finish()]);



                        await device.queue.onSubmittedWorkDone();
                        if (currentRenderId !== renderId) return;

                        store.nRenderedSamples++;
                        store.cumulativeSampleTime = performance.now() - start;

                    }
                    break;
                }

                case RenderTiming.afterEverySample: {
                    for (let i = 0; i < store.nTargetSamples; i++) {
                        device.queue.writeBuffer(uniformsBuffer, 8, new Uint32Array([i]));


                        const passCommandEncoder = device.createCommandEncoder();

                        const computePassEncoder = passCommandEncoder.beginComputePass();
                        computePassEncoder.setBindGroup(0, bindGroup);

                        computePassEncoder.setPipeline(computeSinglePassPipeline);
                        computePassEncoder.dispatchWorkgroups(Math.ceil(nPixels / WORKGROUP_SIZE));

                        computePassEncoder.end();

                        addRenderPass(passCommandEncoder);


                        device.queue.submit([passCommandEncoder.finish()]);


                        await device.queue.onSubmittedWorkDone();
                        if (currentRenderId !== renderId) return;

                        store.nRenderedSamples++;
                        store.cumulativeSampleTime = performance.now() - start;

                    }
                    break;
                }

                case RenderTiming.afterAllSamples: {
                    device.queue.writeBuffer(uniformsBuffer, 8, new Uint32Array([0]));

                    const commandEncoder = device.createCommandEncoder();

                    const computePassEncoder = commandEncoder.beginComputePass();
                    computePassEncoder.setBindGroup(0, bindGroup);
                    computePassEncoder.setPipeline(computeFullPipeline);
                    computePassEncoder.dispatchWorkgroups(Math.ceil(nPixels / WORKGROUP_SIZE));
                    computePassEncoder.end();

                    addRenderPass(commandEncoder);

                    device.queue.submit([commandEncoder.finish()]);

                    await device.queue.onSubmittedWorkDone();
                    if (currentRenderId !== renderId) return;

                    store.nRenderedSamples += store.nTargetSamples;
                    store.cumulativeSampleTime = performance.now() - start;

                    break;
                }
            }
        }

        finally {
            destroy();
        }

        onStatusChange("done");
    };
};