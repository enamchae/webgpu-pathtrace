<script lang="ts">
import Canvas from "./Canvas.svelte";
    import Overlays from "./Overlays.svelte";

let status = $state("loading JS");
</script>

<main>
    <Canvas
        bind:status
    />

    <Overlays
        {status}
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