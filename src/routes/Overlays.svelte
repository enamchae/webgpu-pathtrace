<script lang="ts">
    import Separator from "./Separator.svelte";

let {
    status,
}: {
    status: string,
} = $props();
</script>

<div class="overlays">
    <div class="panel">
        <div>
            <b>Status</b>&#x2003;{status}
        </div>

        <Separator />

        <div class="col">
            <b>Render method</b>
        </div>
    </div>
</div>

<style lang="scss">
.overlays {
    width: 25rem;
    padding: 1rem;
    

    overflow-y: auto;

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
    box-shadow: 0 0.5rem 2rem oklch(0.2 0.06 230 / 0.2);
    border-radius: 1.5rem / 1.25rem;
    color: oklch(1 0 0);

    pointer-events: auto;
}

.col {
    display: flex;
    flex-direction: column;
}
</style>