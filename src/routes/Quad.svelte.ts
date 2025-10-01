import { Vec3 } from "./Vec3.svelte";

export class Quad {
    constructor(
        readonly a: Vec3,
        readonly b: Vec3,
        readonly c: Vec3,
        readonly d: Vec3,
    ) {}

    buffer() {
        return [
            ...this.a,
            ...this.b,
            ...this.c,
            
            ...this.a,
            ...this.c,
            ...this.d,
        ];
    }
}