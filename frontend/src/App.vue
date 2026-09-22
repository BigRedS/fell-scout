<script setup>
import { RouterView } from 'vue-router'
import AppNav from './components/AppNav.vue'
import AppFooter from './components/AppFooter.vue'
</script>

<template>
  <AppNav />
  <main class="container py-4">
    <RouterView />
  </main>
  <AppFooter />
</template>
