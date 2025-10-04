export enum RenderMethod {
    afterAllSamples,
    afterEverySample,
}

export class Store {
    renderMethod = $state<RenderMethod>(RenderMethod.afterEverySample);
    supersampleRate = $state(4);
    
    nRenderedSamples = $state(0);
    cumulativeSampleTime = $state(0);
    readonly nTargetSamples = $derived(this.supersampleRate * this.supersampleRate);
    readonly avgSampleTime = $derived(this.nRenderedSamples === 0 ? null : this.cumulativeSampleTime / this.nRenderedSamples);
}