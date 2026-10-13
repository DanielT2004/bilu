import {
  appleUnavailable,
  createAppleVerifier,
  loadAppleStoreConfig,
} from "./apple_store.ts";
import type { AppleHandlerDependencies } from "./apple_store_handlers.ts";
import { requireAuthenticatedUser } from "./paid_api_guard.ts";
import { getPurchaseWallet, purchaseWalletRPC } from "./purchase_wallet.ts";

let apple: ReturnType<AppleHandlerDependencies["apple"]> | undefined;

export const appleStoreDependencies: AppleHandlerDependencies = {
  authenticate: requireAuthenticatedUser,
  wallet: getPurchaseWallet,
  apple: () => {
    if (!apple) {
      const config = loadAppleStoreConfig();
      apple = {
        verifier: createAppleVerifier(config),
        environment: config.environment,
      };
    }
    return apple;
  },
  owner: (originalTransactionId, environment) =>
    purchaseWalletRPC<string | null>(
      "apple_transaction_owner",
      {
        p_original_transaction_id: originalTransactionId,
        p_environment: environment,
      },
    ),
  apply: async (userId, transaction, notification) => {
    const result = await purchaseWalletRPC<
      { applied: boolean; accountId: string }
    >(
      "apple_apply_transaction",
      {
        p_user_id: userId,
        p_app_account_token: transaction.appAccountToken,
        p_transaction_id: transaction.transactionId,
        p_original_transaction_id: transaction.originalTransactionId,
        p_product_id: transaction.productId,
        p_environment: transaction.environment,
        p_signed_at: transaction.signedAt,
        p_purchased_at: transaction.purchasedAt,
        p_expires_at: transaction.expiresAt,
        p_revoked_at: transaction.revokedAt,
        p_notification_id: notification?.id ?? null,
        p_notification_type: notification?.type ?? null,
      },
    );
    if (
      typeof result?.applied !== "boolean" ||
      result.accountId !== userId.toLowerCase()
    ) {
      throw appleUnavailable();
    }
  },
};
