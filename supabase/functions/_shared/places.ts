// Shared Places API helpers — used by both /recommendations and /enrich

export interface Recommendation {
  name: string;
  dish: string;
  image: string;
  explanation: string;
  mapsUrl: string;
  latitude?: number;
  longitude?: number;
}

export interface GroundingPlace {
  placeId: string;
  title: string;
  uri: string;
}

interface PlaceDetails {
  photoName: string | null;
  latitude: number | undefined;
  longitude: number | undefined;
}

function logPlaces(...args: unknown[]) {
  console.log("[places]", ...args);
}

function logPlacesWarn(...args: unknown[]) {
  console.warn("[places]", ...args);
}

export function parsePlaceIdFromMapsUrl(mapsUrl: string, logTag: string): string | null {
  if (!mapsUrl) return null;
  let decoded: string;
  try {
    decoded = decodeURIComponent(mapsUrl);
  } catch {
    decoded = mapsUrl;
  }

  logPlaces(logTag, "parsePlaceId: raw mapsUrl (truncated)", mapsUrl.slice(0, 200));

  const queryMatch = decoded.match(/(?:query_place_id|place_id)=([A-Za-z0-9_-]{27,})/);
  if (queryMatch) {
    logPlaces(logTag, "parsePlaceId: matched query_place_id / place_id", queryMatch[1]);
    return queryMatch[1];
  }

  const chijMatch = decoded.match(/ChIJ[A-Za-z0-9_-]{20,}/);
  if (chijMatch) {
    logPlaces(logTag, "parsePlaceId: matched ChIJ token", chijMatch[0]);
    return chijMatch[0];
  }

  logPlaces(logTag, "parsePlaceId: no place id pattern found in URL");
  return null;
}

export function findPlaceIdFromGrounding(recName: string, groundingPlaces: GroundingPlace[]): string | null {
  const nameLower = recName.toLowerCase();
  const match = groundingPlaces.find(
    (g) => g.title.toLowerCase().includes(nameLower) || nameLower.includes(g.title.toLowerCase())
  );
  return match?.placeId ?? null;
}

export async function resolvePlaceIdByTextSearch(
  placeName: string,
  apiKey: string,
  logTag: string,
  searchArea = "Los Angeles, CA"
): Promise<string | null> {
  const textQuery = `${placeName} ${searchArea}`;
  logPlaces(logTag, "textSearch: request", { textQuery });

  const res = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "places.id",
    },
    body: JSON.stringify({ textQuery }),
  });

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "textSearch: HTTP error", { status: res.status, bodySnippet: bodyText.slice(0, 500) });
    return null;
  }

  let data: { places?: Array<{ id?: string }> };
  try {
    data = JSON.parse(bodyText);
  } catch {
    logPlacesWarn(logTag, "textSearch: invalid JSON", bodyText.slice(0, 300));
    return null;
  }

  const rawId = data?.places?.[0]?.id;
  if (!rawId) {
    logPlacesWarn(logTag, "textSearch: no places[0].id", { placesLength: data?.places?.length ?? 0 });
    return null;
  }

  const placeId = rawId.startsWith("places/") ? rawId.slice(7) : rawId;
  logPlaces(logTag, "textSearch: resolved place id", { rawId, placeId });
  return placeId;
}

async function fetchPlaceDetails(placeId: string, apiKey: string, logTag: string): Promise<PlaceDetails> {
  const url = `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`;
  logPlaces(logTag, "placeDetails: GET", url);

  const res = await fetch(url, {
    headers: {
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "photos,location",
    },
  });

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "placeDetails: HTTP error", { status: res.status, placeId, bodySnippet: bodyText.slice(0, 500) });
    return { photoName: null, latitude: undefined, longitude: undefined };
  }

  let data: { photos?: Array<{ name?: string }>; location?: { latitude?: number; longitude?: number } };
  try {
    data = JSON.parse(bodyText);
  } catch {
    logPlacesWarn(logTag, "placeDetails: invalid JSON", bodyText.slice(0, 300));
    return { photoName: null, latitude: undefined, longitude: undefined };
  }

  const photoName = data?.photos?.[0]?.name ?? null;
  if (!photoName) {
    logPlacesWarn(logTag, "placeDetails: no photos[0].name", { photosCount: data?.photos?.length ?? 0 });
  } else {
    logPlaces(logTag, "placeDetails: first photo resource name", photoName);
  }

  const latitude = data?.location?.latitude;
  const longitude = data?.location?.longitude;
  logPlaces(logTag, "placeDetails: location", { latitude, longitude });

  return { photoName, latitude, longitude };
}

async function fetchPhotoUri(photoName: string, apiKey: string, logTag: string): Promise<string | null> {
  const resource = photoName.endsWith("/media") ? photoName : `${photoName}/media`;
  const mediaUrl = `https://places.googleapis.com/v1/${resource}?maxWidthPx=800&skipHttpRedirect=true`;
  logPlaces(logTag, "photoMedia: GET (truncated)", mediaUrl.slice(0, 180));

  const res = await fetch(mediaUrl, { headers: { "X-Goog-Api-Key": apiKey } });

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "photoMedia: HTTP error", { status: res.status, bodySnippet: bodyText.slice(0, 500) });
    return null;
  }

  let data: { photoUri?: string };
  try {
    data = JSON.parse(bodyText);
  } catch {
    logPlacesWarn(logTag, "photoMedia: invalid JSON", bodyText.slice(0, 300));
    return null;
  }

  const photoUri = data?.photoUri ?? null;
  if (!photoUri) {
    logPlacesWarn(logTag, "photoMedia: missing photoUri", data);
    return null;
  }

  logPlaces(logTag, "photoMedia: got photoUri (truncated)", photoUri.slice(0, 120) + "…");
  return photoUri;
}

export async function enrichRecommendation(
  rec: Recommendation,
  placesApiKey: string,
  index: number,
  searchArea: string,
  groundingPlaces: GroundingPlace[]
): Promise<{ rec: Recommendation; error: string | null }> {
  const logTag = `[#${index} "${rec.name}"]`;

  logPlaces(logTag, "── enrich start ──", {
    mapsUrlLen: rec.mapsUrl?.length ?? 0,
    searchArea,
  });

  let placeId = parsePlaceIdFromMapsUrl(rec.mapsUrl, logTag);

  if (!placeId) {
    placeId = findPlaceIdFromGrounding(rec.name, groundingPlaces);
    if (placeId) logPlaces(logTag, "placeId resolved from grounding chunks:", placeId);
  }

  if (!placeId) {
    placeId = await resolvePlaceIdByTextSearch(rec.name, placesApiKey, logTag, searchArea);
  }

  if (!placeId) {
    const msg = `${logTag} ENRICHMENT_FAILED: no placeId from URL, grounding, or text search`;
    logPlacesWarn(msg);
    return { rec, error: msg };
  }

  const { photoName, latitude, longitude } = await fetchPlaceDetails(placeId, placesApiKey, logTag);
  const recWithCoords = { ...rec, latitude, longitude };

  const photoUri = photoName ? await fetchPhotoUri(photoName, placesApiKey, logTag) : null;
  if (!photoName) {
    const msg = `${logTag} ENRICHMENT_FAILED: Place Details returned no photo name (placeId=${placeId})`;
    logPlacesWarn(msg);
    return { rec: recWithCoords, error: msg };
  }

  if (!photoUri) {
    const msg = `${logTag} ENRICHMENT_FAILED: photo media URL failed (placeId=${placeId})`;
    logPlacesWarn(msg);
    return { rec: recWithCoords, error: msg };
  }

  logPlaces(logTag, "ENRICHMENT_OK");
  return { rec: { ...recWithCoords, image: photoUri }, error: null };
}
