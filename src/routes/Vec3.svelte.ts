export class Vec3 {
    x: number = $state()!;
    y: number = $state()!;
    z: number = $state()!;

    constructor(x: number, y: number, z: number) {
        this.x = x;
        this.y = y;
        this.z = z;
    }
}