export class Vec3 {
    x: number = $state()!;
    y: number = $state()!;
    z: number = $state()!;

    constructor(x: number, y: number, z: number) {
        this.x = x;
        this.y = y;
        this.z = z;
    }

    buffer() {
        return [this.x, this.y, this.z, 1];
    }

    * [Symbol.iterator]() {
        yield* this.buffer();
    }
}