-- RUN THIS IN SUPABASE SQL EDITOR
-- Enhancing the schema for Vehicle Entry and Daily Help functionality

-- 1. Add vehicle tracking to visitors
ALTER TABLE visitors ADD COLUMN IF NOT EXISTS vehicle_number TEXT;

-- 2. Add vehicle logs for general vehicle tracking (optional but better for production)
CREATE TABLE IF NOT EXISTS vehicle_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_number TEXT NOT NULL,
  vehicle_type TEXT, -- 'car', 'bike', 'commercial'
  entry_time TIMESTAMPTZ DEFAULT now(),
  exit_time TIMESTAMPTZ,
  flat_number TEXT,
  driver_name TEXT,
  purpose TEXT,
  guard_id UUID REFERENCES users(id),
  society_id UUID REFERENCES societies(id),
  status TEXT DEFAULT 'Inside' -- 'Inside', 'Out'
);

-- 3. Enable RLS for vehicle logs
ALTER TABLE vehicle_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Guards manage vehicle logs" ON vehicle_logs
  FOR ALL USING (
    society_id = (SELECT society_id FROM users WHERE id = auth.uid())
    AND EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('guard', 'admin'))
  );

-- 4. Enable RLS for daily help attendance
ALTER TABLE daily_help ENABLE ROW LEVEL SECURITY;
ALTER TABLE help_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all for authenticated" ON daily_help;
DROP POLICY IF EXISTS "Allow all for authenticated" ON help_attendance;

CREATE POLICY "Guards manage daily help" ON daily_help
  FOR ALL USING (
    society_id = (SELECT society_id FROM users WHERE id = auth.uid())
    AND EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('guard', 'admin'))
  );

CREATE POLICY "Guards manage help attendance" ON help_attendance
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM daily_help 
      WHERE id = help_id 
      AND society_id = (SELECT society_id FROM users WHERE id = auth.uid())
    )
    AND EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('guard', 'admin'))
  );
