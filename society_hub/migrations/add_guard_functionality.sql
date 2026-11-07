-- RUN THIS IN SUPABASE SQL EDITOR
-- Enhancing the schema for Security Guard functionality

-- 1. Add tracking columns to visitors
ALTER TABLE visitors ADD COLUMN IF NOT EXISTS checked_in_at TIMESTAMPTZ;
ALTER TABLE visitors ADD COLUMN IF NOT EXISTS checked_out_at TIMESTAMPTZ;
ALTER TABLE visitors ADD COLUMN IF NOT EXISTS guard_id UUID REFERENCES users(id);

-- 2. Update RLS for Guards
-- First, drop the old permissive policy if it exists
DROP POLICY IF EXISTS "Allow all for authenticated" ON visitors;
DROP POLICY IF EXISTS "Guards can manage society visitors" ON visitors;

-- Now create a strict policy for Visitors
CREATE POLICY "Public visitor view" ON visitors
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Residents create visitors" ON visitors
  FOR INSERT WITH CHECK (auth.uid() = (SELECT id FROM users WHERE id = auth.uid()));

CREATE POLICY "Guards manage society visitors" ON visitors
  FOR ALL USING (
    society_id = (SELECT society_id FROM users WHERE id = auth.uid())
    AND EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('guard', 'admin'))
  );

-- 3. (Optional) Update user role documentation/constraints if you use them
-- The app logic will handle 'guard' role automatically now.

-- 4. Verify table structure
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'visitors';
