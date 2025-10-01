import { Vec3 } from "./Vec3.svelte";

export class Quad {
    constructor(
        readonly a: Vec3,
        readonly b: Vec3,
        readonly c: Vec3,
        readonly d: Vec3,
        readonly materialIndex: number=0,
    ) {}

    writeTris(buffer: ArrayBuffer, i: number) {
        new Float32Array(buffer, i * 96).set([...this.a, ...this.b, ...this.c]);
        new Uint32Array(buffer, i * 96 + 12).set([this.materialIndex]);

        new Float32Array(buffer, i * 96 + 48).set([...this.a, ...this.c, ...this.d]);
        new Uint32Array(buffer, i * 96 + 60).set([this.materialIndex]);
    }
}