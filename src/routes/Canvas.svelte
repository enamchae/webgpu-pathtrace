<script lang="ts">
import { onMount, tick } from "svelte";
import renderShaderSrc from "./render.wgsl?raw";
import { loadGltfScene } from "./scene";
import { RenderTiming, type Store } from "./Store.svelte";

let {
    status = $bindable(),
    err = $bindable(),
    store,
}: {
    status: string,
    err: string | null,
    store: Store,
} = $props();

let canvas: HTMLCanvasElement;
let device: GPUDevice;
let context: GPUCanvasContext;
let vertBuffer: GPUBuffer;
let trianglesBuffer: GPUBuffer;
let materialsBuffer: GPUBuffer;
let bindGroupLayout: GPUBindGroupLayout;
let bindGroup: GPUBindGroup;
let renderPipeline: GPURenderPipeline;
let computeFullPipeline: GPUComputePipeline;
let computeSinglePassPipeline: GPUComputePipeline;
let computeBeginPassPipeline: GPUComputePipeline;
let computeIntersectPipeline: GPUComputePipeline;
let computeShadePipeline: GPUComputePipeline;
let computeFinishPassPipeline: GPUComputePipeline;
let computeSortIntersectionsPipeline: GPUComputePipeline;
let uniformsBuffer: GPUBuffer;
let storedBuffer: GPUBuffer;

const gpuReady = Promise.withResolvers<void>();
let okToRerender = false;

status = "loading component";

onMount(async () => {
    status = "accessing gpu";

    if (navigator.gpu === undefined) {
        err = "webgpu not supported";
        return;
    }

    const adapter = await navigator.gpu.requestAdapter();
    if (adapter === null) {
        err = "could not get adapter";
        return;
    }

    device = await adapter.requestDevice();
    if (device === null) {
        err = "could not get device";
        return;
    }

    context = canvas.getContext("webgpu");
    if (context === null) {
        err = "could not get context";
        return;
    }

    const format = navigator.gpu.getPreferredCanvasFormat();
    context.configure({
        device,
        format,
        alphaMode: "premultiplied",
    });


    const renderShaderModule = device.createShaderModule({code: renderShaderSrc});

    const verts = new Float32Array([
        -1, 1, 0, 1,
        1, 1, 0, 1,
        -1, -1, 0, 1,

        1, 1, 0, 1,
        -1, -1, 0, 1,
        1, -1, 0, 1,
    ]);

    vertBuffer = device.createBuffer({
        size: verts.byteLength,
        usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    });

    device.queue.writeBuffer(vertBuffer, 0, verts, 0, verts.length);


    status = "loading scene file";


    const {triangles, materials} = await loadGltfScene("/icosphere.glb");
    store.nTriangles = triangles.byteLength / 48;

    
    trianglesBuffer = device.createBuffer({
        size: triangles.byteLength,
        usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });

    device.queue.writeBuffer(trianglesBuffer, 0, triangles);


    materialsBuffer = device.createBuffer({
        size: materials.byteLength,
        usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });

    device.queue.writeBuffer(materialsBuffer, 0, materials);



    uniformsBuffer = device.createBuffer({
        size: 32,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });


    storedBuffer = device.createBuffer({
        size: 4,
        usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });



    bindGroupLayout = device.createBindGroupLayout({
        entries: [
            {
                binding: 0,
                visibility: GPUShaderStage.COMPUTE,
                buffer: {
                    type: "read-only-storage",
                },
            },

            {
                binding: 1,
                visibility: GPUShaderStage.COMPUTE,
                buffer: {
                    type: "read-only-storage",
                },
            },

            {
                binding: 2,
                visibility: GPUShaderStage.COMPUTE | GPUShaderStage.FRAGMENT,
                buffer: {
                    type: "uniform",
                },
            },

            {
                binding: 3,
                visibility: GPUShaderStage.COMPUTE | GPUShaderStage.FRAGMENT,
                buffer: {
                    type: "storage",
                },
            },

            {
                binding: 4,
                visibility: GPUShaderStage.COMPUTE | GPUShaderStage.FRAGMENT,
                buffer: {
                    type: "storage",
                },
            },

            {
                binding: 5,
                visibility: GPUShaderStage.COMPUTE | GPUShaderStage.FRAGMENT,
                buffer: {
                    type: "storage",
                },
            },

            {
                binding: 6,
                visibility: GPUShaderStage.COMPUTE | GPUShaderStage.FRAGMENT,
                buffer: {
                    type: "storage",
                },
            },
        ],
    });


    renderPipeline = device.createRenderPipeline({
        vertex: {
            module: renderShaderModule,
            entryPoint: "vert",
            buffers: [
                {
                    attributes: [
                        {
                            shaderLocation: 0,
                            offset: 0,
                            format: "float32x4",
                        },
                    ],

                    arrayStride: 16,
                    stepMode: "vertex",
                },
            ],
        },

        fragment: {
            module: renderShaderModule,
            entryPoint: "frag_from_output",
            targets: [
                {
                    format,
                },
            ],
        },

        primitive: {
            topology: "triangle-list",
        },

        layout: device.createPipelineLayout({
            bindGroupLayouts: [bindGroupLayout],
        }),
    });


    computeFullPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({
            bindGroupLayouts: [bindGroupLayout],
        }),

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_full",
        },
    });

    computeSinglePassPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({
            bindGroupLayouts: [bindGroupLayout],
        }),

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_single_pass",
        },
    });


    computeBeginPassPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({
            bindGroupLayouts: [bindGroupLayout],
        }),

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_begin_pass",
        },
    });


    computeIntersectPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({
            bindGroupLayouts: [bindGroupLayout],
        }),

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_intersect",
        },
    });


    computeShadePipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({
            bindGroupLayouts: [bindGroupLayout],
        }),

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_shade",
        },
    });


    computeFinishPassPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({
            bindGroupLayouts: [bindGroupLayout],
        }),

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_finish_pass",
        },
    });


    computeSortIntersectionsPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({
            bindGroupLayouts: [bindGroupLayout],
        }),

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_sort_intersections",
        },
    });

    status = "setting up render";
    okToRerender = true;

    gpuReady.resolve();
});



let rerenderTriggered = false;
const hardRerender = async (nextWidth: number, nextHeight: number) => {
    rerenderTriggered = false;

    const N_ELEMENTS = nextWidth * nextHeight;

    const outputBuffer = device.createBuffer({
        size: N_ELEMENTS * 16,
        usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });


    const intersectionsBuffer = device.createBuffer({
        size: N_ELEMENTS * 64,
        usage: GPUBufferUsage.STORAGE,
    });

    const raysBuffer = device.createBuffer({
        size: N_ELEMENTS * 64,
        usage: GPUBufferUsage.STORAGE,
    });


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
                    buffer: outputBuffer,
                },
            },

            {
                binding: 4,
                resource: {
                    buffer: intersectionsBuffer,
                },
            },

            {
                binding: 5,
                resource: {
                    buffer: raysBuffer,
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


    device.queue.writeBuffer(uniformsBuffer, 0, new Uint32Array([width, height]));
    device.queue.writeBuffer(uniformsBuffer, 12, new Uint32Array([
        store.supersampleRate,
        store.nSamplesPerGridCell,
        store.nMaxBounces,
    ]));

    device.queue.writeBuffer(uniformsBuffer, 24, new Float32Array([
        store.dofRadius,
        store.dofDistance,
    ]));

    status = "rendering";

    store.nRenderedSamples = 0;
    store.cumulativeSampleTime = 0;

    await new Promise(resolve => setTimeout(resolve));

    store.nRenderedSamples = 0;
    store.cumulativeSampleTime = 0;
    const start = performance.now();

    switch (store.renderTiming) {
        case RenderTiming.afterEverySample: {
            for (let i = 0; i < store.nTargetSamples; i++) {
                rerenderTriggered = true;
                
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
                if (!rerenderTriggered) return;

                store.nRenderedSamples++;
                store.cumulativeSampleTime = performance.now() - start;

            }
            break;
        }

        case RenderTiming.afterAllSamples: {
            rerenderTriggered = true;
            
            device.queue.writeBuffer(storedBuffer, 0, new Uint32Array([0]));

            const commandEncoder = device.createCommandEncoder();

            const computePassEncoder = commandEncoder.beginComputePass();
            computePassEncoder.setBindGroup(0, bindGroup);
            computePassEncoder.setPipeline(computeFullPipeline);
            computePassEncoder.dispatchWorkgroups(Math.ceil(nextWidth * nextHeight / 256));
            computePassEncoder.end();

            addRenderPass(commandEncoder);

            device.queue.submit([commandEncoder.finish()]);
            
            await device.queue.onSubmittedWorkDone();
            if (!rerenderTriggered) return;

            store.nRenderedSamples += store.nTargetSamples;
            store.cumulativeSampleTime = performance.now() - start;

            break;
        }
    }
    

    status = "done";
};

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

$effect(() => {
    void store.renderTiming, store.supersampleRate, store.nSamplesPerGridCell, store.nMaxBounces, store.dofDistance, store.dofRadius;
    if (!okToRerender) return;
    hardRerender(width, height);
});

let width = $state(0);
let height = $state(0);
let waiting = false;
const onResize = async () => {
    const nextWidth = width = innerWidth;
    const nextHeight = height = innerHeight;

    if (waiting) return;

    waiting = true;

    await Promise.all([
        tick(),
        gpuReady.promise,
    ]);


    await hardRerender(nextWidth, nextHeight);

    waiting = false;



    /*
    {
        const N_ELEMENTS = 1000;
        const BUFFER_SIZE = N_ELEMENTS * 4;

        const output = device.createBuffer({
            size: BUFFER_SIZE,
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC,
        });

        const stagingBuffer = device.createBuffer({
            size: BUFFER_SIZE,
            usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST,
        });

        const bindGroupLayout = device.createBindGroupLayout({
            entries: [
                {
                    binding: 0,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: {
                        type: "storage",
                    },
                },
            ],
        });

        const bindGroup = device.createBindGroup({
            layout: bindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: {
                        buffer: output,
                    },
                },
            ],
        });

        const computeShaderModule = device.createShaderModule({code: computeShaderSrc});

        const computePipeline = device.createComputePipeline({
            layout: device.createPipelineLayout({
                bindGroupLayouts: [bindGroupLayout],
            }),

            compute: {
                module: computeShaderModule,
                entryPoint: "main",
            },
        });

        const computeCommandEncoder = device.createCommandEncoder();

        const computePassEncoder = computeCommandEncoder.beginComputePass();
        computePassEncoder.setPipeline(computePipeline);
        computePassEncoder.setBindGroup(0, bindGroup);
        computePassEncoder.dispatchWorkgroups(Math.ceil(N_ELEMENTS / 64));
        computePassEncoder.end();

        computeCommandEncoder.copyBufferToBuffer(output, 0, stagingBuffer, 0, BUFFER_SIZE);

        device.queue.submit([computeCommandEncoder.finish()]);


        await stagingBuffer.mapAsync(GPUMapMode.READ, 0, BUFFER_SIZE);

        const copyArrayBuffer = stagingBuffer.getMappedRange(0, BUFFER_SIZE);
        const data = copyArrayBuffer.slice();
        stagingBuffer.unmap();
        console.log(new Float32Array(data));
    }
    */
};
onMount(onResize);

</script>

{#if err !== null}
    {err}
{/if}

<svelte:window onresize={onResize} />

<canvas
    bind:this={canvas}
    {width}
    {height}
></canvas>
