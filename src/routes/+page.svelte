<script lang="ts">
import Canvas from "./Canvas.svelte";
    import Overlays from "./Overlays.svelte";

let nthPass = $state(0);
let lastRenderElapsedTime = $state(0);
</script>

<main>
    <Canvas
        bind:nthPass
        bind:lastRenderElapsedTime
    />

    <Overlays
        {nthPass}
        {lastRenderElapsedTime}
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