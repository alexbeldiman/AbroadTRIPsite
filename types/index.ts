/**
 * Shared application types.
 *
 * Import from `@/types` in app code — not from `@/types/database`. Everything
 * here is derived from the schema, so a migration + regenerated `database.ts`
 * propagates automatically instead of drifting.
 */

import type { Database } from './database';

export type { Database, Json } from './database';

// --- Table row shapes -------------------------------------------------------

type Tables = Database['public']['Tables'];

export type Profile = Tables['profiles']['Row'];
export type Trip = Tables['trips']['Row'];
export type TripSegment = Tables['trip_segments']['Row'];
export type TripParticipant = Tables['trip_participants']['Row'];
export type TripShare = Tables['trip_shares']['Row'];
export type Recommendation = Tables['recommendations']['Row'];
export type Follow = Tables['follows']['Row'];
export type Destination = Tables['destinations']['Row'];

// --- Insert / Update payloads -----------------------------------------------

export type ProfileUpdate = Tables['profiles']['Update'];
export type TripInsert = Tables['trips']['Insert'];
export type TripUpdate = Tables['trips']['Update'];
export type TripSegmentInsert = Tables['trip_segments']['Insert'];
export type TripSegmentUpdate = Tables['trip_segments']['Update'];
export type RecommendationInsert = Tables['recommendations']['Insert'];
export type RecommendationUpdate = Tables['recommendations']['Update'];
export type TripParticipantInsert = Tables['trip_participants']['Insert'];
export type TripShareInsert = Tables['trip_shares']['Insert'];
export type FollowInsert = Tables['follows']['Insert'];

// --- Enums ------------------------------------------------------------------

type Enums = Database['public']['Enums'];

export type AccountVisibility = Enums['account_visibility'];
export type TripStatus = Enums['trip_status'];
export type TripVisibility = Enums['trip_visibility'];
export type SegmentType = Enums['segment_type'];
export type SegmentStatus = Enums['segment_status'];
export type ParticipantRole = Enums['participant_role'];
export type InviteStatus = Enums['invite_status'];
export type FollowStatus = Enums['follow_status'];

/**
 * Runtime-iterable enum values, for building <select> options and validating
 * form input. Kept `as const` and typed against the schema union, so deleting a
 * variant from the database and forgetting to update it here is a type error.
 */
export const TRIP_STATUSES = [
  'idea',
  'planned',
  'booked',
  'completed',
] as const satisfies readonly TripStatus[];

export const TRIP_VISIBILITIES = [
  'public',
  'followers',
  'custom',
  'private',
] as const satisfies readonly TripVisibility[];

export const SEGMENT_TYPES = [
  'flight',
  'train',
  'bus',
  'stay',
  'reservation',
] as const satisfies readonly SegmentType[];

export const SEGMENT_STATUSES = [
  'wanted',
  'booked',
] as const satisfies readonly SegmentStatus[];

export const ACCOUNT_VISIBILITIES = [
  'public',
  'private',
] as const satisfies readonly AccountVisibility[];

// --- Composite shapes -------------------------------------------------------

/** A trip with its segments — the shape the trip detail page needs. */
export type TripWithSegments = Trip & {
  trip_segments: TripSegment[];
};

/** A trip with everything the detail page renders. */
export type TripWithRelations = Trip & {
  trip_segments: TripSegment[];
  recommendations: Recommendation[];
  trip_participants: (TripParticipant & { profiles: Profile | null })[];
};

/** A trip alongside its owner, for feed and profile listings. */
export type TripWithOwner = Trip & {
  profiles: Profile | null;
};
