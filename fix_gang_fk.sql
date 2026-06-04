-- =====================================================
-- إصلاح: إضافة المفتاح الخارجي بين اللاعبين والعصابات
-- شغّل هذا مرة واحدة في Supabase → SQL Editor
-- =====================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'players_gang_id_fkey'
  ) THEN
    ALTER TABLE public.players
      ADD CONSTRAINT players_gang_id_fkey
      FOREIGN KEY (gang_id) REFERENCES public.gangs(id) ON DELETE SET NULL;
  END IF;
END $$;

-- تحديث ذاكرة المخطط في PostgREST فوراً
NOTIFY pgrst, 'reload schema';
