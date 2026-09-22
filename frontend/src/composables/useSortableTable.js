import { ref, computed, unref } from 'vue'

// Replaces the old site's FancyTable (jQuery) click-to-sort-column +
// global-search-box behaviour, used on several list pages. Takes a reactive
// rows array/ref and a column definition array: [{ key, label, value(row),
// numeric? }]. `value(row)` is used for both sorting and searching, so any
// cell can render something richer (a link, a badge) via a scoped slot in
// SortableTable.vue while still sorting/searching on the underlying value.
export function useSortableTable(rows, columns, options = {}) {
  const { defaultSortColumn = 0, defaultSortOrder = 'asc', searchable = true } = options

  const sortColumn = ref(defaultSortColumn)
  const sortOrder = ref(defaultSortOrder)
  const searchTerm = ref('')

  function setSort(index) {
    if (sortColumn.value === index) {
      sortOrder.value = sortOrder.value === 'asc' ? 'desc' : 'asc'
    } else {
      sortColumn.value = index
      sortOrder.value = 'asc'
    }
  }

  const filteredRows = computed(() => {
    const allRows = unref(rows)
    if (!searchable || !searchTerm.value.trim()) return allRows
    const term = searchTerm.value.toLowerCase()
    return allRows.filter((row) =>
      columns.some((col) => String(col.value(row) ?? '').toLowerCase().includes(term)),
    )
  })

  const sortedRows = computed(() => {
    const col = columns[sortColumn.value]
    if (!col) return filteredRows.value
    const dir = sortOrder.value === 'asc' ? 1 : -1
    return [...filteredRows.value].sort((a, b) => {
      const av = col.value(a)
      const bv = col.value(b)
      if (col.numeric) return ((Number(av) || 0) - (Number(bv) || 0)) * dir
      return String(av ?? '').localeCompare(String(bv ?? '')) * dir
    })
  })

  return { sortColumn, sortOrder, searchTerm, searchable, setSort, sortedRows }
}
