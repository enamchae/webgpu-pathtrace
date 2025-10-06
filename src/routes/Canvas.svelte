<script lang="ts">
import { onMount, tick } from "svelte";
import renderShaderSrc from "./render.wgsl?raw";
import { loadGltfScene } from "./scene";
import { RenderTiming, type Store } from "./Store.svelte";
    import { createRenderer } from "./render.svelte";

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
let context: GPUCanvasContext | null;
let vertBuffer: GPUBuffer;
let trianglesBuffer: GPUBuffer;
let materialsBuffer: GPUBuffer;
let bindGroupLayout: GPUBindGroupLayout;
let renderPipeline: GPURenderPipeline;
let computeBeginPassPipeline: GPUComputePipeline;
let computeIntersectPipeline: GPUComputePipeline;
let computeShadePipeline: GPUComputePipeline;
let computeFinishPassPipeline: GPUComputePipeline;
let computeSortIntersectionsPipeline: GPUComputePipeline;
let uniformsBuffer: GPUBuffer;
let storedBuffer: GPUBuffer;
let rerender: ((width: number, height: number) => Promise<void>) | null = null;


const gpuReady = Promise.withResolvers<void>();
let okToRerender = false;

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


    const {triangles, materials} = await loadGltfScene("/cup.glb");
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
        size: 112,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
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
                visibility: GPUShaderStage.COMPUTE,
                buffer: {
                    type: "storage",
                },
            },

            {
                binding: 7,
                visibility: GPUShaderStage.COMPUTE,
                buffer: {
                    type: "storage",
                },
            },

            {
                binding: 8,
                visibility: GPUShaderStage.COMPUTE,
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

    const pipelineLayout = device.createPipelineLayout({
        bindGroupLayouts: [bindGroupLayout],
    });


    const computeFullPipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_full",
        },
    });

    const computeSinglePassPipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_single_pass",
        },
    });

    const computeCompactBoolsPipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_set_terminated_bools",
        },
    });

    const computeCompactUpsweepPipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_terminated_upsweep",
        },
    });

    const computeCompactDownsweepPipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_terminated_downsweep",
        },
    });

    const computeCompactScatterPipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_terminated_scatter",
        },
    });

    const computeCompactCopyBackPipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_terminated_copy_back",
        },
    });

    computeBeginPassPipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_begin_pass",
        },
    });


    computeIntersectPipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_intersect",
        },
    });


    computeShadePipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_shade",
        },
    });


    computeFinishPassPipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_finish_pass",
        },
    });


    computeSortIntersectionsPipeline = device.createComputePipeline({
        layout: pipelineLayout,

        compute: {
            module: renderShaderModule,
            entryPoint: "comp_sort_intersections",
        },
    });

    status = "setting up render";
    okToRerender = true;

    rerender = createRenderer({
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

        onStatusChange: value => status = value,
    });

    gpuReady.resolve();
});


$effect(() => {
    void store.renderTiming;
    void store.supersampleRate;
    void store.nSamplesPerGridCell;
    void store.nMaxBounces;
    void store.dofDistance;
    void store.dofRadius;
    void store.orbit.lat;
    void store.orbit.long;
    void store.orbit.radius;
    if (!okToRerender) return;
    rerender?.(width, height);
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


    await rerender?.(nextWidth, nextHeight);

    waiting = false;
};
onMount(onResize);

let pointerdown = $state(false);

</script>

{#if err !== null}
    {err}
{/if}

<svelte:window
    onresize={onResize}
    onpointerup={() => pointerdown = false}
/>

<canvas
    bind:this={canvas}
    {width}
    {height}

    onpointerdown={() => pointerdown = true}
    onpointermove={event => {
        if (!pointerdown) return;
        store.orbit.long -= event.movementX * 0.01;
        store.orbit.lat += event.movementY * 0.01;
    }}
    onwheel={event => {
        store.orbit.radius += event.y * 0.01;
    }}
></canvas>
