import type { Rot3 } from "./Rot3.svelte";
import type { Vec3 } from "./Vec3.svelte";

export class Transformation {
    readonly pos: Vec3;
    readonly rot: Rot3;

    constructor({
        pos,
        rot,
    }: {
        pos: Vec3,
        rot: Rot3,
    }) {
        this.pos = pos;
        this.rot = rot;
    }
}