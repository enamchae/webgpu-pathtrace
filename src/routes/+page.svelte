<script lang="ts">
import Canvas from "./Canvas.svelte";
</script>

<main>
    <Canvas />
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