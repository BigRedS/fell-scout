<script setup>
defineProps({
  teamNumber: { type: [Number, String], required: true },
})
</script>

<template>
  <router-link :to="`/team/${teamNumber}`"><slot>{{ teamNumber }}</slot></router-link>
</template>
