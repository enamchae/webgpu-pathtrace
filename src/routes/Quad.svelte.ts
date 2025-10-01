import { Vec3 } from "./Vec3.svelte";

export class Quad {
    constructor(
        readonly a: Vec3,
        readonly b: Vec3,
        readonly c: Vec3,
        readonly d: Vec3,
        readonly diffuse: [number, number, number, number]=[0.8, 0.9, 0.9, 1],
        readonly emissive: [number, number, number, number]=[0, 0, 0, 0],
    ) {}

    triBuffer() {
        return [
            ...this.a,
            ...this.b,
            ...this.c,
            
            ...this.a,
            ...this.c,
            ...this.d,
        ];
    }

    materialBuffer() {
        return [
            ...this.diffuse,
            ...this.emissive,

            ...this.diffuse,
            ...this.emissive,
        ];
    }
}