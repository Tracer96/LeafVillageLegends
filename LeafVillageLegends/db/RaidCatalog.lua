local catalog = {}

catalog[1] = {
  key = "ZulGurub",
  name = "Zul'Gurub",
  raidSize = 20,
  roleTargets = { tank = 2, healer = 5, melee = 6, ranged = 7, flex = 0 },
  bosses = {
    { key = "ZGJeklik", name = "High Priestess Jeklik", kind = "boss" },
    { key = "ZGVenoxis", name = "High Priest Venoxis", kind = "boss" },
    { key = "ZGMarli", name = "High Priestess Mar'li", kind = "boss" },
    { key = "ZGMandokir", name = "Bloodlord Mandokir", kind = "boss" },
    { key = "ZGGrilek", name = "Gri'lek", kind = "boss" },
    { key = "ZGHazzarah", name = "Hazza'rah", kind = "boss" },
    { key = "ZGRenataki", name = "Renataki", kind = "boss" },
    { key = "ZGWushoolay", name = "Wushoolay", kind = "boss" },
    { key = "ZGGahzranka", name = "Gahz'ranka", kind = "boss" },
    { key = "ZGThekal", name = "High Priest Thekal", kind = "boss" },
    { key = "ZGArlokk", name = "High Priestess Arlokk", kind = "boss" },
    { key = "ZGJindo", name = "Jin'do the Hexxer", kind = "boss" },
    { key = "ZGHakkar", name = "Hakkar", kind = "boss" },
  },
}

catalog[2] = {
  key = "RuinsofAQ",
  name = "Ruins of Ahn'Qiraj",
  raidSize = 20,
  roleTargets = { tank = 2, healer = 5, melee = 6, ranged = 7, flex = 0 },
  bosses = {
    { key = "AQ20Kurinnaxx", name = "Kurinnaxx", kind = "boss" },
    { key = "AQ20CAPTAIN", name = "Rajaxx's Captains", kind = "boss" },
    { key = "AQ20Rajaxx", name = "General Rajaxx", kind = "boss" },
    { key = "AQ20Moam", name = "Moam", kind = "boss" },
    { key = "AQ20Buru", name = "Buru the Gorger", kind = "boss" },
    { key = "AQ20Ayamiss", name = "Ayamiss the Hunter", kind = "boss" },
    { key = "AQ20Ossirian", name = "Ossirian the Unscarred", kind = "boss" },
  },
}

catalog[3] = {
  key = "MoltenCore",
  name = "Molten Core",
  raidSize = 40,
  roleTargets = { tank = 4, healer = 10, melee = 13, ranged = 13, flex = 0 },
  bosses = {
    { key = "MCIncindis", name = "Incindis", kind = "boss" },
    { key = "MCLucifron", name = "Lucifron", kind = "boss" },
    { key = "MCMagmadar", name = "Magmadar", kind = "boss" },
    { key = "MCGehennas", name = "Gehennas", kind = "boss" },
    { key = "MCGarr", name = "Garr", kind = "boss" },
    { key = "MCShazzrah", name = "Shazzrah", kind = "boss" },
    { key = "MCGeddon", name = "Baron Geddon", kind = "boss" },
    { key = "MCGolemagg", name = "Golemagg the Incinerator", kind = "boss" },
    { key = "MCTwins", name = "Basalthar & Smoldaris", kind = "boss" },
    { key = "MCThaurissan", name = "Sorcerer-Thane Thaurissan", kind = "boss" },
    { key = "MCSulfuron", name = "Sulfuron Harbinger", kind = "boss" },
    { key = "MCMajordomo", name = "Majordomo Executus", kind = "boss" },
    { key = "MCRagnaros", name = "Ragnaros", kind = "boss" },
  },
}

catalog[4] = {
  key = "Onyxia",
  name = "Onyxia's Lair",
  raidSize = 40,
  roleTargets = { tank = 3, healer = 8, melee = 14, ranged = 15, flex = 0 },
  bosses = {
    { key = "Onyxia", name = "Onyxia", kind = "boss" },
  },
}

catalog[5] = {
  key = "LowerKara",
  name = "Lower Karazhan Halls",
  raidSize = 10,
  roleTargets = { tank = 2, healer = 3, melee = 2, ranged = 3, flex = 0 },
  bosses = {
    { key = "LKHRolfen", name = "Master Blacksmith Rolfen", kind = "boss" },
    { key = "LKHBroodQueenAraxxna", name = "Brood Queen Araxxna", kind = "boss" },
    { key = "LKHGrizikil", name = "Grizikil", kind = "boss" },
    { key = "LKHClawlordHowlfang", name = "Clawlord Howlfang", kind = "boss" },
    { key = "LKHLordBlackwaldII", name = "Lord Blackwald II", kind = "boss" },
    { key = "LKHMoroes", name = "Moroes", kind = "boss" },
  },
}

catalog[6] = {
  key = "BlackwingLair",
  name = "Blackwing Lair",
  raidSize = 40,
  roleTargets = { tank = 4, healer = 10, melee = 13, ranged = 13, flex = 0 },
  bosses = {
    { key = "BWLRazorgore", name = "Razorgore the Untamed", kind = "boss" },
    { key = "BWLVaelastrasz", name = "Vaelastrasz the Corrupt", kind = "boss" },
    { key = "BWLLashlayer", name = "Broodlord Lashlayer", kind = "boss" },
    { key = "BWLFiremaw", name = "Firemaw", kind = "boss" },
    { key = "BWLEbonroc", name = "Ebonroc", kind = "boss" },
    { key = "BWLFlamegor", name = "Flamegor", kind = "boss" },
    { key = "BWLChromaggus", name = "Chromaggus", kind = "boss" },
    { key = "BWLNefarian", name = "Nefarian", kind = "boss" },
  },
}

catalog[7] = {
  key = "EmeraldSanctum",
  name = "Emerald Sanctum",
  raidSize = 10,
  roleTargets = { tank = 2, healer = 3, melee = 2, ranged = 3, flex = 0 },
  bosses = {
    { key = "ESErennius", name = "Erennius", kind = "boss" },
    { key = "ESSolnius1", name = "Solnius the Awakener", kind = "boss" },
  },
}

catalog[8] = {
  key = "TempleofAQ",
  name = "Temple of Ahn'Qiraj",
  raidSize = 40,
  roleTargets = { tank = 4, healer = 10, melee = 13, ranged = 13, flex = 0 },
  bosses = {
    { key = "AQ40Skeram", name = "The Prophet Skeram", kind = "boss" },
    { key = "AQ40Trio", name = "The Bug Family", kind = "boss" },
    { key = "AQ40Sartura", name = "Battleguard Sartura", kind = "boss" },
    { key = "AQ40Fankriss", name = "Fankriss the Unyielding", kind = "boss" },
    { key = "AQ40Viscidus", name = "Viscidus", kind = "boss" },
    { key = "AQ40Huhuran", name = "Princess Huhuran", kind = "boss" },
    { key = "AQ40Emperors", name = "The Twin Emperors", kind = "boss" },
    { key = "AQ40Ouro", name = "Ouro", kind = "boss" },
    { key = "AQ40CThun", name = "C'Thun", kind = "boss" },
  },
}

catalog[9] = {
  key = "Naxxramas",
  name = "Naxxramas",
  raidSize = 40,
  roleTargets = { tank = 4, healer = 10, melee = 13, ranged = 13, flex = 0 },
  bosses = {
    { key = "NAXPatchwerk", name = "Patchwerk", kind = "boss" },
    { key = "NAXGrobbulus", name = "Grobbulus", kind = "boss" },
    { key = "NAXGluth", name = "Gluth", kind = "boss" },
    { key = "NAXThaddius", name = "Thaddius", kind = "boss" },
    { key = "NAXAnubRekhan", name = "Anub'Rekhan", kind = "boss" },
    { key = "NAXGrandWidowFaerlina", name = "Grand Widow Faerlina", kind = "boss" },
    { key = "NAXMaexxna", name = "Maexxna", kind = "boss" },
    { key = "NAXNoththePlaguebringer", name = "Noth the Plaguebringer", kind = "boss" },
    { key = "NAXHeigantheUnclean", name = "Heigan the Unclean", kind = "boss" },
    { key = "NAXLoatheb", name = "Loatheb", kind = "boss" },
    { key = "NAXInstructorRazuvious", name = "Instructor Razuvious", kind = "boss" },
    { key = "NAXGothiktheHarvester", name = "Gothik the Harvester", kind = "boss" },
    { key = "NAXTheFourHorsemen", name = "The Four Horsemen", kind = "boss" },
    { key = "NAXSapphiron", name = "Sapphiron", kind = "boss" },
    { key = "NAXKelThuzard", name = "Kel'Thuzad", kind = "boss" },
  },
}

catalog[10] = {
  key = "UpperKara",
  name = "Upper Karazhan Halls",
  raidSize = 10,
  roleTargets = { tank = 2, healer = 3, melee = 2, ranged = 3, flex = 0 },
  bosses = {
    { key = "UKHGnarlmoon", name = "Keeper Gnarlmoon", kind = "boss" },
    { key = "UKHIncantagos", name = "Ley-Watcher Incantagos", kind = "boss" },
    { key = "UKHAnomalus", name = "Anomalus", kind = "boss" },
    { key = "UKHEcho", name = "Echo of Medivh", kind = "boss" },
    { key = "UKHKing", name = "King (Chess fight)", kind = "boss" },
    { key = "UKHSanvTasdal", name = "Sanv Tas'dal", kind = "boss" },
    { key = "UKHKruul", name = "Kruul", kind = "boss" },
    { key = "UKHRupturan", name = "Rupturan the Broken", kind = "boss" },
    { key = "UKHMephistroth", name = "Mephistroth", kind = "boss" },
  },
}

LeafVE_RaidCatalogSource = catalog
