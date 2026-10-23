// [crm] P2-10: pure degradation-detection logic, shared between the
// quality-rating poller (whatsapp-management/number_health.ts) and the
// messaging-limit webhook handler (whatsapp_webhook_processing.ts) -- lives
// here, not in whatsapp-management, because a _shared file can't import
// from a single function's own folder (breaks that function's independent
// bundling/deployment). No network, no DB: directly unit-testable.

// Worse-to-better, so "degraded" is simply "a lower rank than before".
// UNKNOWN/NA and any value Meta might add later rank undefined -- stored,
// never compared (a flag over a value we can't order would be a guess).
const QUALITY_RANK: Record<string, number> = { RED: 0, YELLOW: 1, GREEN: 2 };

// TIER_NOT_SET is the pre-messaging placeholder (not a real tier), ranked
// below every real tier so a number's first real tier never reads as a
// downgrade.
const TIER_RANK: Record<string, number> = {
  TIER_NOT_SET: 0,
  TIER_50: 1,
  TIER_250: 2,
  TIER_2K: 3,
  TIER_10K: 4,
  TIER_100K: 5,
  TIER_UNLIMITED: 6,
};

/** Null/undefined `previous` means no prior data (nothing to compare
 * against yet, so never a degradation). An unrecognized rating on either
 * side can't be ordered, so it's never flagged either -- it's still
 * stored by the caller, just not compared. */
export function isQualityDegraded(
  previous: string | null | undefined,
  current: string,
): boolean {
  if (!previous) return false;

  const prevRank = QUALITY_RANK[previous];
  const currRank = QUALITY_RANK[current];

  if (prevRank === undefined || currRank === undefined) return false;

  return currRank < prevRank;
}

/** Same reasoning as isQualityDegraded, for messaging-limit tiers. */
export function isLimitDowngraded(
  previous: string | null | undefined,
  current: string,
): boolean {
  if (!previous) return false;

  const prevRank = TIER_RANK[previous];
  const currRank = TIER_RANK[current];

  if (prevRank === undefined || currRank === undefined) return false;

  return currRank < prevRank;
}

/** How hard to throttle the send-pacing token bucket (_shared/send_policy.ts)
 * for a number in this state. Pure: no network, no DB. Defaults (passed in,
 * not hardcoded here, so this stays decoupled from send_policy's own
 * constants) apply whenever neither signal indicates trouble. */
export function effectivePacing(
  quality_rating: string | null | undefined,
  messaging_limit_tier: string | null | undefined,
  defaults: { capacity: number; refillPerSecond: number },
): { capacity: number; refillPerSecond: number } {
  const qualityRank = quality_rating ? QUALITY_RANK[quality_rating] : undefined;
  const tierRank = messaging_limit_tier
    ? TIER_RANK[messaging_limit_tier]
    : undefined;

  if (qualityRank === 0) {
    // RED: as gentle as possible without stalling sends entirely.
    return { capacity: 1, refillPerSecond: 0.2 };
  }

  if (qualityRank === 1 || (tierRank !== undefined && tierRank <= 1)) {
    // YELLOW quality, or a low tier (TIER_NOT_SET/TIER_50) -- ease off.
    return { capacity: 2, refillPerSecond: 0.5 };
  }

  return defaults;
}
