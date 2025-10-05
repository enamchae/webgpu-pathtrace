export enum RenderTiming {
    afterAllSamples,
    afterEverySample,
}

export enum SpatialHierarchy {
    none,
    octree,
}

export class Store {
    renderTiming = $state<RenderTiming>(RenderTiming.afterEverySample);
    materialSorting = $state(false);
    spatialHierarchy = $state(SpatialHierarchy.octree);
    dofRadius = $state(0);
    dofDistance = $state(10);
    supersampleRate = $state(4);
    nSamplesPerGridCell = $state(1);
    nMaxBounces = $state(16);
    readonly orbit = new CameraOrbit();
    
    
    nRenderedSamples = $state(0);
    cumulativeSampleTime = $state(0);
    readonly nTargetSamples = $derived(this.supersampleRate * this.supersampleRate * this.nSamplesPerGridCell);
    readonly avgSampleTime = $derived(this.nRenderedSamples === 0 ? null : this.cumulativeSampleTime / this.nRenderedSamples);

    nTriangles = $state<number | null>(null);
}

export class CameraOrbit {
    radius = $state(4);
    lat = $state(Math.PI / 3);
    long = $state(Math.PI / 4);

    mat() {
        const ct = Math.cos(this.long);
        const st = Math.sin(this.long);
        const cp = Math.cos(this.lat);
        const sp = Math.sin(this.lat);
        const r = this.radius;

        return new Float32Array([
            ct, 0, -st, 0,
            sp * st, cp, sp * ct, 0,
            cp * st, -sp, cp * ct, 0,
            r * cp * st, -r * sp, r * cp * ct, 1,
        ]);
    }
}