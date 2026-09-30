<script setup>
import { computed, ref } from 'vue'
import { getSummary } from '../api/client'
import { usePolling } from '../composables/usePolling'
import TeamLink from '../components/TeamLink.vue'
import PageHelp from '../components/PageHelp.vue'

const summary = ref(null)

async function refresh() {
  summary.value = await getSummary()
}

usePolling(refresh, 10000)

const rows = computed(() => {
  if (!summary.value) return []
  const routes = summary.value.routes ?? {}
  const routeRows = Object.keys(routes)
    .sort()
    .map((name) => ({ name, ...routes[name] }))
  return [{ name: 'All', ...summary.value.general }, ...routeRows]
})

function sortedTeamsOut(row) {
  return [...(row.teams_out ?? [])].sort((a, b) => a - b)
}
</script>

<template>
  <h1>Summary</h1>

  <PageHelp>
    <p>
      This is a summary of the whole event; for an idea of which teams are where, see the
      <router-link to="/checkpoints">checkpoints</router-link> page, or the specific checkpoint arrivals boards which
      you can find there.
    </p>

    <p>
      'Next checkpoints' runs from the furthest-back to the furthest-forward checkpoint that is
      any team's next one.
    </p>
  </PageHelp>

  <div v-if="summary" class="row row-cols-1 row-cols-md-2 g-3">
    <div v-for="row in rows" :key="row.name" class="col">
      <div class="card h-100">
        <div class="card-header fw-bold">{{ row.name === 'All' ? 'All routes' : row.name }}</div>
        <div class="card-body">
          <p class="mb-2">
            <b>{{ row.num_not_completed }}</b> still out &middot; {{ row.num_finished }} finished &middot;
            {{ row.num_retired }} retired
          </p>
          <p class="mb-2">Next checkpoints: {{ row.min_cp }} to {{ row.max_cp }}</p>
          <p v-if="row.earliest_finish" class="mb-1">
            First to finish:
            <TeamLink :team-number="row.earliest_finish.team_number">{{ row.earliest_finish.team_name }}</TeamLink>
            ({{ row.earliest_finish.unit }}), {{ row.earliest_finish.finish_expected_in }}
          </p>
          <p v-if="row.latest_finish" class="mb-2">
            Last to finish:
            <TeamLink :team-number="row.latest_finish.team_number">{{ row.latest_finish.team_name }}</TeamLink>
            ({{ row.latest_finish.unit }}), {{ row.latest_finish.finish_expected_in }}
          </p>
          <!-- The 'All' card's list would just be every route's list again -->
          <div v-if="row.name !== 'All'">
            <TeamLink
              v-for="team in sortedTeamsOut(row)"
              :key="team"
              :team-number="team"
              class="badge text-bg-primary mb-1 me-1"
              style="min-width: 50px; font-size: 1.1em"
            >
              {{ team }}
            </TeamLink>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
