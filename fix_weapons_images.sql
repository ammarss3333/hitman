-- =====================================================
-- إضافة صور حقيقية للأسلحة (Wikimedia Commons)
-- =====================================================

ALTER TABLE public.weapons
  ADD COLUMN IF NOT EXISTS image_url TEXT;

-- ===== أسلحة بيضاء =====
UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/9/98/USMC-120713-M-PH863-003.jpg/320px-USMC-120713-M-PH863-003.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000001'; -- Ka-Bar

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/2/23/Brass_Knuckles.jpg/320px-Brass_Knuckles.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000002'; -- Brass Knuckles

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3b/Police_Baton.jpg/320px-Police_Baton.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000003'; -- Baton

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/6/6d/Machete.jpg/320px-Machete.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000004'; -- Machete

-- ===== مسدسات =====
UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b0/Glock_17_2.jpg/320px-Glock_17_2.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000010'; -- Glock 17

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4a/Beretta_92FS_-_left_side.jpg/320px-Beretta_92FS_-_left_side.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000011'; -- Beretta 92FS

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/ca/Sig_Sauer_P226.jpg/320px-Sig_Sauer_P226.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000012'; -- SIG P226

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/36/Colt_1911_45_ACP.jpg/320px-Colt_1911_45_ACP.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000013'; -- Colt 1911

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f4/Desert_Eagle_-_50AE.jpg/320px-Desert_Eagle_-_50AE.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000014'; -- Desert Eagle

-- ===== بنادق خردق =====
UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/0/08/Mossberg_500_-_left_side.jpg/320px-Mossberg_500_-_left_side.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000020'; -- Mossberg 500

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/38/SPAS-12_-_left_side.jpg/320px-SPAS-12_-_left_side.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000021'; -- SPAS-12

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a8/AA-12_automatic_shotgun.jpg/320px-AA-12_automatic_shotgun.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000022'; -- AA-12

-- ===== رشاشات خفيفة =====
UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/cf/HK_MP5A3.jpg/320px-HK_MP5A3.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000030'; -- MP5

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f3/Uzi_with_wooden_stock.jpg/320px-Uzi_with_wooden_stock.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000031'; -- Uzi

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/6/63/FN_P90.jpg/320px-FN_P90.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000032'; -- FN P90

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a1/KRISS_Vector_SMG.jpg/320px-KRISS_Vector_SMG.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000033'; -- KRISS Vector

-- ===== بنادق هجومية =====
UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/38/AK-47_type_II_Part_DM-ST-89-01131.jpg/320px-AK-47_type_II_Part_DM-ST-89-01131.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000040'; -- AK-47

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/6/6e/M4-Carbine_noBG.png/320px-M4-Carbine_noBG.png'
  WHERE id = 'b0000001-0000-0000-0000-000000000041'; -- M4A1

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e5/FN_SCAR-H_-_left_side.jpg/320px-FN_SCAR-H_-_left_side.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000042'; -- FN SCAR-H

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/46/HK416.jpg/320px-HK416.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000043'; -- HK416

-- ===== قناصة =====
UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/2/22/AWSM_f_2.jpg/320px-AWSM_f_2.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000050'; -- AWM

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8f/Barrett_M82A1_2.jpg/320px-Barrett_M82A1_2.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000051'; -- Barrett M82A1

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/9/98/CheyTac_M200_Intervention.jpg/320px-CheyTac_M200_Intervention.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000052'; -- CheyTac M200

-- ===== دروع =====
UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/Bulletproof_vest_-_level_II.jpg/320px-Bulletproof_vest_-_level_II.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000060'; -- Vest Basic

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9b/MOLLE_vest.jpg/320px-MOLLE_vest.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000061'; -- Vest Tactical

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Dragon_Skin_body_armor.jpg/320px-Dragon_Skin_body_armor.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000062'; -- Vest Military

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a9/Interceptor_Body_Armor.jpg/320px-Interceptor_Body_Armor.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000063'; -- Vest Heavy

UPDATE public.weapons SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/EOD_suit.jpg/320px-EOD_suit.jpg'
  WHERE id = 'b0000001-0000-0000-0000-000000000064'; -- Exo Armor

NOTIFY pgrst, 'reload schema';
