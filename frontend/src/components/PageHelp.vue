<script setup>
// The explanatory text at the top of a page: open on desktop, folded away on
// phones so the data is on the first screen. Checked once at load, not
// tracked - after that the reader's own open/close wins.
const startOpen = window.matchMedia('(min-width: 768px)').matches
</script>

<template>
  <details class="mb-3" :open="startOpen">
    <summary class="text-body-secondary">About this page</summary>
    <div class="mt-2">
      <slot />
    </div>
  </details>
</template>
