/**
 * Database schema types.
 *
 * Mirrors supabase/migrations/20260727120000_init_schema.sql.
 *
 * HAND-WRITTEN, not generated — generating requires the Supabase CLI linked to
 * the project. Once the migration is live, replace this file with the generated
 * output and treat that as the source of truth:
 *
 *   npx supabase gen types typescript --project-id <ref> --schema public > types/database.ts
 *
 * Until then: if you change the migration, change this file in the same commit.
 */

export type Json = string | number | boolean | null | { [key: string]: Json } | Json[];

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          username: string;
          display_name: string | null;
          avatar_url: string | null;
          home_school: string | null;
          study_city: string | null;
          study_country: string | null;
          semester_start: string | null;
          semester_end: string | null;
          account_visibility: Database['public']['Enums']['account_visibility'];
          created_at: string;
        };
        // `id` must equal auth.uid() — enforced by RLS, not by types.
        // `username` is set by the handle_new_user trigger on signup.
        Insert: {
          id: string;
          username?: string;
          display_name?: string | null;
          avatar_url?: string | null;
          home_school?: string | null;
          study_city?: string | null;
          study_country?: string | null;
          semester_start?: string | null;
          semester_end?: string | null;
          account_visibility?: Database['public']['Enums']['account_visibility'];
          created_at?: string;
        };
        Update: {
          id?: string;
          username?: string;
          display_name?: string | null;
          avatar_url?: string | null;
          home_school?: string | null;
          study_city?: string | null;
          study_country?: string | null;
          semester_start?: string | null;
          semester_end?: string | null;
          account_visibility?: Database['public']['Enums']['account_visibility'];
          created_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'profiles_id_fkey';
            columns: ['id'];
            referencedRelation: 'users';
            referencedColumns: ['id'];
          },
        ];
      };

      trips: {
        Row: {
          id: string;
          owner_id: string;
          title: string;
          destination_city: string | null;
          destination_country: string | null;
          latitude: number | null;
          longitude: number | null;
          start_date: string | null;
          end_date: string | null;
          status: Database['public']['Enums']['trip_status'];
          visibility: Database['public']['Enums']['trip_visibility'];
          notes: string | null;
          rating: number | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          owner_id: string;
          title: string;
          destination_city?: string | null;
          destination_country?: string | null;
          latitude?: number | null;
          longitude?: number | null;
          start_date?: string | null;
          end_date?: string | null;
          status?: Database['public']['Enums']['trip_status'];
          visibility?: Database['public']['Enums']['trip_visibility'];
          notes?: string | null;
          rating?: number | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          owner_id?: string;
          title?: string;
          destination_city?: string | null;
          destination_country?: string | null;
          latitude?: number | null;
          longitude?: number | null;
          start_date?: string | null;
          end_date?: string | null;
          status?: Database['public']['Enums']['trip_status'];
          visibility?: Database['public']['Enums']['trip_visibility'];
          notes?: string | null;
          rating?: number | null;
          created_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'trips_owner_id_fkey';
            columns: ['owner_id'];
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };

      trip_segments: {
        Row: {
          id: string;
          trip_id: string;
          type: Database['public']['Enums']['segment_type'];
          status: Database['public']['Enums']['segment_status'];
          provider: string | null;
          confirmation_ref: string | null;
          starts_at: string | null;
          ends_at: string | null;
          cost_cents: number | null;
          currency: string;
          details: Json;
          created_at: string;
        };
        Insert: {
          id?: string;
          trip_id: string;
          type: Database['public']['Enums']['segment_type'];
          status?: Database['public']['Enums']['segment_status'];
          provider?: string | null;
          confirmation_ref?: string | null;
          starts_at?: string | null;
          ends_at?: string | null;
          cost_cents?: number | null;
          currency?: string;
          details?: Json;
          created_at?: string;
        };
        Update: {
          id?: string;
          trip_id?: string;
          type?: Database['public']['Enums']['segment_type'];
          status?: Database['public']['Enums']['segment_status'];
          provider?: string | null;
          confirmation_ref?: string | null;
          starts_at?: string | null;
          ends_at?: string | null;
          cost_cents?: number | null;
          currency?: string;
          details?: Json;
          created_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'trip_segments_trip_id_fkey';
            columns: ['trip_id'];
            referencedRelation: 'trips';
            referencedColumns: ['id'];
          },
        ];
      };

      trip_participants: {
        Row: {
          trip_id: string;
          user_id: string;
          role: Database['public']['Enums']['participant_role'];
          invite_status: Database['public']['Enums']['invite_status'];
          created_at: string;
        };
        Insert: {
          trip_id: string;
          user_id: string;
          role?: Database['public']['Enums']['participant_role'];
          invite_status?: Database['public']['Enums']['invite_status'];
          created_at?: string;
        };
        Update: {
          trip_id?: string;
          user_id?: string;
          role?: Database['public']['Enums']['participant_role'];
          invite_status?: Database['public']['Enums']['invite_status'];
          created_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'trip_participants_trip_id_fkey';
            columns: ['trip_id'];
            referencedRelation: 'trips';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'trip_participants_user_id_fkey';
            columns: ['user_id'];
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };

      trip_shares: {
        Row: {
          trip_id: string;
          shared_with_user_id: string;
          created_at: string;
        };
        Insert: {
          trip_id: string;
          shared_with_user_id: string;
          created_at?: string;
        };
        Update: {
          trip_id?: string;
          shared_with_user_id?: string;
          created_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'trip_shares_trip_id_fkey';
            columns: ['trip_id'];
            referencedRelation: 'trips';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'trip_shares_shared_with_user_id_fkey';
            columns: ['shared_with_user_id'];
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };

      recommendations: {
        Row: {
          id: string;
          trip_id: string;
          place_name: string;
          category: string | null;
          rating: number | null;
          note: string | null;
          latitude: number | null;
          longitude: number | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          trip_id: string;
          place_name: string;
          category?: string | null;
          rating?: number | null;
          note?: string | null;
          latitude?: number | null;
          longitude?: number | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          trip_id?: string;
          place_name?: string;
          category?: string | null;
          rating?: number | null;
          note?: string | null;
          latitude?: number | null;
          longitude?: number | null;
          created_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'recommendations_trip_id_fkey';
            columns: ['trip_id'];
            referencedRelation: 'trips';
            referencedColumns: ['id'];
          },
        ];
      };

      follows: {
        Row: {
          follower_id: string;
          following_id: string;
          status: Database['public']['Enums']['follow_status'];
          created_at: string;
        };
        Insert: {
          follower_id: string;
          following_id: string;
          status?: Database['public']['Enums']['follow_status'];
          created_at?: string;
        };
        Update: {
          follower_id?: string;
          following_id?: string;
          status?: Database['public']['Enums']['follow_status'];
          created_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'follows_follower_id_fkey';
            columns: ['follower_id'];
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'follows_following_id_fkey';
            columns: ['following_id'];
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };

      destinations: {
        Row: {
          id: string;
          city: string;
          country: string;
          latitude: number | null;
          longitude: number | null;
          region: string | null;
        };
        // Read-only through the API — there is no INSERT policy. These types
        // exist for migration-based seeding only.
        Insert: {
          id?: string;
          city: string;
          country: string;
          latitude?: number | null;
          longitude?: number | null;
          region?: string | null;
        };
        Update: {
          id?: string;
          city?: string;
          country?: string;
          latitude?: number | null;
          longitude?: number | null;
          region?: string | null;
        };
        Relationships: [];
      };
    };

    Views: Record<never, never>;

    Functions: {
      is_accepted_follower: {
        Args: { _follower: string; _following: string };
        Returns: boolean;
      };
      account_is_private: {
        Args: { _user_id: string };
        Returns: boolean;
      };
      is_trip_participant: {
        Args: { _trip_id: string };
        Returns: boolean;
      };
      is_trip_shared_with_me: {
        Args: { _trip_id: string };
        Returns: boolean;
      };
      is_trip_owner: {
        Args: { _trip_id: string };
        Returns: boolean;
      };
      can_read_trip: {
        Args: { _trip_id: string };
        Returns: boolean;
      };
    };

    Enums: {
      account_visibility: 'public' | 'private';
      trip_status: 'idea' | 'planned' | 'booked' | 'completed';
      trip_visibility: 'public' | 'followers' | 'custom' | 'private';
      segment_type: 'flight' | 'train' | 'bus' | 'stay' | 'reservation';
      segment_status: 'wanted' | 'booked';
      participant_role: 'owner' | 'companion';
      invite_status: 'invited' | 'accepted' | 'declined';
      follow_status: 'pending' | 'accepted';
    };

    CompositeTypes: Record<never, never>;
  };
}
