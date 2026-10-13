import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { discoveryDependencies, handleDiscovery } from "./handler.ts";
import type {
  DiscoveryReservation,
  PurchaseWallet,
} from "../_shared/purchase_wallet.ts";
import { PaidAPIAccessError } from "../_shared/paid_api_guard.ts";

const account = "11111111-1111-4111-8111-111111111111";
const id = "22222222-2222-4222-8222-222222222222";
const wallet: PurchaseWallet = {
  accountId: account,
  appAccountToken: account,
  requiresSignIn: false,
  plan: "free",
  periodStart: "2026-10-01T00:00:00Z",
  periodEnd: "2026-11-01T00:00:00Z",
  included: { explore: 2, tiktok: 1 },
  purchased: { explore: 4, tiktok: 1 },
  commerceEnabled: true,
  proEnabled: false,
};
const reserved: DiscoveryReservation = {
  discoveryId: id,
  kind: "explore",
  status: "reserved",
  source: "included",
  acquired: true,
};
const request = (overrides: Record<string, unknown> = {}) =>
  new Request("http://local/discovery", {
    method: "POST",
    body: JSON.stringify({
      discoveryId: id,
      kind: "explore",
      input: { prompt: "Dinner in LA" },
      ...overrides,
    }),
  });

function fixture() {
  const calls: string[] = [];
  const dependencies: typeof discoveryDependencies = {
    authenticate: async () => ({ id: account, isAnonymous: false }),
    wallet: async () => wallet,
    reserve: async () => {
      calls.push("reserve");
      return reserved;
    },
    read: async () => ({ ...reserved, acquired: false }),
    commit: async (_user, _id, _kind, result) => {
      calls.push("commit");
      return { ...reserved, status: "committed", acquired: false, result };
    },
    release: async () => {
      calls.push("release");
      return { ...reserved, status: "released", acquired: false };
    },
    fulfill: async () => {
      calls.push("fulfill");
      return { usable: true, result: { recommendations: [{ isOpen: true }] } };
    },
  };
  return { dependencies, calls };
}

Deno.test("discovery settles only after a usable server result", async () => {
  const { dependencies, calls } = fixture();
  const response = await handleDiscovery(request(), dependencies);
  assertEquals(response.status, 200);
  assertEquals((await response.json()).status, "committed");
  assertEquals(calls, ["reserve", "fulfill", "commit"]);
});

Deno.test("duplicate pending request never executes a second provider job", async () => {
  const { dependencies, calls } = fixture();
  dependencies.reserve = async () => ({ ...reserved, acquired: false });
  const response = await handleDiscovery(request(), dependencies);
  assertEquals(response.status, 202);
  assertEquals(calls, []);
});

Deno.test("committed replay returns the existing result", async () => {
  const { dependencies, calls } = fixture();
  dependencies.reserve = async () => ({
    ...reserved,
    status: "committed",
    acquired: false,
    result: { saved: true },
  });
  const response = await handleDiscovery(request(), dependencies);
  assertEquals((await response.json()).result, { saved: true });
  assertEquals(calls, []);
});

Deno.test("empty verified result returns allowance instead of committing", async () => {
  const { dependencies, calls } = fixture();
  dependencies.fulfill = async () => ({
    usable: false,
    result: { recommendations: [] },
  });
  const response = await handleDiscovery(request(), dependencies);
  assertEquals((await response.json()).status, "released");
  assertEquals(calls, ["reserve", "release"]);
});

Deno.test("exhausted allowance never starts provider work", async () => {
  const { dependencies, calls } = fixture();
  dependencies.reserve = async () => {
    throw new PaidAPIAccessError(
      402,
      "DISCOVERY_CREDITS_REQUIRED",
      "No allowance",
    );
  };
  assertEquals((await handleDiscovery(request(), dependencies)).status, 402);
  assertEquals(calls, []);
});

Deno.test("provider failure releases once", async () => {
  const { dependencies, calls } = fixture();
  dependencies.fulfill = async () => {
    throw new PaidAPIAccessError(503, "DISCOVERY_FAILED", "Unavailable");
  };
  assertEquals((await handleDiscovery(request(), dependencies)).status, 503);
  assertEquals(calls, ["reserve", "release"]);
});

Deno.test("ambiguous commit response remains recoverable and is never released", async () => {
  const { dependencies, calls } = fixture();
  dependencies.commit = async () => {
    calls.push("commit");
    throw new Error("Connection lost after DB commit");
  };
  assertEquals((await handleDiscovery(request(), dependencies)).status, 202);
  assertEquals(calls, ["reserve", "fulfill", "commit"]);
});

Deno.test("failed release does not claim allowance was returned", async () => {
  const { dependencies } = fixture();
  dependencies.fulfill = async () => {
    throw new Error("Provider failed");
  };
  dependencies.release = async () => {
    throw new Error("Database unavailable");
  };
  const response = await handleDiscovery(request(), dependencies);
  assertEquals(response.status, 202);
  assertEquals((await response.json()).code, "DISCOVERY_PENDING");
});

Deno.test("status recovery remains available after new sales are disabled", async () => {
  const { dependencies, calls } = fixture();
  dependencies.wallet = async () => ({ ...wallet, commerceEnabled: false });
  dependencies.read = async () => ({
    ...reserved,
    status: "committed",
    acquired: false,
    result: { saved: true },
  });
  const response = await handleDiscovery(
    request({ action: "status" }),
    dependencies,
  );
  assertEquals(response.status, 200);
  assertEquals((await response.json()).result, { saved: true });
  assertEquals(calls, []);
  assertEquals((await handleDiscovery(request(), dependencies)).status, 503);
});

Deno.test("oversized body is rejected before reserve or providers", async () => {
  const { dependencies, calls } = fixture();
  const response = await handleDiscovery(
    new Request("http://local/discovery", {
      method: "POST",
      body: "x".repeat(25_000),
    }),
    dependencies,
  );
  assertEquals(response.status, 413);
  assertEquals(calls, []);
});

Deno.test("malformed requests and kind cannot select arbitrary paid work", async () => {
  const { dependencies, calls } = fixture();
  for (
    const overrides of [{ kind: "grant" }, { discoveryId: "bad" }, {
      input: { prompt: "" },
    }, { input: { prompt: "dinner", latitude: 99 } }]
  ) {
    assertEquals(
      (await handleDiscovery(request(overrides), dependencies)).status,
      400,
    );
  }
  assertEquals(calls, []);
});
