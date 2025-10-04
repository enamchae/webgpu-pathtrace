<script lang="ts">
import { onMount, tick } from "svelte";
import renderShaderSrc from "./render.wgsl?raw";
import { Quad } from "./Quad.svelte";
import { Vec3 } from "./Vec3.svelte";
import {GLTFLoader} from "three/addons/loaders/GLTFLoader.js";


let {
    status = $bindable(),
}: {
    status: string,
} = $props();

let err = $state<string | null>(null);

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
let computeBeginPassPipeline: GPUComputePipeline;
let computeIntersectPipeline: GPUComputePipeline;
let computeShadePipeline: GPUComputePipeline;
let computeFinishPassPipeline: GPUComputePipeline;
let computeSortIntersectionsPipeline: GPUComputePipeline;
let uniformsBuffer: GPUBuffer;
let storedBuffer: GPUBuffer;
let commandBuffer: GPUCommandBuffer;

const gpuReady = Promise.withResolvers<void>();

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

    const gltf = await new Promise((resolve, reject) => new GLTFLoader().load("/icosphere.glb", resolve));
    console.log(gltf);

    let nBytes = 0;
    for (const child of gltf.scene.children) {
        nBytes += child.geometry.index.array.length / 3 * 48;
    }

    const triangles = new ArrayBuffer(nBytes);

    let offset = 0;

    for (const child of gltf.scene.children) {
        const pos = child.geometry.attributes.position.array;
        const index = child.geometry.index.array;

        for (let i = 0; i < index.length; i += 3) {
            new Float32Array(triangles, offset).set(pos.slice(3 * index[i], 3 * index[i] + 3));
            new Float32Array(triangles, offset + 16).set(pos.slice(3 * index[i + 1], 3 * index[i + 1] + 3));
            new Float32Array(triangles, offset + 32).set(pos.slice(3 * index[i + 2], 3 * index[i + 2] + 3));
            new Uint32Array(triangles, offset + 12).set([0]);

            offset += 48;
        }
    }

        
    // const quads = [
    //     new Quad(
    //         new Vec3(1, 1, -2),
    //         new Vec3(1, -1, -2),
    //         new Vec3(1, -1, -4),
    //         new Vec3(1, 1, -4),
    //         1,
    //     ),

    //     new Quad(
    //         new Vec3(-1, 1, -2),
    //         new Vec3(1, 1, -2),
    //         new Vec3(1, 1, -4),
    //         new Vec3(-1, 1, -6),
    //     ),

    //     new Quad(
    //         new Vec3(-1, -1, -2),
    //         new Vec3(-1, 1, -2),
    //         new Vec3(-1, 1, -6),
    //         new Vec3(-1, -1, -6),
    //         2,
    //     ),

    //     new Quad(
    //         new Vec3(1, -1, -2),
    //         new Vec3(-1, -1, -2),
    //         new Vec3(-1, -1, -6),
    //         new Vec3(1, -1, -4),
    //         3,
    //     ),

    //     new Quad(
    //         new Vec3(1, 1, -4),
    //         new Vec3(-1, 1, -6),
    //         new Vec3(-1, -1, -6),
    //         new Vec3(1, -1, -4),
    //     ),

    //     // new Quad(
    //     //     new Vec3(0.75, 0.75, -4),
    //     //     new Vec3(-0.25, 0.75, -4),
    //     //     new Vec3(-0.25, -0.25, -4),
    //     //     new Vec3(0.75, -0.25, -4),
    //     //     [0, 0, 0, 1],
    //     //     [1, 1, 1, 1],
    //     // ),

    //     new Quad(
    //         new Vec3(0.5, -0.95, -1),
    //         new Vec3(-0.5, -0.95, -1),
    //         new Vec3(-0.5, -0.95, -6),
    //         new Vec3(0.5, -0.95, -6),
    //         4,
    //     ),

    //     new Quad(
    //         new Vec3(0.5, 0.3, -2),
    //         new Vec3(-0.5, 0.3, -2),
    //         new Vec3(-0.5, 0.3, -6),
    //         new Vec3(0.5, 0.3, -6),
    //     ),
    // ];

    // const triangles2 = new ArrayBuffer(quads.length * 96);
    // for (const [i, quad] of quads.entries()) {
    //     quad.writeTris(triangles2, i);
    // }

    trianglesBuffer = device.createBuffer({
        size: triangles.byteLength,
        usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });

    device.queue.writeBuffer(trianglesBuffer, 0, triangles);


    const materials = new Float32Array([
        0.8, 0.9, 0.9, 1,
        0, 0, 0, 0,
        1, 0, 0, 0,

        0.6, 0.1, 0.1, 0.3,
        0, 0, 0, 0,
        0.5, 0, 0, 0,

        0.1, 0.6, 0.1, 1,
        0, 0, 0, 0,
        0.5, 0, 0, 0,

        0.1, 0.1, 0.2, 1,
        0, 0, 0, 0,
        0.5, 0, 0, 0,

        0, 0, 0, 1,
        1, 1, 1, 1,
        0.5, 0, 0, 0,
    ]);
    materialsBuffer = device.createBuffer({
        size: materials.byteLength,
        usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });

    device.queue.writeBuffer(materialsBuffer, 0, materials);


    uniformsBuffer = device.createBuffer({
        size: 8,
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
            entryPoint: "comp",
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

    gpuReady.resolve();
});


const hardRerender = async (nextWidth: number, nextHeight: number) => {
    device.queue.writeBuffer(uniformsBuffer, 0, new Uint32Array([width, height]));

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

    

        
    const commandEncoder = device.createCommandEncoder();

    const computePassEncoder = commandEncoder.beginComputePass();
    computePassEncoder.setBindGroup(0, bindGroup);
    computePassEncoder.setPipeline(computeFullPipeline);
    computePassEncoder.dispatchWorkgroups(Math.ceil(nextWidth * nextHeight / 256));
    computePassEncoder.end();

    // const computePassEncoder = commandEncoder.beginComputePass();
    // computePassEncoder.setBindGroup(0, bindGroup);

    // const nWorkGroups = Math.ceil(nextWidth * nextHeight / 256);

    // for (let nPass = 0; nPass < 1; nPass++) {
    //     computePassEncoder.setPipeline(computeBeginPassPipeline);
    //     computePassEncoder.dispatchWorkgroups(nWorkGroups);

    //     for (let nBounce = 0; nBounce < 8; nBounce++) {
    //         computePassEncoder.setPipeline(computeIntersectPipeline);
    //         computePassEncoder.dispatchWorkgroups(nWorkGroups);

    //         computePassEncoder.setPipeline(computeSortIntersectionsPipeline);
    //         for (let nIter = 0; nIter < 96; nIter++) {
    //             computePassEncoder.dispatchWorkgroups(nWorkGroups);
    //         }

    //         computePassEncoder.setPipeline(computeShadePipeline);
    //         computePassEncoder.dispatchWorkgroups(nWorkGroups);
    //     }


    //     computePassEncoder.setPipeline(computeFinishPassPipeline);
    //     computePassEncoder.dispatchWorkgroups(nWorkGroups);
    // }

    // computePassEncoder.end();

    addRenderPass(commandEncoder);

    commandBuffer = commandEncoder.finish();

    await rerender(nextWidth, nextHeight);
};

const addRenderPass = (commandEncoder: GPUCommandEncoder) => {
    const renderPassEncoder = commandEncoder.beginRenderPass({
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

    renderPassEncoder.setBindGroup(0, bindGroup);
    renderPassEncoder.setVertexBuffer(0, vertBuffer);
    renderPassEncoder.setPipeline(renderPipeline);
    renderPassEncoder.draw(6);
    renderPassEncoder.end();
};

const rerender = async (nextWidth: number, nextHeight: number) => {
    let start = performance.now();
        
    
    device.queue.writeBuffer(storedBuffer, 0, new Uint32Array([0]));
    device.queue.submit([commandBuffer]);

    status = "rendering";

    device.queue.onSubmittedWorkDone().then(() => {
        status = `render finished in ${(performance.now() - start) / 1000} s`;
    });
};

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
