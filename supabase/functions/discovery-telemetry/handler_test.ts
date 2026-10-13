import {
  type DiscoveryTelemetryDependencies,
  handleDiscoveryTelemetry,
  parseEnvelope,
} from "./handler.ts";
import { PaidAPIAccessError } from "../_shared/paid_api_guard.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
const uuid = "11111111-1111-4111-8111-111111111111";
function event(name = "started") {
  return {
    id: uuid,
    discoveryID: uuid,
    event: name,
    capturedAt: "2026-10-09T12:00:00Z",
    adVisible: false,
  };
}
function envelope(events: unknown[] = [event()]) {
  return { version: 1, appVersion: "1.0", build: "25", events };
}
function request(body: unknown) {
  return new Request("https://local.invalid/discovery-telemetry", {
    method: "POST",
    body: JSON.stringify(body),
  });
}
function fixture() {
  let writes = 0;
  const dependencies: DiscoveryTelemetryDependencies = {
    authenticate: () => Promise.resolve({ id: uuid }),
    ingest: (userID, payload) => {
      assert(userID === uuid);
      assert(payload.events.length > 0);
      writes += 1;
      return Promise.resolve(true);
    },
  };
  return { dependencies, writes: () => writes };
}

Deno.test("typed funnel and decimal revenue envelope accepted", async () => {
  const { dependencies, writes } = fixture();
  const body = envelope([
    event(),
    { ...event("completed"), durationMilliseconds: 2712 },
    {
      ...event("adRevenue"),
      revenue: "0.000001",
      currency: "USD",
      precision: 3,
    },
  ]);
  assert(
    (await handleDiscoveryTelemetry(request(body), dependencies)).status ===
      202,
  );
  assert(writes() === 1);
});

Deno.test("reject user content, identities, unexpected fields and MetricKit envelopes", () => {
  for (
    const field of [
      "prompt",
      "location",
      "userID",
      "rewardToken",
      "advertisingID",
    ]
  ) {
    assert(
      parseEnvelope(envelope([{ ...event(), [field]: "sensitive" }])) === null,
    );
    assert(parseEnvelope({ ...envelope(), [field]: "sensitive" }) === null);
  }
  assert(parseEnvelope({ id: uuid, kind: "metric", payload: "{}" }) === null);
});

Deno.test("validate numeric bounds, currency, dates, enums and batch size", () => {
  for (
    const invalid of [
      { ...event(), durationMilliseconds: -1 },
      { ...event(), durationMilliseconds: Infinity },
      { ...event(), durationMilliseconds: 3_600_001 },
      { ...event(), code: "offline" },
      { ...event(), id: "identity" },
      { ...event(), capturedAt: "not-a-date" },
      event("restaurant-name"),
      { ...event(), revenue: "0.01" },
      { ...event("adRevenue"), revenue: "-1", currency: "USD", precision: 3 },
      {
        ...event("adRevenue"),
        revenue: "0.01",
        currency: "location",
        precision: 3,
      },
      { ...event("adRevenue"), revenue: "0.01", currency: "USD", precision: 4 },
      { ...event("adRevenue"), revenue: "0.01", currency: "USD" },
    ]
  ) assert(parseEnvelope(envelope([invalid])) === null);
  assert(parseEnvelope(envelope([])) === null);
  assert(parseEnvelope(envelope(Array(21).fill(event()))) === null);
});

Deno.test("unauthenticated, malformed and oversized requests never reach storage", async () => {
  const { dependencies, writes } = fixture();
  assert(
    (await handleDiscoveryTelemetry(request({}), dependencies)).status === 400,
  );
  assert(
    (await handleDiscoveryTelemetry(
      request({ data: "x".repeat(24_000) }),
      dependencies,
    )).status === 413,
  );
  dependencies.authenticate = () => {
    throw new PaidAPIAccessError(401, "AUTH_REQUIRED", "Sign in");
  };
  assert(
    (await handleDiscoveryTelemetry(request(envelope()), dependencies))
      .status === 401,
  );
  assert(writes() === 0);
});

Deno.test("rate and unavailable storage have recoverable HTTP responses", async () => {
  const { dependencies } = fixture();
  dependencies.ingest = () => Promise.resolve(false);
  assert(
    (await handleDiscoveryTelemetry(request(envelope()), dependencies))
      .status === 429,
  );
  dependencies.ingest = () => {
    throw new Error("offline");
  };
  assert(
    (await handleDiscoveryTelemetry(request(envelope()), dependencies))
      .status === 503,
  );
});

Deno.test("OPTIONS and unsupported methods do not ingest", async () => {
  const { dependencies, writes } = fixture();
  assert(
    (await handleDiscoveryTelemetry(
      new Request("https://local.invalid", { method: "OPTIONS" }),
      dependencies,
    )).status === 200,
  );
  assert(
    (await handleDiscoveryTelemetry(
      new Request("https://local.invalid"),
      dependencies,
    )).status === 405,
  );
  assert(writes() === 0);
});
