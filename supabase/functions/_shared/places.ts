// Shared Places API helpers — used by both /recommendations and /enrich

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
  placeId?: string;
  photoRefs?: string[];
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
  isOpen: boolean | undefined;
  address: string | undefined;
  phone: string | undefined;
  website: string | undefined;
}

function logPlaces(...args: unknown[]) {
  console.log("[places]", ...args);
}

function logPlacesWarn(...args: unknown[]) {
  console.warn("[places]", ...args);
}

// ── Supabase cache helpers ────────────────────────────────────────────────────

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const CACHE_TABLE_URL = `${SUPABASE_URL}/rest/v1/places_cache`;
const CACHE_TTL_DAYS = 30;

interface CacheRow {
  place_id: string;
  photo_refs: string[];
  rating: number | null;
  review_count: number | null;
  is_open: boolean | null;
  address: string | null;
  phone: string | null;
  website: string | null;
  latitude: number | null;
  longitude: number | null;
  cached_at: string;
}

async function getCachedPlace(placeId: string): Promise<CacheRow | null> {
  try {
    const res = await fetch(
      `${CACHE_TABLE_URL}?place_id=eq.${encodeURIComponent(placeId)}&limit=1`,
      {
        headers: {
          "apikey": SUPABASE_SERVICE_ROLE_KEY,
          "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
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

async function upsertCachedPlace(row: Omit<CacheRow, "cached_at">): Promise<void> {
  try {
    await fetch(CACHE_TABLE_URL, {
      method: "POST",
      headers: {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates",
      },
      body: JSON.stringify({ ...row, cached_at: new Date().toISOString() }),
    });
  } catch {
    // Cache write failure is non-fatal — continue without caching
  }
}

// ── Places API helpers ────────────────────────────────────────────────────────

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
  searchArea = ""
): Promise<string | null> {
  const textQuery = searchArea ? `${placeName} ${searchArea}` : placeName;
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
      "X-Goog-FieldMask": "photos,location,rating,userRatingCount,regularOpeningHours,formattedAddress,nationalPhoneNumber,websiteUri",
    },
  });

  const empty: PlaceDetails = { photoNames: [], latitude: undefined, longitude: undefined, rating: undefined, reviewCount: undefined, isOpen: undefined, address: undefined, phone: undefined, website: undefined };

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "placeDetails: HTTP error", { status: res.status, placeId, bodySnippet: bodyText.slice(0, 500) });
    return empty;
  }

  let data: {
    photos?: Array<{ name?: string }>;
    location?: { latitude?: number; longitude?: number };
    rating?: number;
    userRatingCount?: number;
    regularOpeningHours?: { openNow?: boolean };
    formattedAddress?: string;
    nationalPhoneNumber?: string;
    websiteUri?: string;
  };
  try {
    data = JSON.parse(bodyText);
  } catch {
    logPlacesWarn(logTag, "placeDetails: invalid JSON", bodyText.slice(0, 300));
    return empty;
  }

  const photoNames = (data?.photos ?? []).slice(0, 5).map((p) => p.name ?? "").filter(Boolean);
  logPlaces(logTag, "placeDetails: photo count", photoNames.length);

  const latitude = data?.location?.latitude;
  const longitude = data?.location?.longitude;
  const rating = data?.rating;
  const reviewCount = data?.userRatingCount;
  const isOpen = data?.regularOpeningHours?.openNow;
  const address = data?.formattedAddress;
  const phone = data?.nationalPhoneNumber;
  const website = data?.websiteUri;
  logPlaces(logTag, "placeDetails: location", { latitude, longitude });
  logPlaces(logTag, "placeDetails: rating/reviews/open", { rating, reviewCount, isOpen });

  return { photoNames, latitude, longitude, rating, reviewCount, isOpen, address, phone, website };
}

export async function fetchPhotoUri(photoName: string, apiKey: string, logTag: string, maxWidthPx = 800): Promise<string | null> {
  const resource = photoName.endsWith("/media") ? photoName : `${photoName}/media`;
  const mediaUrl = `https://places.googleapis.com/v1/${resource}?maxWidthPx=${maxWidthPx}&skipHttpRedirect=true`;
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

  // ── 1. Resolve place ID ───────────────────────────────────────────────────
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

  // ── 2. Check cache ────────────────────────────────────────────────────────
  const cached = await getCachedPlace(placeId);

  if (cached) {
    logPlaces(logTag, "CACHE HIT", placeId);

    if (!cached.photo_refs.length) {
      logPlacesWarn(logTag, "CACHE HIT but no photo_refs — returning metadata only");
      return {
        rec: {
          ...rec,
          placeId,
          latitude: cached.latitude ?? undefined,
          longitude: cached.longitude ?? undefined,
          rating: cached.rating ?? undefined,
          reviewCount: cached.review_count ?? undefined,
          isOpen: cached.is_open ?? undefined,
          address: cached.address ?? undefined,
          phone: cached.phone ?? undefined,
          website: cached.website ?? undefined,
        },
        error: null,
      };
    }

    // Resolve only the hero ref fresh at 400px — skip fetchPlaceDetails entirely
    const heroUri = await fetchPhotoUri(cached.photo_refs[0], placesApiKey, logTag, 400);

    return {
      rec: {
        ...rec,
        placeId,
        latitude: cached.latitude ?? undefined,
        longitude: cached.longitude ?? undefined,
        rating: cached.rating ?? undefined,
        reviewCount: cached.review_count ?? undefined,
        isOpen: cached.is_open ?? undefined,
        address: cached.address ?? undefined,
        phone: cached.phone ?? undefined,
        website: cached.website ?? undefined,
        image: heroUri ?? rec.image,
        photos: heroUri ? [heroUri] : undefined,
        photoRefs: cached.photo_refs.slice(1),
      },
      error: null,
    };
  }

  // ── 3. Cache miss — fetch from Google Places ──────────────────────────────
  logPlaces(logTag, "CACHE MISS — fetching from Places API", placeId);

  const { photoNames, latitude, longitude, rating, reviewCount, isOpen, address, phone, website } =
    await fetchPlaceDetails(placeId, placesApiKey, logTag);

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
  };

  if (photoNames.length === 0) {
    const msg = `${logTag} ENRICHMENT_FAILED: Place Details returned no photo names (placeId=${placeId})`;
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
      latitude: latitude ?? null,
      longitude: longitude ?? null,
    });
    return { rec: recWithMeta, error: msg };
  }

  // Resolve only the hero photo at 400px during enrichment
  const heroUri = await fetchPhotoUri(photoNames[0], placesApiKey, logTag, 400);

  if (!heroUri) {
    const msg = `${logTag} ENRICHMENT_FAILED: hero photo fetch failed (placeId=${placeId})`;
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
    latitude: latitude ?? null,
    longitude: longitude ?? null,
  });

  logPlaces(logTag, "ENRICHMENT_OK", { heroUri: heroUri.slice(0, 80), remainingRefs: remainingRefs.length });

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
