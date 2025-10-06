import { RenderTiming, type Store } from "./Store.svelte";
import { ilog2ceil } from "./util";

export const createRenderer = ({
    store,

    device,
    context,
    bindGroupLayout,

    vertBuffer,
    trianglesBuffer,
    materialsBuffer,
    uniformsBuffer,

    renderPipeline,
    computeFullPipeline,
    computeSinglePassPipeline,
    computeCompactBoolsPipeline,
    computeCompactUpsweepPipeline,
    computeCompactDownsweepPipeline,
    computeCompactScatterPipeline,
    computeCompactCopyBackPipeline,

    onStatusChange,
}: {
    store: Store,

    device: GPUDevice,
    context: GPUCanvasContext,
    bindGroupLayout: GPUBindGroupLayout,

    vertBuffer: GPUBuffer,
    trianglesBuffer: GPUBuffer,
    materialsBuffer: GPUBuffer,
    uniformsBuffer: GPUBuffer,

    renderPipeline: GPURenderPipeline,
    computeFullPipeline: GPUComputePipeline,
    computeSinglePassPipeline: GPUComputePipeline,
    computeCompactBoolsPipeline: GPUComputePipeline,
    computeCompactUpsweepPipeline: GPUComputePipeline,
    computeCompactDownsweepPipeline: GPUComputePipeline,
    computeCompactScatterPipeline: GPUComputePipeline,
    computeCompactCopyBackPipeline: GPUComputePipeline,

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

    let outputBuffer: GPUBuffer | null = null;
    let intersectionsBuffer: GPUBuffer | null = null;
    let raysBuffer: GPUBuffer | null = null;

    let compactBools1Buffer: GPUBuffer | null = null;
    let compactBools2Buffer: GPUBuffer | null = null;
    let compactOutBuffer: GPUBuffer | null = null;

    const createOutputBuffers = (nPixels: number) => {
        if (nPixels === lastNPixels) return;
    
        outputBuffer?.destroy();
        intersectionsBuffer?.destroy();
        raysBuffer?.destroy();
    
    
        outputBuffer = device.createBuffer({
            size: nPixels * 16,
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
        });
    
        intersectionsBuffer = device.createBuffer({
            size: nPixels * 64,
            usage: GPUBufferUsage.STORAGE,
        });
    
        raysBuffer = device.createBuffer({
            size: nPixels * 64,
            usage: GPUBufferUsage.STORAGE,
        });

        const nCeil = 1 << ilog2ceil(nPixels);

        compactBools1Buffer = device.createBuffer({
            size: nCeil * 4,
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
        });

        compactBools2Buffer = device.createBuffer({
            size: nCeil * 4,
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
        });

        compactOutBuffer = device.createBuffer({
            size: nCeil * 64,
            usage: GPUBufferUsage.STORAGE,
        });
    };
    

    let renderId = 0n;
    return async (nextWidth: number, nextHeight: number) => {
        renderId++;
        const currentRenderId = renderId;
    
        const nPixels = nextWidth * nextHeight;
        const nCeil = 1 << ilog2ceil(nPixels);
        createOutputBuffers(nPixels);
    
    
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
                        buffer: compactBools1Buffer!,
                    },
                },
    
                {
                    binding: 7,
                    resource: {
                        buffer: compactBools2Buffer!,
                    },
                },
    
                {
                    binding: 8,
                    resource: {
                        buffer: compactOutBuffer!,
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
    
        onStatusChange("rendering");
    
        store.nRenderedSamples = 0;
        store.cumulativeSampleTime = 0;
    
        await new Promise(resolve => setTimeout(resolve));
    

        store.nRenderedSamples = 0;
        store.cumulativeSampleTime = 0;
        const start = performance.now();
    
        switch (store.renderTiming) {
            case RenderTiming.afterEverySample: {
                for (let i = 0; i < store.nTargetSamples; i++) {
                    device.queue.writeBuffer(uniformsBuffer, 8, new Uint32Array([i]));
    
    
                    const passCommandEncoder = device.createCommandEncoder();
    
                    const computePassEncoder = passCommandEncoder.beginComputePass();
                    computePassEncoder.setBindGroup(0, bindGroup);

                    computePassEncoder.setPipeline(computeSinglePassPipeline);
                    computePassEncoder.dispatchWorkgroups(Math.ceil(nPixels / 256));
    
                    computePassEncoder.setPipeline(computeCompactBoolsPipeline);
                    computePassEncoder.dispatchWorkgroups(Math.ceil(nCeil / 256));

                    computePassEncoder.end();

                    addRenderPass(passCommandEncoder);

                    device.queue.submit([passCommandEncoder.finish()]);

                
                    for (let step = 2; step <= nCeil; step <<= 1) {
                        device.queue.writeBuffer(uniformsBuffer, 96, new Uint32Array([step]));
    
                        const upsweepCommandEncoder = device.createCommandEncoder();

                        const computeUpsweepEncoder = upsweepCommandEncoder.beginComputePass();
                        computeUpsweepEncoder.setBindGroup(0, bindGroup);
                        computeUpsweepEncoder.setPipeline(computeCompactUpsweepPipeline);
                        computeUpsweepEncoder.dispatchWorkgroups(Math.ceil((nCeil / step) / 256));
                        computeUpsweepEncoder.end();
    
                        device.queue.submit([upsweepCommandEncoder.finish()]);
                    }

                    device.queue.writeBuffer(compactBools1Buffer!, (nCeil - 1) * 4, new Uint32Array([0]));
                    device.queue.writeBuffer(compactBools2Buffer!, (nCeil - 1) * 4, new Uint32Array([0]));

                
                    for (let step = nCeil; step >= 2; step >>= 1) {
                        device.queue.writeBuffer(uniformsBuffer, 96, new Uint32Array([step]));
    
                        const downsweepCommandEncoder = device.createCommandEncoder();

                        const computeDownsweepEncoder = downsweepCommandEncoder.beginComputePass();
                        computeDownsweepEncoder.setBindGroup(0, bindGroup);
                        computeDownsweepEncoder.setPipeline(computeCompactDownsweepPipeline);
                        computeDownsweepEncoder.dispatchWorkgroups(Math.ceil((nCeil / step) / 256));
                        computeDownsweepEncoder.end();
    
                        device.queue.submit([downsweepCommandEncoder.finish()]);
                    }


    
                    const compactFinishCommandEncoder = device.createCommandEncoder();

                    const computeCompactFinishEncoder = compactFinishCommandEncoder.beginComputePass();
                    computeCompactFinishEncoder.setBindGroup(0, bindGroup);

                    computeCompactFinishEncoder.setPipeline(computeCompactScatterPipeline);
                    computeCompactFinishEncoder.dispatchWorkgroups(Math.ceil(nCeil / 256));

                    computeCompactFinishEncoder.setPipeline(computeCompactCopyBackPipeline);
                    computeCompactFinishEncoder.dispatchWorkgroups(Math.ceil(nCeil / 256));

                    computeCompactFinishEncoder.end();

                    device.queue.submit([compactFinishCommandEncoder.finish()]);


    
    
    
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
                computePassEncoder.dispatchWorkgroups(Math.ceil(nPixels / 256));
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
    
        onStatusChange("done");
    };
};