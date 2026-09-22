<script setup>
defineProps({
  checkpoint: { type: [Number, String], required: true },
})
</script>

<template>
  <router-link :to="`/checkpoint/${checkpoint}`"><slot>{{ checkpoint }}</slot></router-link>
</template>
