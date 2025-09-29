<script lang="ts">
import { onMount } from "svelte";
import shaderSrc from "./shader.wgsl?raw";

let err = $state<string | null>(null);

let canvas: HTMLCanvasElement;

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

    const device = await adapter.requestDevice();
    if (device === null) {
        err = "could not get device";
        return;
    }

    const context = canvas.getContext("webgpu");
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


    const shaderModule = device.createShaderModule({code: shaderSrc});

    const verts = new Float32Array([
        0.0, 0.6, 0, 1,
        1, 0, 0, 1,

        -0.5, -0.6, 0, 1,
        0, 1, 0, 1,

        0.5, -0.6, 0, 1,
        0, 0, 1, 1
    ]);

    const vertBuffer = device.createBuffer({
        size: verts.byteLength,
        usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    });

    device.queue.writeBuffer(vertBuffer, 0, verts, 0, verts.length);

    const pipeline = device.createRenderPipeline({
        vertex: {
            module: shaderModule,
            entryPoint: "vert",
            buffers: [
                {
                    attributes: [
                        {
                            shaderLocation: 0,
                            offset: 0,
                            format: "float32x4",
                        },

                        {
                            shaderLocation: 1,
                            offset: 16,
                            format: "float32x4",
                        },
                    ],

                    arrayStride: 32,
                    stepMode: "vertex",
                },
            ],
        },

        fragment: {
            module: shaderModule,
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

        layout: "auto",
    });


    const commandEncoder = device.createCommandEncoder();

    const passEncoder = commandEncoder.beginRenderPass({
        colorAttachments: [
            {
                clearValue: {
                    r: 0,
                    g: 0.5,
                    b: 1,
                    a: 1,
                },
                loadOp: "clear",
                storeOp: "store",
                view: context.getCurrentTexture().createView(),
            },
        ],
    });

    passEncoder.setPipeline(pipeline);
    passEncoder.setVertexBuffer(0, vertBuffer);
    passEncoder.draw(3);

    passEncoder.end();


    device.queue.submit([commandEncoder.finish()]);
});
</script>

{#if err !== null}
    {err}
{/if}

<canvas bind:this={canvas}></canvas>
