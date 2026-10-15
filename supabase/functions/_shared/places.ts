// Shared Places API helpers — used by both /recommendations and /enrich

export interface PlaceReview {
  authorName: string;
  rating?: number;
  relativeTime?: string;
  text: string;
}

export interface Recommendation {
  name: string;
  dish: string;
  image: string;
  explanation: string;
  mapsUrl: string;
  latitude?: number;
  longitude?: number;
  rating?: number;
  reviewCount?: number;
  isOpen?: boolean;
  photos?: string[];
  address?: string;
  phone?: string;
  website?: string;
  parking?: string;
  placeId?: string;
  photoRefs?: string[];
  reviews?: PlaceReview[];
}

export interface GroundingPlace {
  placeId: string;
  title: string;
  uri: string;
}

export interface PlaceDetails {
  photoNames: string[];
  latitude: number | undefined;
  longitude: number | undefined;
  rating: number | undefined;
  reviewCount: number | undefined;
  isOpen: boolean | undefined;
  address: string | undefined;
  phone: string | undefined;
  website: string | undefined;
  neighborhood: string | undefined;
  displayName: string | undefined;
  reviews: PlaceReview[] | undefined;
}

function logPlaces(...args: unknown[]) {
  console.log("[places]", ...args);
}

function logPlacesWarn(...args: unknown[]) {
  console.warn("[places]", ...args);
}

/** Loggable facts about a failed Google response: its length and, when the
 * body is Google's standard error envelope, the canonical status code (e.g.
 * "INVALID_ARGUMENT"). Never the body text, which can echo the query. */
export function upstreamErrorSummary(
  bodyText: string,
): { bodyLength: number; errorStatus?: string } {
  const summary: { bodyLength: number; errorStatus?: string } = {
    bodyLength: bodyText.length,
  };
  try {
    const status = JSON.parse(bodyText)?.error?.status;
    if (typeof status === "string" && /^[A-Z_]{1,40}$/.test(status)) {
      summary.errorStatus = status;
    }
  } catch {
    // Not JSON: the length is all we keep.
  }
  return summary;
}

// ── Supabase cache helpers ────────────────────────────────────────────────────

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";
const CACHE_TABLE_URL = `${SUPABASE_URL}/rest/v1/places_cache`;
const CACHE_TTL_DAYS = 30;

export interface CacheRow {
  place_id: string;
  photo_refs: string[];
  rating: number | null;
  review_count: number | null;
  is_open: boolean | null;
  address: string | null;
  phone: string | null;
  website: string | null;
  reviews: PlaceReview[] | null;
  latitude: number | null;
  longitude: number | null;
  neighborhood: string | null;
  cached_at: string;
}

export async function getCachedPlace(
  placeId: string,
): Promise<CacheRow | null> {
  try {
    const res = await fetch(
      `${CACHE_TABLE_URL}?place_id=eq.${encodeURIComponent(placeId)}&limit=1`,
      {
        headers: {
          "apikey": SUPABASE_SERVICE_ROLE_KEY,
        },
      },
    );
    if (!res.ok) return null;
    const rows: CacheRow[] = await res.json();
    if (!rows.length) return null;
    const cachedAt = new Date(rows[0].cached_at).getTime();
    if (Date.now() - cachedAt > CACHE_TTL_DAYS * 86400000) return null;
    return rows[0];
  } catch {
    return null;
  }
}

export async function upsertCachedPlace(
  row: Omit<CacheRow, "cached_at">,
): Promise<void> {
  try {
    await fetch(CACHE_TABLE_URL, {
      method: "POST",
      headers: {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates",
      },
      body: JSON.stringify({ ...row, cached_at: new Date().toISOString() }),
    });
  } catch {
    // Cache write failure is non-fatal — continue without caching
  }
}

// ── Name → placeId cache (skip Places textSearch on repeats) ──────────────────

const NAME_CACHE_TABLE_URL = `${SUPABASE_URL}/rest/v1/place_name_cache`;

export async function getCachedPlaceIdByName(
  nameKey: string,
): Promise<string | null> {
  try {
    const res = await fetch(
      `${NAME_CACHE_TABLE_URL}?name_key=eq.${
        encodeURIComponent(nameKey)
      }&limit=1`,
      {
        headers: {
          "apikey": SUPABASE_SERVICE_ROLE_KEY,
        },
      },
    );
    if (!res.ok) return null;
    const rows: Array<
      { name_key: string; place_id: string; cached_at: string }
    > = await res.json();
    if (!rows.length) return null;
    const cachedAt = new Date(rows[0].cached_at).getTime();
    if (Date.now() - cachedAt > CACHE_TTL_DAYS * 86400000) return null;
    return rows[0].place_id;
  } catch {
    return null;
  }
}

export async function upsertPlaceNameCache(
  nameKey: string,
  placeId: string,
): Promise<void> {
  try {
    await fetch(NAME_CACHE_TABLE_URL, {
      method: "POST",
      headers: {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates",
      },
      body: JSON.stringify({
        name_key: nameKey,
        place_id: placeId,
        cached_at: new Date().toISOString(),
      }),
    });
  } catch {
    // non-fatal
  }
}

// ── Geocode a city query to (lat, lng) for use as locationBias ────────────────

export async function geocodeCityToCoord(
  city: string,
  apiKey: string,
  logTag: string,
): Promise<{ lat: number; lng: number } | null> {
  logPlaces(logTag, "geocodeCity: request", { cityLength: city.length });

  const res = await fetch(
    "https://places.googleapis.com/v1/places:searchText",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": "places.location",
      },
      body: JSON.stringify({ textQuery: city, includedType: "locality" }),
    },
  );

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "geocodeCity: HTTP error", {
      status: res.status,
      ...upstreamErrorSummary(bodyText),
    });
    return null;
  }

  let data: {
    places?: Array<{ location?: { latitude?: number; longitude?: number } }>;
  };
  try {
    data = JSON.parse(bodyText);
  } catch {
    return null;
  }

  const loc = data?.places?.[0]?.location;
  if (loc?.latitude === undefined || loc?.longitude === undefined) {
    logPlacesWarn(logTag, "geocodeCity: no location returned");
    return null;
  }

  logPlaces(logTag, "geocodeCity: resolved");
  return { lat: loc.latitude, lng: loc.longitude };
}

// ── Places API helpers ────────────────────────────────────────────────────────

export function parsePlaceIdFromMapsUrl(
  mapsUrl: string,
  logTag: string,
): string | null {
  if (!mapsUrl) return null;
  let decoded: string;
  try {
    decoded = decodeURIComponent(mapsUrl);
  } catch {
    decoded = mapsUrl;
  }

  logPlaces(logTag, "parsePlaceId: mapsUrl length", mapsUrl.length);

  const queryMatch = decoded.match(
    /(?:query_place_id|place_id)=([A-Za-z0-9_-]{27,})/,
  );
  if (queryMatch) {
    logPlaces(logTag, "parsePlaceId: matched query_place_id / place_id");
    return queryMatch[1];
  }

  const chijMatch = decoded.match(/ChIJ[A-Za-z0-9_-]{20,}/);
  if (chijMatch) {
    logPlaces(logTag, "parsePlaceId: matched ChIJ token");
    return chijMatch[0];
  }

  logPlaces(logTag, "parsePlaceId: no place id pattern found in URL");
  return null;
}

export function findPlaceIdFromGrounding(
  recName: string,
  groundingPlaces: GroundingPlace[],
): string | null {
  const nameLower = recName.toLowerCase();
  const match = groundingPlaces.find(
    (g) =>
      g.title.toLowerCase().includes(nameLower) ||
      nameLower.includes(g.title.toLowerCase()),
  );
  return match?.placeId ?? null;
}

export interface LocationBias {
  lat: number;
  lng: number;
  radiusMeters: number;
}

export async function resolvePlaceIdByTextSearch(
  placeName: string,
  apiKey: string,
  logTag: string,
  searchArea = "",
  locationBias?: LocationBias,
  includedType?: string,
): Promise<string | null> {
  const textQuery = searchArea ? `${placeName} ${searchArea}` : placeName;
  const requestBody: Record<string, unknown> = { textQuery };
  if (locationBias) {
    requestBody.locationBias = {
      circle: {
        center: { latitude: locationBias.lat, longitude: locationBias.lng },
        radius: locationBias.radiusMeters,
      },
    };
  }
  if (includedType) requestBody.includedType = includedType;

  logPlaces(logTag, "textSearch: request", {
    textQueryLength: textQuery.length,
    hasBias: !!locationBias,
    includedType: includedType ?? "(none)",
  });

  const res = await fetch(
    "https://places.googleapis.com/v1/places:searchText",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": "places.id",
      },
      body: JSON.stringify(requestBody),
    },
  );

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "textSearch: HTTP error", {
      status: res.status,
      ...upstreamErrorSummary(bodyText),
    });
    return null;
  }

  let data: { places?: Array<{ id?: string }> };
  try {
    data = JSON.parse(bodyText);
  } catch {
    logPlacesWarn(logTag, "textSearch: invalid JSON", {
      bodyLength: bodyText.length,
    });
    return null;
  }

  const rawId = data?.places?.[0]?.id;
  if (!rawId) {
    logPlacesWarn(logTag, "textSearch: no places[0].id", {
      placesLength: data?.places?.length ?? 0,
    });
    return null;
  }

  const placeId = rawId.startsWith("places/") ? rawId.slice(7) : rawId;
  logPlaces(logTag, "textSearch: resolved place id");
  return placeId;
}

export async function fetchPlaceDetails(
  placeId: string,
  apiKey: string,
  logTag: string,
): Promise<PlaceDetails> {
  const url = `https://places.googleapis.com/v1/places/${
    encodeURIComponent(placeId)
  }`;
  logPlaces(logTag, "placeDetails: GET");

  const res = await fetch(url, {
    headers: {
      "X-Goog-Api-Key": apiKey,
      // `reviews` is an Enterprise + Atmosphere field but is not required for
      // the decision flow. Other requested fields still determine the final
      // Places SKU; cached historic reviews remain displayable if present.
      "X-Goog-FieldMask":
        "displayName,photos,location,rating,userRatingCount,regularOpeningHours,formattedAddress,nationalPhoneNumber,websiteUri,addressComponents",
    },
  });

  const empty: PlaceDetails = {
    photoNames: [],
    latitude: undefined,
    longitude: undefined,
    rating: undefined,
    reviewCount: undefined,
    isOpen: undefined,
    address: undefined,
    phone: undefined,
    website: undefined,
    neighborhood: undefined,
    displayName: undefined,
    reviews: undefined,
  };

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "placeDetails: HTTP error", {
      status: res.status,
      ...upstreamErrorSummary(bodyText),
    });
    return empty;
  }

  let data: {
    displayName?: { text?: string };
    photos?: Array<{ name?: string }>;
    location?: { latitude?: number; longitude?: number };
    rating?: number;
    userRatingCount?: number;
    regularOpeningHours?: { openNow?: boolean };
    formattedAddress?: string;
    nationalPhoneNumber?: string;
    websiteUri?: string;
    addressComponents?: Array<
      { longText?: string; shortText?: string; types?: string[] }
    >;
    reviews?: Array<{
      rating?: number;
      text?: { text?: string };
      originalText?: { text?: string };
      relativePublishTimeDescription?: string;
      authorAttribution?: { displayName?: string };
    }>;
  };
  try {
    data = JSON.parse(bodyText);
  } catch {
    logPlacesWarn(logTag, "placeDetails: invalid JSON", {
      bodyLength: bodyText.length,
    });
    return empty;
  }

  const photoNames = (data?.photos ?? []).slice(0, 5).map((p) => p.name ?? "")
    .filter(Boolean);
  logPlaces(logTag, "placeDetails: photo count", photoNames.length);

  const latitude = data?.location?.latitude;
  const longitude = data?.location?.longitude;
  const rating = data?.rating;
  const reviewCount = data?.userRatingCount;
  const isOpen = data?.regularOpeningHours?.openNow;
  const address = data?.formattedAddress;
  const phone = data?.nationalPhoneNumber;
  const website = data?.websiteUri;
  const displayName = data?.displayName?.text;

  // Neighborhood: prefer sublocality_level_1 / sublocality, fall back to "neighborhood" type.
  let neighborhood: string | undefined;
  for (const c of data?.addressComponents ?? []) {
    const types = c.types ?? [];
    if (
      types.includes("sublocality_level_1") || types.includes("sublocality") ||
      types.includes("neighborhood")
    ) {
      neighborhood = c.longText ?? c.shortText;
      break;
    }
  }

  const reviews: PlaceReview[] = (data?.reviews ?? [])
    .slice(0, 5)
    .map((r) => ({
      authorName: r.authorAttribution?.displayName ?? "Anonymous",
      rating: r.rating,
      relativeTime: r.relativePublishTimeDescription,
      text: r.originalText?.text ?? r.text?.text ?? "",
    }))
    .filter((r) => r.text.length > 0);

  logPlaces(logTag, "placeDetails: hasLocation", {
    hasLocation: latitude !== undefined && longitude !== undefined,
  });
  logPlaces(logTag, "placeDetails: rating/reviews/open", {
    rating,
    reviewCount,
    isOpen,
  });
  logPlaces(logTag, "placeDetails: hasNeighborhood", Boolean(neighborhood));
  logPlaces(logTag, "placeDetails: review count fetched", reviews.length);

  return {
    photoNames,
    latitude,
    longitude,
    rating,
    reviewCount,
    isOpen,
    address,
    phone,
    website,
    neighborhood,
    displayName,
    reviews,
  };
}

/**
 * Opening status is time-sensitive and must never be served from the 30-day
 * metadata cache. Undefined means the status could not be verified, allowing
 * callers to fail closed instead of showing a possibly closed venue.
 */
export async function fetchCurrentOpenStatus(
  placeId: string,
  apiKey: string,
  logTag: string,
): Promise<boolean | undefined> {
  const url = `https://places.googleapis.com/v1/places/${
    encodeURIComponent(placeId)
  }`;
  const res = await fetch(url, {
    headers: {
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "regularOpeningHours.openNow",
    },
  });

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "openStatus: HTTP error", {
      status: res.status,
      ...upstreamErrorSummary(bodyText),
    });
    return undefined;
  }

  try {
    const data = JSON.parse(bodyText) as {
      regularOpeningHours?: { openNow?: boolean };
    };
    const isOpen = data.regularOpeningHours?.openNow;
    logPlaces(logTag, "openStatus: live", { isOpen });
    return isOpen;
  } catch {
    logPlacesWarn(logTag, "openStatus: invalid JSON", {
      bodyLength: bodyText.length,
    });
    return undefined;
  }
}

export async function fetchPhotoUri(
  photoName: string,
  apiKey: string,
  logTag: string,
  maxWidthPx = 800,
): Promise<string | null> {
  const resource = photoName.endsWith("/media")
    ? photoName
    : `${photoName}/media`;
  const mediaUrl =
    `https://places.googleapis.com/v1/${resource}?maxWidthPx=${maxWidthPx}&skipHttpRedirect=true`;
  logPlaces(logTag, "photoMedia: GET", { maxWidthPx });

  const res = await fetch(mediaUrl, { headers: { "X-Goog-Api-Key": apiKey } });

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "photoMedia: HTTP error", {
      status: res.status,
      ...upstreamErrorSummary(bodyText),
    });
    return null;
  }

  let data: { photoUri?: string };
  try {
    data = JSON.parse(bodyText);
  } catch {
    logPlacesWarn(logTag, "photoMedia: invalid JSON", {
      bodyLength: bodyText.length,
    });
    return null;
  }

  const photoUri = data?.photoUri ?? null;
  if (!photoUri) {
    logPlacesWarn(logTag, "photoMedia: missing photoUri");
    return null;
  }

  logPlaces(logTag, "photoMedia: got photoUri", {
    photoUriLength: photoUri.length,
  });
  return photoUri;
}

export async function enrichRecommendation(
  rec: Recommendation,
  placesApiKey: string,
  index: number,
  searchArea: string,
  groundingPlaces: GroundingPlace[],
): Promise<{ rec: Recommendation; error: string | null }> {
  const logTag = `[#${index}]`;

  logPlaces(logTag, "── enrich start ──", {
    mapsUrlLen: rec.mapsUrl?.length ?? 0,
    hasSearchArea: searchArea.length > 0,
  });

  // ── 1. Resolve place ID ───────────────────────────────────────────────────
  let placeId = parsePlaceIdFromMapsUrl(rec.mapsUrl, logTag);

  if (!placeId) {
    placeId = findPlaceIdFromGrounding(rec.name, groundingPlaces);
    if (placeId) {
      logPlaces(logTag, "placeId resolved from grounding chunks");
    }
  }

  if (!placeId) {
    placeId = await resolvePlaceIdByTextSearch(
      rec.name,
      placesApiKey,
      logTag,
      searchArea,
    );
  }

  if (!placeId) {
    const msg =
      `${logTag} ENRICHMENT_FAILED: no placeId from URL, grounding, or text search`;
    logPlacesWarn(msg);
    return { rec, error: msg };
  }

  // ── 2. Check cache ────────────────────────────────────────────────────────
  const cached = await getCachedPlace(placeId);

  if (cached) {
    logPlaces(logTag, "CACHE HIT");

    // Cached is_open reflects the instant this metadata row was written and can
    // be days old. Feed eligibility always requires a live status check.
    const currentIsOpen = await fetchCurrentOpenStatus(
      placeId,
      placesApiKey,
      logTag,
    );

    if (!cached.photo_refs.length) {
      logPlacesWarn(
        logTag,
        "CACHE HIT but no photo_refs — returning metadata only",
      );
      return {
        rec: {
          ...rec,
          placeId,
          latitude: cached.latitude ?? undefined,
          longitude: cached.longitude ?? undefined,
          rating: cached.rating ?? undefined,
          reviewCount: cached.review_count ?? undefined,
          isOpen: currentIsOpen,
          address: cached.address ?? undefined,
          phone: cached.phone ?? undefined,
          website: cached.website ?? undefined,
          reviews: cached.reviews ?? undefined,
        },
        error: null,
      };
    }

    // Resolve only the hero ref fresh at 400px — skip fetchPlaceDetails entirely
    const heroUri = await fetchPhotoUri(
      cached.photo_refs[0],
      placesApiKey,
      logTag,
      400,
    );

    return {
      rec: {
        ...rec,
        placeId,
        latitude: cached.latitude ?? undefined,
        longitude: cached.longitude ?? undefined,
        rating: cached.rating ?? undefined,
        reviewCount: cached.review_count ?? undefined,
        isOpen: currentIsOpen,
        address: cached.address ?? undefined,
        phone: cached.phone ?? undefined,
        website: cached.website ?? undefined,
        reviews: cached.reviews ?? undefined,
        image: heroUri ?? rec.image,
        photos: heroUri ? [heroUri] : undefined,
        photoRefs: cached.photo_refs.slice(1),
      },
      error: null,
    };
  }

  // ── 3. Cache miss — fetch from Google Places ──────────────────────────────
  logPlaces(logTag, "CACHE MISS — fetching from Places API");

  const {
    photoNames,
    latitude,
    longitude,
    rating,
    reviewCount,
    isOpen,
    address,
    phone,
    website,
    neighborhood,
    reviews,
  } = await fetchPlaceDetails(placeId, placesApiKey, logTag);

  const recWithMeta = {
    ...rec,
    placeId,
    latitude,
    longitude,
    rating,
    reviewCount,
    isOpen,
    address,
    phone,
    website,
    reviews,
  };

  if (photoNames.length === 0) {
    const msg =
      `${logTag} ENRICHMENT_FAILED: Place Details returned no photo names`;
    logPlacesWarn(msg);
    // Still write metadata to cache even without photos
    await upsertCachedPlace({
      place_id: placeId,
      photo_refs: [],
      rating: rating ?? null,
      review_count: reviewCount ?? null,
      is_open: isOpen ?? null,
      address: address ?? null,
      phone: phone ?? null,
      website: website ?? null,
      reviews: reviews ?? null,
      latitude: latitude ?? null,
      longitude: longitude ?? null,
      neighborhood: neighborhood ?? null,
    });
    return { rec: recWithMeta, error: msg };
  }

  // Resolve only the hero photo at 400px during enrichment
  const heroUri = await fetchPhotoUri(photoNames[0], placesApiKey, logTag, 400);

  if (!heroUri) {
    const msg = `${logTag} ENRICHMENT_FAILED: hero photo fetch failed`;
    logPlacesWarn(msg);
    return { rec: recWithMeta, error: msg };
  }

  const remainingRefs = photoNames.slice(1);

  // Write to cache — store refs only, never URIs
  await upsertCachedPlace({
    place_id: placeId,
    photo_refs: photoNames,
    rating: rating ?? null,
    review_count: reviewCount ?? null,
    is_open: isOpen ?? null,
    address: address ?? null,
    phone: phone ?? null,
    website: website ?? null,
    reviews: reviews ?? null,
    latitude: latitude ?? null,
    longitude: longitude ?? null,
    neighborhood: neighborhood ?? null,
  });

  logPlaces(logTag, "ENRICHMENT_OK", {
    heroUriLength: heroUri.length,
    remainingRefs: remainingRefs.length,
  });

  return {
    rec: {
      ...recWithMeta,
      image: heroUri,
      photos: [heroUri],
      photoRefs: remainingRefs,
    },
    error: null,
  };
}
