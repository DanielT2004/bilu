// Shared Places API helpers — used by both /recommendations and /enrich

export interface PlaceReview {
  authorName: string;
  rating: number;
  text: string;
  relativeTimeDescription: string;
}

export interface Recommendation {
  name: string;
  dish: string;
  image: string;
  explanation: string;
  mapsUrl: string;
  latitude?: number;
  longitude?: number;
  // Enriched fields
  rating?: number;
  reviewCount?: number;
  photos?: string[];
  reviews?: PlaceReview[];
  address?: string;
  phone?: string;
  website?: string;
  isOpen?: boolean;
  tips?: string[];
}

export interface GroundingPlace {
  placeId: string;
  title: string;
  uri: string;
}

interface PlaceDetails {
  photoNames: string[];
  latitude: number | undefined;
  longitude: number | undefined;
  rating: number | undefined;
  reviewCount: number | undefined;
  reviews: PlaceReview[];
  address: string | undefined;
  phone: string | undefined;
  website: string | undefined;
  isOpen: boolean | undefined;
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
      "X-Goog-FieldMask": "photos,location,rating,userRatingCount,reviews,formattedAddress,nationalPhoneNumber,websiteUri,currentOpeningHours",
    },
  });

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "placeDetails: HTTP error", { status: res.status, placeId, bodySnippet: bodyText.slice(0, 500) });
    return { photoNames: [], latitude: undefined, longitude: undefined, rating: undefined, reviewCount: undefined, reviews: [], address: undefined, phone: undefined, website: undefined, isOpen: undefined };
  }

  let data: {
    photos?: Array<{ name?: string }>;
    location?: { latitude?: number; longitude?: number };
    rating?: number;
    userRatingCount?: number;
    reviews?: Array<{ authorAttribution?: { displayName?: string }; rating?: number; text?: { text?: string }; relativePublishTimeDescription?: string }>;
    formattedAddress?: string;
    nationalPhoneNumber?: string;
    websiteUri?: string;
    currentOpeningHours?: { openNow?: boolean };
  };
  try {
    data = JSON.parse(bodyText);
  } catch {
    logPlacesWarn(logTag, "placeDetails: invalid JSON", bodyText.slice(0, 300));
    return { photoNames: [], latitude: undefined, longitude: undefined, rating: undefined, reviewCount: undefined, reviews: [], address: undefined, phone: undefined, website: undefined, isOpen: undefined };
  }

  // ── Raw field audit ────────────────────────────────────────────────────────
  logPlaces(logTag, "placeDetails: RAW FIELDS →", {
    hasPhotos:       !!(data?.photos?.length),
    photosCount:     data?.photos?.length ?? 0,
    rating:          data?.rating ?? "MISSING",
    userRatingCount: data?.userRatingCount ?? "MISSING",
    reviewsCount:    data?.reviews?.length ?? 0,
    formattedAddress: data?.formattedAddress ?? "MISSING",
    nationalPhone:   data?.nationalPhoneNumber ?? "MISSING",
    websiteUri:      data?.websiteUri ? data.websiteUri.slice(0, 60) : "MISSING",
    openNow:         data?.currentOpeningHours?.openNow ?? "MISSING",
  });
  // ──────────────────────────────────────────────────────────────────────────

  const photoNames = (data?.photos ?? [])
    .slice(0, 10)
    .map((p) => p.name)
    .filter((n): n is string => !!n);

  if (photoNames.length === 0) {
    logPlacesWarn(logTag, "placeDetails: no photos", { photosCount: data?.photos?.length ?? 0 });
  } else {
    logPlaces(logTag, "placeDetails: found", photoNames.length, "photos");
  }

  const latitude = data?.location?.latitude;
  const longitude = data?.location?.longitude;
  logPlaces(logTag, "placeDetails: location", { latitude, longitude });

  const reviews: PlaceReview[] = (data?.reviews ?? []).slice(0, 5).map((r) => ({
    authorName: r.authorAttribution?.displayName ?? "Anonymous",
    rating: r.rating ?? 5,
    text: r.text?.text ?? "",
    relativeTimeDescription: r.relativePublishTimeDescription ?? "",
  }));

  return {
    photoNames,
    latitude,
    longitude,
    rating: data?.rating,
    reviewCount: data?.userRatingCount,
    reviews,
    address: data?.formattedAddress,
    phone: data?.nationalPhoneNumber,
    website: data?.websiteUri,
    isOpen: data?.currentOpeningHours?.openNow,
  };
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

  const details = await fetchPlaceDetails(placeId, placesApiKey, logTag);

  const recWithMeta: Recommendation = {
    ...rec,
    latitude: details.latitude,
    longitude: details.longitude,
    rating: details.rating,
    reviewCount: details.reviewCount,
    reviews: details.reviews,
    address: details.address,
    phone: details.phone,
    website: details.website,
    isOpen: details.isOpen,
  };

  if (details.photoNames.length === 0) {
    const msg = `${logTag} ENRICHMENT_FAILED: Place Details returned no photo names (placeId=${placeId})`;
    logPlacesWarn(msg);
    return { rec: recWithMeta, error: msg };
  }

  // Resolve all photo URIs in parallel (up to 10)
  const photoUris = await Promise.all(
    details.photoNames.map((name) => fetchPhotoUri(name, placesApiKey, logTag))
  );
  const validPhotoUris = photoUris.filter((uri): uri is string => !!uri);

  if (validPhotoUris.length === 0) {
    const msg = `${logTag} ENRICHMENT_FAILED: all photo media URLs failed (placeId=${placeId})`;
    logPlacesWarn(msg);
    return { rec: recWithMeta, error: msg };
  }

  logPlaces(logTag, "ENRICHMENT_OK — photos:", validPhotoUris.length);
  return {
    rec: {
      ...recWithMeta,
      image: validPhotoUris[0],
      photos: validPhotoUris,
    },
    error: null,
  };
}
