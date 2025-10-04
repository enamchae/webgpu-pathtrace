export enum RenderTiming {
    afterAllSamples,
    afterEverySample,
}

export class Store {
    renderTiming = $state<RenderTiming>(RenderTiming.afterEverySample);
    supersampleRate = $state(4);
    nSamplesPerGridCell = $state(1);
    nMaxBounces = $state(8);
    
    nRenderedSamples = $state(0);
    cumulativeSampleTime = $state(0);
    readonly nTargetSamples = $derived(this.supersampleRate * this.supersampleRate * this.nSamplesPerGridCell);
    readonly avgSampleTime = $derived(this.nRenderedSamples === 0 ? null : this.cumulativeSampleTime / this.nRenderedSamples);
}