<script setup>
import { computed, ref } from 'vue'
import { getProblems } from '../api/client'
import { usePolling } from '../composables/usePolling'
import TeamLink from '../components/TeamLink.vue'

const problems = ref(null)

async function refresh() {
  problems.value = await getProblems()
}

usePolling(refresh, 10000)

const problemTypes = computed(() => Object.keys(problems.value ?? {}).sort())
</script>

<template>
  <h1>Problems</h1>

  <p>This is a list of likely problems. It doesn't attempt to solve them, but hopefully tell you about them.</p>

  <table v-if="problems" class="table table-hover table-sm">
    <thead>
      <tr>
        <th>Problem Type</th>
        <th>Problems</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="type in problemTypes" :key="type">
        <td>{{ type }}</td>
        <td>
          <ul class="mb-0">
            <li v-for="problem in problems[type]" :key="problem.team">
              <TeamLink :team-number="problem.team">Team {{ problem.team }}</TeamLink> {{ problem.message }}
            </li>
          </ul>
        </td>
      </tr>
    </tbody>
  </table>
</template>
