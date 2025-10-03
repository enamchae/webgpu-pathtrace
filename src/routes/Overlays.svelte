<script lang="ts">
let {
    status,
}: {
    status: string,
} = $props();
</script>

<div class="overlays">
    <div>{status}</div>
</div>

<style lang="scss">
.overlays {
    width: 40%;
}
</style>