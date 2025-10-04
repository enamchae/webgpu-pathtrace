<script lang="ts">
import Canvas from "./Canvas.svelte";
import Overlays from "./Overlays.svelte";
import { Store } from "./Store.svelte";

let status = $state("loading JS");
let err = $state<string | null>(null);
let store = new Store();
</script>

<main>
    <Canvas
        bind:status
        bind:err
        {store}
    />

    <Overlays
        {status}
        {err}
        {store}
    />
</main>

<style lang="scss">
main {
    width: 100vw;
    height: 100vh;

    display: grid;

    > :global(*) {
        grid-area: 1/1;
    }
}
</style>