const state = {
  session: null,
  map: null,
  mapLayers: {
    search: null,
    publicPlaces: null,
    savedLocations: null,
    selected: null,
  },
  charts: {
    line: null,
    status: null,
  },
  currentView: window.location.pathname.includes('/dashboard')
    ? 'dashboard'
    : 'config',
  catalog: {
    locations: [],
    questions: [],
  },
  selectedCity: null,
  selectedLocationId: null,
};

const els = {
  sessionEmail: document.getElementById('session-email'),
  logoutButton: document.getElementById('logout-button'),
  refreshButton: document.getElementById('refresh-button'),
  pageTitle: document.getElementById('page-title'),
  configView: document.getElementById('config-view'),
  dashboardView: document.getElementById('dashboard-view'),
  cityQuery: document.getElementById('city-query'),
  citySearchButton: document.getElementById('city-search-button'),
  cityResults: document.getElementById('city-results'),
  publicPlacesButton: document.getElementById('public-places-button'),
  placesResults: document.getElementById('places-results'),
  reloadCatalogButton: document.getElementById('reload-catalog-button'),
  validationPill: document.getElementById('validation-pill'),
  validationMessage: document.getElementById('validation-message'),
  locationForm: document.getElementById('location-form'),
  locationId: document.getElementById('location-id'),
  locationName: document.getElementById('location-name'),
  locationCity: document.getElementById('location-city'),
  locationLatitude: document.getElementById('location-latitude'),
  locationLongitude: document.getElementById('location-longitude'),
  locationRadius: document.getElementById('location-radius'),
  locationRules: document.getElementById('location-rules'),
  validateLocationButton: document.getElementById('validate-location-button'),
  savedLocations: document.getElementById('saved-locations'),
  questionForm: document.getElementById('question-form'),
  questionId: document.getElementById('question-id'),
  questionPrompt: document.getElementById('question-prompt'),
  questionOptionsContainer: document.getElementById('question-options-container'),
  addOptionBtn: document.getElementById('add-option-btn'),
  questionReactiveEnabled: document.getElementById('question-reactive-enabled'),
  clearQuestionButton: document.getElementById('clear-question-button'),
  statsGrid: document.getElementById('stats-grid'),
  topCities: document.getElementById('top-cities'),
  recentDevices: document.getElementById('recent-devices'),
  responsesTable: document.getElementById('responses-table'),
};

init().catch((error) => {
  console.error(error);
  alert('Falha ao iniciar o painel administrativo.');
});

async function init() {
  await loadSession();
  activateNav();
  initMap();
  bindEvents();
  if (els.questionOptionsContainer) {
    clearQuestionForm();
  }
  await refreshCurrentView();
}

function activateNav() {
  document.querySelectorAll('[data-nav]').forEach((link) => {
    const view = link.dataset.nav;
    link.classList.toggle('active', view === state.currentView);
  });

  els.pageTitle.textContent =
    state.currentView === 'dashboard'
      ? 'Dashboard de Respostas'
      : 'Configuração de Locais';
  els.configView.classList.toggle('hidden', state.currentView !== 'config');
  els.dashboardView.classList.toggle('hidden', state.currentView !== 'dashboard');
}

function bindEvents() {
  els.logoutButton?.addEventListener('click', logout);
  els.refreshButton?.addEventListener('click', refreshCurrentView);
  els.citySearchButton?.addEventListener('click', searchCities);
  els.publicPlacesButton?.addEventListener('click', searchPublicPlaces);
  els.reloadCatalogButton?.addEventListener('click', loadCatalog);
  els.validateLocationButton?.addEventListener('click', validateCurrentLocation);
  els.locationForm?.addEventListener('submit', saveLocation);
  els.questionForm?.addEventListener('submit', saveLinkedQuestion);
  els.clearQuestionButton?.addEventListener('click', clearQuestionForm);
  els.addOptionBtn?.addEventListener('click', () => appendQuestionOptionRow());
}

function appendQuestionOptionRow(id = '', label = '') {
  const container = els.questionOptionsContainer;
  const count = container.children.length;
  if (count >= 4) {
    alert('O máximo é de 4 opções por pergunta.');
    return;
  }
  const index = count + 1;
  const row = document.createElement('div');
  row.className = 'field-grid';
  row.innerHTML = `
    <label class="field">
      <span>ID da opção ${index}</span>
      <input type="text" class="opt-id" value="${escapeHtml(id)}" required />
    </label>
    <label class="field" style="position: relative;">
      <span>Rótulo da opção ${index}</span>
      <div style="display:flex; gap: 8px;">
        <input type="text" class="opt-label" value="${escapeHtml(label)}" required style="flex:1;" />
        <button type="button" class="ghost-btn compact remove-opt-btn" title="Remover" style="padding: 0 12px; min-width: 44px;">&times;</button>
      </div>
    </label>
  `;
  const removeBtn = row.querySelector('.remove-opt-btn');
  removeBtn.addEventListener('click', () => {
    row.remove();
    reindexOptions();
  });
  container.appendChild(row);
  updateAddOptionBtn();
}

function reindexOptions() {
  const rows = els.questionOptionsContainer.children;
  Array.from(rows).forEach((row, idx) => {
    const num = idx + 1;
    row.querySelectorAll('span')[0].textContent = `ID da opção ${num}`;
    row.querySelectorAll('span')[1].textContent = `Rótulo da opção ${num}`;
  });
  updateAddOptionBtn();
}

function updateAddOptionBtn() {
  const count = els.questionOptionsContainer.children.length;
  els.addOptionBtn.style.display = count >= 4 ? 'none' : 'block';
}

async function loadSession() {
  const data = await fetchJson('/api/admin/auth/session');
  state.session = data.admin;
  if (els.sessionEmail) {
    els.sessionEmail.textContent = data.admin.email;
  }
}

async function logout() {
  await fetchJson('/api/admin/auth/logout', { method: 'POST' });
  window.location.href = '/admin/login';
}

async function refreshCurrentView() {
  if (state.currentView === 'dashboard') {
    await loadDashboard();
    return;
  }

  await loadCatalog();
}

function initMap() {
  const mapEl = document.getElementById('admin-map');
  if (!mapEl || state.map) return;

  state.map = L.map(mapEl, {
    center: [-14.235, -51.9253],
    zoom: 4,
  });

  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap contributors',
  }).addTo(state.map);

  state.mapLayers.search = L.layerGroup().addTo(state.map);
  state.mapLayers.publicPlaces = L.layerGroup().addTo(state.map);
  state.mapLayers.savedLocations = L.layerGroup().addTo(state.map);
  state.mapLayers.selected = L.layerGroup().addTo(state.map);

  state.map.on('click', (event) => {
    setSelectedCoordinates(event.latlng.lat, event.latlng.lng, true);
  });
}

async function loadCatalog() {
  const data = await fetchJson('/api/admin/catalog');
  state.catalog = data;
  renderSavedLocations();
  renderSavedLocationMarkers();
}

function renderSavedLocations() {
  if (!els.savedLocations) return;
  if (!state.catalog.locations.length) {
    els.savedLocations.innerHTML = '<p class="muted">Nenhum local salvo ainda.</p>';
    return;
  }

  els.savedLocations.innerHTML = state.catalog.locations
    .map((location) => {
      const linkedQuestion = state.catalog.questions.find(
        (question) => question.locationId === location.id,
      );

      return `
      <article class="location-card" >
          <strong>${escapeHtml(location.name)}</strong>
          <p>${escapeHtml(location.city || 'cidade nao definida')} • ${location.latitude}, ${location.longitude}</p>
          <p>Raio: ${location.radiusMeters} m</p>
          <p>${linkedQuestion ? `Pergunta: ${escapeHtml(linkedQuestion.prompt)}` : 'Sem pergunta vinculada'}</p>
          <div class="item-actions">
            <button class="ghost-btn compact" data-action="edit-location" data-id="${location.id}">Editar</button>
            <button class="ghost-btn compact" data-action="delete-location" data-id="${location.id}">Excluir</button>
          </div>
        </article>
      `;
    })
    .join('');

  els.savedLocations.querySelectorAll('[data-action="edit-location"]').forEach((button) => {
    button.addEventListener('click', () => populateLocation(button.dataset.id));
  });

  els.savedLocations
    .querySelectorAll('[data-action="delete-location"]')
    .forEach((button) => {
      button.addEventListener('click', async () => {
        if (!confirm('Excluir este local?')) return;
        await fetchJson(`/api/admin/locations/${button.dataset.id}`, {
          method: 'DELETE',
        });
        await loadCatalog();
      });
    });
}

function renderSavedLocationMarkers() {
  const layer = state.mapLayers.savedLocations;
  layer.clearLayers();

  state.catalog.locations.forEach((location) => {
    if (!Number.isFinite(Number(location.latitude)) || !Number.isFinite(Number(location.longitude))) {
      return;
    }

    const marker = L.circle([location.latitude, location.longitude], {
      radius: Number(location.radiusMeters || 100),
      color: '#0f8c8c',
      fillColor: '#0f8c8c',
      fillOpacity: 0.16,
    }).bindPopup(`<strong> ${escapeHtml(location.name)}</strong> <br />${escapeHtml(location.city || '')} `);

    marker.addTo(layer);
  });
}

async function searchCities() {
  const query = els.cityQuery.value.trim();
  if (!query) return;

  const data = await fetchJson(`/api/admin/discovery/cities?query=${encodeURIComponent(query)}`);
  if (!data.results.length) {
    els.cityResults.innerHTML = '<p class="muted">Nenhuma cidade encontrada.</p>';
    return;
  }

  els.cityResults.innerHTML = data.results
    .map(
      (item, index) => `
      <article class="result-item" >
          <strong>${escapeHtml(item.city || item.name)}</strong>
          <p class="item-meta">${escapeHtml(item.displayName)}</p>
          <div class="item-actions">
            <button class="primary-btn compact" data-city-index="${index}">Selecionar</button>
          </div>
        </article>
      `,
    )
    .join('');

  els.cityResults.querySelectorAll('[data-city-index]').forEach((button) => {
    button.addEventListener('click', () => {
      const item = data.results[Number(button.dataset.cityIndex)];
      selectCity(item);
    });
  });
}

function selectCity(city) {
  state.selectedCity = city;
  els.locationCity.value = city.city || city.name || '';
  els.cityQuery.value = city.city || city.name || '';

  state.mapLayers.search.clearLayers();
  const marker = L.marker([city.latitude, city.longitude]).bindPopup(
    `<strong> ${escapeHtml(city.city || city.name)}</strong> <br />${escapeHtml(city.state || '')} `,
  );
  marker.addTo(state.mapLayers.search).openPopup();

  if (city.boundingBox) {
    const bounds = [
      [city.boundingBox.south, city.boundingBox.west],
      [city.boundingBox.north, city.boundingBox.east],
    ];
    L.rectangle(bounds, {
      color: '#176f99',
      weight: 1,
      fillOpacity: 0.05,
    }).addTo(state.mapLayers.search);
    state.map.fitBounds(bounds, { padding: [24, 24] });
  } else {
    state.map.setView([city.latitude, city.longitude], 12);
  }
}

async function searchPublicPlaces() {
  if (!state.selectedCity?.boundingBox && !els.locationCity.value.trim()) {
    alert('Selecione ou busque uma cidade antes.');
    return;
  }

  const params = new URLSearchParams();
  if (state.selectedCity?.boundingBox) {
    params.set('city', state.selectedCity.city || state.selectedCity.name || '');
    params.set('south', state.selectedCity.boundingBox.south);
    params.set('north', state.selectedCity.boundingBox.north);
    params.set('west', state.selectedCity.boundingBox.west);
    params.set('east', state.selectedCity.boundingBox.east);
  } else {
    params.set('city', els.locationCity.value.trim());
  }

  const data = await fetchJson(`/api/admin/discovery/public-places?${params.toString()}`);
  renderPublicPlaces(data.results || []);
}

function renderPublicPlaces(places) {
  state.mapLayers.publicPlaces.clearLayers();

  if (!places.length) {
    els.placesResults.innerHTML = '<p class="muted">Nenhum local publico encontrado para a area pesquisada.</p>';
    return;
  }

  els.placesResults.innerHTML = places
    .map(
      (place, index) => `
      <article class="result-item" >
          <strong>${escapeHtml(place.name)}</strong>
          <p class="item-meta">${escapeHtml(place.category)}</p>
          <div class="item-actions">
            <button class="ghost-btn compact" data-place-index="${index}">Usar este ponto</button>
          </div>
        </article>
      `,
    )
    .join('');

  places.forEach((place) => {
    const marker = L.marker([place.latitude, place.longitude]).bindPopup(
      `<strong> ${escapeHtml(place.name)}</strong> <br />${escapeHtml(place.category)} `,
    );
    marker.addTo(state.mapLayers.publicPlaces);
  });

  els.placesResults.querySelectorAll('[data-place-index]').forEach((button) => {
    button.addEventListener('click', () => {
      const place = places[Number(button.dataset.placeIndex)];
      els.locationName.value = place.name;
      els.locationCity.value = place.city || els.locationCity.value;
      setSelectedCoordinates(place.latitude, place.longitude, true);
    });
  });
}

function setSelectedCoordinates(latitude, longitude, centerMap = false) {
  els.locationLatitude.value = Number(latitude).toFixed(6);
  els.locationLongitude.value = Number(longitude).toFixed(6);

  state.mapLayers.selected.clearLayers();
  const circle = L.circleMarker([latitude, longitude], {
    radius: 10,
    color: '#c95b4d',
    fillColor: '#c95b4d',
    fillOpacity: 0.85,
  }).bindPopup('Ponto selecionado');
  circle.addTo(state.mapLayers.selected).openPopup();

  if (centerMap) {
    state.map.setView([latitude, longitude], 16);
  }
}

function parseRulesInput(value) {
  return String(value || '')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line, index) => {
      const [ruleType, ruleValue, priority] = line.split('|').map((item) => item?.trim());
      return {
        ruleType: ruleType || 'notify',
        ruleValue: ruleValue || line,
        priority: Number(priority || index + 1),
      };
    });
}

async function validateCurrentLocation() {
  const city = els.locationCity.value.trim();
  const latitude = els.locationLatitude.value.trim();
  const longitude = els.locationLongitude.value.trim();

  const result = await fetchJson('/api/admin/discovery/validate-location', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ city, latitude, longitude }),
  });

  els.validationPill.className = `status - pill ${result.valid ? 'success' : 'warning'} `;
  els.validationPill.textContent = result.valid
    ? 'Local validado'
    : 'Cidade divergente';
  els.validationMessage.textContent = result.displayName
    ? `Endereço detectado: ${result.displayName} `
    : 'Nenhuma referencia encontrada.';
}

async function saveLocation(event) {
  event.preventDefault();

  const payload = {
    name: els.locationName.value.trim(),
    city: els.locationCity.value.trim(),
    latitude: Number(els.locationLatitude.value),
    longitude: Number(els.locationLongitude.value),
    radiusMeters: Number(els.locationRadius.value || 120),
    rules: parseRulesInput(els.locationRules.value),
  };

  if (!payload.name || !payload.city || !Number.isFinite(payload.latitude) || !Number.isFinite(payload.longitude)) {
    alert('Preencha nome, cidade e coordenadas validas.');
    return;
  }

  const locationId = els.locationId.value.trim();
  const url = locationId ? `/api/admin/locations/${locationId}` : '/api/admin/locations';
  const method = locationId ? 'PUT' : 'POST';
  const data = await fetchJson(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  els.locationId.value = data.location.id;
  state.selectedLocationId = data.location.id;
  await loadCatalog();
  populateLocation(data.location.id);
  alert('Local salvo com sucesso.');
}

async function saveLinkedQuestion(event) {
  event.preventDefault();
  const locationId = els.locationId.value.trim();
  if (!locationId) {
    alert('Salve ou selecione um local antes de vincular a pergunta.');
    return;
  }

  const location = state.catalog.locations.find((item) => item.id === locationId);
  if (!location) {
    alert('Local selecionado nao encontrado.');
    return;
  }

  const prompt = els.questionPrompt.value.trim();
  if (!prompt) {
    alert('Preencha a pergunta.');
    return;
  }

  const options = [];
  els.questionOptionsContainer.querySelectorAll('.field-grid').forEach((row) => {
    const id = row.querySelector('.opt-id').value.trim();
    const label = row.querySelector('.opt-label').value.trim();
    if (id && label) {
      options.push({ id, label });
    }
  });

  if (options.length === 0) {
    alert('Adicione pelo menos uma opção.');
    return;
  }

  const payload = {
    prompt,
    city: location.city,
    locationId,
    reactiveEnabled: els.questionReactiveEnabled.checked,
    options,
  };

  const questionId = els.questionId.value.trim();
  const url = questionId ? `/api/admin/questions/${questionId}` : '/api/admin/questions';
  const method = questionId ? 'PUT' : 'POST';
  const data = await fetchJson(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  els.questionId.value = data.question.id;
  await loadCatalog();
  alert('Pergunta vinculada salva.');
}

function populateLocation(locationId) {
  const location = state.catalog.locations.find((item) => item.id === locationId);
  if (!location) return;

  state.selectedLocationId = location.id;
  els.locationId.value = location.id;
  els.locationName.value = location.name || '';
  els.locationCity.value = location.city || '';
  els.locationLatitude.value = location.latitude;
  els.locationLongitude.value = location.longitude;
  els.locationRadius.value = location.radiusMeters || 120;
  els.locationRules.value = (location.rules || [])
    .map((rule) => `${rule.ruleType}| ${rule.ruleValue}| ${rule.priority} `)
    .join('\n');
  setSelectedCoordinates(location.latitude, location.longitude, true);

  const linkedQuestion = state.catalog.questions.find(
    (question) => question.locationId === location.id,
  );

  if (linkedQuestion) {
    els.questionId.value = linkedQuestion.id;
    els.questionPrompt.value = linkedQuestion.prompt || '';
    els.questionReactiveEnabled.checked = linkedQuestion.reactiveEnabled !== false;

    if (els.questionOptionsContainer) {
      els.questionOptionsContainer.innerHTML = '';
      const opts = linkedQuestion.options || [];
      if (opts.length === 0) {
        appendQuestionOptionRow('SIM', 'Sim');
        appendQuestionOptionRow('NAO', 'Nao');
      } else {
        opts.forEach(opt => appendQuestionOptionRow(opt.id, opt.label));
      }
    }
  } else {
    clearQuestionForm();
  }
}

function clearQuestionForm() {
  if (els.questionId) els.questionId.value = '';
  if (els.questionPrompt) els.questionPrompt.value = '';
  if (els.questionReactiveEnabled) els.questionReactiveEnabled.checked = true;

  if (els.questionOptionsContainer) {
    els.questionOptionsContainer.innerHTML = '';
    appendQuestionOptionRow('SIM', 'Sim');
    appendQuestionOptionRow('NAO', 'Nao');
  }
}

async function loadDashboard() {
  const data = await fetchJson('/api/admin/dashboard');
  renderStats(data.summary);
  renderRecentDevices(data.recentDevices || []);
  renderResponsesTable(data.recentResponses || []);
  renderTopCities(data.topCities || []);
  renderCharts(data);
}

function renderStats(summary) {
  els.statsGrid.innerHTML = [
    ['Dispositivos', summary.devicesCount],
    ['Locais', summary.locationsCount],
    ['Perguntas', summary.questionsCount],
    ['Respostas', summary.totalResponses],
    ['Pendentes', summary.pendingResponses],
    ['Hoje', summary.responsesToday],
  ]
    .map(
      ([label, value]) => `
      <article class="stat-card" >
          <span>${label}</span>
          <strong>${value}</strong>
        </article>
      `,
    )
    .join('');
}

function renderRecentDevices(devices) {
  if (!devices.length) {
    els.recentDevices.innerHTML = '<p class="muted">Nenhum dispositivo registrado.</p>';
    return;
  }

  els.recentDevices.innerHTML = devices
    .map(
      (device) => `
      <article class="device-item" >
          <strong>${escapeHtml(device.name || device.id)}</strong>
          <p>${escapeHtml(device.lastCity || 'sem cidade')} • status ${escapeHtml(device.status || 'n/a')}</p>
          <p>Último contato: ${formatDate(device.lastSeenAt || device.createdAt)}</p>
        </article>
      `,
    )
    .join('');
}

function renderResponsesTable(rows) {
  if (!rows.length) {
    els.responsesTable.innerHTML =
      '<tr><td colspan="6" class="muted">Nenhuma resposta recebida ainda.</td></tr>';
    return;
  }

  els.responsesTable.innerHTML = rows
    .map(
      (row) => `
      <tr>
          <td>${formatDate(row.receivedAt)}</td>
          <td>${escapeHtml(row.deviceName || row.deviceId)}</td>
          <td>${escapeHtml(row.questionPrompt || row.questionId || '-')}</td>
          <td>${escapeHtml(row.answerText || row.answerId || '-')}</td>
          <td>${escapeHtml(row.city || '-')}</td>
          <td><span class="status-pill ${statusClass(row.status)}">${escapeHtml(row.status)}</span></td>
        </tr >
      `,
    )
    .join('');
}

function renderTopCities(cities) {
  if (!cities.length) {
    els.topCities.innerHTML = '<p class="muted">Ainda nao ha distribuicao por cidade.</p>';
    return;
  }

  const max = Math.max(...cities.map((item) => item.total));
  els.topCities.innerHTML = cities
    .map(
      (item) => `
      <article class="city-bar" >
          <strong>${escapeHtml(item.city)}</strong>
          <div class="bar"><span style="width:${(item.total / max) * 100}%"></span></div>
          <span class="muted">${item.total} respostas</span>
        </article>
      `,
    )
    .join('');
}

function renderCharts(data) {
  const lineCtx = document.getElementById('responses-line-chart');
  const statusCtx = document.getElementById('responses-status-chart');

  if (state.charts.line) state.charts.line.destroy();
  if (state.charts.status) state.charts.status.destroy();

  state.charts.line = new Chart(lineCtx, {
    type: 'line',
    data: {
      labels: data.volumeByDay.map((item) => item.day),
      datasets: [
        {
          label: 'Respostas',
          data: data.volumeByDay.map((item) => item.total),
          borderColor: '#0f8c8c',
          backgroundColor: 'rgba(15, 140, 140, 0.12)',
          tension: 0.32,
          fill: true,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          display: false,
        },
      },
    },
  });

  const statusEntries = Object.entries(data.responseStatusCounts || {});
  state.charts.status = new Chart(statusCtx, {
    type: 'doughnut',
    data: {
      labels: statusEntries.map(([key]) => key),
      datasets: [
        {
          data: statusEntries.map(([, value]) => value),
          backgroundColor: ['#0f8c8c', '#c08a22', '#c95b4d', '#176f99'],
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
    },
  });
}

function statusClass(status) {
  if (status === 'processed' || status === 'done') return 'success';
  if (status === 'pending' || status === 'processing') return 'warning';
  if (status === 'failed') return 'danger';
  return 'neutral';
}

function formatDate(value) {
  if (!value) return '-';
  return new Date(value).toLocaleString('pt-BR');
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, {
    credentials: 'same-origin',
    ...options,
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
    throw new Error(data.error || 'request failed');
  }

  return data;
}

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}
