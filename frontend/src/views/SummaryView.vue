<script setup>
import { computed, ref } from 'vue'
import { getSummary } from '../api/client'
import { usePolling } from '../composables/usePolling'
import TeamLink from '../components/TeamLink.vue'

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

  <p>
    This is a summary of the whole event; for an idea of which teams are where, see the
    <a href="/checkpoints">checkpoints</a> page, or the specific checkpoint arrivals boards which
    you can find there.
  </p>

  <p>
    The 'Highest CP' is the furthest-forward checkpoint that is any team's next one, and the
    'Lowest CP' is the furthest back one that is any team's next one.
  </p>

  <table v-if="summary" class="table table-striped table-hover">
    <thead>
      <tr>
        <th class="text-center">Route</th>
        <th class="text-center">Lowest CP</th>
        <th class="text-center">Highest CP</th>
        <th class="text-center">Earliest-finishing team</th>
        <th class="text-center">Latest-finishing team</th>
        <th>Teams still out</th>
        <th>Teams not still out</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="row in rows" :key="row.name">
        <td>{{ row.name }}</td>
        <td class="text-center">{{ row.min_cp }}</td>
        <td class="text-center">{{ row.max_cp }}</td>
        <td class="text-center">
          <template v-if="row.earliest_finish">
            <TeamLink :team-number="row.earliest_finish.team_number">
              {{ row.earliest_finish.team_name }}<br />
              {{ row.earliest_finish.unit }}
            </TeamLink>
            <br />
            {{ row.earliest_finish.finish_expected_in }}
          </template>
        </td>
        <td class="text-center">
          <template v-if="row.latest_finish">
            <TeamLink :team-number="row.latest_finish.team_number">
              {{ row.latest_finish.team_name }}<br />
              {{ row.latest_finish.unit }}
            </TeamLink>
            <br />
            {{ row.latest_finish.finish_expected_in }}
          </template>
        </td>
        <td>
          {{ row.num_not_completed }}
          <br />
          <TeamLink
            v-for="team in sortedTeamsOut(row)"
            :key="team"
            :team-number="team"
            class="badge text-bg-primary mb-1 me-1"
            style="min-width: 50px; font-size: 1.1em"
          >
            {{ team }}
          </TeamLink>
        </td>
        <td>{{ row.num_finished }} Finished<br />{{ row.num_retired }} Retired</td>
      </tr>
    </tbody>
  </table>
</template>
