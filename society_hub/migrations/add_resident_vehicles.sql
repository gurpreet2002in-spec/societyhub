-- RUN THIS IN SUPABASE SQL EDITOR
-- Adding Resident Vehicle Management

-- 1. Create resident_vehicles table
CREATE TABLE IF NOT EXISTS resident_vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_number TEXT NOT NULL,
  vehicle_type TEXT NOT NULL, -- 'car', 'bike', 'other'
  brand_model TEXT,
  color TEXT,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  society_id UUID REFERENCES societies(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(vehicle_number, society_id)
);

-- 2. Enhance parking_slots to link to resident_vehicles (optional but cleaner)
-- ALTER TABLE parking_slots ADD COLUMN IF NOT EXISTS resident_vehicle_id UUID REFERENCES resident_vehicles(id);

-- 3. Enable RLS
ALTER TABLE resident_vehicles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Residents can manage their own vehicles" ON resident_vehicles
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Guards can view all resident vehicles" ON resident_vehicles
  FOR SELECT USING (
    society_id = (SELECT society_id FROM users WHERE id = auth.uid())
    AND EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('guard', 'admin'))
  );

-- 4. Add a flag to vehicle_logs to identify resident vehicles
ALTER TABLE vehicle_logs ADD COLUMN IF NOT EXISTS is_resident_vehicle BOOLEAN DEFAULT false;
ALTER TABLE vehicle_logs ADD COLUMN IF NOT EXISTS resident_vehicle_id UUID REFERENCES resident_vehicles(id);
