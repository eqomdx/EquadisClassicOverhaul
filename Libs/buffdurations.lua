--[[ **How long a buff lasts, which 1.12 will not tell you either.**

     `UnitBuff` answers a texture and a stack count and stops, exactly as
     `UnitDebuff` does -- so a timer on a target's buff needs the same two halves
     the debuff timer needs: knowing beforehand how long the spell lasts, and
     having seen it land.

     The debuff half shipped and this one did not, which is why a target's
     debuffs counted down and its buffs showed nothing at all. `debuffDurations`
     carries a handful of buffs incidentally -- Battle Shout, Arcane Intellect,
     Mark of the Wild are in there -- and that is what made the gap hard to see
     from outside: some buffs had a timer and most did not, which reads as
     flaky rather than as missing.

     **Only what is certain goes in here.** A timer reading four minutes on a
     thirty minute blessing is worse than no timer, because it is read as fact
     rather than as ignorance -- the same rule the debuff table states and the
     reason an absent spell draws nothing. So this is the set of buffs whose
     vanilla durations are not in doubt, and it is meant to be added to: one
     line, name to rank to seconds, and the timer appears.

     Rank zero is the entry for a spell whose rank does not change its duration,
     which is true of every buff below. A ranked spell whose *duration* changes
     with rank -- Blessing of Protection -- lists its ranks. ]]--
local OB = EquadisClassicOverhaul
if not OB then return end

local MINUTE = 60

OB.buffDurations = {

    -- priest ---------------------------------------------------------------
    ['Power Word: Fortitude']           = { [0] = 30 * MINUTE },
    ['Prayer of Fortitude']             = { [0] = 60 * MINUTE },
    ['Divine Spirit']                   = { [0] = 30 * MINUTE },
    ['Prayer of Spirit']                = { [0] = 60 * MINUTE },
    ['Shadow Protection']               = { [0] = 10 * MINUTE },
    ['Prayer of Shadow Protection']     = { [0] = 20 * MINUTE },
    ['Power Word: Shield']              = { [0] = 30 },
    ['Renew']                           = { [0] = 15 },
    ['Inner Fire']                      = { [0] = 10 * MINUTE },
    ['Fear Ward']                       = { [0] = 10 * MINUTE },
    ['Elune\'s Grace']                  = { [0] = 15 },

    -- mage -----------------------------------------------------------------
    ['Arcane Intellect']                = { [0] = 30 * MINUTE },
    ['Arcane Brilliance']               = { [0] = 60 * MINUTE },
    ['Amplify Magic']                   = { [0] = 10 * MINUTE },
    ['Dampen Magic']                    = { [0] = 10 * MINUTE },
    ['Frost Armor']                     = { [0] = 30 * MINUTE },
    ['Ice Armor']                       = { [0] = 30 * MINUTE },
    ['Mage Armor']                      = { [0] = 30 * MINUTE },
    ['Ice Barrier']                     = { [0] = 60 },
    ['Mana Shield']                     = { [0] = 60 },
    ['Ice Block']                       = { [0] = 10 },
    ['Evocation']                       = { [0] = 8 },
    ['Slow Fall']                       = { [0] = 30 },

    -- druid ----------------------------------------------------------------
    ['Mark of the Wild']                = { [0] = 30 * MINUTE },
    ['Gift of the Wild']                = { [0] = 60 * MINUTE },
    ['Thorns']                          = { [0] = 10 * MINUTE },
    ['Rejuvenation']                    = { [0] = 12 },
    ['Regrowth']                        = { [0] = 21 },
    ['Barkskin']                        = { [0] = 12 },
    ['Nature\'s Grasp']                 = { [0] = 45 },
    ['Innervate']                       = { [0] = 20 },

    -- paladin --------------------------------------------------------------
    --[[ The greater forms are a different spell name, which is what makes them
         a different row rather than a rank. ]]--
    ['Blessing of Might']               = { [0] = 5 * MINUTE },
    ['Greater Blessing of Might']       = { [0] = 15 * MINUTE },
    ['Blessing of Wisdom']              = { [0] = 5 * MINUTE },
    ['Greater Blessing of Wisdom']      = { [0] = 15 * MINUTE },
    ['Blessing of Kings']               = { [0] = 5 * MINUTE },
    ['Greater Blessing of Kings']       = { [0] = 15 * MINUTE },
    ['Blessing of Salvation']           = { [0] = 5 * MINUTE },
    ['Greater Blessing of Salvation']   = { [0] = 15 * MINUTE },
    ['Blessing of Light']               = { [0] = 5 * MINUTE },
    ['Greater Blessing of Light']       = { [0] = 15 * MINUTE },
    ['Blessing of Sanctuary']           = { [0] = 5 * MINUTE },
    ['Greater Blessing of Sanctuary']   = { [0] = 15 * MINUTE },
    ['Blessing of Freedom']             = { [0] = 10 },
    ['Blessing of Protection']          = { [1] = 6, [2] = 8, [3] = 10 },
    ['Blessing of Sacrifice']           = { [0] = 30 },
    ['Divine Shield']                   = { [0] = 12 },
    ['Divine Protection']               = { [0] = 10 },
    ['Divine Favor']                    = { [0] = 15 },
    ['Holy Shield']                     = { [0] = 10 },

    -- warrior --------------------------------------------------------------
    ['Battle Shout']                    = { [0] = 2 * MINUTE },
    ['Berserker Rage']                  = { [0] = 10 },
    ['Recklessness']                    = { [0] = 15 },
    ['Retaliation']                     = { [0] = 15 },
    ['Shield Wall']                     = { [0] = 10 },
    ['Last Stand']                      = { [0] = 20 },
    ['Death Wish']                      = { [0] = 30 },
    ['Shield Block']                    = { [0] = 5 },
    ['Bloodrage']                       = { [0] = 10 },

    -- rogue ----------------------------------------------------------------
    --[[ Slice and Dice and Rupture are bought with combo points, so their
         length is written down when they land rather than looked up here --
         see `OB.ComboDuration`. ]]--
    ['Sprint']                          = { [0] = 15 },
    ['Evasion']                         = { [0] = 15 },
    ['Blade Flurry']                    = { [0] = 15 },
    ['Adrenaline Rush']                 = { [0] = 20 },
    ['Stealth']                         = { [0] = 0 },

    -- hunter ---------------------------------------------------------------
    ['Aspect of the Cheetah']           = { [0] = 0 },
    ['Rapid Fire']                      = { [0] = 15 },
    ['Bestial Wrath']                   = { [0] = 18 },
    ['Quick Shots']                     = { [0] = 12 },

    -- shaman ---------------------------------------------------------------
    ['Lightning Shield']                = { [0] = 10 * MINUTE },
    ['Stoneskin']                       = { [0] = 2 * MINUTE },
    ['Nature Resistance']               = { [0] = 2 * MINUTE },
    ['Elemental Mastery']               = { [0] = 30 },
    ['Nature\'s Swiftness']             = { [0] = 10 },
    ['Water Walking']                   = { [0] = 10 * MINUTE },
    ['Water Breathing']                 = { [0] = 10 * MINUTE },

    -- warlock --------------------------------------------------------------
    ['Demon Skin']                      = { [0] = 30 * MINUTE },
    ['Demon Armor']                     = { [0] = 30 * MINUTE },
    ['Unending Breath']                 = { [0] = 10 * MINUTE },
    ['Detect Invisibility']             = { [0] = 10 * MINUTE },
    ['Detect Greater Invisibility']     = { [0] = 10 * MINUTE },
    ['Shadow Ward']                     = { [0] = 30 },
    ['Sacrifice']                       = { [0] = 30 },
    ['Soulstone Resurrection']          = { [0] = 30 * MINUTE },
    ['Blood Pact']                      = { [0] = 30 * MINUTE },

    -- consumables ----------------------------------------------------------
    --[[ Every battle elixir in the game is an hour and every guardian elixir is
         an hour; flasks are two and survive death. The names are the *buff*
         names rather than the item names, because that is what the tooltip
         scan reads off the icon. ]]--
    ['Elixir of the Mongoose']          = { [0] = 60 * MINUTE },
    ['Elixir of Giants']                = { [0] = 60 * MINUTE },
    ['Elixir of Superior Defense']      = { [0] = 60 * MINUTE },
    ['Elixir of Fortitude']             = { [0] = 60 * MINUTE },
    ['Greater Arcane Elixir']           = { [0] = 60 * MINUTE },
    ['Arcane Elixir']                   = { [0] = 60 * MINUTE },
    ['Elixir of Greater Firepower']     = { [0] = 60 * MINUTE },
    ['Elixir of Frost Power']           = { [0] = 60 * MINUTE },
    ['Elixir of Shadow Power']          = { [0] = 60 * MINUTE },
    ['Mana Regeneration']               = { [0] = 60 * MINUTE },
    ['Flask of the Titans']             = { [0] = 120 * MINUTE },
    ['Flask of Distilled Wisdom']       = { [0] = 120 * MINUTE },
    ['Flask of Supreme Power']          = { [0] = 120 * MINUTE },
    ['Flask of Chromatic Resistance']   = { [0] = 120 * MINUTE },
    ['Well Fed']                        = { [0] = 15 * MINUTE },
    ['Increased Stamina']               = { [0] = 60 * MINUTE },
    ['Increased Intellect']             = { [0] = 60 * MINUTE },

    -- world buffs ----------------------------------------------------------
    ['Rallying Cry of the Dragonslayer'] = { [0] = 120 * MINUTE },
    ['Warchief\'s Blessing']            = { [0] = 120 * MINUTE },
    ['Spirit of Zandalar']              = { [0] = 120 * MINUTE },
    ['Songflower Serenade']             = { [0] = 60 * MINUTE },
    ['Fengus\' Ferocity']               = { [0] = 120 * MINUTE },
    ['Mol\'dar\'s Moxie']               = { [0] = 120 * MINUTE },
    ['Slip\'kik\'s Savvy']              = { [0] = 120 * MINUTE },
    ['Sayge\'s Dark Fortune of Damage'] = { [0] = 120 * MINUTE },
    ['Sayge\'s Dark Fortune of Agility'] = { [0] = 120 * MINUTE },
    ['Sayge\'s Dark Fortune of Intelligence'] = { [0] = 120 * MINUTE },
    ['Sayge\'s Dark Fortune of Spirit'] = { [0] = 120 * MINUTE },
    ['Sayge\'s Dark Fortune of Stamina'] = { [0] = 120 * MINUTE },
    ['Sayge\'s Dark Fortune of Armor']  = { [0] = 120 * MINUTE },
    ['Sayge\'s Dark Fortune of Resistance'] = { [0] = 120 * MINUTE },
    ['Traces of Silithyst']             = { [0] = 0 },
}
