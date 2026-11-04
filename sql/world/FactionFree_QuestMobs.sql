/*
Companion script for mod-Faction-Free. Run it AFTER FactionFree.sql, against acore_world.

Problem:
FactionTemplate.dbc in this mod makes every Alliance- and Horde-aligned faction friendly to both sides. Some of those
creatures are kill targets for the other side's quests (Dalaran mages in Silverpine Forest, Syndicate-free Alliance
camps, etc.), so the quest can no longer be completed.

Fix:
Find every creature that
  1. uses a faction template the mod turned friendly (lists below, computed by diffing the stock FactionTemplate.dbc
     against the one shipped in /dbc),
  2. is a kill objective of a quest (directly, through KillCredit1/2, or by dropping a required quest item), and
  3. is the target of a quest handed out by an NPC of the OPPOSITE side, so "kill the enemy" quests are caught while
     same-side "heal / talk to / rescue" quests that also use the objective slots are left alone,
and move it to faction 14 (Monster), which is hostile to all players and unchanged by the mod's DBC (client and
server agree, so no MPQ change is needed).

Vendors, quest givers, trainers, flight masters etc. (npcflag != 0), creatures spawned in battlegrounds, and the
mod's own NPCs are skipped.

Original factions are saved in `mod_factionfree_questmob_backup`; the revert statement is at the bottom.
The script can be re-run safely.
*/

USE `acore_world`;

/* Faction templates the mod made friendly. Alliance side = originally hostile to Horde only; Horde side = vice versa. */
DROP TEMPORARY TABLE IF EXISTS `ff_side`;
CREATE TEMPORARY TABLE `ff_side` (`faction` INT UNSIGNED PRIMARY KEY, `side` TINYINT UNSIGNED NOT NULL);

INSERT INTO `ff_side` (`faction`, `side`) SELECT `n`, 1 FROM JSON_TABLE('[1,3,4,11,12,23,53,55,56,57,64,76,79,80,84,
88,101,115,122,123,124,150,151,210,371,655,694,874,875,894,1054,1055,1075,1076,1077,1078,1096,1097,1216,1217,1274,1315,
1334,1414,1514,1534,1575,1576,1577,1594,1596,1599,1611,1618,1621,1622,1629,1638,1639,1640,1642,1644,1645,1646,1647,
1648,1649,1654,1655,1666,1667,1671,1685,1686,1694,1698,1699,1700,1721,1722,1723,1724,1732,1733,1737,1802,1803,1819,
1891,1892,1893,1898,1899,1920,1926,1927,1934,1951,1973,1974,1976,1977,1993,1994,1997,2004,2021,2025,2026,2027,2032,
2037,2040,2044,2130,2142,2143,2155,2178,2236]', '$[*]' COLUMNS (`n` INT UNSIGNED PATH '$')) AS `j`;

INSERT INTO `ff_side` (`faction`, `side`) SELECT `n`, 2 FROM JSON_TABLE('[2,5,6,29,68,71,83,85,98,102,104,105,106,
116,118,125,126,412,876,877,995,1034,1074,1134,1154,1174,1214,1215,1275,1314,1335,1415,1494,1495,1496,1515,1595,1597,
1598,1602,1603,1604,1606,1607,1610,1612,1619,1623,1627,1628,1636,1637,1641,1650,1651,1652,1653,1656,1657,1658,1668,
1669,1670,1695,1729,1734,1735,1745,1801,1804,1835,1897,1900,1901,1918,1921,1922,1923,1928,1929,1935,1978,1979,1980,
1981,1995,2019,2020,2024,2034,2045,2055,2056,2121,2122,2123,2129,2132,2176,2235]', '$[*]'
COLUMNS (`n` INT UNSIGNED PATH '$')) AS `j`;

/* Alterac Valley's own templates (Frostwolf / Stormpike troops, marshals, mounts): leave the battleground alone. */
DELETE FROM `ff_side` WHERE `faction` IN (1214, 1216, 1274, 1275, 1534);

/* MySQL cannot open a temporary table twice in one query, so the quest-giver lookup gets its own copy. */
DROP TEMPORARY TABLE IF EXISTS `ff_side_giver`;
CREATE TEMPORARY TABLE `ff_side_giver` (`faction` INT UNSIGNED PRIMARY KEY, `side` TINYINT UNSIGNED NOT NULL);
INSERT INTO `ff_side_giver` SELECT * FROM `ff_side`;

/* Quest -> creature entry it requires killed (positive RequiredNpcOrGo values are creatures; negative are gameobjects). */
DROP TEMPORARY TABLE IF EXISTS `ff_quest_npc`;
CREATE TEMPORARY TABLE `ff_quest_npc` (`quest` INT UNSIGNED, `npc` INT UNSIGNED, KEY (`npc`), KEY (`quest`));
INSERT INTO `ff_quest_npc` SELECT `ID`, `RequiredNpcOrGo1` FROM `quest_template` WHERE `RequiredNpcOrGo1` > 0;
INSERT INTO `ff_quest_npc` SELECT `ID`, `RequiredNpcOrGo2` FROM `quest_template` WHERE `RequiredNpcOrGo2` > 0;
INSERT INTO `ff_quest_npc` SELECT `ID`, `RequiredNpcOrGo3` FROM `quest_template` WHERE `RequiredNpcOrGo3` > 0;
INSERT INTO `ff_quest_npc` SELECT `ID`, `RequiredNpcOrGo4` FROM `quest_template` WHERE `RequiredNpcOrGo4` > 0;

/* Quest -> item it requires collected. */
DROP TEMPORARY TABLE IF EXISTS `ff_quest_item`;
CREATE TEMPORARY TABLE `ff_quest_item` (`quest` INT UNSIGNED, `item` INT UNSIGNED, KEY (`item`));
INSERT INTO `ff_quest_item` SELECT `ID`, `RequiredItemId1` FROM `quest_template` WHERE `RequiredItemId1` > 0;
INSERT INTO `ff_quest_item` SELECT `ID`, `RequiredItemId2` FROM `quest_template` WHERE `RequiredItemId2` > 0;
INSERT INTO `ff_quest_item` SELECT `ID`, `RequiredItemId3` FROM `quest_template` WHERE `RequiredItemId3` > 0;
INSERT INTO `ff_quest_item` SELECT `ID`, `RequiredItemId4` FROM `quest_template` WHERE `RequiredItemId4` > 0;
INSERT INTO `ff_quest_item` SELECT `ID`, `RequiredItemId5` FROM `quest_template` WHERE `RequiredItemId5` > 0;
INSERT INTO `ff_quest_item` SELECT `ID`, `RequiredItemId6` FROM `quest_template` WHERE `RequiredItemId6` > 0;

/* Candidate creature -> quest that needs it dead. */
DROP TEMPORARY TABLE IF EXISTS `ff_target`;
CREATE TEMPORARY TABLE `ff_target` (`entry` INT UNSIGNED, `quest` INT UNSIGNED, KEY (`entry`), KEY (`quest`));

INSERT INTO `ff_target`
SELECT `ct`.`entry`, `qn`.`quest`
FROM `creature_template` `ct`
JOIN `ff_quest_npc` `qn` ON `qn`.`npc` IN (`ct`.`entry`, `ct`.`KillCredit1`, `ct`.`KillCredit2`);

INSERT INTO `ff_target`
SELECT DISTINCT `ct`.`entry`, `qi`.`quest`
FROM `creature_template` `ct`
/* Quest-only drops; ordinary drops such as cloth would drag in every humanoid via the donation quests. */
JOIN `creature_loot_template` `cl` ON `cl`.`Entry` = `ct`.`lootid` AND `cl`.`Reference` = 0 AND `cl`.`QuestRequired` = 1
JOIN `ff_quest_item` `qi` ON `qi`.`item` = `cl`.`Item`
WHERE `ct`.`lootid` > 0;

/* Keep only friendly-to-both creatures whose quest comes from an NPC of the other side. */
DROP TEMPORARY TABLE IF EXISTS `ff_fix`;
CREATE TEMPORARY TABLE `ff_fix` (`entry` INT UNSIGNED PRIMARY KEY);

INSERT IGNORE INTO `ff_fix`
SELECT DISTINCT `ct`.`entry`
FROM `ff_target` `t`
JOIN `creature_template` `ct` ON `ct`.`entry` = `t`.`entry`
JOIN `ff_side` `ts` ON `ts`.`faction` = `ct`.`faction`
JOIN `creature_queststarter` `qs` ON `qs`.`quest` = `t`.`quest`
JOIN `creature_template` `giver` ON `giver`.`entry` = `qs`.`id`
JOIN `ff_side_giver` `gs` ON `gs`.`faction` = `giver`.`faction` AND `gs`.`side` <> `ts`.`side`
JOIN `quest_template` `q` ON `q`.`ID` = `t`.`quest`
WHERE `ct`.`npcflag` = 0
  AND `ct`.`entry` NOT IN (500000, 500001)
  /* Not real kill targets: Rhukah and Nargut stand in Dalaran with a bogus KillCredit1, North Fleet Corpse is burned with
     a quest item, and the two Champions are unspawned Wintergrasp PvP credit dummies. */
  AND `ct`.`entry` NOT IN (31885, 31886, 24146, 30739, 30740)
  /* Battleground quests (AV, WSG, AB, EotS, SotA, IoC); AV NPCs are spawned by script, not the creature table. */
  AND `q`.`QuestSortID` NOT IN (2597, 3277, 3358, 3820, 4384, 4710)
  AND NOT EXISTS (SELECT 1 FROM `creature` `c` WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` IN (30, 489, 529, 566, 607, 628));

/* Skip creatures that a same-side quest also needs (heal / rescue / escort, e.g. Debilitated Mag'har Grunt):
   making them hostile would break that quest. They are listed so they can be reviewed by hand. */
DROP TEMPORARY TABLE IF EXISTS `ff_conflict`;
CREATE TEMPORARY TABLE `ff_conflict` (`entry` INT UNSIGNED PRIMARY KEY);
INSERT IGNORE INTO `ff_conflict`
SELECT `ct`.`entry`
FROM `ff_fix` `f`
JOIN `creature_template` `ct` ON `ct`.`entry` = `f`.`entry`
JOIN `ff_side` `ts` ON `ts`.`faction` = `ct`.`faction`
JOIN `ff_quest_npc` `qn` ON `qn`.`npc` IN (`ct`.`entry`, `ct`.`KillCredit1`, `ct`.`KillCredit2`)
JOIN `creature_queststarter` `qs` ON `qs`.`quest` = `qn`.`quest`
JOIN `creature_template` `giver` ON `giver`.`entry` = `qs`.`id`
JOIN `ff_side_giver` `gs` ON `gs`.`faction` = `giver`.`faction` AND `gs`.`side` = `ts`.`side`;

SELECT `ct`.`entry`, `ct`.`name`, `ct`.`faction` AS `skipped_same_side_quest_target`
FROM `ff_conflict` `c` JOIN `creature_template` `ct` ON `ct`.`entry` = `c`.`entry`
ORDER BY `ct`.`name`;

DELETE `f` FROM `ff_fix` `f` JOIN `ff_conflict` `c` ON `c`.`entry` = `f`.`entry`;

/* Difficulty entries (heroic / 25-man / level-bracket copies) follow their base creature, never on their own. */
DROP TEMPORARY TABLE IF EXISTS `ff_fix_base`;
CREATE TEMPORARY TABLE `ff_fix_base` (`entry` INT UNSIGNED PRIMARY KEY);
INSERT INTO `ff_fix_base` SELECT `entry` FROM `ff_fix`;
DELETE `f` FROM `ff_fix` `f`
JOIN `creature_template` `parent` ON `f`.`entry` IN (`parent`.`difficulty_entry_1`, `parent`.`difficulty_entry_2`,
                                                     `parent`.`difficulty_entry_3`)
LEFT JOIN `ff_fix_base` `pb` ON `pb`.`entry` = `parent`.`entry`
WHERE `pb`.`entry` IS NULL;
TRUNCATE `ff_fix_base`;
INSERT INTO `ff_fix_base` SELECT `entry` FROM `ff_fix`;
INSERT IGNORE INTO `ff_fix`
SELECT `d`.`entry`
FROM `ff_fix_base` `b`
JOIN `creature_template` `ct` ON `ct`.`entry` = `b`.`entry`
JOIN `creature_template` `d` ON `d`.`entry` IN (`ct`.`difficulty_entry_1`, `ct`.`difficulty_entry_2`,
                                               `ct`.`difficulty_entry_3`)
JOIN `ff_side` `ds` ON `ds`.`faction` = `d`.`faction`;

/* Preview: what is about to change. */
SELECT `ct`.`entry`, `ct`.`name`, `ct`.`faction` AS `old_faction`
FROM `ff_fix` `f` JOIN `creature_template` `ct` ON `ct`.`entry` = `f`.`entry`
ORDER BY `ct`.`name`;

/* Back up original factions (first run wins, so re-running never overwrites the true originals). */
CREATE TABLE IF NOT EXISTS `mod_factionfree_questmob_backup` (
    `entry` INT UNSIGNED PRIMARY KEY,
    `faction` SMALLINT UNSIGNED NOT NULL
);
INSERT IGNORE INTO `mod_factionfree_questmob_backup` (`entry`, `faction`)
SELECT `ct`.`entry`, `ct`.`faction` FROM `ff_fix` `f` JOIN `creature_template` `ct` ON `ct`.`entry` = `f`.`entry`;

UPDATE `creature_template` `ct` JOIN `ff_fix` `f` ON `f`.`entry` = `ct`.`entry` SET `ct`.`faction` = 14;

DROP TEMPORARY TABLE IF EXISTS `ff_side`, `ff_side_giver`, `ff_quest_npc`, `ff_quest_item`, `ff_target`, `ff_fix`, `ff_fix_base`, `ff_conflict`;

/* To revert:
UPDATE `creature_template` `ct` JOIN `mod_factionfree_questmob_backup` `b` ON `b`.`entry` = `ct`.`entry`
SET `ct`.`faction` = `b`.`faction`;
*/
