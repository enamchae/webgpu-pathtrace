<script lang="ts">
import { onMount, tick } from "svelte";
import renderShaderSrc from "./render.wgsl?raw";
import computeShaderSrc from "./compute.wgsl?raw";
    import { readonly } from "svelte/store";
    import { Quad } from "./Quad.svelte";
    import { Vec3 } from "./Vec3.svelte";

let err = $state<string | null>(null);

let canvas: HTMLCanvasElement;
let device: GPUDevice;
let context: GPUCanvasContext;
let vertBuffer: GPUBuffer;
let bindGroup: GPUBindGroup;
let renderPipeline: GPURenderPipeline;
let renderCommandEncoder: GPURenderCommandEncoder;

const gpuReady = Promise.withResolvers<void>();

onMount(async () => {
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


    const quads = [
        new Quad(
            new Vec3(1, 1, -2),
            new Vec3(1, -1, -2),
            new Vec3(1, -1, -4),
            new Vec3(1, 1, -4),
            [0.6, 0.1, 0.1, 1],
        ),

        new Quad(
            new Vec3(-1, 1, -2),
            new Vec3(1, 1, -2),
            new Vec3(1, 1, -4),
            new Vec3(-1, 1, -10),
        ),

        new Quad(
            new Vec3(-1, -1, -2),
            new Vec3(-1, 1, -2),
            new Vec3(-1, 1, -10),
            new Vec3(-1, -1, -10),
            [0.1, 0.6, 0.1, 1],
        ),

        new Quad(
            new Vec3(1, -1, -2),
            new Vec3(-1, -1, -2),
            new Vec3(-1, -1, -10),
            new Vec3(1, -1, -4),
        ),

        new Quad(
            new Vec3(1, 1, -4),
            new Vec3(-1, 1, -10),
            new Vec3(-1, -1, -10),
            new Vec3(1, -1, -4),
        ),

        new Quad(
            new Vec3(0.75, 0.75, -4),
            new Vec3(-0.25, 0.75, -4),
            new Vec3(-0.25, -0.25, -4),
            new Vec3(0.75, -0.25, -4),
            [0, 0, 0, 1],
            [1, 0, 1, 1],
        ),
    ];

    const triangles = new Float32Array([...quads.flatMap(quad => quad.triBuffer())]);

    const trianglesBuffer = device.createBuffer({
        size: triangles.byteLength,
        usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });

    device.queue.writeBuffer(trianglesBuffer, 0, triangles);



    const materials = new Float32Array([...quads.flatMap(quad => quad.materialBuffer())]);
    const materialsBuffer = device.createBuffer({
        size: materials.byteLength,
        usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });

    device.queue.writeBuffer(materialsBuffer, 0, materials);





    const bindGroupLayout = device.createBindGroupLayout({
        entries: [
            {
                binding: 0,
                visibility: GPUShaderStage.FRAGMENT,
                buffer: {
                    type: "read-only-storage",
                },
            },

            {
                binding: 1,
                visibility: GPUShaderStage.FRAGMENT,
                buffer: {
                    type: "read-only-storage",
                },
            },
        ],
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
            entryPoint: "frag",
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

    renderCommandEncoder = device.createCommandEncoder();


    gpuReady.resolve();
});


const rerender = () => {
    const renderPassEncoder = renderCommandEncoder.beginRenderPass({
        colorAttachments: [
            {
                clearValue: {
                    r: 0,
                    g: 0.5,
                    b: 1,
                    a: 0,
                },
                loadOp: "clear",
                storeOp: "store",
                view: context.getCurrentTexture().createView(),
            },
        ],
    });

    renderPassEncoder.setPipeline(renderPipeline);
    renderPassEncoder.setBindGroup(0, bindGroup);
    renderPassEncoder.setVertexBuffer(0, vertBuffer);
    renderPassEncoder.draw(6);
    renderPassEncoder.end();


    device.queue.submit([renderCommandEncoder.finish()]);
};

let width = $state(0);
let height = $state(0);
const onResize = async () => {
    width = innerWidth;
    height = innerHeight;

    await Promise.all([
        tick(),
        gpuReady.promise,
    ]);

    rerender();



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
