-- Migration: 20260917000001_initial_billy_schema.sql
-- Description: Launch schema for Billy The Viewer production persistence.
-- Notes: Contains tables for profiles, advertiser_profiles, advertiser_members, campaigns,
--        creatives, recognition_signatures (with pgvector), campaign_locations, recognition_events,
--        and Supabase Storage bucket/RLS configuration for 'ad-creatives'.
--        Primary keys for campaigns, creatives, signatures are TEXT (defaulting to UUID string)
--        to guarantee 100% compatibility with existing Flutter string identifiers.
--        DO NOT MODIFY RECOGNITION ALGORITHMS. 192-dim vectors match VisionService exactly.

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- 2. ENUMS
DO $$ BEGIN
    CREATE TYPE advertiser_type AS ENUM ('individual', 'organization');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE verification_status AS ENUM ('unverified', 'pending', 'verified', 'rejected');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE member_role AS ENUM ('owner', 'admin', 'campaign_manager', 'analyst');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE campaign_status AS ENUM ('draft', 'processing', 'active', 'paused', 'expired');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE ad_medium_type AS ENUM ('universal', 'billboard', 'screen', 'flyer');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- 3. PROFILES TABLE (Mirrors auth.users, minimal without email duplication)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. ADVERTISER PROFILES TABLE (Unified Individual & Organization Tenants)
CREATE TABLE IF NOT EXISTS public.advertiser_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    account_type advertiser_type NOT NULL DEFAULT 'individual',
    display_name TEXT NOT NULL,
    legal_name TEXT,
    contact_email TEXT NOT NULL,
    contact_phone TEXT,
    tax_or_business_id TEXT,
    website_url TEXT,
    verification_status verification_status NOT NULL DEFAULT 'unverified',
    billing_customer_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Constraint: Organizations must have a non-empty legal_name
    CONSTRAINT chk_org_identity CHECK (
        account_type = 'individual' OR (legal_name IS NOT NULL AND length(trim(legal_name)) > 0)
    )
);

-- 5. ADVERTISER MEMBERS TABLE (Team Collaboration for Organizations ONLY)
CREATE TABLE IF NOT EXISTS public.advertiser_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    advertiser_id UUID NOT NULL REFERENCES public.advertiser_profiles(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role member_role NOT NULL DEFAULT 'campaign_manager',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(advertiser_id, user_id)
);

-- Constraint function to prevent adding members to individual advertiser accounts
CREATE OR REPLACE FUNCTION public.check_advertiser_is_organization()
RETURNS TRIGGER AS $$
DECLARE
    adv_type advertiser_type;
BEGIN
    SELECT account_type INTO adv_type FROM public.advertiser_profiles WHERE id = NEW.advertiser_id;
    IF adv_type <> 'organization' THEN
        RAISE EXCEPTION 'Individual advertiser accounts cannot have team members.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_advertiser_member ON public.advertiser_members;
CREATE TRIGGER trg_check_advertiser_member
    BEFORE INSERT OR UPDATE ON public.advertiser_members
    FOR EACH ROW
    EXECUTE FUNCTION public.check_advertiser_is_organization();

-- 6. CAMPAIGNS TABLE (Campaign Identity & Flight Schedules - TEXT ID for String compatibility)
CREATE TABLE IF NOT EXISTS public.campaigns (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    advertiser_id UUID NOT NULL REFERENCES public.advertiser_profiles(id) ON DELETE RESTRICT,
    ad_name TEXT NOT NULL,
    brand_name TEXT NOT NULL,
    destination_url TEXT NOT NULL,
    status campaign_status NOT NULL DEFAULT 'draft',
    medium_type ad_medium_type NOT NULL DEFAULT 'universal',
    start_at TIMESTAMPTZ,
    end_at TIMESTAMPTZ,
    is_demo BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. CREATIVES TABLE (Creative File Metadata & Storage References - TEXT ID)
CREATE TABLE IF NOT EXISTS public.creatives (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    campaign_id TEXT NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL,
    public_url TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type TEXT NOT NULL DEFAULT 'image/jpeg',
    width INT,
    height INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 8. RECOGNITION SIGNATURES TABLE (192-dim Visual Vectors & Normalized OCR - TEXT ID)
CREATE TABLE IF NOT EXISTS public.recognition_signatures (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    creative_id TEXT NOT NULL REFERENCES public.creatives(id) ON DELETE CASCADE,
    campaign_id TEXT NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    version TEXT NOT NULL DEFAULT '1.0',
    visual_vector vector(192) NOT NULL,
    raw_ocr_text TEXT,
    normalized_ocr_text TEXT,
    extracted_words TEXT[] DEFAULT '{}',
    algorithm TEXT NOT NULL DEFAULT 'relative_spatial_gradient_192',
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 9. CAMPAIGN LOCATIONS TABLE (Geofences for Out-of-Home Advertising)
CREATE TABLE IF NOT EXISTS public.campaign_locations (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    campaign_id TEXT NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    label TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius_meters DOUBLE PRECISION NOT NULL DEFAULT 300.0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 10. RECOGNITION EVENTS TABLE (Audit Log / Analytics for Verified Scans)
CREATE TABLE IF NOT EXISTS public.recognition_events (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    campaign_id TEXT NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    viewer_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    recognition_mode TEXT NOT NULL,
    visual_similarity DOUBLE PRECISION,
    text_similarity DOUBLE PRECISION,
    combined_score DOUBLE PRECISION NOT NULL,
    distinctive_tokens_count INT DEFAULT 0,
    verified_by_gemini BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 11. INDEXES FOR PERFORMANCE
CREATE INDEX IF NOT EXISTS idx_campaigns_lookup ON public.campaigns (status, start_at, end_at);
CREATE INDEX IF NOT EXISTS idx_campaigns_advertiser ON public.campaigns (advertiser_id);
CREATE INDEX IF NOT EXISTS idx_creatives_campaign ON public.creatives (campaign_id);
CREATE INDEX IF NOT EXISTS idx_signatures_campaign ON public.recognition_signatures (campaign_id);
CREATE INDEX IF NOT EXISTS idx_signatures_ocr ON public.recognition_signatures USING gin (extracted_words);
CREATE INDEX IF NOT EXISTS idx_locations_active ON public.campaign_locations (latitude, longitude) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_events_campaign_created ON public.recognition_events (campaign_id, created_at);

-- 12. RECOGNITION VIEW: Filters only eligible active campaigns
-- Declared WITH (security_invoker = true) so querying user's RLS policies apply
CREATE OR REPLACE VIEW public.active_recognition_candidates
WITH (security_invoker = true) AS
SELECT 
    c.id AS campaign_id,
    c.advertiser_id,
    c.ad_name,
    c.brand_name,
    c.destination_url,
    c.medium_type,
    c.is_demo,
    cr.id AS creative_id,
    cr.public_url AS creative_url,
    sig.id AS signature_id,
    sig.visual_vector,
    sig.normalized_ocr_text,
    sig.version AS signature_version
FROM public.campaigns c
JOIN public.creatives cr ON cr.campaign_id = c.id
JOIN public.recognition_signatures sig ON sig.creative_id = cr.id
WHERE c.status = 'active'
  AND (c.start_at IS NULL OR c.start_at <= now())
  AND (c.end_at IS NULL OR c.end_at >= now());

-- 13. ROW LEVEL SECURITY (RLS) POLICIES
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.advertiser_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.advertiser_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.creatives ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recognition_signatures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campaign_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recognition_events ENABLE ROW LEVEL SECURITY;

-- Helper function: Is current user a member or creator of advertiser
-- Uses SECURITY DEFINER with search_path = public to avoid search path injection
CREATE OR REPLACE FUNCTION public.is_advertiser_member(adv_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.advertiser_profiles WHERE id = adv_id AND created_by = auth.uid()
    ) OR EXISTS (
        SELECT 1 FROM public.advertiser_members WHERE advertiser_id = adv_id AND user_id = auth.uid()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Profiles: Users manage own profile
CREATE POLICY "Users can manage own profile"
    ON public.profiles FOR ALL
    USING (id = auth.uid());

-- Advertiser Profiles: Direct membership lookup (NO RECURSION)
CREATE POLICY "Advertisers can view their own profile"
    ON public.advertiser_profiles FOR SELECT
    USING (
        created_by = auth.uid()
        OR id IN (
            SELECT advertiser_id
            FROM public.advertiser_members
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create advertiser profiles"
    ON public.advertiser_profiles FOR INSERT
    WITH CHECK (created_by = auth.uid());

CREATE POLICY "Advertisers can update their own profile"
    ON public.advertiser_profiles FOR UPDATE
    USING (
        created_by = auth.uid()
        OR id IN (
            SELECT advertiser_id
            FROM public.advertiser_members
            WHERE user_id = auth.uid()
        )
    );

-- Advertiser Members: Organization members can view team
CREATE POLICY "Members can view their organization teams"
    ON public.advertiser_members FOR SELECT
    USING (user_id = auth.uid() OR public.is_advertiser_member(advertiser_id));

CREATE POLICY "Admins can manage organization members"
    ON public.advertiser_members FOR ALL
    USING (public.is_advertiser_member(advertiser_id));

-- Campaigns: Advertisers have full CRUD, Viewers can read active
CREATE POLICY "Advertisers manage own campaigns"
    ON public.campaigns FOR ALL
    USING (public.is_advertiser_member(advertiser_id));

CREATE POLICY "Viewers can read active campaigns"
    ON public.campaigns FOR SELECT
    USING (status = 'active' AND (start_at IS NULL OR start_at <= now()) AND (end_at IS NULL OR end_at >= now()));

-- Creatives: Advertisers manage own, Viewers can read active
CREATE POLICY "Advertisers manage own creatives"
    ON public.creatives FOR ALL
    USING (campaign_id IN (SELECT id FROM public.campaigns WHERE public.is_advertiser_member(advertiser_id)));

CREATE POLICY "Viewers can view active creatives"
    ON public.creatives FOR SELECT
    USING (campaign_id IN (
        SELECT id FROM public.campaigns 
        WHERE status = 'active' AND (start_at IS NULL OR start_at <= now()) AND (end_at IS NULL OR end_at >= now())
    ));

-- Recognition Signatures: Read-only for viewers on active campaigns
CREATE POLICY "Advertisers manage own signatures"
    ON public.recognition_signatures FOR ALL
    USING (campaign_id IN (SELECT id FROM public.campaigns WHERE public.is_advertiser_member(advertiser_id)));

CREATE POLICY "Viewers can read active signatures"
    ON public.recognition_signatures FOR SELECT
    USING (campaign_id IN (
        SELECT id FROM public.campaigns 
        WHERE status = 'active' AND (start_at IS NULL OR start_at <= now()) AND (end_at IS NULL OR end_at >= now())
    ));

-- Campaign Locations: Public read for active campaigns
CREATE POLICY "Anyone can read locations for active campaigns"
    ON public.campaign_locations FOR SELECT
    USING (is_active = true AND campaign_id IN (
        SELECT id FROM public.campaigns 
        WHERE status = 'active' AND (start_at IS NULL OR start_at <= now()) AND (end_at IS NULL OR end_at >= now())
    ));

CREATE POLICY "Advertisers manage own locations"
    ON public.campaign_locations FOR ALL
    USING (campaign_id IN (SELECT id FROM public.campaigns WHERE public.is_advertiser_member(advertiser_id)));

-- Recognition Events: Protected insert only for active campaigns via authenticated or anonymous sessions
CREATE POLICY "Authenticated or anonymous sessions can record events for active campaigns"
    ON public.recognition_events FOR INSERT
    WITH CHECK (
        (auth.role() = 'authenticated' OR auth.role() = 'anon')
        AND campaign_id IN (
            SELECT id FROM public.campaigns
            WHERE status = 'active'
              AND (start_at IS NULL OR start_at <= now())
              AND (end_at IS NULL OR end_at >= now())
        )
    );

CREATE POLICY "Advertisers can view their campaign events"
    ON public.recognition_events FOR SELECT
    USING (campaign_id IN (SELECT id FROM public.campaigns WHERE public.is_advertiser_member(advertiser_id)));

-- RPC for structured, verified recognition event logging
CREATE OR REPLACE FUNCTION public.record_recognition_event(
    p_campaign_id TEXT,
    p_mode TEXT,
    p_combined_score DOUBLE PRECISION,
    p_visual_sim DOUBLE PRECISION DEFAULT 0.0,
    p_text_sim DOUBLE PRECISION DEFAULT 0.0,
    p_distinctive_tokens INT DEFAULT 0,
    p_verified_by_gemini BOOLEAN DEFAULT false
)
RETURNS TEXT AS $$
DECLARE
    new_event_id TEXT;
BEGIN
    -- Validate that campaign is active and unexpired
    IF NOT EXISTS (
        SELECT 1 FROM public.campaigns
        WHERE id = p_campaign_id
          AND status = 'active'
          AND (start_at IS NULL OR start_at <= now())
          AND (end_at IS NULL OR end_at >= now())
    ) THEN
        RAISE EXCEPTION 'Cannot record event: campaign % is not active or is expired.', p_campaign_id;
    END IF;

    INSERT INTO public.recognition_events (
        campaign_id,
        viewer_user_id,
        recognition_mode,
        visual_similarity,
        text_similarity,
        combined_score,
        distinctive_tokens_count,
        verified_by_gemini
    ) VALUES (
        p_campaign_id,
        auth.uid(),
        p_mode,
        p_visual_sim,
        p_text_sim,
        p_combined_score,
        p_distinctive_tokens,
        p_verified_by_gemini
    ) RETURNING id INTO new_event_id;

    RETURN new_event_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 14. SUPABASE STORAGE: 'ad-creatives' BUCKET & RLS POLICIES
-- Insert the public ad-creatives bucket if it does not already exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'ad-creatives',
    'ad-creatives',
    true,
    10485760, -- 10MB file size limit
    ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

-- Storage RLS: Public READ for all creative images
CREATE POLICY "Public Read Access on ad-creatives"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'ad-creatives');

-- Storage RLS: INSERT restricted to advertiser's own namespace: {advertiser_id}/...
-- Verified against public.is_advertiser_member()
CREATE POLICY "Advertisers can upload creatives to own namespace"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'ad-creatives'
        AND auth.role() = 'authenticated'
        AND public.is_advertiser_member((storage.foldername(name))[1]::uuid)
    );

-- Storage RLS: UPDATE restricted to authorized advertiser
CREATE POLICY "Advertisers can update creatives in own namespace"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'ad-creatives'
        AND auth.role() = 'authenticated'
        AND public.is_advertiser_member((storage.foldername(name))[1]::uuid)
    );

-- Storage RLS: DELETE restricted to authorized advertiser
CREATE POLICY "Advertisers can delete creatives in own namespace"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'ad-creatives'
        AND auth.role() = 'authenticated'
        AND public.is_advertiser_member((storage.foldername(name))[1]::uuid)
    );
