<script lang="ts">
let {
    nthPass,
    lastRenderElapsedTime,
}: {
    nthPass: number,
    lastRenderElapsedTime: number,
} = $props();
</script>

<div class="overlays">
    <div>Sample #{nthPass}</div>
    <div>Rendered in {lastRenderElapsedTime / 1000} s</div>
</div>

<style lang="scss">
.overlays {
    width: 40%;
}
</style>