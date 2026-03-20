const { NOMINATIM_BASE_URL, OVERPASS_BASE_URL } = require('../config/env');
const { normalizeCity, toNullableNumber } = require('../utils/helpers');
const { HttpError } = require('../utils/http-error');

const REQUEST_HEADERS = {
  'User-Agent': 'relogio-blutu-admin/1.0',
  Accept: 'application/json',
  'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.8',
};

async function searchCities(query) {
  const trimmed = String(query || '').trim();
  if (!trimmed) {
    throw new HttpError(400, 'query is required');
  }

  const url = new URL('/search', NOMINATIM_BASE_URL);
  url.searchParams.set('q', trimmed);
  url.searchParams.set('format', 'jsonv2');
  url.searchParams.set('addressdetails', '1');
  url.searchParams.set('limit', '6');
  url.searchParams.set('countrycodes', 'br');

  const results = await fetchJson(url.toString());
  return results.map((item) => ({
    name: item.name || item.display_name,
    displayName: item.display_name,
    city:
      item.address?.city ||
      item.address?.town ||
      item.address?.municipality ||
      item.address?.village ||
      item.name,
    state: item.address?.state || null,
    country: item.address?.country || null,
    latitude: Number(item.lat),
    longitude: Number(item.lon),
    boundingBox: item.boundingbox
      ? {
          south: Number(item.boundingbox[0]),
          north: Number(item.boundingbox[1]),
          west: Number(item.boundingbox[2]),
          east: Number(item.boundingbox[3]),
        }
      : null,
  }));
}

async function searchPublicPlaces({ city, south, north, west, east }) {
  const normalizedCity = normalizeCity(city);
  let bbox = null;

  if (
    [south, north, west, east].every((value) => value !== undefined && value !== null)
  ) {
    bbox = {
      south: Number(south),
      north: Number(north),
      west: Number(west),
      east: Number(east),
    };
  } else if (normalizedCity) {
    const [cityMatch] = await searchCities(city);
    if (!cityMatch?.boundingBox) {
      throw new HttpError(404, 'city not found');
    }
    bbox = cityMatch.boundingBox;
  } else {
    throw new HttpError(400, 'city or bounding box is required');
  }

  const query = `
[out:json][timeout:25];
(
  node["amenity"~"school|college|university|hospital|clinic|police|fire_station|townhall|courthouse|library|post_office|bus_station"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  way["amenity"~"school|college|university|hospital|clinic|police|fire_station|townhall|courthouse|library|post_office|bus_station"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  relation["amenity"~"school|college|university|hospital|clinic|police|fire_station|townhall|courthouse|library|post_office|bus_station"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  node["tourism"~"attraction|museum|gallery|viewpoint|artwork|information"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  way["tourism"~"attraction|museum|gallery|viewpoint|artwork|information"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  relation["tourism"~"attraction|museum|gallery|viewpoint|artwork|information"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  node["office"="government"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  way["office"="government"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  relation["office"="government"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  node["leisure"~"park|garden|playground|sports_centre"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  way["leisure"~"park|garden|playground|sports_centre"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  relation["leisure"~"park|garden|playground|sports_centre"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
);
out center 50;
`;

  try {
    const result = await fetchJson(OVERPASS_BASE_URL, {
      method: 'POST',
      headers: {
        ...REQUEST_HEADERS,
        'Content-Type': 'text/plain;charset=UTF-8',
      },
      body: query,
    });

    return (result.elements || [])
      .map((element) => {
        const latitude = element.lat ?? element.center?.lat;
        const longitude = element.lon ?? element.center?.lon;
        const tags = element.tags || {};
        if (!latitude || !longitude) return null;

        return {
          id: `${element.type}-${element.id}`,
          name:
            tags.name ||
            tags.official_name ||
            tags.short_name ||
            `${tags.amenity || tags.leisure || tags.tourism || tags.office || 'local'} ${element.id}`,
          category:
            tags.amenity ||
            tags.leisure ||
            tags.tourism ||
            tags.office ||
            'public_place',
          latitude,
          longitude,
          city: normalizedCity,
          tags,
        };
      })
      .filter(Boolean)
      .slice(0, 40);
  } catch (_) {
    return searchPublicPlacesWithNominatim(normalizedCity, bbox);
  }
}

async function validateLocation({ city, latitude, longitude }) {
  const normalizedCity = normalizeCity(city);
  const lat = toNullableNumber(latitude);
  const lng = toNullableNumber(longitude);

  if (!normalizedCity || lat === null || lng === null) {
    throw new HttpError(400, 'city, latitude and longitude are required');
  }

  const url = new URL('/reverse', NOMINATIM_BASE_URL);
  url.searchParams.set('format', 'jsonv2');
  url.searchParams.set('lat', String(lat));
  url.searchParams.set('lon', String(lng));
  url.searchParams.set('zoom', '16');
  url.searchParams.set('addressdetails', '1');

  const result = await fetchJson(url.toString());
  const detectedCity = normalizeCity(
    result.address?.city ||
      result.address?.town ||
      result.address?.municipality ||
      result.address?.village,
  );

  return {
    valid: detectedCity === normalizedCity,
    detectedCity,
    displayName: result.display_name || null,
    latitude: lat,
    longitude: lng,
  };
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      ...REQUEST_HEADERS,
      ...(options.headers || {}),
    },
  });

  if (!response.ok) {
    const text = await response.text();
    throw new HttpError(
      502,
      'external map service failed',
      text.slice(0, 300),
    );
  }

  return response.json();
}

async function searchPublicPlacesWithNominatim(city, bbox) {
  const keywords = [
    ['praca', 'praca'],
    ['parque', 'parque'],
    ['prefeitura', 'governo'],
    ['forum', 'judiciario'],
    ['hospital', 'saude'],
    ['biblioteca', 'biblioteca'],
    ['universidade', 'educacao'],
    ['rodoviaria', 'transporte'],
  ];

  const results = [];

  for (const [keyword, category] of keywords) {
    const url = new URL('/search', NOMINATIM_BASE_URL);
    url.searchParams.set('q', `${keyword} ${city}`);
    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('addressdetails', '1');
    url.searchParams.set('limit', '4');
    url.searchParams.set('countrycodes', 'br');
    if (bbox) {
      url.searchParams.set(
        'viewbox',
        `${bbox.west},${bbox.north},${bbox.east},${bbox.south}`,
      );
      url.searchParams.set('bounded', '1');
    }

    const items = await fetchJson(url.toString());
    for (const item of items) {
      results.push({
        id: `${keyword}-${item.place_id}`,
        name: item.name || item.display_name,
        category,
        latitude: Number(item.lat),
        longitude: Number(item.lon),
        city,
        tags: {
          display_name: item.display_name,
          type: item.type,
          class: item.class,
        },
      });
    }
  }

  const deduped = [];
  const seen = new Set();
  for (const item of results) {
    const key = `${item.name}|${item.latitude.toFixed(5)}|${item.longitude.toFixed(5)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(item);
  }

  return deduped.slice(0, 40);
}

module.exports = {
  searchCities,
  searchPublicPlaces,
  validateLocation,
};
