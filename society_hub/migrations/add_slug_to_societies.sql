-- RUN THIS IN SUPABASE SQL EDITOR
-- This script adds the missing 'slug' column to your existing societies table

-- 1. Add the slug column
ALTER TABLE societies ADD COLUMN IF NOT EXISTS slug TEXT UNIQUE;

-- 2. (Optional) Populate slugs for existing societies that don't have one
-- This converts "Ekta Society" to "ekta_society"
UPDATE societies 
SET slug = lower(regexp_replace(name, '[^a-zA-Z0-9\s]+', '', 'g')); -- First remove special chars

UPDATE societies 
SET slug = lower(regexp_replace(slug, '\s+', '_', 'g'))
WHERE slug IS NOT NULL;

-- 3. Verify
SELECT id, name, slug FROM societies;
