/* GeoNexo Admin — painel de locais e respostas */

// Limits imposed by the BLE protocol (lib/core/ble/ble_question_protocol.dart).
const BLE = {
  promptMax: 44,
  labelMax: 14,
  minOptions: 2,
  maxOptions: 4,
};

const PRESETS = {
  yn: ['Sim', 'Não'],
  ynm: ['Sim', 'Não', 'Talvez'],
  rating: ['Ótimo', 'Bom', 'Regular', 'Ruim'],
};

const STATUS_LABELS = {
  processed: 'Processada',
  done: 'Processada',
  pending: 'Pendente',
  processing: 'Processando',
  failed: 'Falhou',
};

const CATEGORY_LABELS = {
  school: 'Escola',
  college: 'Faculdade',
  university: 'Universidade',
  hospital: 'Hospital',
  clinic: 'Clínica',
  police: 'Polícia',
  fire_station: 'Bombeiros',
  townhall: 'Prefeitura',
  courthouse: 'Fórum',
  library: 'Biblioteca',
  post_office: 'Correios',
  bus_station: 'Rodoviária',
  park: 'Parque',
  garden: 'Jardim',
  playground: 'Playground',
  sports_centre: 'Centro esportivo',
  government: 'Órgão público',
  museum: 'Museu',
  gallery: 'Galeria',
  attraction: 'Atração',
  viewpoint: 'Mirante',
  artwork: 'Obra de arte',
  information: 'Informações',
};

const COLORS = {
  accent: '#0d7c7c',
  edit: '#c2410c',
  poi: '#6366f1',
  status: {
    processed: '#0d7c7c',
    pending: '#d4a017',
    processing: '#6366f1',
    failed: '#c2410c',
  },
};

const state = {
  view: viewFromPath(window.location.pathname),
  catalog: { locations: [], questions: [] },
  map: null,
  layers: {},
  editor: {
    open: false,
    locationId: null,
    questionId: null,
    point: null,
    options: [],
    dirty: false,
    marker: null,
    circle: null,
    reverseSeq: 0,
  },
  search: { seq: 0, results: [], active: -1 },
  dashboard: { data: null, timer: null, charts: {} },
};

const $ = (id) => document.getElementById(id);

const els = {
  sessionEmail: $('session-email'),
  logoutButton: $('logout-button'),
  configView: $('config-view'),
  dashboardView: $('dashboard-view'),
  // locations
  locationsCount: $('locations-count'),
  newLocationButton: $('new-location-button'),
  listPanel: $('list-panel'),
  listFilter: $('list-filter-input'),
  locationsList: $('locations-list'),
  // search
  searchInput: $('place-search-input'),
  searchResults: $('place-search-results'),
  // editor
  editor: $('editor-panel'),
  editorTitle: $('editor-title'),
  editorBack: $('editor-back'),
  editorDelete: $('editor-delete'),
  editorUndo: $('editor-undo'),
  editorRedo: $('editor-redo'),
  editorCancel: $('editor-cancel'),
  editorSave: $('editor-save'),
  locName: $('loc-name'),
  locCity: $('loc-city'),
  locActive: $('loc-active'),
  locRadius: $('loc-radius'),
  locRadiusNumber: $('loc-radius-number'),
  pointCard: $('point-card'),
  pointAddress: $('point-address'),
  pointCoords: $('point-coords'),
  qEnabled: $('q-enabled'),
  qFields: $('question-fields'),
  qPrompt: $('q-prompt'),
  qPromptCount: $('q-prompt-count'),
  qPromptHint: $('q-prompt-hint'),
  qOptions: $('q-options'),
  qAddOption: $('q-add-option'),
  qPresets: $('q-presets'),
  previewPrompt: $('preview-prompt'),
  previewOptions: $('preview-options'),
  // map
  locateButton: null, // created as a Leaflet control in initMap()
  publicPlacesButton: $('public-places-button'),
  clearPublicButton: $('clear-public-button'),
  mapHint: $('map-hint'),
  // dashboard
  refreshButton: $('refresh-button'),
  dashboardUpdated: $('dashboard-updated'),
  statsGrid: $('stats-grid'),
  responsesFilter: $('responses-filter'),
  responsesTable: $('responses-table'),
  topCities: $('top-cities'),
  recentDevices: $('recent-devices'),
  // misc
  toasts: $('toasts'),
  confirmDialog: $('confirm-dialog'),
};

init().catch((error) => {
  console.error(error);
  toast('Falha ao iniciar o painel.', 'error');
});

/* ======================================================================
   Bootstrapping & navigation
   ====================================================================== */

async function init() {
  await loadSession();
  initMap();
  bindEvents();
  showView(state.view);
  await loadCatalog();
  fitToLocations();
}

function viewFromPath(pathname) {
  return pathname.includes('/dashboard') ? 'dashboard' : 'config';
}

function showView(view) {
  state.view = view;
  document.querySelectorAll('[data-nav]').forEach((link) => {
    link.classList.toggle('active', link.dataset.nav === view);
  });
  els.configView.hidden = view !== 'config';
  els.dashboardView.hidden = view !== 'dashboard';
  document.title = `${view === 'dashboard' ? 'Respostas' : 'Locais'} · GeoNexo Admin`;

  clearInterval(state.dashboard.timer);
  if (view === 'dashboard') {
    safe(loadDashboard)();
    state.dashboard.timer = setInterval(() => {
      if (!document.hidden) safe(loadDashboard)();
    }, 30000);
  } else {
    requestAnimationFrame(() => state.map?.invalidateSize());
  }
}

function bindEvents() {
  document.querySelectorAll('[data-nav]').forEach((link) => {
    link.addEventListener('click', (event) => {
      event.preventDefault();
      const view = link.dataset.nav;
      if (view === state.view) return;
      history.pushState({}, '', link.getAttribute('href'));
      showView(view);
    });
  });
  window.addEventListener('popstate', () => showView(viewFromPath(location.pathname)));

  els.logoutButton.addEventListener('click', safe(logout));
  els.refreshButton.addEventListener('click', safe(loadDashboard));
  els.responsesFilter.addEventListener('input', () => renderResponsesTable());

  // List
  els.newLocationButton.addEventListener('click', () => requestOpenEditor(null));
  els.listFilter.addEventListener('input', renderLocationsList);

  // Search
  els.searchInput.addEventListener('input', debounce(safe(runPlaceSearch), 350));
  els.searchInput.addEventListener('keydown', onSearchKeydown);
  els.searchInput.addEventListener('focus', () => {
    if (state.search.results.length) els.searchResults.hidden = false;
  });
  document.addEventListener('click', (event) => {
    if (!event.target.closest('#place-search')) els.searchResults.hidden = true;
  });

  // Editor
  els.editor.addEventListener('submit', (event) => {
    event.preventDefault();
    safe(saveEditor)();
  });
  els.editorBack.addEventListener('click', () => requestCloseEditor());
  els.editorCancel.addEventListener('click', () => requestCloseEditor());
  els.editorDelete.addEventListener('click', safe(deleteCurrentLocation));
  els.editor.addEventListener('input', () => {
    state.editor.dirty = true;
    historySchedule();
  });
  els.editorUndo.addEventListener('click', undoEdit);
  els.editorRedo.addEventListener('click', redoEdit);

  els.locRadius.addEventListener('input', () => setRadius(els.locRadius.value));
  els.locRadiusNumber.addEventListener('input', () => {
    // Live preview while typing; normalisation happens on change.
    const value = Number(els.locRadiusNumber.value);
    if (value >= 20 && value <= 2000) {
      els.locRadius.value = Math.min(value, Number(els.locRadius.max));
      state.editor.circle?.setRadius(value);
    }
  });
  els.locRadiusNumber.addEventListener('change', () => setRadius(els.locRadiusNumber.value));

  els.qEnabled.addEventListener('change', () => {
    syncQuestionEnabled();
    historyCommit();
  });
  els.qPrompt.addEventListener('input', renderPreview);
  els.qAddOption.addEventListener('click', () => {
    addOption('');
    const inputs = els.qOptions.querySelectorAll('input');
    inputs[inputs.length - 1]?.focus();
  });
  els.qPresets.addEventListener('click', (event) => {
    const key = event.target.closest('[data-preset]')?.dataset.preset;
    if (key) applyPreset(PRESETS[key]);
  });

  // Map tools
  els.publicPlacesButton.addEventListener('click', safe(searchPublicPlacesInView));
  els.clearPublicButton.addEventListener('click', () => {
    state.layers.pois.clearLayers();
    els.clearPublicButton.hidden = true;
  });

  // Keyboard shortcuts
  document.addEventListener('keydown', (event) => {
    if (state.view !== 'config') return;
    const typing = /INPUT|TEXTAREA/.test(document.activeElement?.tagName || '');
    const mod = event.ctrlKey || event.metaKey;

    // Undo / redo inside the editor (also while typing: text edits are part of the history).
    if (mod && !event.altKey && state.editor.open && !els.confirmDialog.open
      && document.activeElement !== els.searchInput) {
      const key = event.key.toLowerCase();
      if (key === 'z' && !event.shiftKey) {
        event.preventDefault();
        undoEdit();
        return;
      }
      if (key === 'y' || (key === 'z' && event.shiftKey)) {
        event.preventDefault();
        redoEdit();
        return;
      }
    }

    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's' && state.editor.open) {
      event.preventDefault();
      safe(saveEditor)();
      return;
    }
    if (event.key === '/' && !typing) {
      event.preventDefault();
      els.searchInput.focus();
      els.searchInput.select();
      return;
    }
    if (event.key === 'Escape' && state.editor.open && !els.confirmDialog.open
      && document.activeElement !== els.searchInput) {
      requestCloseEditor();
    }
  });

  window.addEventListener('beforeunload', (event) => {
    if (state.editor.open && state.editor.dirty) event.preventDefault();
  });
}

async function loadSession() {
  const data = await fetchJson('/api/admin/auth/session');
  els.sessionEmail.textContent = data.admin?.email || '';
  els.sessionEmail.title = data.admin?.email || '';
}

async function logout() {
  await fetchJson('/api/admin/auth/logout', { method: 'POST' });
  window.location.href = '/admin/login';
}

/* ======================================================================
   Map
   ====================================================================== */

function initMap() {
  state.map = L.map('admin-map', { zoomControl: false }).setView([-14.235, -51.925], 4);
  L.control.zoom({ position: 'bottomright' }).addTo(state.map);

  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap',
    maxZoom: 19,
  }).addTo(state.map);

  // Permanent labels only when zoomed in enough to avoid overlap.
  const syncLabels = () =>
    state.map.getContainer().classList.toggle('hide-labels', state.map.getZoom() < 13);
  state.map.on('zoomend', syncLabels);
  syncLabels();

  state.layers.locations = L.layerGroup().addTo(state.map);
  state.layers.pois = L.layerGroup().addTo(state.map);
  state.layers.editing = L.layerGroup().addTo(state.map);

  state.layers.me = L.layerGroup().addTo(state.map);

  // Bottom-right corner stacks newer controls on top, so this sits above the zoom buttons.
  const LocateControl = L.Control.extend({
    options: { position: 'bottomright' },
    onAdd() {
      const container = L.DomUtil.create('div', 'leaflet-bar locate-control');
      const button = L.DomUtil.create('a', '', container);
      button.href = '#';
      button.role = 'button';
      button.title = 'Minha localização';
      button.setAttribute('aria-label', 'Minha localização');
      button.innerHTML = '<svg><use href="#i-locate"/></svg>';
      L.DomEvent.disableClickPropagation(container);
      L.DomEvent.on(button, 'click', (event) => {
        L.DomEvent.preventDefault(event);
        locateMe();
      });
      els.locateButton = button;
      return container;
    },
  });
  new LocateControl().addTo(state.map);

  state.map.on('click', (event) => {
    if (state.editor.open) {
      setPoint(event.latlng.lat, event.latlng.lng);
      return;
    }
    showCreatePopup(event.latlng, 'Novo local aqui?');
  });
}

function showCreatePopup(latlng, title) {
  const popup = L.popup()
    .setLatLng(latlng)
    .setContent(`
      <strong>${escapeHtml(title)}</strong>
      <span class="popup-meta mono">${formatCoords(latlng.lat, latlng.lng)}</span>
      <button class="btn btn-primary" data-popup-action="create">Criar local aqui</button>`)
    .openOn(state.map);
  bindPopupAction(popup, 'create', () => {
    state.map.closePopup();
    requestOpenEditor(null, { lat: latlng.lat, lng: latlng.lng });
  });
}

/* ----- My location (browser geolocation) ----- */

function locateMe() {
  if (!('geolocation' in navigator)) {
    toast('Este navegador não suporta localização.', 'error');
    return;
  }
  if (!window.isSecureContext) {
    toast('A localização só funciona via HTTPS ou localhost.', 'error');
    return;
  }

  const button = els.locateButton;
  if (button.classList.contains('is-loading')) return;
  button.classList.add('is-loading');
  button.setAttribute('aria-busy', 'true');
  const done = () => {
    button.classList.remove('is-loading');
    button.removeAttribute('aria-busy');
  };

  navigator.geolocation.getCurrentPosition(
    (position) => {
      done();
      showMyLocation(position.coords);
    },
    (error) => {
      done();
      toast(geolocationErrorMessage(error), 'error');
    },
    { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
  );
}

function showMyLocation({ latitude: lat, longitude: lng, accuracy }) {
  const layer = state.layers.me;
  layer.clearLayers();

  L.circle([lat, lng], {
    radius: accuracy,
    color: '#2563eb',
    weight: 1,
    fillColor: '#2563eb',
    fillOpacity: 0.08,
    interactive: false,
  }).addTo(layer);

  L.marker([lat, lng], {
    icon: L.divIcon({ className: '', html: '<div class="me-dot"></div>', iconSize: [16, 16], iconAnchor: [8, 8] }),
    interactive: false,
    keyboard: false,
  }).addTo(layer);

  els.locateButton?.classList.add('is-active');
  const precision = `precisão ~${Math.round(accuracy)} m`;

  if (state.editor.open) {
    setPoint(lat, lng, { fly: true });
    toast(`Posição do local definida pela sua localização (${precision}).`);
  } else {
    state.map.flyTo([lat, lng], Math.max(state.map.getZoom(), 17), { duration: 0.6 });
    state.map.once('moveend', () => showCreatePopup({ lat, lng }, 'Você está aqui'));
  }

  if (accuracy > 200) {
    toast(`Localização imprecisa (${precision}). Ajuste o ponto no mapa se necessário.`, 'error');
  }
}

function geolocationErrorMessage(error) {
  switch (error?.code) {
    case 1: return 'Permissão de localização negada. Libere no cadeado da barra de endereço.';
    case 2: return 'Não foi possível obter sua localização.';
    case 3: return 'Tempo esgotado ao obter localização. Tente novamente.';
    default: return 'Falha ao obter localização.';
  }
}

function bindPopupAction(popup, action, handler) {
  const el = popup.getElement()?.querySelector(`[data-popup-action="${action}"]`);
  el?.addEventListener('click', handler);
}

const pinIcon = () =>
  L.divIcon({ className: '', html: '<div class="pin-icon"></div>', iconSize: [26, 26], iconAnchor: [13, 26] });
const poiIcon = () =>
  L.divIcon({ className: '', html: '<div class="poi-icon"></div>', iconSize: [14, 14], iconAnchor: [7, 7] });

function renderLocationLayers() {
  const layer = state.layers.locations;
  layer.clearLayers();

  for (const location of state.catalog.locations) {
    if (location.id === state.editor.locationId && state.editor.open) continue;
    if (!isFiniteCoord(location.latitude, location.longitude)) continue;

    const color = location.isActive ? COLORS.accent : '#9ca3af';
    const circle = L.circle([location.latitude, location.longitude], {
      radius: Number(location.radiusMeters || 100),
      color,
      weight: 2,
      fillColor: color,
      fillOpacity: 0.14,
      bubblingMouseEvents: false,
    });

    circle.bindTooltip(escapeHtml(location.name), {
      permanent: true,
      direction: 'top',
      className: 'loc-label',
      offset: [0, -4],
    });

    circle.on('click', (event) => {
      if (state.editor.open) {
        setPoint(event.latlng.lat, event.latlng.lng);
      } else {
        requestOpenEditor(location.id);
      }
    });

    circle.addTo(layer);
  }
}

function fitToLocations() {
  const points = state.catalog.locations
    .filter((l) => isFiniteCoord(l.latitude, l.longitude))
    .map((l) => [l.latitude, l.longitude]);
  if (!points.length) return;
  state.map.fitBounds(points, { padding: [60, 60], maxZoom: 15 });
}

async function searchPublicPlacesInView() {
  if (state.map.getZoom() < 12) {
    toast('Aproxime o mapa da região desejada para buscar locais públicos.');
    return;
  }

  const bounds = state.map.getBounds();
  const params = new URLSearchParams({
    south: bounds.getSouth(),
    north: bounds.getNorth(),
    west: bounds.getWest(),
    east: bounds.getEast(),
  });

  const button = els.publicPlacesButton;
  button.disabled = true;
  const originalHtml = button.innerHTML;
  button.lastChild.textContent = 'Buscando…';

  try {
    const data = await fetchJson(`/api/admin/discovery/public-places?${params}`);
    const places = data.results || [];
    state.layers.pois.clearLayers();

    places.forEach((place) => {
      const marker = L.marker([place.latitude, place.longitude], { icon: poiIcon() });
      marker.bindPopup(`
        <strong>${escapeHtml(place.name)}</strong>
        <span class="popup-meta">${escapeHtml(categoryLabel(place.category))}</span>
        <button class="btn btn-primary" data-popup-action="use">Usar este local</button>`);
      marker.on('popupopen', (event) => {
        bindPopupAction(event.popup, 'use', () => {
          state.map.closePopup();
          usePlace({ name: place.name, lat: place.latitude, lng: place.longitude });
        });
      });
      marker.addTo(state.layers.pois);
    });

    els.clearPublicButton.hidden = !places.length;
    toast(places.length ? `${places.length} locais públicos encontrados.` : 'Nenhum local público nesta área.');
  } finally {
    button.disabled = false;
    button.innerHTML = originalHtml;
  }
}

/** Uses a place (search result or POI) — fills the open editor or starts a new one. */
function usePlace({ name, lat, lng, city }) {
  if (state.editor.open) {
    historyFlush();
    if (name && !els.locName.value.trim()) els.locName.value = name;
    setPoint(lat, lng, { city, fly: true });
    return;
  }
  requestOpenEditor(null, { lat, lng, name, city });
}

/* ======================================================================
   Catalog & list
   ====================================================================== */

async function loadCatalog() {
  state.catalog = await fetchJson('/api/admin/catalog');
  renderLocationsList();
  renderLocationLayers();
}

function questionFor(locationId) {
  return state.catalog.questions.find((q) => q.locationId === locationId) || null;
}

function renderLocationsList() {
  const total = state.catalog.locations.length;
  els.locationsCount.textContent = total === 1 ? '1 local' : `${total} locais`;

  if (!total) {
    els.locationsList.innerHTML = `
      <div class="empty-state">
        <strong>Nenhum local cadastrado</strong>
        Busque um endereço acima ou clique no mapa para criar o primeiro.
        <div><button class="btn btn-primary" id="empty-new"><svg><use href="#i-plus"/></svg>Novo local</button></div>
      </div>`;
    $('empty-new').addEventListener('click', () => requestOpenEditor(null));
    return;
  }

  const term = normalize(els.listFilter.value);
  const items = state.catalog.locations.filter((location) => {
    if (!term) return true;
    const question = questionFor(location.id);
    return normalize(`${location.name} ${location.city} ${question?.prompt || ''}`).includes(term);
  });

  if (!items.length) {
    els.locationsList.innerHTML = '<div class="empty-state">Nenhum local corresponde ao filtro.</div>';
    return;
  }

  els.locationsList.innerHTML = items
    .map((location) => {
      const question = questionFor(location.id);
      const questionLine = question
        ? `<div class="loc-question"><svg><use href="#i-msg"/></svg><span>${escapeHtml(question.prompt)}</span>
             ${question.reactiveEnabled ? '' : '<span class="badge">pausada</span>'}</div>`
        : '<div class="loc-question none">Sem pergunta</div>';

      return `
        <button type="button" class="loc-item ${location.isActive ? '' : 'inactive'}" data-id="${location.id}">
          <div class="loc-top">
            <span class="loc-name">${escapeHtml(location.name)}</span>
            ${location.isActive ? '' : '<span class="badge">inativo</span>'}
          </div>
          <div class="loc-meta"><span class="cap">${escapeHtml(location.city || 'sem cidade')}</span> · raio ${Math.round(location.radiusMeters)} m</div>
          ${questionLine}
        </button>`;
    })
    .join('');

  els.locationsList.querySelectorAll('.loc-item').forEach((item) => {
    item.addEventListener('click', () => requestOpenEditor(item.dataset.id));
    item.addEventListener('mouseenter', () => highlightLocation(item.dataset.id, true));
    item.addEventListener('mouseleave', () => highlightLocation(item.dataset.id, false));
  });
}

function highlightLocation(id, on) {
  const location = state.catalog.locations.find((l) => l.id === id);
  if (!location) return;
  state.layers.locations.eachLayer((layer) => {
    const ll = layer.getLatLng?.();
    if (ll && ll.lat === location.latitude && ll.lng === location.longitude) {
      layer.setStyle({ weight: on ? 4 : 2, fillOpacity: on ? 0.28 : 0.14 });
    }
  });
}

/* ======================================================================
   Place search (Nominatim via backend)
   ====================================================================== */

const COORD_RE = /^\s*(-?\d{1,2}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)\s*$/;

async function runPlaceSearch() {
  const query = els.searchInput.value.trim();
  const seq = ++state.search.seq;

  if (query.length < 3) {
    state.search.results = [];
    els.searchResults.hidden = true;
    return;
  }

  const coords = query.match(COORD_RE);
  if (coords) {
    const lat = Number(coords[1]);
    const lng = Number(coords[2]);
    if (Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
      renderSearchResults([{ coords: true, name: 'Ir para coordenadas', displayName: formatCoords(lat, lng), latitude: lat, longitude: lng }]);
      return;
    }
  }

  els.searchResults.innerHTML = '<div class="search-empty">Buscando…</div>';
  els.searchResults.hidden = false;

  const params = new URLSearchParams({ query });
  if (state.map.getZoom() >= 10) {
    const b = state.map.getBounds();
    params.set('viewbox', [b.getWest(), b.getNorth(), b.getEast(), b.getSouth()].map((n) => n.toFixed(5)).join(','));
  }
  const data = await fetchJson(`/api/admin/discovery/search?${params}`);
  if (seq !== state.search.seq) return;
  renderSearchResults(data.results || []);
}

function renderSearchResults(results) {
  state.search.results = results;
  state.search.active = results.length ? 0 : -1;

  if (!results.length) {
    els.searchResults.innerHTML = '<div class="search-empty">Nenhum resultado. Tente incluir a cidade (ex: “UNEMAT Sinop”) ou clique direto no mapa.</div>';
    els.searchResults.hidden = false;
    return;
  }

  els.searchResults.innerHTML = results
    .map((item, index) => {
      const secondary = item.coords
        ? item.displayName
        : item.displayName?.replace(`${item.name}, `, '') || '';
      return `
        <button type="button" class="search-item ${index === 0 ? 'active' : ''}" data-index="${index}">
          <svg><use href="#${item.coords ? 'i-crosshair' : 'i-pin'}"/></svg>
          <div><strong>${escapeHtml(item.name)}</strong><span>${escapeHtml(secondary)}</span></div>
        </button>`;
    })
    .join('');
  els.searchResults.hidden = false;

  els.searchResults.querySelectorAll('.search-item').forEach((button) => {
    button.addEventListener('click', () => selectSearchResult(Number(button.dataset.index)));
  });
}

function onSearchKeydown(event) {
  const { results } = state.search;
  if (event.key === 'Escape') {
    els.searchResults.hidden = true;
    els.searchInput.blur();
    return;
  }
  if (!results.length || els.searchResults.hidden) return;

  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault();
    const delta = event.key === 'ArrowDown' ? 1 : -1;
    state.search.active = (state.search.active + delta + results.length) % results.length;
    els.searchResults.querySelectorAll('.search-item').forEach((el, i) => {
      el.classList.toggle('active', i === state.search.active);
    });
  } else if (event.key === 'Enter') {
    event.preventDefault();
    selectSearchResult(Math.max(state.search.active, 0));
  }
}

function selectSearchResult(index) {
  const item = state.search.results[index];
  if (!item) return;
  els.searchResults.hidden = true;
  els.searchInput.blur();

  const box = item.boundingBox;
  const isArea = box && (Math.abs(box.north - box.south) > 0.02 || Math.abs(box.east - box.west) > 0.02);

  // Cities / neighbourhoods: just navigate the map.
  if (isArea && !state.editor.open) {
    state.map.fitBounds([[box.south, box.west], [box.north, box.east]]);
    return;
  }

  usePlace({
    name: item.coords ? '' : item.name,
    lat: item.latitude,
    lng: item.longitude,
    city: item.city,
  });
}

/* ======================================================================
   Editor
   ====================================================================== */

async function requestOpenEditor(locationId, preset = null) {
  if (state.editor.open && state.editor.dirty) {
    const ok = await confirmDialog({
      title: 'Descartar alterações?',
      message: 'As alterações no local atual não foram salvas.',
      okLabel: 'Descartar',
    });
    if (!ok) return;
  }
  openEditor(locationId, preset);
}

async function requestCloseEditor() {
  if (state.editor.dirty) {
    const ok = await confirmDialog({
      title: 'Descartar alterações?',
      message: 'As alterações não foram salvas.',
      okLabel: 'Descartar',
    });
    if (!ok) return;
  }
  closeEditor();
}

function openEditor(locationId, preset = null) {
  const location = locationId ? state.catalog.locations.find((l) => l.id === locationId) : null;
  const question = location ? questionFor(location.id) : null;
  const editor = state.editor;

  editor.open = true;
  editor.locationId = location?.id || null;
  editor.questionId = question?.id || null;
  editor.point = null;

  els.editorTitle.textContent = location ? 'Editar local' : 'Novo local';
  els.editorDelete.hidden = !location;
  els.locName.value = location?.name || preset?.name || '';
  els.locCity.value = titleCase(location?.city || preset?.city || '');
  els.locActive.checked = location ? location.isActive : true;
  setRadius(location?.radiusMeters || 120, { silent: true });

  els.qEnabled.checked = question ? question.reactiveEnabled : true;
  els.qPrompt.value = question?.prompt || '';
  editor.options = (question?.options?.length ? question.options : PRESETS.yn.map((label) => ({ label })))
    .map((o) => ({ id: o.id || null, label: o.label, originalLabel: o.id ? o.label : null }));
  renderOptions();
  syncQuestionEnabled();

  els.listPanel.hidden = true;
  els.editor.hidden = false;
  els.mapHint.hidden = false;

  renderLocationLayers();
  state.layers.editing.clearLayers();
  editor.marker = null;
  editor.circle = null;
  resetPointCard();

  if (location && isFiniteCoord(location.latitude, location.longitude)) {
    setPoint(location.latitude, location.longitude, { fly: true, keepCity: true });
  } else if (preset && isFiniteCoord(preset.lat, preset.lng)) {
    setPoint(preset.lat, preset.lng, { fly: true, city: preset.city });
  }

  editor.dirty = !location && Boolean(preset);
  historyReset(editor.dirty);
  setTimeout(() => els.locName.focus(), 0);
}

function closeEditor() {
  const editor = state.editor;
  editor.open = false;
  editor.locationId = null;
  editor.questionId = null;
  editor.dirty = false;
  historyReset(false);
  state.layers.editing.clearLayers();
  editor.marker = null;
  editor.circle = null;
  els.editor.hidden = true;
  els.listPanel.hidden = false;
  els.mapHint.hidden = true;
  renderLocationLayers();
}

function resetPointCard() {
  els.pointCard.classList.add('empty');
  els.pointAddress.textContent = 'Clique no mapa ou busque um endereço';
  els.pointCoords.textContent = '';
}

/** Draws the editing marker/circle and coordinates — no geocoding, no history. */
function drawPoint(lat, lng) {
  const editor = state.editor;
  editor.point = { lat, lng };
  const radius = Number(els.locRadius.value);

  if (!editor.marker) {
    editor.circle = L.circle([lat, lng], {
      radius,
      color: COLORS.edit,
      weight: 2,
      dashArray: '6 6',
      fillColor: COLORS.edit,
      fillOpacity: 0.12,
      interactive: false,
    }).addTo(state.layers.editing);

    editor.marker = L.marker([lat, lng], { icon: pinIcon(), draggable: true, autoPan: true })
      .addTo(state.layers.editing);
    editor.marker.on('drag', (event) => editor.circle.setLatLng(event.latlng));
    editor.marker.on('dragend', (event) => {
      const ll = event.target.getLatLng();
      setPoint(ll.lat, ll.lng);
    });
  } else {
    editor.marker.setLatLng([lat, lng]);
    editor.circle.setLatLng([lat, lng]);
  }

  els.pointCard.classList.remove('empty');
  els.pointCoords.textContent = formatCoords(lat, lng);
}

function clearPoint() {
  const editor = state.editor;
  editor.point = null;
  editor.marker = null;
  editor.circle = null;
  state.layers.editing.clearLayers();
  resetPointCard();
}

function setPoint(lat, lng, { fly = false, city = null, keepCity = false } = {}) {
  historyFlush();
  state.editor.dirty = true;
  drawPoint(lat, lng);
  if (city) els.locCity.value = titleCase(city);

  if (fly) {
    const target = Math.max(state.map.getZoom(), 16);
    state.map.flyTo([lat, lng], target, { duration: 0.6 });
  }

  historyCommit();
  safe(reverseGeocode)(lat, lng, { keepCity });
}

async function reverseGeocode(lat, lng, { keepCity = false } = {}) {
  const seq = ++state.editor.reverseSeq;
  els.pointAddress.textContent = 'Identificando endereço…';
  try {
    const data = await fetchJson(`/api/admin/discovery/reverse?latitude=${lat}&longitude=${lng}`);
    if (seq !== state.editor.reverseSeq || !state.editor.open) return;
    els.pointAddress.textContent = data.shortAddress || data.displayName || 'Endereço não identificado';
    els.pointAddress.title = data.displayName || '';
    if (data.city && !(keepCity && els.locCity.value.trim())) els.locCity.value = titleCase(data.city);
    historyAmendAddress();
  } catch (error) {
    if (seq === state.editor.reverseSeq) els.pointAddress.textContent = 'Endereço não identificado';
    throw error;
  }
}

function setRadius(value, { silent = false } = {}) {
  const radius = clamp(Math.round(Number(value) || 120), 20, 2000);
  els.locRadius.value = Math.min(radius, Number(els.locRadius.max));
  els.locRadiusNumber.value = radius;
  state.editor.circle?.setRadius(radius);
  if (!silent) state.editor.dirty = true;
}

/* ----- Question ----- */

function syncQuestionEnabled() {
  els.qFields.classList.toggle('disabled', !els.qEnabled.checked);
  renderPreview();
}

function renderOptions() {
  const { options } = state.editor;
  els.qOptions.innerHTML = '';

  options.forEach((option, index) => {
    const row = document.createElement('div');
    row.className = 'option-row';
    row.innerHTML = `
      <span class="option-index">${index + 1}</span>
      <input type="text" maxlength="${BLE.labelMax}" placeholder="Resposta ${index + 1}" aria-label="Resposta ${index + 1}" />
      <span class="counter"></span>
      <button type="button" class="icon-btn" title="Remover" aria-label="Remover resposta ${index + 1}"><svg><use href="#i-x"/></svg></button>`;

    const input = row.querySelector('input');
    const counter = row.querySelector('.counter');
    const remove = row.querySelector('button');

    input.value = option.label;
    counter.textContent = `${option.label.length}/${BLE.labelMax}`;

    input.addEventListener('input', () => {
      option.label = input.value;
      counter.textContent = `${input.value.length}/${BLE.labelMax}`;
      renderPreview();
    });
    input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        if (index === options.length - 1 && options.length < BLE.maxOptions) {
          addOption('');
          els.qOptions.querySelectorAll('input')[index + 1]?.focus();
        }
      }
    });

    remove.disabled = options.length <= BLE.minOptions;
    remove.addEventListener('click', () => {
      historyFlush();
      options.splice(index, 1);
      state.editor.dirty = true;
      renderOptions();
      historyCommit();
    });

    els.qOptions.appendChild(row);
  });

  els.qAddOption.hidden = options.length >= BLE.maxOptions;
  renderPreview();
}

function addOption(label) {
  if (state.editor.options.length >= BLE.maxOptions) return;
  historyFlush();
  state.editor.options.push({ id: null, label, originalLabel: null });
  state.editor.dirty = true;
  renderOptions();
  historyCommit();
}

function applyPreset(labels) {
  historyFlush();
  const previous = state.editor.options;
  state.editor.options = labels.map((label) => {
    const match = previous.find((o) => o.id && normalize(o.originalLabel) === normalize(label));
    return match
      ? { id: match.id, label, originalLabel: match.originalLabel }
      : { id: null, label, originalLabel: null };
  });
  state.editor.dirty = true;
  renderOptions();
  historyCommit();
}

function renderPreview() {
  const prompt = bleText(els.qPrompt.value);
  const len = prompt.length;
  els.qPromptCount.textContent = `${len}/${BLE.promptMax}`;
  els.qPromptCount.classList.toggle('over', len > BLE.promptMax);
  els.qPromptHint.hidden = len <= BLE.promptMax;

  els.previewPrompt.textContent = prompt
    ? prompt.slice(0, BLE.promptMax)
    : 'Sua pergunta aparece aqui';

  const labels = state.editor.options.map((o) => bleText(o.label).slice(0, BLE.labelMax)).filter(Boolean);
  els.previewOptions.innerHTML = labels.map((label) => `<span>${escapeHtml(label)}</span>`).join('');
}

/** Mirrors sanitizeBleQuestionText: the watch protocol reserves `|` and `:`. */
function bleText(value) {
  return String(value || '').replace(/[|:]/g, ' ').replace(/\s+/g, ' ').trim();
}

/* ----- Undo / redo ----- */

const HISTORY_LIMIT = 100;
const editHistory = {
  stack: [],
  index: -1,
  timer: null,
  restoring: false,
  baseDirty: false, // editor opened already "dirty" (e.g. new location from a search result)
};

const HISTORY_FIELDS = [
  ['name', 'nome'],
  ['city', 'cidade'],
  ['active', 'ativo'],
  ['radius', 'raio'],
  ['point', 'posição'],
  ['qEnabled', 'envio da pergunta'],
  ['prompt', 'pergunta'],
  ['options', 'respostas'],
];

function snapshotEditor() {
  return {
    name: els.locName.value,
    city: els.locCity.value,
    active: els.locActive.checked,
    radius: Number(els.locRadiusNumber.value),
    point: state.editor.point ? { lat: state.editor.point.lat, lng: state.editor.point.lng } : null,
    address: els.pointAddress.textContent,
    addressTitle: els.pointAddress.title,
    qEnabled: els.qEnabled.checked,
    prompt: els.qPrompt.value,
    options: state.editor.options.map((o) => ({ id: o.id, label: o.label, originalLabel: o.originalLabel })),
  };
}

function changedFields(a, b) {
  return HISTORY_FIELDS
    .filter(([key]) => JSON.stringify(a[key]) !== JSON.stringify(b[key]))
    .map(([, label]) => label);
}

function historyReset(baseDirty = false) {
  clearTimeout(editHistory.timer);
  editHistory.timer = null;
  editHistory.baseDirty = baseDirty;
  editHistory.stack = state.editor.open ? [snapshotEditor()] : [];
  editHistory.index = editHistory.stack.length - 1;
  updateHistoryButtons();
}

/** Groups fast typing into a single step. */
function historySchedule() {
  if (editHistory.restoring || !state.editor.open) return;
  clearTimeout(editHistory.timer);
  editHistory.timer = setTimeout(historyCommit, 500);
}

/** Commits pending typing so it becomes its own step before a discrete action. */
function historyFlush() {
  if (editHistory.timer) historyCommit();
}

function historyCommit() {
  clearTimeout(editHistory.timer);
  editHistory.timer = null;
  if (editHistory.restoring || !state.editor.open) return;

  const snap = snapshotEditor();
  const current = editHistory.stack[editHistory.index];
  if (current && !changedFields(current, snap).length) return;

  editHistory.stack = editHistory.stack.slice(0, editHistory.index + 1);
  editHistory.stack.push(snap);
  if (editHistory.stack.length > HISTORY_LIMIT) editHistory.stack.shift();
  editHistory.index = editHistory.stack.length - 1;
  updateHistoryButtons();
}

/** Reverse geocoding finishes later: fold its address/city into the step that moved the point. */
function historyAmendAddress() {
  const current = editHistory.stack[editHistory.index];
  if (!current || editHistory.restoring) return;
  const snap = snapshotEditor();
  if (JSON.stringify(current.point) !== JSON.stringify(snap.point)) return;
  current.address = snap.address;
  current.addressTitle = snap.addressTitle;
  current.city = snap.city;
}

function undoEdit() {
  historyFlush();
  if (editHistory.index <= 0) return;
  moveHistory(-1, 'Desfeito');
}

function redoEdit() {
  historyFlush();
  if (editHistory.index >= editHistory.stack.length - 1) return;
  moveHistory(1, 'Refeito');
}

function moveHistory(delta, verb) {
  const from = editHistory.stack[editHistory.index];
  editHistory.index += delta;
  const to = editHistory.stack[editHistory.index];
  applySnapshot(to, from);

  state.editor.dirty = editHistory.baseDirty || editHistory.index > 0;
  updateHistoryButtons();

  const fields = changedFields(from, to);
  toast(fields.length ? `${verb}: ${fields.slice(0, 2).join(', ')}` : verb, 'info', { key: 'history', duration: 1500 });
}

function applySnapshot(snap, previous) {
  editHistory.restoring = true;
  try {
    // Keep focus on the same option row when its inputs are re-rendered.
    const active = document.activeElement;
    const optionIndex = els.qOptions.contains(active)
      ? [...els.qOptions.querySelectorAll('input')].indexOf(active)
      : -1;

    els.locName.value = snap.name;
    els.locCity.value = snap.city;
    els.locActive.checked = snap.active;
    setRadius(snap.radius, { silent: true });
    els.qEnabled.checked = snap.qEnabled;
    els.qPrompt.value = snap.prompt;
    state.editor.options = snap.options.map((o) => ({ ...o }));
    renderOptions();
    syncQuestionEnabled();

    state.editor.reverseSeq += 1; // drop any in-flight geocoding result
    if (snap.point) {
      drawPoint(snap.point.lat, snap.point.lng);
      els.pointAddress.textContent = snap.address;
      els.pointAddress.title = snap.addressTitle || '';
      const moved = JSON.stringify(snap.point) !== JSON.stringify(previous?.point);
      const ll = L.latLng(snap.point.lat, snap.point.lng);
      if (moved && !state.map.getBounds().contains(ll)) state.map.panTo(ll);
    } else {
      clearPoint();
    }

    if (optionIndex >= 0) els.qOptions.querySelectorAll('input')[optionIndex]?.focus();
  } finally {
    editHistory.restoring = false;
  }
}

function updateHistoryButtons() {
  els.editorUndo.disabled = editHistory.index <= 0;
  els.editorRedo.disabled = editHistory.index < 0 || editHistory.index >= editHistory.stack.length - 1;
}

/* ----- Save / delete ----- */

async function saveEditor() {
  const editor = state.editor;
  if (!editor.open || els.editorSave.disabled) return;

  const name = els.locName.value.trim();
  if (!name) {
    els.locName.focus();
    toast('Informe o nome do local.', 'error');
    return;
  }
  if (!editor.point) {
    toast('Defina a posição: clique no mapa ou busque um endereço.', 'error');
    return;
  }

  const prompt = els.qPrompt.value.trim();
  const options = editor.options
    .map((o) => ({ label: o.label.trim(), id: o.id, originalLabel: o.originalLabel }))
    .filter((o) => o.label)
    // Keep the stored id only if the label meaning didn't change, so old answers still match.
    .map((o) => (o.id && normalize(o.label) === normalize(o.originalLabel) ? { id: o.id, label: o.label } : { label: o.label }));

  const wantsQuestion = els.qEnabled.checked && (prompt || editor.questionId);
  if (wantsQuestion) {
    if (!prompt) {
      els.qPrompt.focus();
      toast('Escreva a pergunta ou desative o envio.', 'error');
      return;
    }
    if (options.length < BLE.minOptions) {
      toast(`A pergunta precisa de pelo menos ${BLE.minOptions} respostas.`, 'error');
      return;
    }
    const labels = options.map((o) => normalize(o.label));
    if (new Set(labels).size !== labels.length) {
      toast('Há respostas repetidas.', 'error');
      return;
    }
  }

  els.editorSave.disabled = true;
  els.editorSave.textContent = 'Salvando…';

  try {
    const locationPayload = {
      name,
      city: els.locCity.value.trim(),
      latitude: Number(editor.point.lat.toFixed(6)),
      longitude: Number(editor.point.lng.toFixed(6)),
      radiusMeters: Number(els.locRadiusNumber.value),
      isActive: els.locActive.checked,
    };

    const { location } = await fetchJson(
      editor.locationId ? `/api/admin/locations/${editor.locationId}` : '/api/admin/locations',
      { method: editor.locationId ? 'PUT' : 'POST', body: locationPayload },
    );

    if (wantsQuestion) {
      await fetchJson(
        editor.questionId ? `/api/admin/questions/${editor.questionId}` : '/api/admin/questions',
        {
          method: editor.questionId ? 'PUT' : 'POST',
          body: {
            prompt,
            city: location.city,
            locationId: location.id,
            reactiveEnabled: true,
            options,
          },
        },
      );
    } else if (editor.questionId) {
      await fetchJson(`/api/admin/questions/${editor.questionId}`, {
        method: 'PUT',
        body: { reactiveEnabled: false, city: location.city },
      });
    }

    editor.dirty = false;
    closeEditor();
    await loadCatalog();
    toast(`“${location.name}” salvo.`);
  } finally {
    els.editorSave.disabled = false;
    els.editorSave.textContent = 'Salvar';
  }
}

async function deleteCurrentLocation() {
  const { locationId } = state.editor;
  const location = state.catalog.locations.find((l) => l.id === locationId);
  if (!location) return;

  const ok = await confirmDialog({
    title: 'Excluir local?',
    message: `“${location.name}” e a pergunta vinculada serão removidos. Respostas já recebidas continuam no histórico.`,
    okLabel: 'Excluir',
  });
  if (!ok) return;

  await fetchJson(`/api/admin/locations/${locationId}`, { method: 'DELETE' });
  state.editor.dirty = false;
  closeEditor();
  await loadCatalog();
  toast(`“${location.name}” excluído.`);
}

/* ======================================================================
   Dashboard
   ====================================================================== */

async function loadDashboard() {
  const data = await fetchJson('/api/admin/dashboard');
  state.dashboard.data = data;
  renderKpis(data.summary);
  renderCharts(data);
  renderResponsesTable();
  renderTopCities(data.topCities || []);
  renderDevices(data.recentDevices || []);
  els.dashboardUpdated.textContent = `atualizado ${new Date().toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`;
}

function renderKpis(summary) {
  const kpis = [
    ['Respostas', summary.totalResponses],
    ['Hoje', summary.responsesToday],
    ['Pendentes', summary.pendingResponses, summary.pendingResponses > 0 ? 'warning' : ''],
    ['Falhas', summary.failedResponses, summary.failedResponses > 0 ? 'danger' : ''],
    ['Locais', summary.locationsCount],
    ['Dispositivos', summary.devicesCount],
  ];
  els.statsGrid.innerHTML = kpis
    .map(([label, value, tone]) => `
      <div class="kpi ${tone || ''}"><span>${label}</span><strong>${formatNumber(value)}</strong></div>`)
    .join('');
}

function renderCharts(data) {
  const { charts } = state.dashboard;
  if (typeof Chart === 'undefined') return;

  Chart.defaults.font.family = getComputedStyle(document.body).fontFamily;
  Chart.defaults.color = '#6b7280';

  // Fill missing days so the timeline is continuous.
  const byDay = new Map((data.volumeByDay || []).map((d) => [d.day, d.total]));
  const days = [];
  for (let i = 9; i >= 0; i -= 1) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    const key = d.toISOString().slice(0, 10);
    days.push({ key, label: d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }), total: byDay.get(key) || 0 });
  }

  charts.line?.destroy();
  charts.line = new Chart($('responses-line-chart'), {
    type: 'bar',
    data: {
      labels: days.map((d) => d.label),
      datasets: [{
        label: 'Respostas',
        data: days.map((d) => d.total),
        backgroundColor: COLORS.accent,
        borderRadius: 4,
        maxBarThickness: 28,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      plugins: { legend: { display: false } },
      scales: {
        x: { grid: { display: false } },
        y: { beginAtZero: true, ticks: { precision: 0 }, grid: { color: '#eef0f3' }, border: { display: false } },
      },
    },
  });

  const entries = Object.entries(data.responseStatusCounts || {});
  charts.status?.destroy();
  charts.status = new Chart($('responses-status-chart'), {
    type: 'doughnut',
    data: {
      labels: entries.map(([key]) => STATUS_LABELS[key] || key),
      datasets: [{
        data: entries.map(([, value]) => value),
        backgroundColor: entries.map(([key]) => COLORS.status[key] || '#9ca3af'),
        borderWidth: 2,
        borderColor: '#fff',
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      cutout: '68%',
      plugins: { legend: { position: 'bottom', labels: { boxWidth: 10, boxHeight: 10, usePointStyle: true } } },
    },
  });
}

function renderResponsesTable() {
  const rows = state.dashboard.data?.recentResponses || [];
  const term = normalize(els.responsesFilter.value);
  const filtered = term
    ? rows.filter((r) => normalize([r.locationName, r.questionPrompt, r.answerText, r.answerId, r.city, r.deviceName, r.deviceId].join(' ')).includes(term))
    : rows;

  if (!filtered.length) {
    els.responsesTable.innerHTML = `<tr><td colspan="6" class="empty">${rows.length ? 'Nada corresponde ao filtro.' : 'Nenhuma resposta recebida ainda.'}</td></tr>`;
    return;
  }

  els.responsesTable.innerHTML = filtered
    .map((row) => `
      <tr>
        <td class="nowrap" title="${escapeHtml(formatDate(row.receivedAt))}">${escapeHtml(relativeTime(row.receivedAt))}</td>
        <td>${escapeHtml(row.locationName || '—')}<span class="cell-sub">${escapeHtml(row.city || '')}</span></td>
        <td>${escapeHtml(row.questionPrompt || '—')}</td>
        <td class="answer">${escapeHtml(row.answerText || row.answerId || '—')}</td>
        <td>${escapeHtml(row.deviceName || shortId(row.deviceId))}</td>
        <td><span class="badge ${statusTone(row.status)}" ${row.errorMessage ? `title="${escapeHtml(row.errorMessage)}"` : ''}>${escapeHtml(STATUS_LABELS[row.status] || row.status)}</span></td>
      </tr>`)
    .join('');
}

function renderTopCities(cities) {
  if (!cities.length) {
    els.topCities.innerHTML = '<div class="placeholder">Sem dados ainda.</div>';
    return;
  }
  const max = Math.max(...cities.map((c) => c.total));
  els.topCities.innerHTML = cities
    .map((c) => `
      <div class="bar-row">
        <span class="bar-label">${escapeHtml(c.city)}</span>
        <div class="bar-track"><span style="width:${(c.total / max) * 100}%"></span></div>
        <span class="bar-value">${formatNumber(c.total)}</span>
      </div>`)
    .join('');
}

function renderDevices(devices) {
  if (!devices.length) {
    els.recentDevices.innerHTML = '<div class="placeholder">Nenhum dispositivo registrado.</div>';
    return;
  }
  const now = Date.now();
  els.recentDevices.innerHTML = devices
    .map((device) => {
      const seen = device.lastSeenAt || device.createdAt;
      const online = seen && now - new Date(seen).getTime() < 15 * 60 * 1000;
      return `
        <div class="device-row">
          <span class="dot ${online ? 'on' : ''}" title="${online ? 'Ativo nos últimos 15 min' : 'Inativo'}"></span>
          <div>
            <strong>${escapeHtml(device.name || shortId(device.id))}</strong>
            <span class="sub">${escapeHtml(device.lastCity || 'cidade desconhecida')}</span>
          </div>
          <span class="muted" title="${escapeHtml(formatDate(seen))}">${escapeHtml(relativeTime(seen))}</span>
        </div>`;
    })
    .join('');
}

/* ======================================================================
   UI helpers
   ====================================================================== */

const keyedToasts = new Map();

/** `key` reuses one toast instead of stacking (e.g. repeated Ctrl+Z). */
function toast(message, type = 'info', { key = null, duration = null } = {}) {
  let el = key ? keyedToasts.get(key) : null;
  if (el) {
    clearTimeout(el._timer);
    el.classList.remove('leaving');
  } else {
    el = document.createElement('div');
    els.toasts.appendChild(el);
    if (key) keyedToasts.set(key, el);
  }
  el.className = `toast ${type}`;
  el.textContent = message;
  el._timer = setTimeout(() => {
    el.classList.add('leaving');
    setTimeout(() => {
      el.remove();
      if (key && keyedToasts.get(key) === el) keyedToasts.delete(key);
    }, 220);
  }, duration ?? (type === 'error' ? 5000 : 3000));
}

function confirmDialog({ title, message, okLabel = 'Confirmar' }) {
  const dialog = els.confirmDialog;
  $('confirm-title').textContent = title;
  $('confirm-message').textContent = message;
  $('confirm-ok').textContent = okLabel;
  dialog.returnValue = '';
  dialog.showModal();
  return new Promise((resolve) => {
    dialog.addEventListener('close', () => resolve(dialog.returnValue === 'ok'), { once: true });
  });
}

/** Wraps an async handler so failures surface as a toast instead of being lost. */
function safe(fn) {
  return (...args) =>
    Promise.resolve()
      .then(() => fn(...args))
      .catch((error) => {
        if (error?.message === 'unauthorized') return;
        console.error(error);
        toast(translateError(error?.message), 'error');
      });
}

function translateError(message) {
  const known = {
    'external map service failed': 'Serviço de mapas indisponível. Tente novamente.',
    'a question needs between 2 and 4 options': 'A pergunta precisa de 2 a 4 respostas.',
    'name is required': 'Informe o nome do local.',
    'prompt is required': 'Escreva a pergunta.',
    'location not found': 'Local não encontrado (talvez já excluído).',
    'question not found': 'Pergunta não encontrada.',
    'Failed to fetch': 'Sem conexão com o servidor.',
  };
  return known[message] || message || 'Erro inesperado.';
}

async function fetchJson(url, { body, headers, ...options } = {}) {
  const response = await fetch(url, {
    credentials: 'same-origin',
    ...options,
    headers: body ? { 'Content-Type': 'application/json', ...headers } : headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  let data = {};
  try {
    data = await response.json();
  } catch (_) {
    data = {};
  }

  if (response.status === 401) {
    window.location.href = '/admin/login';
    throw new Error('unauthorized');
  }
  if (!response.ok) {
    throw new Error(data.error || `Erro ${response.status}`);
  }
  return data;
}

function debounce(fn, wait) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), wait);
  };
}

/* ======================================================================
   Formatting
   ====================================================================== */

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function normalize(value) {
  return String(value || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
}

function titleCase(value) {
  return String(value || '').replace(/(^|\s)(\p{L})/gu, (m, s, c) => s + c.toUpperCase());
}

function categoryLabel(category) {
  return CATEGORY_LABELS[category] || String(category || 'Local').replace(/_/g, ' ');
}

function statusTone(status) {
  if (status === 'processed' || status === 'done') return 'success';
  if (status === 'pending' || status === 'processing') return 'warning';
  if (status === 'failed') return 'danger';
  return '';
}

function isFiniteCoord(lat, lng) {
  return Number.isFinite(Number(lat)) && Number.isFinite(Number(lng)) && lat !== null && lng !== null;
}

function formatCoords(lat, lng) {
  return `${Number(lat).toFixed(6)}, ${Number(lng).toFixed(6)}`;
}

function formatNumber(value) {
  return Number(value || 0).toLocaleString('pt-BR');
}

function formatDate(value) {
  if (!value) return '';
  return new Date(value).toLocaleString('pt-BR');
}

function relativeTime(value) {
  if (!value) return '—';
  const diff = (Date.now() - new Date(value).getTime()) / 1000;
  if (diff < 60) return 'agora';
  if (diff < 3600) return `há ${Math.floor(diff / 60)} min`;
  if (diff < 86400) return `há ${Math.floor(diff / 3600)} h`;
  if (diff < 7 * 86400) return `há ${Math.floor(diff / 86400)} d`;
  return new Date(value).toLocaleDateString('pt-BR');
}

function shortId(id) {
  const value = String(id || '');
  return value.length > 14 ? `${value.slice(0, 12)}…` : value || '—';
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}
