import L from 'leaflet'
import './leafletFullscreen.css'

// A CSS overlay rather than the browser Fullscreen API: it works on iPhone
// Safari, which only allows the API on video elements. The map's container
// must have the `map-responsive` class (see leafletFullscreen.css).
const FullscreenControl = L.Control.extend({
  options: { position: 'topleft' },

  onAdd(map) {
    const wrapper = L.DomUtil.create('div', 'leaflet-bar')
    const button = L.DomUtil.create('a', '', wrapper)
    button.href = '#'
    button.setAttribute('role', 'button')

    const container = map.getContainer()
    const isFullscreen = () => container.classList.contains('map-fullscreen')

    const render = () => {
      const label = isFullscreen() ? 'Exit full screen' : 'Full screen'
      button.title = label
      button.setAttribute('aria-label', label)
      button.textContent = isFullscreen() ? '✕' : '⛶'
      button.style.fontSize = '18px'
      button.style.textAlign = 'center'
    }

    const onKeydown = (e) => {
      if (e.key === 'Escape') setFullscreen(false)
    }

    // Leaflet caches the container size, so it has to be told when the CSS
    // changes it, or the tiles render grey/partial.
    const setFullscreen = (on) => {
      container.classList.toggle('map-fullscreen', on)
      if (on) document.addEventListener('keydown', onKeydown)
      else document.removeEventListener('keydown', onKeydown)
      render()
      map.invalidateSize()
    }

    L.DomEvent.disableClickPropagation(wrapper)
    L.DomEvent.on(button, 'click', (e) => {
      L.DomEvent.preventDefault(e)
      setFullscreen(!isFullscreen())
    })

    // The view calls map.remove() when it's destroyed - don't leave the Esc
    // listener behind.
    map.on('unload', () => document.removeEventListener('keydown', onKeydown))

    render()
    return wrapper
  },
})

export function addFullscreenControl(map) {
  new FullscreenControl().addTo(map)
}
