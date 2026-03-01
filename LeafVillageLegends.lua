LeafVE_DB = LeafVE_DB or {}
LeafVE_GlobalDB = LeafVE_GlobalDB or {}

-- Lua 5.0 compatibility: string.match was introduced in Lua 5.1
if not string.match then
  string.match = function(s, pattern, init)
    local t = {string.find(s, pattern, init)}
    if not t[1] then return nil end
    if table.getn(t) > 2 then
      local captures = {}
      for i = 3, table.getn(t) do
        captures[i - 2] = t[i]
      end
      return unpack(captures)
    end
    return string.sub(s, t[1], t[2])
  end
end

LeafVE = LeafVE or {}
LeafVE.name = "LeafVillageLegends"
LeafVE.prefix = "LeafVE"
LeafVE.version = "11.0"
-- Minimum peer version whose synced data is accepted.  Bump this whenever a
-- version introduces a breaking data-format change so that older clients
-- cannot corrupt the shared leaderboard / badge data.
LeafVE.minCompatVersion = "11.0"

local SEP = "\31"
local SECONDS_PER_DAY = 86400
local SECONDS_PER_HOUR = 3600
local GROUP_MIN_TIME = 300
local GROUP_COOLDOWN = 900
local GROUP_POINT_INTERVAL = 1200
local GUILD_ROSTER_CACHE_DURATION = 30
local SHOUTOUT_MAX_PER_DAY = 2
local LBOARD_RESYNC_COOLDOWN = 30  -- seconds between outgoing LBOARDREQ messages
local LBOARD_RESPOND_COOLDOWN = 30 -- seconds between responses to LBOARDREQ
local SHOUT_SYNC_RESPOND_COOLDOWN = 30 -- seconds between shoutout history sync responses
local DEFAULT_ACHIEVEMENT_POINTS = 10  -- fallback points per achievement when metadata is unavailable

local GEAR_BROADCAST_THROTTLE  = 10  -- seconds between gear broadcasts
local STATS_BROADCAST_THROTTLE = 30  -- seconds between BCS stats broadcasts
local GEAR_SLOT_NAMES = {
  "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
  "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
  "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
  "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}
local GEAR_SLOT_LABELS = {
  HeadSlot = "Head", NeckSlot = "Neck", ShoulderSlot = "Shoulder", BackSlot = "Back",
  ChestSlot = "Chest", WristSlot = "Wrist", HandsSlot = "Hands", WaistSlot = "Waist",
  LegsSlot = "Legs", FeetSlot = "Feet", Finger0Slot = "Ring 1", Finger1Slot = "Ring 2",
  Trinket0Slot = "Trinket 1", Trinket1Slot = "Trinket 2", MainHandSlot = "Main Hand",
  SecondaryHandSlot = "Off Hand", RangedSlot = "Ranged",
}
local GEAR_SLOT_IDS = {
  HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, BackSlot = 15, ChestSlot = 5,
  WristSlot = 9, HandsSlot = 10, WaistSlot = 6, LegsSlot = 7, FeetSlot = 8,
  Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13, Trinket1Slot = 14,
  MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18,
}

local INSTANCE_BOSS_POINTS = 10       -- dungeon boss
local RAID_BOSS_POINTS = 25           -- raid boss
local BOSS_KILL_DEDUP_WINDOW = 10     -- seconds to suppress duplicate boss-kill awards
local INSTANCE_COMPLETION_POINTS = 10 -- dungeon completion (flat)
local RAID_COMPLETION_POINTS = 25     -- raid completion (flat)
local INSTANCE_MIN_PRESENCE_PCT = 0.5  -- must be present for ≥50% of run time
local INSTANCE_MAX_DAILY = 20
local QUEST_POINTS = 10
local QUEST_MAX_DAILY = 0
local LEAF_POINT_DAILY_CAP = 700
local GROUP_POINTS = 10               -- points awarded per guild group tick
local GROUP_POINTS_DAILY_CAP = 0      -- no separate group cap; global daily cap applies

-- Named constants for the three point categories.  Use these everywhere instead
-- of raw "L"/"G"/"S" strings to prevent accidental mis-categorisation.
local POINT_TYPE_LOGIN    = "L"  -- daily login and login-streak bonus
local POINT_TYPE_GAMEPLAY = "G"  -- quests, dungeons, raids, boss kills, guild grouping
local POINT_TYPE_SOCIAL   = "S"  -- shoutout received (the ONLY activity that awards S)

local SEASON_REWARD_1 = 10
local SEASON_REWARD_2 = 5
local SEASON_REWARD_3 = 3
local SEASON_REWARD_4 = 2
local SEASON_REWARD_5 = 1

-- Shoutout V2 constants
local SHOUTOUT_V2_POINTS = 10
local SHOUTOUT_GIVER_COOLDOWN = 3600   -- 1 hour between shoutouts from same giver
local SHOUTOUT_TARGET_COOLDOWN = 3600  -- 1 hour between receiving from same source
local SHOUTOUT_V2_MAX_PER_DAY = 3      -- max shoutouts a giver can give per day

-- Guild ranks that can access the Admin tab
local ADMIN_RANKS = { anbu = true, sannin = true, hokage = true }
local ACCESS_RANKS = {
  hokage = true,
  sannin = true,
  anbu = true,
  jonin = true,
  chunin = true,
  genin = true,
  ["academy student"] = true,
}

local VALID_GUILD_RANKS = {
  ["Academy Student"] = true,
  ["Genin"] = true,
  ["Chunin"] = true,
  ["Jonin"] = true,
  ["Anbu"] = true,
  ["Sannin"] = true,
  ["Hokage"] = true,
}

local LEAF_EMBLEM = "Interface\\Icons\\Spell_Nature_ResistNature"
local LEAF_FALLBACK = "Interface\\Icons\\Spell_Nature_ResistNature"
local QUEST_ICON = "Interface\\Icons\\INV_Misc_Book_09"

local PVP_RANK_ICONS = {
  [1] = "Interface\\PvPRankBadges\\PvPRank14",
  [2] = "Interface\\PvPRankBadges\\PvPRank13",
  [3] = "Interface\\PvPRankBadges\\PvPRank12",
  [4] = "Interface\\PvPRankBadges\\PvPRank11",
  [5] = "Interface\\PvPRankBadges\\PvPRank10",
}

local CLASS_ICONS = {
  WARRIOR = "Interface\\Icons\\Ability_Warrior_SavageBlow",
  PALADIN = "Interface\\Icons\\Spell_Holy_SealOfMight",
  HUNTER = "Interface\\Icons\\Ability_Hunter_AimedShot",
  ROGUE = "Interface\\Icons\\Ability_Rogue_Eviscerate",
  PRIEST = "Interface\\Icons\\Spell_Holy_PowerWordShield",
  SHAMAN = "Interface\\Icons\\Spell_Nature_LightningShield",
  MAGE = "Interface\\Icons\\Spell_Frost_IceStorm",
  WARLOCK = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
  DRUID = "Interface\\Icons\\Spell_Nature_Regeneration",
}

local CLASS_COLORS = {
  WARRIOR = {0.78, 0.61, 0.43}, PALADIN = {0.96, 0.55, 0.73}, HUNTER = {0.67, 0.83, 0.45},
  ROGUE = {1.00, 0.96, 0.41}, PRIEST = {1.00, 1.00, 1.00}, SHAMAN = {0.14, 0.35, 1.00},
  MAGE = {0.41, 0.80, 0.94}, WARLOCK = {0.58, 0.51, 0.79}, DRUID = {1.00, 0.49, 0.04},
}

-- Faction-specific flat background colour for the live player model portrait.
-- Each entry: {r, g, b}
local FACTION_BACKGROUNDS = {
  Horde    = {0.60, 0.05, 0.05},  -- Horde: red
  Alliance = {0.05, 0.25, 0.60},  -- Alliance: blue
}

local THEME = {
  bg = {0.05, 0.05, 0.06, 0.96}, insetBG = {0.02, 0.02, 0.03, 0.88},
  white = {0.96, 0.96, 0.96, 1.00}, leaf = {0.20, 0.78, 0.35, 1.00},
  leaf2 = {0.12, 0.55, 0.26, 1.00}, gold = {1.00, 0.82, 0.20, 1.00},
  border = {0.28, 0.28, 0.30, 1.00}, soft = {0.18, 0.18, 0.20, 1.00},
}

-- Badge quality tiers (WoW item-quality style)
local BADGE_QUALITY = {
  LEGENDARY  = "Legendary",
  EPIC       = "Epic",
  RARE       = "Rare",
  UNCOMMON   = "Uncommon",
  COMMON     = "Common",
}
local BADGE_QUALITY_COLORS = {
  Legendary = {1.00, 0.50, 0.00}, -- orange
  Epic      = {0.64, 0.21, 0.93}, -- purple
  Rare      = {0.00, 0.44, 0.87}, -- blue
  Uncommon  = {0.12, 1.00, 0.00}, -- green
  Common    = {0.62, 0.62, 0.62}, -- gray
}
local function GetBadgeQualityColor(quality)
  local c = BADGE_QUALITY_COLORS[quality] or BADGE_QUALITY_COLORS.Common
  return c[1], c[2], c[3]
end
local function GetBadgeQualityLabel(quality)
  return quality or BADGE_QUALITY.COMMON
end
local function RGBToHex(r, g, b)
  return string.format("%02X%02X%02X", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

BADGES = {
  -- Login & Activity (AUTO-TRACKED)
  {id = "first_login",      name = "First Steps",    desc = "Earn your first login point",   icon = "Interface\\Icons\\INV_Misc_Ribbon_01",            category = "Activity",    quality = BADGE_QUALITY.COMMON},
  {id = "login_streak_7",   name = "Dedicated",      desc = "Login 7 days in a row",         icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom",       category = "Activity",    quality = BADGE_QUALITY.UNCOMMON},
  {id = "login_streak_30",  name = "Truly Dedicated", desc = "Login 30 days in a row",       icon = "Interface\\Icons\\INV_Helmet_66",                 category = "Activity",    quality = BADGE_QUALITY.RARE},
  {id = "total_logins_100", name = "Regular",        desc = "Earn 100 login points",         icon = "Interface\\Icons\\Spell_Arcane_TeleportIronForge", category = "Activity",   quality = BADGE_QUALITY.UNCOMMON},
  
  -- Group Content (AUTO-TRACKED)
  {id = "first_group", name = "Team Player",     desc = "Complete your first guild group", icon = "Interface\\Icons\\INV_Banner_02",   category = "Social", quality = BADGE_QUALITY.COMMON},
  {id = "group_10",    name = "Groupie",         desc = "Complete 10 guild groups",        icon = "Interface\\Icons\\INV_Misc_Gift_02", category = "Social", quality = BADGE_QUALITY.UNCOMMON},
  {id = "group_50",    name = "Social Butterfly", desc = "Complete 50 guild groups",       icon = "Interface\\Icons\\INV_Banner_01",   category = "Social", quality = BADGE_QUALITY.RARE},
  {id = "group_100",   name = "Guild Hero",      desc = "Complete 100 guild groups",       icon = "Interface\\Icons\\INV_Crown_01",    category = "Social", quality = BADGE_QUALITY.EPIC},
  
  -- Shoutouts (AUTO-TRACKED)
  {id = "first_shoutout_given",    name = "Generous Soul",   desc = "Give your first shoutout",    icon = "Interface\\Icons\\INV_Letter_15",                    category = "Recognition", quality = BADGE_QUALITY.COMMON},
  {id = "first_shoutout_received", name = "Recognized",      desc = "Receive your first shoutout", icon = "Interface\\Icons\\INV_Misc_Note_01",                 category = "Recognition", quality = BADGE_QUALITY.COMMON},
  {id = "shoutout_received_10",    name = "Well Known",      desc = "Receive 10 shoutouts",        icon = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings", category = "Recognition", quality = BADGE_QUALITY.UNCOMMON},
  {id = "shoutout_received_50",    name = "Guild Celebrity", desc = "Receive 50 shoutouts",        icon = "Interface\\Icons\\INV_Crown_02",                     category = "Recognition", quality = BADGE_QUALITY.RARE},
  
  -- Point Milestones (AUTO-TRACKED)
  -- NOTE: Badge IDs are intentionally kept unchanged to preserve existing earned badge data.
  -- Thresholds and descriptions reflect the new increased requirements.
  {id = "total_500",   name = "Core Member",    desc = "Earn 2,500 total points",   icon = "Interface\\Icons\\INV_Jewelry_Talisman_07",  category = "Milestones", quality = BADGE_QUALITY.RARE},
  {id = "total_1000",  name = "Shinobi",        desc = "Earn 5,000 total points",  icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Red",  category = "Milestones", quality = BADGE_QUALITY.EPIC},
  {id = "total_2000",  name = "Elite Shinobi",  desc = "Earn 10,000 total points",  icon = "Interface\\Icons\\INV_Jewelry_Talisman_09",  category = "Milestones", quality = BADGE_QUALITY.EPIC},
  {id = "total_5000",  name = "Kage Candidate", desc = "Earn 25,000 total points",  icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black", category = "Milestones", quality = BADGE_QUALITY.EPIC},
  {id = "total_10000", name = "Hokage Legend",  desc = "Earn 50,000 total points", icon = "Interface\\Icons\\INV_Crown_02",        category = "Milestones", quality = BADGE_QUALITY.LEGENDARY},
  
  -- Attendance (AUTO-TRACKED if in raids)
  {id = "attendance_10", name = "Raider",       desc = "Attend 10 raids", icon = "Interface\\Icons\\Spell_Fire_Immolation",      category = "Raids", quality = BADGE_QUALITY.UNCOMMON},
  {id = "attendance_50", name = "Raid Veteran", desc = "Attend 50 raids", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black", category = "Raids", quality = BADGE_QUALITY.RARE},
  
  -- Time-based (AUTO-TRACKED)
  {id = "guild_age_30",  name = "One Month Strong",    desc = "Be in guild for 30 days",  icon = "Interface\\Icons\\INV_Helmet_66",                category = "Loyalty", quality = BADGE_QUALITY.UNCOMMON},
  {id = "guild_age_90",  name = "Three Month Veteran", desc = "Be in guild for 90 days",  icon = "Interface\\Icons\\INV_Shield_06",                category = "Loyalty", quality = BADGE_QUALITY.RARE},
  {id = "guild_age_365", name = "One Year Legend",     desc = "Be in guild for 1 year",   icon = "Interface\\Icons\\Ability_Creature_Cursed_02",   category = "Loyalty", quality = BADGE_QUALITY.LEGENDARY},
}

-- Known Classic WoW boss names for per-boss point awards (CHAT_MSG_COMBAT_HOSTILE_DEATH detection)
local KNOWN_BOSSES = {
  -- Ragefire Chasm
  ["Taragaman the Hungerer"] = true, ["Oggleflint"] = true,
  ["Jergosh the Invoker"] = true, ["Bazzalan"] = true,
  -- Wailing Caverns
  ["Lord Cobrahn"] = true, ["Lady Anacondra"] = true, ["Kresh"] = true,
  ["Deviate Faerie Dragon"] = true, ["Zandara Windhoof"] = true,
  ["Lord Pythas"] = true, ["Skum"] = true, ["Vangros"] = true,
  ["Lord Serpentis"] = true, ["Verdan the Everliving"] = true,
  ["Mutanus the Devourer"] = true,
  -- The Deadmines
  ["Jared Voss"] = true, ["Rhahk'Zor"] = true, ["Miner Johnson"] = true,
  ["Sneed"] = true, ["Sneed's Shredder"] = true, ["Gilnid"] = true,
  ["Masterpiece Harvester"] = true, ["Mr. Smite"] = true, ["Cookie"] = true,
  ["Captain Greenskin"] = true, ["Edwin VanCleef"] = true,
  -- Shadowfang Keep
  ["Rethilgore"] = true, ["Fel Steed"] = true, ["Razorclaw the Butcher"] = true,
  ["Baron Silverlaine"] = true, ["Commander Springvale"] = true,
  ["Sever"] = true, ["Odo the Blindwatcher"] = true, ["Deathsworn Captain"] = true,
  ["Fenrus the Devourer"] = true, ["Arugal's Voidwalker"] = true,
  ["Wolf Master Nandos"] = true, ["Archmage Arugal"] = true, ["Prelate Ironmane"] = true,
  -- Blackfathom Deeps
  ["Ghamoo-ra"] = true, ["Lady Sarevess"] = true, ["Gelihast"] = true,
  ["Baron Aquanis"] = true, ["Velthelaxx the Defiler"] = true,
  ["Twilight Lord Kelris"] = true, ["Old Serra'kis"] = true, ["Aku'mai"] = true,
  -- The Stockade
  ["Targorr the Dread"] = true, ["Kam Deepfury"] = true, ["Hamhock"] = true,
  ["Dextren Ward"] = true, ["Bazil Thredd"] = true, ["Bruegal Ironknuckle"] = true,
  -- Dragonmaw Retreat
  ["Gowlfang"] = true, ["Cavernweb Broodmother"] = true, ["Web Master Torkon"] = true,
  ["Garlok Flamekeeper"] = true, ["Halgan Redbrand"] = true,
  ["Slagfist Destroyer"] = true, ["Overlord Blackheart"] = true,
  ["Elder Hollowblood"] = true, ["Searistrasz"] = true, ["Zuluhed the Whacked"] = true,
  -- Gnomeregan
  ["Grubbis"] = true, ["Viscous Fallout"] = true, ["Electrocutioner 6000"] = true,
  ["Crowd Pummeler 9-60"] = true, ["Dark Iron Ambassador"] = true,
  ["Mekgineer Thermaplugg"] = true,
  -- Razorfen Kraul
  ["Aggem Thorncurse"] = true, ["Death Speaker Jargba"] = true,
  ["Overlord Ramtusk"] = true, ["Razorfen Spearhide"] = true,
  ["Agathelos the Raging"] = true, ["Blind Hunter"] = true,
  ["Charlga Razorflank"] = true, ["Earthcaller Halmgar"] = true, ["Rotthorn"] = true,
  -- The Crescent Grove
  ["Grovetender Engryss"] = true, ["Keeper Ranathos"] = true,
  ["High Priestess A'lathea"] = true, ["Fenektis the Deceiver"] = true,
  ["Master Raxxieth"] = true,
  -- Scarlet Monastery (Graveyard)
  ["Interrogator Vishas"] = true, ["Duke Dreadmoore"] = true, ["Scorn"] = true,
  ["Ironspine"] = true, ["Azshir the Sleepless"] = true, ["Fallen Champion"] = true,
  ["Bloodmage Thalnos"] = true,
  -- Scarlet Monastery (Library)
  ["Houndmaster Loksey"] = true, ["Brother Wystan"] = true, ["Arcanist Doan"] = true,
  -- Scarlet Monastery (Armory)
  ["Herod"] = true, ["Armory Quartermaster Daghelm"] = true,
  -- Scarlet Monastery (Cathedral)
  ["High Inquisitor Fairbanks"] = true, ["Scarlet Commander Mograine"] = true,
  ["High Inquisitor Whitemane"] = true,
  -- Stormwrought Ruins
  ["Oronok Torn-Heart"] = true, ["Dagar the Glutton"] = true,
  ["Duke Balor the IV"] = true, ["Librarian Theodorus"] = true,
  ["Chieftain Stormsong"] = true, ["Deathlord Tidebane"] = true,
  ["Subjugator Halthas Shadecrest"] = true, ["Mycellakos"] = true,
  ["Eldermaw the Primordial"] = true, ["Lady Drazare"] = true, ["Mergothid"] = true,
  -- Razorfen Downs
  ["Tuten'kash"] = true, ["Lady Falther'ess"] = true, ["Plaguemaw the Rotting"] = true,
  ["Mordresh Fire Eye"] = true, ["Glutton"] = true, ["Death Prophet Rakameg"] = true,
  ["Ragglesnout"] = true, ["Amnennar the Coldbringer"] = true,
  -- Uldaman
  ["Baelog"] = true, ["Olaf"] = true, ["Eric 'The Swift'"] = true,
  ["Revelosh"] = true, ["Ironaya"] = true, ["Ancient Stone Keeper"] = true,
  ["Galgann Firehammer"] = true, ["Grimlok"] = true, ["Archaedas"] = true,
  -- Gilneas City
  ["Matthias Holtz"] = true, ["Packmaster Ragetooth"] = true,
  ["Judge Sutherland"] = true, ["Dustivan Blackcowl"] = true,
  ["Marshal Magnus Greystone"] = true, ["Horsemaster Levvin"] = true,
  ["Genn Greymane"] = true,
  -- Maraudon
  ["Noxxion"] = true, ["Razorlash"] = true, ["Lord Vyletongue"] = true,
  ["Meshlok the Harvester"] = true, ["Celebras the Cursed"] = true,
  ["Landslide"] = true, ["Tinkerer Gizlock"] = true, ["Rotgrip"] = true,
  ["Princess Theradras"] = true,
  -- Zul'Farrak
  ["Antu'sul"] = true, ["Witch Doctor Zum'rah"] = true,
  ["Shadowpriest Sezz'ziz"] = true, ["Dustwraith"] = true, ["Zerillis"] = true,
  ["Gahz'rilla"] = true, ["Chief Ukorz Sandscalp"] = true,
  ["Zel'jeb the Ancient"] = true, ["Champion Razjal the Quick"] = true,
  -- Sunken Temple
  ["Atal'alarion"] = true, ["Spawn of Hakkar"] = true, ["Avatar of Hakkar"] = true,
  ["Jammal'an the Prophet"] = true, ["Ogom the Wretched"] = true,
  ["Dreamscythe"] = true, ["Weaver"] = true, ["Morphaz"] = true,
  ["Hazzas"] = true, ["Shade of Eranikus"] = true,
  -- Hateforge Quarry
  ["High Foreman Bargul Blackhammer"] = true, ["Engineer Figgles"] = true,
  ["Corrosis"] = true, ["Hatereaver Annihilator"] = true, ["Har'gesh Doomcaller"] = true,
  -- Blackrock Depths
  ["Lord Roccor"] = true, ["High Interrogator Gerstahn"] = true,
  ["Anub'shiah"] = true, ["Eviscerator"] = true, ["Gorosh the Dervish"] = true,
  ["Grizzle"] = true, ["Hedrum the Creeper"] = true, ["Ok'thor the Breaker"] = true,
  ["Theldren"] = true, ["Houndmaster Grebmar"] = true, ["Pyromancer Loregrain"] = true,
  ["Warder Stilgiss"] = true, ["Verek"] = true, ["Fineous Darkvire"] = true,
  ["Lord Incendius"] = true, ["Bael'Gar"] = true, ["General Angerforge"] = true,
  ["Golem Lord Argelmach"] = true, ["Ambassador Flamelash"] = true,
  ["Panzor the Invincible"] = true, ["Magmus"] = true,
  ["Princess Moira Bronzebeard"] = true, ["Emperor Dagran Thaurissan"] = true,
  -- Dire Maul (East)
  ["Pusillin"] = true, ["Zevrim Thornhoof"] = true, ["Hydrospawn"] = true,
  ["Lethtendris"] = true, ["Pimgib"] = true, ["Isalien"] = true,
  ["Alzzin the Wildshaper"] = true,
  -- Dire Maul (West)
  ["Tendris Warpwood"] = true, ["Illyanna Ravenoak"] = true,
  ["Magister Kalendris"] = true, ["Tsu'zee"] = true, ["Revanchion"] = true,
  ["Immol'thar"] = true, ["Lord Hel'nurath"] = true, ["Prince Tortheldrin"] = true,
  -- Dire Maul (North)
  ["Guard Mol'dar"] = true, ["Stomper Kreeg"] = true, ["Guard Fengus"] = true,
  ["Knot Thimblejack"] = true, ["Guard Slip'kik"] = true,
  ["Captain Kromcrush"] = true, ["Cho'Rush the Observer"] = true, ["King Gordok"] = true,
  -- Scholomance
  ["Kirtonos the Herald"] = true, ["Jandice Barov"] = true, ["Lord Blackwood"] = true,
  ["Rattlegore"] = true, ["Death Knight Darkreaver"] = true, ["Marduk Blackpool"] = true,
  ["Vectus"] = true, ["Ras Frostwhisper"] = true, ["Kormok"] = true,
  ["Instructor Malicia"] = true, ["Doctor Theolen Krastinov"] = true,
  ["Lorekeeper Polkelt"] = true, ["The Ravenian"] = true,
  ["Lord Alexei Barov"] = true, ["Lady Illucia Barov"] = true,
  ["Darkmaster Gandling"] = true,
  -- Stratholme
  ["Skul"] = true, ["The Unforgiven"] = true, ["Timmy the Cruel"] = true,
  ["Malor the Zealous"] = true, ["Crimson Hammersmith"] = true,
  ["Cannon Master Willey"] = true, ["Archivist Galford"] = true, ["Balnazzar"] = true,
  ["Hearthsinger Forresten"] = true, ["Balzaphon"] = true, ["Stonespine"] = true,
  ["Baroness Anastari"] = true, ["Black Guard Swordsmith"] = true,
  ["Nerub'enkan"] = true, ["Maleki the Pallid"] = true,
  ["Magistrate Barthilas"] = true, ["Ramstein the Gorger"] = true,
  ["Baron Rivendare"] = true, ["Sothos"] = true, ["Jarien"] = true,
  -- Lower Blackrock Spire
  ["Spirestone Butcher"] = true, ["Spirestone Battle Lord"] = true,
  ["Spirestone Lord Magus"] = true, ["Highlord Omokk"] = true,
  ["Shadow Hunter Vosh'gajin"] = true, ["War Master Voone"] = true,
  ["Burning Felguard"] = true, ["Mor Grayhoof"] = true, ["Bannok Grimaxe"] = true,
  ["Mother Smolderweb"] = true, ["Crystal Fang"] = true, ["Urok Doomhowl"] = true,
  ["Quartermaster Zigris"] = true, ["Halycon"] = true, ["Gizrul the Slavener"] = true,
  ["Ghok Bashguud"] = true, ["Overlord Wyrmthalak"] = true,
  -- Upper Blackrock Spire
  ["Pyroguard Emberseer"] = true, ["Solakar Flamewreath"] = true,
  ["Father Flame"] = true, ["Jed Runewatcher"] = true, ["Goraluk Anvilcrack"] = true,
  ["Warchief Rend Blackhand"] = true, ["Gyth"] = true, ["The Beast"] = true,
  ["Lord Valthalak"] = true, ["General Drakkisath"] = true,
  -- Karazhan Crypt
  ["Marrowspike"] = true, ["Hivaxxis"] = true, ["Corpsemuncher"] = true,
  ["Guard Captain Gort"] = true, ["Archlich Enkhraz"] = true,
  ["Commander Andreon"] = true, ["Alarus"] = true,
  -- Caverns of Time: Black Morass
  ["Chronar"] = true, ["Epidamu"] = true, ["Drifting Avatar of Sand"] = true,
  ["Time-Lord Epochronos"] = true, ["Mossheart"] = true, ["Rotmaw"] = true,
  ["Antnormi"] = true,
  -- Stormwind Vault
  ["Aszosh Grimflame"] = true, ["Tham'Grarr"] = true, ["Black Bride"] = true,
  ["Damian"] = true, ["Volkan Cruelblade"] = true, ["Arc'tiras"] = true,
  -- Raids
  -- Zul'Gurub
  ["High Priestess Jeklik"] = true, ["High Priest Venoxis"] = true,
  ["High Priestess Mar'li"] = true, ["Bloodlord Mandokir"] = true,
  ["Gri'lek"] = true, ["Hazza'rah"] = true, ["Renataki"] = true, ["Wushoolay"] = true,
  ["Gahz'ranka"] = true, ["High Priest Thekal"] = true, ["High Priestess Arlokk"] = true,
  ["Jin'do the Hexxer"] = true, ["Hakkar"] = true,
  -- Ruins of Ahn'Qiraj
  ["Kurinnaxx"] = true, ["General Rajaxx"] = true, ["Moam"] = true,
  ["Buru the Gorger"] = true, ["Ayamiss the Hunter"] = true,
  ["Ossirian the Unscarred"] = true,
  -- Molten Core
  ["Incindis"] = true, ["Lucifron"] = true, ["Magmadar"] = true,
  ["Garr"] = true, ["Shazzrah"] = true, ["Baron Geddon"] = true,
  ["Golemagg the Incinerator"] = true, ["Basalthar & Smoldaris"] = true,
  ["Sorcerer-Thane Thaurissan"] = true, ["Sulfuron Harbinger"] = true,
  ["Majordomo Executus"] = true, ["Ragnaros"] = true,
  -- Onyxia's Lair
  ["Onyxia"] = true,
  -- Blackwing Lair
  ["Razorgore the Untamed"] = true, ["Vaelastrasz the Corrupt"] = true,
  ["Broodlord Lashlayer"] = true, ["Firemaw"] = true, ["Ebonroc"] = true,
  ["Flamegor"] = true, ["Chromaggus"] = true, ["Nefarian"] = true,
  -- Emerald Sanctum
  ["Erennius"] = true, ["Solnius the Awakener"] = true,
  -- Temple of Ahn'Qiraj
  ["The Prophet Skeram"] = true, ["The Bug Family"] = true,
  ["Battleguard Sartura"] = true, ["Fankriss the Unyielding"] = true,
  ["Viscidus"] = true, ["Princess Huhuran"] = true, ["The Twin Emperors"] = true,
  ["Ouro"] = true, ["C'Thun"] = true,
  -- Naxxramas
  ["Patchwerk"] = true, ["Grobbulus"] = true, ["Gluth"] = true, ["Thaddius"] = true,
  ["Anub'Rekhan"] = true, ["Grand Widow Faerlina"] = true, ["Maexxna"] = true,
  ["Noth the Plaguebringer"] = true, ["Heigan the Unclean"] = true, ["Loatheb"] = true,
  ["Instructor Razuvious"] = true, ["Gothik the Harvester"] = true,
  ["The Four Horsemen"] = true, ["Sapphiron"] = true, ["Kel'Thuzad"] = true,
  -- Lower Karazhan Halls
  ["Master Blacksmith Rolfen"] = true, ["Brood Queen Araxxna"] = true,
  ["Grizikil"] = true, ["Clawlord Howlfang"] = true, ["Lord Blackwald II"] = true,
  ["Moroes"] = true,
  -- Upper Karazhan Halls
  ["Keeper Gnarlmoon"] = true, ["Ley-Watcher Incantagos"] = true,
  ["Anomalus"] = true, ["Echo of Medivh"] = true, ["King (Chess fight)"] = true,
  ["Sanv Tas'dal"] = true, ["Kruul"] = true, ["Rupturan the Broken"] = true,
  ["Mephistroth"] = true,
  -- World Bosses
  ["Azuregos"] = true, ["Emeriss"] = true, ["Lethon"] = true, ["Taerar"] = true,
  ["Ysondre"] = true, ["Lord Kazzak"] = true, ["Nerubian Overseer"] = true,
  ["Dark Reaver of Karazhan"] = true, ["Ostarius"] = true, ["Concavius"] = true,
  ["Moo"] = true, ["Cla'ckora"] = true,
  -- Rare Spawns
  ["Earthcaller Rezengal"] = true, ["Shade Mage"] = true, ["Graypaw Alpha"] = true,
  ["Blazespark"] = true, ["Witch Doctor Tan'zo"] = true, ["Widow of the Woods"] = true,
  ["Dawnhowl"] = true, ["Maltimor's Prototype"] = true, ["Bonecruncher"] = true,
  ["Duskskitter"] = true, ["Baron Perenolde"] = true, ["Kin'Tozo"] = true,
  ["Grug'thok the Seer"] = true, ["M-0L1Y"] = true, ["Explorer Ashbeard"] = true,
  ["Jal'akar"] = true, ["Embereye"] = true, ["Ruk'thok the Pyromancer"] = true,
  ["Tarangos"] = true, ["Ripjaw"] = true, ["Xalvic Blackclaw"] = true,
  ["Aquitus"] = true, ["Firstborn of Arugal"] = true, ["Letashaz"] = true,
  ["Margon the Mighty"] = true, ["The Wandering Knight"] = true, ["Stoneshell"] = true,
  ["Zareth Terrorblade"] = true, ["Highvale Silverback"] = true,
  ["Mallon The Moontouched"] = true, ["Blademaster Kargron"] = true,
  ["Professor Lysander"] = true, ["Admiral Barean Westwind"] = true,
  ["Azurebeak"] = true, ["Barkskin Fisher"] = true, ["Crusader Larsarius"] = true,
  ["Shadeflayer Goliath"] = true,
}

LeafVE.guildRosterCache = {}
LeafVE.guildRosterCacheTime = 0
LeafVE.guildRosterRequestAt = 0
LeafVE.currentGroupStart = nil
LeafVE.currentGroupMembers = {}
LeafVE.notificationQueue = {}
LeafVE.errorLog = {}
LeafVE.maxErrors = 50
LeafVE.lastResyncRequestAt = 0
LeafVE.lastResyncRespondAt = 0
LeafVE.lastShoutSyncRespondAt = 0
LeafVE.lastBadgeSyncRespondAt = 0
LeafVE.lastAchSyncRespondAt = 0
LeafVE.shoutSyncBuffer = {}
LeafVE.instanceJoinedAt = nil
LeafVE.instanceZone = nil
LeafVE.instanceHasGuildie = false
LeafVE.instanceBossesKilledThisRun = 0
LeafVE.recentBossKills = {}  -- bossName -> timestamp, for dedup within a short window
LeafVE.lastGroupAwardTime = nil
LeafVE.lastCombatAt = 0
LeafVE.lastActivityTime = 0
local AFK_TIMEOUT = 600  -- 10 minutes of inactivity = considered AFK
-- Quest tracking via pfDB
LeafVE.questLogCache       = {}   -- title -> {level, isComplete}  (updated on QUEST_LOG_UPDATE)
LeafVE.lastQuestTurnInTime = 0    -- timestamp of last quest LP award (guard against double-awarding)
LeafVE.pendingQuestTurnIn  = nil  -- quest title captured from QUEST_COMPLETE, cleared on QUEST_FINISHED

local function SetSize(f, w, h)
  if not f then return end
  if f.SetSize then f:SetSize(w, h) 
  else if w then f:SetWidth(w) end if h then f:SetHeight(h) end end
end

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cFF2DD35CLeafVE|r: "..tostring(msg))
  end
end

local function Now() return time() end
local function Lower(s) return s and string.lower(s) or "" end
local function Trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end

local function ShortName(name)
  if not name then return nil end
  local dash = string.find(name, "-")
  if dash then return string.sub(name, 1, dash-1) end
  return name
end

local function FormatAchievementName(achID)
  if not achID then return "Unknown" end
  local formatted = string.gsub(achID, "raid_", "")
  formatted = string.gsub(formatted, "dungeon_", "")
  formatted = string.gsub(formatted, "pvp_", "")
  formatted = string.gsub(formatted, "mc_", "MC: ")
  formatted = string.gsub(formatted, "bwl_", "BWL: ")
  formatted = string.gsub(formatted, "aq40_", "AQ40: ")
  formatted = string.gsub(formatted, "naxx_", "Naxx: ")
  formatted = string.gsub(formatted, "onyxia_", "Onyxia: ")
  formatted = string.gsub(formatted, "zg_", "ZG: ")
  formatted = string.gsub(formatted, "_", " ")
  local first = string.sub(formatted, 1, 1)
  formatted = string.upper(first) .. string.sub(formatted, 2)
  return formatted
end

local function InGuild() return (IsInGuild and IsInGuild()) and true or false end

local function DayKeyFromTS(ts)
  local d = date("*t", ts)
  return string.format("%04d-%02d-%02d", d.year, d.month, d.day)
end

local function DayKey(ts) return DayKeyFromTS(ts or Now()) end

local function WeekStartTS(ts)
  local d = date("*t", ts or Now())
  d.hour, d.min, d.sec = 0, 0, 0
  local midnight = time(d)
  local wday = d.wday or 1
  
  -- Week runs Wednesday→Tuesday so it ends on Tuesday (the WoW weekly reset day).
  -- Sunday=1, Monday=2, Tuesday=3, Wednesday=4, Thursday=5, Friday=6, Saturday=7
  local daysSinceWednesday
  if wday >= 4 then
    daysSinceWednesday = wday - 4  -- Wed=0, Thu=1, Fri=2, Sat=3
  else
    daysSinceWednesday = wday + 3  -- Sun=4, Mon=5, Tue=6
  end
  
  return midnight - daysSinceWednesday * SECONDS_PER_DAY
end

local function GetWeekDateRange()
  local startTS = WeekStartTS(Now())
  local endTS = startTS + (6 * SECONDS_PER_DAY)
  return date("%m/%d", startTS).." - "..date("%m/%d", endTS)
end

local function WeekKey(ts)
  local d = date("*t", WeekStartTS(ts or Now()))
  return string.format("%04d%02d%02d", d.year, d.month, d.day)
end

local function SkinFrameModern(f)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  f:SetBackdropColor(THEME.bg[1], THEME.bg[2], THEME.bg[3], THEME.bg[4])
  f:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4])
  if not f._accentStripe then
    local stripe = f:CreateTexture(nil, "BORDER")
    stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -44)
    stripe:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -44)
    stripe:SetHeight(2)
    stripe:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    stripe:SetVertexColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3], 0.85)
    f._accentStripe = stripe
  end
end

local function CreateInset(parent)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  inset:SetBackdropColor(THEME.insetBG[1], THEME.insetBG[2], THEME.insetBG[3], THEME.insetBG[4])
  inset:SetBackdropBorderColor(THEME.soft[1], THEME.soft[2], THEME.soft[3], 1)
  return inset
end

local function CreateGradientInset(parent)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  inset:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  inset:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  local gradient = inset:CreateTexture(nil, "BACKGROUND")
  gradient:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  gradient:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
  gradient:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  gradient:SetGradientAlpha("VERTICAL", 0.2, 0.2, 0.22, 1, 0.08, 0.08, 0.1, 1)
  return inset
end

local function MakeResizeHandle(f)
  if f._resize then return end
  if f.SetResizable then f:SetResizable(true) end
  if f.SetMinResize then f:SetMinResize(950, 600) end
  if f.SetMaxResize then f:SetMaxResize(1400, 1000) end
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  local grip = CreateFrame("Button", nil, f)
  SetSize(grip, 16, 16)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
  local tex = grip:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(grip)
  tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetNormalTexture(tex)
  grip:SetScript("OnMouseDown", function() if f.StartSizing then f:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function() 
    if f.StopMovingOrSizing then 
      f:StopMovingOrSizing()
      local w, h = f:GetWidth(), f:GetHeight()
      if w < 950 then f:SetWidth(950) w = 950 end
      if w > 1400 then f:SetWidth(1400) w = 1400 end
      if h < 600 then f:SetHeight(600) h = 600 end
      if h > 1000 then f:SetHeight(1000) h = 1000 end
      if LeafVE_DB and LeafVE_DB.ui then LeafVE_DB.ui.w = w LeafVE_DB.ui.h = h end
    end 
  end)
  f._resize = grip
end

local function SkinButtonAccent(btn)
  if not btn then return end
  btn:SetScript("OnEnter", function()
    local fs = btn.GetFontString and btn:GetFontString()
    if fs then fs:SetTextColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3]) end
  end)
  btn:SetScript("OnLeave", function()
    local fs = btn.GetFontString and btn:GetFontString()
    if fs then fs:SetTextColor(1, 1, 1) end
  end)
end

local function EnsureDB()
  if not LeafVE_DB then LeafVE_DB = {} end
  -- Detect version upgrade and notify the player once per session.
  if LeafVE_DB.addonVersion ~= LeafVE.version then
    if LeafVE_DB.addonVersion then
      Print("|cFFFFD700Leaf Village Legends updated from v"..LeafVE_DB.addonVersion.." → v"..LeafVE.version..". Old-version peers will be ignored until they update.|r")
    end
    LeafVE_DB.addonVersion = LeafVE.version
  end
  if not LeafVE_DB.options then LeafVE_DB.options = {} end
  if not LeafVE_DB.ui then LeafVE_DB.ui = {} end
  if not LeafVE_DB.global then LeafVE_DB.global = {} end
  if not LeafVE_DB.alltime then LeafVE_DB.alltime = {} end
  if not LeafVE_DB.season then LeafVE_DB.season = {} end
  if not LeafVE_DB.loginTracking then LeafVE_DB.loginTracking = {} end
  if not LeafVE_DB.groupCooldowns then LeafVE_DB.groupCooldowns = {} end
  if not LeafVE_DB.shoutouts then LeafVE_DB.shoutouts = {} end
  if not LeafVE_DB.pointHistory then LeafVE_DB.pointHistory = {} end
  if not LeafVE_DB.badges then LeafVE_DB.badges = {} end
  if not LeafVE_DB.attendance then LeafVE_DB.attendance = {} end
  if not LeafVE_DB.weeklyRecap then LeafVE_DB.weeklyRecap = {} end
  if not LeafVE_DB.loginStreaks then LeafVE_DB.loginStreaks = {} end
  if not LeafVE_DB.persistentRoster then LeafVE_DB.persistentRoster = {} end
  if not LeafVE_DB.instanceTracking then LeafVE_DB.instanceTracking = {} end
  if not LeafVE_DB.questTracking then LeafVE_DB.questTracking = {} end
  if not LeafVE_DB.questCompletions then LeafVE_DB.questCompletions = {} end
  if not LeafVE_DB.groupSessions then LeafVE_DB.groupSessions = {} end
  if not LeafVE_DB.groupPointsToday then LeafVE_DB.groupPointsToday = {} end
  if not LeafVE_DB.peerProgress then LeafVE_DB.peerProgress = {} end
  if not LeafVE_DB.lboard then LeafVE_DB.lboard = { alltime = {}, weekly = {}, season = {}, updatedAt = {} } end
  -- Ensure sub-tables exist (migration: older versions may not have all sub-tables)
  if not LeafVE_DB.lboard.alltime then LeafVE_DB.lboard.alltime = {} end
  if not LeafVE_DB.lboard.weekly then LeafVE_DB.lboard.weekly = {} end
  if not LeafVE_DB.lboard.season then LeafVE_DB.lboard.season = {} end
  if not LeafVE_DB.lboard.updatedAt then LeafVE_DB.lboard.updatedAt = {} end
  -- Migrate: older code stored updatedAt[name] as a plain timestamp number; now it must be a table
  for k, v in pairs(LeafVE_DB.lboard.updatedAt) do
    if type(v) == "number" then LeafVE_DB.lboard.updatedAt[k] = { lifetime = v } end
  end
  -- Migrate: ensure weekly[wk] entries are tables, not numbers
  for wk, v in pairs(LeafVE_DB.lboard.weekly) do
    if type(v) ~= "table" then LeafVE_DB.lboard.weekly[wk] = {} end
  end
  if LeafVE_DB.ui.w == nil then LeafVE_DB.ui.w = 950 end
  if LeafVE_DB.ui.h == nil then LeafVE_DB.ui.h = 660 end
  if LeafVE_DB.options.officerRankThreshold == nil then LeafVE_DB.options.officerRankThreshold = 4 end
  if LeafVE_DB.options.showOfflineMembers == nil then LeafVE_DB.options.showOfflineMembers = true end
  if LeafVE_DB.options.minimapPos == nil then LeafVE_DB.options.minimapPos = 220 end
  if LeafVE_DB.options.enableNotifications == nil then LeafVE_DB.options.enableNotifications = true end
  if LeafVE_DB.options.notificationSound == nil then LeafVE_DB.options.notificationSound = true end
  if LeafVE_DB.options.enablePointNotifications == nil then LeafVE_DB.options.enablePointNotifications = true end
  if LeafVE_DB.options.enableBadgeNotifications == nil then LeafVE_DB.options.enableBadgeNotifications = true end
  if LeafVE_DB.options.bossPoints == nil then LeafVE_DB.options.bossPoints = INSTANCE_BOSS_POINTS end
  if LeafVE_DB.options.instanceCompletionPoints == nil then LeafVE_DB.options.instanceCompletionPoints = INSTANCE_COMPLETION_POINTS end
  if LeafVE_DB.options.questPoints == nil then LeafVE_DB.options.questPoints = QUEST_POINTS end
  if LeafVE_DB.options.questMaxDaily == nil then LeafVE_DB.options.questMaxDaily = QUEST_MAX_DAILY end
  if LeafVE_DB.options.instanceMaxDaily == nil then LeafVE_DB.options.instanceMaxDaily = INSTANCE_MAX_DAILY end
  if LeafVE_DB.options.groupPointInterval == nil then LeafVE_DB.options.groupPointInterval = GROUP_POINT_INTERVAL end
  if LeafVE_DB.options.seasonReward1 == nil then LeafVE_DB.options.seasonReward1 = SEASON_REWARD_1 end
  if LeafVE_DB.options.seasonReward2 == nil then LeafVE_DB.options.seasonReward2 = SEASON_REWARD_2 end
  if LeafVE_DB.options.seasonReward3 == nil then LeafVE_DB.options.seasonReward3 = SEASON_REWARD_3 end
  if LeafVE_DB.options.seasonReward4 == nil then LeafVE_DB.options.seasonReward4 = SEASON_REWARD_4 end
  if LeafVE_DB.options.seasonReward5 == nil then LeafVE_DB.options.seasonReward5 = SEASON_REWARD_5 end
  if not LeafVE_GlobalDB then LeafVE_GlobalDB = {} end
  if not LeafVE_GlobalDB.playerNotes then LeafVE_GlobalDB.playerNotes = {} end
  if not LeafVE_GlobalDB.achievementCache then LeafVE_GlobalDB.achievementCache = {} end
  if not LeafVE_GlobalDB.gearCache then LeafVE_GlobalDB.gearCache = {} end
  if not LeafVE_GlobalDB.gearStatsCache then LeafVE_GlobalDB.gearStatsCache = {} end
  if LeafVE_DB.options.groupPoints == nil then LeafVE_DB.options.groupPoints = GROUP_POINTS end
  if LeafVE_DB.options.loginPoints == nil then LeafVE_DB.options.loginPoints = 20 end
  -- Alt linking tables
  if not LeafVE_DB.links then LeafVE_DB.links = {} end
  if not LeafVE_DB.pendingMerge then LeafVE_DB.pendingMerge = {} end
  if not LeafVE_DB.lastDeposit then LeafVE_DB.lastDeposit = {} end
  if not LeafVE_DB.lastLinkChange then LeafVE_DB.lastLinkChange = {} end
  -- Shoutout V2 table
  if not LeafVE_DB.shoutouts_v2 then
    LeafVE_DB.shoutouts_v2 = { given = {}, received = {}, daily = { dateKey = "", awards = {} } }
  end
  if not LeafVE_DB.shoutouts_v2.given then LeafVE_DB.shoutouts_v2.given = {} end
  if not LeafVE_DB.shoutouts_v2.received then LeafVE_DB.shoutouts_v2.received = {} end
  if not LeafVE_DB.shoutouts_v2.daily then LeafVE_DB.shoutouts_v2.daily = { dateKey = "", awards = {} } end
  -- Meta table for guild-wide wipe tracking
  if not LeafVE_DB.meta then LeafVE_DB.meta = {} end
  if LeafVE_DB.meta.lastWipeId == nil then LeafVE_DB.meta.lastWipeId = "" end
end

-------------------------------------------------
-- ALT LINKING HELPER FUNCTIONS
-------------------------------------------------

function LVL_GetCharKey()
  return ShortName(UnitName("player")) or ""
end

function LVL_IsAltLinked(key)
  return LeafVE_DB.links and LeafVE_DB.links[key] ~= nil
end

function LVL_GetMainKey(key)
  return (LeafVE_DB.links and LeafVE_DB.links[key]) or key
end

function LVL_FormatTime(secs)
  local h = math.floor(secs / 3600)
  local m = math.floor(math.mod(secs, 3600) / 60)
  return h .. "h " .. m .. "m"
end

function LVL_Remain(last, window)
  return math.max(0, window - (Now() - (last or 0)))
end

-- Check if a short player name is a linked alt (uses current player's realm)
function LVL_IsAltByName(shortName)
  if not shortName or not LeafVE_DB.links then return false end
  return LeafVE_DB.links[shortName] ~= nil
end

function LeafVE:AddToHistory(playerName, pointType, amount, reason)
  EnsureDB() playerName = ShortName(playerName) if not playerName then return end
  if not LeafVE_DB.pointHistory[playerName] then LeafVE_DB.pointHistory[playerName] = {} end
  table.insert(LeafVE_DB.pointHistory[playerName], {timestamp = Now(), type = pointType, amount = amount, reason = reason or "Unknown"})
  while table.getn(LeafVE_DB.pointHistory[playerName]) > 500 do table.remove(LeafVE_DB.pointHistory[playerName], 1) end
end

function LeafVE:AwardBadge(playerName, badgeId)
  EnsureDB()
  playerName = ShortName(playerName)
  
  if not playerName then
    Print("ERROR: Invalid player name")
    return
  end
  
  -- Check if badge exists
  local badge = nil
  for i = 1, table.getn(BADGES) do
    if BADGES[i].id == badgeId then
      badge = BADGES[i]
      break
    end
  end

  if not badge then
    Print("ERROR: Badge '"..badgeId.."' does not exist")
    return
  end

  -- Initialize player badges table if needed
  if not LeafVE_DB.badges[playerName] then
    LeafVE_DB.badges[playerName] = {}
  end

  -- Check if already earned
  if LeafVE_DB.badges[playerName][badgeId] then
    Print(playerName.." already has badge: "..badgeId)
    return
  end

  -- Award the badge
  LeafVE_DB.badges[playerName][badgeId] = time()
  Print("Badge awarded to "..playerName..": "..badgeId)

  -- Show notification if this is the current player
  local me = ShortName(UnitName("player"))
  if me and playerName == me then
    local badgeQuality = badge.quality or BADGE_QUALITY.COMMON
    local qr, qg, qb = GetBadgeQualityColor(badgeQuality)
    local qualityLabel = GetBadgeQualityLabel(badgeQuality)
    if LeafVE_DB.options.enableNotifications ~= false and LeafVE_DB.options.enableBadgeNotifications ~= false then
      self:ShowNotification("Badge Earned! ["..qualityLabel.."]", badge.name..": "..badge.desc, badge.icon, {qr, qg, qb, 1})
    end
    Print("|cFF"..RGBToHex(qr, qg, qb).."["..qualityLabel.."] Badge Earned:|r "..badge.name.." - "..badge.desc)
  end

  -- Send guild chat announcement
  if InGuild() then
    local badgeQuality = badge.quality or BADGE_QUALITY.COMMON
    local qr, qg, qb = GetBadgeQualityColor(badgeQuality)
    local badgeLink = "|cFF"..RGBToHex(qr, qg, qb).."|Hleafve_badge:"..badge.id.."|h["..badge.name.."]|h|r"
    local titleStr = ""
    if LeafVE_AchTest_DB and LeafVE_AchTest_DB[playerName] and LeafVE_AchTest_DB[playerName].equippedTitle and LeafVE_AchTest_DB[playerName].equippedTitle ~= "" then
      titleStr = "|cFFFF8000[" .. LeafVE_AchTest_DB[playerName].equippedTitle .. "]|r"
    end
    SendChatMessage(titleStr.."[LeafVE Note] received "..badgeLink.." for contributing to the guild!", "GUILD")
  end

  -- Broadcast badges immediately after awarding
  if me and playerName == me then
    self:BroadcastBadges()
  end
  
  -- Refresh UI if player card is showing this player
  if LeafVE.UI.cardCurrentPlayer == playerName then
    LeafVE.UI:UpdateCardRecentBadges(playerName)
  end
  
  -- Refresh badges tab if open
  if LeafVE.UI.panels and LeafVE.UI.panels.badges and LeafVE.UI.panels.badges:IsVisible() then
    LeafVE.UI:RefreshBadges()
  end
end

function LeafVE:AwardRandomBadge(playerName)
  EnsureDB()
  playerName = ShortName(playerName)
  if not playerName then
    Print("ERROR: Invalid player name")
    return
  end
  if not LeafVE_DB.badges[playerName] then LeafVE_DB.badges[playerName] = {} end
  local unearned = {}
  for i = 1, table.getn(BADGES) do
    if not LeafVE_DB.badges[playerName][BADGES[i].id] then
      table.insert(unearned, BADGES[i].id)
    end
  end
  if table.getn(unearned) == 0 then
    Print(playerName.." already has all badges.")
    return
  end
  local idx = math.random(1, table.getn(unearned))
  self:AwardBadge(playerName, unearned[idx])
end

function LeafVE:ResetBadges(playerName)
  EnsureDB()
  playerName = ShortName(playerName)
  if not playerName then
    Print("ERROR: Invalid player name")
    return
  end
  LeafVE_DB.badges[playerName] = {}
  -- Clear all progress-tracking data for this player so badges cannot immediately re-earn
  LeafVE_DB.alltime[playerName] = nil
  LeafVE_DB.season[playerName] = nil
  LeafVE_DB.loginStreaks[playerName] = nil
  LeafVE_DB.loginTracking[playerName] = nil
  LeafVE_DB.groupSessions[playerName] = nil
  LeafVE_DB.attendance[playerName] = nil
  LeafVE_DB.pointHistory[playerName] = nil
  LeafVE_DB.instanceTracking[playerName] = nil
  LeafVE_DB.questTracking[playerName] = nil
  LeafVE_DB.questCompletions[playerName] = nil
  LeafVE_DB.lboard.alltime[playerName] = nil
  for wk, wkData in pairs(LeafVE_DB.lboard.weekly) do
    if type(wkData) == "table" then wkData[playerName] = nil end
  end
  for day, dayData in pairs(LeafVE_DB.global) do
    if type(dayData) == "table" then dayData[playerName] = nil end
  end
  for _, targets in pairs(LeafVE_DB.shoutouts) do
    if type(targets) == "table" then targets[playerName] = nil end
  end
  LeafVE_DB.shoutouts[playerName] = nil
  if LeafVE_GlobalDB.achievementCache then
    LeafVE_GlobalDB.achievementCache[playerName] = nil
  end
  Print("All badges reset for "..playerName..".")
  if InGuild() then
    SendAddonMessage("LeafVE", "BADGESRESET:"..playerName, "GUILD")
  end
  local me = ShortName(UnitName("player"))
  if me and playerName == me then
    self:BroadcastBadges()
  end
  if LeafVE.UI and LeafVE.UI.Refresh then
    LeafVE.UI:Refresh()
  end
end

function LeafVE:ResetAllBadges()
  EnsureDB()
  LeafVE_DB.badges = {}
  -- Clear all progress-tracking tables so badges cannot immediately re-earn
  LeafVE_DB.alltime      = {}
  LeafVE_DB.season       = {}
  LeafVE_DB.global       = {}
  LeafVE_DB.loginStreaks  = {}
  LeafVE_DB.loginTracking = {}
  LeafVE_DB.groupSessions = {}
  LeafVE_DB.groupCooldowns = {}
  LeafVE_DB.shoutouts    = {}
  LeafVE_DB.attendance   = {}
  LeafVE_DB.pointHistory = {}
  LeafVE_DB.weeklyRecap  = {}
  LeafVE_DB.instanceTracking = {}
  LeafVE_DB.questTracking = {}
  LeafVE_DB.questCompletions = {}
  LeafVE_DB.lboard       = { alltime = {}, weekly = {}, season = {}, updatedAt = {} }
  LeafVE_GlobalDB.achievementCache = {}
  if LeafVE_AchTest_DB and LeafVE_AchTest_DB.achievements then
    LeafVE_AchTest_DB.achievements = {}
  end
  Print("All badges reset for all players.")
  if InGuild() then
    SendAddonMessage("LeafVE", "BADGESRESETALL", "GUILD")
  end
  if LeafVE.UI and LeafVE.UI.Refresh then
    LeafVE.UI:Refresh()
  end
end

-- Hard-wipes ALL Leaf Point data (daily/weekly/season/all-time) locally.
-- Called by the admin UI button and by the guild broadcast handler.
function LeafVE:HardResetLeafPoints_Local()
  EnsureDB()
  LeafVE_DB.global       = {}
  LeafVE_DB.alltime      = {}
  LeafVE_DB.season       = {}
  LeafVE_DB.weeklyRecap  = {}
  LeafVE_DB.pointHistory = {}
  LeafVE_DB.instanceTracking = {}
  LeafVE_DB.questTracking = {}
  LeafVE_DB.questCompletions = {}
  LeafVE_DB.groupSessions = {}
  LeafVE_DB.groupCooldowns = {}
  LeafVE_DB.shoutouts = {}
  LeafVE_DB.groupPointsToday = {}
  LeafVE_DB.lboard       = { alltime = {}, weekly = {}, season = {}, updatedAt = {} }
  self.lastGroupAwardTime = nil
  self.currentGroupStart = nil
  self.currentGroupMembers = {}
  -- Refresh all visible panels (handles me, leaderWeek, leaderLife, etc.)
  if LeafVE.UI and LeafVE.UI.panels and LeafVE.UI.Refresh then
    LeafVE.UI:Refresh()
  end
  Print("|cFFFF4444All Leaf Points have been wiped (daily/weekly/season/all-time).|r")
end

-------------------------------------------------
-- GUILD-WIDE FULL WIPE (FEATURE E)
-------------------------------------------------

-- Full local DB wipe preserving the wipeId so we don't reapply the same wipe twice.
function LVL_FullWipeLocal()
  EnsureDB()
  local lastId = (LeafVE_DB.meta and LeafVE_DB.meta.lastWipeId) or ""
  LeafVE_DB = {}
  LeafVE_DB.meta = { lastWipeId = lastId }
  -- Re-init all required tables
  LeafVE_DB.options = {}
  LeafVE_DB.ui = {}
  LeafVE_DB.global = {}
  LeafVE_DB.alltime = {}
  LeafVE_DB.season = {}
  LeafVE_DB.loginTracking = {}
  LeafVE_DB.groupCooldowns = {}
  LeafVE_DB.shoutouts = {}
  LeafVE_DB.pointHistory = {}
  LeafVE_DB.badges = {}
  LeafVE_DB.attendance = {}
  LeafVE_DB.weeklyRecap = {}
  LeafVE_DB.loginStreaks = {}
  LeafVE_DB.persistentRoster = {}
  LeafVE_DB.instanceTracking = {}
  LeafVE_DB.questTracking = {}
  LeafVE_DB.questCompletions = {}
  LeafVE_DB.groupSessions = {}
  LeafVE_DB.groupPointsToday = {}
  LeafVE_DB.peerProgress = {}
  LeafVE_DB.lboard = { alltime = {}, weekly = {}, season = {}, updatedAt = {} }
  LeafVE_DB.links = {}
  LeafVE_DB.pendingMerge = {}
  LeafVE_DB.lastDeposit = {}
  LeafVE_DB.lastLinkChange = {}
  LeafVE_DB.shoutouts_v2 = { given = {}, received = {}, daily = { dateKey = "", awards = {} } }
  EnsureDB()
  if LeafVE.UI and LeafVE.UI.panels and LeafVE.UI.Refresh then
    LeafVE.UI:Refresh()
  end
end

-- Returns true only if sender's guild rank is Hokage, Sannin, or Anbu.
function LVL_IsAuthorizedSender(sender)
  if not sender then return false end
  local info = LeafVE.guildRosterCache and LeafVE.guildRosterCache[Lower(sender)]
  if not info then
    info = LeafVE_DB and LeafVE_DB.persistentRoster and LeafVE_DB.persistentRoster[Lower(sender)]
  end
  if info and info.rank then
    return ADMIN_RANKS[Lower(Trim(info.rank))] == true
  end
  return false
end

-- Officer initiates a guild-wide wipe; broadcasts via LVL prefix and writes bulletin token.
function LVL_AdminResetAll()
  if not LeafVE:IsAdminRank() then
    Print("|cFFFF4444You do not have permission to perform a guild-wide reset.|r")
    return
  end
  EnsureDB()
  local me = ShortName(UnitName("player")) or "unknown"
  local wipeId = tostring(time()) .. "-" .. me
  LeafVE_DB.meta.lastWipeId = wipeId
  LVL_FullWipeLocal()
  if InGuild() then
    SendAddonMessage("LVL", "WIPE_ALL|" .. wipeId, "GUILD")
  end
  -- Attempt to embed a wipe token in guild info text so offline members catch it on login
  if SetGuildInfoText then
    local current = GetGuildInfoText and GetGuildInfoText() or ""
    -- Remove any previous token
    current = string.gsub(current, "%s*LVL_WIPE:[^%s]+", "")
    local token = " LVL_WIPE:" .. wipeId
    if string.len(current) + string.len(token) <= 500 then
      SetGuildInfoText(current .. token)
    end
  end
  Print("|cFFFF4444Guild-wide point reset initiated. All online members will be wiped.|r")
end

-- Called on PLAYER_LOGIN and GUILD_ROSTER_UPDATE: check guild info for a wipe bulletin.
function LVL_CheckGuildWipeBulletin()
  EnsureDB()
  local info = GetGuildInfoText and GetGuildInfoText() or ""
  local wipeId = info and string.match(info, "LVL_WIPE:([^%s]+)")
  if wipeId and wipeId ~= "" then
    local stored = (LeafVE_DB.meta and LeafVE_DB.meta.lastWipeId) or ""
    if wipeId ~= stored then
      LeafVE_DB.meta = LeafVE_DB.meta or {}
      LeafVE_DB.meta.lastWipeId = wipeId
      LVL_FullWipeLocal()
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LVL]|r Guild-wide point reset detected from guild info. All data cleared.")
    end
  end
end



-- Hard-wipes the achievement leaderboard cache locally.
-- Called by the admin UI button and by the guild broadcast handler.
function LeafVE:HardResetAchievementLeaderboard_Local()
  EnsureDB()
  LeafVE_GlobalDB.achievementCache = {}
  if LeafVE_AchTest_DB and LeafVE_AchTest_DB.achievements then
    LeafVE_AchTest_DB.achievements = {}
  end
  -- Refresh the achievement leaderboard panel if it is open
  if LeafVE.UI and LeafVE.UI.panels then
    if LeafVE.UI.panels.achievements and LeafVE.UI.panels.achievements:IsVisible() then
      LeafVE.UI:RefreshAchievementsLeaderboard()
    end
  end
  Print("|cFFFF4444Achievement leaderboard cache has been wiped.|r")
end

function LeafVE:GetHistory(playerName, limit)
  EnsureDB() playerName = ShortName(playerName) if not playerName then return {} end
  local history = LeafVE_DB.pointHistory[playerName] or {} local sorted = {}
  for i = table.getn(history), 1, -1 do table.insert(sorted, history[i]) if limit and table.getn(sorted) >= limit then break end end
  return sorted
end

function LeafVE:ShowNotification(title, message, icon, color)
  if LeafVE_DB.options.enableNotifications == false then return end
  table.insert(self.notificationQueue, {title = title, message = message, icon = icon or LEAF_EMBLEM, color = color or THEME.leaf, timestamp = Now()})
end

function LeafVE:CreateToastFrame()
  if self.toastFrame then return end
  local toast = CreateFrame("Frame", "LeafVEToast", UIParent)
  toast:SetWidth(300) toast:SetHeight(80) toast:SetPoint("TOP", UIParent, "TOP", 0, -100) toast:SetFrameStrata("TOOLTIP") toast:SetAlpha(0)
  toast:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
  toast:SetBackdropColor(0.05, 0.05, 0.06, 0.95) toast:SetBackdropBorderColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3], 1)
  local icon = toast:CreateTexture(nil, "ARTWORK") icon:SetWidth(48) icon:SetHeight(48) icon:SetPoint("LEFT", toast, "LEFT", 12, 0) toast.icon = icon
  local title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -5) title:SetPoint("RIGHT", toast, "RIGHT", -12, 0) title:SetJustifyH("LEFT") toast.title = title
  local message = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") message:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5) message:SetPoint("RIGHT", toast, "RIGHT", -12, 0) message:SetJustifyH("LEFT") toast.message = message
  toast:Hide() self.toastFrame = toast
end

function LeafVE:ProcessNotifications()
  if table.getn(self.notificationQueue) == 0 then return end
  if not self.toastFrame then self:CreateToastFrame() end
  if self.toastShowing then return end
  local notif = table.remove(self.notificationQueue, 1)
  self.toastFrame.icon:SetTexture(notif.icon) if not self.toastFrame.icon:GetTexture() then self.toastFrame.icon:SetTexture(LEAF_FALLBACK) end
  self.toastFrame.title:SetText(notif.title) self.toastFrame.title:SetTextColor(notif.color[1], notif.color[2], notif.color[3])
  self.toastFrame.message:SetText(notif.message)
  if LeafVE_DB.options.notificationSound then PlaySound("AuctionWindowOpen") end
  self.toastShowing = true
  self.toastFrame:Show()
  local fadeIn = 0 local fadeInFrame = CreateFrame("Frame")
  fadeInFrame:SetScript("OnUpdate", function()
    fadeIn = fadeIn + arg1
    if fadeIn >= 0.3 then self.toastFrame:SetAlpha(1) fadeInFrame:Hide()
      local hold = 0 local holdFrame = CreateFrame("Frame")
      holdFrame:SetScript("OnUpdate", function()
        hold = hold + arg1
        if hold >= 4 then holdFrame:Hide()
          local fadeOut = 0 local fadeOutFrame = CreateFrame("Frame")
          fadeOutFrame:SetScript("OnUpdate", function()
            fadeOut = fadeOut + arg1
            if fadeOut >= 0.3 then self.toastFrame:SetAlpha(0) self.toastFrame:Hide() self.toastShowing = false fadeOutFrame:Hide()
            else self.toastFrame:SetAlpha(1 - (fadeOut / 0.3)) end
          end)
        end
      end)
    else self.toastFrame:SetAlpha(fadeIn / 0.3) end
  end)
end

function LeafVE:CheckAndAwardBadge(playerName, badgeId)
  EnsureDB() playerName = ShortName(playerName) if not playerName then return end
  if not LeafVE_DB.badges[playerName] then LeafVE_DB.badges[playerName] = {} end
  if LeafVE_DB.badges[playerName][badgeId] then return false end
  LeafVE_DB.badges[playerName][badgeId] = Now()
  local badge = nil
  for i = 1, table.getn(BADGES) do
    if BADGES[i].id == badgeId then badge = BADGES[i] break end
  end
  if badge then
    local me = ShortName(UnitName("player"))
    if me and Lower(playerName) == Lower(me) then
      local badgeQuality = badge.quality or BADGE_QUALITY.COMMON
      local qr, qg, qb = GetBadgeQualityColor(badgeQuality)
      local qualityLabel = GetBadgeQualityLabel(badgeQuality)
      if LeafVE_DB.options.enableNotifications ~= false and LeafVE_DB.options.enableBadgeNotifications ~= false then
        self:ShowNotification("Badge Earned! ["..qualityLabel.."]", badge.name..": "..badge.desc, badge.icon, {qr, qg, qb, 1})
      end
      Print("|cFF"..RGBToHex(qr, qg, qb).."["..qualityLabel.."] Badge Earned:|r "..badge.name.." - "..badge.desc)
      if InGuild() then
        local badgeLink = "|cFF"..RGBToHex(qr, qg, qb).."|Hleafve_badge:"..badge.id.."|h["..badge.name.."]|h|r"
        local titleStr = ""
        if LeafVE_AchTest_DB and LeafVE_AchTest_DB[playerName] and LeafVE_AchTest_DB[playerName].equippedTitle and LeafVE_AchTest_DB[playerName].equippedTitle ~= "" then
          titleStr = "|cFFFF8000[" .. LeafVE_AchTest_DB[playerName].equippedTitle .. "]|r"
        end
        SendChatMessage(titleStr.."[LeafVE Note] received "..badgeLink.." for contributing to the guild!", "GUILD")
      end
      self:BroadcastBadges()
      if LeafVE.UI.cardCurrentPlayer == playerName then
        LeafVE.UI:UpdateCardRecentBadges(playerName)
      end
      if LeafVE.UI.panels and LeafVE.UI.panels.badges and LeafVE.UI.panels.badges:IsVisible() then
        LeafVE.UI:RefreshBadges()
      end
    end
  end
  return true
end

function LeafVE:CheckBadgeMilestones(playerName)
  EnsureDB()
  playerName = ShortName(playerName)
  if not playerName then return end
  
  -- Get player data
  local alltime = LeafVE_DB.alltime[playerName] or {L = 0, G = 0, S = 0}
  local totalPoints = (alltime.L or 0) + (alltime.G or 0) + (alltime.S or 0)
  
  -- === LOGIN & ACTIVITY ===
  if alltime.L >= 1 then 
    self:CheckAndAwardBadge(playerName, "first_login") 
  end
  if alltime.L >= 100 then 
    self:CheckAndAwardBadge(playerName, "total_logins_100") 
  end
  
  -- Login streaks (check if you have streak tracking)
  if LeafVE_DB.loginStreaks and LeafVE_DB.loginStreaks[playerName] then
    local streak = LeafVE_DB.loginStreaks[playerName].current or 0
    if streak >= 7 then 
      self:CheckAndAwardBadge(playerName, "login_streak_7") 
    end
    if streak >= 30 then 
      self:CheckAndAwardBadge(playerName, "login_streak_30") 
    end
  end
  
  -- === GROUP CONTENT ===
  local groupCount = LeafVE_DB.groupSessions[playerName] or 0
  if groupCount >= 1 then 
    self:CheckAndAwardBadge(playerName, "first_group") 
  end
  if groupCount >= 10 then 
    self:CheckAndAwardBadge(playerName, "group_10") 
  end
  if groupCount >= 50 then 
    self:CheckAndAwardBadge(playerName, "group_50") 
  end
  if groupCount >= 100 then 
    self:CheckAndAwardBadge(playerName, "group_100") 
  end
  
  -- === POINT MILESTONES ===
  if totalPoints >= 2500 then 
    self:CheckAndAwardBadge(playerName, "total_500") 
  end
  if totalPoints >= 5000 then 
    self:CheckAndAwardBadge(playerName, "total_1000") 
  end
  if totalPoints >= 10000 then 
    self:CheckAndAwardBadge(playerName, "total_2000") 
  end
  if totalPoints >= 25000 then 
    self:CheckAndAwardBadge(playerName, "total_5000") 
  end
  if totalPoints >= 50000 then 
    self:CheckAndAwardBadge(playerName, "total_10000") 
  end
  
  -- === RAID ATTENDANCE ===
  local attendance = LeafVE_DB.attendance[playerName] or {}
  local attendCount = table.getn(attendance)
  if attendCount >= 10 then 
    self:CheckAndAwardBadge(playerName, "attendance_10") 
  end
  if attendCount >= 50 then 
    self:CheckAndAwardBadge(playerName, "attendance_50") 
  end
  
  -- === GUILD LOYALTY (Time-based) ===
  -- You'll need to track guild join date - add this to your DB when someone joins
  if LeafVE_DB.guildJoinDate and LeafVE_DB.guildJoinDate[playerName] then
    local joinDate = LeafVE_DB.guildJoinDate[playerName]
    local daysInGuild = math.floor((Now() - joinDate) / SECONDS_PER_DAY)
    
    if daysInGuild >= 30 then 
      self:CheckAndAwardBadge(playerName, "guild_age_30") 
    end
    if daysInGuild >= 90 then 
      self:CheckAndAwardBadge(playerName, "guild_age_90") 
    end
    if daysInGuild >= 365 then 
      self:CheckAndAwardBadge(playerName, "guild_age_365") 
    end
  end
end

function LeafVE:GetBadgeProgress(playerName, badgeId)
  EnsureDB()
  local name = ShortName(playerName)
  if not name then return nil, nil end

  local me = ShortName(UnitName("player"))
  local isMe = (name == me)

  -- For other players use synced peer-progress data when available
  local peer = (not isMe) and LeafVE_DB.peerProgress and LeafVE_DB.peerProgress[name]

  local alltime = LeafVE_DB.alltime[name] or {L=0, G=0, S=0}
  -- Also check synced lboard alltime for non-local players
  if not isMe then
    local synced = LeafVE_DB.lboard and LeafVE_DB.lboard.alltime and LeafVE_DB.lboard.alltime[name]
    if synced then
      local sL = (synced.L or 0) + (synced.G or 0) + (synced.S or 0)
      local aL = (alltime.L or 0) + (alltime.G or 0) + (alltime.S or 0)
      if sL > aL then alltime = synced end
    end
  end
  local totalPoints = (alltime.L or 0) + (alltime.G or 0) + (alltime.S or 0)

  if badgeId == "total_logins_100" then
    return alltime.L or 0, 100
  elseif badgeId == "login_streak_7" then
    local streak
    if isMe then
      streak = (LeafVE_DB.loginStreaks and LeafVE_DB.loginStreaks[name] and LeafVE_DB.loginStreaks[name].current) or 0
    else
      streak = peer and peer.streak or 0
    end
    return streak, 7
  elseif badgeId == "login_streak_30" then
    local streak
    if isMe then
      streak = (LeafVE_DB.loginStreaks and LeafVE_DB.loginStreaks[name] and LeafVE_DB.loginStreaks[name].current) or 0
    else
      streak = peer and peer.streak or 0
    end
    return streak, 30
  elseif badgeId == "first_group" then
    local groups = isMe and ((LeafVE_DB.groupSessions and LeafVE_DB.groupSessions[name]) or 0) or (peer and peer.groups or 0)
    return groups, 1
  elseif badgeId == "group_10" then
    local groups = isMe and ((LeafVE_DB.groupSessions and LeafVE_DB.groupSessions[name]) or 0) or (peer and peer.groups or 0)
    return groups, 10
  elseif badgeId == "group_50" then
    local groups = isMe and ((LeafVE_DB.groupSessions and LeafVE_DB.groupSessions[name]) or 0) or (peer and peer.groups or 0)
    return groups, 50
  elseif badgeId == "group_100" then
    local groups = isMe and ((LeafVE_DB.groupSessions and LeafVE_DB.groupSessions[name]) or 0) or (peer and peer.groups or 0)
    return groups, 100
  elseif badgeId == "shoutout_received_10" or badgeId == "shoutout_received_50" then
    local count = 0
    for _, targets in pairs(LeafVE_DB.shoutouts or {}) do
      for t, _ in pairs(targets) do
        if Lower(t) == Lower(name) then count = count + 1 end
      end
    end
    return count, (badgeId == "shoutout_received_10") and 10 or 50
  elseif badgeId == "total_500" then
    return totalPoints, 2500
  elseif badgeId == "total_1000" then
    return totalPoints, 5000
  elseif badgeId == "total_2000" then
    return totalPoints, 10000
  elseif badgeId == "total_5000" then
    return totalPoints, 25000
  elseif badgeId == "total_10000" then
    return totalPoints, 50000
  elseif badgeId == "attendance_10" then
    local raids = isMe and table.getn(LeafVE_DB.attendance[name] or {}) or (peer and peer.raids or 0)
    return raids, 10
  elseif badgeId == "attendance_50" then
    local raids = isMe and table.getn(LeafVE_DB.attendance[name] or {}) or (peer and peer.raids or 0)
    return raids, 50
  elseif badgeId == "guild_age_30" or badgeId == "guild_age_90" or badgeId == "guild_age_365" then
    local joinTS
    if isMe then
      joinTS = LeafVE_DB.guildJoinDate and LeafVE_DB.guildJoinDate[name]
    else
      joinTS = (peer and peer.joinTS ~= 0 and peer.joinTS) or (LeafVE_DB.guildJoinDate and LeafVE_DB.guildJoinDate[name])
    end
    if joinTS then
      local days = math.floor((Now() - joinTS) / SECONDS_PER_DAY)
      if badgeId == "guild_age_30" then return days, 30 end
      if badgeId == "guild_age_90" then return days, 90 end
      return days, 365
    end
  end
  return nil, nil
end

function LeafVE:GetPlayerBadges(playerName)
  EnsureDB() playerName = ShortName(playerName) if not playerName then return {} end
  local playerBadges = LeafVE_DB.badges[playerName] or {} local badges = {}
  for i = 1, table.getn(BADGES) do
    local badge = BADGES[i]
    if playerBadges[badge.id] then table.insert(badges, {badge = badge, earnedAt = playerBadges[badge.id]}) end
  end
  table.sort(badges, function(a, b) return a.earnedAt > b.earnedAt end)
  return badges
end

function LeafVE:TrackAttendance()
  local inRaid = GetNumRaidMembers() > 0
  if not inRaid then return end
  EnsureDB() local me = ShortName(UnitName("player")) if not me then return end
  if not LeafVE_DB.attendance[me] then LeafVE_DB.attendance[me] = {} end
  local today = DayKey() local found = false
  for i = 1, table.getn(LeafVE_DB.attendance[me]) do
    if LeafVE_DB.attendance[me][i].date == today then found = true break end
  end
  if not found then
    table.insert(LeafVE_DB.attendance[me], {date = today, timestamp = Now()})
    self:AddToHistory(me, "A", 1, "Raid attendance")
    self:CheckBadgeMilestones(me)
  end
end

function LeafVE:AddPoints(playerName, pointType, amount)
  EnsureDB() playerName = ShortName(playerName) if not playerName then return end
  if pointType ~= POINT_TYPE_LOGIN and pointType ~= POINT_TYPE_GAMEPLAY and pointType ~= POINT_TYPE_SOCIAL then
    Print("ERROR: Invalid point type '"..tostring(pointType).."' — must be L, G, or S")
    return
  end
  amount = amount or 1 local day = DayKey()
  if not LeafVE_DB.global[day] then LeafVE_DB.global[day] = {} end
  if not LeafVE_DB.global[day][playerName] then LeafVE_DB.global[day][playerName] = {L = 0, G = 0, S = 0} end
  local dailyCap = LEAF_POINT_DAILY_CAP
  if dailyCap ~= 0 then
    local totals = LeafVE_DB.global[day][playerName]
    local currentTotal = (totals.L or 0) + (totals.G or 0) + (totals.S or 0)
    if currentTotal >= dailyCap then
      return 0
    end
    if currentTotal + amount > dailyCap then
      amount = dailyCap - currentTotal
    end
  end
  if amount <= 0 then
    return 0
  end
  LeafVE_DB.global[day][playerName][pointType] = (LeafVE_DB.global[day][playerName][pointType] or 0) + amount
  if not LeafVE_DB.alltime[playerName] then LeafVE_DB.alltime[playerName] = {L = 0, G = 0, S = 0} end
  LeafVE_DB.alltime[playerName][pointType] = (LeafVE_DB.alltime[playerName][pointType] or 0) + amount
  if not LeafVE_DB.season[playerName] then LeafVE_DB.season[playerName] = {L = 0, G = 0, S = 0} end
  LeafVE_DB.season[playerName][pointType] = (LeafVE_DB.season[playerName][pointType] or 0) + amount
  local me = ShortName(UnitName("player"))
  -- Show notification if this is the current player
  local isMe = me and Lower(playerName) == Lower(me)
  if isMe then
    local typeNames = {L = "Login", G = "Gameplay", S = "Social"}
    if not self.suppressPointNotification then
      if LeafVE_DB.options.enableNotifications ~= false and LeafVE_DB.options.enablePointNotifications ~= false then
        self:ShowNotification("Points Earned!", string.format("+%d %s Point%s", amount, typeNames[pointType] or "?", amount > 1 and "s" or ""), LEAF_EMBLEM, THEME.leaf)
      end
    end
  end
  self:CheckBadgeMilestones(playerName)
  return amount
end

function LeafVE:CheckDailyLogin()
  EnsureDB()
  local me = ShortName(UnitName("player"))
  if not me then return end
  local today = DayKey()
  if not LeafVE_DB.loginTracking[me] then LeafVE_DB.loginTracking[me] = {} end
  if LeafVE_DB.loginTracking[me][today] then return end
  local loginPts = 20
  -- Update login streak
  if not LeafVE_DB.loginStreaks[me] then
    LeafVE_DB.loginStreaks[me] = {current = 0, lastLogin = nil}
  end
  local streakData = LeafVE_DB.loginStreaks[me]
  local yesterday = DayKeyFromTS(Now() - SECONDS_PER_DAY)
  if streakData.lastLogin == yesterday then
    -- Consecutive day - increment streak
    streakData.current = (streakData.current or 0) + 1
  elseif streakData.lastLogin ~= today then
    -- Missed a day (or first ever login) - reset streak to 1
    streakData.current = 1
  end
  streakData.lastLogin = today
  local awarded = self:AddPoints(me, "L", loginPts)
  if awarded and awarded > 0 then
    self:AddToHistory(me, "L", awarded, "Daily login")
  end
  LeafVE_DB.loginTracking[me][today] = true
  if awarded and awarded > 0 then
    Print(string.format("Daily login point awarded! (+%d L)", awarded))
  end
end

function LeafVE:UpdateGuildRosterCache()
  local now = Now()
  if now - self.guildRosterCacheTime < GUILD_ROSTER_CACHE_DURATION then return end
  
  self.guildRosterCache = {} 

  if InGuild() then
  EnsureDB()
  -- Only request a fresh roster from the server periodically to avoid hammering it.
  if GuildRoster and (now - self.guildRosterRequestAt >= GUILD_ROSTER_CACHE_DURATION) then
    GuildRoster()
    self.guildRosterRequestAt = now
  end
  local n = GetNumGuildMembers and GetNumGuildMembers() or 0
  -- GuildRoster() is async; if data hasn't arrived yet, don't stamp the cache as
  -- valid so that the GUILD_ROSTER_UPDATE handler can trigger a real rebuild.
  if n == 0 then return end

  -- Get currently online members
  for i = 1, n do
    local name, rank, rankIndex, level, class, zone, note, officernote, online, status = GetGuildRosterInfo(i)
    name = ShortName(name)
    if name then
      local isOnline = false
      if online then 
        if type(online) == "number" then 
          isOnline = (online == 1) 
        else 
          isOnline = (online == true) 
        end 
      end
      
      local memberData = {
        name = name, 
        rank = rank, 
        rankIndex = rankIndex, 
        level = level, 
        class = class, 
        zone = zone, 
        note = note, 
        officernote = officernote, 
        online = isOnline, 
        status = status,
        lastSeen = now
      }
      
      self.guildRosterCache[Lower(name)] = memberData
      
      -- Store in persistent roster
      LeafVE_DB.persistentRoster[Lower(name)] = memberData
    end
  end
  
  -- Add offline members from persistent roster
  if LeafVE_DB.options.showOfflineMembers then
    for lowerName, memberData in pairs(LeafVE_DB.persistentRoster) do
      if not self.guildRosterCache[lowerName] then
        -- This member is offline, add them with offline flag
        local offlineCopy = {}
        for k, v in pairs(memberData) do
          offlineCopy[k] = v
        end
        offlineCopy.online = false
        offlineCopy.zone = "Offline"
        
        self.guildRosterCache[lowerName] = offlineCopy
      end
    end
  end
  end -- end if InGuild()
  
  self.guildRosterCacheTime = now
end

function LeafVE:GetGuildInfo(playerName)
  self:UpdateGuildRosterCache() playerName = ShortName(playerName) if not playerName then return nil end
  return self.guildRosterCache[Lower(playerName)]
end

function LeafVE:IsOfficer()
  if CanEditOfficerNote and CanEditOfficerNote() then return true end
  if CanGuildInvite and CanGuildInvite() then return true end
  return false
end

-- Returns true if the current player holds an admin guild rank (Anbu, Sannin, or Hokage).
function LeafVE:IsAdminRank()
  local me = ShortName(UnitName("player"))
  if not me then return false end
  self:UpdateGuildRosterCache()
  local info = self.guildRosterCache[Lower(me)]
  if info and info.rank then
    local lrank = Lower(Trim(info.rank))
    return ADMIN_RANKS[lrank] == true
  end
  return false
end

function LeafVE:RecordActivity()
  self.lastActivityTime = Now()
end

function LeafVE:IsPlayerInactive()
  if UnitIsAFK and UnitIsAFK("player") then
    return true
  end
  if self.lastActivityTime and (Now() - self.lastActivityTime) > AFK_TIMEOUT then
    return true
  end
  return false
end

-- Returns true if the current player holds an approved Leaf Village rank.
function LeafVE:HasLeafAccess()
  local me = ShortName(UnitName("player"))
  if not me then return false end
  self:UpdateGuildRosterCache()
  local info = self.guildRosterCache[Lower(me)]
  if info and info.rank then
    local lrank = Lower(Trim(info.rank))
    return ACCESS_RANKS[lrank] == true
  end
  return false
end

-- Returns true if `name` appears in the in-memory roster cache or the
-- persistent roster, covering the case where GetGuildInfo() returns nil.
function LeafVE:IsKnownGuildie(name)
  if not name then return false end
  local lname = Lower(name)
  return (self.guildRosterCache[lname] ~= nil)
    or (LeafVE_DB and LeafVE_DB.persistentRoster and LeafVE_DB.persistentRoster[lname] ~= nil)
end

function LeafVE:GetMemberGuildRank(name)
  if not name then return nil end
  local data = self.guildRosterCache[Lower(name)]
  return data and data.rank or nil
end

function LeafVE:GetGroupGuildies()
  local myGuild = GetGuildInfo("player")  -- may be nil early in the session
  self:UpdateGuildRosterCache()
  local guildies = {} local numMembers = GetNumRaidMembers() local isRaid = numMembers > 0
  if not isRaid then numMembers = GetNumPartyMembers() end
  if numMembers == 0 then return {} end
  for i = 1, numMembers do
    local unit = isRaid and "raid"..i or "party"..i
    if UnitExists(unit) and UnitIsConnected(unit) then
      local name = UnitName(unit) name = ShortName(name)
      local unitGuild = GetGuildInfo(unit)
      local isGuildie = (myGuild and unitGuild and unitGuild == myGuild)
        or self:IsKnownGuildie(name)
      if name and isGuildie then
        local rank = self:GetMemberGuildRank(name)
        if rank and VALID_GUILD_RANKS[rank] then
          table.insert(guildies, name)
        end
      end
    end
  end
  return guildies
end

function LeafVE:GetGroupHash(members) table.sort(members) return table.concat(members, ",") end

function LeafVE:OnGroupUpdate()
  local guildies = self:GetGroupGuildies() local numGuildies = table.getn(guildies)
  if numGuildies == 0 then self.currentGroupStart = nil self.currentGroupMembers = {} self.lastGroupAwardTime = nil return end
  local groupHash = self:GetGroupHash(guildies)
  if not self.currentGroupStart or groupHash ~= self:GetGroupHash(self.currentGroupMembers) then
    self.currentGroupStart = Now() self.currentGroupMembers = guildies self.lastGroupAwardTime = nil
    Print("Group leaf points are now active! (grouped with: "..table.concat(guildies, ", ")..")")
    return
  end
  EnsureDB()
  local groupInterval = GROUP_POINT_INTERVAL
  local now = Now()
  local nextAwardTime = (self.lastGroupAwardTime or self.currentGroupStart) + groupInterval
  if self.currentGroupStart and now >= nextAwardTime then
    local playerName = ShortName(UnitName("player"))
    if playerName then
      -- AFK / inactivity check
      if self:IsPlayerInactive() then
        self.lastGroupAwardTime = now
        Print("|cFFFF4444Group points skipped — you appear to be AFK or inactive!|r")
        return
      end
      local pointsPerGuildie = GROUP_POINTS
      -- Enforce daily cap for group points
      local today = DayKey()
      if not LeafVE_DB.groupPointsToday then LeafVE_DB.groupPointsToday = {} end
      if not LeafVE_DB.groupPointsToday[playerName] then LeafVE_DB.groupPointsToday[playerName] = {} end
      local todayData = LeafVE_DB.groupPointsToday[playerName]
      if todayData.date ~= today then
        todayData.date = today
        todayData.earned = 0
      end
      local points = pointsPerGuildie * numGuildies
      local awarded = self:AddPoints(playerName, "G", points)
      if awarded and awarded > 0 then
        todayData.earned = (todayData.earned or 0) + awarded
        self:AddToHistory(playerName, "G", awarded, "Grouped with "..numGuildies.." guildies: "..table.concat(guildies, ", "))
        LeafVE_DB.groupSessions[playerName] = (LeafVE_DB.groupSessions[playerName] or 0) + 1
        self:CheckBadgeMilestones(playerName)
      end
      self.lastGroupAwardTime = now
      if awarded and awarded > 0 then
        Print(string.format("Group points awarded! +%d LP (%d per guildie x%d guildies)", awarded, pointsPerGuildie, numGuildies))
      end
    end
  end
end

-------------------------------------------------
-- INSTANCE / BOSS / QUEST TRACKING
-------------------------------------------------

-------------------------------------------------
-- pfDB INTEGRATION (pfQuest database)
-------------------------------------------------

-- Snapshot the current quest log: title -> {level, isComplete}
function LeafVE:CacheQuestLog()
  local newCache = {}
  local numEntries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
  for i = 1, numEntries do
    local title, level, _, isHeader, isComplete = GetQuestLogTitle(i)
    if title and not isHeader then
      newCache[title] = { level = level, isComplete = isComplete or 0 }
    end
  end
  self.questLogCache = newCache
end

-- Diff the current quest log against the last snapshot to find the completed quest.
-- Returns the title of the quest that just disappeared, or nil.
function LeafVE:GetCompletedQuestTitle()
  local numEntries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
  -- First pass: find a quest marked complete (isComplete ~= 0) that is still in the log.
  -- In 1.12, QUEST_TURNED_IN often fires before QUEST_LOG_UPDATE removes the quest,
  -- so the completed quest is still there with isComplete = 1.
  for i = 1, numEntries do
    local title, _, _, isHeader, isComplete = GetQuestLogTitle(i)
    if title and not isHeader and isComplete and isComplete ~= 0 then
      return title
    end
  end
  -- Second pass: if the quest is already gone (QUEST_LOG_UPDATE fired first),
  -- find it by diffing the cached log against what is currently in the log.
  -- Only count as a turn-in if it was marked complete before disappearing.
  -- Abandoned quests have isComplete = 0 and should not award points.
  local current = {}
  for i = 1, numEntries do
    local title, _, _, isHeader = GetQuestLogTitle(i)
    if title and not isHeader then current[title] = true end
  end
  for title, data in pairs(self.questLogCache) do
    if not current[title] then
      if data and data.isComplete and data.isComplete ~= 0 then
        return title
      end
    end
  end
  return nil
end

function LeafVE:OnZoneChanged()
  local wasInInstance = self.instanceJoinedAt ~= nil
  local inInstance, instanceType
  if IsInInstance then
    inInstance, instanceType = IsInInstance()
  else
    inInstance = false
    instanceType = "none"
  end
  local zone = GetRealZoneText and GetRealZoneText() or "Unknown"
  if inInstance then
    if not wasInInstance then
      self.instanceJoinedAt = Now()
      self.instanceZone = zone
      self.instanceHasGuildie = false
      self.instanceBossesKilledThisRun = 0
      self.instanceIsRaid = (instanceType == "raid")
      local guildies = self:GetGroupGuildies()
      if table.getn(guildies) > 0 then
        self.instanceHasGuildie = true
      end
    end
  else
    if wasInInstance then
      self:OnInstanceExit()
    end
  end
end

function LeafVE:OnInstanceExit()
  if not self.instanceJoinedAt then return end
  local runDuration = Now() - self.instanceJoinedAt
  local me = ShortName(UnitName("player"))
  if not me then
    self.instanceJoinedAt = nil
    return
  end
  -- Require the player to have been present for at least INSTANCE_MIN_PRESENCE_PCT of
  -- the minimum expected run length (GROUP_MIN_TIME). This gates out teleporting out
  -- immediately while still crediting fast dungeon clears.
  local minPresence = math.floor(GROUP_MIN_TIME * INSTANCE_MIN_PRESENCE_PCT)
  if self.instanceHasGuildie and runDuration >= minPresence then
    EnsureDB()
    local today = DayKey()
    if not LeafVE_DB.instanceTracking[me] then
      LeafVE_DB.instanceTracking[me] = {}
    end
    if not LeafVE_DB.instanceTracking[me][today] then
      LeafVE_DB.instanceTracking[me][today] = {completions = 0, bosses = 0}
    end
    local tracked = LeafVE_DB.instanceTracking[me][today]
    local instCap = (LeafVE_DB.options and LeafVE_DB.options.instanceMaxDaily) or INSTANCE_MAX_DAILY
    local instPts = self.instanceIsRaid and RAID_COMPLETION_POINTS or INSTANCE_COMPLETION_POINTS
    if instCap == 0 or tracked.completions < instCap then
      if self.instanceBossesKilledThisRun > 0 then
        local awarded = self:AddPoints(me, "G", instPts)
        if awarded and awarded > 0 then
          tracked.completions = tracked.completions + 1
          tracked.bosses = tracked.bosses + self.instanceBossesKilledThisRun
          self:AddToHistory(me, "G", awarded, "Instance completion: "..(self.instanceZone or "Unknown"))
          Print(string.format("Instance complete! +%d G (%d boss%s)", awarded, self.instanceBossesKilledThisRun, self.instanceBossesKilledThisRun ~= 1 and "es" or ""))
        end
      else
        Print("Instance exited with no bosses slain. No completion points awarded.")
      end
    end
  end
  self.instanceJoinedAt = nil
  self.instanceZone = nil
  self.instanceHasGuildie = false
  self.instanceBossesKilledThisRun = 0
  self.instanceIsRaid = false
end

function LeafVE:OnBossKillChat(msg)
  -- Match "BossName is slain by PlayerName." or "BossName is slain by PlayerName!"
  local bossName = string.match(msg, "^(.+) is slain by .+[%.!]$")
  -- Fallback: match "BossName dies." (environmental or alternate death messages)
  if not bossName then bossName = string.match(msg, "^(.+) dies%.$") end
  if not bossName then return end
  if not KNOWN_BOSSES[bossName] then return end
  local me = ShortName(UnitName("player"))
  if not me then return end
  EnsureDB()

  -- Dedup: ignore if this boss was already awarded within the last 10 seconds
  local now = Now()
  if self.recentBossKills[bossName] and (now - self.recentBossKills[bossName]) < BOSS_KILL_DEDUP_WINDOW then return end
  self.recentBossKills[bossName] = now

  -- Require at least one other guildie in the group (solo runs don't count)
  local guildies = self:GetGroupGuildies()
  local hasGuildie = table.getn(guildies) > 0
  if not hasGuildie then return end

  self.instanceBossesKilledThisRun = self.instanceBossesKilledThisRun + 1
  local bossPts = self.instanceIsRaid and RAID_BOSS_POINTS or INSTANCE_BOSS_POINTS
  self.suppressPointNotification = true
  local awarded = self:AddPoints(me, "G", bossPts)
  self.suppressPointNotification = false
  if awarded and awarded > 0 then
    self:AddToHistory(me, "G", awarded, bossName.." slain (guild group)")
    if LeafVE_DB.options.enableNotifications ~= false and LeafVE_DB.options.enablePointNotifications ~= false then
      self:ShowNotification("Boss Slain!", string.format("%s  +%d LP", bossName, awarded), LEAF_EMBLEM, THEME.gold)
    end
    Print(string.format("Boss slain: %s! +%d LP", bossName, awarded))
  end
end

function LeafVE:OnQuestTurnedIn()
  local me = ShortName(UnitName("player"))
  if not me then return end

  -- Guard against double-awarding if QUEST_LOG_UPDATE fires multiple times
  -- for the same turn-in within a short window (e.g. ~3 seconds).
  if Now() - (self.lastQuestTurnInTime or 0) < 3 then
    self:CacheQuestLog()
    return
  end
  -- Set the timestamp immediately as an early lock so back-to-back calls within
  -- the same frame are blocked before any async work or points are awarded.
  self.lastQuestTurnInTime = Now()

  -- Only award quest LP when grouped with at least one guildie
  local guildies = self:GetGroupGuildies()
  if table.getn(guildies) == 0 then
    self:CacheQuestLog()
    return
  end

  EnsureDB()
  local today = DayKey()

  -- Identify which quest was just completed from the pending turn-in capture
  local questTitle = LeafVE.pendingQuestTurnIn

  -- Prevent awarding LP for the same quest title more than once per character
  -- (only when we could actually identify the quest; unknown quests fall through to daily cap)
  if questTitle then
    if not LeafVE_DB.questCompletions[me] then
      LeafVE_DB.questCompletions[me] = {}
    end
    if LeafVE_DB.questCompletions[me][questTitle] then
      -- Already awarded LP for this quest; update cache and return
      self:CacheQuestLog()
      return
    end
  end

  -- Daily cap tracked per character
  if not LeafVE_DB.questTracking[me] then
    LeafVE_DB.questTracking[me] = {}
  end
  if not LeafVE_DB.questTracking[me][today] then
    LeafVE_DB.questTracking[me][today] = 0
  end
  local questPts = QUEST_POINTS
  local awarded = self:AddPoints(me, "G", questPts)
  if awarded and awarded > 0 then
    LeafVE_DB.questTracking[me][today] = LeafVE_DB.questTracking[me][today] + 1
    if questTitle and LeafVE_DB.questCompletions[me] then
      LeafVE_DB.questCompletions[me][questTitle] = Now()
    end
  end
  local displayTitle = questTitle or "Quest"
  local histMsg = "Quest completion"
  if questTitle then histMsg = "Quest: "..questTitle end
  if awarded and awarded > 0 then
    self:AddToHistory(me, "G", awarded, histMsg)
    if LeafVE_DB.options.enableNotifications ~= false and LeafVE_DB.options.enablePointNotifications ~= false then
      self:ShowNotification("Quest Complete!", string.format("[%s] +%d LP", displayTitle, awarded), QUEST_ICON, THEME.gold)
    end
    Print(string.format("Quest complete! [%s] +%d G", displayTitle, awarded))
  end
  -- Update the cached log to reflect the turn-in
  self:CacheQuestLog()
end

function LeafVE:GiveShoutout(targetName, reason)
  EnsureDB() 
  local giverName = ShortName(UnitName("player")) 
  targetName = ShortName(targetName)
  if not giverName or not targetName then 
    Print("Error: Invalid player names") 
    return false 
  end
  if Lower(giverName) == Lower(targetName) then 
    Print("You cannot shout out yourself!") 
    return false 
  end
  
  -- Daily cap is tracked per giver character
  local today = DayKey()
  if not LeafVE_DB.shoutouts[giverName] then 
    LeafVE_DB.shoutouts[giverName] = {} 
  end
  
  local count = 0
  for tname, timestamp in pairs(LeafVE_DB.shoutouts[giverName]) do
    local shoutoutDay = DayKeyFromTS(timestamp)
    if shoutoutDay == today then 
      count = count + 1 
    else 
      LeafVE_DB.shoutouts[giverName][tname] = nil 
    end
  end
  
  local maxDaily = (LeafVE_DB.options and LeafVE_DB.options.shoutoutMaxDaily) or SHOUTOUT_MAX_PER_DAY
  if count >= maxDaily then 
    Print(string.format("You've used all %d shoutouts for today!", maxDaily)) 
    return false 
  end
  
  local targetInfo = self:GetGuildInfo(targetName)
  if not targetInfo and LeafVE_DB.persistentRoster then
    targetInfo = LeafVE_DB.persistentRoster[Lower(targetName)]
  end
  if not targetInfo then 
    Print("Player "..targetName.." is not in the guild!") 
    return false 
  end

  local shoutPts = (LeafVE_DB.options and LeafVE_DB.options.shoutoutPoints) or 10
  LeafVE_DB.shoutouts[giverName][targetName] = Now()
  local awardedTarget = self:AddPoints(targetName, "S", shoutPts)
  if awardedTarget and awardedTarget > 0 then
    self:AddToHistory(targetName, "S", awardedTarget, "Shoutout from "..giverName..(reason and (": "..reason) or ""))
  end
  self:CheckAndAwardBadge(giverName, "first_shoutout_given")
  
  if InGuild() then
    reason = reason and Trim(reason) or ""
    
    local title = nil
    if LeafVE_AchTest_DB and LeafVE_AchTest_DB[giverName] and LeafVE_AchTest_DB[giverName].equippedTitle then
      title = LeafVE_AchTest_DB[giverName].equippedTitle
    end
    
    local message
    if title and title ~= "" then
      message = string.format("[%s] recognizes %s!", title, targetName)
    else
      message = string.format("recognizes %s!", targetName)
    end
    
    if reason ~= "" then 
      message = message .. " - " .. reason 
    end
    
    message = message .. " (+"..shoutPts.." Leaf Points each)"
    SendChatMessage(message, "GUILD")
    SendAddonMessage("LeafVE", "SHOUTOUT:"..giverName..":"..targetName, "GUILD")
  end
  
  local remaining = maxDaily - count - 1
  Print(string.format("Shoutout sent to %s! (%d remaining today)", targetName, remaining))
  return true
end

-------------------------------------------------
-- SHOUTOUT V2 (FEATURE D)
-------------------------------------------------

-- Helper: ensure shoutouts_v2 daily table is current (resets when the date changes).
local function LVL_EnsureShoutoutDailyReset(sv2)
  local today = DayKey()
  if sv2.daily.dateKey ~= today then
    sv2.daily.dateKey = today
    sv2.daily.awards = {}
  end
end

-- Check if a giver can award a shoutout to a target.
-- Returns: canAward (bool), reason (string or nil).
function LVL_CanShoutout(giverKey, targetKey)
  EnsureDB()
  if not giverKey or not targetKey then return false, "Invalid names" end
  if Lower(giverKey) == Lower(targetKey) then return false, "Cannot shoutout yourself" end
  local sv2 = LeafVE_DB.shoutouts_v2
  LVL_EnsureShoutoutDailyReset(sv2)
  -- Daily limit per giver
  local awardsToday = sv2.daily.awards[giverKey] or 0
  if awardsToday >= SHOUTOUT_V2_MAX_PER_DAY then
    return false, string.format("Daily limit reached (%d/%d)", awardsToday, SHOUTOUT_V2_MAX_PER_DAY)
  end
  -- Giver cooldown: check last time this giver gave to this specific target today
  local givenToTarget = sv2.given[giverKey] and sv2.given[giverKey][targetKey]
  if givenToTarget then
    local elapsed = Now() - givenToTarget
    if elapsed < SHOUTOUT_GIVER_COOLDOWN then
      local rem = SHOUTOUT_GIVER_COOLDOWN - elapsed
      return false, string.format("Giver cooldown: %s remaining", LVL_FormatTime(rem))
    end
  end
  -- Target cooldown: check last time this target received from this giver
  local rcvFromGiver = sv2.received[targetKey] and sv2.received[targetKey][giverKey]
  if rcvFromGiver then
    local elapsed = Now() - rcvFromGiver
    if elapsed < SHOUTOUT_TARGET_COOLDOWN then
      local rem = SHOUTOUT_TARGET_COOLDOWN - elapsed
      return false, string.format("Target cooldown: %s remaining", LVL_FormatTime(rem))
    end
  end
  return true, nil
end

-- Award a shoutout from giverKey to targetKey using the V2 system.
function LVL_AwardShoutout(giverKey, targetKey)
  EnsureDB()
  local canAward, reason = LVL_CanShoutout(giverKey, targetKey)
  if not canAward then
    Print("|cff00ff00[LVL]|r Cannot give shoutout: " .. (reason or "unknown"))
    return false
  end
  local sv2 = LeafVE_DB.shoutouts_v2
  local now = Now()
  LVL_EnsureShoutoutDailyReset(sv2)
  -- Record in given table
  if not sv2.given[giverKey] then sv2.given[giverKey] = {} end
  sv2.given[giverKey][targetKey] = now
  -- Record in received table
  if not sv2.received[targetKey] then sv2.received[targetKey] = {} end
  sv2.received[targetKey][giverKey] = now
  -- Increment daily count
  sv2.daily.awards[giverKey] = (sv2.daily.awards[giverKey] or 0) + 1
  -- Award points to target
  local awarded = LeafVE:AddPoints(targetKey, "S", SHOUTOUT_V2_POINTS)
  if awarded and awarded > 0 then
    LeafVE:AddToHistory(targetKey, "S", awarded, "Shoutout V2 from " .. giverKey)
  end
  LeafVE:CheckAndAwardBadge(giverKey, "first_shoutout_given")
  local remaining = SHOUTOUT_V2_MAX_PER_DAY - sv2.daily.awards[giverKey]
  Print(string.format("|cff00ff00[LVL]|r Shoutout sent to %s! +%d LP (%d remaining today)", targetKey, SHOUTOUT_V2_POINTS, remaining))
  -- Broadcast via guild channel
  if InGuild() then
    SendAddonMessage("LeafVE", "SHOUTOUT:" .. giverKey .. ":" .. targetKey, "GUILD")
  end
  return true
end


  EnsureDB()

  if not LeafVE_AchTest_DB or not LeafVE_AchTest_DB.achievements then return end

  -- Build entries: "achID:timestamp" pairs
  local entries = {}
  for achId, timestamp in pairs(LeafVE_AchTest_DB.achievements) do
    if type(timestamp) == "number" and timestamp > 0 then
      table.insert(entries, achId..":"..tostring(timestamp))
    end
  end

  if table.getn(entries) == 0 then return end

  if not InGuild() then return end

  -- Send in chunks to stay within the 255-byte WoW addon message limit.
  -- "ACHSYNC:" prefix uses 8 chars (255 - 8 = 247 available). Use 220 for safety.
  local MAX_CHUNK = 220
  local chunk = {}
  local chunkLen = 0

  for _, entry in ipairs(entries) do
    local sep = (chunkLen > 0) and 1 or 0
    if chunkLen > 0 and chunkLen + sep + string.len(entry) > MAX_CHUNK then
      SendAddonMessage("LeafVE", "ACHSYNC:"..table.concat(chunk, ","), "GUILD")
      chunk = {}
      chunkLen = 0
      sep = 0
    end
    table.insert(chunk, entry)
    chunkLen = chunkLen + sep + string.len(entry)
  end

  if table.getn(chunk) > 0 then
    SendAddonMessage("LeafVE", "ACHSYNC:"..table.concat(chunk, ","), "GUILD")
  end
end

function LeafVE:BroadcastBadges()
  local me = ShortName(UnitName("player"))
  if not me then return end
  
  EnsureDB()
  local myBadges = LeafVE_DB.badges[me] or {}
  
  -- Build compressed badge list: "badgeID:timestamp,badgeID:timestamp,..."
  local badgeData = {}
  for badgeId, timestamp in pairs(myBadges) do
    table.insert(badgeData, badgeId..":"..timestamp)
  end
  
  if table.getn(badgeData) > 0 and InGuild() then
    local message = table.concat(badgeData, ",")
    SendAddonMessage("LeafVE", "BADGES:"..message, "GUILD")
  end
end

-- Broadcast this player's badge-progress counters so guildmates can display
-- accurate progress bars when viewing this player's badge collection.
-- Called on login alongside BroadcastBadges().
function LeafVE:BroadcastBadgeProgress()
  if not InGuild() then return end
  local me = ShortName(UnitName("player"))
  if not me then return end
  EnsureDB()
  local streak = (LeafVE_DB.loginStreaks and LeafVE_DB.loginStreaks[me] and LeafVE_DB.loginStreaks[me].current) or 0
  local groups  = (LeafVE_DB.groupSessions and LeafVE_DB.groupSessions[me]) or 0
  local raids   = table.getn(LeafVE_DB.attendance and LeafVE_DB.attendance[me] or {})
  local joinTS  = (LeafVE_DB.guildJoinDate and LeafVE_DB.guildJoinDate[me]) or 0
  local payload = string.format("BADGEPROG:%s:%d:%d:%d:%d", me, streak, groups, raids, joinTS)
  SendAddonMessage("LeafVE", payload, "GUILD")
end

function LeafVE:BroadcastLeaderboardData()
  local me = ShortName(UnitName("player"))
  if not me then return end
  
  EnsureDB()
  
  local wk = WeekKey()
  local data = {}
  
  -- Collect ALL known players from local alltime and synced lboard data
  -- so that players who were offline when events occurred can still receive the full leaderboard
  local knownPlayers = {}
  for name, _ in pairs(LeafVE_DB.alltime) do
    knownPlayers[name] = true
  end
  for name, _ in pairs(LeafVE_DB.lboard.alltime) do
    knownPlayers[name] = true
  end
  
  -- Also include all players from this week's aggregation and synced weekly data
  local weekAgg = AggForThisWeek()
  local syncedWeek = (type(LeafVE_DB.lboard.weekly[wk]) == "table") and LeafVE_DB.lboard.weekly[wk] or {}
  for name, _ in pairs(weekAgg) do
    knownPlayers[name] = true
  end
  for name, _ in pairs(syncedWeek) do
    knownPlayers[name] = true
  end
  
  for name, _ in pairs(knownPlayers) do
    -- Lifetime: use only directly-observed alltime data as the base.
    local lbase = LeafVE_DB.alltime[name] or {L = 0, G = 0, S = 0}
    local lL, lG, lS = lbase.L or 0, lbase.G or 0, lbase.S or 0
    if lL + lG + lS > 0 then
      table.insert(data, string.format("L:%s:%d:%d:%d", name, lL, lG, lS))
    end

    -- Weekly: use only locally-aggregated data as the base (never synced weekly).
    local wbase = weekAgg[name]
    local wL = wbase and (wbase.L or 0) or 0
    local wG = wbase and (wbase.G or 0) or 0
    local wS = wbase and (wbase.S or 0) or 0
    if wL + wG + wS > 0 then
      table.insert(data, string.format("W%s:%s:%d:%d:%d", wk, name, wL, wG, wS))
    end
  end
  
  -- Send in chunks to stay within the 255-byte WoW addon message limit.
  -- "LBOARD:" prefix uses 7 chars (255 - 7 = 248 available). We use 220 to
  -- stay well under the limit and account for any protocol overhead.
  if not InGuild() then return end
  local MAX_CHUNK = 220
  local chunk = {}
  local chunkLen = 0
  
  for _, entry in ipairs(data) do
    local sep = (chunkLen > 0) and 1 or 0  -- account for comma separator
    if chunkLen > 0 and chunkLen + sep + string.len(entry) > MAX_CHUNK then
      SendAddonMessage("LeafVE", "LBOARD:"..table.concat(chunk, ","), "GUILD")
      chunk = {}
      chunkLen = 0
      sep = 0
    end
    table.insert(chunk, entry)
    chunkLen = chunkLen + sep + string.len(entry)
  end
  
  if table.getn(chunk) > 0 then
    SendAddonMessage("LeafVE", "LBOARD:"..table.concat(chunk, ","), "GUILD")
  end

  -- Propagate the admin reset timestamp so offline players who missed the original
  -- broadcast will wipe their stale data when they receive this sync response.
  if LeafVE_GlobalDB and LeafVE_GlobalDB.lastAdminResetTS then
    SendAddonMessage("LeafVE", "RESETTS:"..LeafVE_GlobalDB.lastAdminResetTS, "GUILD")
  end

end

function LeafVE:SendResyncRequest()
  local now = Now()
  if (now - self.lastResyncRequestAt) < LBOARD_RESYNC_COOLDOWN then return end
  self.lastResyncRequestAt = now
  if InGuild() then
    SendAddonMessage("LeafVE", "LBOARDREQ", "GUILD")
    SendAddonMessage("LeafVE", "SHOUTSYNCREQ", "GUILD")
  end
end

-- Serialize the full shoutout history table and broadcast it in chunks.
-- Format per entry: "giver\31target\31timestamp", entries separated by ",".
-- Message format: "SHOUTSYNC:N/T:payload" where N is chunk number, T is total.
function LeafVE:BroadcastShoutoutHistory()
  EnsureDB()

  local entries = {}
  for giver, targets in pairs(LeafVE_DB.shoutouts) do
    for target, timestamp in pairs(targets) do
      if type(timestamp) == "number" and timestamp > 0 then
        table.insert(entries, giver..SEP..target..SEP..tostring(timestamp))
      end
    end
  end

  if table.getn(entries) == 0 then return end
  if not InGuild() then return end

  -- Build payload chunks; "SHOUTSYNC:NN/TT:" prefix is at most ~16 chars,
  -- so 200-char payloads keep each message well under WoW's 255-byte limit.
  local MAX_PAYLOAD = 200
  local chunks = {}
  local current = ""
  for _, entry in ipairs(entries) do
    if current == "" then
      current = entry
    elseif string.len(current) + 1 + string.len(entry) <= MAX_PAYLOAD then
      current = current..","..entry
    else
      table.insert(chunks, current)
      current = entry
    end
  end
  if current ~= "" then
    table.insert(chunks, current)
  end

  local total = table.getn(chunks)
  for i = 1, total do
    SendAddonMessage("LeafVE", "SHOUTSYNC:"..i.."/"..total..":"..chunks[i], "GUILD")
  end
end

-- Idempotently merge received shoutout history into the local DB.
-- Awards +1 S point only for entries not previously known; updates timestamps
-- when incoming data is newer (without awarding an extra point).
function LeafVE:MergeShoutoutHistory(payload)
  EnsureDB()
  if not payload or payload == "" then return end

  local me = ShortName(UnitName("player"))
  local updated = false
  local startPos = 1

  while startPos <= string.len(payload) do
    local commaPos = string.find(payload, ",", startPos)
    local entry
    if commaPos then
      entry = string.sub(payload, startPos, commaPos - 1)
      startPos = commaPos + 1
    else
      entry = string.sub(payload, startPos)
      startPos = string.len(payload) + 1
    end

    -- Parse "giver\31target\31timestamp"
    local sep1 = string.find(entry, SEP)
    if sep1 then
      local giver = string.sub(entry, 1, sep1 - 1)
      local rest = string.sub(entry, sep1 + 1)
      local sep2 = string.find(rest, SEP)
      if sep2 then
        local target = string.sub(rest, 1, sep2 - 1)
        local timestamp = tonumber(string.sub(rest, sep2 + 1))
        if giver ~= "" and target ~= "" and timestamp then
          -- Skip entries where we are the giver (already recorded locally)
          if not (me and Lower(me) == Lower(giver)) then
            if not LeafVE_DB.shoutouts[giver] then
              LeafVE_DB.shoutouts[giver] = {}
            end
            local existing = LeafVE_DB.shoutouts[giver][target]
            if not existing then
              -- New entry: record it for history/badge tracking only.
              -- Points for shoutouts are awarded in real-time via the SHOUTOUT: handler.
              LeafVE_DB.shoutouts[giver][target] = timestamp
              self:CheckBadgeMilestones(target)
              self:CheckAndAwardBadge(giver, "first_shoutout_given")
              self:CheckAndAwardBadge(target, "first_shoutout_received")
              updated = true
            elseif timestamp > existing then
              -- Newer timestamp for an already-known entry: update only, no extra point
              LeafVE_DB.shoutouts[giver][target] = timestamp
              updated = true
            end
          end
        end
      end
    end
  end

  -- Refresh leaderboard panels if any are currently open
  if updated and LeafVE.UI and LeafVE.UI.panels then
    if LeafVE.UI.panels.leaderLife and LeafVE.UI.panels.leaderLife:IsVisible() then
      LeafVE.UI:RefreshLeaderboard("leaderLife")
    end
    if LeafVE.UI.panels.leaderWeek and LeafVE.UI.panels.leaderWeek:IsVisible() then
      LeafVE.UI:RefreshLeaderboard("leaderWeek")
    end
  end
end

function LeafVE:BroadcastPlayerNote(noteText)
  local me = ShortName(UnitName("player"))
  if not me then return end
  
  noteText = noteText or ""
  
  -- Escape special characters
  noteText = string.gsub(noteText, "|", "||")
  
  if InGuild() then
    SendAddonMessage("LeafVE", "NOTE:"..noteText, "GUILD")
  end
end

-------------------------------------------------
-- GEAR CACHING & BROADCAST
-------------------------------------------------
LeafVE.lastGearBroadcast  = 0
LeafVE.lastStatsBroadcast = 0

function LeafVE:ParseItemIDFromLink(link)
  if not link then return nil end
  local s = string.find(link, "|Hitem:")
  if not s then return nil end
  local rest = string.sub(link, s + 7)
  local colonPos = string.find(rest, ":")
  local idStr
  if colonPos then
    idStr = string.sub(rest, 1, colonPos - 1)
  else
    idStr = rest
  end
  local id = tonumber(idStr)
  if id and id > 0 then return id end
  return nil
end

function LeafVE:CaptureGearForUnit(unitToken)
  if not unitToken then return {} end
  local slots = {}
  for i = 1, table.getn(GEAR_SLOT_NAMES) do
    local slotName = GEAR_SLOT_NAMES[i]
    local slotId = GetInventorySlotInfo(slotName)
    if slotId then
      local link = GetInventoryItemLink(unitToken, slotId)
      local itemId = self:ParseItemIDFromLink(link)
      if itemId then
        slots[slotName] = itemId
      end
    end
  end
  return slots
end

function LeafVE:CaptureAndCacheMyGear()
  EnsureDB()
  local me = ShortName(UnitName("player"))
  if not me then return end
  local nameLower = Lower(me)
  if not LeafVE_GlobalDB.gearCache[nameLower] then
    LeafVE_GlobalDB.gearCache[nameLower] = {}
  end
  local slots = self:CaptureGearForUnit("player")
  LeafVE_GlobalDB.gearCache[nameLower].broadcast = {
    updatedAt = Now(),
    slots = slots,
  }
end

function LeafVE:CaptureAndCacheInspectedGear(playerName, unitToken)
  if not playerName or not unitToken then return end
  EnsureDB()
  local nameLower = Lower(ShortName(playerName) or playerName)
  if not LeafVE_GlobalDB.gearCache[nameLower] then
    LeafVE_GlobalDB.gearCache[nameLower] = {}
  end
  local slots = self:CaptureGearForUnit(unitToken)
  LeafVE_GlobalDB.gearCache[nameLower].inspected = {
    updatedAt = Now(),
    slots = slots,
  }
end

function LeafVE:BroadcastMyGear()
  if not InGuild() then return end
  local now = Now()
  if (now - self.lastGearBroadcast) < GEAR_BROADCAST_THROTTLE then return end
  self.lastGearBroadcast = now

  self:CaptureAndCacheMyGear()

  local me = ShortName(UnitName("player"))
  if not me then return end
  local cache = LeafVE_GlobalDB.gearCache and LeafVE_GlobalDB.gearCache[Lower(me)]
  local snapshot = cache and cache.broadcast
  if not snapshot or not snapshot.slots then return end

  local header = "GEAR:" .. me .. ":" .. tostring(snapshot.updatedAt) .. ":"
  local maxPayload = 200

  local chunk = {}
  local chunkLen = 0
  for i = 1, table.getn(GEAR_SLOT_NAMES) do
    local slotName = GEAR_SLOT_NAMES[i]
    local itemId = snapshot.slots[slotName]
    if itemId then
      local entry = slotName .. "=" .. tostring(itemId)
      local entryLen = string.len(entry)
      local sepLen = chunkLen > 0 and 1 or 0
      if chunkLen > 0 and chunkLen + sepLen + entryLen > maxPayload then
        SendAddonMessage("LeafVE", header .. table.concat(chunk, ","), "GUILD")
        chunk = {}
        chunkLen = 0
        sepLen = 0
      end
      table.insert(chunk, entry)
      chunkLen = chunkLen + sepLen + entryLen
    end
  end
  if table.getn(chunk) > 0 then
    SendAddonMessage("LeafVE", header .. table.concat(chunk, ","), "GUILD")
  end
end

-------------------------------------------------
-- BCS STATS COMPUTE & BROADCAST
-------------------------------------------------

-- Compute all BCS-based stats for the local player and return a key/value table.
-- Short keys are used so the serialized payload fits in one 255-byte message.
function LeafVE:ComputeMyBCSStats()
  if not BCS then return nil end
  BCS.needScanGear    = true
  BCS.needScanTalents = true
  BCS.needScanAuras   = true
  BCS.needScanSkills  = true
  BCS:RunScans()
  BCS.needScanGear    = false
  BCS.needScanTalents = false
  BCS.needScanAuras   = false
  BCS.needScanSkills  = false

  local apBase, apPos, apNeg = UnitAttackPower("player")
  local ap = (apBase or 0) + (apPos or 0) + (apNeg or 0)
  local rap = 0
  if UnitRangedAttackPower then
    local rb, rp, rn = UnitRangedAttackPower("player")
    rap = (rb or 0) + (rp or 0) + (rn or 0)
  end

  local hit          = BCS:GetHitRating() or 0
  local mcrit        = BCS:GetCritChance() or 0
  local rhit         = BCS:GetRangedHitRating() or 0
  local rcrit        = BCS:GetRangedCritChance() or 0
  local mhsk         = BCS:GetMHWeaponSkill() or 0
  local rsk          = BCS:GetRangedWeaponSkill() or 0
  local sp           = BCS:GetSpellPower() or 0
  local shit         = BCS:GetSpellHitRating() or 0
  local scrit        = BCS:GetSpellCritChance() or 0
  local heal         = BCS:GetHealingPower() or 0
  local manaBase, _, mp5 = BCS:GetManaRegen()
  manaBase = manaBase or 0; mp5 = mp5 or 0
  local _, spellHaste = BCS:GetHaste()
  spellHaste = spellHaste or 0
  local dodge  = GetDodgeChance and GetDodgeChance() or 0
  local parry  = GetParryChance and GetParryChance() or 0
  local block  = GetBlockChance and GetBlockChance() or 0
  local defBase, defMod = 0, 0
  if UnitDefense then
    defBase, defMod = UnitDefense("player")
    defBase = defBase or 0; defMod = defMod or 0
  end
  local defense = defBase + defMod
  local _, armor = UnitArmor("player")
  armor = armor or 0
  local _, str  = UnitStat("player", 1)
  local _, agi  = UnitStat("player", 2)
  local _, sta  = UnitStat("player", 3)
  local _, int_ = UnitStat("player", 4)
  local _, spi  = UnitStat("player", 5)

  return {
    ap = ap,   hi = hit,  mc = mcrit,
    ra = rap,  rh = rhit, rc = rcrit,
    ms = mhsk, rs = rsk,
    sp = sp,   sh = shit, sc = scrit, ss = spellHaste,
    he = heal, m5 = mp5,  mr = manaBase,
    st = str or 0,  ag = agi or 0,  sa = sta or 0,
    ["in"] = int_ or 0, si = spi or 0,
    ar = armor, de = defense, dg = dodge, pa = parry, bl = block,
  }
end

-- Serialize a stats table (from ComputeMyBCSStats) and broadcast it over the
-- guild addon channel so guildmates can cache and display it.
function LeafVE:BroadcastMyStats()
  if not InGuild() then return end
  if not BCS then return end
  local now = Now()
  if (now - self.lastStatsBroadcast) < STATS_BROADCAST_THROTTLE then return end
  self.lastStatsBroadcast = now

  local me = ShortName(UnitName("player"))
  if not me then return end

  local s = self:ComputeMyBCSStats()
  if not s then return end

  EnsureDB()
  LeafVE_GlobalDB.gearStatsCache[Lower(me)] = { stats = s, updatedAt = now }

  -- Serialize non-zero values with short keys; floats get 1 decimal place
  local parts = {}
  local function addStat(key, val, fmt)
    if val and val ~= 0 then
      table.insert(parts, key .. "=" .. string.format(fmt, val))
    end
  end
  addStat("ap", s.ap,  "%d")
  addStat("hi", s.hi,  "%d")
  addStat("mc", s.mc,  "%.1f")
  addStat("ra", s.ra,  "%d")
  addStat("rh", s.rh,  "%d")
  addStat("rc", s.rc,  "%.1f")
  addStat("ms", s.ms,  "%d")
  addStat("rs", s.rs,  "%d")
  addStat("sp", s.sp,  "%d")
  addStat("sh", s.sh,  "%d")
  addStat("sc", s.sc,  "%.1f")
  addStat("ss", s.ss,  "%d")
  addStat("he", s.he,  "%d")
  addStat("m5", s.m5,  "%d")
  addStat("mr", s.mr,  "%.0f")
  addStat("st", s.st,  "%d")
  addStat("ag", s.ag,  "%d")
  addStat("sa", s.sa,  "%d")
  addStat("in", s["in"], "%d")
  addStat("si", s.si,  "%d")
  addStat("ar", s.ar,  "%d")
  addStat("de", s.de,  "%d")
  addStat("dg", s.dg,  "%.1f")
  addStat("pa", s.pa,  "%.1f")
  addStat("bl", s.bl,  "%.1f")

  local payload = "STATS:" .. me .. ":" .. tostring(now) .. ":" .. table.concat(parts, ",")
  SendAddonMessage("LeafVE", payload, "GUILD")
end
local function VersionLessThan(a, b)
  local amaj, amin = string.match(a or "0.0", "(%d+)%.(%d+)")
  local bmaj, bmin = string.match(b or "0.0", "(%d+)%.(%d+)")
  amaj, amin = tonumber(amaj) or 0, tonumber(amin) or 0
  bmaj, bmin = tonumber(bmaj) or 0, tonumber(bmin) or 0
  if amaj ~= bmaj then return amaj < bmaj end
  return amin < bmin
end

-- Returns true when a sender's known version meets LeafVE.minCompatVersion.
-- If the sender's version has not been received yet (VERSIONRSP not yet seen),
-- we optimistically allow the message so we don't silently drop data on the
-- very first login before any version exchange has occurred.
local function IsSenderCompatible(sender)
  if not LeafVE.versionResponses then return true end
  local senderVer = LeafVE.versionResponses[sender]
  if not senderVer then return true end
  return not VersionLessThan(senderVer, LeafVE.minCompatVersion)
end

function LeafVE:OnAddonMessage(prefix, message, channel, sender)
  -- Handle LVL prefix messages (alt linking and guild-wide wipes)
  if prefix == "LVL" then
    if channel ~= "GUILD" and channel ~= "PARTY" and channel ~= "RAID" then return end
    sender = ShortName(sender)
    if not sender then return end
    local me = ShortName(UnitName("player"))

    -- MERGE_REQ|altKey|mainKey|altPoints
    if string.sub(message, 1, 10) == "MERGE_REQ|" then
      local rest = string.sub(message, 11)
      local p1 = string.find(rest, "|")
      if not p1 then return end
      local altKey = string.sub(rest, 1, p1 - 1)
      rest = string.sub(rest, p1 + 1)
      local p2 = string.find(rest, "|")
      local mainKey, altPtsStr
      if p2 then
        mainKey = string.sub(rest, 1, p2 - 1)
        altPtsStr = string.sub(rest, p2 + 1)
      else
        mainKey = rest
        altPtsStr = "0"
      end
      -- Officers see the merge request
      if LeafVE:IsAdminRank() then
        EnsureDB()
        if not LeafVE_DB.pendingMerge then LeafVE_DB.pendingMerge = {} end
        LeafVE_DB.pendingMerge[altKey] = { main = mainKey, t = Now() }
        Print(string.format("|cff00ff00[LVL]|r Merge request: %s wants to link to %s (%s pts). Use /lve altapprove %s %s", altKey, mainKey, altPtsStr, altKey, mainKey))
      end
      return
    end

    -- MERGE_APPROVE|altKey|mainKey
    if string.sub(message, 1, 14) == "MERGE_APPROVE|" then
      if not LVL_IsAuthorizedSender(sender) then return end
      local rest = string.sub(message, 15)
      local p1 = string.find(rest, "|")
      if not p1 then return end
      local altKey = string.sub(rest, 1, p1 - 1)
      local mainKey = string.sub(rest, p1 + 1)
      EnsureDB()
      LeafVE_DB.links[altKey] = mainKey
      LeafVE_DB.lastLinkChange[altKey] = Now()
      if LeafVE_DB.pendingMerge then LeafVE_DB.pendingMerge[altKey] = nil end
      if me and Lower(me) == Lower(altKey) then
        Print(string.format("|cff00ff00[LVL]|r Your alt has been linked to %s by %s!", mainKey, sender))
        if LeafVE.UI and LeafVE.UI.panels and LeafVE.UI.panels.alt and LeafVE.UI.panels.alt:IsVisible() then
          LeafVE.UI:RefreshAltPanel()
        end
      end
      return
    end

    -- WIPE_ALL|wipeId
    if string.sub(message, 1, 9) == "WIPE_ALL|" then
      if not LVL_IsAuthorizedSender(sender) then return end
      local wipeId = string.sub(message, 10)
      EnsureDB()
      local stored = (LeafVE_DB.meta and LeafVE_DB.meta.lastWipeId) or ""
      if wipeId == stored then return end  -- already processed
      if LeafVE_DB.meta then LeafVE_DB.meta.lastWipeId = wipeId end
      LVL_FullWipeLocal()
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LVL]|r Guild-wide point reset received from " .. sender .. ". All data cleared.")
      return
    end
    return
  end

  if prefix ~= "LeafVE" then return end
  if channel ~= "GUILD" and channel ~= "PARTY" and channel ~= "RAID" then return end
  
  sender = ShortName(sender)
  if not sender then return end
  
  -- Handle version check request
  if message == "VERSIONREQ" then
    local me = ShortName(UnitName("player"))
    if me and sender ~= me then
      SendAddonMessage("LeafVE", "VERSIONRSP:"..LeafVE.version, "GUILD")
    end
    return
  end

  -- Handle version check response
  if string.sub(message, 1, 11) == "VERSIONRSP:" then
    local ver = string.sub(message, 12)
    if not LeafVE.versionResponses then LeafVE.versionResponses = {} end
    LeafVE.versionResponses[sender] = ver
    -- Only print version warnings when explicitly requested via the Admin "Check Addon Versions"
    -- button AND only for players with an admin guild rank.
    if LeafVE.adminVersionCheckActive and LeafVE:IsAdminRank() then
      local myVer = LeafVE.version
      if not LeafVE.shownVersionNag and VersionLessThan(myVer, ver) then
        LeafVE.shownVersionNag = true
        Print("|cFFFFAA00⚠ Your Leaf Village Legends addon is outdated! You have v"..myVer..", latest is v"..ver..". Please update!|r")
      end
      if VersionLessThan(ver, LeafVE.minCompatVersion) then
        if not LeafVE.warnedOldVersion then LeafVE.warnedOldVersion = {} end
        if not LeafVE.warnedOldVersion[sender] then
          LeafVE.warnedOldVersion[sender] = true
          Print("|cFFFF4444⚠ "..sender.." is running an outdated version (v"..ver..") and their synced data will not be accepted. Ask them to update to v"..LeafVE.minCompatVersion.."+.|r")
        end
      end
    end
    return
  end

  -- Handle on-demand resync request
  if message == "LBOARDREQ" then
    local me = ShortName(UnitName("player"))
    if me and sender ~= me then
      local now = Now()
      if (now - self.lastResyncRespondAt) >= LBOARD_RESPOND_COOLDOWN then
        self.lastResyncRespondAt = now
        LeafVE:BroadcastLeaderboardData()
      end
      if (now - self.lastShoutSyncRespondAt) >= SHOUT_SYNC_RESPOND_COOLDOWN then
        self.lastShoutSyncRespondAt = now
        LeafVE:BroadcastShoutoutHistory()
      end
      if (now - self.lastBadgeSyncRespondAt) >= LBOARD_RESPOND_COOLDOWN then
        self.lastBadgeSyncRespondAt = now
        LeafVE:BroadcastBadges()
      end
      if (now - self.lastAchSyncRespondAt) >= LBOARD_RESPOND_COOLDOWN then
        self.lastAchSyncRespondAt = now
        LeafVE:BroadcastMyAchievements()
      end
    end
    return
  end

  -- Handle badge reset broadcast for a single player
  if string.sub(message, 1, 12) == "BADGESRESET:" then
    local targetPlayer = ShortName(string.sub(message, 13))
    if targetPlayer then
      EnsureDB()
      LeafVE_DB.badges[targetPlayer] = {}
      LeafVE_DB.alltime[targetPlayer] = nil
      LeafVE_DB.season[targetPlayer] = nil
      LeafVE_DB.loginStreaks[targetPlayer] = nil
      LeafVE_DB.loginTracking[targetPlayer] = nil
      LeafVE_DB.groupSessions[targetPlayer] = nil
      LeafVE_DB.attendance[targetPlayer] = nil
      LeafVE_DB.pointHistory[targetPlayer] = nil
      LeafVE_DB.instanceTracking[targetPlayer] = nil
      LeafVE_DB.questTracking[targetPlayer] = nil
      LeafVE_DB.questCompletions[targetPlayer] = nil
      LeafVE_DB.lboard.alltime[targetPlayer] = nil
      for wk, wkData in pairs(LeafVE_DB.lboard.weekly) do
        if type(wkData) == "table" then wkData[targetPlayer] = nil end
      end
      for day, dayData in pairs(LeafVE_DB.global) do
        if type(dayData) == "table" then dayData[targetPlayer] = nil end
      end
      for _, targets in pairs(LeafVE_DB.shoutouts) do
        if type(targets) == "table" then targets[targetPlayer] = nil end
      end
      LeafVE_DB.shoutouts[targetPlayer] = nil
      if LeafVE_GlobalDB.achievementCache then
        LeafVE_GlobalDB.achievementCache[targetPlayer] = nil
      end
      if LeafVE.UI and LeafVE.UI.Refresh then
        LeafVE.UI:Refresh()
      end
    end
    return
  end

  -- Handle global badge reset broadcast (all players)
  if message == "BADGESRESETALL" then
    EnsureDB()
    LeafVE_DB.badges = {}
    LeafVE_DB.alltime      = {}
    LeafVE_DB.season       = {}
    LeafVE_DB.global       = {}
    LeafVE_DB.loginStreaks  = {}
    LeafVE_DB.loginTracking = {}
    LeafVE_DB.groupSessions = {}
    LeafVE_DB.groupCooldowns = {}
    LeafVE_DB.shoutouts    = {}
    LeafVE_DB.attendance   = {}
    LeafVE_DB.pointHistory = {}
    LeafVE_DB.weeklyRecap  = {}
    LeafVE_DB.instanceTracking = {}
    LeafVE_DB.questTracking = {}
    LeafVE_DB.questCompletions = {}
    LeafVE_DB.lboard       = { alltime = {}, weekly = {}, season = {}, updatedAt = {} }
    LeafVE_GlobalDB.achievementCache = {}
    if LeafVE_AchTest_DB and LeafVE_AchTest_DB.achievements then
      LeafVE_AchTest_DB.achievements = {}
    end
    if LeafVE.UI and LeafVE.UI.Refresh then
      LeafVE.UI:Refresh()
    end
    return
  end

  -- Parse badge sync message
  if string.sub(message, 1, 7) == "BADGES:" then
    if not IsSenderCompatible(sender) then return end
    local badgeData = string.sub(message, 8)
    
    EnsureDB()
    if not LeafVE_DB.badges[sender] then
      LeafVE_DB.badges[sender] = {}
    end
    
    -- Parse badge data (Vanilla WoW compatible)
    local badges = {}
    local startPos = 1
    
    while startPos <= string.len(badgeData) do
      local commaPos = string.find(badgeData, ",", startPos)
      local badgeEntry
      
      if commaPos then
        badgeEntry = string.sub(badgeData, startPos, commaPos - 1)
        startPos = commaPos + 1
      else
        badgeEntry = string.sub(badgeData, startPos)
        startPos = string.len(badgeData) + 1
      end
      
      -- Parse individual badge: "badgeID:timestamp"
      local colonPos = string.find(badgeEntry, ":")
      if colonPos then
        local badgeId = string.sub(badgeEntry, 1, colonPos - 1)
        local timestamp = string.sub(badgeEntry, colonPos + 1)
        badges[badgeId] = tonumber(timestamp)
      end
    end
    
    -- Merge received badges (never discard locally-known badges; keep earliest timestamp)
    if not LeafVE_DB.badges[sender] then
      LeafVE_DB.badges[sender] = {}
    end
    for badgeId, timestamp in pairs(badges) do
      if not LeafVE_DB.badges[sender][badgeId] then
        LeafVE_DB.badges[sender][badgeId] = timestamp
      else
        LeafVE_DB.badges[sender][badgeId] = math.min(LeafVE_DB.badges[sender][badgeId], timestamp)
      end
    end
    
    local count = 0
    for _ in pairs(badges) do count = count + 1 end
    
    -- Refresh UI if viewing this player
    if LeafVE.UI and LeafVE.UI.cardCurrentPlayer == sender then
      LeafVE.UI:UpdateCardRecentBadges(sender)
    end
    
    return

  -- Parse badge-progress sync message: BADGEPROG:name:streak:groups:raids:joinTS
  elseif string.sub(message, 1, 10) == "BADGEPROG:" then
    local rest = string.sub(message, 11)
    -- split on ":"
    local parts = {}
    local s = 1
    while s <= string.len(rest) do
      local c = string.find(rest, ":", s)
      if c then
        table.insert(parts, string.sub(rest, s, c - 1))
        s = c + 1
      else
        table.insert(parts, string.sub(rest, s))
        s = string.len(rest) + 1
      end
    end
    if table.getn(parts) >= 5 then
      local pname   = ShortName(parts[1]) or parts[1]
      local streak  = tonumber(parts[2]) or 0
      local groups  = tonumber(parts[3]) or 0
      local raids   = tonumber(parts[4]) or 0
      local joinTS  = tonumber(parts[5]) or 0
      EnsureDB()
      if not LeafVE_DB.peerProgress then LeafVE_DB.peerProgress = {} end
      LeafVE_DB.peerProgress[pname] = { streak = streak, groups = groups, raids = raids, joinTS = joinTS }
      -- Refresh badge tab if it is currently showing this player
      if LeafVE.UI and LeafVE.UI.cardCurrentPlayer == pname then
        if LeafVE.UI.panels and LeafVE.UI.panels.badges and LeafVE.UI.panels.badges:IsVisible() then
          LeafVE.UI:RefreshBadges()
        end
      end
    end
    return
    
  -- Parse shoutout sync message
  elseif string.sub(message, 1, 9) == "SHOUTOUT:" then
    if not IsSenderCompatible(sender) then return end
    local shoutData = string.sub(message, 10)
    local colonPos = string.find(shoutData, ":")
    if colonPos then
      local msgGiver = string.sub(shoutData, 1, colonPos - 1)
      local targetName = string.sub(shoutData, colonPos + 1)
      -- Validate both names are non-empty
      if msgGiver ~= "" and targetName ~= "" then
        -- Verify sender matches the declared giver (security check)
        if Lower(sender) == Lower(msgGiver) then
          local me = ShortName(UnitName("player"))
          -- Skip if we are the giver (already recorded via AddPoints in GiveShoutout)
          if not (me and Lower(me) == Lower(msgGiver)) then
            EnsureDB()
            -- Deduplicate: only record if not already tracked for today
            local today = DayKey()
            local alreadyRecorded = false
            if LeafVE_DB.shoutouts[msgGiver] and LeafVE_DB.shoutouts[msgGiver][targetName] then
              local existingDay = DayKeyFromTS(LeafVE_DB.shoutouts[msgGiver][targetName])
              if existingDay == today then
                alreadyRecorded = true
              end
            end
            if not alreadyRecorded then
              if not LeafVE_DB.shoutouts[msgGiver] then
                LeafVE_DB.shoutouts[msgGiver] = {}
              end
              LeafVE_DB.shoutouts[msgGiver][targetName] = Now()
              local shoutPtsIncoming = (LeafVE_DB.options and LeafVE_DB.options.shoutoutPoints) or 10
              self:AddPoints(targetName, "S", shoutPtsIncoming)
            end
            -- If we are the shoutout recipient, award received badges on our machine
            if me and Lower(me) == Lower(targetName) then
              self:CheckAndAwardBadge(targetName, "first_shoutout_received")
              local rcvCount = 0
              for g, _ in pairs(LeafVE_DB.shoutouts) do
                for t, _ in pairs(LeafVE_DB.shoutouts[g]) do
                  if Lower(t) == Lower(targetName) then rcvCount = rcvCount + 1 end
                end
              end
              if rcvCount >= 10 then self:CheckAndAwardBadge(targetName, "shoutout_received_10") end
              if rcvCount >= 50 then self:CheckAndAwardBadge(targetName, "shoutout_received_50") end
            end
          end
        end
      end
    end
    return

  -- Parse player note sync message
  elseif string.sub(message, 1, 5) == "NOTE:" then
    local noteText = string.sub(message, 6)
    
    -- Unescape special characters
    noteText = string.gsub(noteText, "||", "|")
    
    EnsureDB()
    if not LeafVE_GlobalDB.playerNotes then
      LeafVE_GlobalDB.playerNotes = {}
    end
    
    LeafVE_GlobalDB.playerNotes[sender] = noteText
    
    -- Refresh UI if viewing this player
    if LeafVE.UI and LeafVE.UI.cardCurrentPlayer == sender then
      if LeafVE.UI.cardNotesEdit then
        LeafVE.UI.cardNotesEdit:SetText(noteText)
      end
    end
    
    return
    
    -- **NEW: Parse leaderboard sync message**
  elseif string.sub(message, 1, 7) == "LBOARD:" then
    -- Ignore our own broadcasts: WoW echoes guild addon messages back to the sender.
    -- Processing our own echo would store already-pooled data as the base for the next
    -- broadcast, causing alt G/S contributions to accumulate every 5 minutes.
    local me = ShortName(UnitName("player"))
    if me and sender == me then return end
    if not IsSenderCompatible(sender) then return end
    local lboardData = string.sub(message, 8)
    
    -- Parse comma-separated player entries
    local startPos = 1
    while startPos <= string.len(lboardData) do
      local commaPos = string.find(lboardData, ",", startPos)
      local playerEntry
      
      if commaPos then
        playerEntry = string.sub(lboardData, startPos, commaPos - 1)
        startPos = commaPos + 1
      else
        playerEntry = string.sub(lboardData, startPos)
        startPos = string.len(lboardData) + 1
      end
      
      LeafVE:ReceiveLeaderboardData(sender, playerEntry)
    end  -- ← CLOSE THE WHILE LOOP
    
    -- Refresh leaderboards if open
    if LeafVE.UI and LeafVE.UI.panels then
      if LeafVE.UI.panels.leaderLife and LeafVE.UI.panels.leaderLife:IsVisible() then
        LeafVE.UI:RefreshLeaderboard("leaderLife")
      end
      if LeafVE.UI.panels.leaderWeek and LeafVE.UI.panels.leaderWeek:IsVisible() then
        LeafVE.UI:RefreshLeaderboard("leaderWeek")
      end
    end
    
    return

  -- Handle shoutout history sync request
  elseif message == "SHOUTSYNCREQ" then
    local me = ShortName(UnitName("player"))
    if me and sender ~= me then
      local now = Now()
      if (now - self.lastShoutSyncRespondAt) >= SHOUT_SYNC_RESPOND_COOLDOWN then
        self.lastShoutSyncRespondAt = now
        LeafVE:BroadcastShoutoutHistory()
      end
    end
    return

  -- Handle chunked shoutout history sync payload
  elseif string.sub(message, 1, 10) == "SHOUTSYNC:" then
    if not IsSenderCompatible(sender) then return end
    local rest = string.sub(message, 11)
    local slashPos = string.find(rest, "/")
    if not slashPos then return end
    local chunkNum = tonumber(string.sub(rest, 1, slashPos - 1))
    local afterSlash = string.sub(rest, slashPos + 1)
    local colonPos2 = string.find(afterSlash, ":")
    if not colonPos2 then return end
    local totalChunks = tonumber(string.sub(afterSlash, 1, colonPos2 - 1))
    local payload = string.sub(afterSlash, colonPos2 + 1)
    if not chunkNum or not totalChunks or chunkNum < 1 or totalChunks < 1 then return end
    -- Buffer chunks per sender; reset if a new sync starts (different total)
    if not self.shoutSyncBuffer[sender] or self.shoutSyncBuffer[sender].total ~= totalChunks then
      self.shoutSyncBuffer[sender] = {total = totalChunks, chunks = {}}
    end
    self.shoutSyncBuffer[sender].chunks[chunkNum] = payload
    -- Check if all chunks have been received
    local received = 0
    for i = 1, totalChunks do
      if self.shoutSyncBuffer[sender].chunks[i] then received = received + 1 end
    end
    if received == totalChunks then
      local parts = {}
      for i = 1, totalChunks do
        table.insert(parts, self.shoutSyncBuffer[sender].chunks[i])
      end
      self.shoutSyncBuffer[sender] = nil
      self:MergeShoutoutHistory(table.concat(parts, ","))
    end
    return

  -- Handle hard reset of all Leaf Points (admin broadcast)
  elseif string.sub(message, 1, 25) == "LVE_ADMIN_RESET_LEAF_ALL:" then
    -- Validate sender is an admin rank before applying the reset
    local senderInfo = LeafVE.guildRosterCache[Lower(sender)]
    local senderRank = senderInfo and senderInfo.rank and Lower(senderInfo.rank) or ""
    if ADMIN_RANKS[senderRank] then
      -- "LVE_ADMIN_RESET_LEAF_ALL:" is 25 chars; timestamp starts at position 26
      local incomingTS = tonumber(string.sub(message, 26)) or 0
      local localTS = LeafVE_GlobalDB and LeafVE_GlobalDB.lastAdminResetTS or 0
      if incomingTS > 0 and incomingTS > localTS then
        EnsureDB()
        LeafVE_GlobalDB.lastAdminResetTS = incomingTS
        LeafVE:HardResetLeafPoints_Local()
      end
    end
    return

  -- Handle hard reset of achievement leaderboard (admin broadcast)
  elseif string.sub(message, 1, 28) == "LVE_ADMIN_RESET_ACHIEVE_ALL:" then
    -- Validate sender is an admin rank before applying the reset
    local senderInfo = LeafVE.guildRosterCache[Lower(sender)]
    local senderRank = senderInfo and senderInfo.rank and Lower(senderInfo.rank) or ""
    if ADMIN_RANKS[senderRank] then
      LeafVE:HardResetAchievementLeaderboard_Local()
    end
    return

  -- Handle admin config broadcast
  elseif string.sub(message, 1, 17) == "LVE_ADMIN_CONFIG:" then
    -- No longer used; configurable admin settings have been removed.
    return

  -- Handle propagated admin reset timestamp (peer-to-peer propagation for offline catch-up)
  elseif string.sub(message, 1, 8) == "RESETTS:" then
    local incomingTS = tonumber(string.sub(message, 9)) or 0
    local localTS = LeafVE_GlobalDB and LeafVE_GlobalDB.lastAdminResetTS or 0
    if incomingTS > 0 and incomingTS > localTS then
      EnsureDB()
      LeafVE_GlobalDB.lastAdminResetTS = incomingTS
      LeafVE:HardResetLeafPoints_Local()
    end
    return

  -- Handle achievement data sync from a guild member
  elseif string.sub(message, 1, 8) == "ACHSYNC:" then
    if not IsSenderCompatible(sender) then return end
    local achData = string.sub(message, 9)
    EnsureDB()
    if not LeafVE_GlobalDB.achievementCache then
      LeafVE_GlobalDB.achievementCache = {}
    end
    if not LeafVE_GlobalDB.achievementCache[sender] then
      LeafVE_GlobalDB.achievementCache[sender] = {}
    end
    -- Parse "achID:timestamp,achID:timestamp,..." entries
    local startPos = 1
    while startPos <= string.len(achData) do
      local commaPos = string.find(achData, ",", startPos)
      local entry
      if commaPos then
        entry = string.sub(achData, startPos, commaPos - 1)
        startPos = commaPos + 1
      else
        entry = string.sub(achData, startPos)
        startPos = string.len(achData) + 1
      end
      local colonPos = string.find(entry, ":")
      if colonPos then
        local achId = string.sub(entry, 1, colonPos - 1)
        local timestamp = tonumber(string.sub(entry, colonPos + 1))
        if achId ~= "" and timestamp then
          if not LeafVE_GlobalDB.achievementCache[sender][achId] then
            LeafVE_GlobalDB.achievementCache[sender][achId] = timestamp
          else
            LeafVE_GlobalDB.achievementCache[sender][achId] = math.min(
              LeafVE_GlobalDB.achievementCache[sender][achId], timestamp)
          end
        end
      end
    end
    -- After parsing all entries, compute and cache total points
    local totalPts = 0
    for achId, _ in pairs(LeafVE_GlobalDB.achievementCache[sender]) do
      if achId ~= "_totalPoints" then
        local meta = LeafVE_AchTest and LeafVE_AchTest.GetAchievementMeta and LeafVE_AchTest.GetAchievementMeta(achId)
        local pts = (meta and meta.points) or DEFAULT_ACHIEVEMENT_POINTS
        totalPts = totalPts + pts
      end
    end
    LeafVE_GlobalDB.achievementCache[sender]._totalPoints = totalPts
    -- Refresh the achievement leaderboard panel if it is visible
    if LeafVE.UI and LeafVE.UI.panels then
      if LeafVE.UI.panels.achievements and LeafVE.UI.panels.achievements:IsVisible() then
        LeafVE.UI:RefreshAchievementsLeaderboard()
      end
    end
    return

  -- Handle leaderboard zero-out broadcast from admin (bypasses higher-total-wins guard)
  elseif string.sub(message, 1, 22) == "LVE_RESET_LBOARD_ZERO:" then
    -- Validate sender is an admin rank before applying the reset
    local senderInfo = LeafVE.guildRosterCache[Lower(sender)]
    local senderRank = senderInfo and senderInfo.rank and Lower(senderInfo.rank) or ""
    if ADMIN_RANKS[senderRank] then
      EnsureDB()
      LeafVE_DB.lboard = { alltime = {}, weekly = {}, season = {}, updatedAt = {} }
      if LeafVE.UI and LeafVE.UI.panels then
        if LeafVE.UI.panels.leaderLife and LeafVE.UI.panels.leaderLife:IsVisible() then
          LeafVE.UI:RefreshLeaderboard("leaderLife")
        end
        if LeafVE.UI.panels.leaderWeek and LeafVE.UI.panels.leaderWeek:IsVisible() then
          LeafVE.UI:RefreshLeaderboard("leaderWeek")
        end
      end
    end
    return

  -- Handle BCS stats broadcast from a guild member
  elseif string.sub(message, 1, 6) == "STATS:" then
    local rest = string.sub(message, 7)
    -- Format: STATS:<playerName>:<updatedAt>:<key>=<val>,...
    local firstColon = string.find(rest, ":")
    if not firstColon then return end
    local declaredName = string.sub(rest, 1, firstColon - 1)
    if Lower(sender) ~= Lower(ShortName(declaredName) or declaredName) then return end
    rest = string.sub(rest, firstColon + 1)
    local secondColon = string.find(rest, ":")
    if not secondColon then return end
    local updatedAt = tonumber(string.sub(rest, 1, secondColon - 1)) or Now()
    local statData = string.sub(rest, secondColon + 1)

    EnsureDB()
    local nameLower = Lower(sender)
    local cached = LeafVE_GlobalDB.gearStatsCache[nameLower]
    if cached and cached.updatedAt and updatedAt < cached.updatedAt then return end

    local stats = {}
    local startPos = 1
    local statDataLen = string.len(statData)
    while startPos <= statDataLen do
      local commaPos = string.find(statData, ",", startPos)
      local entry
      if commaPos then
        entry = string.sub(statData, startPos, commaPos - 1)
        startPos = commaPos + 1
      else
        entry = string.sub(statData, startPos)
        startPos = statDataLen + 1
      end
      local eqPos = string.find(entry, "=")
      if eqPos then
        local k = string.sub(entry, 1, eqPos - 1)
        local v = tonumber(string.sub(entry, eqPos + 1))
        if k ~= "" and v then stats[k] = v end
      end
    end

    LeafVE_GlobalDB.gearStatsCache[nameLower] = { stats = stats, updatedAt = updatedAt }

    -- Refresh gear popup if currently viewing this sender
    if LeafVE.UI and LeafVE.UI.gearPopup and LeafVE.UI.gearPopup:IsVisible() then
      if LeafVE.UI.cardCurrentPlayer and Lower(LeafVE.UI.cardCurrentPlayer) == nameLower then
        LeafVE.UI:RefreshGearPopup(LeafVE.UI.cardCurrentPlayer)
      end
    end
    return

  -- Handle gear cache broadcast from a guild member
  elseif string.sub(message, 1, 5) == "GEAR:" then
    local rest = string.sub(message, 6)
    -- Format: GEAR:<playerName>:<updatedAt>:<slotName>=<itemID>,...
    local firstColon = string.find(rest, ":")
    if not firstColon then return end
    local declaredName = string.sub(rest, 1, firstColon - 1)
    -- Basic spoof prevention: sender must match declared name (case-insensitive)
    if Lower(sender) ~= Lower(ShortName(declaredName) or declaredName) then return end
    rest = string.sub(rest, firstColon + 1)
    local secondColon = string.find(rest, ":")
    if not secondColon then return end
    local updatedAt = tonumber(string.sub(rest, 1, secondColon - 1)) or Now()
    local slotData = string.sub(rest, secondColon + 1)

    EnsureDB()
    if not LeafVE_GlobalDB.gearCache then LeafVE_GlobalDB.gearCache = {} end
    local nameLower = Lower(sender)
    if not LeafVE_GlobalDB.gearCache[nameLower] then
      LeafVE_GlobalDB.gearCache[nameLower] = {}
    end
    if not LeafVE_GlobalDB.gearCache[nameLower].broadcast then
      LeafVE_GlobalDB.gearCache[nameLower].broadcast = { updatedAt = 0, slots = {} }
    end
    -- Merge slot entries (accept if message timestamp >= cached timestamp)
    if updatedAt >= LeafVE_GlobalDB.gearCache[nameLower].broadcast.updatedAt then
      LeafVE_GlobalDB.gearCache[nameLower].broadcast.updatedAt = updatedAt
      local startPos = 1
      while startPos <= string.len(slotData) do
        local commaPos = string.find(slotData, ",", startPos)
        local entry
        if commaPos then
          entry = string.sub(slotData, startPos, commaPos - 1)
          startPos = commaPos + 1
        else
          entry = string.sub(slotData, startPos)
          startPos = string.len(slotData) + 1
        end
        local eqPos = string.find(entry, "=")
        if eqPos then
          local slotName = string.sub(entry, 1, eqPos - 1)
          local itemId = tonumber(string.sub(entry, eqPos + 1))
          if slotName ~= "" and itemId then
            LeafVE_GlobalDB.gearCache[nameLower].broadcast.slots[slotName] = itemId
          end
        end
      end
    end
    -- Refresh gear popup if the viewed player is this sender
    if LeafVE.UI and LeafVE.UI.gearPopup and LeafVE.UI.gearPopup:IsVisible() then
      if LeafVE.UI.cardCurrentPlayer and Lower(LeafVE.UI.cardCurrentPlayer) == nameLower then
        LeafVE.UI:RefreshGearPopup(LeafVE.UI.cardCurrentPlayer)
      end
    end
    return

  end  -- ← CLOSE THE OnAddonMessage FUNCTION
end
      
      function LeafVE:ReceiveLeaderboardData(sender, playerData)
  EnsureDB()
  
  -- Parse "L:PlayerName:L:G:S" (lifetime) or "W<weekKey>:PlayerName:L:G:S" (weekly, new format)
  -- Also accepts old "W:PlayerName:L:G:S" (unknown week → stored under current week key)
  local colonPos1 = string.find(playerData, ":")
  if not colonPos1 then return end
  
  local dataType = string.sub(playerData, 1, colonPos1 - 1) -- "L", "W", or "W20260217"
  local rest = string.sub(playerData, colonPos1 + 1)
  
  local colonPos2 = string.find(rest, ":")
  if not colonPos2 then return end
  
  local playerName = string.sub(rest, 1, colonPos2 - 1)
  local rest2 = string.sub(rest, colonPos2 + 1)
  
  local colonPos3 = string.find(rest2, ":")
  if not colonPos3 then return end
  
  local L = tonumber(string.sub(rest2, 1, colonPos3 - 1)) or 0
  local rest3 = string.sub(rest2, colonPos3 + 1)
  
  local colonPos4 = string.find(rest3, ":")
  if not colonPos4 then return end
  
  local G = tonumber(string.sub(rest3, 1, colonPos4 - 1)) or 0
  local S = tonumber(string.sub(rest3, colonPos4 + 1)) or 0
  
  -- Store into dedicated lboard tables (never overwrite local accounting)
  local now = Now()
  if dataType == "L" then
    -- Higher-total-wins guard: only overwrite if the incoming data has a higher
    -- or equal total than what we already have.  A timestamp comparison is not
    -- reliable here because `now` (receive time) is always greater than a
    -- previously stored receive timestamp, which caused zero-broadcasts from
    -- peers who lack a player's data to silently wipe correct synced values.
    local newTotal = L + G + S
    local existingEntry = LeafVE_DB.lboard.alltime[playerName]
    local existingTotal = existingEntry and ((existingEntry.L or 0) + (existingEntry.G or 0) + (existingEntry.S or 0)) or 0
    if newTotal > 0 and newTotal >= existingTotal then
      LeafVE_DB.lboard.alltime[playerName] = {L = L, G = G, S = S}
    end

  elseif string.sub(dataType, 1, 1) == "W" then
    -- Weekly synced data; extract week key (new format "W20260217", old format "W" → current week)
    local wk = string.sub(dataType, 2)
    if wk == "" then wk = WeekKey() end  -- backward compatibility: old "W:Name:L:G:S"
    -- Only store if this is the current week; discard stale week data
    local currentWk = WeekKey()
    if wk ~= currentWk then return end
    -- Higher-total-wins guard: only overwrite if the incoming data has a higher
    -- or equal total than what we already have.  A timestamp comparison is not
    -- reliable here because `now` (receive time) is always greater than a
    -- previously stored receive timestamp, which caused zero-broadcasts from
    -- peers who lack a player's data to silently wipe correct synced values.
    local newTotal = L + G + S
    local existingEntry = type(LeafVE_DB.lboard.weekly[wk]) == "table" and LeafVE_DB.lboard.weekly[wk][playerName]
    local existingTotal = existingEntry and ((existingEntry.L or 0) + (existingEntry.G or 0) + (existingEntry.S or 0)) or 0
    if newTotal > 0 and newTotal >= existingTotal then
      if type(LeafVE_DB.lboard.weekly[wk]) ~= "table" then LeafVE_DB.lboard.weekly[wk] = {} end
      LeafVE_DB.lboard.weekly[wk][playerName] = {L = L, G = G, S = S}
    end
  end
end

function FindUnitToken(playerName)
  if UnitName("player") == playerName then return "player" end
  if UnitExists("target") and UnitName("target") == playerName then return "target" end
  for i = 1, 4 do local unit = "party"..i if UnitExists(unit) and UnitName(unit) == playerName then return unit end end
  for i = 1, 40 do local unit = "raid"..i if UnitExists(unit) and UnitName(unit) == playerName then return unit end end
  return nil
end

function LeafVE:PurgeStaleWeeklyData()
  EnsureDB()
  local currentWk = WeekKey()
  for wk in pairs(LeafVE_DB.lboard.weekly) do
    if wk ~= currentWk then
      LeafVE_DB.lboard.weekly[wk] = nil
    end
  end
end

function AggForThisWeek()
  EnsureDB() local startTS = WeekStartTS(Now()) local agg = {}
  for d = 0, 6 do
    local dk = DayKeyFromTS(startTS + d * SECONDS_PER_DAY)
    if LeafVE_DB.global[dk] then
      for name, t in pairs(LeafVE_DB.global[dk]) do
        if not agg[name] then agg[name] = {L = 0, G = 0, S = 0} end
        agg[name].L = agg[name].L + (t.L or 0)
        agg[name].G = agg[name].G + (t.G or 0)
        agg[name].S = agg[name].S + (t.S or 0)
      end
    end
  end
  return agg, startTS
end

function LeafVE:ToggleUI()
  EnsureDB()
  
  if not LeafVE.UI or not LeafVE.UI.Build then 
    Print("ERROR: UI not loaded. Check addon file!") 
    return 
  end
  
  if not LeafVE.UI.frame then 
    LeafVE.UI:Build()
  end
  
  if not LeafVE.UI.frame then
    Print("ERROR: UI frame failed to build!")
    return
  end
  
  if LeafVE.UI.frame:IsVisible() then 
    LeafVE.UI.frame:Hide()
  else 
    LeafVE.UI.frame:Show()
    LeafVE.UI:Refresh()
  end
end

-------------------------------------------------
-- UI SYSTEM - ALL TABS
-------------------------------------------------
LeafVE.UI = LeafVE.UI or { activeTab = "me" }

-- C_Timer.After polyfill for WoW 1.12 (uses OnUpdate on a hidden frame)
if not C_Timer_After then
  C_Timer_After = function(delay, func)
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function()
      elapsed = elapsed + arg1
      if elapsed >= delay then
        ticker:SetScript("OnUpdate", nil)
        ticker:Hide()
        func()
      end
    end)
    ticker:Show()
  end
end

function LeafVE:ShowVersionResults()
  local myVer = LeafVE.version
  -- Build a sorted list of all known guild members
  local results = {}
  -- Add self
  local me = ShortName(UnitName("player"))
  if me then
    table.insert(results, {name = me, ver = myVer, status = "self"})
  end
  -- Add responses received
  if LeafVE.versionResponses then
    for name, ver in pairs(LeafVE.versionResponses) do
      if name ~= me then
        local status
        if ver == myVer then
          status = "ok"
        elseif VersionLessThan(ver, myVer) then
          status = "old"
        else
          status = "newer"
        end
        table.insert(results, {name = name, ver = ver, status = status})
      end
    end
  end
  table.sort(results, function(a, b) return a.name < b.name end)

  -- Create popup frame if needed
  if not LeafVE.versionFrame then
    local f = CreateFrame("Frame", "LeafVE_VersionFrame", UIParent)
    f:SetWidth(300)
    f:SetHeight(400)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    f:SetBackdropBorderColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.8)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("|cFFFFD700Addon Version Check|r")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local scrollFrame = CreateFrame("ScrollFrame", nil, f)
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function()
      local cur = scrollFrame:GetVerticalScroll()
      local mx = scrollFrame:GetVerticalScrollRange()
      local ns = cur - (arg1 * 20)
      if ns < 0 then ns = 0 end
      if ns > mx then ns = mx end
      scrollFrame:SetVerticalScroll(ns)
    end)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(270)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    f.scrollChild = scrollChild
    f.resultRows = {}
    LeafVE.versionFrame = f
  end

  local f = LeafVE.versionFrame
  local sc = f.scrollChild

  -- Clear old rows
  for _, row in ipairs(f.resultRows) do row:Hide() end
  f.resultRows = {}

  local yOff = -4
  for i, entry in ipairs(results) do
    local row = CreateFrame("Frame", nil, sc)
    row:SetWidth(270)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, yOff)

    local icon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    icon:SetWidth(20)
    if entry.status == "ok" or entry.status == "self" then
      icon:SetText("|cFF00FF00✔|r")
    elseif entry.status == "old" then
      icon:SetText("|cFFFF4444✘|r")
    else
      icon:SetText("|cFFAAAAAA⚠|r")
    end

    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("LEFT", row, "LEFT", 28, 0)
    nameFS:SetWidth(140)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetText(entry.name or "")

    local verFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verFS:SetPoint("LEFT", row, "LEFT", 172, 0)
    verFS:SetWidth(90)
    verFS:SetJustifyH("LEFT")
    if entry.status == "old" then
      verFS:SetText("|cFFFF4444v"..(entry.ver or "?").."  (outdated)|r")
    elseif entry.status == "self" then
      verFS:SetText("|cFFFFD700v"..(entry.ver or "?").."  (you)|r")
    else
      verFS:SetText("|cFF00FF00v"..(entry.ver or "?").."|r")
    end

    table.insert(f.resultRows, row)
    yOff = yOff - 20
  end
  sc:SetHeight(math.max(math.abs(yOff) + 8, 1))
  f:Show()
end


-- Achievement icon mapping
local ACHIEVEMENT_ICONS = {
  -- Professions
  ["prof_skinning_300"] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
  ["prof_herbalism_300"] = "Interface\\Icons\\INV_Misc_Herb_07",
  ["prof_mining_300"] = "Interface\\Icons\\INV_Pick_02",
  ["prof_alchemy_300"] = "Interface\\Icons\\Trade_Alchemy",
  ["prof_blacksmithing_300"] = "Interface\\Icons\\Trade_BlackSmithing",
  ["prof_engineering_300"] = "Interface\\Icons\\Trade_Engineering",
  ["prof_enchanting_300"] = "Interface\\Icons\\Trade_Engraving",
  ["prof_tailoring_300"] = "Interface\\Icons\\Trade_Tailoring",
  ["prof_leatherworking_300"] = "Interface\\Icons\\Trade_LeatherWorking",
  
  -- PvP
  ["pvp_duel_100"] = "Interface\\Icons\\Ability_Duel",
  ["pvp_honorable_kills_1000"] = "Interface\\Icons\\Ability_Warrior_Challange",
  ["pvp_warsong_victories_100"] = "Interface\\Icons\\INV_BannerPVP_01",
  ["pvp_arathi_victories_100"] = "Interface\\Icons\\INV_BannerPVP_02",
  
  -- Dungeons
  ["dung_sm_armory"] = "Interface\\Icons\\INV_Misc_Key_03",
  ["dung_gnomer"] = "Interface\\Icons\\INV_Gizmo_02",
  ["dung_deadmines"] = "Interface\\Icons\\INV_Ingot_03",
  ["dung_wailing_caverns"] = "Interface\\Icons\\Spell_Nature_NullifyDisease",
  ["dung_shadowfang_keep"] = "Interface\\Icons\\Spell_Shadow_Curse",
  ["dung_blackfathom_deeps"] = "Interface\\Icons\\Spell_Shadow_SacrificialShield",
  ["dung_razorfen_kraul"] = "Interface\\Icons\\Spell_Shadow_ShadeTrueSight",
  ["dung_uldaman"] = "Interface\\Icons\\INV_Misc_Rune_01",
  ["dung_zul_farrak"] = "Interface\\Icons\\Ability_Hunter_Pet_Vulture",
  ["dung_maraudon"] = "Interface\\Icons\\Spell_Nature_ResistNature",
  ["dung_sunken_temple"] = "Interface\\Icons\\INV_Misc_Head_Dragon_Green",
  ["dung_blackrock_depths"] = "Interface\\Icons\\Spell_Fire_LavaSpawn",
  ["dung_dire_maul"] = "Interface\\Icons\\INV_Misc_Book_11",
  ["dung_stratholme"] = "Interface\\Icons\\INV_Misc_Key_14",
  ["dung_scholomance"] = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  
  -- Raids
  ["elite_no_wipe_bwl"] = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
  ["elite_flawless_nef"] = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
  ["elite_all_raids_one_week"] = "Interface\\Icons\\INV_Misc_Bone_ElfSkull_01",
  ["elite_molten_core_clear"] = "Interface\\Icons\\Spell_Fire_Incinerate",
  ["elite_onyxia_kill"] = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
  ["elite_zul_gurub_clear"] = "Interface\\Icons\\Ability_Mount_JungleTiger",
  ["elite_ahn_qiraj_20_clear"] = "Interface\\Icons\\INV_Misc_AhnQirajTrinket_04",
  ["elite_ahn_qiraj_40_clear"] = "Interface\\Icons\\INV_Misc_AhnQirajTrinket_05",
  ["elite_naxxramas_clear"] = "Interface\\Icons\\INV_Misc_Key_15",
  
  -- Exploration
  ["explore_eastern_kingdoms"] = "Interface\\Icons\\INV_Misc_Map_01",
  ["explore_kalimdor"] = "Interface\\Icons\\INV_Misc_Map02",
  
  -- Gold
  ["gold_1000"] = "Interface\\Icons\\INV_Misc_Coin_01",
  ["gold_5000"] = "Interface\\Icons\\INV_Misc_Coin_05",
  ["gold_10000"] = "Interface\\Icons\\INV_Misc_Coin_16",
  
  -- Casual/Fun
  ["casual_fall_death"] = "Interface\\Icons\\Ability_Rogue_FeignDeath",
  ["casual_drunk"] = "Interface\\Icons\\INV_Drink_05",
  ["casual_fish_100"] = "Interface\\Icons\\INV_Misc_Fish_02",
  ["casual_first_aid_300"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
  ["casual_cooking_300"] = "Interface\\Icons\\INV_Misc_Food_15",
  
  -- Level achievements
  ["level_60"] = "Interface\\Icons\\INV_Misc_LevelGain",
  ["level_40_mount"] = "Interface\\Icons\\Ability_Mount_RidingHorse",
  ["level_60_epic_mount"] = "Interface\\Icons\\Ability_Mount_NightmareHorse",
}

local function GetAchievementIcon(achId)
  if not achId then return LEAF_FALLBACK end
  
  -- Check achievement addon metadata first
  if LeafVE_AchTest and LeafVE_AchTest.GetAchievementMeta then
    local meta = LeafVE_AchTest.GetAchievementMeta(achId)
    if meta and meta.icon then
      return meta.icon
    end
  end
  
  local lowerAchId = string.lower(achId)
  
  -- Check the full ACHIEVEMENT_ICONS table
  if ACHIEVEMENT_ICONS[lowerAchId] then
    return ACHIEVEMENT_ICONS[lowerAchId]
  end
  
  local iconMap = {
    lvl_10 = "Interface\\Icons\\INV_Sword_04",
    lvl_20 = "Interface\\Icons\\INV_Sword_27",
    lvl_30 = "Interface\\Icons\\INV_Sword_39",
    lvl_40 = "Interface\\Icons\\INV_Sword_43",
    lvl_50 = "Interface\\Icons\\INV_Sword_62",
    lvl_60 = "Interface\\Icons\\INV_Sword_65",
    gold_10 = "Interface\\Icons\\INV_Misc_Coin_01",
    gold_100 = "Interface\\Icons\\INV_Misc_Coin_05",
    gold_1000 = "Interface\\Icons\\INV_Misc_Gem_Pearl_05",
  }
  
  if iconMap[lowerAchId] then
    return iconMap[lowerAchId]
  end
  
  if string.find(lowerAchId, "lvl") or string.find(lowerAchId, "level") then
    return "Interface\\Icons\\INV_Sword_04"
  elseif string.find(lowerAchId, "gold") then
    return "Interface\\Icons\\INV_Misc_Coin_01"
  end
  
  return LEAF_FALLBACK
end

local function TabButton(parent, text, name)
  local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  b:SetHeight(20)
  b:SetText(text)
  SkinButtonAccent(b)
  return b
end

function LeafVE.UI:BuildPlayerCard(parent)
  if self.card then return end
  
  local c = CreateGradientInset(parent)
  self.card = c
  c:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -10)
  c:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 10)
  c:SetWidth(480)

  local title = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -10)
  title:SetText("Player Card")
  title:SetTextColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3])

  local portraitContainer = CreateFrame("Frame", nil, c)
  portraitContainer:SetPoint("TOP", c, "TOP", 0, -40)
  portraitContainer:SetWidth(180)
  portraitContainer:SetHeight(180)
  portraitContainer:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  portraitContainer:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
  portraitContainer:SetBackdropBorderColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3], 0.8)
  self.cardPortraitContainer = portraitContainer

  -- Faction-coloured gradient background: single full-area texture (red=Horde, blue=Alliance)
  local modelBG = portraitContainer:CreateTexture(nil, "BACKGROUND")
  modelBG:SetAllPoints(portraitContainer)
  modelBG:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
  modelBG:SetVertexColor(0.1, 0.1, 0.15, 0.9)
  modelBG:Hide()
  self.cardModelBG = modelBG

  local model = CreateFrame("PlayerModel", nil, portraitContainer)
  model:SetAllPoints(portraitContainer)
  model:Hide()
  self.cardModel = model

  local classIconFrame = CreateFrame("Frame", nil, portraitContainer)
  classIconFrame:SetAllPoints(portraitContainer)
  classIconFrame:Hide()
  self.cardClassIconFrame = classIconFrame

  local classIcon = classIconFrame:CreateTexture(nil, "ARTWORK")
  classIcon:SetPoint("CENTER", classIconFrame, "CENTER", 0, 0)
  classIcon:SetWidth(130)
  classIcon:SetHeight(130)
  classIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  self.cardClassIcon = classIcon

  local portraitTypeText = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  portraitTypeText:SetPoint("TOP", portraitContainer, "BOTTOM", 0, 2)
  portraitTypeText:SetText("")
  portraitTypeText:SetTextColor(0.7, 0.7, 0.7)
  self.cardPortraitTypeText = portraitTypeText

  local nameFS = c:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  nameFS:SetPoint("TOP", portraitContainer, "BOTTOM", 0, -10)
  nameFS:SetWidth(430)
  nameFS:SetJustifyH("CENTER")
  nameFS:SetText("-")
  self.cardName = nameFS

  local infoFS = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  infoFS:SetPoint("TOP", nameFS, "BOTTOM", 0, -5)
  infoFS:SetWidth(430)
  infoFS:SetJustifyH("CENTER")
  infoFS:SetText("")
  self.cardClassLevelRank = infoFS

-- Recent Badges Section (LEFT SIDE)
local recentBadgesLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
recentBadgesLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -300)
recentBadgesLabel:SetText("|cFFFFD700Recent Badges|r")

local recentBadgesFrame = CreateFrame("Frame", nil, c)
recentBadgesFrame:SetPoint("TOPLEFT", recentBadgesLabel, "BOTTOMLEFT", 0, -10)
recentBadgesFrame:SetWidth(210)
recentBadgesFrame:SetHeight(160)
self.cardRecentBadgesFrame = recentBadgesFrame

self.cardRecentBadgeFrames = {}

-- View All Badges Button
local viewAllBadgesBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
viewAllBadgesBtn:SetWidth(140)
viewAllBadgesBtn:SetHeight(22)
viewAllBadgesBtn:SetPoint("TOPLEFT", recentBadgesFrame, "BOTTOMLEFT", 0, 10)
viewAllBadgesBtn:SetText("View All Badges")
SkinButtonAccent(viewAllBadgesBtn)
viewAllBadgesBtn:SetScript("OnClick", function()
  if LeafVE.UI.allBadgesFrame and LeafVE.UI.allBadgesFrame:IsVisible() then
    LeafVE.UI.allBadgesFrame:Hide()
  else
    LeafVE.UI:ShowAllBadgesPanel(LeafVE.UI.inspectedPlayer or UnitName("player"))
    if LeafVE.UI.allBadgesFrame then
      LeafVE.UI.allBadgesFrame:Show()
    end
  end
end)
self.viewAllBadgesBtn = viewAllBadgesBtn

-- Gear Button (between View All Badges and View All Achievements)
local gearBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
gearBtn:SetWidth(140)
gearBtn:SetHeight(22)
gearBtn:SetPoint("TOPLEFT", viewAllBadgesBtn, "BOTTOMLEFT", 0, -5)
gearBtn:SetText("Gear")
SkinButtonAccent(gearBtn)
gearBtn:SetScript("OnClick", function()
  if not LeafVE.UI.cardCurrentPlayer then return end
  if not LeafVE.UI.gearPopup then
    LeafVE.UI:CreateGearPopup()
  end
  if LeafVE.UI.gearPopup:IsVisible() then
    LeafVE.UI.gearPopup:Hide()
  else
    LeafVE.UI:RefreshGearPopup(LeafVE.UI.cardCurrentPlayer)
    LeafVE.UI.gearPopup:Show()
  end
end)
self.cardGearBtn = gearBtn

-- Achievements Section
  local achLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  achLabel:SetPoint("TOPRIGHT", c, "TOPRIGHT", -40, -300)
  achLabel:SetText("|cFFFFD700Achievements|r")
  
  local achPointsText = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  achPointsText:SetPoint("TOP", achLabel, "BOTTOM", 0, -5)  -- stays relative to achLabel
  achPointsText:SetWidth(210)
  achPointsText:SetJustifyH("CENTER")
  achPointsText:SetText("0 Points")
  self.cardAchPoints = achPointsText
  
  local recentLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  recentLabel:SetPoint("TOP", achPointsText, "BOTTOM", -0, -8)
  recentLabel:SetText("|cFFAAAAFFRecent Achievements|r")
  
  -- Recent achievements frame
  local recentFrame = CreateFrame("Frame", nil, c)
  recentFrame:SetPoint("TOP", recentLabel, "BOTTOM", 27, -7)
  recentFrame:SetWidth(230)
  recentFrame:SetHeight(110)
  self.cardRecentAchFrame = recentFrame
  
  self.cardRecentAchEntries = {}
  
  -- View All button
  local viewAllBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
  viewAllBtn:SetPoint("TOP", recentFrame, "BOTTOM", -33, -10)
  viewAllBtn:SetWidth(180)
  viewAllBtn:SetHeight(22)
  viewAllBtn:SetText("View All Achievements")
  SkinButtonAccent(viewAllBtn)
viewAllBtn:SetScript("OnClick", function()
  if not LeafVE.UI.cardCurrentPlayer then return end
  
  -- Create popup if it doesn't exist
  if not LeafVE.UI.achPopup then
    LeafVE.UI:CreateAchievementListPopup()
  end
  
  -- Toggle open/closed
  if LeafVE.UI.achPopup:IsVisible() then
    LeafVE.UI.achPopup:Hide()
  else
    LeafVE.UI:RefreshAchievementPopup(LeafVE.UI.cardCurrentPlayer)
    LeafVE.UI.achPopup:Show()
  end
end)
  self.cardViewAllBtn = viewAllBtn

   -- Player Note (matching Wisdom of the Leaf style)
  local notesLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  notesLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -70)  -- ← MOVED UP (was -100)
  notesLabel:SetText("|cFFFFD700Player Note|r")

  local notesBox = CreateFrame("Frame", nil, c)
  notesBox:SetPoint("TOPLEFT", notesLabel, "BOTTOMLEFT", 0, -5)
  notesBox:SetWidth(125)  -- ← NARROWER (was 210)
  notesBox:SetHeight(105)  -- ← MATCHES quote height
  notesBox:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  notesBox:SetBackdropColor(0.05, 0.05, 0.08, 0.8)
  notesBox:SetBackdropBorderColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.6)

  local notesEditBox = CreateFrame("EditBox", nil, notesBox)
  notesEditBox:SetPoint("TOPLEFT", notesBox, "TOPLEFT", 8, -8)
  notesEditBox:SetWidth(110)  -- ← NARROWER (was 210)
  notesEditBox:SetHeight(65)  -- ← ADJUSTED for space
  notesEditBox:SetMultiLine(true)
  notesEditBox:SetAutoFocus(false)
  notesEditBox:SetFontObject(GameFontHighlightSmall)
  notesEditBox:SetMaxLetters(500)
  notesEditBox:SetTextColor(0.667, 0.667, 1.0)
  
  notesEditBox:SetScript("OnEscapePressed", function() 
    this:ClearFocus() 
  end)
  
  self.cardNotesEdit = notesEditBox
  
  -- Save button (positioned at bottom like Kakashi attribution)
  local saveNoteBtn = CreateFrame("Button", nil, notesBox, "UIPanelButtonTemplate")
  saveNoteBtn:SetPoint("BOTTOM", notesBox, "BOTTOM", 0, 8)  -- ← BOTTOM ALIGNED
  saveNoteBtn:SetWidth(100)
  saveNoteBtn:SetHeight(20)
  saveNoteBtn:SetText("Save Note")
  SkinButtonAccent(saveNoteBtn)
  
  saveNoteBtn:SetScript("OnClick", function()
    local cardPlayer = LeafVE.UI.cardCurrentPlayer
    if not cardPlayer then 
      Print("No player selected!")
      return 
    end
    
    EnsureDB()
    local me = ShortName(UnitName("player"))
    
    -- Only save if editing your own note
    if me and cardPlayer == me then
      local text = LeafVE.UI.cardNotesEdit:GetText()
      if not LeafVE_GlobalDB.playerNotes then
        LeafVE_GlobalDB.playerNotes = {}
      end
      LeafVE_GlobalDB.playerNotes[me] = text
      
      -- Clear focus
      LeafVE.UI.cardNotesEdit:ClearFocus()
      
      -- Broadcast the note change
      LeafVE:BroadcastPlayerNote(text)
      Print("Player note saved and broadcast!")
    else
      Print("You can only edit your own note!")
    end
  end)
  
  self.cardSaveNoteBtn = saveNoteBtn

  -- Kakashi Quote (parallel to Player Note, right side - COMPACT)
  local quoteLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  quoteLabel:SetPoint("TOPRIGHT", c, "TOPRIGHT", -15, -70)  -- ← MOVED UP (was -100)
  quoteLabel:SetText("|cFF2DD35CWisdom of the Leaf|r")
  
  local quoteBox = CreateFrame("Frame", nil, c)
  quoteBox:SetPoint("TOPRIGHT", quoteLabel, "BOTTOMRIGHT", 0, -5)
  quoteBox:SetWidth(125)
  quoteBox:SetHeight(105)
  quoteBox:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  quoteBox:SetBackdropColor(0.05, 0.05, 0.08, 0.8)
  quoteBox:SetBackdropBorderColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3], 0.6)
  
  local quoteText = quoteBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  quoteText:SetPoint("TOP", quoteBox, "TOP", 0, -8)
  quoteText:SetWidth(110)
  quoteText:SetJustifyH("CENTER")
  quoteText:SetText("|cFFAAAAFF\"In the ninja world, those who break the rules are scum, that's true. But those who abandon their friends are worse than scum.\"|r")
  
  local attribution = quoteBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  attribution:SetPoint("BOTTOM", quoteBox, "BOTTOM", 0, 15)
  attribution:SetText("|cFF2DD35C- Kakashi Hatake|r")

  -- Leaf Village Emblem with BIG BRIGHT GLOW
local leafGlow = c:CreateTexture(nil, "BACKGROUND")
leafGlow:SetWidth(128)
leafGlow:SetHeight(128)
leafGlow:SetPoint("CENTER", c, "CENTER", 0, -380)  -- Centered between left and right sections
  leafGlow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
  leafGlow:SetVertexColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3], 1.0)  -- ← FULL BRIGHTNESS (was 0.6)
  leafGlow:SetBlendMode("ADD")
  
local leafEmblem = c:CreateTexture(nil, "ARTWORK")
leafEmblem:SetWidth(48)
leafEmblem:SetHeight(48)
leafEmblem:SetPoint("CENTER", c, "CENTER", 0, -125)  -- Same position
leafEmblem:SetTexture(LEAF_EMBLEM)
leafEmblem:SetVertexColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3], 1.0)

  local leafLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  leafLabel:SetPoint("TOP", leafEmblem, "BOTTOM", 0, -2)
  leafLabel:SetText("Leaf Village")
  leafLabel:SetTextColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3])
  
  leafEmblem:SetVertexColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3], 0.8)

  local leafLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  leafLabel:SetPoint("TOP", leafEmblem, "BOTTOM", 0, -2)
  leafLabel:SetText("Leaf Village")
  leafLabel:SetTextColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3])
 end

function LeafVE.UI:ShowAllBadgesPanel(playerName)
  if not playerName then
    playerName = UnitName("player")
  end

  -- Create main frame (only once)
  if not self.allBadgesFrame then
    local f = CreateFrame("Frame", "LeafVEAllBadgesFrame", UIParent)
    f:SetWidth(450)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    
    -- Anchor to right side of main UI panel
    if LeafVE.UI.frame then
      f:SetPoint("TOPLEFT", LeafVE.UI.frame, "TOPRIGHT", 5, 0)
      f:SetHeight(LeafVE.UI.frame:GetHeight())
    else
      f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      f:SetHeight(550)
    end
    
    -- Backdrop
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true,
      tileSize = 32,
      edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetBackdropColor(0, 0, 0, 1)
    
    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -15)
    f.title:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() this:GetParent():Hide() end)
    
    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", "LeafVEAllBadgesScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 20)
    
    -- Content Frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(400)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    
    f.scrollFrame = scrollFrame
    f.content = content
    
    self.allBadgesFrame = f
  end
local f = self.allBadgesFrame
f.title:SetText(playerName .. "'s Badge Collection")

-- Destroy and recreate content frame to force refresh
if f.content then
  f.content:Hide()
  f.content:SetParent(nil)
  f.content = nil
end

-- Create fresh content frame
local content = CreateFrame("Frame", nil, f.scrollFrame)
content:SetWidth(400)
content:SetHeight(1)
f.scrollFrame:SetScrollChild(content)
f.content = content

f.badgeIcons = {}
  
-- Get player's badges
EnsureDB()
local shortName = ShortName(playerName)
local playerBadges = {}
if shortName and LeafVE_DB.badges[shortName] then
  for badgeId, timestamp in pairs(LeafVE_DB.badges[shortName]) do
    playerBadges[badgeId] = {
      id = badgeId,
      earned = timestamp
    }
  end
end

-- Organize badges by category
local categories = {}
for i = 1, table.getn(BADGES) do
  local badge = BADGES[i]
  local category = badge.category or "Other"
  
  if not categories[category] then
    categories[category] = {}
  end
  
  table.insert(categories[category], {
    id = badge.id,
    name = badge.name,
    description = badge.desc,
    icon = badge.icon,
    quality = badge.quality or BADGE_QUALITY.COMMON,
    order = i,  -- BADGES array index preserves progression order
    earned = playerBadges[badge.id] ~= nil,
    earnedDate = playerBadges[badge.id] and playerBadges[badge.id].earned or nil
  })
end
  
  -- Sort categories
  local sortedCategories = {}
  for category, _ in pairs(categories) do
    table.insert(sortedCategories, category)
  end
  table.sort(sortedCategories)
  
  -- Build UI
  local yOffset = -10
  local content = f.content
  
  for _, category in ipairs(sortedCategories) do
    -- Category Header
    local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    header:SetText("|cFFFFD700" .. category .. "|r")
    table.insert(f.badgeIcons, header)
    yOffset = yOffset - 30
    
    -- Sort badges in category by progression order (BADGES array index)
    table.sort(categories[category], function(a, b)
      return a.order < b.order
    end)
    
    -- Display badges in grid
    local xOffset = 10
    local col = 0
    local maxCols = 4
    local iconSize = 50
    local spacing = 10
    
for _, badgeData in ipairs(categories[category]) do
  local icon = CreateFrame("Frame", nil, content)
  icon:SetWidth(iconSize)
  icon:SetHeight(iconSize)
  icon:SetPoint("TOPLEFT", content, "TOPLEFT", xOffset, yOffset)
  
  icon:EnableMouse(true)
      
      -- Quality background glow (behind texture, only when earned)
      local qualityBG = icon:CreateTexture(nil, "BACKGROUND")
      qualityBG:SetAllPoints()
      qualityBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
      if badgeData.earned then
        local qr, qg, qb = GetBadgeQualityColor(badgeData.quality)
        qualityBG:SetVertexColor(qr, qg, qb, 0.40)
      else
        qualityBG:SetVertexColor(0, 0, 0, 0.5)
      end

      -- Badge texture
      local tex = icon:CreateTexture(nil, "ARTWORK")
      tex:SetAllPoints()
      tex:SetTexture(badgeData.icon)
      
      if not badgeData.earned then
        tex:SetDesaturated(true)
        tex:SetAlpha(0.3)
      end
      
      -- Border
      local border = icon:CreateTexture(nil, "OVERLAY")
      border:SetAllPoints()
      border:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
      border:SetTexCoord(0, 0.5625, 0, 0.5625)
      
-- Store badge data on icon for tooltip
icon.badgeName = badgeData.name
icon.badgeDesc = badgeData.description
icon.badgeQuality = badgeData.quality
icon.badgeEarned = badgeData.earned
icon.badgeEarnedDate = badgeData.earnedDate
icon.badgeId = badgeData.id
icon.badgePlayerName = shortName

-- Tooltip
icon:SetScript("OnEnter", function()
  GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  local qr2, qg2, qb2 = GetBadgeQualityColor(this.badgeQuality)
  if this.badgeEarned then
    GameTooltip:SetText(this.badgeName, qr2, qg2, qb2, 1, true)
    GameTooltip:AddLine("|cFF888888"..GetBadgeQualityLabel(this.badgeQuality).."|r", 1, 1, 1)
    GameTooltip:AddLine(this.badgeDesc, 1, 1, 1, true)
    if this.badgeEarnedDate then
      GameTooltip:AddLine(" ", 1, 1, 1)
      GameTooltip:AddLine("Earned: " .. date("%m/%d/%Y", this.badgeEarnedDate), 0.5, 0.8, 0.5)
    end
  else
    GameTooltip:SetText(this.badgeName, 0.6, 0.6, 0.6, 1, true)
    GameTooltip:AddLine("|cFF888888"..GetBadgeQualityLabel(this.badgeQuality).."|r", 1, 1, 1)
    GameTooltip:AddLine(this.badgeDesc, 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine(" ", 1, 1, 1)
    local cur, tgt = LeafVE:GetBadgeProgress(this.badgePlayerName, this.badgeId)
    if cur and tgt then
      GameTooltip:AddLine("Progress: "..cur.." / "..tgt, 1, 0.82, 0)
    end
    GameTooltip:AddLine("Not yet earned", 0.8, 0.4, 0.4)
  end
  GameTooltip:Show()
end)

icon:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)  
      table.insert(f.badgeIcons, icon)
      
      col = col + 1
      if col >= maxCols then
        col = 0
        xOffset = 10
        yOffset = yOffset - (iconSize + spacing)
      else
        xOffset = xOffset + iconSize + spacing
      end
    end
    
    -- Move to next row if we didn't finish a full row
    if col > 0 then
      yOffset = yOffset - (iconSize + spacing)
    end
    
    yOffset = yOffset - 20 -- Extra space between categories
  end
  
  -- Update content height
  content:SetHeight(math.abs(yOffset) + 50)
  
  -- Show frame
  f:Show()
end

function LeafVE.UI:UpdateCardRecentBadges(playerName)
  if not self.cardRecentBadgesFrame then
    return
  end
  
  if not self.cardRecentBadgeFrames then
    return
  end
  
  -- Hide all existing badge frames
  for i = 1, table.getn(self.cardRecentBadgeFrames) do
    self.cardRecentBadgeFrames[i]:Hide()
  end
  
  local shortName = ShortName(playerName)
  
  EnsureDB()
  
  local myBadges = LeafVE_DB.badges[shortName] or {}
  
  -- Build list of earned badges with timestamps
  local earnedBadges = {}
  for i = 1, table.getn(BADGES) do
    local badge = BADGES[i]
    if myBadges[badge.id] then
      table.insert(earnedBadges, {
        id = badge.id,
        name = badge.name,
        desc = badge.desc,
        icon = badge.icon,
        quality = badge.quality or BADGE_QUALITY.COMMON,
        earnedAt = myBadges[badge.id],
        earned = true
      })
    end
  end
  
  -- Sort by most recent first
  table.sort(earnedBadges, function(a, b)
    return a.earnedAt > b.earnedAt
  end)
  
  -- Take top 9 earned badges
  local topEarned = {}
  for i = 1, math.min(9, table.getn(earnedBadges)) do
    table.insert(topEarned, earnedBadges[i])
  end
  
  -- Fill remaining slots with locked badges (not yet earned)
  if table.getn(topEarned) < 9 then
    for i = 1, table.getn(BADGES) do
      if table.getn(topEarned) >= 9 then break end
      
      local badge = BADGES[i]
      local alreadyShown = false
      
      for j = 1, table.getn(topEarned) do
        if topEarned[j].id == badge.id then
          alreadyShown = true
          break
        end
      end
      
      if not alreadyShown then
        table.insert(topEarned, {
          id = badge.id,
          name = badge.name,
          desc = badge.desc,
          icon = badge.icon,
          quality = badge.quality or BADGE_QUALITY.COMMON,
          earnedAt = nil,
          earned = false
        })
      end
    end
  end
  
  -- Display all 9 badges (earned + locked)
  local badgeSize = 45
  local xSpacing = 50
  local ySpacing = 50
  local perRow = 3
  
  for i = 1, 9 do  -- ← CHANGE FROM 6 TO 9
    local badge = topEarned[i]
    local frame = self.cardRecentBadgeFrames[i]
    
    if not frame then
      frame = CreateFrame("Frame", nil, self.cardRecentBadgesFrame)
      frame:SetWidth(badgeSize)
      frame:SetHeight(badgeSize)
      frame:EnableMouse(true)
      
      local icon = frame:CreateTexture(nil, "ARTWORK")
      icon:SetAllPoints(frame)
      frame.icon = icon
      
      table.insert(self.cardRecentBadgeFrames, frame)
    end
    
    -- Position: grid layout (3 per row)
    local row = math.floor((i - 1) / perRow)
    local col = math.mod(i - 1, perRow)
    
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", self.cardRecentBadgesFrame, "TOPLEFT", col * xSpacing, -row * ySpacing)
    
    if badge then
      -- Set icon
      frame.icon:SetTexture(badge.icon)
      if not frame.icon:GetTexture() then
        frame.icon:SetTexture(LEAF_FALLBACK)
      end
      
      -- Style: earned = full color, locked = greyed out
      if badge.earned then
        frame.icon:SetVertexColor(1, 1, 1, 1)
        frame.icon:SetDesaturated(nil)
      else
        frame.icon:SetVertexColor(0.4, 0.4, 0.4, 0.7)
        if frame.icon.SetDesaturated then
          frame.icon:SetDesaturated(true)
        end
      end
      
      -- Tooltip
      frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        local qr2, qg2, qb2 = GetBadgeQualityColor(badge.quality or BADGE_QUALITY.COMMON)
        if badge.earned then
          GameTooltip:SetText(badge.name, qr2, qg2, qb2, 1, true)
          GameTooltip:AddLine("|cFF888888"..GetBadgeQualityLabel(badge.quality or BADGE_QUALITY.COMMON).."|r", 1, 1, 1)
          GameTooltip:AddLine(badge.desc, 1, 1, 1, true)
          GameTooltip:AddLine(" ", 1, 1, 1)
          GameTooltip:AddLine("Earned: "..date("%m/%d/%Y", badge.earnedAt), 0.5, 0.8, 0.5)
        else
          GameTooltip:SetText(badge.name, 0.6, 0.6, 0.6, 1, true)
          GameTooltip:AddLine("|cFF888888"..GetBadgeQualityLabel(badge.quality or BADGE_QUALITY.COMMON).."|r", 1, 1, 1)
          GameTooltip:AddLine(badge.desc, 0.7, 0.7, 0.7, true)
          GameTooltip:AddLine(" ", 1, 1, 1)
          local cur, tgt = LeafVE:GetBadgeProgress(shortName, badge.id)
          if cur and tgt then
            GameTooltip:AddLine("Progress: "..cur.." / "..tgt, 1, 0.82, 0)
          end
          GameTooltip:AddLine("Not yet earned", 0.8, 0.4, 0.4)
        end
        GameTooltip:Show()
      end)
      
      frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
    else
      -- Empty slot
      frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      frame.icon:SetVertexColor(0.3, 0.3, 0.3, 0.5)
      if frame.icon.SetDesaturated then
        frame.icon:SetDesaturated(true)
      end
      
      frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:SetText("Empty Badge Slot", 0.5, 0.5, 0.5, 1, true)
        GameTooltip:Show()
      end)
      
      frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
    end
    
    frame:Show()
  end
  
  -- Hide "No badges" text
  if self.cardNoBadgesText then
    self.cardNoBadgesText:Hide()
  end
end

function LeafVE.UI:ShowPlayerCard(playerName)
  EnsureDB()
  playerName = ShortName(playerName)
  if not playerName or not self.card then return end
  
  self.cardCurrentPlayer = playerName
  self.cardName:SetText(playerName)

  local guildInfo = LeafVE:GetGuildInfo(playerName)
  local class = guildInfo and guildInfo.class or "Unknown"
  local level = guildInfo and guildInfo.level or "??"
  local rank = guildInfo and guildInfo.rank or "Unknown"

  class = string.upper(Trim(class))

  local classColor = CLASS_COLORS[class] or {1, 1, 1}
  self.cardName:SetTextColor(classColor[1], classColor[2], classColor[3])
  self.cardClassLevelRank:SetText(string.format("Lvl %s %s\n%s", tostring(level), class, rank))

  local unitToken = FindUnitToken(playerName)
  local useModel = unitToken ~= nil
  
  if useModel then
    self.cardModel:Show()
    self.cardClassIconFrame:Hide()
    self.cardModel:ClearModel()
    self.cardModel:SetCamera(0)
    pcall(function()
      self.cardModel:SetUnit(unitToken)
      self.cardModel:SetPosition(0, 0, 0)
      self.cardModel:SetFacing(0.5)
    end)
    -- Fallback: if model didn't load, show class icon instead of empty model
    local modelPath = self.cardModel:GetModel()
    if not modelPath or modelPath == "" then
      self.cardModel:Hide()
      self.cardClassIconFrame:Show()
      local classIconPath = CLASS_ICONS[class] or LEAF_FALLBACK
      self.cardClassIcon:SetTexture(classIconPath)
      self.cardClassIcon:SetVertexColor(1, 1, 1, 1)
      if self.cardPortraitTypeText then
        self.cardPortraitTypeText:SetText("|cFFFFAA00"..class.."|r")
      end
      if self.cardModelBG then self.cardModelBG:Hide() end
    else
      if self.cardPortraitTypeText then
        self.cardPortraitTypeText:SetText("|cFF00FF00Live|r")
      end
      -- Apply faction gradient background (red=Horde, blue=Alliance) with gold border.
      if self.cardModelBG then
        local faction = UnitFactionGroup(unitToken)
        if faction == "Horde" then
          self.cardModelBG:SetGradientAlpha("VERTICAL", 0.30, 0.02, 0.02, 1, 0.70, 0.08, 0.08, 1)
        elseif faction == "Alliance" then
          self.cardModelBG:SetGradientAlpha("VERTICAL", 0.02, 0.12, 0.35, 1, 0.08, 0.30, 0.75, 1)
        else
          self.cardModelBG:SetGradientAlpha("VERTICAL", 0.06, 0.06, 0.08, 1, 0.12, 0.12, 0.16, 1)
        end
        self.cardModelBG:Show()
      end
      if self.cardPortraitContainer then
        self.cardPortraitContainer:SetBackdropBorderColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)
      end
    end
  else
    self.cardModel:Hide()
    self.cardClassIconFrame:Show()
    local classIconPath = CLASS_ICONS[class] or LEAF_FALLBACK
    self.cardClassIcon:SetTexture(classIconPath)
    self.cardClassIcon:SetVertexColor(1, 1, 1, 1)
    if self.cardPortraitTypeText then
      self.cardPortraitTypeText:SetText("|cFFFFAA00"..class.."|r")
    end
    if self.cardModelBG then self.cardModelBG:Hide() end
  end

  -- UPDATE RECENT BADGES (LEFT SIDE) - REPLACES Today/Week/Season stats
  if self.UpdateCardRecentBadges then
    self:UpdateCardRecentBadges(playerName)
  end
  
 if self.cardNotesEdit then
    EnsureDB()
    if not LeafVE_GlobalDB.playerNotes then
      LeafVE_GlobalDB.playerNotes = {}
    end
    
    local note = LeafVE_GlobalDB.playerNotes[playerName] or ""
    self.cardNotesEdit:SetText(note)
    
    local me = ShortName(UnitName("player"))
    
    if me and playerName == me then
      -- Enable editing
      self.cardNotesEdit:EnableMouse(true)
      self.cardNotesEdit:EnableKeyboard(true)
      self.cardNotesEdit:SetTextColor(0.667, 0.667, 1.0, 1)  -- Bright blue (RGBA)
      self.cardNotesEdit:SetAlpha(1)
      
      -- Show save button
      if self.cardSaveNoteBtn then
        self.cardSaveNoteBtn:Show()
        self.cardSaveNoteBtn:Enable()
      end
    else
      -- Disable editing (Vanilla compatible)
      self.cardNotesEdit:EnableMouse(false)
      self.cardNotesEdit:EnableKeyboard(false)
      self.cardNotesEdit:SetTextColor(0.667, 0.667, 1.0, 1)  -- Bright blue for other players
      self.cardNotesEdit:SetAlpha(0.7)
      
      -- Hide save button for other players
      if self.cardSaveNoteBtn then
        self.cardSaveNoteBtn:Hide()
      end
      
      -- Clear focus to prevent editing
      self.cardNotesEdit:ClearFocus()
    end
  end

    -- Update achievement points display using API
  
  local achPoints = 0
  if LeafVE_AchTest then
    if LeafVE_AchTest.API then
      if LeafVE_AchTest.API.GetPlayerPoints then
        -- FIX: Pass playerName instead of assuming it's the local player
        achPoints = LeafVE_AchTest.API.GetPlayerPoints(playerName)
      end
    end
  end
  
  if self.cardAchPoints then
    self.cardAchPoints:SetText(string.format("|cFFFFD700%d|r Points", achPoints))
  end
  
  -- Get recent achievements using API
  local recentAch = {}
  if LeafVE_AchTest and LeafVE_AchTest.API and LeafVE_AchTest.API.GetRecentAchievements then
    -- FIX: Pass playerName instead of assuming local player
    recentAch = LeafVE_AchTest.API.GetRecentAchievements(playerName, 5)
  end
  
  -- Clear previous recent achievements
  for i = 1, table.getn(self.cardRecentAchEntries) do
    self.cardRecentAchEntries[i]:Hide()
  end
  
  -- Display recent achievements (max 5)
  local maxRecent = math.min(5, table.getn(recentAch))
  local yOffset = 0
  
  for i = 1, maxRecent do
    local ach = recentAch[i]
    local meta = nil
    if LeafVE_AchTest and LeafVE_AchTest.GetAchievementMeta then
      meta = LeafVE_AchTest.GetAchievementMeta(ach.id)
    end
    local displayName = (meta and meta.name) or ach.name
    local displayIcon = (meta and meta.icon) or ach.icon
    local entry = self.cardRecentAchEntries[i]
    
    if not entry then
      entry = CreateFrame("Frame", nil, self.cardRecentAchFrame)
      entry:SetWidth(210)
      entry:SetHeight(20)
      
      local icon = entry:CreateTexture(nil, "ARTWORK")
      icon:SetWidth(16)
      icon:SetHeight(16)
      icon:SetPoint("LEFT", entry, "LEFT", 0, 0)
      entry.icon = icon
      
      local nameText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
      nameText:SetWidth(160)
      nameText:SetJustifyH("LEFT")
      entry.nameText = nameText
      
      local pointsText = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      pointsText:SetPoint("RIGHT", entry, "RIGHT", -50, 0)
      pointsText:SetWidth(60)
      pointsText:SetJustifyH("RIGHT")
      entry.pointsText = pointsText
      
      table.insert(self.cardRecentAchEntries, entry)
    end
    
    entry:SetPoint("TOPLEFT", self.cardRecentAchFrame, "TOPLEFT", 0, -yOffset)
    
    entry.icon:SetTexture(displayIcon)
    if not entry.icon:GetTexture() then
      entry.icon:SetTexture(LEAF_FALLBACK)
    end
    
    entry.nameText:SetText(displayName)
    
    entry.pointsText:SetText("|cFFFFD700"..ach.points.."|r")
    
    entry:Show()
    yOffset = yOffset + 22
  end
  
 end

function LeafVE.UI:ShowAchievementPopup(achId, achData)
  if not achId or not achData then return end
  
  -- Create popup frame if it doesn't exist
  if not self.achPopup then
    local popup = CreateFrame("Frame", "LeafVE_AchievementPopup", UIParent)
    popup:SetWidth(300)
    popup:SetHeight(80)
    popup:SetPoint("TOP", UIParent, "TOP", 0, -150)
    popup:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    popup:SetBackdropColor(0, 0, 0, 0.9)
    popup:Hide()
    
    -- Icon
    popup.icon = popup:CreateTexture(nil, "ARTWORK")
    popup.icon:SetWidth(36)
    popup.icon:SetHeight(36)
    popup.icon:SetPoint("LEFT", popup, "LEFT", 15, 0)
    
    -- Title text
    popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    popup.title:SetPoint("TOPLEFT", popup.icon, "TOPRIGHT", 10, -5)
    popup.title:SetText("|cFFFFD700Achievement Earned!|r")
    
    -- Achievement name
    popup.achName = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popup.achName:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -5)
    popup.achName:SetJustifyH("LEFT")
    popup.achName:SetWidth(220)
    
    -- Points
    popup.points = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    popup.points:SetPoint("BOTTOMLEFT", popup.icon, "BOTTOMRIGHT", 10, 5)
    
    self.achPopup = popup
  end
  
  -- Format achievement name
  local displayName = achId
  local meta = nil
  if LeafVE_AchTest and LeafVE_AchTest.GetAchievementMeta then
    meta = LeafVE_AchTest.GetAchievementMeta(achId)
  end
  if meta and meta.name then
    displayName = meta.name
  else
    displayName = string.gsub(displayName, "_", " ")
    displayName = string.gsub(displayName, "(%a)([%w_']*)", function(first, rest)
      return string.upper(first)..string.lower(rest)
    end)
  end
  
  -- Set popup content
  self.achPopup.icon:SetTexture(GetAchievementIcon(achId))
  self.achPopup.achName:SetText(displayName)
  self.achPopup.points:SetText(achData.points.." Points")
  
  -- Show and auto-hide
  self.achPopup:Show()
  self.achPopup:SetScript("OnUpdate", function()
    if not this.showTime then
      this.showTime = GetTime()
    end
    
    if GetTime() - this.showTime > 5 then
      this:Hide()
      this.showTime = nil
      this:SetScript("OnUpdate", nil)
    end
  end)
  
  -- Play sound
  PlaySound("LevelUp")
end

-------------------------------------------------
-- GEAR POPUP UI
-------------------------------------------------

-- Hidden tooltip used for stat scanning
local leafScanTip

local function GetOrCreateScanTip()
  if not leafScanTip then
    leafScanTip = CreateFrame("GameTooltip", "LeafVE_StatScanTip", UIParent, "GameTooltipTemplate")
    leafScanTip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  return leafScanTip
end

local function ParseStatLine(line, stats)
  if not line or line == "" then return end
  -- Strip color codes
  line = string.gsub(line, "|c%x%x%x%x%x%x%x%x", "")
  line = string.gsub(line, "|r", "")

  local val
  -- Primary stats (+X StatName)
  val = tonumber(string.match(line, "%+(%d+) Strength"))
  if val then stats.str = (stats.str or 0) + val end

  val = tonumber(string.match(line, "%+(%d+) Agility"))
  if val then stats.agi = (stats.agi or 0) + val end

  val = tonumber(string.match(line, "%+(%d+) Stamina"))
  if val then stats.sta = (stats.sta or 0) + val end

  val = tonumber(string.match(line, "%+(%d+) Intellect"))
  if val then stats.int_ = (stats.int_ or 0) + val end

  val = tonumber(string.match(line, "%+(%d+) Spirit"))
  if val then stats.spi = (stats.spi or 0) + val end

  val = tonumber(string.match(line, "%+(%d+) Attack Power"))
  if val then stats.ap = (stats.ap or 0) + val end

  -- Hit chance
  if string.find(line, "chance to hit") then
    val = tonumber(string.match(line, "by (%d+)%%"))
    if val then stats.hit = (stats.hit or 0) + val end
  end

  -- Melee Crit (not spell crit)
  if string.find(line, "chance to get a critical strike") and not string.find(line, "with spells") then
    val = tonumber(string.match(line, "by (%d+)%%"))
    if val then stats.crit = (stats.crit or 0) + val end
  end

  -- Spell Crit
  if string.find(line, "critical strike with spells") then
    val = tonumber(string.match(line, "by (%d+)%%"))
    if val then stats.spellcrit = (stats.spellcrit or 0) + val end
  end

  -- Spell Damage + Healing combined
  if string.find(line, "Increases damage and healing done by magical spells") then
    val = tonumber(string.match(line, "up to (%d+)"))
    if val then
      stats.spelldmg = (stats.spelldmg or 0) + val
      stats.healing = (stats.healing or 0) + val
    end
  -- Spell Damage only
  elseif string.find(line, "Increases damage done by magical spells") then
    val = tonumber(string.match(line, "up to (%d+)"))
    if val then stats.spelldmg = (stats.spelldmg or 0) + val end
  -- Healing only
  elseif string.find(line, "Increases healing done by spells") then
    val = tonumber(string.match(line, "up to (%d+)"))
    if val then stats.healing = (stats.healing or 0) + val end
  end
end

local function ComputeGearStats(slots)
  local stats = {}
  local tip = GetOrCreateScanTip()
  for slotName, itemId in pairs(slots) do
    tip:ClearLines()
    tip:SetHyperlink("item:" .. tostring(itemId) .. ":0:0:0")
    local numLines = tip:NumLines()
    if numLines and numLines > 0 then
      for i = 1, numLines do
        local leftObj = getglobal("LeafVE_StatScanTipTextLeft" .. i)
        if leftObj then
          ParseStatLine(leftObj:GetText() or "", stats)
        end
      end
    end
  end
  tip:Hide()
  return stats
end

local function AddStatLine(lines, label, val, color)
  if not val or val <= 0 then return end
  local valStr = tostring(val)
  if color then
    table.insert(lines, "|cFF" .. color .. label .. ": " .. valStr .. "|r")
  else
    table.insert(lines, label .. ": " .. valStr)
  end
end

local function FormatGearStats(stats, class)
  local lines = {}
  local classUpper = string.upper(class or "")
  local isCaster = (classUpper == "MAGE" or classUpper == "WARLOCK" or classUpper == "PRIEST")
  local isMelee  = (classUpper == "WARRIOR" or classUpper == "ROGUE" or classUpper == "HUNTER")

  if isCaster then
    AddStatLine(lines, "Spell Damage", stats.spelldmg, "88AAFF")
    AddStatLine(lines, "Healing",      stats.healing,  "88FFAA")
    AddStatLine(lines, "Spell Crit %", stats.spellcrit,"FFAA44")
    AddStatLine(lines, "Intellect",    stats.int_,     "AAAAFF")
    AddStatLine(lines, "Spirit",       stats.spi,      "AAFFAA")
    AddStatLine(lines, "Stamina",      stats.sta,      "CCCCCC")
    AddStatLine(lines, "Strength",     stats.str,      "CCCCCC")
    AddStatLine(lines, "Agility",      stats.agi,      "CCCCCC")
    AddStatLine(lines, "Attack Power", stats.ap,       "FFAA44")
    AddStatLine(lines, "Hit %",        stats.hit,      "88FF88")
    AddStatLine(lines, "Crit %",       stats.crit,     "FFCC44")
  elseif isMelee then
    AddStatLine(lines, "Attack Power", stats.ap,       "FFAA44")
    AddStatLine(lines, "Hit %",        stats.hit,      "88FF88")
    AddStatLine(lines, "Crit %",       stats.crit,     "FFCC44")
    AddStatLine(lines, "Strength",     stats.str,      "CCCCCC")
    AddStatLine(lines, "Agility",      stats.agi,      "CCCCCC")
    AddStatLine(lines, "Stamina",      stats.sta,      "CCCCCC")
    AddStatLine(lines, "Spell Damage", stats.spelldmg, "88AAFF")
    AddStatLine(lines, "Healing",      stats.healing,  "88FFAA")
    AddStatLine(lines, "Intellect",    stats.int_,     "AAAAFF")
    AddStatLine(lines, "Spirit",       stats.spi,      "AAFFAA")
  else -- Hybrid: DRUID, PALADIN, SHAMAN, or unknown
    AddStatLine(lines, "Spell Damage", stats.spelldmg, "88AAFF")
    AddStatLine(lines, "Healing",      stats.healing,  "88FFAA")
    AddStatLine(lines, "Spell Crit %", stats.spellcrit,"FFAA44")
    AddStatLine(lines, "Attack Power", stats.ap,       "FFAA44")
    AddStatLine(lines, "Hit %",        stats.hit,      "88FF88")
    AddStatLine(lines, "Crit %",       stats.crit,     "FFCC44")
    AddStatLine(lines, "Strength",     stats.str,      "CCCCCC")
    AddStatLine(lines, "Agility",      stats.agi,      "CCCCCC")
    AddStatLine(lines, "Stamina",      stats.sta,      "CCCCCC")
    AddStatLine(lines, "Intellect",    stats.int_,     "AAAAFF")
    AddStatLine(lines, "Spirit",       stats.spi,      "AAFFAA")
  end

  if table.getn(lines) == 0 then
    return "|cFF888888No stats parsed|r"
  end
  return table.concat(lines, "\n")
end

-- Format a stats table into organized vertical category layout.
-- Accepts either the short-key table from BroadcastMyStats or a direct stat table.
local function FormatBCSStats(s)
  if not s then return "|cFF888888Awaiting stats broadcast...|r" end
  local G = "|cFFFFD700"
  local W = "|cFFFFFFFF"
  local E = "|r"
  local ap   = s.ap  or 0;  local hi  = s.hi  or 0;  local mc  = s.mc  or 0;  local ms  = s.ms or 0
  local sp   = s.sp  or 0;  local sh  = s.sh  or 0;  local sc  = s.sc  or 0
  local he   = s.he  or 0;  local ss  = s.ss  or 0;  local m5  = s.m5  or 0
  local str_ = s.st  or 0;  local agi = s.ag  or 0;  local sta = s.sa  or 0
  local int_ = s["in"] or 0; local spi = s.si or 0
  local ar   = s.ar  or 0;  local de  = s.de  or 0
  local dg   = s.dg  or 0;  local pa  = s.pa  or 0;  local bl  = s.bl  or 0
  local lines = {}
  table.insert(lines, G.."Melee"..E)
  table.insert(lines, string.format("  Attack Power: "..W.."%d"..E, ap))
  table.insert(lines, string.format("  Hit: "..W.."%d%%"..E, hi))
  table.insert(lines, string.format("  Crit: "..W.."%.1f%%"..E, mc))
  table.insert(lines, string.format("  Weapon Skill: "..W.."%d"..E, ms))
  table.insert(lines, "")
  table.insert(lines, G.."Spell"..E)
  table.insert(lines, string.format("  Spell Power: "..W.."%d"..E, sp))
  table.insert(lines, string.format("  Spell Hit: "..W.."%d%%"..E, sh))
  table.insert(lines, string.format("  Spell Crit: "..W.."%.1f%%"..E, sc))
  table.insert(lines, string.format("  Healing Power: "..W.."%d"..E, he))
  table.insert(lines, string.format("  Haste: "..W.."%d%%"..E, ss))
  table.insert(lines, string.format("  MP5: "..W.."%d"..E, m5))
  table.insert(lines, "")
  table.insert(lines, G.."Base Stats"..E)
  table.insert(lines, string.format("  Str: "..W.."%d"..E.."  Agi: "..W.."%d"..E, str_, agi))
  table.insert(lines, string.format("  Sta: "..W.."%d"..E.."  Int: "..W.."%d"..E, sta, int_))
  table.insert(lines, string.format("  Spi: "..W.."%d"..E, spi))
  table.insert(lines, "")
  table.insert(lines, G.."Defense"..E)
  table.insert(lines, string.format("  Armor: "..W.."%d"..E, ar))
  table.insert(lines, string.format("  Defense: "..W.."%d"..E, de))
  table.insert(lines, string.format("  Dodge: "..W.."%.1f%%"..E, dg))
  table.insert(lines, string.format("  Parry: "..W.."%.1f%%"..E, pa))
  table.insert(lines, string.format("  Block: "..W.."%.1f%%"..E, bl))
  return table.concat(lines, "\n")
end

function LeafVE.UI:CreateGearPopup()
  if self.gearPopup then return end

  local popup = CreateFrame("Frame", "LeafVE_GearPopup", UIParent)
  popup:SetWidth(560)
  popup:SetFrameStrata("DIALOG")
  popup:EnableMouse(true)

  if LeafVE.UI.frame then
    popup:SetPoint("TOPLEFT", LeafVE.UI.frame, "TOPRIGHT", 5, 0)
    popup:SetHeight(LeafVE.UI.frame:GetHeight())
  else
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:SetHeight(560)
  end

  popup:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  popup:SetBackdropColor(0, 0, 0, 0.95)
  popup:Hide()

  -- Title
  local titleText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleText:SetPoint("TOP", popup, "TOP", 0, -15)
  titleText:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])
  popup.titleText = titleText

  -- Source / timestamp info
  local sourceText = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sourceText:SetPoint("TOP", titleText, "BOTTOM", 0, -3)
  popup.sourceText = sourceText

  -- Close button
  local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -5, -5)
  closeBtn:SetScript("OnClick", function() popup:Hide() end)

  -- Refresh button
  local refreshBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
  refreshBtn:SetWidth(80)
  refreshBtn:SetHeight(22)
  refreshBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -30, -42)
  refreshBtn:SetText("Refresh")
  SkinButtonAccent(refreshBtn)
  refreshBtn:SetScript("OnClick", function()
    if LeafVE.UI.cardCurrentPlayer then
      LeafVE.UI:RefreshGearPopup(LeafVE.UI.cardCurrentPlayer)
    end
  end)
  popup.refreshBtn = refreshBtn

  -- Left column label
  local slotLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  slotLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", 15, -68)
  slotLabel:SetText("|cFFFFD700Equipment|r")

  -- Slot scroll frame
  local slotScroll = CreateFrame("ScrollFrame", "LeafVE_GearSlotScroll", popup, "UIPanelScrollFrameTemplate")
  slotScroll:SetPoint("TOPLEFT",    slotLabel, "BOTTOMLEFT", 0,   -5)
  slotScroll:SetPoint("BOTTOMLEFT", popup,     "BOTTOMLEFT", 15,  15)
  slotScroll:SetWidth(290)
  popup.slotScroll = slotScroll

  local slotChild = CreateFrame("Frame", nil, slotScroll)
  slotChild:SetWidth(268)
  slotChild:SetHeight(1)
  slotScroll:SetScrollChild(slotChild)
  popup.slotChild = slotChild

  -- Right column label
  local statLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  statLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", 325, -68)
  statLabel:SetText("|cFFFFD700Important Stats|r")

  -- Stats text
  local statsText = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  statsText:SetPoint("TOPLEFT", statLabel, "BOTTOMLEFT", 0, -8)
  statsText:SetWidth(210)
  statsText:SetJustifyH("LEFT")
  statsText:SetText("")
  popup.statsText = statsText

  -- Slot entry frames (pre-allocated)
  popup.slotEntries = {}

  self.gearPopup = popup
end

function LeafVE.UI:RefreshGearPopup(playerName)
  if not self.gearPopup then return end
  playerName = ShortName(playerName)
  if not playerName then return end

  self.gearPopup.titleText:SetText(playerName .. "'s Gear")

  EnsureDB()
  local nameLower = Lower(playerName)
  local cache = LeafVE_GlobalDB.gearCache and LeafVE_GlobalDB.gearCache[nameLower]

  -- Prefer inspected snapshot; fall back to broadcast
  local snapshot  = nil
  local sourceLabel = ""
  if cache then
    if cache.inspected and cache.inspected.slots then
      snapshot    = cache.inspected
      sourceLabel = "Source: |cFF88FF88Inspected|r"
    elseif cache.broadcast and cache.broadcast.slots then
      snapshot    = cache.broadcast
      sourceLabel = "Source: |cFFAAAA88Broadcast|r"
    end
  end

  if snapshot then
    local timeAgo = Now() - (snapshot.updatedAt or 0)
    local timeStr
    if timeAgo < 60 then
      timeStr = timeAgo .. "s ago"
    elseif timeAgo < 3600 then
      timeStr = math.floor(timeAgo / 60) .. "m ago"
    else
      timeStr = math.floor(timeAgo / 3600) .. "h ago"
    end
    self.gearPopup.sourceText:SetText(sourceLabel .. "  |cFF888888" .. timeStr .. "|r")
  else
    self.gearPopup.sourceText:SetText("|cFF888888No gear data cached|r")
  end

  -- Hide existing slot entry frames
  for i = 1, table.getn(self.gearPopup.slotEntries) do
    self.gearPopup.slotEntries[i]:Hide()
  end

  local scrollChild = self.gearPopup.slotChild
  local yOffset     = -5
  local entryH      = 30
  local me = ShortName(UnitName("player"))
  local isLocalPlayer = me and Lower(playerName) == Lower(me)

  if snapshot and snapshot.slots then
    for i = 1, table.getn(GEAR_SLOT_NAMES) do
      local slotName = GEAR_SLOT_NAMES[i]
      local label    = GEAR_SLOT_LABELS[slotName] or slotName
      local itemId   = snapshot.slots[slotName]

      local entry = self.gearPopup.slotEntries[i]
      if not entry then
        entry = CreateFrame("Frame", nil, scrollChild)
        entry:SetHeight(entryH)
        entry:SetWidth(265)

        local iconTex = entry:CreateTexture(nil, "OVERLAY")
        iconTex:SetWidth(24)
        iconTex:SetHeight(24)
        iconTex:SetPoint("LEFT", entry, "LEFT", 2, 0)
        entry.iconTex = iconTex

        local labelFS = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        labelFS:SetPoint("LEFT", entry, "LEFT", 28, 0)
        labelFS:SetWidth(75)
        labelFS:SetJustifyH("LEFT")
        entry.labelFS = labelFS

        local itemFS = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        itemFS:SetPoint("LEFT", labelFS, "RIGHT", 2, 0)
        itemFS:SetWidth(157)
        itemFS:SetJustifyH("LEFT")
        entry.itemFS = itemFS

        entry:EnableMouse(true)
        entry:SetScript("OnEnter", function()
          if this.itemId then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. tostring(this.itemId) .. ":0:0:0")
            GameTooltip:Show()
          end
        end)
        entry:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)

        self.gearPopup.slotEntries[i] = entry
      end

      entry:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 2, yOffset)
      entry.itemId = itemId
      entry.labelFS:SetText("|cFFAAAAAA" .. label .. ":|r")

      -- Determine icon texture: live for local player, from item cache for others
      local slotID = GEAR_SLOT_IDS[slotName]
      local iconTexture = nil
      if isLocalPlayer and slotID then
        iconTexture = GetInventoryItemTexture("player", slotID)
      elseif itemId then
        local _, _, _, _, _, _, _, _, _, itemTex = GetItemInfo(itemId)
        iconTexture = itemTex
      end
      if iconTexture then
        entry.iconTex:SetTexture(iconTexture)
        entry.iconTex:Show()
      elseif itemId then
        entry.iconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        entry.iconTex:Show()
      else
        entry.iconTex:Hide()
      end

      if itemId then
        local itemName, _, itemRarity = GetItemInfo(itemId)
        local displayText
        if itemName then
          local r, g, b
          if GetItemQualityColor and itemRarity then
            r, g, b = GetItemQualityColor(itemRarity)
          end
          if r then
            local hex = string.format("%02X%02X%02X",
              math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
            displayText = "|cFF" .. hex .. itemName .. "|r"
          else
            displayText = itemName
          end
        else
          displayText = "|cFF888888#" .. tostring(itemId) .. "|r"
        end
        entry.itemFS:SetText(displayText)
      else
        entry.itemFS:SetText("|cFF444444--empty--|r")
        entry.itemId = nil
      end

      entry:Show()
      yOffset = yOffset - entryH - 6
    end
  else
    local entry = self.gearPopup.slotEntries[1]
    if not entry then
      entry = CreateFrame("Frame", nil, scrollChild)
      entry:SetHeight(entryH)
      entry:SetWidth(265)
      local iconTex = entry:CreateTexture(nil, "OVERLAY")
      iconTex:SetWidth(24)
      iconTex:SetHeight(24)
      iconTex:SetPoint("LEFT", entry, "LEFT", 2, 0)
      entry.iconTex = iconTex
      local labelFS = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      labelFS:SetPoint("LEFT", entry, "LEFT", 28, 0)
      labelFS:SetWidth(75)
      labelFS:SetJustifyH("LEFT")
      entry.labelFS = labelFS
      local itemFS = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      itemFS:SetPoint("LEFT", labelFS, "RIGHT", 2, 0)
      itemFS:SetWidth(157)
      itemFS:SetJustifyH("LEFT")
      entry.itemFS = itemFS
      self.gearPopup.slotEntries[1] = entry
    end
    entry:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 2, yOffset)
    entry.labelFS:SetText("")
    entry.itemFS:SetText("|cFF888888No gear data available|r")
    entry.itemId = nil
    entry.iconTex:Hide()
    entry:Show()
    yOffset = yOffset - entryH - 6
  end

  scrollChild:SetHeight(math.max(1, math.abs(yOffset) + 20))

  -- Compute and display organized stats
  local statsText = "|cFF888888No stats available|r"
  if isLocalPlayer and BCS and BCS.RunScans then
    -- Local player: use BCS for live computed stats
    BCS.needScanGear    = true
    BCS.needScanTalents = true
    BCS.needScanAuras   = true
    BCS.needScanSkills  = true
    BCS:RunScans()
    BCS.needScanGear    = false
    BCS.needScanTalents = false
    BCS.needScanAuras   = false
    BCS.needScanSkills  = false

    local apBase, apPos, apNeg = UnitAttackPower("player")
    local ap = (apBase or 0) + (apPos or 0) + (apNeg or 0)
    local hit         = BCS:GetHitRating() or 0
    local mcrit       = BCS:GetCritChance() or 0
    local mhSkill     = BCS:GetMHWeaponSkill() or 0
    local spellPower  = BCS:GetSpellPower() or 0
    local spellHit    = BCS:GetSpellHitRating() or 0
    local spellCrit   = BCS:GetSpellCritChance() or 0
    local healing     = BCS:GetHealingPower() or 0
    local _, spellHaste = BCS:GetHaste()
    spellHaste = spellHaste or 0
    local _, _, manaMP5 = BCS:GetManaRegen()
    manaMP5 = manaMP5 or 0
    local _, str_ = UnitStat("player", 1)
    local _, agi  = UnitStat("player", 2)
    local _, sta  = UnitStat("player", 3)
    local _, int_ = UnitStat("player", 4)
    local _, spi  = UnitStat("player", 5)
    local dodge  = GetDodgeChance and GetDodgeChance() or 0
    local parry  = GetParryChance and GetParryChance() or 0
    local block  = GetBlockChance and GetBlockChance() or 0
    local defBase, defMod = 0, 0
    if UnitDefense then
      defBase, defMod = UnitDefense("player")
      defBase = defBase or 0; defMod = defMod or 0
    end
    local _, armor = UnitArmor("player")
    statsText = FormatBCSStats({
      ap = ap, hi = hit, mc = mcrit, ms = mhSkill,
      sp = spellPower, sh = spellHit, sc = spellCrit, he = healing,
      ss = spellHaste, m5 = manaMP5,
      st = str_ or 0, ag = agi or 0, sa = sta or 0,
      ["in"] = int_ or 0, si = spi or 0,
      ar = armor or 0, de = defBase + defMod,
      dg = dodge, pa = parry, bl = block,
    })
  else
    -- Other players: check for cached BCS stats from broadcast
    EnsureDB()
    local cachedBCS = LeafVE_GlobalDB.gearStatsCache and LeafVE_GlobalDB.gearStatsCache[nameLower]
    if cachedBCS and cachedBCS.stats then
      statsText = FormatBCSStats(cachedBCS.stats)
    else
      statsText = "|cFF888888Awaiting stats broadcast...|r"
    end
  end
  self.gearPopup.statsText:SetText(statsText)
end

function LeafVE.UI:CreateAchievementListPopup()
  if self.achPopup then return end
  
  local popup = CreateFrame("Frame", "LeafVE_AchievementListPopup", UIParent)
  popup:SetWidth(450)
  popup:SetFrameStrata("DIALOG")
  popup:EnableMouse(true)
  
  -- Anchor to right side of main UI panel (matching badge popup)
  if LeafVE.UI.frame then
    popup:SetPoint("TOPLEFT", LeafVE.UI.frame, "TOPRIGHT", 5, 0)
    popup:SetHeight(LeafVE.UI.frame:GetHeight())
  else
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:SetHeight(500)
  end
  
  popup:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  popup:SetBackdropColor(0, 0, 0, 0.95)
  popup:Hide()
  
  -- Title (gold like badge collection)
  local titleText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleText:SetPoint("TOP", popup, "TOP", 0, -15)
  titleText:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])
  popup.titleText = titleText
  
  -- Player name
  local playerNameText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  playerNameText:SetPoint("TOP", titleText, "BOTTOM", 0, -5)
  popup.playerNameText = playerNameText
  
  -- Close button
  local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -5, -5)
  closeBtn:SetScript("OnClick", function() popup:Hide() end)
  
  -- Scroll frame
  local scrollFrame = CreateFrame("ScrollFrame", "LeafVE_AchScrollFrame", popup, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -60)
  scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -30, 15)
  popup.scrollFrame = scrollFrame
  
  -- Scroll child
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(550)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  popup.scrollChild = scrollChild
  
  -- Scroll bar
  local scrollBar = getglobal(scrollFrame:GetName().."ScrollBar")
  popup.scrollBar = scrollBar
  
  -- Achievement entries table
  popup.achEntries = {}
  
  self.achPopup = popup
end

function LeafVE.UI:RefreshAchievementPopup(playerName)
  if not self.achPopup then return end
  
  self.achPopup.titleText:SetText(playerName.."'s Achievements")  -- ← Change this line
  
  local achievements = {}
  
  if LeafVE_AchTest_DB and LeafVE_AchTest_DB.achievements and LeafVE_AchTest_DB.achievements[playerName] then
    local playerAchievements = LeafVE_AchTest_DB.achievements[playerName]
    
    for achId, achData in pairs(playerAchievements) do
      if type(achData) == "table" and achData.points and achData.timestamp then
        -- Get proper name, icon, and description from achievement addon metadata
        local meta = nil
        if LeafVE_AchTest and LeafVE_AchTest.GetAchievementMeta then
          meta = LeafVE_AchTest.GetAchievementMeta(achId)
        end
        local displayName = nil
        if meta and meta.name then
          displayName = meta.name
        else
          -- Fallback: convert ID to title case
          displayName = achId
          displayName = string.gsub(displayName, "_", " ")
          displayName = string.gsub(displayName, "(%a)([%w_']*)", function(first, rest)
            return string.upper(first)..string.lower(rest)
          end)
        end
        local displayIcon = (meta and meta.icon) or GetAchievementIcon(achId)
        local displayDesc = (meta and meta.desc) or ("Completed on "..date("%m/%d/%Y", achData.timestamp))
        
        table.insert(achievements, {
          id = achId,
          name = displayName,
          desc = displayDesc,
          icon = displayIcon,
          points = achData.points,
          completed = true,
          timestamp = achData.timestamp
        })
      end
    end
  end
  
  -- Sort by most recent
  table.sort(achievements, function(a, b)
    return a.timestamp > b.timestamp
  end)
  
  -- Clear previous entries
  for i = 1, table.getn(self.achPopup.achEntries) do
    self.achPopup.achEntries[i]:Hide()
  end
  
  local scrollChild = self.achPopup.scrollChild
  local yOffset = -5
  local entryHeight = 50
  
  if table.getn(achievements) == 0 then
    local noAch = self.achPopup.achEntries[1]
    if not noAch then
      noAch = CreateFrame("Frame", nil, scrollChild)
      noAch:SetWidth(550)
      noAch:SetHeight(50)
      
      local text = noAch:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      text:SetPoint("CENTER", noAch, "CENTER", 0, 0)
      text:SetText("|cFF888888No achievements yet|r")
      noAch.text = text
      
      table.insert(self.achPopup.achEntries, noAch)
    end
    noAch:SetPoint("TOP", scrollChild, "TOP", 0, -20)
    noAch:Show()
  else
    for i = 1, table.getn(achievements) do
      local ach = achievements[i]
      local entry = self.achPopup.achEntries[i]
      
      if not entry then
        entry = CreateFrame("Frame", nil, scrollChild)
        entry:SetWidth(550)
        entry:SetHeight(entryHeight)
        
        local icon = entry:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(40)
        icon:SetHeight(40)
        icon:SetPoint("LEFT", entry, "LEFT", 5, 0)
        entry.icon = icon
        
        local nameText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -5)
        nameText:SetWidth(400)
        nameText:SetJustifyH("LEFT")
        entry.nameText = nameText
        
        local descText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        descText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
        descText:SetWidth(400)
        descText:SetJustifyH("LEFT")
        entry.descText = descText
        
        local pointsBadge = CreateFrame("Frame", nil, entry)
        pointsBadge:SetWidth(44)
        pointsBadge:SetHeight(44)
        pointsBadge:SetPoint("RIGHT", entry, "RIGHT", -12, 0)

        local badgeIcon = pointsBadge:CreateTexture(nil, "BACKGROUND")
        badgeIcon:SetAllPoints()
        badgeIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        badgeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pointsBadge.Icon = badgeIcon

        local badgeText = pointsBadge:CreateFontString(nil, "OVERLAY")
        badgeText:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
        badgeText:SetPoint("CENTER", pointsBadge, "CENTER", 0, 0)
        pointsBadge.Text = badgeText
        entry.pointsBadge = pointsBadge
        
        local bg = entry:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(entry)
        bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        bg:SetVertexColor(0.1, 0.1, 0.1, 0.3)
        entry.bg = bg

        -- Tooltip — same style as Badge tooltip
        entry:EnableMouse(true)
        entry:SetScript("OnEnter", function()
          if not this.achId then return end
          -- Get real achievement metadata from the achievement addon if available
          local meta = LeafVE_AchTest and LeafVE_AchTest.GetAchievementMeta and
                       LeafVE_AchTest.GetAchievementMeta(this.achId)
          local achName   = meta and meta.name     or this.achDisplayName
          local achDesc   = meta and meta.desc     or ""
          local achCat    = meta and meta.category or "Achievement"
          local achPts    = this.achPoints or 0
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:ClearLines()
          -- All entries in this popup are completed achievements
          GameTooltip:SetText(achName, THEME.gold[1], THEME.gold[2], THEME.gold[3], 1, true)
          GameTooltip:AddLine("|cFF888888"..achCat.."|r", 1, 1, 1)
          if achDesc and achDesc ~= "" then
            GameTooltip:AddLine(achDesc, 1, 1, 1, true)
          end
          GameTooltip:AddLine(" ", 1, 1, 1)
          if this.achTimestamp and this.achTimestamp > 0 then
            GameTooltip:AddLine("Earned: "..date("%m/%d/%Y", this.achTimestamp), 0.5, 0.8, 0.5)
          else
            GameTooltip:AddLine("Earned", 0.5, 0.8, 0.5)
          end
          GameTooltip:AddLine(" ", 1, 1, 1)
          GameTooltip:AddLine(achPts.." Achievement Points", 1.0, 0.5, 0.0)
          -- Boss criteria list for dungeon/raid completion achievements
          if meta and meta.criteria_key and meta.criteria_type then
            local bossList = LeafVE_AchTest and LeafVE_AchTest.GetBossCriteria and
                             LeafVE_AchTest.GetBossCriteria(meta.criteria_key, meta.criteria_type)
            local progress = LeafVE_AchTest and LeafVE_AchTest.GetBossProgress and
                             LeafVE_AchTest.GetBossProgress(this.achPlayerName, meta.criteria_key, meta.criteria_type)
            if bossList then
              GameTooltip:AddLine(" ", 1, 1, 1)
              GameTooltip:AddLine("Criteria:", 1.0, 0.82, 0.2)
              for _, bossName in ipairs(bossList) do
                if progress and progress[bossName] then
                  GameTooltip:AddLine("|cFF00CC00[x]|r "..bossName, 0.9, 0.9, 0.9)
                else
                  GameTooltip:AddLine("|cFF666666[ ]|r "..bossName, 0.5, 0.5, 0.5)
                end
              end
            end
          end
          GameTooltip:Show()
        end)
        entry:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)

        table.insert(self.achPopup.achEntries, entry)
      end

      entry:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)

      entry.icon:SetTexture(ach.icon)
      if not entry.icon:GetTexture() then
        entry.icon:SetTexture(LEAF_FALLBACK)
      end

      entry.icon:SetVertexColor(1, 1, 1, 1)
      entry.nameText:SetText(ach.name)
      entry.nameText:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])
      entry.descText:SetText(ach.desc)
      entry.descText:SetTextColor(0.8, 0.8, 0.8)
      entry.pointsBadge.Icon:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])
      entry.pointsBadge.Text:SetText(tostring(ach.points).." pts")
      -- Store per-frame data for the tooltip
      entry.achId          = ach.id
      entry.achDisplayName = ach.name
      entry.achPoints      = ach.points
      entry.achTimestamp   = ach.timestamp
      entry.achPlayerName  = playerName
      
      entry:Show()
      yOffset = yOffset - entryHeight - 8
    end
  end
  
  scrollChild:SetHeight(math.max(1, math.abs(yOffset) + 50))
  
  local scrollRange = self.achPopup.scrollFrame:GetVerticalScrollRange()
  if scrollRange > 0 then
    self.achPopup.scrollBar:Show()
  else
    self.achPopup.scrollBar:Hide()
  end
  
  self.achPopup.scrollFrame:SetVerticalScroll(0)
  self.achPopup.scrollBar:SetValue(0)
end

local function BuildMyPanel(panel)
  local maxWidth = 500
  
  -- Block header background
  local headerBG = panel:CreateTexture(nil, "BACKGROUND")
  headerBG:SetPoint("TOP", panel, "TOP", -15, -10)
  headerBG:SetWidth(420)  -- ← NARROWER (was 500)
  headerBG:SetHeight(50)
  headerBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  headerBG:SetVertexColor(0.15, 0.15, 0.18, 0.9)
  
  -- Top accent stripe
  local accentTop = panel:CreateTexture(nil, "BORDER")
  accentTop:SetPoint("TOPLEFT", headerBG, "TOPLEFT", 0, 0)
  accentTop:SetPoint("TOPRIGHT", headerBG, "TOPRIGHT", 0, 0)
  accentTop:SetHeight(3)
  accentTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  accentTop:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)
  
  -- Title
  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOP", headerBG, "TOP", 0, -10)
  h:SetText("|cFFFFD700My Stats|r")

  -- Subtitle
  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOP", h, "BOTTOM", 0, -3)
  subtitle:SetText("|cFF888888View your contribution statistics|r")
  
  local todayLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  todayLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -80)
  todayLabel:SetText("|cFF2DD35CToday|r")
  
  local todayStats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  todayStats:SetPoint("TOPLEFT", todayLabel, "BOTTOMLEFT", 0, -5)
  todayStats:SetWidth(maxWidth)
  todayStats:SetJustifyH("LEFT")
  todayStats:SetText("")
  panel.todayStats = todayStats
  
  local weekLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  weekLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -150)
  weekLabel:SetText("|cFF2DD35CThis Week|r")
  
  local weekStats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  weekStats:SetPoint("TOPLEFT", weekLabel, "BOTTOMLEFT", 0, -5)
  weekStats:SetWidth(maxWidth)
  weekStats:SetJustifyH("LEFT")
  weekStats:SetText("")
  panel.weekStats = weekStats
  
  local seasonLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  seasonLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -220)
  seasonLabel:SetText("|cFF2DD35CSeason|r")
  
  local seasonStats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  seasonStats:SetPoint("TOPLEFT", seasonLabel, "BOTTOMLEFT", 0, -5)
  seasonStats:SetWidth(maxWidth)
  seasonStats:SetJustifyH("LEFT")
  seasonStats:SetText("")
  panel.seasonStats = seasonStats
  
  local alltimeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  alltimeLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -290)
  alltimeLabel:SetText("|cFF2DD35CAll-Time|r")
  
  local alltimeStats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  alltimeStats:SetPoint("TOPLEFT", alltimeLabel, "BOTTOMLEFT", 0, -5)
  alltimeStats:SetWidth(maxWidth)
  alltimeStats:SetJustifyH("LEFT")
  alltimeStats:SetText("")
  panel.alltimeStats = alltimeStats
  
  -- Section Divider (now anchored to alltimeStats)
  local divider = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  divider:SetPoint("TOPLEFT", alltimeStats, "BOTTOMLEFT", 0, -20)
  divider:SetText("|cFFFFD700▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬|r")
  
  -- Last Week's Winner (styled like other stats)
  local lastWeekLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lastWeekLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -15)
  lastWeekLabel:SetText("|cFF2DD35CLast Week's Winner|r")
  
  local lastWeekWinner = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lastWeekWinner:SetPoint("TOPLEFT", lastWeekLabel, "BOTTOMLEFT", 0, -5)
  lastWeekWinner:SetWidth(maxWidth)
  lastWeekWinner:SetJustifyH("LEFT")
  lastWeekWinner:SetText("Loading...")
  panel.lastWeekWinner = lastWeekWinner
  
  -- All-Time Leader (styled like other stats)
  local alltimeLeaderLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  alltimeLeaderLabel:SetPoint("TOPLEFT", lastWeekWinner, "BOTTOMLEFT", 0, -15)
  alltimeLeaderLabel:SetText("|cFF2DD35CAll-Time Leader|r")
  
  local alltimeLeader = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  alltimeLeader:SetPoint("TOPLEFT", alltimeLeaderLabel, "BOTTOMLEFT", 0, -5)
  alltimeLeader:SetWidth(maxWidth)
  alltimeLeader:SetJustifyH("LEFT")
  alltimeLeader:SetText("Loading...")
  panel.alltimeLeader = alltimeLeader

  -- Season Rewards (beneath All-Time Leader)
  local seasonRewardsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  seasonRewardsLabel:SetPoint("TOPLEFT", alltimeLeader, "BOTTOMLEFT", 0, -15)
  seasonRewardsLabel:SetText("|cFF2DD35CSeason Rewards|r")

  local seasonRewards = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  seasonRewards:SetPoint("TOPLEFT", seasonRewardsLabel, "BOTTOMLEFT", 0, -4)
  seasonRewards:SetWidth(maxWidth)
  seasonRewards:SetJustifyH("LEFT")
  seasonRewards:SetText("")
  panel.seasonRewards = seasonRewards
  
  -- Week Countdown (styled like other stats) - MOVE TO RIGHT SIDE
  local weekCountdownLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  weekCountdownLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 250, -15)  -- ← 250 pixels to the right
  weekCountdownLabel:SetText("|cFF2DD35CWeek Resets In|r")
  
  local weekCountdown = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  weekCountdown:SetPoint("TOPLEFT", weekCountdownLabel, "BOTTOMLEFT", 0, -5)
  weekCountdown:SetWidth(maxWidth)
  weekCountdown:SetJustifyH("LEFT")
  weekCountdown:SetText("Loading...")
  panel.weekCountdown = weekCountdown

  -- Current Weekly Standings (top 5)
  local weekStandingsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  weekStandingsLabel:SetPoint("TOPLEFT", weekCountdown, "BOTTOMLEFT", 0, -15)
  weekStandingsLabel:SetText("|cFF2DD35CCurrent Weekly Standings|r")

  local weekTopEntries = {}
  local prevTopAnchor = weekStandingsLabel
  for i = 1, 5 do
    local entry = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    entry:SetPoint("TOPLEFT", prevTopAnchor, "BOTTOMLEFT", 0, -4)
    entry:SetWidth(maxWidth)
    entry:SetJustifyH("LEFT")
    entry:SetText("Loading...")
    weekTopEntries[i] = entry
    prevTopAnchor = entry
  end
  panel.weekTopEntries = weekTopEntries

local legend = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  legend:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12)
  legend:SetWidth(maxWidth)
  legend:SetJustifyH("LEFT")
  legend:SetText("|cFFAAAAAAL = Login  |  G = Group  |  S = Shoutout|r")

end

local function BuildShoutoutsPanel(panel)
  -- Block header background
  local headerBG = panel:CreateTexture(nil, "BACKGROUND")
  headerBG:SetPoint("TOP", panel, "TOP", -15, -10)
  headerBG:SetWidth(420)
  headerBG:SetHeight(50)
  headerBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  headerBG:SetVertexColor(0.15, 0.15, 0.18, 0.9)
  
  -- Top accent stripe
  local accentTop = panel:CreateTexture(nil, "BORDER")
  accentTop:SetPoint("TOPLEFT", headerBG, "TOPLEFT", 0, 0)
  accentTop:SetPoint("TOPRIGHT", headerBG, "TOPRIGHT", 0, 0)
  accentTop:SetHeight(3)
  accentTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  accentTop:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)
  
  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOP", headerBG, "TOP", 0, -10)
  h:SetText("|cFFFFD700Shoutouts|r")

  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOP", h, "BOTTOM", 0, -3)
  subtitle:SetText("|cFF888888Give recognition to guild members! You can give 2 shoutouts per day.|r")
  
  local usageText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  usageText:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -80)
  usageText:SetText("Shoutouts remaining today: 2 / 2")
  panel.usageText = usageText
  
  local targetLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  targetLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -120)
  targetLabel:SetText("Target Player:")
  
  local targetInput = CreateFrame("EditBox", nil, panel)
  targetInput:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 5, -5)
  targetInput:SetWidth(200)
  targetInput:SetHeight(20)
  targetInput:SetAutoFocus(false)
  targetInput:SetFontObject(GameFontHighlight)
  targetInput:SetMaxLetters(50)
  
  local targetInputBG = CreateFrame("Frame", nil, panel)
  targetInputBG:SetPoint("TOPLEFT", targetInput, "TOPLEFT", -5, 5)
  targetInputBG:SetPoint("BOTTOMRIGHT", targetInput, "BOTTOMRIGHT", 5, -5)
  targetInputBG:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  targetInputBG:SetBackdropColor(0, 0, 0, 0.5)
  targetInputBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  targetInputBG:SetFrameLevel(targetInput:GetFrameLevel() - 1)
  
  -- Autocomplete suggestion dropdown for target input
  local suggestFrame = CreateFrame("Frame", "LeafVE_TargetSuggest", UIParent)
  suggestFrame:SetFrameStrata("TOOLTIP")
  suggestFrame:SetWidth(210)
  suggestFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  suggestFrame:SetBackdropColor(0, 0, 0, 0.9)
  suggestFrame:SetBackdropBorderColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)
  suggestFrame:Hide()

  local MAX_SUGGESTIONS = 8
  local suggestButtons = {}
  for i = 1, MAX_SUGGESTIONS do
    local btn = CreateFrame("Button", nil, suggestFrame)
    btn:SetWidth(200)
    btn:SetHeight(18)
    btn:SetPoint("TOPLEFT", suggestFrame, "TOPLEFT", 5, -3 - (i - 1) * 18)

    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetAllPoints(btn)
    txt:SetJustifyH("LEFT")
    btn.txt = txt

    local hoverBg = btn:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints(btn)
    hoverBg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    hoverBg:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.3)
    hoverBg:Hide()

    btn:SetScript("OnEnter", function() hoverBg:Show() end)
    btn:SetScript("OnLeave", function() hoverBg:Hide() end)
    btn:SetScript("OnClick", function()
      targetInput:SetText(btn.txt:GetText())
      suggestFrame:Hide()
      targetInput:ClearFocus()
    end)

    suggestButtons[i] = btn
  end

  local function ShowTargetSuggestions()
    local text = targetInput:GetText()
    if not text or text == "" then
      suggestFrame:Hide()
      return
    end

    local lowerText = Lower(text)
    local matches = {}
    local seen = {}

    -- Search current guild roster cache
    LeafVE:UpdateGuildRosterCache()
    if LeafVE.guildRosterCache then
      for lname, data in pairs(LeafVE.guildRosterCache) do
        if string.sub(lname, 1, string.len(lowerText)) == lowerText then
          if not seen[lname] then
            seen[lname] = true
            table.insert(matches, data.name)
          end
        end
      end
    end

    -- Also include persistent roster (offline / historical members)
    EnsureDB()
    if LeafVE_DB.persistentRoster then
      for lname, data in pairs(LeafVE_DB.persistentRoster) do
        if string.sub(lname, 1, string.len(lowerText)) == lowerText then
          if not seen[lname] then
            seen[lname] = true
            table.insert(matches, data.name)
          end
        end
      end
    end

    table.sort(matches, function(a, b) return a < b end)

    if table.getn(matches) == 0 then
      suggestFrame:Hide()
      return
    end

    local numShow = math.min(MAX_SUGGESTIONS, table.getn(matches))
    suggestFrame:SetHeight(numShow * 18 + 6)

    for i = 1, MAX_SUGGESTIONS do
      if i <= numShow then
        suggestButtons[i].txt:SetText(matches[i])
        suggestButtons[i]:Show()
      else
        suggestButtons[i]:Hide()
      end
    end

    suggestFrame:SetPoint("TOPLEFT", targetInput, "BOTTOMLEFT", -5, -2)
    suggestFrame:Show()
  end

  targetInput:SetScript("OnTextChanged", function() ShowTargetSuggestions() end)
  targetInput:SetScript("OnEscapePressed", function()
    targetInput:ClearFocus()
    suggestFrame:Hide()
  end)
  targetInput:SetScript("OnEnterPressed", function()
    targetInput:ClearFocus()
    suggestFrame:Hide()
  end)

  panel.targetInput = targetInput
  
  local hintText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hintText:SetPoint("TOPLEFT", targetInput, "BOTTOMLEFT", 0, -2)
  hintText:SetText("|cFF888888Type player name (case-insensitive)|r")
  
  local reasonLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  reasonLabel:SetPoint("TOPLEFT", targetInput, "BOTTOMLEFT", -5, -20)
  reasonLabel:SetText("Reason (optional):")
  
  local reasonEdit = CreateFrame("EditBox", nil, panel)
  reasonEdit:SetPoint("TOPLEFT", reasonLabel, "BOTTOMLEFT", 0, -5)
  reasonEdit:SetWidth(450)
  reasonEdit:SetHeight(60)
  reasonEdit:SetMultiLine(true)
  reasonEdit:SetAutoFocus(false)
  reasonEdit:SetFontObject(GameFontHighlight)
  reasonEdit:SetMaxLetters(200)
  
  local reasonBG = CreateFrame("Frame", nil, panel)
  reasonBG:SetPoint("TOPLEFT", reasonEdit, "TOPLEFT", -5, 5)
  reasonBG:SetPoint("BOTTOMRIGHT", reasonEdit, "BOTTOMRIGHT", 5, -5)
  reasonBG:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  reasonBG:SetBackdropColor(0, 0, 0, 0.5)
  reasonBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  reasonBG:SetFrameLevel(reasonEdit:GetFrameLevel() - 1)
  reasonEdit:SetScript("OnEscapePressed", function() reasonEdit:ClearFocus() end)
  panel.reasonEdit = reasonEdit
  
  local sendBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  sendBtn:SetPoint("TOPLEFT", reasonEdit, "BOTTOMLEFT", 0, -10)
  sendBtn:SetWidth(120)
  sendBtn:SetHeight(25)
  sendBtn:SetText("Send Shoutout")
  SkinButtonAccent(sendBtn)
  
  sendBtn:SetScript("OnClick", function()
    local target = panel.targetInput:GetText()
    target = Trim(target)
    local reason = reasonEdit:GetText()
    
    if target and target ~= "" then
      if LeafVE:GiveShoutout(target, reason) then
        panel.targetInput:SetText("")
        reasonEdit:SetText("")
        
        if LeafVE.UI and LeafVE.UI.Refresh then
          LeafVE.UI:Refresh()
        end
        if LeafVE.UI and LeafVE.UI.RefreshShoutoutsPanel then
          LeafVE.UI:RefreshShoutoutsPanel()
        end
      end
    else
      Print("Please enter a player name!")
    end
  end)

  -- Separator
  local feedSep = panel:CreateTexture(nil, "ARTWORK")
  feedSep:SetPoint("TOPLEFT", sendBtn, "BOTTOMLEFT", 0, -14)
  feedSep:SetWidth(450)
  feedSep:SetHeight(1)
  feedSep:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  feedSep:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.5)

  -- Recent Shoutouts section header
  local feedHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  feedHeader:SetPoint("TOPLEFT", feedSep, "BOTTOMLEFT", 0, -6)
  feedHeader:SetText("|cFFFFD700Recent Shoutouts|r")

  -- Scroll frame for the shoutout feed
  local shoutScrollFrame = CreateFrame("ScrollFrame", nil, panel)
  shoutScrollFrame:SetPoint("TOPLEFT", feedHeader, "BOTTOMLEFT", 0, -5)
  shoutScrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)
  shoutScrollFrame:EnableMouse(true)
  shoutScrollFrame:EnableMouseWheel(true)

  local shoutScrollChild = CreateFrame("Frame", nil, shoutScrollFrame)
  shoutScrollChild:SetWidth(430)
  shoutScrollChild:SetHeight(1)
  shoutScrollFrame:SetScrollChild(shoutScrollChild)

  shoutScrollFrame:SetScript("OnMouseWheel", function()
    local current = shoutScrollFrame:GetVerticalScroll()
    local maxScroll = shoutScrollFrame:GetVerticalScrollRange()
    local newScroll = current - (arg1 * 30)
    if newScroll < 0 then newScroll = 0 end
    if newScroll > maxScroll then newScroll = maxScroll end
    shoutScrollFrame:SetVerticalScroll(newScroll)
  end)

  local shoutScrollBar = CreateFrame("Slider", nil, panel)
  shoutScrollBar:SetPoint("TOPLEFT", shoutScrollFrame, "TOPRIGHT", 4, 0)
  shoutScrollBar:SetPoint("BOTTOMLEFT", shoutScrollFrame, "BOTTOMRIGHT", 4, 0)
  shoutScrollBar:SetWidth(16)
  shoutScrollBar:SetOrientation("VERTICAL")
  shoutScrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  shoutScrollBar:SetMinMaxValues(0, 100)
  shoutScrollBar:SetValue(0)

  local shoutThumb = shoutScrollBar:GetThumbTexture()
  shoutThumb:SetWidth(16)
  shoutThumb:SetHeight(24)

  shoutScrollBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  shoutScrollBar:SetBackdropColor(0, 0, 0, 0.3)
  shoutScrollBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

  shoutScrollBar:SetScript("OnValueChanged", function()
    local value = shoutScrollBar:GetValue()
    local maxScroll = shoutScrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      shoutScrollFrame:SetVerticalScroll((value / 100) * maxScroll)
    end
  end)

  shoutScrollFrame:SetScript("OnVerticalScroll", function()
    local maxScroll = shoutScrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      local current = shoutScrollFrame:GetVerticalScroll()
      shoutScrollBar:SetValue((current / maxScroll) * 100)
    else
      shoutScrollBar:SetValue(0)
    end
  end)

  panel.shoutScrollFrame = shoutScrollFrame
  panel.shoutScrollChild = shoutScrollChild
  panel.shoutScrollBar = shoutScrollBar
  panel.shoutEntries = {}
end

local function CreateScrollablePanel(panel, title, desc)
  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
  h:SetText(title)
  h:SetTextColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3])
  
  local infoText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  infoText:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -40)
  infoText:SetWidth(500)
  infoText:SetJustifyH("LEFT")
  infoText:SetText(desc)
  
  local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
  scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -80)
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)
  scrollFrame:EnableMouse(true)
  scrollFrame:EnableMouseWheel(true)
  
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(500)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  
  scrollFrame:SetScript("OnMouseWheel", function()
    local current = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    local newScroll = current - (arg1 * 40)
    if newScroll < 0 then newScroll = 0 end
    if newScroll > maxScroll then newScroll = maxScroll end
    scrollFrame:SetVerticalScroll(newScroll)
  end)
  
  local scrollBar = CreateFrame("Slider", nil, panel)
  scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -80)
  scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 12)
  scrollBar:SetWidth(16)
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetMinMaxValues(0, 100)
  scrollBar:SetValue(0)
  
  local thumb = scrollBar:GetThumbTexture()
  thumb:SetWidth(16)
  thumb:SetHeight(24)
  
  scrollBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  scrollBar:SetBackdropColor(0, 0, 0, 0.3)
  scrollBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
  
  scrollBar:SetScript("OnValueChanged", function()
    local value = scrollBar:GetValue()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      scrollFrame:SetVerticalScroll((value / 100) * maxScroll)
    end
  end)
  
  scrollFrame:SetScript("OnVerticalScroll", function()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      local current = scrollFrame:GetVerticalScroll()
      scrollBar:SetValue((current / maxScroll) * 100)
    else
      scrollBar:SetValue(0)
    end
  end)
  
  panel.scrollFrame = scrollFrame
  panel.scrollChild = scrollChild
  panel.scrollBar = scrollBar
end

-------------------------------------------------
-- ALT LINKING PANEL (FEATURE A)
-------------------------------------------------

local function BuildAltPanel(panel)
  -- Header background
  local headerBG = panel:CreateTexture(nil, "BACKGROUND")
  headerBG:SetPoint("TOP", panel, "TOP", -15, -10)
  headerBG:SetWidth(420)
  headerBG:SetHeight(50)
  headerBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  headerBG:SetVertexColor(0.15, 0.15, 0.18, 0.9)

  local accentTop = panel:CreateTexture(nil, "BORDER")
  accentTop:SetPoint("TOPLEFT", headerBG, "TOPLEFT", 0, 0)
  accentTop:SetPoint("TOPRIGHT", headerBG, "TOPRIGHT", 0, 0)
  accentTop:SetHeight(3)
  accentTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  accentTop:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)

  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOP", headerBG, "TOP", 0, -10)
  h:SetText("|cFFFFD700Alt Linking|r")

  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOP", h, "BOTTOM", 0, -3)
  subtitle:SetText("|cFF888888Link an alt to deposit points to your main character.|r")

  -- Status text
  local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  statusText:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -80)
  statusText:SetWidth(380)
  statusText:SetJustifyH("LEFT")
  statusText:SetText("|cFFAAAAAA Not linked|r")
  panel.altStatusText = statusText

  -- Main name input (visible when not linked)
  local inputLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  inputLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -110)
  inputLabel:SetText("Main character name:")
  panel.altInputLabel = inputLabel

  local mainInput = CreateFrame("EditBox", nil, panel)
  mainInput:SetPoint("TOPLEFT", inputLabel, "BOTTOMLEFT", 0, -4)
  mainInput:SetWidth(200)
  mainInput:SetHeight(20)
  mainInput:SetAutoFocus(false)
  mainInput:SetFontObject(GameFontHighlight)
  mainInput:SetMaxLetters(50)
  local inputBG = CreateFrame("Frame", nil, panel)
  inputBG:SetPoint("TOPLEFT", mainInput, "TOPLEFT", -4, 4)
  inputBG:SetPoint("BOTTOMRIGHT", mainInput, "BOTTOMRIGHT", 4, -4)
  inputBG:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  inputBG:SetBackdropColor(0, 0, 0, 0.5)
  inputBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  inputBG:SetFrameLevel(mainInput:GetFrameLevel() - 1)
  panel.altMainInput = mainInput

  -- Link/Unlink button
  local linkBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  linkBtn:SetWidth(130)
  linkBtn:SetHeight(22)
  linkBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -150)
  linkBtn:SetText("Link Points")
  SkinButtonAccent(linkBtn)
  linkBtn:SetScript("OnClick", function()
    EnsureDB()
    local myKey = LVL_GetCharKey()
    if LVL_IsAltLinked(myKey) then
      -- Unlink
      local remain = LVL_Remain(LeafVE_DB.lastLinkChange[myKey], SECONDS_PER_DAY)
      if remain > 0 then
        Print("|cff00ff00[LVL]|r Cannot unlink yet. " .. LVL_FormatTime(remain) .. " remaining.")
        return
      end
      LeafVE_DB.links[myKey] = nil
      LeafVE_DB.lastLinkChange[myKey] = Now()
      Print("|cff00ff00[LVL]|r Unlinked successfully.")
      if LeafVE.UI and LeafVE.UI.panels and LeafVE.UI.panels.alt then
        LeafVE.UI:RefreshAltPanel()
      end
    else
      -- Link: check cooldown
      local remain = LVL_Remain(LeafVE_DB.lastLinkChange[myKey], SECONDS_PER_DAY)
      if remain > 0 then
        Print("|cff00ff00[LVL]|r Cannot link yet. " .. LVL_FormatTime(remain) .. " remaining.")
        return
      end
      local mainName = Trim(panel.altMainInput:GetText() or "")
      if not mainName or mainName == "" then
        Print("|cff00ff00[LVL]|r Please enter a main character name.")
        return
      end
      -- Send merge request to guild
      local myPts = 0
      local allT = LeafVE_DB.alltime and LeafVE_DB.alltime[myKey] or {L=0,G=0,S=0}
      myPts = (allT.G or 0) + (allT.S or 0)
      EnsureDB()
      if not LeafVE_DB.pendingMerge then LeafVE_DB.pendingMerge = {} end
      LeafVE_DB.pendingMerge[myKey] = { main = mainName, t = Now() }
      if InGuild() then
        SendAddonMessage("LVL", "MERGE_REQ|" .. myKey .. "|" .. mainName .. "|" .. myPts, "GUILD")
      end
      Print("|cff00ff00[LVL]|r Link request sent for " .. myKey .. " → " .. mainName .. ". Awaiting officer approval.")
    end
  end)
  panel.altLinkBtn = linkBtn

  -- Deposit Now button (visible only when linked)
  local depositBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  depositBtn:SetWidth(130)
  depositBtn:SetHeight(22)
  depositBtn:SetPoint("LEFT", linkBtn, "RIGHT", 8, 0)
  depositBtn:SetText("Deposit Now")
  SkinButtonAccent(depositBtn)
  depositBtn:SetScript("OnClick", function()
    EnsureDB()
    local myKey = LVL_GetCharKey()
    if not LVL_IsAltLinked(myKey) then
      Print("|cff00ff00[LVL]|r Not linked to a main character.")
      return
    end
    local remain = LVL_Remain(LeafVE_DB.lastDeposit[myKey], SECONDS_PER_DAY)
    if remain > 0 then
      Print("|cff00ff00[LVL]|r Deposit on cooldown. " .. LVL_FormatTime(remain) .. " remaining.")
      return
    end
    local mainKey = LVL_GetMainKey(myKey)
    local altAlltime = LeafVE_DB.alltime and LeafVE_DB.alltime[myKey] or {L=0, G=0, S=0}
    local amtG = altAlltime.G or 0
    local amtS = altAlltime.S or 0
    local amt = amtG + amtS
    if amt > 0 then
      altAlltime.G = 0
      altAlltime.S = 0
      LeafVE_DB.alltime[myKey] = altAlltime
      local mainAlltime = LeafVE_DB.alltime[mainKey] or {L=0, G=0, S=0}
      mainAlltime.G = (mainAlltime.G or 0) + amtG
      mainAlltime.S = (mainAlltime.S or 0) + amtS
      LeafVE_DB.alltime[mainKey] = mainAlltime
    end
    LeafVE_DB.lastDeposit[myKey] = Now()
    Print(string.format("|cff00ff00[LVL]|r Deposited %d points to %s. (24h cooldown started)", amt, mainKey))
    if LeafVE.UI and LeafVE.UI.panels and LeafVE.UI.panels.alt then
      LeafVE.UI:RefreshAltPanel()
    end
  end)
  panel.altDepositBtn = depositBtn

  -- Cooldown display text
  local cdText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cdText:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -185)
  cdText:SetWidth(420)
  cdText:SetJustifyH("LEFT")
  cdText:SetText("")
  panel.altCooldownText = cdText

  -- OnShow / OnHide: drive a per-second timer only while this panel is visible
  local tickElapsed = 0
  panel:SetScript("OnShow", function()
    tickElapsed = 0
    panel:SetScript("OnUpdate", function()
      tickElapsed = tickElapsed + arg1
      if tickElapsed >= 1 then
        tickElapsed = 0
        if LeafVE.UI and LeafVE.UI.panels and LeafVE.UI.panels.alt then
          LeafVE.UI:RefreshAltPanel()
        end
      end
    end)
    if LeafVE.UI and LeafVE.UI.panels and LeafVE.UI.panels.alt then
      LeafVE.UI:RefreshAltPanel()
    end
  end)
  panel:SetScript("OnHide", function()
    panel:SetScript("OnUpdate", nil)
  end)
end


  -- Block header background
  local headerBG = panel:CreateTexture(nil, "BACKGROUND")
  headerBG:SetPoint("TOP", panel, "TOP", -15, -10)
  headerBG:SetWidth(420)
  headerBG:SetHeight(50)
  headerBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  headerBG:SetVertexColor(0.15, 0.15, 0.18, 0.9)
  
  -- Top accent stripe
  local accentTop = panel:CreateTexture(nil, "BORDER")
  accentTop:SetPoint("TOPLEFT", headerBG, "TOPLEFT", 0, 0)
  accentTop:SetPoint("TOPRIGHT", headerBG, "TOPRIGHT", 0, 0)
  accentTop:SetHeight(3)
  accentTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  accentTop:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)
  
  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOP", headerBG, "TOP", 0, -10)
  h:SetText(isWeekly and "|cFFFFD700Weekly Leaderboard|r" or "|cFFFFD700Lifetime Leaderboard|r")
  
  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOP", h, "BOTTOM", 0, -3)
  subtitle:SetText(isWeekly and "|cFF888888Top performers ranked by achievement points|r" or "|cFF888888Top performers ranked by achievement points|r")
  
  local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
  scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -45)
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)
  scrollFrame:EnableMouse(true)
  scrollFrame:EnableMouseWheel(true)
  
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(500)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  
  scrollFrame:SetScript("OnMouseWheel", function()
    local current = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    local newScroll = current - (arg1 * 40)
    if newScroll < 0 then newScroll = 0 end
    if newScroll > maxScroll then newScroll = maxScroll end
    scrollFrame:SetVerticalScroll(newScroll)
  end)
  
  local scrollBar = CreateFrame("Slider", nil, panel)
  scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -45)
  scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 12)
  scrollBar:SetWidth(16)
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetMinMaxValues(0, 100)
  scrollBar:SetValue(0)
  
  local thumb = scrollBar:GetThumbTexture()
  thumb:SetWidth(16)
  thumb:SetHeight(24)
  
  scrollBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  scrollBar:SetBackdropColor(0, 0, 0, 0.3)
  scrollBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
  
  scrollBar:SetScript("OnValueChanged", function()
    local value = scrollBar:GetValue()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      scrollFrame:SetVerticalScroll((value / 100) * maxScroll)
    end
  end)
  
  scrollFrame:SetScript("OnVerticalScroll", function()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      local current = scrollFrame:GetVerticalScroll()
      scrollBar:SetValue((current / maxScroll) * 100)
    else
      scrollBar:SetValue(0)
    end
  end)
  
  panel.scrollFrame = scrollFrame
  panel.scrollChild = scrollChild
  panel.scrollBar = scrollBar
  panel.leaderEntries = {}
  panel.isWeekly = isWeekly
end

function LeafVE.UI:RefreshLeaderboard(panelName)
  if not self.panels or not self.panels[panelName] then return end

  -- Trigger an on-demand resync if not done recently
  LeafVE:SendResyncRequest()

  local panel = self.panels[panelName]
  local isWeekly = panel.isWeekly
  
  EnsureDB()
  LeafVE:UpdateGuildRosterCache()
  
  local leaders = {}
  
  -- Build a unified member set from persistentRoster (stable, includes offline)
  -- supplemented by current guildRosterCache for class/rank metadata
  local memberSet = {}
  if LeafVE_DB.persistentRoster then
    for lowerName, info in pairs(LeafVE_DB.persistentRoster) do
      memberSet[lowerName] = info
    end
  end
  -- Overlay live cache data for freshest metadata
  for lowerName, info in pairs(LeafVE.guildRosterCache) do
    memberSet[lowerName] = info
  end

  if isWeekly then
    -- Use the higher of local aggregation and synced weekly data so that stale
    -- synced broadcasts never hide points that are accurately recorded locally.
    local wk = WeekKey()
    local syncedWeek = LeafVE_DB.lboard.weekly[wk]
    local localWeek = (AggForThisWeek())
    
    for _, guildInfo in pairs(memberSet) do
      local name = guildInfo.name
      -- Feature C: linked alts never appear on the leaderboard
      if not LVL_IsAltByName(name) then
        local pts
        local localPts = localWeek[name]
        local syncedPts = syncedWeek and syncedWeek[name]
        if localPts and syncedPts then
          local localTotal = (localPts.L or 0) + (localPts.G or 0) + (localPts.S or 0)
          local syncedTotal = (syncedPts.L or 0) + (syncedPts.G or 0) + (syncedPts.S or 0)
          pts = localTotal >= syncedTotal and localPts or syncedPts
        elseif localPts then
          pts = localPts
        else
          pts = syncedPts or {L = 0, G = 0, S = 0}
        end
        local totL = pts.L or 0
        local totG = pts.G or 0
        local totS = pts.S or 0
        local total = totL + totG + totS
        table.insert(leaders, {
          name = name, total = total,
          L = totL, G = totG, S = totS,
          class = guildInfo.class or "Unknown"
        })
      end
    end
  else
    for _, guildInfo in pairs(memberSet) do
      local name = guildInfo.name
      -- Feature C: linked alts never appear on the leaderboard
      if not LVL_IsAltByName(name) then
        local pts
        local localPts = LeafVE_DB.alltime[name]
        local syncedPts = LeafVE_DB.lboard.alltime[name]
        if localPts and syncedPts then
          local localTotal = (localPts.L or 0) + (localPts.G or 0) + (localPts.S or 0)
          local syncedTotal = (syncedPts.L or 0) + (syncedPts.G or 0) + (syncedPts.S or 0)
          pts = localTotal >= syncedTotal and localPts or syncedPts
        elseif localPts then
          pts = localPts
        else
          pts = syncedPts or {L = 0, G = 0, S = 0}
        end
        local totL = pts.L or 0
        local totG = pts.G or 0
        local totS = pts.S or 0
        local total = totL + totG + totS
        table.insert(leaders, {
          name = name, total = total,
          L = totL, G = totG, S = totS,
          class = guildInfo.class or "Unknown"
        })
      end
    end
  end

  
  table.sort(leaders, function(a, b)
    if a.total == b.total then
      return Lower(a.name) < Lower(b.name)
    end
    return a.total > b.total
  end)
  
  for i = 1, table.getn(panel.leaderEntries) do
    panel.leaderEntries[i]:Hide()
  end
  
  local scrollChild = panel.scrollChild
  local yOffset = -5
  local entryHeight = 40
  
  local maxShow = math.min(20, table.getn(leaders))
  
  if table.getn(leaders) == 0 then
    if not panel.noDataText then
      local noDataText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      noDataText:SetPoint("TOP", scrollChild, "TOP", 0, -20)
      noDataText:SetText("|cFF888888No data available yet|r")
      panel.noDataText = noDataText
    end
    panel.noDataText:Show()
  else
    if panel.noDataText then
      panel.noDataText:Hide()
    end
    
    for i = 1, maxShow do
      local leader = leaders[i]
      local frame = panel.leaderEntries[i]
      
      if not frame then
        frame = CreateFrame("Frame", nil, scrollChild)
        frame:SetWidth(480)
        frame:SetHeight(entryHeight)
        
        local rankIcon = frame:CreateTexture(nil, "ARTWORK")
        rankIcon:SetWidth(32)
        rankIcon:SetHeight(32)
        rankIcon:SetPoint("LEFT", frame, "LEFT", 5, 0)
        frame.rankIcon = rankIcon
        
        local rank = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        rank:SetPoint("LEFT", frame, "LEFT", 5, 0)
        rank:SetWidth(30)
        rank:SetJustifyH("RIGHT")
        frame.rank = rank
        
        local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", rank, "RIGHT", 40, 0)
        nameText:SetWidth(150)
        nameText:SetJustifyH("LEFT")
        frame.nameText = nameText
        
        local pointsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        pointsText:SetPoint("LEFT", nameText, "RIGHT", 10, 0)
        pointsText:SetWidth(250)
        pointsText:SetJustifyH("LEFT")
        frame.pointsText = pointsText
        
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        bg:SetVertexColor(0.1, 0.1, 0.1, 0.3)
        frame.bg = bg

        frame:EnableMouse(true)
        frame:SetScript("OnEnter", function()
          this.bg:SetVertexColor(0.25, 0.25, 0.15, 0.7)
        end)
        frame:SetScript("OnLeave", function()
          this.bg:SetVertexColor(0.1, 0.1, 0.1, 0.3)
        end)
        frame:SetScript("OnMouseUp", function()
          if this.playerName then
            if LeafVE.UI.allBadgesFrame and LeafVE.UI.allBadgesFrame:IsVisible() then
              LeafVE.UI.allBadgesFrame:Hide()
            end
            if LeafVE.UI.achPopup and LeafVE.UI.achPopup:IsVisible() then
              LeafVE.UI.achPopup:Hide()
            end
            if LeafVE.UI.gearPopup and LeafVE.UI.gearPopup:IsVisible() then
              LeafVE.UI.gearPopup:Hide()
            end
            LeafVE.UI.inspectedPlayer = this.playerName
            LeafVE.UI:ShowPlayerCard(this.playerName)
          end
        end)
        
        table.insert(panel.leaderEntries, frame)
      end
      
      frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
      
      local rankColor = {1, 1, 1}
      
      if i <= 5 and PVP_RANK_ICONS[i] then
        frame.rankIcon:SetTexture(PVP_RANK_ICONS[i])
        frame.rankIcon:Show()
        frame.rank:Hide()
      else
        frame.rankIcon:Hide()
        frame.rank:Show()
        frame.rank:SetText("#"..i)
        frame.rank:SetTextColor(rankColor[1], rankColor[2], rankColor[3])
      end
      
      local classColor = CLASS_COLORS[class] or {1, 1, 1}
      frame.nameText:SetText(leader.name)
      frame.nameText:SetTextColor(classColor[1], classColor[2], classColor[3])
      frame.playerName = leader.name
      
      frame.pointsText:SetText(string.format("|cFFFFD700%d pts|r  (L:%d G:%d S:%d)", leader.total, leader.L, leader.G, leader.S))
      
      frame:Show()
      yOffset = yOffset - entryHeight - 8
    end
  end
  
  scrollChild:SetHeight(math.max(1, math.abs(yOffset) + 50))
  
  local scrollRange = panel.scrollFrame:GetVerticalScrollRange()
  if scrollRange > 0 then
    panel.scrollBar:Show()
  else
    panel.scrollBar:Hide()
  end
  
  panel.scrollFrame:SetVerticalScroll(0)
  panel.scrollBar:SetValue(0)
end

local function BuildRosterPanel(panel)
  -- Block header background
  local headerBG = panel:CreateTexture(nil, "BACKGROUND")
  headerBG:SetPoint("TOP", panel, "TOP", -15, -10)
  headerBG:SetWidth(420)
  headerBG:SetHeight(50)
  headerBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  headerBG:SetVertexColor(0.15, 0.15, 0.18, 0.9)
  
  -- Top accent stripe
  local accentTop = panel:CreateTexture(nil, "BORDER")
  accentTop:SetPoint("TOPLEFT", headerBG, "TOPLEFT", 0, 0)
  accentTop:SetPoint("TOPRIGHT", headerBG, "TOPRIGHT", 0, 0)
  accentTop:SetHeight(3)
  accentTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  accentTop:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)
  
  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOP", headerBG, "TOP", 0, -10)
  h:SetText("|cFFFFD700Guild Roster|r")
  
  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOP", h, "BOTTOM", 0, -3)
  subtitle:SetText("|cFF888888Click a member to view their achievements and badges|r")
  
  -- SEARCH BAR
  local searchLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  searchLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -75)  -- ← MOVED DOWN (was -45)
  searchLabel:SetText("Search:")
  
  local searchBox = CreateFrame("EditBox", nil, panel)
  searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 5, 0)
  searchBox:SetWidth(200)
  searchBox:SetHeight(20)
  searchBox:SetAutoFocus(false)
  searchBox:SetFontObject(GameFontHighlight)
  searchBox:SetMaxLetters(50)
  
  local searchBG = CreateFrame("Frame", nil, panel)
  searchBG:SetPoint("TOPLEFT", searchBox, "TOPLEFT", -5, 5)
  searchBG:SetPoint("BOTTOMRIGHT", searchBox, "BOTTOMRIGHT", 5, -5)
  searchBG:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  searchBG:SetBackdropColor(0, 0, 0, 0.5)
  searchBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  searchBG:SetFrameLevel(searchBox:GetFrameLevel() - 1)
  
  searchBox:SetScript("OnEscapePressed", function() 
    this:ClearFocus() 
  end)
  
  searchBox:SetScript("OnTextChanged", function()
    if LeafVE.UI and LeafVE.UI.RefreshRoster then
      LeafVE.UI:RefreshRoster()
    end
  end)
  
  panel.searchBox = searchBox
  
  -- Clear button
  local clearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  clearBtn:SetPoint("LEFT", searchBox, "RIGHT", 5, 0)
  clearBtn:SetWidth(50)
  clearBtn:SetHeight(20)
  clearBtn:SetText("Clear")
  SkinButtonAccent(clearBtn)
  
  clearBtn:SetScript("OnClick", function()
    panel.searchBox:SetText("")
    panel.searchBox:ClearFocus()
    if LeafVE.UI and LeafVE.UI.RefreshRoster then
      LeafVE.UI:RefreshRoster()
    end
  end)
  
  -- SCROLL FRAME (moved down for search bar)
  local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
  scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -105)  -- ← MOVED DOWN (was -75)
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)
  scrollFrame:EnableMouse(true)
  scrollFrame:EnableMouseWheel(true)
  
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(500)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  
  scrollFrame:SetScript("OnMouseWheel", function()
    local current = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    local newScroll = current - (arg1 * 40)
    if newScroll < 0 then newScroll = 0 end
    if newScroll > maxScroll then newScroll = maxScroll end
    scrollFrame:SetVerticalScroll(newScroll)
  end)
  
  local scrollBar = CreateFrame("Slider", nil, panel)
  scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -75)
  scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 12)
  scrollBar:SetWidth(16)
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetMinMaxValues(0, 100)
  scrollBar:SetValue(0)
  
  local thumb = scrollBar:GetThumbTexture()
  thumb:SetWidth(16)
  thumb:SetHeight(24)
  
  scrollBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  scrollBar:SetBackdropColor(0, 0, 0, 0.3)
  scrollBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
  
  scrollBar:SetScript("OnValueChanged", function()
    local value = scrollBar:GetValue()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      scrollFrame:SetVerticalScroll((value / 100) * maxScroll)
    end
  end)
  
  scrollFrame:SetScript("OnVerticalScroll", function()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      local current = scrollFrame:GetVerticalScroll()
      scrollBar:SetValue((current / maxScroll) * 100)
    else
      scrollBar:SetValue(0)
    end
  end)
  
  panel.scrollFrame = scrollFrame
  panel.scrollChild = scrollChild
  panel.scrollBar = scrollBar
  panel.rosterButtons = {}
end

function LeafVE.UI:RefreshRoster()
  if not self.panels or not self.panels.roster then return end
  
  EnsureDB()
  LeafVE:UpdateGuildRosterCache()
  
  -- GET SEARCH TEXT
  local searchText = ""
  if self.panels.roster.searchBox then
    searchText = Lower(Trim(self.panels.roster.searchBox:GetText() or ""))
  end
  
  local members = {}
  for _, info in pairs(LeafVE.guildRosterCache) do
    -- FILTER BY SEARCH TEXT
    if searchText == "" or string.find(Lower(info.name), searchText, 1, true) then
      table.insert(members, info)
    end
  end
  
  table.sort(members, function(a, b)
    if a.online ~= b.online then
      return a.online
    end
    return Lower(a.name) < Lower(b.name)
  end)
  
  for i = 1, table.getn(self.panels.roster.rosterButtons) do
    self.panels.roster.rosterButtons[i]:Hide()
  end
  
  local scrollChild = self.panels.roster.scrollChild
  local yOffset = -5
  local buttonHeight = 34
  
  for i = 1, table.getn(members) do
    local member = members[i]
    local btn = self.panels.roster.rosterButtons[i]
    
    if not btn then
      btn = CreateFrame("Button", nil, scrollChild)
      btn:SetWidth(480)
      btn:SetHeight(buttonHeight)
      
      local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      text:SetPoint("LEFT", btn, "LEFT", 5, 0)
      text:SetWidth(475)
      text:SetJustifyH("LEFT")
      btn.text = text
      
      local bg = btn:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints(btn)
      bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
      bg:SetVertexColor(0.1, 0.1, 0.1, 0.5)
      bg:SetAlpha(0)
      btn.bg = bg
      
      btn:SetScript("OnEnter", function() this.bg:SetAlpha(0.8) end)
      btn:SetScript("OnLeave", function() this.bg:SetAlpha(0) end)
      
      table.insert(self.panels.roster.rosterButtons, btn)
    end
    
    btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
    
    local class = string.upper(member.class or "UNKNOWN")
    local classColor = CLASS_COLORS[class] or {1, 1, 1}
    
    local onlineIndicator = member.online and "|cFF00FF00●|r " or "|cFF888888●|r "
    
    btn.text:SetText(string.format("%s%s - Lvl %s %s", onlineIndicator, member.name, tostring(member.level), member.rank))
    btn.text:SetTextColor(classColor[1], classColor[2], classColor[3])
    
btn.playerName = member.name
btn:SetScript("OnClick", function()
  -- Close badge collection popup when switching players
  if LeafVE.UI.allBadgesFrame and LeafVE.UI.allBadgesFrame:IsVisible() then
    LeafVE.UI.allBadgesFrame:Hide()
  end
  
  -- Close achievement popup when switching players
  if LeafVE.UI.achPopup and LeafVE.UI.achPopup:IsVisible() then
    LeafVE.UI.achPopup:Hide()
  end
  
  -- Close gear popup when switching players
  if LeafVE.UI.gearPopup and LeafVE.UI.gearPopup:IsVisible() then
    LeafVE.UI.gearPopup:Hide()
  end
  
  if LeafVE.UI.cardCurrentPlayer ~= this.playerName then
    LeafVE.UI.inspectedPlayer = this.playerName
    LeafVE.UI:ShowPlayerCard(this.playerName)
  end
end)
    
    btn:Show()
    yOffset = yOffset - buttonHeight - 4
  end
  
  scrollChild:SetHeight(math.max(1, math.abs(yOffset) + 50))
  
  local scrollRange = self.panels.roster.scrollFrame:GetVerticalScrollRange()
  if scrollRange > 0 then
    self.panels.roster.scrollBar:Show()
  else
    self.panels.roster.scrollBar:Hide()
  end
  
  self.panels.roster.scrollFrame:SetVerticalScroll(0)
  self.panels.roster.scrollBar:SetValue(0)
end

local function BuildHistoryPanel(panel)
  -- Block header background
  local headerBG = panel:CreateTexture(nil, "BACKGROUND")
  headerBG:SetPoint("TOP", panel, "TOP", -15, -10)
  headerBG:SetWidth(420)
  headerBG:SetHeight(50)
  headerBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  headerBG:SetVertexColor(0.15, 0.15, 0.18, 0.9)
  
  -- Top accent stripe
  local accentTop = panel:CreateTexture(nil, "BORDER")
  accentTop:SetPoint("TOPLEFT", headerBG, "TOPLEFT", 0, 0)
  accentTop:SetPoint("TOPRIGHT", headerBG, "TOPRIGHT", 0, 0)
  accentTop:SetHeight(3)
  accentTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  accentTop:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)
  
  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOP", headerBG, "TOP", 0, -10)
  h:SetText("|cFFFFD700Point History|r")
  
  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOP", h, "BOTTOM", 0, -3)
  subtitle:SetText("|cFF888888Complete log of all your point transactions|r")
  
local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
  scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -75)  -- ← CHANGED from -45
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)
  scrollFrame:EnableMouse(true)
  scrollFrame:EnableMouseWheel(true)
  
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(500)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  
  scrollFrame:SetScript("OnMouseWheel", function()
    local current = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    local newScroll = current - (arg1 * 40)
    if newScroll < 0 then newScroll = 0 end
    if newScroll > maxScroll then newScroll = maxScroll end
    scrollFrame:SetVerticalScroll(newScroll)
  end)
  
  local scrollBar = CreateFrame("Slider", nil, panel)
  scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -75)  -- ← CHANGED from -45
  scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 12)
  scrollBar:SetWidth(16)
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetMinMaxValues(0, 100)
  scrollBar:SetValue(0)
  
  local thumb = scrollBar:GetThumbTexture()
  thumb:SetWidth(16)
  thumb:SetHeight(24)
  
  scrollBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  scrollBar:SetBackdropColor(0, 0, 0, 0.3)
  scrollBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
  
  scrollBar:SetScript("OnValueChanged", function()
    local value = scrollBar:GetValue()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      scrollFrame:SetVerticalScroll((value / 100) * maxScroll)
    end
  end)
  
  scrollFrame:SetScript("OnVerticalScroll", function()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      local current = scrollFrame:GetVerticalScroll()
      scrollBar:SetValue((current / maxScroll) * 100)
    else
      scrollBar:SetValue(0)
    end
  end)
  
  panel.scrollFrame = scrollFrame
  panel.scrollChild = scrollChild
  panel.scrollBar = scrollBar
  panel.historyEntries = {}
end

local function BuildBadgesPanel(panel)
  -- Block header background
  local headerBG = panel:CreateTexture(nil, "BACKGROUND")
  headerBG:SetPoint("TOP", panel, "TOP", -15, -10)
  headerBG:SetWidth(420)
  headerBG:SetHeight(50)
  headerBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  headerBG:SetVertexColor(0.15, 0.15, 0.18, 0.9)
  
  -- Top accent stripe
  local accentTop = panel:CreateTexture(nil, "BORDER")
  accentTop:SetPoint("TOPLEFT", headerBG, "TOPLEFT", 0, 0)
  accentTop:SetPoint("TOPRIGHT", headerBG, "TOPRIGHT", 0, 0)
  accentTop:SetHeight(3)
  accentTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  accentTop:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)
  
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", headerBG, "TOP", 0, -10)
  title:SetText("|cFFFFD700Milestone Badges|r")
  
  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOP", title, "BOTTOM", 0, -3)
  subtitle:SetText("|cFF888888Earn badges by completing milestones and challenges|r")
  
  -- Scroll frame (REBUILT)
  local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
  scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -70)
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)
  scrollFrame:EnableMouse(true)
  scrollFrame:EnableMouseWheel(true)
  panel.scrollFrame = scrollFrame
  
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(400)
  scrollChild:SetHeight(1500)  -- Start with tall height
  scrollFrame:SetScrollChild(scrollChild)
  panel.scrollChild = scrollChild
  
  -- Mouse wheel scrolling with proper bounds
  scrollFrame:SetScript("OnMouseWheel", function()
    local current = this:GetVerticalScroll()
    local maxScroll = this:GetVerticalScrollRange()
    local newScroll = current - (arg1 * 80)
    
    -- CLAMP to valid range
    if newScroll < 0 then 
      newScroll = 0 
    elseif newScroll > maxScroll then 
      newScroll = maxScroll 
    end
    
    this:SetVerticalScroll(newScroll)
    
    -- Update scrollbar
    if panel.scrollBar and maxScroll > 0 then
      panel.scrollBar:SetValue((newScroll / maxScroll) * 100)
    end
  end)
  
  -- Scroll bar
  local scrollBar = CreateFrame("Slider", nil, panel)
  scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -70)
  scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 12)
  scrollBar:SetWidth(16)
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetMinMaxValues(0, 100)
  scrollBar:SetValue(0)
  panel.scrollBar = scrollBar
  
  local thumb = scrollBar:GetThumbTexture()
  thumb:SetWidth(16)
  thumb:SetHeight(24)
  
  scrollBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  scrollBar:SetBackdropColor(0, 0, 0, 0.3)
  scrollBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
  
  scrollBar:SetScript("OnValueChanged", function()
    local value = this:GetValue()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      local targetScroll = (value / 100) * maxScroll
      scrollFrame:SetVerticalScroll(targetScroll)
    end
  end)
  
  panel.badgeFrames = {}
end

local function BuildAchievementsPanel(panel)
  -- Block header background
  local headerBG = panel:CreateTexture(nil, "BACKGROUND")
  headerBG:SetPoint("TOP", panel, "TOP", -15, -10)
  headerBG:SetWidth(420)
  headerBG:SetHeight(50)
  headerBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  headerBG:SetVertexColor(0.15, 0.15, 0.18, 0.9)
  
  -- Top accent stripe
  local accentTop = panel:CreateTexture(nil, "BORDER")
  accentTop:SetPoint("TOPLEFT", headerBG, "TOPLEFT", 0, 0)
  accentTop:SetPoint("TOPRIGHT", headerBG, "TOPRIGHT", 0, 0)
  accentTop:SetHeight(3)
  accentTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  accentTop:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)
  
  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOP", headerBG, "TOP", 0, -10)
  h:SetText("|cFFFFD700Achievements|r")
  
  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOP", h, "BOTTOM", 0, -3)
  subtitle:SetText("|cFF888888Complete challenges to earn achievement points and titles|r")
  
  local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
  scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -45)
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)
  scrollFrame:EnableMouse(true)
  scrollFrame:EnableMouseWheel(true)
  
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(500)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  
  scrollFrame:SetScript("OnMouseWheel", function()
    local current = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    local newScroll = current - (arg1 * 40)
    if newScroll < 0 then newScroll = 0 end
    if newScroll > maxScroll then newScroll = maxScroll end
    scrollFrame:SetVerticalScroll(newScroll)
  end)
  
  local scrollBar = CreateFrame("Slider", nil, panel)
  scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -45)
  scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 12)
  scrollBar:SetWidth(16)
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetMinMaxValues(0, 100)
  scrollBar:SetValue(0)
  
  local thumb = scrollBar:GetThumbTexture()
  thumb:SetWidth(16)
  thumb:SetHeight(24)
  
  scrollBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  scrollBar:SetBackdropColor(0, 0, 0, 0.3)
  scrollBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
  
  scrollBar:SetScript("OnValueChanged", function()
    local value = scrollBar:GetValue()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      scrollFrame:SetVerticalScroll((value / 100) * maxScroll)
    end
  end)
  
  scrollFrame:SetScript("OnVerticalScroll", function()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      local current = scrollFrame:GetVerticalScroll()
      scrollBar:SetValue((current / maxScroll) * 100)
    else
      scrollBar:SetValue(0)
    end
  end)
  
  panel.scrollFrame = scrollFrame
  panel.scrollChild = scrollChild
  panel.scrollBar = scrollBar
  panel.achEntries = {}
end

local function MakeToggleButton(parent, label, yPos, getOpt, setOpt)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetWidth(80)
  btn:SetHeight(22)
  btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 170, yPos)
  SkinButtonAccent(btn)

  local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lbl:SetPoint("LEFT", parent, "LEFT", 12, 0)
  lbl:SetPoint("RIGHT", btn, "LEFT", -8, 0)
  lbl:SetPoint("TOP", btn, "TOP", 0, 0)
  lbl:SetHeight(22)
  lbl:SetJustifyH("LEFT")
  lbl:SetText(label)

  local function Sync()
    if getOpt() then
      btn:SetText("|cFF00FF00ON|r")
    else
      btn:SetText("|cFFFF4444OFF|r")
    end
  end
  Sync()

  btn:SetScript("OnClick", function()
    setOpt(not getOpt())
    Sync()
  end)

  return btn, lbl
end

local function BuildOptionsPanel(panel)
  local headerBG = panel:CreateTexture(nil, "BACKGROUND")
  headerBG:SetPoint("TOP", panel, "TOP", -15, -10)
  headerBG:SetWidth(420)
  headerBG:SetHeight(50)
  headerBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  headerBG:SetVertexColor(0.15, 0.15, 0.18, 0.9)

  local accentTop = panel:CreateTexture(nil, "BORDER")
  accentTop:SetPoint("TOPLEFT", headerBG, "TOPLEFT", 0, 0)
  accentTop:SetPoint("TOPRIGHT", headerBG, "TOPRIGHT", 0, 0)
  accentTop:SetHeight(3)
  accentTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  accentTop:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)

  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOP", headerBG, "TOP", 0, -10)
  h:SetText("|cFFFFD700Options|r")

  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOP", h, "BOTTOM", 0, -3)
  subtitle:SetText("|cFF888888Configure addon behaviour|r")

  local yBase = -80
  local gap = 36

  -- Section: Notifications
  local notifSection = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  notifSection:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, yBase)
  notifSection:SetText("|cFF2DD35CNotifications|r")
  yBase = yBase - 28

  local subFrame = CreateFrame("Frame", nil, panel)

  MakeToggleButton(subFrame, "All Notifications (master switch)",
    yBase,
    function() return LeafVE_DB.options.enableNotifications ~= false end,
    function(v) LeafVE_DB.options.enableNotifications = v end)
  yBase = yBase - gap

  MakeToggleButton(subFrame, "Leaf Point Pop-ups",
    yBase,
    function() return LeafVE_DB.options.enablePointNotifications ~= false end,
    function(v) LeafVE_DB.options.enablePointNotifications = v end)
  yBase = yBase - gap

  MakeToggleButton(subFrame, "Badge & Achievement Pop-ups",
    yBase,
    function() return LeafVE_DB.options.enableBadgeNotifications ~= false end,
    function(v) LeafVE_DB.options.enableBadgeNotifications = v end)
  yBase = yBase - gap

  MakeToggleButton(subFrame, "Notification Sound",
    yBase,
    function() return LeafVE_DB.options.notificationSound ~= false end,
    function(v) LeafVE_DB.options.notificationSound = v end)
  yBase = yBase - gap + 8

  -- Divider
  local div1 = panel:CreateTexture(nil, "ARTWORK")
  div1:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, yBase)
  div1:SetWidth(430)
  div1:SetHeight(1)
  div1:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  div1:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.4)
  yBase = yBase - 18

  -- Section: Roster
  local rosterSection = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rosterSection:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, yBase)
  rosterSection:SetText("|cFF2DD35CRoster|r")
  yBase = yBase - 28

  MakeToggleButton(subFrame, "Show Offline Members",
    yBase,
    function() return LeafVE_DB.options.showOfflineMembers ~= false end,
    function(v)
      LeafVE_DB.options.showOfflineMembers = v
      LeafVE.guildRosterCacheTime = 0
      if LeafVE.UI and LeafVE.UI.RefreshRoster then LeafVE.UI:RefreshRoster() end
    end)
  yBase = yBase - gap + 8

  -- Divider
  local div2 = panel:CreateTexture(nil, "ARTWORK")
  div2:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, yBase)
  div2:SetWidth(430)
  div2:SetHeight(1)
  div2:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  div2:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.4)
  yBase = yBase - 18

  -- Section: UI Size shortcuts
  local uiSection = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  uiSection:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, yBase)
  uiSection:SetText("|cFF2DD35CUI Size|r")
  yBase = yBase - 28

  local uiHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  uiHint:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, yBase)
  uiHint:SetText("|cFF888888Use /lve bigger|smaller|wider|narrower or drag the corner grip|r")
  uiHint:SetWidth(430)
  uiHint:SetJustifyH("LEFT")

  subFrame:SetAllPoints(panel)
  panel.optSubFrame = subFrame
end

function LeafVE.UI:RefreshOptions()
  if not self.panels or not self.panels.options then return end
  -- Options are driven by toggle buttons that read/write DB directly; nothing extra needed.
end

-------------------------------------------------
-- ADMIN TAB PANEL (Anbu / Sannin / Hokage only)
-------------------------------------------------
local function MakeNumberStepper(parent, label, yPos, getVal, setVal, minVal, maxVal)
  local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yPos)
  lbl:SetText(label)

  local valText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  valText:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, yPos)
  valText:SetWidth(60)
  valText:SetJustifyH("CENTER")

  local function Sync()
    local v = getVal()
    if v == 0 then
      valText:SetText("|cFF"..RGBToHex(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3]).."unlimited|r")
    else
      valText:SetText("|cFF"..RGBToHex(THEME.gold[1], THEME.gold[2], THEME.gold[3])..tostring(v).."|r")
    end
  end
  Sync()

  local btnMinus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btnMinus:SetWidth(26)
  btnMinus:SetHeight(20)
  btnMinus:SetPoint("TOPLEFT", parent, "TOPLEFT", 240, yPos + 2)
  btnMinus:SetText("-")
  SkinButtonAccent(btnMinus)
  btnMinus:SetScript("OnClick", function()
    local v = getVal()
    v = v - 1
    if v < minVal then v = minVal end
    setVal(v)
    Sync()
  end)

  local btnPlus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btnPlus:SetWidth(26)
  btnPlus:SetHeight(20)
  btnPlus:SetPoint("TOPLEFT", parent, "TOPLEFT", 315, yPos + 2)
  btnPlus:SetText("+")
  SkinButtonAccent(btnPlus)
  btnPlus:SetScript("OnClick", function()
    local v = getVal()
    v = v + 1
    if maxVal and v > maxVal then v = maxVal end
    setVal(v)
    Sync()
  end)

  -- Return Sync so callers can force a redraw (e.g. after Reset)
  return lbl, valText, Sync
end

local function BuildAdminPanel(panel)
  local headerBG = panel:CreateTexture(nil, "BACKGROUND")
  headerBG:SetPoint("TOP", panel, "TOP", -15, -10)
  headerBG:SetWidth(420)
  headerBG:SetHeight(50)
  headerBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  headerBG:SetVertexColor(0.15, 0.15, 0.18, 0.9)

  local accentTop = panel:CreateTexture(nil, "BORDER")
  accentTop:SetPoint("TOPLEFT", headerBG, "TOPLEFT", 0, 0)
  accentTop:SetPoint("TOPRIGHT", headerBG, "TOPRIGHT", 0, 0)
  accentTop:SetHeight(3)
  accentTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  accentTop:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)

  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOP", headerBG, "TOP", 0, -10)
  h:SetText("|cFFFFD700Admin Settings|r")

  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOP", h, "BOTTOM", 0, -3)
  subtitle:SetText("|cFF888888Anbu / Sannin / Hokage only|r")

  local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
  scrollFrame:SetPoint("TOPLEFT",     panel, "TOPLEFT",     0, -68)
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 10)
  scrollFrame:EnableMouseWheel(true)

  local scrollBar  -- forward-declared so the OnMouseWheel closure below can reference it
  scrollFrame:SetScript("OnMouseWheel", function()
    local cur = scrollFrame:GetVerticalScroll()
    local max = scrollFrame:GetVerticalScrollRange()
    local new = cur - (arg1 * 30)
    if new < 0 then new = 0 end
    if new > max then new = max end
    scrollFrame:SetVerticalScroll(new)
    scrollBar:SetValue(new)
  end)

  scrollBar = CreateFrame("Slider", nil, panel)
  scrollBar:SetPoint("TOPRIGHT",    panel, "TOPRIGHT",    -4, -68)
  scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 10)
  scrollBar:SetWidth(14)
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetMinMaxValues(0, 1)
  scrollBar:SetValue(0)
  scrollBar:SetScript("OnValueChanged", function()
    scrollFrame:SetVerticalScroll(this:GetValue())
  end)
  local function UpdateAdminScroll()
    local max = scrollFrame:GetVerticalScrollRange()
    scrollBar:SetMinMaxValues(0, max > 0 and max or 1)
  end

  local subFrame = CreateFrame("Frame", nil, scrollFrame)
  subFrame:SetWidth(440)
  subFrame:SetHeight(1)
  scrollFrame:SetScrollChild(subFrame)

  local yBase = -10
  local gap = 34

  -- Section: Current Rules (read-only display)
  local rulesSection = subFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rulesSection:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 12, yBase)
  rulesSection:SetText("|cFF2DD35CCurrent Rules (Hard-Coded)|r")
  yBase = yBase - 24

  local ruleLines = {
    "• Daily Login: 20 LP",
    "• Quest Turn-In: 10 LP (requires guildie in group, no daily cap)",
    "• Dungeon Boss: 10 LP  |  Raid Boss: 25 LP",
    "• Dungeon Complete: 10 LP  |  Raid Complete: 25 LP",
    "• Group Time: 10 LP per guildie every 20 min",
    "• Shoutout: 10 LP (2 per day)",
    "• Daily Total LP Cap: 700",
  }
  for _, ruleText in ipairs(ruleLines) do
    local ruleFS = subFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ruleFS:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 18, yBase)
    ruleFS:SetWidth(420)
    ruleFS:SetJustifyH("LEFT")
    ruleFS:SetText("|cFFCCCCCC"..ruleText.."|r")
    yBase = yBase - 18
  end
  yBase = yBase - 8

  -- Divider
  local divAnnounce = subFrame:CreateTexture(nil, "ARTWORK")
  divAnnounce:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 12, yBase)
  divAnnounce:SetWidth(430)
  divAnnounce:SetHeight(1)
  divAnnounce:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  divAnnounce:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.4)
  yBase = yBase - 18

  -- Section: Announce Weekly Standings
  local announceSection = subFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  announceSection:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 12, yBase)
  announceSection:SetText("|cFF2DD35CAnnounce Weekly Standings|r")
  yBase = yBase - 28

  local previewBox = subFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  previewBox:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 18, yBase)
  previewBox:SetWidth(400)
  previewBox:SetJustifyH("LEFT")
  previewBox:SetText("|cFF888888Click Refresh Preview to load standings.|r")
  yBase = yBase - 90

  local function BuildStandingsLines()
    -- Use the same data sources as the My Stats "Current Weekly Standings" section:
    -- merge local daily aggregation with synced weekly leaderboard data and pick
    -- the higher total for each player so the announcement is always accurate.
    local wk = WeekKey()
    local localWeek = AggForThisWeek()
    local syncedWeek = LeafVE_DB.lboard.weekly[wk]
    local memberSet = {}
    if LeafVE_DB.persistentRoster then
      for _, info in pairs(LeafVE_DB.persistentRoster) do
        memberSet[Lower(info.name)] = info
      end
    end
    for lowerName, info in pairs(LeafVE.guildRosterCache) do
      memberSet[lowerName] = info
    end
    local sorted = {}
    for _, guildInfo in pairs(memberSet) do
      local name = guildInfo.name
      local localPts = localWeek[name]
      local syncedPts = syncedWeek and syncedWeek[name]
      local pts
      if localPts and syncedPts then
        local lTotal = (localPts.L or 0) + (localPts.G or 0) + (localPts.S or 0)
        local sTotal = (syncedPts.L or 0) + (syncedPts.G or 0) + (syncedPts.S or 0)
        pts = lTotal >= sTotal and localPts or syncedPts
      elseif localPts then
        pts = localPts
      else
        pts = syncedPts or {L = 0, G = 0, S = 0}
      end
      local total = (pts.L or 0) + (pts.G or 0) + (pts.S or 0)
      if total > 0 then
        table.insert(sorted, {name = name, total = total})
      end
    end
    table.sort(sorted, function(a, b)
      if a.total == b.total then return Lower(a.name) < Lower(b.name) end
      return a.total > b.total
    end)
    local rewards = {SEASON_REWARD_1, SEASON_REWARD_2, SEASON_REWARD_3, SEASON_REWARD_4, SEASON_REWARD_5}
    local lines = {"|cFF2DD35CLeaf Village Weekly Standings|r"}
    local ordinals = {"1st", "2nd", "3rd", "4th", "5th"}
    for i = 1, 5 do
      local entry = sorted[i]
      if entry then
        local reward = rewards[i] or 0
        table.insert(lines, string.format("%s: %s - %d LP (%dg reward)", ordinals[i], entry.name, entry.total, reward))
      else
        table.insert(lines, string.format("%s: ---", ordinals[i]))
      end
    end
    return lines
  end

  local refreshPreviewBtn = CreateFrame("Button", nil, subFrame, "UIPanelButtonTemplate")
  refreshPreviewBtn:SetWidth(130)
  refreshPreviewBtn:SetHeight(22)
  refreshPreviewBtn:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 18, yBase)
  refreshPreviewBtn:SetText("Refresh Preview")
  SkinButtonAccent(refreshPreviewBtn)
  refreshPreviewBtn:SetScript("OnClick", function()
    local lines = BuildStandingsLines()
    previewBox:SetText(table.concat(lines, "\n"))
  end)

  local announceBtn = CreateFrame("Button", nil, subFrame, "UIPanelButtonTemplate")
  announceBtn:SetWidth(140)
  announceBtn:SetHeight(22)
  announceBtn:SetPoint("LEFT", refreshPreviewBtn, "RIGHT", 8, 0)
  announceBtn:SetText("Announce to Guild")
  SkinButtonAccent(announceBtn)
  announceBtn:SetScript("OnClick", function()
    local lines = BuildStandingsLines()
    if InGuild() then
      for _, line in ipairs(lines) do
        SendChatMessage(line, "GUILD")
      end
      Print("Weekly standings announced to guild!")
    else
      Print("You are not in a guild.")
    end
  end)
  yBase = yBase - 44

  -- Check Addon Versions button
  local checkVerBtn = CreateFrame("Button", nil, subFrame, "UIPanelButtonTemplate")
  checkVerBtn:SetWidth(160)
  checkVerBtn:SetHeight(22)
  checkVerBtn:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 12, yBase - 10)
  checkVerBtn:SetText("Check Addon Versions")
  SkinButtonAccent(checkVerBtn)
  checkVerBtn:SetScript("OnClick", function()
    -- Reset response table and send request
    LeafVE.versionResponses = {}
    LeafVE.shownVersionNag = nil
    LeafVE.warnedOldVersion = {}
    LeafVE.adminVersionCheckActive = true
    LeafVE.versionCheckTime = Now()
    SendAddonMessage("LeafVE", "VERSIONREQ", "GUILD")
    -- Clear the admin flag after responses have been collected so passive
    -- VERSIONRSP messages that arrive later do not trigger chat spam.
    -- 10 seconds gives guild members enough time to respond to the request.
    C_Timer_After(10, function()
      LeafVE.adminVersionCheckActive = false
    end)
    -- Open the version results popup after a short delay
    C_Timer_After(5, function()
      LeafVE:ShowVersionResults()
    end)
    Print("Version check sent to guild. Results will appear in 5 seconds.")
  end)
  yBase = yBase - 44

  -- Divider
  local div3 = subFrame:CreateTexture(nil, "ARTWORK")
  div3:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 12, yBase)
  div3:SetWidth(430)
  div3:SetHeight(1)
  div3:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  div3:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.4)
  yBase = yBase - 18
  local testSection = subFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  testSection:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 12, yBase)
  testSection:SetText("|cFF2DD35CTesting|r")
  yBase = yBase - 28

  local randBadgeBtn = CreateFrame("Button", nil, subFrame, "UIPanelButtonTemplate")
  randBadgeBtn:SetWidth(160)
  randBadgeBtn:SetHeight(22)
  randBadgeBtn:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 12, yBase)
  randBadgeBtn:SetText("Award Random Badge")
  SkinButtonAccent(randBadgeBtn)
  randBadgeBtn:SetScript("OnClick", function()
    local me = ShortName(UnitName("player"))
    LeafVE:AwardRandomBadge(me)
  end)

  local resetBadgesBtn = CreateFrame("Button", nil, subFrame, "UIPanelButtonTemplate")
  resetBadgesBtn:SetWidth(130)
  resetBadgesBtn:SetHeight(22)
  resetBadgesBtn:SetPoint("LEFT", randBadgeBtn, "RIGHT", 8, 0)
  resetBadgesBtn:SetText("Reset My Badges")
  SkinButtonAccent(resetBadgesBtn)
  resetBadgesBtn:SetScript("OnClick", function()
    local me = ShortName(UnitName("player"))
    LeafVE:ResetBadges(me)
  end)

  local resetAllBadgesBtn = CreateFrame("Button", nil, subFrame, "UIPanelButtonTemplate")
  resetAllBadgesBtn:SetWidth(130)
  resetAllBadgesBtn:SetHeight(22)
  resetAllBadgesBtn:SetPoint("LEFT", resetBadgesBtn, "RIGHT", 8, 0)
  resetAllBadgesBtn:SetText("Reset ALL Badges")
  SkinButtonAccent(resetAllBadgesBtn)
  resetAllBadgesBtn:SetScript("OnClick", function()
    LeafVE:ResetAllBadges()
  end)

  yBase = yBase - 38

  -- Divider above Danger Zone
  local divDanger = subFrame:CreateTexture(nil, "ARTWORK")
  divDanger:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 12, yBase)
  divDanger:SetWidth(430)
  divDanger:SetHeight(1)
  divDanger:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  divDanger:SetVertexColor(0.8, 0.1, 0.1, 0.6)
  yBase = yBase - 18

  -- Section: Danger Zone
  local dangerSection = subFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dangerSection:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 12, yBase)
  dangerSection:SetText("|cFFFF4444Danger Zone|r")
  yBase = yBase - 28

  -- "Reset All Leaf Points" button
  local resetLeafBtn = CreateFrame("Button", nil, subFrame, "UIPanelButtonTemplate")
  resetLeafBtn:SetWidth(200)
  resetLeafBtn:SetHeight(22)
  resetLeafBtn:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 12, yBase)
  resetLeafBtn:SetText("|cFFFF4444Reset All Leaf Points|r")
  SkinButtonAccent(resetLeafBtn)
  resetLeafBtn:SetScript("OnClick", function()
    -- Confirmation popup
    if not LeafVE._confirmResetLeafFrame then
      local cf = CreateFrame("Frame", "LeafVE_ConfirmResetLeaf", UIParent)
      cf:SetWidth(380)
      cf:SetHeight(120)
      cf:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
      cf:SetFrameStrata("DIALOG")
      cf:EnableMouse(true)
      cf:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
      })
      cf:SetBackdropColor(0.1, 0.02, 0.02, 0.97)
      cf:SetBackdropBorderColor(0.8, 0.1, 0.1, 1)

      local warningText = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      warningText:SetPoint("TOP", cf, "TOP", 0, -16)
      warningText:SetWidth(340)
      warningText:SetJustifyH("CENTER")
      warningText:SetText("|cFFFF4444This will wipe ALL Leaf Points\n(daily/weekly/season/all-time) for the\nentire guild and clear everyone's saved data.|r")

      local confirmBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
      confirmBtn:SetWidth(120)
      confirmBtn:SetHeight(22)
      confirmBtn:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 20, 14)
      confirmBtn:SetText("Confirm Reset")
      confirmBtn:SetScript("OnClick", function()
        local ts = time()
        EnsureDB()
        LeafVE_GlobalDB.lastAdminResetTS = ts
        -- Use LVL_AdminResetAll for the new guild-wide wipe (Feature E)
        LVL_AdminResetAll()
        if InGuild() then
          SendAddonMessage("LeafVE", "LVE_ADMIN_RESET_LEAF_ALL:"..ts, "GUILD")
          SendAddonMessage("LeafVE", "LVE_RESET_LBOARD_ZERO:"..ts, "GUILD")
          LeafVE:BroadcastLeaderboardData()
        end
        Print("|cFFFF4444Broadcast: All Leaf Points reset for all guild members.|r")
        cf:Hide()
      end)

      local cancelBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
      cancelBtn:SetWidth(80)
      cancelBtn:SetHeight(22)
      cancelBtn:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -20, 14)
      cancelBtn:SetText("Cancel")
      cancelBtn:SetScript("OnClick", function() cf:Hide() end)

      cf:Hide()
      LeafVE._confirmResetLeafFrame = cf
    end
    LeafVE._confirmResetLeafFrame:Show()
  end)
  yBase = yBase - 34

  -- "Reset ALL Achievement Leaderboard Data" button
  local resetAchLbBtn = CreateFrame("Button", nil, subFrame, "UIPanelButtonTemplate")
  resetAchLbBtn:SetWidth(280)
  resetAchLbBtn:SetHeight(22)
  resetAchLbBtn:SetPoint("TOPLEFT", subFrame, "TOPLEFT", 12, yBase)
  resetAchLbBtn:SetText("|cFFFF4444Reset ALL Achievement Leaderboard Data|r")
  SkinButtonAccent(resetAchLbBtn)
  resetAchLbBtn:SetScript("OnClick", function()
    -- Confirmation popup
    if not LeafVE._confirmResetAchFrame then
      local cf = CreateFrame("Frame", "LeafVE_ConfirmResetAch", UIParent)
      cf:SetWidth(380)
      cf:SetHeight(120)
      cf:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
      cf:SetFrameStrata("DIALOG")
      cf:EnableMouse(true)
      cf:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
      })
      cf:SetBackdropColor(0.1, 0.02, 0.02, 0.97)
      cf:SetBackdropBorderColor(0.8, 0.1, 0.1, 1)

      local warningText = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      warningText:SetPoint("TOP", cf, "TOP", 0, -16)
      warningText:SetWidth(340)
      warningText:SetJustifyH("CENTER")
      warningText:SetText("|cFFFF4444This will wipe the achievement leaderboard\ncache for all guild members.\nIndividual completion flags are NOT deleted.|r")

      local confirmBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
      confirmBtn:SetWidth(120)
      confirmBtn:SetHeight(22)
      confirmBtn:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 20, 14)
      confirmBtn:SetText("Confirm Reset")
      confirmBtn:SetScript("OnClick", function()
        LeafVE:HardResetAchievementLeaderboard_Local()
        if InGuild() then
          SendAddonMessage("LeafVE", "LVE_ADMIN_RESET_ACHIEVE_ALL:"..time(), "GUILD")
          LeafVE:BroadcastMyAchievements()
        end
        Print("|cFFFF4444Broadcast: Achievement leaderboard cache reset for all guild members.|r")
        cf:Hide()
      end)

      local cancelBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
      cancelBtn:SetWidth(80)
      cancelBtn:SetHeight(22)
      cancelBtn:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -20, 14)
      cancelBtn:SetText("Cancel")
      cancelBtn:SetScript("OnClick", function() cf:Hide() end)

      cf:Hide()
      LeafVE._confirmResetAchFrame = cf
    end
    LeafVE._confirmResetAchFrame:Show()
  end)

  panel.adminSubFrame = subFrame
  -- Set the scroll child height and update scrollbar range
  subFrame:SetHeight(math.abs(yBase) + 50)
  UpdateAdminScroll()
end

local function BuildJoinPanel(panel)
  local joinText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  joinText:SetPoint("CENTER", panel, "CENTER", 0, 10)
  joinText:SetWidth(420)
  joinText:SetJustifyH("CENTER")
  joinText:SetText("|cFFFFD700Please Join Leaf Village to gain access|r")
end

local function BuildWelcomePanel(panel)
  -- Header
  local headerBG = panel:CreateTexture(nil, "BACKGROUND")
  headerBG:SetPoint("TOP", panel, "TOP", -15, -10)
  headerBG:SetWidth(420)
  headerBG:SetHeight(50)
  headerBG:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  headerBG:SetVertexColor(0.15, 0.15, 0.18, 0.9)

  local accentTop = panel:CreateTexture(nil, "BORDER")
  accentTop:SetPoint("TOPLEFT", headerBG, "TOPLEFT", 0, 0)
  accentTop:SetPoint("TOPRIGHT", headerBG, "TOPRIGHT", 0, 0)
  accentTop:SetHeight(3)
  accentTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  accentTop:SetVertexColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3], 1)

  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOP", headerBG, "TOP", 0, -10)
  h:SetText("|cFF2DD35CLeaf Village Legends|r")

  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOP", h, "BOTTOM", 0, -3)
  subtitle:SetText("|cFF888888The path of a true shinobi begins here|r")

  -- Scrollable content area
  local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
  scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -75)
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)
  scrollFrame:EnableMouse(true)
  scrollFrame:EnableMouseWheel(true)

  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(410)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)

  scrollFrame:SetScript("OnMouseWheel", function()
    local current = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    local newScroll = current - (arg1 * 40)
    if newScroll < 0 then newScroll = 0 end
    if newScroll > maxScroll then newScroll = maxScroll end
    scrollFrame:SetVerticalScroll(newScroll)
  end)

  local scrollBar = CreateFrame("Slider", nil, panel)
  scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -75)
  scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 12)
  scrollBar:SetWidth(16)
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetMinMaxValues(0, 100)
  scrollBar:SetValue(0)
  local thumb = scrollBar:GetThumbTexture()
  thumb:SetWidth(16)
  thumb:SetHeight(24)
  scrollBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  scrollBar:SetBackdropColor(0, 0, 0, 0.3)
  scrollBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
  scrollBar:SetScript("OnValueChanged", function()
    local value = scrollBar:GetValue()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      scrollFrame:SetVerticalScroll((value / 100) * maxScroll)
    end
  end)
  scrollFrame:SetScript("OnVerticalScroll", function()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      local current = scrollFrame:GetVerticalScroll()
      scrollBar:SetValue((current / maxScroll) * 100)
    else
      scrollBar:SetValue(0)
    end
  end)

  -- Content helpers
  local yOffset = -10
  local lineGap = 19
  local sectionGap = 28

  local function AddSection(title, icon)
    local tex = scrollChild:CreateTexture(nil, "ARTWORK")
    tex:SetWidth(16)
    tex:SetHeight(16)
    tex:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset + 3)
    tex:SetTexture(icon or LEAF_EMBLEM)
    tex:SetVertexColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3], 1)
    local fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 30, yOffset)
    fs:SetText("|cFF2DD35C"..title.."|r")
    yOffset = yOffset - sectionGap
  end

  local function AddLine(text, indent)
    indent = indent or 0
    local fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 14 + indent, yOffset)
    fs:SetWidth(390 - indent)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    yOffset = yOffset - lineGap
    return fs
  end

  local function AddDivider()
    local div = scrollChild:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset + 6)
    div:SetWidth(390)
    div:SetHeight(1)
    div:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    div:SetVertexColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3], 0.35)
    yOffset = yOffset - 14
  end

  -- Welcome
  AddSection("Welcome, Shinobi!", "Interface\\Icons\\Spell_Nature_ResistNature")
  AddLine("Believe it! You have joined Leaf Village Legends, a guild tracker")
  AddLine("that honours every mission, every ally, and every act of recognition.")
  AddLine("In the spirit of Konohagakure, no shinobi walks alone. Your deeds")
  AddLine("earn |cFFFFD700Leaf Points (LP)|r, the currency of legends.")
  yOffset = yOffset - 4
  AddDivider()

  -- How to earn points
  AddSection("How to Earn Leaf Points", "Interface\\Icons\\INV_Misc_Coin_01")

  panel.welcomeLoginLine = AddLine("|cFFFFD700Daily Login|r  (+20 LP)", 10)
  AddLine("Log in each day to collect your ninja stipend. Chain logins unlock", 20)
  AddLine("legendary badges at 7 and 30 days straight.", 20)
  yOffset = yOffset - 4

  panel.welcomeGroupHeader = AddLine("|cFFFFD700Group Time|r  (+10 LP per online guildie every 20 minutes (cap: 700/day))", 10)
  panel.welcomeGroupDetail = AddLine("Spend time in a party or raid with online guildmates. Earn 10 LP", 20)
  AddLine("per online guildie per session. Offline members do not count.", 20)
  yOffset = yOffset - 4

  local soPoints = (LeafVE_DB and LeafVE_DB.options and LeafVE_DB.options.shoutoutPoints) or 10
  local soMax = (LeafVE_DB and LeafVE_DB.options and LeafVE_DB.options.shoutoutMaxDaily) or SHOUTOUT_MAX_PER_DAY
  panel.welcomeSOHeader = AddLine(string.format("|cFFFFD700Shoutouts|r  (+%d LP each)", soPoints), 10)
  AddLine("Recognise a fellow shinobi's greatness! Both the giver and receiver", 20)
  panel.welcomeSODetail1 = AddLine(string.format("earn %d LP. Use |cFF00CCFF/so PlayerName [reason]|r. You have", soPoints), 20)
  panel.welcomeSODetail2 = AddLine(string.format("%d shoutouts per day, so spend them wisely!", soMax), 20)
  yOffset = yOffset - 4

  panel.welcomeInstHeader = AddLine("|cFFFFD700Instance Runs|r  (+10 dungeon boss, +25 raid boss | +10 dungeon complete, +25 raid complete)", 10)
  AddLine("Complete dungeons or raids with a guildmate. Earn boss kill points", 20)
  panel.welcomeInstDetail = AddLine("plus a flat completion bonus. Boss and completion points are separate.", 20)
  yOffset = yOffset - 4

  panel.welcomeQuestHeader = AddLine("|cFFFFD700Quest Completions|r  (+10 LP, no daily cap)", 10)
  panel.welcomeQuestDetail1 = AddLine("Turn in quests while grouped with a guildmate to earn 10 LP each.", 20)
  panel.welcomeQuestDetail2 = AddLine("No daily cap — every mission matters!", 20)
  yOffset = yOffset - 6
  AddDivider()

  -- Badges
  AddSection("Badges", "Interface\\Icons\\INV_Letter_15")
  AddLine("Badges are titles of honour earned when you hit milestones:")
  AddLine("login streaks, group counts, shoutouts received, point totals,")
  AddLine("and raid attendance all unlock badges automatically.")
  AddLine("View yours in the |cFFFFD700Badges|r tab and wear them with pride!")
  yOffset = yOffset - 6
  AddDivider()

  -- Achievements
  AddSection("Achievements", "Interface\\Icons\\INV_Misc_Note_01")
  AddLine("Track your journey through Azeroth: levels, professions, dungeons,")
  AddLine("raids, PvP rank, gold, and exploration. Complete specific feats to")
  AddLine("unlock titles like |cFFFFD700Hokage|r or |cFF00CCFFShadow Clone|r.")
  AddLine("Equip a title and broadcast your legend to the guild!")
  yOffset = yOffset - 6
  AddDivider()

  -- Quick Commands
  AddSection("Quick Commands", "Interface\\Icons\\INV_Misc_Book_09")
  AddLine("|cFF00CCFF/lve|r  or  |cFF00CCFF/leaf|r        - Open this window")
  AddLine("|cFF00CCFF/so PlayerName [reason]|r   - Give a shoutout")
  AddLine("|cFF00CCFF/lboardreq|r              - Request leaderboard sync")
  AddLine("|cFF00CCFF/badgesync|r              - Broadcast your badges")
  AddLine("|cFF00CCFF/lvedebug points|r        - Show your current points")
  yOffset = yOffset - 6
  AddDivider()

  -- Closing
  AddSection("Final Words", "Interface\\Icons\\Spell_Holy_BlessingOfStrength")
  AddLine("\"In the ninja world, those who break the rules are scum,")
  AddLine("but those who abandon their comrades are worse than scum.\"")
  AddLine("|cFF2DD35C- Kakashi Hatake|r")
  yOffset = yOffset - 4
  AddLine("Now run dungeons, shout out your homies, and climb to the top")
  AddLine("of the leaderboard. The Will of Fire burns in every guildmate!")

  yOffset = yOffset - 20
  scrollChild:SetHeight(math.abs(yOffset) + 20)
end

function LeafVE:CreateMinimapButton()
  if self.minimapBtn then return end
  EnsureDB()

  local btn = CreateFrame("Button", "LeafVEMinimapButton", Minimap)
  btn:SetWidth(28)
  btn:SetHeight(28)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:SetClampedToScreen(true)
  btn:SetMovable(true)
  btn:EnableMouse(true)
  btn:RegisterForDrag("LeftButton")
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
  icon:SetTexture(LEAF_EMBLEM)

  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetWidth(52)
  border:SetHeight(52)
  border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  local function UpdatePos()
    local angle = math.rad(LeafVE_DB.options.minimapPos or 220)
    local x = math.cos(angle) * 82
    local y = math.sin(angle) * 82
    btn:SetPoint("TOPLEFT", Minimap, "CENTER", x - 14, y + 14)
  end
  UpdatePos()

  btn:SetScript("OnDragStart", function() btn:StartMoving() end)
  btn:SetScript("OnDragStop", function()
    btn:StopMovingOrSizing()
    local cx, cy = btn:GetCenter()
    local mx, my = Minimap:GetCenter()
    local dx, dy = cx - mx, cy - my
    local angle = math.deg(math.atan2(dy, dx))
    if angle < 0 then angle = angle + 360 end
    EnsureDB()
    LeafVE_DB.options.minimapPos = angle
    UpdatePos()
  end)

  btn:SetScript("OnClick", function()
    LeafVE:ToggleUI()
  end)

  btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("Leaf Village Legends", THEME.leaf[1], THEME.leaf[2], THEME.leaf[3])
    GameTooltip:AddLine("Click to toggle UI", 1, 1, 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  self.minimapBtn = btn
end

function LeafVE.UI:RefreshHistory()
  if not self.panels or not self.panels.history then return end
  local panel = self.panels.history

  local me = ShortName(UnitName("player"))
  local history = LeafVE:GetHistory(me, 100)

  for i = 1, table.getn(panel.historyEntries) do
    panel.historyEntries[i]:Hide()
  end

  local scrollChild = panel.scrollChild
  local yOffset = -5
  local entryHeight = 38

  if table.getn(history) == 0 then
    if not panel.noHistoryText then
      local noHistoryText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      noHistoryText:SetPoint("TOP", scrollChild, "TOP", 0, -20)
      noHistoryText:SetText("|cFF888888No history yet|r")
      panel.noHistoryText = noHistoryText
    end
    panel.noHistoryText:Show()
  else
    if panel.noHistoryText then
      panel.noHistoryText:Hide()
    end

    for i = 1, table.getn(history) do
      local entry = history[i]
      local frame = panel.historyEntries[i]

      if not frame then
        frame = CreateFrame("Frame", nil, scrollChild)
        frame:SetWidth(480)
        frame:SetHeight(entryHeight)

        local dateText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateText:SetPoint("LEFT", frame, "LEFT", 5, 0)
        dateText:SetWidth(100)
        dateText:SetJustifyH("LEFT")
        frame.dateText = dateText

        local typeIcon = frame:CreateTexture(nil, "ARTWORK")
        typeIcon:SetWidth(16)
        typeIcon:SetHeight(16)
        typeIcon:SetPoint("LEFT", dateText, "RIGHT", 5, 0)
        frame.typeIcon = typeIcon

        local amountText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        amountText:SetPoint("LEFT", typeIcon, "RIGHT", 5, 0)
        amountText:SetWidth(40)
        amountText:SetJustifyH("LEFT")
        frame.amountText = amountText

        local reasonText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        reasonText:SetPoint("LEFT", amountText, "RIGHT", 10, 0)
        reasonText:SetWidth(280)
        reasonText:SetJustifyH("LEFT")
        frame.reasonText = reasonText

        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        bg:SetVertexColor(0.1, 0.1, 0.1, 0.3)
        frame.bg = bg

        table.insert(panel.historyEntries, frame)
      end

      frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)

      frame.dateText:SetText(date("%m/%d %H:%M", entry.timestamp))

      local typeColor = {1, 1, 1}
      if entry.type == "L" then
        frame.typeIcon:SetTexture(LEAF_EMBLEM)
        typeColor = THEME.leaf
      elseif entry.type == "G" then
        frame.typeIcon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
        typeColor = THEME.gold
      elseif entry.type == "S" then
        frame.typeIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        typeColor = THEME.gold
      end

      if not frame.typeIcon:GetTexture() then
        frame.typeIcon:SetTexture(LEAF_FALLBACK)
      end
      frame.typeIcon:SetVertexColor(typeColor[1], typeColor[2], typeColor[3])

      frame.amountText:SetText("|cFFFFD700+"..entry.amount.."|r")
      frame.reasonText:SetText(entry.reason or "")

      frame:Show()
      yOffset = yOffset - entryHeight - 6
    end
  end

  scrollChild:SetHeight(math.max(1, math.abs(yOffset) + 50))

  local scrollRange = panel.scrollFrame:GetVerticalScrollRange()
  if scrollRange > 0 then
    panel.scrollBar:Show()
  else
    panel.scrollBar:Hide()
  end

  panel.scrollFrame:SetVerticalScroll(0)
  panel.scrollBar:SetValue(0)
end

-------------------------------------------------
-- ALT PANEL REFRESH (FEATURE A)
-------------------------------------------------

function LeafVE.UI:RefreshAltPanel()
  if not self.panels or not self.panels.alt then return end
  local p = self.panels.alt
  EnsureDB()
  local myKey = LVL_GetCharKey()
  local isLinked = LVL_IsAltLinked(myKey)

  -- Update status text
  if p.altStatusText then
    if isLinked then
      p.altStatusText:SetText("|cFF00FF00Linked to: " .. LVL_GetMainKey(myKey) .. "|r")
    else
      local pending = LeafVE_DB.pendingMerge and LeafVE_DB.pendingMerge[myKey]
      if pending then
        p.altStatusText:SetText("|cFFFFAA00Pending approval: " .. (pending.main or "?") .. "|r")
      else
        p.altStatusText:SetText("|cFFAAAAAA Not linked|r")
      end
    end
  end

  -- Show/hide input box
  if p.altMainInput then
    if isLinked then
      p.altMainInput:Hide()
      if p.altInputLabel then p.altInputLabel:Hide() end
    else
      p.altMainInput:Show()
      if p.altInputLabel then p.altInputLabel:Show() end
    end
  end

  -- Update link/unlink button text
  if p.altLinkBtn then
    p.altLinkBtn:SetText(isLinked and "Unlink" or "Link Points")
  end

  -- Show/hide deposit button
  if p.altDepositBtn then
    if isLinked then
      p.altDepositBtn:Show()
    else
      p.altDepositBtn:Hide()
    end
  end

  -- Update cooldown text
  if p.altCooldownText then
    local lc = LeafVE_DB.lastLinkChange and LeafVE_DB.lastLinkChange[myKey]
    local ld = LeafVE_DB.lastDeposit and LeafVE_DB.lastDeposit[myKey]
    local linkRemain = LVL_Remain(lc, SECONDS_PER_DAY)
    local depositRemain = LVL_Remain(ld, SECONDS_PER_DAY)
    local parts = {}
    if linkRemain > 0 then
      table.insert(parts, (isLinked and "Unlink: " or "Link: ") .. LVL_FormatTime(linkRemain))
    end
    if isLinked and depositRemain > 0 then
      table.insert(parts, "Deposit: " .. LVL_FormatTime(depositRemain))
    end
    if table.getn(parts) > 0 then
      p.altCooldownText:SetText("|cFFAAAAAA" .. table.concat(parts, " | ") .. "|r")
    else
      p.altCooldownText:SetText("")
    end
  end
end


  if not self.panels or not self.panels.shoutouts then return end
  local panel = self.panels.shoutouts
  if not panel.shoutScrollChild then return end

  EnsureDB()

  -- Collect all shoutout history entries from all players
  local allShouts = {}
  for playerName, history in pairs(LeafVE_DB.pointHistory) do
    for i = 1, table.getn(history) do
      local entry = history[i]
      if entry.type == "S" then
        table.insert(allShouts, {
          target = playerName,
          timestamp = entry.timestamp,
          reason = entry.reason or ""
        })
      end
    end
  end

  -- Sort by timestamp descending (most recent first)
  table.sort(allShouts, function(a, b) return a.timestamp > b.timestamp end)

  -- Hide existing entries
  for i = 1, table.getn(panel.shoutEntries) do
    panel.shoutEntries[i]:Hide()
  end

  local scrollChild = panel.shoutScrollChild
  local yOffset = -5
  local entryHeight = 30

  if table.getn(allShouts) == 0 then
    if not panel.noShoutText then
      local noShoutText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      noShoutText:SetPoint("TOP", scrollChild, "TOP", 0, -10)
      noShoutText:SetText("|cFF888888No shoutouts yet|r")
      panel.noShoutText = noShoutText
    end
    panel.noShoutText:Show()
  else
    if panel.noShoutText then panel.noShoutText:Hide() end

    local maxShow = table.getn(allShouts)
    for i = 1, maxShow do
      local shout = allShouts[i]
      local frame = panel.shoutEntries[i]

      if not frame then
        frame = CreateFrame("Frame", nil, scrollChild)
        frame:SetWidth(430)
        frame:SetHeight(entryHeight)

        local dateText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateText:SetPoint("LEFT", frame, "LEFT", 5, 0)
        dateText:SetWidth(65)
        dateText:SetJustifyH("LEFT")
        frame.dateText = dateText

        local msgText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        msgText:SetPoint("LEFT", dateText, "RIGHT", 5, 0)
        msgText:SetWidth(355)
        msgText:SetJustifyH("LEFT")
        frame.msgText = msgText

        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        bg:SetVertexColor(0.1, 0.1, 0.1, 0.3)
        frame.bg = bg

        table.insert(panel.shoutEntries, frame)
      end

      frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
      frame.dateText:SetText(date("%m/%d", shout.timestamp))
      frame.msgText:SetText("|cFFFFD700" .. shout.target .. "|r - " .. shout.reason)

      if math.mod(i, 2) == 0 then
        frame.bg:SetVertexColor(0.08, 0.08, 0.08, 0.4)
      else
        frame.bg:SetVertexColor(0.12, 0.12, 0.12, 0.3)
      end

      frame:Show()
      yOffset = yOffset - entryHeight - 4
    end
  end

  scrollChild:SetHeight(math.max(1, math.abs(yOffset) + 20))

  local scrollRange = panel.shoutScrollFrame:GetVerticalScrollRange()
  if scrollRange > 0 then
    panel.shoutScrollBar:Show()
  else
    panel.shoutScrollBar:Hide()
  end

  panel.shoutScrollFrame:SetVerticalScroll(0)
  panel.shoutScrollBar:SetValue(0)
end

function LeafVE.UI:RefreshBadges()
  if not self.panels or not self.panels.badges then 
    Print("ERROR: panels.badges not found")
    return 
  end
  local panel = self.panels.badges

  local me = ShortName(UnitName("player"))
  EnsureDB()

  -- When a player card is open for someone else, show that player's badges
  local viewTarget = (self.cardCurrentPlayer and self.cardCurrentPlayer ~= "") and self.cardCurrentPlayer or me
  local myBadges = LeafVE_DB.badges[viewTarget] or {}

  -- Safety check: ensure badgeFrames exists
  if not panel.badgeFrames then
    panel.badgeFrames = {}
  end

  for i = 1, table.getn(panel.badgeFrames) do
    panel.badgeFrames[i]:Hide()
  end

  local scrollChild = panel.scrollChild

  -- Ensure scrollChild is properly configured
  if not scrollChild then
    Print("ERROR: scrollChild doesn't exist!")
    return
  end

  scrollChild:ClearAllPoints()
  scrollChild:SetPoint("TOPLEFT", panel.scrollFrame, "TOPLEFT", 0, 0)
  scrollChild:SetWidth(400)  -- Fixed width
  scrollChild:Show()

  local yOffset = -10
  local badgeSize = 80
  local xSpacing = 90
  local ySpacing = 110
  local perRow = 4

  local allBadges = {}
  for i = 1, table.getn(BADGES) do
    local badge = BADGES[i]
    local earned = myBadges[badge.id] ~= nil
    table.insert(allBadges, {
      id = badge.id,
      name = badge.name,
      desc = badge.desc,
      icon = badge.icon,
      quality = badge.quality or BADGE_QUALITY.COMMON,
      category = badge.category or "Other",
      order = i,  -- BADGES array index for within-category progression order
      earned = earned,
      earnedAt = myBadges[badge.id]
    })
  end

  -- Sort: category name alphabetically first, then by BADGES array index within each category
  table.sort(allBadges, function(a, b)
    if a.category ~= b.category then
      return a.category < b.category
    end
    return a.order < b.order
  end)

  if table.getn(allBadges) == 0 then
    if not panel.noBadgesText then
      local noBadgesText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      noBadgesText:SetPoint("TOP", scrollChild, "TOP", 0, -20)
      noBadgesText:SetText("|cFF888888No badges available yet|r")
      panel.noBadgesText = noBadgesText
    end
    panel.noBadgesText:Show()
    scrollChild:SetHeight(100)
  else
    if panel.noBadgesText then
      panel.noBadgesText:Hide()
    end

    local row = 0
    local col = 0
    local lastYPos = yOffset  -- Track the last Y position

    for i = 1, table.getn(allBadges) do
      local badge = allBadges[i]
      local frame = panel.badgeFrames[i]

      if not frame then
        frame = CreateFrame("Frame", nil, scrollChild)
        frame:SetWidth(badgeSize)
        frame:SetHeight(badgeSize)
        frame:EnableMouse(true)

        -- Quality-coloured border (drawn behind the icon)
        local qualityBorder = frame:CreateTexture(nil, "BACKGROUND")
        qualityBorder:SetAllPoints(frame)
        qualityBorder:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        frame.qualityBorder = qualityBorder

        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(badgeSize - 10)
        icon:SetHeight(badgeSize - 10)
        icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame.icon = icon

        local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("TOP", frame, "BOTTOM", 0, -2)
        nameText:SetWidth(badgeSize + 20)
        nameText:SetJustifyH("CENTER")
        frame.nameText = nameText

        table.insert(panel.badgeFrames, frame)
      end
      
      -- CALCULATE POSITION
      local xPos = 10 + (col * xSpacing)
      local yPos = yOffset - (row * ySpacing)
      lastYPos = yPos  -- Update last Y position

      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", xPos, yPos)

      -- SET ICON AND STYLE
      frame.icon:SetTexture(badge.icon)
      if not frame.icon:GetTexture() then
        frame.icon:SetTexture(LEAF_FALLBACK)
      end

      local qr, qg, qb = GetBadgeQualityColor(badge.quality)
      if badge.earned then
        frame.icon:SetVertexColor(1, 1, 1, 1)
        -- Quality-coloured name text
        frame.nameText:SetText(badge.name)
        frame.nameText:SetTextColor(qr, qg, qb)
        -- Quality border glow
        if frame.qualityBorder then
          frame.qualityBorder:SetVertexColor(qr, qg, qb, 0.35)
          frame.qualityBorder:Show()
        end
      else
        frame.icon:SetVertexColor(0.3, 0.3, 0.3, 1)
        frame.nameText:SetText(badge.name)
        frame.nameText:SetTextColor(0.4, 0.4, 0.4)
        if frame.qualityBorder then
          frame.qualityBorder:Hide()
        end
      end

      frame.badgeName = badge.name
      frame.badgeDesc = badge.desc
      frame.badgeQuality = badge.quality
      frame.earnedAt = badge.earnedAt
      frame.badgeId = badge.id
      frame.badgePlayerName = viewTarget
      
      -- TOOLTIP
      frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        local qr2, qg2, qb2 = GetBadgeQualityColor(this.badgeQuality)
        GameTooltip:SetText(this.badgeName, qr2, qg2, qb2, 1, true)
        GameTooltip:AddLine("|cFF888888"..GetBadgeQualityLabel(this.badgeQuality).."|r", 1, 1, 1)
        GameTooltip:AddLine(this.badgeDesc, 1, 1, 1, true)
        if this.earnedAt then
          GameTooltip:AddLine(" ", 1, 1, 1)
          GameTooltip:AddLine("Earned: "..date("%m/%d/%Y", this.earnedAt), 0.5, 0.8, 0.5)
        else
          GameTooltip:AddLine(" ", 1, 1, 1)
          local cur, tgt = LeafVE:GetBadgeProgress(this.badgePlayerName, this.badgeId)
          if cur and tgt then
            GameTooltip:AddLine("Progress: "..cur.." / "..tgt, 1, 0.82, 0)
          end
          GameTooltip:AddLine("Not yet earned", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
      end)
      
      frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      frame:Show()

      -- INCREMENT COLUMN/ROW
      col = col + 1
      if col >= perRow then
        col = 0
        row = row + 1
      end
    end

    -- CALCULATE TOTAL HEIGHT using actual last position
    local calculatedHeight = math.abs(lastYPos) + badgeSize + 80
    
    -- FORCE the scrollChild to update (Vanilla WoW fix)
    scrollChild:SetHeight(1)  -- Reset to 1
    scrollChild:Show()
    scrollChild:SetHeight(calculatedHeight)  -- Set actual height
    
    -- Force the scrollFrame to recalculate
    panel.scrollFrame:SetVerticalScroll(0)
    panel.scrollFrame:Show()
  end

  -- Wait one frame for layout to update, then check scroll range
  local checkFrame = CreateFrame("Frame")
  checkFrame:SetScript("OnUpdate", function()
    local scrollRange = panel.scrollFrame:GetVerticalScrollRange()
    local viewportHeight = panel.scrollFrame:GetHeight()
    
    if scrollRange > 0 then
      panel.scrollBar:SetMinMaxValues(0, scrollRange)
      panel.scrollBar:Show()
    else
      panel.scrollBar:Hide()
    end
    
    panel.scrollFrame:SetVerticalScroll(0)
    panel.scrollBar:SetValue(0)
    
    -- Remove this frame after one update
    checkFrame:SetScript("OnUpdate", nil)
  end)
end

function LeafVE.UI:RefreshAchievementsLeaderboard()
  if not self.panels or not self.panels.achievements then return end
  local panel = self.panels.achievements

  EnsureDB()
  LeafVE:UpdateGuildRosterCache()

  local leaders = {}

  -- Build a unified set of players from both the guild roster and the achievement cache
  local allPlayers = {}
  for _, guildInfo in pairs(LeafVE.guildRosterCache) do
    allPlayers[Lower(guildInfo.name)] = { name = guildInfo.name, class = guildInfo.class or "Unknown" }
  end
  if LeafVE_GlobalDB.achievementCache then
    for cachedName, _ in pairs(LeafVE_GlobalDB.achievementCache) do
      local lname = Lower(cachedName)
      if not allPlayers[lname] then
        allPlayers[lname] = { name = cachedName, class = "Unknown" }
      end
    end
  end

  for _, playerInfo in pairs(allPlayers) do
    local name = playerInfo.name
    local achPoints = 0

    -- Try live API first
    if LeafVE_AchTest and LeafVE_AchTest.API and LeafVE_AchTest.API.GetPlayerPoints then
      achPoints = LeafVE_AchTest.API.GetPlayerPoints(name) or 0
    end

    -- Fall back to cached data if live API returned nothing
    if achPoints == 0 and LeafVE_GlobalDB.achievementCache and LeafVE_GlobalDB.achievementCache[name] then
      local cache = LeafVE_GlobalDB.achievementCache[name]
      if cache._totalPoints then
        achPoints = cache._totalPoints
      else
        -- Manually sum cached achievement points
        for achId, _ in pairs(cache) do
          if achId ~= "_totalPoints" then
            local meta = LeafVE_AchTest and LeafVE_AchTest.GetAchievementMeta and LeafVE_AchTest.GetAchievementMeta(achId)
            local pts = (meta and meta.points) or DEFAULT_ACHIEVEMENT_POINTS
            achPoints = achPoints + pts
          end
        end
      end
    end

    if achPoints > 0 then
      table.insert(leaders, {
        name = name,
        points = achPoints,
        class = playerInfo.class
      })
    end
  end

  table.sort(leaders, function(a, b)
    if a.points == b.points then
      return Lower(a.name) < Lower(b.name)
    end
    return a.points > b.points
  end)

  for i = 1, table.getn(panel.achEntries) do
    panel.achEntries[i]:Hide()
  end

  local scrollChild = panel.scrollChild
  local yOffset = -5
  local entryHeight = 40

  local maxShow = math.min(20, table.getn(leaders))

  if table.getn(leaders) == 0 then
    if not panel.noDataText then
      local noDataText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      noDataText:SetPoint("TOP", scrollChild, "TOP", 0, -20)
      noDataText:SetText("|cFF888888No achievement data available yet|r")
      panel.noDataText = noDataText
    end
    panel.noDataText:Show()
  else
    if panel.noDataText then
      panel.noDataText:Hide()
    end

    for i = 1, maxShow do
      local leader = leaders[i]
      local frame = panel.achEntries[i]
      if not frame then
        frame = CreateFrame("Frame", nil, scrollChild)
        frame:SetWidth(480)
        frame:SetHeight(entryHeight)

        local rankIcon = frame:CreateTexture(nil, "ARTWORK")
        rankIcon:SetWidth(32)
        rankIcon:SetHeight(32)
        rankIcon:SetPoint("LEFT", frame, "LEFT", 5, 0)
        frame.rankIcon = rankIcon

        local rank = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        rank:SetPoint("LEFT", frame, "LEFT", 5, 0)
        rank:SetWidth(30)
        rank:SetJustifyH("RIGHT")
        frame.rank = rank

        local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", rank, "RIGHT", 40, 0)
        nameText:SetWidth(200)
        nameText:SetJustifyH("LEFT")
        frame.nameText = nameText

        local pointsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        pointsText:SetPoint("LEFT", nameText, "RIGHT", 10, 0)
        pointsText:SetWidth(200)
        pointsText:SetJustifyH("LEFT")
        frame.pointsText = pointsText

        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        bg:SetVertexColor(0.1, 0.1, 0.1, 0.3)
        frame.bg = bg

        frame:EnableMouse(true)
        frame:SetScript("OnEnter", function()
          this.bg:SetVertexColor(0.25, 0.25, 0.15, 0.7)
        end)
        frame:SetScript("OnLeave", function()
          this.bg:SetVertexColor(0.1, 0.1, 0.1, 0.3)
        end)
        frame:SetScript("OnMouseUp", function()
          if this.playerName then
            if LeafVE.UI.allBadgesFrame and LeafVE.UI.allBadgesFrame:IsVisible() then
              LeafVE.UI.allBadgesFrame:Hide()
            end
            if LeafVE.UI.achPopup and LeafVE.UI.achPopup:IsVisible() then
              LeafVE.UI.achPopup:Hide()
            end
            if LeafVE.UI.gearPopup and LeafVE.UI.gearPopup:IsVisible() then
              LeafVE.UI.gearPopup:Hide()
            end
            LeafVE.UI.inspectedPlayer = this.playerName
            LeafVE.UI:ShowPlayerCard(this.playerName)
          end
        end)

        table.insert(panel.achEntries, frame)
      end

      frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)

      -- Show PVP rank icons for top 5, numbers for rest
      if i <= 5 and PVP_RANK_ICONS[i] then
        frame.rankIcon:SetTexture(PVP_RANK_ICONS[i])
        frame.rankIcon:Show()
        frame.rank:Hide()
      else
        frame.rankIcon:Hide()
        frame.rank:Show()
        frame.rank:SetText("#"..i)
        frame.rank:SetTextColor(1, 1, 1)
      end

      local class = string.upper(leader.class or "UNKNOWN")
      local classColor = CLASS_COLORS[class] or {1, 1, 1}
      frame.nameText:SetText(leader.name)
      frame.nameText:SetTextColor(classColor[1], classColor[2], classColor[3])
      frame.playerName = leader.name

      frame.pointsText:SetText("|cFFFFD700"..leader.points.." achievement pts|r")

      frame:Show()
      yOffset = yOffset - entryHeight - 8
    end
  end

  scrollChild:SetHeight(math.max(1, math.abs(yOffset) + 50))

  local scrollRange = panel.scrollFrame:GetVerticalScrollRange()
  if scrollRange > 0 then
    panel.scrollBar:Show()
  else
    panel.scrollBar:Hide()
  end

  panel.scrollFrame:SetVerticalScroll(0)
  panel.scrollBar:SetValue(0)
end

function LeafVE.UI:Build()
  if self.frame then return end
  
  EnsureDB()
  
  local f = CreateFrame("Frame", nil, UIParent)
  self.frame = f
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  
  local w = LeafVE_DB.ui.w or 1050
  local h = LeafVE_DB.ui.h or 699  -- ← CHANGED TO 699
  
  if w < 950 then w = 950 end
  if w > 1400 then w = 1400 end
  if h < 600 then h = 600 end  
  if h > 1000 then h = 1000 end
  
  f:SetWidth(w)
  f:SetHeight(h)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    if LeafVE_DB and LeafVE_DB.ui then
      local point, _, relativePoint, x, y = f:GetPoint()
      LeafVE_DB.ui.point = point
      LeafVE_DB.ui.relativePoint = relativePoint
      LeafVE_DB.ui.x = x
      LeafVE_DB.ui.y = y
    end
  end)
  
  SkinFrameModern(f)
  MakeResizeHandle(f)
  
  f:SetScript("OnSizeChanged", function()
    if LeafVE_DB and LeafVE_DB.ui then
      LeafVE_DB.ui.w = f:GetWidth()
      LeafVE_DB.ui.h = f:GetHeight()
    end
  end)

  if f.HookScript then
    f:HookScript("OnHide", function()
      if LeafVE.UI.allBadgesFrame then LeafVE.UI.allBadgesFrame:Hide() end
      if LeafVE.UI.achPopup then LeafVE.UI.achPopup:Hide() end
      if LeafVE.UI.gearPopup then LeafVE.UI.gearPopup:Hide() end
    end)
  else
    local _prevOnHide = f:GetScript("OnHide")
    f:SetScript("OnHide", function()
      if _prevOnHide then _prevOnHide(f) end
      if LeafVE.UI.allBadgesFrame then LeafVE.UI.allBadgesFrame:Hide() end
      if LeafVE.UI.achPopup then LeafVE.UI.achPopup:Hide() end
      if LeafVE.UI.gearPopup then LeafVE.UI.gearPopup:Hide() end
    end)
  end
  
  -- Title (CENTERED, GOLD)
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", f, "TOP", 0, -12)  -- ← CENTERED
  title:SetText("|cFFFFD700Leaf Village Legends|r")  -- ← GOLD COLOR
  
  -- Subtitle description (centered below title)
  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOP", title, "BOTTOM", 0, -2)
  sub:SetText("Auto-tracking: Login + Group Points")
  sub:SetTextColor(0.7, 0.7, 0.7)
  
  -- Emblem (left side, keep existing)
  local emblem = f:CreateTexture(nil, "ARTWORK")
  emblem:SetWidth(22)
  emblem:SetHeight(22)
  emblem:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
  emblem:SetTexture(LEAF_EMBLEM)
  if not emblem:GetTexture() then emblem:SetTexture(LEAF_FALLBACK) end
  emblem:SetVertexColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3], 1)
  
  -- Created by credit (FAR RIGHT)
  local credit = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  credit:SetPoint("TOPRIGHT", f, "TOPRIGHT", -35, -12)
  credit:SetText("|cFF2DD35CCreated by Methl|r")
  credit:SetAlpha(0.9)
  
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

  self.tabJoin = TabButton(f, "Please Join Leaf Village to gain access", "LeafVE_TabJoin")
  self.tabJoin:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -52)
  self.tabJoin:SetWidth(300)
  self.tabJoin:Hide()

  self.tabWelcome = TabButton(f, "Welcome", "LeafVE_TabWelcome")
  self.tabWelcome:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -52)
  self.tabWelcome:SetWidth(65)

  self.tabMe = TabButton(f, "My Stats", "LeafVE_TabMy")
  self.tabMe:SetPoint("LEFT", self.tabWelcome, "RIGHT", 4, 0)
  self.tabMe:SetWidth(70)

  self.tabShout = TabButton(f, "Shout", "LeafVE_TabShout")
  self.tabShout:SetPoint("LEFT", self.tabMe, "RIGHT", 4, 0)
  self.tabShout:SetWidth(55)

  self.tabRoster = TabButton(f, "Roster", "LeafVE_TabRoster")
  self.tabRoster:SetPoint("LEFT", self.tabShout, "RIGHT", 4, 0)
  self.tabRoster:SetWidth(60)

  self.tabLeaderWeek = TabButton(f, "Weekly", "LeafVE_TabLeaderWeek")
  self.tabLeaderWeek:SetPoint("LEFT", self.tabRoster, "RIGHT", 4, 0)
  self.tabLeaderWeek:SetWidth(60)

  self.tabLeaderLife = TabButton(f, "Lifetime", "LeafVE_TabLeaderLife")
  self.tabLeaderLife:SetPoint("LEFT", self.tabLeaderWeek, "RIGHT", 4, 0)
  self.tabLeaderLife:SetWidth(65)

  self.tabAchievements = TabButton(f, "Achievements", "LeafVE_TabAchievements")
  self.tabAchievements:SetPoint("LEFT", self.tabLeaderLife, "RIGHT", 4, 0)
  self.tabAchievements:SetWidth(95)

  self.tabBadges = TabButton(f, "Badges", "LeafVE_TabBadges")
  self.tabBadges:SetPoint("LEFT", self.tabAchievements, "RIGHT", 4, 0)
  self.tabBadges:SetWidth(65)

  self.tabHistory = TabButton(f, "History", "LeafVE_TabHistory")
  self.tabHistory:SetPoint("LEFT", self.tabBadges, "RIGHT", 4, 0)
  self.tabHistory:SetWidth(60)

  self.tabOptions = TabButton(f, "Options", "LeafVE_TabOptions")
  self.tabOptions:SetPoint("LEFT", self.tabHistory, "RIGHT", 4, 0)
  self.tabOptions:SetWidth(60)

  self.tabAdmin = TabButton(f, "Admin", "LeafVE_TabAdmin")
  self.tabAdmin:SetPoint("LEFT", self.tabOptions, "RIGHT", 4, 0)
  self.tabAdmin:SetWidth(50)
  -- Show admin tab only to Anbu, Sannin, or Hokage
  if LeafVE:IsAdminRank() then
    self.tabAdmin:Show()
  else
    self.tabAdmin:Hide()
  end

  self.tabAlt = TabButton(f, "Alts", "LeafVE_TabAlt")
  self.tabAlt:SetPoint("LEFT", self.tabAdmin, "RIGHT", 4, 0)
  self.tabAlt:SetWidth(45)
  
  self.inset = CreateInset(f)
  self.inset:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -80)
  self.inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
  
  self.left = CreateFrame("Frame", nil, self.inset)
  self.left:SetPoint("TOPLEFT", self.inset, "TOPLEFT", 0, 0)
  self.left:SetPoint("BOTTOMLEFT", self.inset, "BOTTOMLEFT", 0, 0)
  self.left:SetPoint("TOPRIGHT", self.inset, "TOPRIGHT", -470, 0)
  self.left:SetPoint("BOTTOMRIGHT", self.inset, "BOTTOMRIGHT", -470, 0)
  
  self:BuildPlayerCard(self.inset)
  
  -- Create all panels
  self.panels = {}
  
  self.panels.me = CreateFrame("Frame", nil, self.left)
  self.panels.me:SetAllPoints(self.left)
  BuildMyPanel(self.panels.me)
  
  self.panels.shoutouts = CreateFrame("Frame", nil, self.left)
  self.panels.shoutouts:SetAllPoints(self.left)
  BuildShoutoutsPanel(self.panels.shoutouts)
  
  self.panels.leaderWeek = CreateFrame("Frame", nil, self.left)
  self.panels.leaderWeek:SetAllPoints(self.left)
  BuildLeaderboardPanel(self.panels.leaderWeek, true)
  
  self.panels.leaderLife = CreateFrame("Frame", nil, self.left)
  self.panels.leaderLife:SetAllPoints(self.left)
  BuildLeaderboardPanel(self.panels.leaderLife, false)
  
  self.panels.roster = CreateFrame("Frame", nil, self.left)
  self.panels.roster:SetAllPoints(self.left)
  BuildRosterPanel(self.panels.roster)
  
  self.panels.history = CreateFrame("Frame", nil, self.left)
  self.panels.history:SetAllPoints(self.left)
  BuildHistoryPanel(self.panels.history)
  
  self.panels.badges = CreateFrame("Frame", nil, self.left)
  self.panels.badges:SetAllPoints(self.left)
  BuildBadgesPanel(self.panels.badges)
  
  self.panels.achievements = CreateFrame("Frame", nil, self.left)
  self.panels.achievements:SetAllPoints(self.left)
  BuildAchievementsPanel(self.panels.achievements)

  self.panels.options = CreateFrame("Frame", nil, self.left)
  self.panels.options:SetAllPoints(self.left)
  BuildOptionsPanel(self.panels.options)

  self.panels.admin = CreateFrame("Frame", nil, self.left)
  self.panels.admin:SetAllPoints(self.left)
  BuildAdminPanel(self.panels.admin)

  self.panels.alt = CreateFrame("Frame", nil, self.left)
  self.panels.alt:SetAllPoints(self.left)
  BuildAltPanel(self.panels.alt)

  self.panels.welcome = CreateFrame("Frame", nil, self.left)
  self.panels.welcome:SetAllPoints(self.left)
  BuildWelcomePanel(self.panels.welcome)

  self.panels.join = CreateFrame("Frame", nil, self.left)
  self.panels.join:SetAllPoints(self.left)
  BuildJoinPanel(self.panels.join)
  
  -- Tab click handlers
  self.tabMe:SetScript("OnClick", function()
    self.activeTab = "me"
    self:Refresh()
  end)

  self.tabShout:SetScript("OnClick", function()
    self.activeTab = "shoutouts"
    self:Refresh()
  end)
  
  self.tabLeaderWeek:SetScript("OnClick", function()
    self.activeTab = "leaderWeek"
    self:Refresh()
  end)
  
  self.tabLeaderLife:SetScript("OnClick", function()
    self.activeTab = "leaderLife"
    self:Refresh()
  end)
  
  self.tabRoster:SetScript("OnClick", function()
    self.activeTab = "roster"
    self:Refresh()
  end)
  
  self.tabHistory:SetScript("OnClick", function()
    self.activeTab = "history"
    self:Refresh()
  end)
  
  self.tabBadges:SetScript("OnClick", function()
    self.activeTab = "badges"
    self:Refresh()
  end)
  
  self.tabAchievements:SetScript("OnClick", function()
    self.activeTab = "achievements"
    self:Refresh()
  end)

  self.tabOptions:SetScript("OnClick", function()
    self.activeTab = "options"
    self:Refresh()
  end)

  self.tabAdmin:SetScript("OnClick", function()
    self.activeTab = "admin"
    self:Refresh()
  end)

  self.tabAlt:SetScript("OnClick", function()
    self.activeTab = "alt"
    self:Refresh()
  end)

  self.tabWelcome:SetScript("OnClick", function()
    self.activeTab = "welcome"
    self:Refresh()
  end)
  
  self.tabJoin:SetScript("OnClick", function()
    self.activeTab = "join"
    self:Refresh()
  end)
  
  -- Initial state - hide all panels except "me"
  self.activeTab = "me"
  
  self.panels.shoutouts:Hide()
  self.panels.leaderWeek:Hide()
  self.panels.leaderLife:Hide()
  self.panels.roster:Hide()
  self.panels.history:Hide()
  self.panels.badges:Hide()
  self.panels.achievements:Hide()
  self.panels.options:Hide()
  self.panels.admin:Hide()
  self.panels.welcome:Hide()
  self.panels.join:Hide()
  self.panels.alt:Hide()
  
  self.panels.me:Show()
  
  local me = ShortName(UnitName("player"))
  if me then
    self:ShowPlayerCard(me)
  end
  
  if LeafVE_DB.ui.point and LeafVE_DB.ui.x and LeafVE_DB.ui.y then
    f:ClearAllPoints()
    f:SetPoint(LeafVE_DB.ui.point, UIParent, LeafVE_DB.ui.relativePoint or "CENTER", LeafVE_DB.ui.x, LeafVE_DB.ui.y)
  end
  
  f:Hide()
end

function LeafVE.UI:Refresh()
  EnsureDB()
  
  -- Safety check
  if not self.panels then 
    Print("ERROR: Panels not initialized!")
    return 
  end

  local hasAccess = LeafVE:HasLeafAccess()
  if not hasAccess and self.activeTab ~= "join" then
    self.activeTab = "join"
  elseif hasAccess and self.activeTab == "join" then
    self.activeTab = "me"
  end

  local accessTabs = {self.tabWelcome, self.tabMe, self.tabShout, self.tabRoster, self.tabLeaderWeek, self.tabLeaderLife, self.tabAchievements, self.tabBadges, self.tabHistory, self.tabOptions, self.tabAlt}
  if hasAccess then
    for _, tab in ipairs(accessTabs) do
      if tab then tab:Show() end
    end
  else
    for _, tab in ipairs(accessTabs) do
      if tab then tab:Hide() end
    end
  end

  if self.tabAdmin then
    if hasAccess and LeafVE:IsAdminRank() then
      self.tabAdmin:Show()
    else
      self.tabAdmin:Hide()
      -- Redirect away from admin tab if player lost access
      if self.activeTab == "admin" then
        self.activeTab = hasAccess and "me" or "join"
      end
    end
  end
  
  if self.tabJoin then
    if hasAccess then
      self.tabJoin:Hide()
    else
      self.tabJoin:Show()
    end
  end

  if self.card then
    if hasAccess then
      self.card:Show()
    else
      self.card:Hide()
    end
  end
  
  -- Hide all panels safely
  local panelNames = {"me", "shoutouts", "leaderWeek", "leaderLife", "roster", "history", "badges", "achievements", "options", "admin", "welcome", "join", "alt"}
  for _, name in ipairs(panelNames) do
    if self.panels[name] and self.panels[name].Hide then
      self.panels[name]:Hide()
    end
  end
  
  if not hasAccess then
    if self.panels.join then
      self.panels.join:Show()
    end
    return
  end
  
  -- Show active tab
  if self.activeTab == "me" and self.panels.me then
    self.panels.me:Show()
    local me = ShortName(UnitName("player") or "")
    if not me or me == "" then return end
    
    local day = DayKey()
    local dayT = (LeafVE_DB.global[day] and LeafVE_DB.global[day][me]) or {L = 0, G = 0, S = 0}
    
    if self.panels.me.todayStats then
      self.panels.me.todayStats:SetText(string.format(
        "Login: %d  |  Group: %d  |  Shoutouts: %d  |  |cFFFFD700Total: %d|r",
        dayT.L or 0, dayT.G or 0, dayT.S or 0, (dayT.L or 0) + (dayT.G or 0) + (dayT.S or 0)
      ))
    end
    
    -- Weekly: use higher of local aggregation vs synced lboard data (mirrors RefreshLeaderboard logic)
    local weekAgg = (AggForThisWeek())
    local wk = WeekKey()
    local localWeekT = weekAgg[me]
    local syncedWeekT = LeafVE_DB.lboard.weekly[wk] and LeafVE_DB.lboard.weekly[wk][me]
    local weekT
    if localWeekT and syncedWeekT then
      local localTotal = (localWeekT.L or 0) + (localWeekT.G or 0) + (localWeekT.S or 0)
      local syncedTotal = (syncedWeekT.L or 0) + (syncedWeekT.G or 0) + (syncedWeekT.S or 0)
      weekT = localTotal >= syncedTotal and localWeekT or syncedWeekT
    elseif localWeekT then
      weekT = localWeekT
    else
      weekT = syncedWeekT or {L = 0, G = 0, S = 0}
    end
    if self.panels.me.weekStats then
      self.panels.me.weekStats:SetText(string.format(
        "Login: %d  |  Group: %d  |  Shoutouts: %d  |  |cFFFFD700Total: %d|r",
        weekT.L or 0, weekT.G or 0, weekT.S or 0, (weekT.L or 0) + (weekT.G or 0) + (weekT.S or 0)
      ))
    end
    
    local seasonT = LeafVE_DB.season[me] or {L = 0, G = 0, S = 0}
    if self.panels.me.seasonStats then
      self.panels.me.seasonStats:SetText(string.format(
        "Login: %d  |  Group: %d  |  Shoutouts: %d  |  |cFFFFD700Total: %d|r",
        seasonT.L or 0, seasonT.G or 0, seasonT.S or 0, (seasonT.L or 0) + (seasonT.G or 0) + (seasonT.S or 0)
      ))
    end
    
    -- All-time: use higher of local vs synced lboard data (mirrors RefreshLeaderboard logic)
    local localAlltimeT = LeafVE_DB.alltime[me]
    local syncedAlltimeT = LeafVE_DB.lboard.alltime[me]
    local alltimeT
    if localAlltimeT and syncedAlltimeT then
      local localTotal = (localAlltimeT.L or 0) + (localAlltimeT.G or 0) + (localAlltimeT.S or 0)
      local syncedTotal = (syncedAlltimeT.L or 0) + (syncedAlltimeT.G or 0) + (syncedAlltimeT.S or 0)
      alltimeT = localTotal >= syncedTotal and localAlltimeT or syncedAlltimeT
    elseif localAlltimeT then
      alltimeT = localAlltimeT
    else
      alltimeT = syncedAlltimeT or {L = 0, G = 0, S = 0}
    end
    if self.panels.me.alltimeStats then
      self.panels.me.alltimeStats:SetText(string.format(
        "Login: %d  |  Group: %d  |  Shoutouts: %d  |  |cFFFFD700Total: %d|r",
        alltimeT.L or 0, alltimeT.G or 0, alltimeT.S or 0, (alltimeT.L or 0) + (alltimeT.G or 0) + (alltimeT.S or 0)
      ))
    end
  
    -- Calculate Last Week's Winner
    if self.panels.me.lastWeekWinner then
      local lastWeekStart = WeekStartTS(Now()) - (7 * SECONDS_PER_DAY)
      local lastWeekAgg = {}
      
      for d = 0, 6 do
        local dk = DayKeyFromTS(lastWeekStart + d * SECONDS_PER_DAY)
        if LeafVE_DB.global[dk] then
          for name, t in pairs(LeafVE_DB.global[dk]) do
            if not lastWeekAgg[name] then lastWeekAgg[name] = {L = 0, G = 0, S = 0} end
            lastWeekAgg[name].L = lastWeekAgg[name].L + (t.L or 0)
            lastWeekAgg[name].G = lastWeekAgg[name].G + (t.G or 0)
            lastWeekAgg[name].S = lastWeekAgg[name].S + (t.S or 0)
          end
        end
      end
      
      local winner = nil
      local maxPoints = 0
      for name, pts in pairs(lastWeekAgg) do
        local total = (pts.L or 0) + (pts.G or 0) + (pts.S or 0)
        if total > maxPoints then
          maxPoints = total
          winner = name
        end
      end
      
    if winner then
      self.panels.me.lastWeekWinner:SetText(string.format("%s with |cFFFFD700%d points|r", winner, maxPoints))
    else
      self.panels.me.lastWeekWinner:SetText("|cFF888888No data available|r")
    end
   end
    
    -- Calculate All-Time Leader
    if self.panels.me.alltimeLeader then
      local leader = nil
      local maxPoints = 0
      
      for name, pts in pairs(LeafVE_DB.alltime) do
        local total = (pts.L or 0) + (pts.G or 0) + (pts.S or 0)
        if total > maxPoints then
          maxPoints = total
          leader = name
        end
      end
      
    if leader then
      self.panels.me.alltimeLeader:SetText(string.format("%s with |cFFFFD700%d points|r", leader, maxPoints))
    else
      self.panels.me.alltimeLeader:SetText("|cFF888888No data available|r")
    end
   end

    -- Refresh Season Rewards display
    if self.panels.me.seasonRewards then
      local COIN = "g"
      local r1 = LeafVE_DB.options.seasonReward1 or SEASON_REWARD_1
      local r2 = LeafVE_DB.options.seasonReward2 or SEASON_REWARD_2
      local r3 = LeafVE_DB.options.seasonReward3 or SEASON_REWARD_3
      local r4 = LeafVE_DB.options.seasonReward4 or SEASON_REWARD_4
      local r5 = LeafVE_DB.options.seasonReward5 or SEASON_REWARD_5
      self.panels.me.seasonRewards:SetText(string.format(
        "|cFFFFD7001st: %d%s   3rd: %d%s\n2nd: %d%s   4th: %d%s\n5th: %d%s|r",
        r1, COIN, r3, COIN, r2, COIN, r4, COIN, r5, COIN
      ))
    end

    -- Calculate Week Countdown
    if self.panels.me.weekCountdown then
      local weekStart = WeekStartTS(Now())
      local weekEnd = weekStart + (7 * SECONDS_PER_DAY)
      local timeLeft = weekEnd - Now()
      
    if timeLeft > 0 then
      local days = math.floor(timeLeft / SECONDS_PER_DAY)
      local hours = math.floor((timeLeft - (days * SECONDS_PER_DAY)) / SECONDS_PER_HOUR)
      local minutes = math.floor((timeLeft - (days * SECONDS_PER_DAY) - (hours * SECONDS_PER_HOUR)) / 60)
      
      self.panels.me.weekCountdown:SetText(string.format("|cFFFFD700%dd %dh %dm|r", days, hours, minutes))
    else
      self.panels.me.weekCountdown:SetText("|cFFFF0000Resetting now!|r")
    end
   end

    -- Populate current weekly top 5 standings
    if self.panels.me.weekTopEntries then
      local wk = WeekKey()
      local syncedWeek = LeafVE_DB.lboard.weekly[wk]
      local localWeek = (AggForThisWeek())

      local weekLeaders = {}
      local memberSet = {}
      if LeafVE_DB.persistentRoster then
        for lowerName, info in pairs(LeafVE_DB.persistentRoster) do
          memberSet[lowerName] = info
        end
      end
      for lowerName, info in pairs(LeafVE.guildRosterCache) do
        memberSet[lowerName] = info
      end
      for _, guildInfo in pairs(memberSet) do
        local name = guildInfo.name
        local localPts = localWeek[name]
        local syncedPts = syncedWeek and syncedWeek[name]
        local pts
        if localPts and syncedPts then
          local lTotal = (localPts.L or 0) + (localPts.G or 0) + (localPts.S or 0)
          local sTotal = (syncedPts.L or 0) + (syncedPts.G or 0) + (syncedPts.S or 0)
          pts = lTotal >= sTotal and localPts or syncedPts
        elseif localPts then
          pts = localPts
        else
          pts = syncedPts or {L = 0, G = 0, S = 0}
        end
        local total = (pts.L or 0) + (pts.G or 0) + (pts.S or 0)
        if total > 0 then
          table.insert(weekLeaders, {name = name, total = total})
        end
      end
      table.sort(weekLeaders, function(a, b)
        if a.total == b.total then return Lower(a.name) < Lower(b.name) end
        return a.total > b.total
      end)
      local rankLabels = {"|cFFFFD7001st|r", "|cFFC0C0C02nd|r", "|cFFCD7F323rd|r", "|cFFFFFFFF4th|r", "|cFFFFFFFF5th|r"}
      for i = 1, 5 do
        if self.panels.me.weekTopEntries[i] then
          if weekLeaders[i] then
            self.panels.me.weekTopEntries[i]:SetText(string.format("%s %s - |cFFFFD700%d pts|r", rankLabels[i], weekLeaders[i].name, weekLeaders[i].total))
          else
            self.panels.me.weekTopEntries[i]:SetText(string.format("%s |cFF888888------|r", rankLabels[i]))
          end
        end
      end
    end
  elseif self.activeTab == "shoutouts" and self.panels.shoutouts then
    self.panels.shoutouts:Show()
    local me = ShortName(UnitName("player"))
    if me then
      local today = DayKey()
      if not LeafVE_DB.shoutouts[me] then LeafVE_DB.shoutouts[me] = {} end
      local count = 0
      for tname, timestamp in pairs(LeafVE_DB.shoutouts[me]) do
        if DayKeyFromTS(timestamp) == today then count = count + 1 end
      end
      local remaining = SHOUTOUT_MAX_PER_DAY - count
      if self.panels.shoutouts.usageText then
        self.panels.shoutouts.usageText:SetText(string.format("Shoutouts remaining today: %d / %d", remaining, SHOUTOUT_MAX_PER_DAY))
      end
    end
    self:RefreshShoutoutsPanel()
    
  elseif self.activeTab == "leaderWeek" and self.panels.leaderWeek then
    self.panels.leaderWeek:Show()
    self:RefreshLeaderboard("leaderWeek")
    
  elseif self.activeTab == "leaderLife" and self.panels.leaderLife then
    self.panels.leaderLife:Show()
    self:RefreshLeaderboard("leaderLife")
    
  elseif self.activeTab == "roster" and self.panels.roster then
    self.panels.roster:Show()
    self:RefreshRoster()
    
  elseif self.activeTab == "history" and self.panels.history then
    self.panels.history:Show()
    self:RefreshHistory()
    
  elseif self.activeTab == "badges" and self.panels.badges then
    self.panels.badges:Show()
    
    -- Force refresh after panel is shown
    local badgeRefreshFrame = CreateFrame("Frame")
    badgeRefreshFrame:SetScript("OnUpdate", function()
      self:RefreshBadges()
      badgeRefreshFrame:SetScript("OnUpdate", nil)
    end)
    
  elseif self.activeTab == "achievements" and self.panels.achievements then
    self.panels.achievements:Show()
    self:RefreshAchievementsLeaderboard()

  elseif self.activeTab == "options" and self.panels.options then
    self.panels.options:Show()
    self:RefreshOptions()

  elseif self.activeTab == "admin" and self.panels.admin then
    if LeafVE:IsAdminRank() then
      self.panels.admin:Show()
    else
      -- Redirect non-admins back to "me" tab
      self.activeTab = "me"
      if self.panels.me then self.panels.me:Show() end
    end

  elseif self.activeTab == "welcome" and self.panels.welcome then
    self.panels.welcome:Show()
    self:RefreshWelcome()

  elseif self.activeTab == "alt" and self.panels.alt then
    self.panels.alt:Show()
    -- RefreshAltPanel is called by the OnShow script of the alt panel
  end
end

function LeafVE.UI:RefreshWelcome()
  EnsureDB()
  local p = self.panels.welcome
  if not p then return end
  local opts = LeafVE_DB.options
  local soPts  = (opts and opts.shoutoutPoints) or 10
  local soMax  = (opts and opts.shoutoutMaxDaily) or SHOUTOUT_MAX_PER_DAY
  if p.welcomeLoginLine then
    p.welcomeLoginLine:SetText("|cFFFFD700Daily Login|r  (+20 LP)")
  end
  if p.welcomeGroupHeader then
    p.welcomeGroupHeader:SetText("|cFFFFD700Group Time|r  (+10 LP per online guildie every 20 minutes (cap: 700/day))")
  end
  if p.welcomeGroupDetail then
    p.welcomeGroupDetail:SetText("Spend time in a party or raid with online guildmates. Earn 10 LP")
  end
  if p.welcomeSOHeader then
    p.welcomeSOHeader:SetText(string.format("|cFFFFD700Shoutouts|r  (+%d LP each)", soPts))
  end
  if p.welcomeSODetail1 then
    p.welcomeSODetail1:SetText(string.format("earn %d LP. Use |cFF00CCFF/so PlayerName [reason]|r. You have", soPts))
  end
  if p.welcomeSODetail2 then
    p.welcomeSODetail2:SetText(string.format("%d shoutouts per day, so spend them wisely!", soMax))
  end
  if p.welcomeInstHeader then
    p.welcomeInstHeader:SetText("|cFFFFD700Instance Runs|r  (+10 dungeon boss, +25 raid boss | +10 dungeon complete, +25 raid complete)")
  end
  if p.welcomeInstDetail then
    p.welcomeInstDetail:SetText("plus a flat completion bonus. Boss and completion points are separate.")
  end
  if p.welcomeQuestHeader then
    p.welcomeQuestHeader:SetText("|cFFFFD700Quest Completions|r  (+10 LP, no daily cap)")
  end
  if p.welcomeQuestDetail1 then
    p.welcomeQuestDetail1:SetText("Turn in quests while grouped with a guildmate to earn 10 LP each.")
  end
  if p.welcomeQuestDetail2 then
    p.welcomeQuestDetail2:SetText("No daily cap — every mission matters!")
  end
end

-------------------------------------------------
-- ERROR TRACKING SYSTEM
-------------------------------------------------
local function LogError(errorMsg, source)
  local timestamp = Now()
  local errorEntry = {
    message = errorMsg,
    source = source or "Unknown",
    timestamp = timestamp,
    dateStr = date("%m/%d %H:%M:%S", timestamp)
  }
  
  table.insert(LeafVE.errorLog, errorEntry)
  
  while table.getn(LeafVE.errorLog) > LeafVE.maxErrors do
    table.remove(LeafVE.errorLog, 1)
  end
end


-------------------------------------------------
-- EVENT HANDLERS
-------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("CHAT_MSG_ADDON")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("GUILD_ROSTER_UPDATE")
ef:RegisterEvent("PARTY_MEMBERS_CHANGED")
ef:RegisterEvent("RAID_ROSTER_UPDATE")
ef:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ef:RegisterEvent("QUEST_LOG_UPDATE")
ef:RegisterEvent("QUEST_COMPLETE")
ef:RegisterEvent("QUEST_FINISHED")
ef:RegisterEvent("PLAYER_REGEN_DISABLED")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
ef:RegisterEvent("PLAYER_TARGET_CHANGED")
ef:RegisterEvent("LOOT_OPENED")
ef:RegisterEvent("CHAT_MSG_SAY")
ef:RegisterEvent("CHAT_MSG_PARTY")
ef:RegisterEvent("CHAT_MSG_GUILD")
ef:RegisterEvent("CHAT_MSG_WHISPER")
ef:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
ef:RegisterEvent("UNIT_INVENTORY_CHANGED")
ef:RegisterEvent("CHARACTER_POINTS_CHANGED")
ef:RegisterEvent("PLAYER_AURAS_CHANGED")
ef:RegisterEvent("CHAT_MSG_SKILL")

local groupCheckTimer = 0
local notificationTimer = 0
local attendanceTimer = 0
local badgeSyncTimer = 0
local achLeaderTimer = 0

ef:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == LeafVE.name then
    EnsureDB()
    
    -- Register addon message prefixes
    if RegisterAddonMessagePrefix then
      RegisterAddonMessagePrefix("LeafVE")
      RegisterAddonMessagePrefix("LeafVEAch")
      RegisterAddonMessagePrefix("LVL")
      Print("Registered addon message prefixes")
    else
      Print("Warning: RegisterAddonMessagePrefix not available!")
    end
    
    LeafVE:CreateMinimapButton()
    Print("Addon loaded v"..LeafVE.version.."! Use /lve or /leaf to open")
    return
  end
  
  if event == "PLAYER_LOGIN" then
    Print("Loaded v"..LeafVE.version)
    EnsureDB()
    LeafVE:RecordActivity()
    -- Initialise BCS scan dirty flags so stats are computed on first tab open
    if BCS then
      BCS.needScanGear     = true
      BCS.needScanTalents  = true
      BCS.needScanAuras    = true
      BCS.needScanSkills   = true
    end
    -- One-time migration: purge old "Quest area trigger" history entries
    if not LeafVE_DB.migratedTriggerHistory then
      EnsureDB()
      for pName, entries in pairs(LeafVE_DB.pointHistory) do
        if type(entries) == "table" then
          local filtered = {}
          for _, entry in ipairs(entries) do
            local reason = entry.reason or ""
            local isTrigger = string.find(reason, "Quest area trigger") or string.find(reason, "trigger %d+")
            if not isTrigger then
              table.insert(filtered, entry)
            end
          end
          LeafVE_DB.pointHistory[pName] = filtered
        end
      end
      LeafVE_DB.migratedTriggerHistory = true
    end
    -- One-time migration: wipe old shoutout data and migrate to V2
    if not LeafVE_DB.shoutouts_v2_migrated then
      LeafVE_DB.shoutouts = {}
      LeafVE_DB.shoutouts_v2_migrated = true
    end
    -- Check guild info bulletin for a pending guild-wide wipe (Feature E: offline catch-up)
    LVL_CheckGuildWipeBulletin()
    LeafVE:CheckDailyLogin()
    LeafVE:PurgeStaleWeeklyData()
    -- Seed the quest log cache so we can diff on the first QUEST_LOG_UPDATE
    LeafVE:CacheQuestLog()
    -- Register badge hyperlink handler last so it wraps any other addon's hook
    LeafVE:RegisterBadgeHyperlinkHandler()

    -- Broadcast after 5 seconds
    local broadcastTimer = 0
    local broadcastFrame = CreateFrame("Frame")
    broadcastFrame:SetScript("OnUpdate", function()
      broadcastTimer = broadcastTimer + arg1
      if broadcastTimer >= 5 then
        if InGuild() then
          -- Request version info from all online guild members so we can
          -- enforce minCompatVersion when their data messages arrive.
          LeafVE.versionResponses = {}
          SendAddonMessage("LeafVE", "VERSIONREQ", "GUILD")
          LeafVE:BroadcastBadges()
          LeafVE:BroadcastBadgeProgress()
          LeafVE:BroadcastLeaderboardData()
          
          local bme = ShortName(UnitName("player"))
          if bme and LeafVE_GlobalDB.playerNotes and LeafVE_GlobalDB.playerNotes[bme] then
            LeafVE:BroadcastPlayerNote(LeafVE_GlobalDB.playerNotes[bme])
          end
          -- Broadcast gear so guildmates can cache it
          LeafVE.lastGearBroadcast = 0  -- bypass throttle for login broadcast
          LeafVE:BroadcastMyGear()
          -- Broadcast BCS stats so guildmates can display them
          LeafVE.lastStatsBroadcast = 0  -- bypass throttle for login broadcast
          LeafVE:BroadcastMyStats()
        end
        broadcastFrame:SetScript("OnUpdate", nil)
      end
    end)
    return
  end
  
  if event == "CHAT_MSG_ADDON" then
    LeafVE:OnAddonMessage(arg1, arg2, arg3, arg4)
    return
  end
  
  if event == "GUILD_ROSTER_UPDATE" then
    -- Invalidate the roster cache so the next GetGroupGuildies() call rebuilds it
    -- from the fresh server data (without triggering another GuildRoster() request).
    LeafVE.guildRosterCacheTime = 0
    -- Check guild bulletin for pending wipe (Feature E: offline catch-up on roster update)
    LVL_CheckGuildWipeBulletin()
    return
  end

  if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
    LeafVE:OnGroupUpdate()
    return
  end

  if event == "ZONE_CHANGED_NEW_AREA" then
    LeafVE:RecordActivity()
    LeafVE:OnZoneChanged()
    return
  end

  if event == "QUEST_LOG_UPDATE" then
    -- Keep the cache fresh; turn-in detection is handled by QUEST_COMPLETE + QUEST_FINISHED.
    LeafVE:CacheQuestLog()
    return
  end

  if event == "QUEST_COMPLETE" then
    -- Dialog opened: player is about to turn in a quest. Capture the title now.
    LeafVE.pendingQuestTurnIn = GetTitleText and GetTitleText() or nil
    return
  end

  if event == "QUEST_FINISHED" then
    -- Dialog closed. If we captured a title from QUEST_COMPLETE, this is a real turn-in.
    if LeafVE.pendingQuestTurnIn and LeafVE.pendingQuestTurnIn ~= "" then
      LeafVE:OnQuestTurnedIn()
    end
    -- Always clear; covers both successful turn-ins and dialog cancellations.
    LeafVE.pendingQuestTurnIn = nil
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    LeafVE.lastCombatAt = Now()
    LeafVE:RecordActivity()
    return
  end

  if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_TARGET_CHANGED"
     or event == "LOOT_OPENED" or event == "CHAT_MSG_SAY"
     or event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_GUILD"
     or event == "CHAT_MSG_WHISPER" then
    LeafVE:RecordActivity()
    return
  end

  if event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
    LeafVE:OnBossKillChat(arg1 or "")
    return
  end

  if event == "UNIT_INVENTORY_CHANGED" then
    if arg1 == "player" then
      LeafVE:BroadcastMyGear()
      -- Debounce BCS gear scan (200 ms, same as standalone BCS addon)
      if BCS then
        LeafVE.bcsInventoryDebounceTimer   = 0.2
        LeafVE.bcsInventoryDebouncePending = true
        LeafVE.statsBroadcastPending       = true
      end
    end
    return
  end

  if event == "CHARACTER_POINTS_CHANGED" then
    if BCS then BCS.needScanTalents = true end
    return
  end

  if event == "PLAYER_AURAS_CHANGED" then
    if BCS then BCS.needScanAuras = true end
    return
  end

  if event == "CHAT_MSG_SKILL" then
    if BCS then BCS.needScanSkills = true end
    return
  end
end)

local updateFrame = CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", function()
  groupCheckTimer = groupCheckTimer + arg1
  notificationTimer = notificationTimer + arg1
  attendanceTimer = attendanceTimer + arg1
  badgeSyncTimer = badgeSyncTimer + arg1
  achLeaderTimer = achLeaderTimer + arg1

  -- BCS inventory debounce: coalesce rapid gear-change events into one scan
  if BCS and LeafVE.bcsInventoryDebouncePending then
    LeafVE.bcsInventoryDebounceTimer = LeafVE.bcsInventoryDebounceTimer - arg1
    if LeafVE.bcsInventoryDebounceTimer <= 0 then
      LeafVE.bcsInventoryDebouncePending = false
      BCS.needScanGear   = true
      BCS.needScanSkills = true
      -- Broadcast updated BCS stats after gear debounce settles
      if LeafVE.statsBroadcastPending then
        LeafVE.statsBroadcastPending = false
        LeafVE:BroadcastMyStats()
      end
    end
  end

  if groupCheckTimer >= 30 then
    groupCheckTimer = 0
    LeafVE:OnGroupUpdate()
  end
  
  if notificationTimer >= 0.1 then
    notificationTimer = 0
    LeafVE:ProcessNotifications()
  end
  
  if attendanceTimer >= 300 then
    attendanceTimer = 0
    LeafVE:TrackAttendance()
  end
  
  -- Sync badges every 5 minutes
  if badgeSyncTimer >= 300 then
    badgeSyncTimer = 0
    if InGuild() then
      LeafVE:BroadcastBadges()
      LeafVE:BroadcastLeaderboardData()
    end
  end

  -- Achievement leaderboard auto-refresh every 5 minutes
  if achLeaderTimer >= 300 then
    achLeaderTimer = 0
    -- Request a leaderboard resync from the guild (respects cooldown)
    if InGuild() then
      local now = Now()
      if (now - LeafVE.lastResyncRequestAt) >= LBOARD_RESYNC_COOLDOWN then
        LeafVE.lastResyncRequestAt = now
        LeafVE:SendResyncRequest()
      end
    end
    -- Refresh the achievement leaderboard panel if it is currently open
    if LeafVE.UI and LeafVE.UI.panels and
       LeafVE.UI.panels.achievements and LeafVE.UI.panels.achievements:IsVisible() then
      LeafVE.UI:RefreshAchievementsLeaderboard()
    end
  end
end)

-------------------------------------------------
-- SLASH COMMANDS
-------------------------------------------------

SLASH_LBOARDSYNC1 = "/lboardsync"
SlashCmdList["LBOARDSYNC"] = function()
  LeafVE:BroadcastLeaderboardData()
  Print("Broadcasting leaderboard data to guild...")
end

SLASH_LBOARDREQ1 = "/lboardreq"
SlashCmdList["LBOARDREQ"] = function()
  LeafVE.lastResyncRequestAt = 0  -- bypass cooldown for manual request
  LeafVE:SendResyncRequest()
  Print("Sent leaderboard resync request to guild.")
end

SLASH_NOTESYNC1 = "/notesync"
SlashCmdList["NOTESYNC"] = function()
  local me = ShortName(UnitName("player"))
  if me and LeafVE_GlobalDB.playerNotes and LeafVE_GlobalDB.playerNotes[me] then
    LeafVE:BroadcastPlayerNote(LeafVE_GlobalDB.playerNotes[me])
    Print("Broadcasting player note to guild...")
  else
    Print("You don't have a player note set!")
  end
end

SLASH_BADGESYNC1 = "/badgesync"
SlashCmdList["BADGESYNC"] = function()
  LeafVE:BroadcastBadges()
  Print("Broadcasting badges to guild...")
end

SLASH_SHOUTSYNC1 = "/shoutsync"
SlashCmdList["SHOUTSYNC"] = function()
  LeafVE.lastShoutSyncRespondAt = 0  -- bypass cooldown for manual broadcast
  LeafVE:BroadcastShoutoutHistory()
  Print("Broadcasting shoutout history to guild...")
end

SLASH_LEAFVE1 = "/lve"
SlashCmdList["LEAFVE"] = function(msg)
  local trimmedMsg = Trim(Lower(msg or ""))
  
  if trimmedMsg == "bigger" or trimmedMsg == "taller" then
    EnsureDB()
    LeafVE_DB.ui.h = (LeafVE_DB.ui.h or 700) + 50
    if LeafVE_DB.ui.h > 1000 then LeafVE_DB.ui.h = 1000 end
    Print("Height increased to: "..LeafVE_DB.ui.h)
    if LeafVE.UI and LeafVE.UI.frame then
      LeafVE.UI.frame:Hide()
      LeafVE.UI.frame = nil
      LeafVE.UI.panels = nil
      LeafVE.UI.card = nil
    end
    LeafVE.UI = { activeTab = "me" }
    LeafVE:ToggleUI()
    
  elseif trimmedMsg == "smaller" or trimmedMsg == "shorter" then
    EnsureDB()
    LeafVE_DB.ui.h = (LeafVE_DB.ui.h or 700) - 50
    if LeafVE_DB.ui.h < 600 then LeafVE_DB.ui.h = 600 end
    Print("Height decreased to: "..LeafVE_DB.ui.h)
    if LeafVE.UI and LeafVE.UI.frame then
      LeafVE.UI.frame:Hide()
      LeafVE.UI.frame = nil
      LeafVE.UI.panels = nil
      LeafVE.UI.card = nil
    end
    LeafVE.UI = { activeTab = "me" }
    LeafVE:ToggleUI()
    
  elseif trimmedMsg == "wider" then
    EnsureDB()
    LeafVE_DB.ui.w = (LeafVE_DB.ui.w or 1050) + 50
    if LeafVE_DB.ui.w > 1400 then LeafVE_DB.ui.w = 1400 end
    Print("Width increased to: "..LeafVE_DB.ui.w)
    if LeafVE.UI and LeafVE.UI.frame then
      LeafVE.UI.frame:Hide()
      LeafVE.UI.frame = nil
      LeafVE.UI.panels = nil
      LeafVE.UI.card = nil
    end
    LeafVE.UI = { activeTab = "me" }
    LeafVE:ToggleUI()
    
  elseif trimmedMsg == "narrower" then
    EnsureDB()
    LeafVE_DB.ui.w = (LeafVE_DB.ui.w or 1050) - 50
    if LeafVE_DB.ui.w < 950 then LeafVE_DB.ui.w = 950 end
    Print("Width decreased to: "..LeafVE_DB.ui.w)
    if LeafVE.UI and LeafVE.UI.frame then
      LeafVE.UI.frame:Hide()
      LeafVE.UI.frame = nil
      LeafVE.UI.panels = nil
      LeafVE.UI.card = nil
    end
    LeafVE.UI = { activeTab = "me" }
    LeafVE:ToggleUI()
    
  elseif trimmedMsg == "reset" then
    EnsureDB()
    LeafVE_DB.ui.w = 1050
    LeafVE_DB.ui.h = 700
    Print("UI size reset to default!")
    if LeafVE.UI and LeafVE.UI.frame then
      LeafVE.UI.frame:Hide()
      LeafVE.UI.frame = nil
      LeafVE.UI.panels = nil
      LeafVE.UI.card = nil
    end
    LeafVE.UI = { activeTab = "me" }
    LeafVE:ToggleUI()

  elseif string.sub(trimmedMsg, 1, 6) == "shout " then
    -- /lve shout <name>  (Shoutout V2 slash command)
    local targetName = Trim(string.sub(msg, 7))
    if not targetName or targetName == "" then
      Print("Usage: /lve shout PlayerName")
    else
      EnsureDB()
      local myKey = LVL_GetCharKey()
      local targetKey = ShortName(targetName) or targetName
      LVL_AwardShoutout(myKey, targetKey)
    end

  elseif string.sub(trimmedMsg, 1, 11) == "altapprove " then
    -- /lve altapprove altKey mainKey  (officer approves a link request)
    if not LeafVE:IsAdminRank() then
      Print("|cFFFF4444You must be an officer to approve alt links.|r")
    else
      local rest = Trim(string.sub(msg, 12))
      local spacePos = string.find(rest, " ")
      if not spacePos then
        Print("Usage: /lve altapprove <altName> <mainName>")
      else
        local altKey = Trim(string.sub(rest, 1, spacePos - 1))
        local mainKey = Trim(string.sub(rest, spacePos + 1))
        EnsureDB()
        LeafVE_DB.links[altKey] = mainKey
        LeafVE_DB.lastLinkChange[altKey] = Now()
        if LeafVE_DB.pendingMerge then LeafVE_DB.pendingMerge[altKey] = nil end
        if InGuild() then
          SendAddonMessage("LVL", "MERGE_APPROVE|" .. altKey .. "|" .. mainKey, "GUILD")
        end
        Print(string.format("|cff00ff00[LVL]|r Approved: %s linked to %s. Broadcast sent.", altKey, mainKey))
      end
    end

  else
    LeafVE:ToggleUI()
  end
end

SLASH_LEAFSHOUTOUT1 = "/shoutout"
SLASH_LEAFSHOUTOUT2 = "/so"
SlashCmdList["LEAFSHOUTOUT"] = function(msg)
  if not msg or msg == "" then
    Print("Usage: /shoutout PlayerName [reason]")
    return
  end
  
  local playerName, reason = string.match(msg, "^(%S+)%s*(.*)$")
  
  if playerName then
    LeafVE:GiveShoutout(playerName, reason)
  end
end

SLASH_RESETSHOUTOUTS1 = "/resetshoutouts"
SlashCmdList["RESETSHOUTOUTS"] = function()
  EnsureDB()
  local me = ShortName(UnitName("player"))
  if not me then Print("Error: Could not determine player name") return end
  LeafVE_DB.shoutouts[me] = {}
  Print("Your shoutout limits have been reset!")
end

SLASH_LEAFBADGES1 = "/lvebadges"
SlashCmdList["LEAFBADGES"] = function()
  local me = ShortName(UnitName("player"))
  if not me then return end
  
  local badges = LeafVE:GetPlayerBadges(me)
  Print(string.format("You have earned %d badge%s:", table.getn(badges), table.getn(badges) ~= 1 and "s" or ""))
  
  for i = 1, table.getn(badges) do
    Print("  - "..badges[i].badge.name..": "..badges[i].badge.desc)
  end
end

SLASH_LEAFDEBUG1 = "/lvedebug"
SlashCmdList["LEAFDEBUG"] = function(msg)
  if msg == "login" then
    LeafVE:CheckDailyLogin()
    
  elseif msg == "group" then
    LeafVE:OnGroupUpdate()
    
  elseif msg == "points" then
    local me = ShortName(UnitName("player"))
    local day = DayKey()
    local dayT = (LeafVE_DB.global[day] and LeafVE_DB.global[day][me]) or {L = 0, G = 0, S = 0}
    Print(string.format("Today: L:%d G:%d S:%d | Total: %d", dayT.L, dayT.G, dayT.S, (dayT.L + dayT.G + dayT.S)))
    
    local allT = LeafVE_DB.alltime[me] or {L = 0, G = 0, S = 0}
    Print(string.format("All-Time: L:%d G:%d S:%d | Total: %d", allT.L, allT.G, allT.S, (allT.L + allT.G + allT.S)))
    
  elseif msg == "shoutouts" then
    local me = ShortName(UnitName("player"))
    local today = DayKey()
    if not LeafVE_DB.shoutouts[me] then LeafVE_DB.shoutouts[me] = {} end
    local count = 0
    for tname, timestamp in pairs(LeafVE_DB.shoutouts[me]) do
      if DayKeyFromTS(timestamp) == today then count = count + 1 end
    end
    Print(string.format("Shoutouts used today: %d / %d", count, SHOUTOUT_MAX_PER_DAY))
    
  elseif msg == "quest" then
    local me = ShortName(UnitName("player"))
    if not me then return end
    EnsureDB()
    local today = DayKey()
    if not LeafVE_DB.questTracking[me] then LeafVE_DB.questTracking[me] = {} end
    if not LeafVE_DB.questTracking[me][today] then LeafVE_DB.questTracking[me][today] = 0 end
    local questCap = (LeafVE_DB.options and LeafVE_DB.options.questMaxDaily) or QUEST_MAX_DAILY
    local questPts = (LeafVE_DB.options and LeafVE_DB.options.questPoints) or QUEST_POINTS
    if questCap ~= 0 and LeafVE_DB.questTracking[me][today] >= questCap then
      Print(string.format("Quest LP test: already at daily cap (%d/%s)", LeafVE_DB.questTracking[me][today], questCap == 0 and "unlimited" or tostring(questCap)))
    else
      local awarded = LeafVE:AddPoints(me, "G", questPts)
      if awarded and awarded > 0 then
        LeafVE_DB.questTracking[me][today] = LeafVE_DB.questTracking[me][today] + 1
        LeafVE:AddToHistory(me, "G", awarded, "Quest completion (debug test)")
        Print(string.format("Quest LP test: +%d G awarded (%d/%s today)", awarded, LeafVE_DB.questTracking[me][today], questCap == 0 and "unlimited" or tostring(questCap)))
      end
    end
    
  elseif msg == "notify" then
    LeafVE:ShowNotification("Test Notification", "This is a test message!", LEAF_EMBLEM, THEME.gold)
    
  elseif msg == "badges" then
    local me = ShortName(UnitName("player"))
    Print("Checking all badge milestones...")
    LeafVE:CheckBadgeMilestones(me)
    
  elseif msg == "attendance" then
    LeafVE:TrackAttendance()
    Print("Attendance tracked!")
    
  elseif msg == "history" then
    local me = ShortName(UnitName("player"))
    local history = LeafVE:GetHistory(me, 5)
    Print("Last 5 history entries:")
    for i = 1, table.getn(history) do
      local entry = history[i]
      Print(string.format("  %s: +%d %s - %s", date("%m/%d %H:%M", entry.timestamp), entry.amount, entry.type, entry.reason))
    end
    
  elseif msg == "populate" then
    Print("Manually populating persistent roster from online members...")
    LeafVE:UpdateGuildRosterCache()
    
    local count = 0
    if LeafVE_DB.persistentRoster then
      for _ in pairs(LeafVE_DB.persistentRoster) do count = count + 1 end
    end
    
    Print("Persistent roster now has: "..count.." members")
    Print("These members will show even when offline.")
    
    if LeafVE.UI and LeafVE.UI.RefreshRoster then
      LeafVE.UI:RefreshRoster()
    end
    
  elseif msg == "errors" then
    if table.getn(LeafVE.errorLog) == 0 then
      Print("|cFF00FF00No errors logged!|r")
    else
      Print("|cFFFFD700=== ERROR LOG ===|r")
      Print(string.format("Total errors: %d (showing last %d)", table.getn(LeafVE.errorLog), math.min(10, table.getn(LeafVE.errorLog))))
      
      local startIdx = math.max(1, table.getn(LeafVE.errorLog) - 9)
      for i = startIdx, table.getn(LeafVE.errorLog) do
        local err = LeafVE.errorLog[i]
        Print(string.format("|cFFFF0000[%s]|r %s", err.dateStr, err.source))
        Print("|cFFAAAAAA  "..err.message.."|r")
      end
      Print("|cFFFFD700=================|r")
    end
    
  elseif msg == "clearerrors" then
    LeafVE.errorLog = {}
    Print("|cFF00FF00Error log cleared!|r")
    
  elseif msg == "ui" then
    Print("=== UI DEBUG INFO ===")
    if LeafVE.UI then
      Print("LeafVE.UI: EXISTS")
      Print("LeafVE.UI.frame: "..(LeafVE.UI.frame and "EXISTS" or "NIL"))
      Print("LeafVE.UI.Build: "..(LeafVE.UI.Build and "EXISTS" or "NIL"))
      Print("LeafVE.UI.Refresh: "..(LeafVE.UI.Refresh and "EXISTS" or "NIL"))
      Print("LeafVE.UI.activeTab: "..(LeafVE.UI.activeTab or "NIL"))
      
      if LeafVE.UI.panels then
        Print("Panels:")
        for name, panel in pairs(LeafVE.UI.panels) do
          local visible = panel:IsVisible() and "VISIBLE" or "HIDDEN"
          Print("  "..name..": "..visible)
        end
      else
        Print("Panels: NIL")
      end
    else
      Print("LeafVE.UI: NIL")
    end
    Print("====================")
    
  elseif msg == "reload" then
    Print("Reloading UI...")
    if LeafVE.UI and LeafVE.UI.frame then
      LeafVE.UI.frame:Hide()
      LeafVE.UI.frame = nil
      LeafVE.UI.panels = nil
      LeafVE.UI.card = nil
    end
    LeafVE.UI = { activeTab = "me" }
    Print("UI reset! Use /lve to rebuild.")
    
  elseif msg == "db" then
    Print("=== DATABASE INFO ===")
    Print("LeafVE_DB: "..(LeafVE_DB and "EXISTS" or "NIL"))
    if LeafVE_DB then
      local dayCount = 0
      if LeafVE_DB.global then
        for _ in pairs(LeafVE_DB.global) do dayCount = dayCount + 1 end
      end
      Print("  global: "..dayCount.." days")
      Print("  alltime: "..(LeafVE_DB.alltime and "EXISTS" or "NIL"))
      Print("  season: "..(LeafVE_DB.season and "EXISTS" or "NIL"))
      Print("  shoutouts: "..(LeafVE_DB.shoutouts and "EXISTS" or "NIL"))
      Print("  badges: "..(LeafVE_DB.badges and "EXISTS" or "NIL"))
      
      local rosterCount = 0
      if LeafVE_DB.persistentRoster then
        for _ in pairs(LeafVE_DB.persistentRoster) do rosterCount = rosterCount + 1 end
      end
      Print("  persistentRoster: "..rosterCount.." members")
    end
    Print("LeafVE_GlobalDB: "..(LeafVE_GlobalDB and "EXISTS" or "NIL"))
    if LeafVE_GlobalDB then
      Print("  achievementCache: "..(LeafVE_GlobalDB.achievementCache and "EXISTS" or "NIL"))
      Print("  playerNotes: "..(LeafVE_GlobalDB.playerNotes and "EXISTS" or "NIL"))
    end
    Print("=====================")
    
  elseif msg == "guild" then
    Print("=== GUILD CACHE INFO ===")
    Print("InGuild: "..(InGuild() and "YES" or "NO"))
    local cacheCount = 0
    for _ in pairs(LeafVE.guildRosterCache) do cacheCount = cacheCount + 1 end
    Print("Cache size: "..cacheCount)
    Print("Cache age: "..(Now() - LeafVE.guildRosterCacheTime).." seconds")
    
    local onlineCount = 0
    local offlineCount = 0
    for _, info in pairs(LeafVE.guildRosterCache) do
      if info.online then 
        onlineCount = onlineCount + 1 
      else
        offlineCount = offlineCount + 1
      end
    end
    Print("Online members: "..onlineCount)
    Print("Offline members: "..offlineCount)
    
    local persistentCount = 0
    if LeafVE_DB.persistentRoster then
      for _ in pairs(LeafVE_DB.persistentRoster) do persistentCount = persistentCount + 1 end
    end
    Print("Persistent roster: "..persistentCount.." members")
    Print("========================")
    
  elseif msg == "test" then
    Print("=== RUNNING TESTS ===")
    
    Print("Test 1: Core functions")
    Print("  LeafVE:ToggleUI: "..(LeafVE.ToggleUI and "PASS" or "FAIL"))
    Print("  LeafVE:AddPoints: "..(LeafVE.AddPoints and "PASS" or "FAIL"))
    Print("  LeafVE:GiveShoutout: "..(LeafVE.GiveShoutout and "PASS" or "FAIL"))
    
    Print("Test 2: UI structure")
    Print("  LeafVE.UI: "..(LeafVE.UI and "PASS" or "FAIL"))
    Print("  LeafVE.UI.Build: "..(LeafVE.UI and LeafVE.UI.Build and "PASS" or "FAIL"))
    Print("  LeafVE.UI.Refresh: "..(LeafVE.UI and LeafVE.UI.Refresh and "PASS" or "FAIL"))
    
    Print("Test 3: Database")
    EnsureDB()
    Print("  LeafVE_DB: "..(LeafVE_DB and "PASS" or "FAIL"))
    Print("  LeafVE_DB.global: "..(LeafVE_DB.global and "PASS" or "FAIL"))
    Print("  LeafVE_DB.alltime: "..(LeafVE_DB.alltime and "PASS" or "FAIL"))
    Print("  LeafVE_DB.persistentRoster: "..(LeafVE_DB.persistentRoster and "PASS" or "FAIL"))
    
    Print("Test 4: Player info")
    local me = ShortName(UnitName("player"))
    Print("  Player name: "..(me or "FAIL"))
    local guildInfo = LeafVE:GetGuildInfo(me)
    Print("  Guild info: "..(guildInfo and "PASS" or "FAIL"))
    
    Print("Test 5: Achievement title")
    if LeafVE_AchTest_DB and LeafVE_AchTest_DB[me] then
      local title = LeafVE_AchTest_DB[me].equippedTitle
      Print("  Equipped title: "..(title or "NONE"))
    else
      Print("  Achievement addon: NOT LOADED")
    end
    
    Print("Test 6: Quest turn-in guild detection")
    Print("  LeafVE:GetGroupGuildies: "..(LeafVE.GetGroupGuildies and "PASS" or "FAIL"))
    Print("  LeafVE:OnQuestTurnedIn: "..(LeafVE.OnQuestTurnedIn and "PASS" or "FAIL"))
    Print("  LeafVE.guildRosterCache: "..(LeafVE.guildRosterCache and "PASS" or "FAIL"))
    Print("  LeafVE_DB.questTracking: "..(LeafVE_DB and LeafVE_DB.questTracking and "PASS" or "FAIL"))
    
    Print("Test 7: Quest log integration")
    local logCount = 0
    for _ in pairs(LeafVE.questLogCache) do logCount = logCount + 1 end
    Print("  Cached quest log entries: "..logCount)
    local compCount = 0
    if LeafVE_DB.questCompletions and LeafVE_DB.questCompletions[me] then
      for _ in pairs(LeafVE_DB.questCompletions[me]) do compCount = compCount + 1 end
    end
    Print("  Quests with LP awarded (lifetime): "..compCount)
    
    Print("=====================")
    
  else
    Print("=== DEBUG COMMANDS ===")
    Print("/lvedebug login - Test login point award")
    Print("/lvedebug group - Test group point check")
    Print("/lvedebug quest - Test quest LP award (bypasses guild-group check)")
    Print("/lvedebug points - Show current points")
    Print("/lvedebug shoutouts - Show shoutout usage")
    Print("/lvedebug notify - Test notification")
    Print("/lvedebug badges - Check badge milestones")
    Print("/lvedebug attendance - Track attendance")
    Print("/lvedebug history - Show point history")
    Print("/lvedebug populate - Populate roster from online")
    Print("|cFFFFD700/lvedebug errors|r - Show error log")
    Print("|cFFFFD700/lvedebug clearerrors|r - Clear error log")
    Print("/lvedebug ui - Show UI debug info")
    Print("/lvedebug reload - Reset and reload UI")
    Print("/lvedebug db - Show database info")
    Print("/lvedebug guild - Show guild cache info")
    Print("/lvedebug test - Run all tests")
    Print("======================")
  end
end

-------------------------------------------------
-- BADGE HYPERLINK HANDLER
-- Registered at PLAYER_LOGIN so our hook wraps any other addon's
-- SetItemRef override (e.g. AtlasLoot) regardless of load order.
-- Intercepts |Hleafve_badge:id|h[Name]|h clicks in chat
-- and shows a stationary info panel at the bottom of the screen.
-------------------------------------------------

-- Lazily-created stationary badge info panel shown at the bottom of the screen.
local function GetOrCreateBadgeInfoPanel()
  if LeafVE._badgeInfoPanel then return LeafVE._badgeInfoPanel end

  local f = CreateFrame("Frame", "LeafVEBadgeInfoPanel", UIParent)
  f:SetWidth(380)
  f:SetHeight(110)
  f:SetFrameStrata("DIALOG")
  f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 30)
  f:EnableMouse(true)
  f:Hide()

  f:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  f:SetBackdropColor(THEME.bg[1], THEME.bg[2], THEME.bg[3], THEME.bg[4])
  f:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)

  -- Badge icon
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetWidth(48)
  icon:SetHeight(48)
  icon:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
  f.icon = icon

  -- Badge name
  local nameFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  nameFS:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  nameFS:SetPoint("RIGHT", f, "RIGHT", -36, 0)
  nameFS:SetJustifyH("LEFT")
  f.nameFS = nameFS

  -- Quality label
  local qualityFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  qualityFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -3)
  f.qualityFS = qualityFS

  -- Description
  local descFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  descFS:SetPoint("TOPLEFT", qualityFS, "BOTTOMLEFT", 0, -4)
  descFS:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  descFS:SetJustifyH("LEFT")
  f.descFS = descFS

  -- Close (X) button
  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  LeafVE._badgeInfoPanel = f
  return f
end

function LeafVE:RegisterBadgeHyperlinkHandler()
  local _origSetItemRef = SetItemRef
  SetItemRef = function(link, text, button)
    local badgeId = string.match(link, "^leafve_badge:(.+)$")
    if badgeId then
      -- Look up the badge definition
      local badge = nil
      for i = 1, table.getn(BADGES) do
        if BADGES[i].id == badgeId then badge = BADGES[i] break end
      end
      if badge then
        local quality = badge.quality or BADGE_QUALITY.COMMON
        local qr, qg, qb = GetBadgeQualityColor(quality)
        local panel = GetOrCreateBadgeInfoPanel()

        -- Populate icon
        if badge.icon then
          panel.icon:SetTexture(badge.icon)
          panel.icon:Show()
        else
          panel.icon:Hide()
        end

        -- Populate text fields
        panel.nameFS:SetText(badge.name)
        panel.nameFS:SetTextColor(qr, qg, qb)
        panel.qualityFS:SetText("|cFF888888"..GetBadgeQualityLabel(quality).."|r")
        panel.descFS:SetText(badge.desc)

        -- Resize to fit content (24 = top padding + icon top offset, 20 = bottom padding)
        local neededHeight = 24 + panel.nameFS:GetHeight() + panel.qualityFS:GetHeight() + panel.descFS:GetHeight() + 20
        if neededHeight < 80 then neededHeight = 80 end
        panel:SetHeight(neededHeight)

        panel:Show()
      end
      return
    end

    -- Handle achievement hyperlinks — same panel, populated with achievement data
    local achId = string.match(link, "^leafve_ach:(.+)$")
    if achId then
      local achData = LeafVE_AchTest and LeafVE_AchTest.GetAchievementMeta and
                      LeafVE_AchTest.GetAchievementMeta(achId)
      if achData then
        local panel = GetOrCreateBadgeInfoPanel()

        if achData.icon then
          panel.icon:SetTexture(achData.icon)
          panel.icon:Show()
        else
          panel.icon:Hide()
        end

        panel.nameFS:SetText(achData.name)
        panel.nameFS:SetTextColor(THEME.leaf[1], THEME.leaf[2], THEME.leaf[3])
        panel.qualityFS:SetText("|cFF888888"..achData.category.."|r")
        panel.descFS:SetText(achData.desc.."  |cFFFF7F00("..achData.points.." pts)|r")

        local neededHeight = 24 + panel.nameFS:GetHeight() + panel.qualityFS:GetHeight() + panel.descFS:GetHeight() + 20
        if neededHeight < 80 then neededHeight = 80 end
        panel:SetHeight(neededHeight)

        panel:Show()
      end
      return
    end

    -- Fall back to default behaviour for all other link types
    _origSetItemRef(link, text, button)
  end
end

-------------------------------------------------
-- STARTUP MESSAGE
-------------------------------------------------
Print("|cFF2DD35CLeaf Village Legends|r v"..LeafVE.version.." loaded!")
Print("Type |cFFFFD700/lve|r or |cFFFFD700/leaf|r to open the UI")
Print("Type |cFFFFD700/lvedebug|r for debug commands")
