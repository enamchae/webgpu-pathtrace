import { RenderTiming, type Store } from "./Store.svelte";

export const createRenderer = ({
    store,

    device,
    context,
    bindGroupLayout,

    vertBuffer,
    trianglesBuffer,
    materialsBuffer,
    uniformsBuffer,
    storedBuffer,

    renderPipeline,
    computeFullPipeline,
    computeSinglePassPipeline,

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
    storedBuffer: GPUBuffer,

    renderPipeline: GPURenderPipeline,
    computeFullPipeline: GPUComputePipeline,
    computeSinglePassPipeline: GPUComputePipeline,

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


    let lastNElements = -1;
    let outputBuffer: GPUBuffer | null = null;
    let intersectionsBuffer: GPUBuffer | null = null;
    let raysBuffer: GPUBuffer | null = null;
    const createOutputBuffers = (nElements: number) => {
        if (nElements === lastNElements) return;
    
        outputBuffer?.destroy();
        intersectionsBuffer?.destroy();
        raysBuffer?.destroy();
    
    
        outputBuffer = device.createBuffer({
            size: nElements * 16,
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
        });
    
        intersectionsBuffer = device.createBuffer({
            size: nElements * 64,
            usage: GPUBufferUsage.STORAGE,
        });
    
        raysBuffer = device.createBuffer({
            size: nElements * 64,
            usage: GPUBufferUsage.STORAGE,
        });
    };
    

    let renderId = 0n;
    return async (nextWidth: number, nextHeight: number) => {
        renderId++;
        const currentRenderId = renderId;
    
        const nElements = nextWidth * nextHeight;
        createOutputBuffers(nElements);
    
    
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
                        buffer: storedBuffer,
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
    
    
                    const commandEncoder = device.createCommandEncoder();
    
                    const computePassEncoder = commandEncoder.beginComputePass();
                    computePassEncoder.setBindGroup(0, bindGroup);
                    computePassEncoder.setPipeline(computeSinglePassPipeline);
                    computePassEncoder.dispatchWorkgroups(Math.ceil(nextWidth * nextHeight / 256));
                    computePassEncoder.end();
    
                    addRenderPass(commandEncoder);
    
                    device.queue.submit([commandEncoder.finish()]);
    
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
                computePassEncoder.dispatchWorkgroups(Math.ceil(nextWidth * nextHeight / 256));
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