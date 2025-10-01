import type { Vec3 } from "./Vec3.svelte";

export class Rot3 {
    scalar: number = $state()!;
    xy: number = $state()!;
    yz: number = $state()!;
    zx: number = $state()!;

    constructor(scalar: number, xy: number, yz: number, zx: number) {
        this.scalar = scalar;
        this.xy = xy;
        this.yz = yz;
        this.zx = zx;
    }

    rotate(vec: Vec3) {
        
    }
}