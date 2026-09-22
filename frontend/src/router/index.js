import { createRouter, createWebHistory } from 'vue-router'
import SummaryView from '../views/SummaryView.vue'
import TeamView from '../views/TeamView.vue'
import TeamsView from '../views/TeamsView.vue'
import CheckpointView from '../views/CheckpointView.vue'
import ArrivalsView from '../views/ArrivalsView.vue'
import CheckpointsView from '../views/CheckpointsView.vue'
import EntrantsView from '../views/EntrantsView.vue'
import LegsView from '../views/LegsView.vue'
import LaterunnersView from '../views/LaterunnersView.vue'
import ProblemsView from '../views/ProblemsView.vue'
import MapView from '../views/MapView.vue'
import ScratchTeamsView from '../views/ScratchTeamsView.vue'
import AdminView from '../views/AdminView.vue'
import AdminCheckpointsView from '../views/AdminCheckpointsView.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'summary',
      component: SummaryView,
      meta: { title: 'Summary' },
    },
    {
      path: '/team/:team',
      name: 'team',
      component: TeamView,
      meta: { title: (route) => `Team ${route.params.team}` },
    },
    {
      path: '/teams',
      name: 'teams',
      component: TeamsView,
      meta: { title: 'Teams' },
    },
    {
      path: '/checkpoint/:checkpoint',
      name: 'checkpoint',
      component: CheckpointView,
      meta: { title: (route) => `Checkpoint ${route.params.checkpoint}` },
    },
    {
      path: '/arrivals/:checkpoint',
      name: 'arrivals',
      component: ArrivalsView,
      meta: { title: (route) => `Arrivals for checkpoint ${route.params.checkpoint}` },
    },
    {
      path: '/checkpoints',
      name: 'checkpoints',
      component: CheckpointsView,
      meta: { title: 'Checkpoints' },
    },
    {
      path: '/entrants',
      name: 'entrants',
      component: EntrantsView,
      meta: { title: 'Entrants' },
    },
    {
      path: '/legs',
      name: 'legs',
      component: LegsView,
      meta: { title: 'Legs' },
    },
    {
      path: '/laterunners/:threshold?',
      name: 'laterunners',
      component: LaterunnersView,
      meta: { title: 'Late Runners' },
    },
    {
      path: '/problems',
      name: 'problems',
      component: ProblemsView,
      meta: { title: 'Problems' },
    },
    {
      path: '/map',
      name: 'map',
      component: MapView,
      meta: { title: 'Map' },
    },
    {
      path: '/scratch-teams',
      name: 'scratch-teams',
      component: ScratchTeamsView,
      meta: { title: 'Scratch Teams' },
    },
    {
      path: '/admin',
      name: 'admin',
      component: AdminView,
      meta: { title: 'Admin' },
    },
    {
      path: '/admin/checkpoints',
      name: 'admin-checkpoints',
      component: AdminCheckpointsView,
      meta: { title: 'Checkpoint Admin' },
    },
  ],
})

// Matches the old server-rendered layout's `<% page.title %> | FellScout`
// pattern - the SPA never reloads between pages, so nothing else would ever
// update the browser tab title otherwise.
router.afterEach((to) => {
  const title = typeof to.meta.title === 'function' ? to.meta.title(to) : to.meta.title
  document.title = title ? `${title} | Fell Scout` : 'Fell Scout'
})

export default router
