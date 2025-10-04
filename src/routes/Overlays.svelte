<script lang="ts">
    import Separator from "./Separator.svelte";
    import { RenderMethod, type Store } from "./Store.svelte";

let {
    status,
    err,
    store,
}: {
    status: string,
    err: string | null,
    store: Store,
} = $props();
</script>

<div class="overlays">
    <div class="panel">
        <div>
            <b>Status</b>&#x2003;{err === null ? status : `error: ${err}`}
        </div>
    </div>

    <div class="panel">
        <div class="col">
            <b>Render method</b>

            <div>
                <label>
                    <input
                        type="radio"
                        name="render-method"
                        value={RenderMethod.afterEverySample}
                        bind:group={store.renderMethod}
                    />

                    after every sample
                </label>
            </div>

            <div>
                <label>
                    <input
                        type="radio"
                        name="render-method"
                        value={RenderMethod.afterAllSamples}
                        bind:group={store.renderMethod}
                    />

                    after all samples
                </label>
            </div>
        </div>

        <Separator />

        <div class="col">
            <b>Supersample rate</b>
            <input
                type="number"
                value={store.supersampleRate}
                onchange={event => {
                    const numeric = Number(event.currentTarget.value);
                    store.supersampleRate = isNaN(numeric) ? 4 : numeric;
                }}
            />
        </div>
    </div>

    <div class="panel">
        <div>
            <b># samples complete</b>&#x2003;{store.nRenderedSamples} / {store.nTargetSamples}
        </div>

        <div>
            <b>Average sample time (incl. overhead)</b>&#x2003;{
                store.avgSampleTime === null
                    ? "--"
                    : `${(store.avgSampleTime / 1000).toFixed(3)} s`
            }
        </div>

        <div>
            <b>Total sample time (incl. overhead)</b>&#x2003;{store.cumulativeSampleTime / 1000} s
        </div>
    </div>
</div>

<style lang="scss">
.overlays {
    width: 30rem;
    padding: 1rem;
    overflow-y: auto;

    display: flex;
    flex-direction: column;
    gap: 1rem;

    pointer-events: none;
}

.panel {
    padding: 0.75rem 1rem;
    border: 2px solid oklch(1 0 0 / 0.25);

    display: flex;
    flex-direction: column;
    gap: 0.5rem;

    background: oklch(0.1 0.02 170 / 0.2);
    backdrop-filter: blur(8px);
    box-shadow: 0 0.5rem 1rem oklch(0.2 0.06 230 / 0.2);
    border-radius: 1.5rem / 1.25rem;
    color: oklch(1 0 0);

    pointer-events: auto;
}

.col {
    display: flex;
    flex-direction: column;
}

input[type="number"] {
    border-radius: 0.5rem;

    border: 2px solid oklch(1 0 0 / 0.25);
    background: oklch(0.1 0.02 170 / 0.2);
    padding: 0.25rem;
}
</style>