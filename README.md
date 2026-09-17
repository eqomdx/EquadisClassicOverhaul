# Equadis' Classic Overhaul

**An all-in-one interface package for World of Warcraft: Vanilla (1.12.x).**

<https://github.com/eqomdx/EquadisClassicOverhaul>

One addon instead of eight. Unit frames, nameplates, aura bars, a damage meter, a
threat meter and a class-aware combat HUD — sharing a single settings panel, a
single media library, a single profile system, and one consistent look.

> **Version 0.86.4.**
> Tooltip and Item Database runtime fixes: cursor/fixed positioning with separate
> mouse offsets, class/reaction health-bar colours, centred configurable bar text,
> constrained tooltip text, item names/icons, database shortcuts, and pfExtend-
> compatible embedded pfQuest/Turtle direct/reference loot resolution (no live
> pfQuest dependency) including quest and boss
> drops. Atlas-CFM DestinationClick and AtlasLoot data remain bundled.
> Saved-variable migrations are provided; keeping a backup of your `WTF` folder
> before replacing a UI addon is still recommended.

## Why

The usual vanilla UI is a pile of addons that do not know about each other. Six
different bar textures, six settings panels, six ideas of what "thin border"
means, and six separate places to configure the same font. Each one is fine; the
result is not.

The Overhaul is one addon with one media list, one options panel, one profile store,
and modules that can each be switched off if you prefer someone else's.

The package is designed to coexist with unrelated addons, but **do not enable a
second standalone Atlas-CFM or AtlasLoot copy at the same time**. Their globals and
frame names are bundled here already, so loading the same addon twice can collide.

## Status

| Area | State |
|---|---|
| Core framework — config, profiles, media, options generator, module registry | **done** |
| Combat HUD — resource, combo points, swing timers, health | **done** |
| Distance readout, ranged swing timer, druid secondary mana | **done** |
| Threat meter | **done**, off by default |
| Combat log parser | **done** |
| Damage meter | **done**, off by default |
| Unit frames | **done** |
| Nameplates | **done** |
| Aura bars | **done** |
| Chat / QoL | **done**, actively iterated |
| Tooltip | **done**, enabled by default |
| Item Database | **done**, searchable by item name or ID |
| Bundled Atlas-CFM DestinationClick | **done**, upstream `9d92e187` + embedding patches |
| Bundled AtlasLoot data | **done**, item/source provider |

**Every subsystem has a tab of its own** in the settings panel, from the day it
is planned rather than the day it works:

```
Profiles · Bars · Unit Frames · Nameplates · Damage Meter ·
Threat Meter · Chat · QoL · Item Database · Tooltip · Modules
```

Profiles is first because it decides what every other tab is editing. Modules is
last because it is the shortest question — which of these do I want at all.

A tab for something unwritten carries a sentence saying what it will be **and its
full settings, greyed out**. That is not decoration: a name says what a subsystem
will be, the settings say what it will actually let you *do*, and that is the
part worth arguing about before it is written rather than after.

The framework is deliberately ahead of the features: modules declare their own
settings, their own class gating and their own panel rows, so each item above is
an addition rather than a rewrite.

## The idea: one layout, every character

Most HUD addons give every bar its own position. That means a warrior's rage bar
and a rogue's energy bar are two unrelated settings, and configuring an alt means
starting over.

In the Overhaul the **rectangle** and **what is drawn in it** are separate things.
Position, size, texture, border and background belong to the bar and are shared
by every character on the profile. Color and behavior belong to the module,
because those are the things that *should* differ — energy yellow, rage red,
health green.

So the resource bar is one rectangle. A rogue fills it with energy, a warrior with
rage, a priest with mana: same place, same size, different color. A druid
shifting form does not move it either — only the color and the ticker change.

### The bars

Listed in the settings panel in this order, and stacked on screen the same way.
Drag them into whatever order you actually want.

| Bar | Shows |
|---|---|
| Health | Your health |
| Resource | Energy / rage / mana / focus, whichever the class uses |
| Main Hand | Main hand swing timer |
| Off Hand | Off hand swing timer |
| Ranged | Auto shot timer |
| Ranged Distance Check | Can you hit your target from here |
| Secondary Resource | A druid's mana while shifted |
| Extras | Class specific — combo points for a rogue or druid |

Each bar has a **Show Bar** switch, on by default. Bars your class cannot use are
not listed at all: a warrior has no Extras and no Secondary Resource. And a bar
with nothing to say hides itself whatever that switch says — no off hand
equipped, nothing ranged equipped — so an empty off hand leaves no gap in the
art, just space.

That space is not closed up automatically, because bar positions are shared and
closing a gap for one character would move another's. **Restack Occupied Bars**
on the Bars page does it on demand.

## Modules today

**Resource** — every power type from one bar. Energy and focus anchor their
ticker to the observed regeneration pulse and hold the phase when capped, so the
spark is in the right place the moment you spend. The tick interval is
*measured* rather than assumed to be two seconds — the number everyone quotes is
not what a client observes — and gains that are not the tick are ignored, so a
rogue's Vigor refunds and Relentless Strikes do not drag the sweep off the beat. Mana has no pulse to observe,
so it infers the cycle from the last change: spending opens a five second rule
window, optionally shaded on the bar as a shrinking region. Rage does not tick,
but it leaks — an optional marker shows where it will have decayed to a few
seconds from now, at a rate measured from your own server rather than assumed.

**Combo Points** — five segments, one color each, inactive points dimmed to a
configurable opacity.

**Swing Timers** — main hand, off hand and ranged, with remaining time and weapon
speed. Fill or deplete, flip, 0–2 decimal points. Because vanilla's
combat log does not say which hand swung, a landed swing is attributed to
whichever hand has been ready *longest* — which is what lets the pair recover on
its own after a stun or a run out of range.

**Health** — green by default, any color, and three ways to choose it:

| Setting | |
|---|---|
| **Bar Color** | one color, whatever you pick |
| **Color By Remaining Health** | a ramp between **Full**, **Half** and **Low** colors |
| **Color By Class** | your class color |

Class wins outright, the ramp beats the swatch, the swatch is what is left.

This is the panel's general rule: **a setting that has stopped doing anything is
greyed out, never removed.** Turn off Show Timer and its position and decimals
dim; turn off Check Line Of Sight and its color and timer dim; turn off Show HUD
and the three hide-conditions dim. They all still say what they say, and they
apply again the moment the switch comes back — a control that vanished would read
as having been deleted.

A row is only removed when it has no meaning at all rather than a meaning that
is not in charge: a rogue never sees Mark Rage Decay, because there is no switch
that would bring it back.

The **Off Hand** bar is the one place that bends. A mage cannot dual wield, so
none of it will ever draw for them — but bar geometry is account-wide, and that
rectangle is the one their warrior uses. So it is dimmed rather than removed,
leaving it reachable. And if a server hands dual wield to a class vanilla never
did, an off hand that actually swings settles the matter and the section comes
back for the rest of the session.

The ramp takes three colors rather than two on purpose. A straight blend from
green to red passes through olive-brown at the halfway point, which reads as a
fault rather than as half health; a bright middle keeps every value on the ramp
legible. Set the middle to the average of the ends if you want a plain two-color
blend.

**Ranged Distance Check** — can you hit your target from here. **One bar, always
full**, and its color is the whole answer. All five colors are yours to set:

| State | Default |
|---|---|
| In range | green |
| Too close — inside a bow's dead zone | orange |
| Too far | red |
| No line of sight — something is in the way | violet |
| No target | dark grey `#1f1f1f` — a placeholder, so you can see the bar is there |

The question is about **your equipped ranged weapon**, not some generic distance.
It reads your ranged slot, works out whether that is a bow, a gun, a crossbow, a
wand or a thrown weapon, and looks up the range of the auto-attack *you* fire with
it — so a wand has no dead zone, and a hunter's gun reaches further than a
warrior's, because Auto Shot and Shoot Gun are different spells with different
ranges.

How precisely it can answer depends on your client. With **Nampower** it uses the
game's own range check, including the real minimum range. **SuperWoW** adds exact
yardage for friendly units. Exact hostile yardage comes from Nampower when it
exposes `GetUnitDistance`, or from **UnitXP_SP3**. Without an exact source,
hostile targets still get the correct range state but not a numeric yardage. With
none of these extensions it falls back to your ranged attack's own action button,
found on your bars automatically, and failing that to the game's coarse
interaction distances.

Turn the No Target color's opacity down to zero if you would rather the bar
vanish when you have nothing selected.

### Distance without a distance API

Vanilla has no call that returns how far away a mob is, and the two extensions
that add one are not on most installs. So with **Nampower** the Overhaul measures
anyway, by asking a question it *can* ask.

`IsSpellInRange` only answers yes or no — but yes or no against a *known
threshold* is one bit of a distance. Ask about a spell that reaches 35 yards and
one that reaches 40: no, then yes, puts your target between the two. Enough
spells and the answer narrows to a five-yard step.

The label shows that step: `<5y`, `5y`, `10y`, `15y`, up to `50y+`. Both ends of
a band are open and say so — nothing is ever at zero, and past fifty the rungs
get coarse enough that one honest ceiling beats a number pretending otherwise.

**When something can measure, the label is the measurement**, to the yard:
`23y`, and no ceiling, because there is nothing to admit. That needs an exact
source — UnitXP SP3, a Nampower build with `GetUnitDistance`, or SuperWoW for
friendly units — and the ladder above is what runs when none is installed. The
two read the same way, `23y` beside `20y`, so the label does not change character
when you switch targets; it simply gets five times finer when the client can
answer.

You do not need to know the spells, and neither did the Overhaul — the rung list came
out of the client's own range table. Several of them are not player spells at
all: *Debilitating Charge*, *True Fulfillment*, *Disturb Rookery Egg*. That is
fine, because nothing is ever cast. The range check is arithmetic on a table row,
so a spell nobody can cast measures a distance exactly as well as one anybody
can.

The rungs land at **5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60 and 100 yards** —
five-yard resolution unbroken from touching distance to fifty, which covers every
weapon in the game. Each candidate's real range is read from **your** client at
login, so a server that has retuned something calibrates to the retuned value.
Spells with a dead zone are dropped: a threshold that answers "no" from both
directions is not a threshold.

Three settings govern the labels and the line-of-sight hold:

- **Show Active Distance** — the live figure in the middle of the bar.
- **Show In-Range Distances** — your equipped attack's whole usable range, `[8-30y]`, on
  the right. Off by default: a number that never changes, on a bar whose job is
  to change, invites being read as the answer.
- **No Line Of Sight Timer** — 0.1 to 2 seconds, how long a refused shot holds
  the violet. Nothing ever confirms the wall has gone, so this is a guess about
  the future and only you know how long a guess you want. Short flickers; long
  keeps lying after you have stepped clear.

`/eq rangedebug` prints the rungs your client produced. `/eq rangescan` goes
further and lists every band the client *could* measure, naming one spell for
each — so a gap in the readout is closed by adding that spell's ID to
`LADDER_IDS` in `modules/range.lua`, with no other change.

**Check Line Of Sight** is on by default and needs nothing installed, but how
quickly it answers depends on what you have. Vanilla will not let an addon
*ask* whether something is in the way — there is no such API — so the only signal
is the client's own refusal: try to shoot, get *Target not in line of sight*, and
the bar turns violet for a couple of seconds. It cannot tell you in advance, and
it cannot notice the obstruction clearing, so it goes quiet on its own rather
than guessing.

In practice that is less of a gap than it sounds: while you are actually
shooting, the client retries and the refusal keeps arriving, so the bar stays
violet for as long as the wall is there. The gap is standing still and not
attacking.

Making it *continuous* needs a native query, because no vanilla API can be asked
this. The Overhaul will use either `IsUnitInSight(unitToken)` — a Nampower build
extended the way `native/` extends it for distance — or **UnitXP_SP3**, whichever
is present. With one of those the bar turns the moment you step behind a pillar.

Classes with a relic in the ranged slot have no ranged attack at all, so the bar
becomes a plain distance readout using an assumed 30 yards.

**Druid Mana** — how much mana you still have in bear or cat form. Vanilla stops
reporting it the moment you shift, so it is simulated from the shift onwards:
spirit regeneration, mana-per-5 from your gear, the shapeshift cost, Innervate
and the five second rule. If you log in already shifted there is no baseline to
work from, so the bar stays hidden rather than showing a confident wrong number.

**Threat Meter** — who has the aggro, and how close you are to taking it. A
window of rows, highest first, sorted by percentage of the tank's threat rather
than raw threat: the two agree while everyone is on one target and disagree the
moment somebody is not, and the percentage is already the answer to *am I about
to pull*.

The name sits left and the figures together on the right, the same shape the
damage meter uses — two numbers that belong to each other read as a pair only
when they are next to each other.

Color goes **bar color, then class, then your own pull** — each one overriding
the one before. The three ramp anchors are **Low**, **Medium** and **High
Threat**. The bar color is what a row is unless something knows better;
class knows better, because it is how you find a name in a list; and your own
threat ramp knows better still, because it is the reading the window exists for.
Safe through to about-to-pull, the same three-anchor ramp the health bar uses,
pointed the other way. Melee rip at 110% of the tank and everyone else at 130%,
so the same percentage is a different color depending on which you are.

It reads the threat Turtle broadcasts to your group, so there is no combat log
parsing in it and nothing to configure to make it accurate — and equally, nothing
it can do on a server that does not send that broadcast. Rows scale against the
leader rather than against a fixed hundred, so a group where nobody is near the
tank still shows who is ahead of whom.

**With no data it says so rather than disappearing**, and names which of the
reasons applies: no threat data from the server, or waiting for a pull. Those are
different problems and only one of them is worth looking for a setting about. It
also means the window is there to be placed before the raid starts, which a
hidden one is not.

**Solo is the exception, and it is off by default.** Threat arrives over the
party or raid channel, so alone there is no channel to hear it on — the window is
not waiting for data, it is waiting for a group, and a permanent "no threat solo"
sitting over the world while you quest is a label rather than a readout. **Show
When Solo** puts it back if you want it there to place. Test Bars shows it either
way, since configuring a window is exactly what you do while standing alone.

Off by default: it is a whole threat meter, and turning it on should be a
decision.

**Damage Meter** — damage and healing done, in a window of rows, highest first.

The combat log is read **without matching a word of English**. The client already
holds its own sentences — `COMBATHITSELFOTHER` is *"You hit %s for %d."* in
whatever language you are running — so those get turned into patterns and the
client does the translating. That approach is ShaguDPS's and it is why the parser
was ported rather than written; the alternative is a table of translated
sentences that rots the day a server changes one.

Two segments are kept at once: **Current Fight**, which starts over at each pull,
and **Overall**, which runs until you reset it. Both, rather than a switch,
because the moment you want the other one the fight is over and it cannot be
recomputed.

Three statistics, not two: **Damage Done**, **Healing Done** and **Damage
Taken**. The third is a separate count rather than a filter on the first — damage
done is keyed by who dealt it, damage taken by who received it, which is the
question a tank is actually asking.

A **header bar** across the top is where the window is controlled, left to right:

| | |
|---|---|
| cog | open this meter's settings tab |
| padlock | lock or unlock this window |
| Current / Overall | which segment — and **Reset Data** |
| Damage / Healing / Taken | which statistic |
| **+** / **X** | open another window, or close this one |

The last position carries **+ on the first window and X on every other**. The
first window is the one the settings page edits and cannot be closed; the others
can only ever close. Neither ever needs the other's action, so showing both would
be one dead button per window.

Three groups, not one strip: **window controls on the left**, the two menus
**centred**, add-or-close **on the right**. They are three different kinds of
thing, and the two menus are the only ones whose answer changes — so they get the
middle, where the eye lands.

Drag the header to move the window. The threat meter has the same header with
the first two buttons — it has one segment, one statistic and one window, so
there is nothing for the others to say.

**Hover a row to see where the number came from**: that player's damage broken
down by spell, biggest first, with each one's share. A total answers *who*, and
the next question is always *off what* — which cannot be recovered from a total
afterwards, so the breakdown is recorded as the fight happens rather than worked
out on demand. Swings are listed as **Melee**, because for a warrior that is most
of the answer. Damage taken breaks down the same way, which is the reading a tank
wants: not how much they took, but what took it off them.

A new window is **a copy of the first one, moved** — same colours, same columns,
same sizes — showing the next statistic along. A window opened beside one you
spent ten minutes colouring should not arrive in the shipped grey.

**Windows push each other apart.** Drop one on another and it lands clear below
it, always downwards: sideways would put it where the next window is going to go,
and a third drop would cascade. Two stacked windows are unreadable and, worse,
unrecoverable — the one underneath cannot be grabbed to move it.

The two middle ones open a short menu rather than cycling, so picking *Overall*
takes one look instead of counting clicks. Every button writes the same setting
the panel does, so the window and the panel cannot disagree.

**Reset lives in the segment menu**, not on a button. The X closes a window now,
and a header carrying both an X that closes and an X-alike that wipes your raid's
numbers is one misclick away from losing a fight nobody can recompute. The
padlock shows the state the window is *in* — an open padlock means unlocked —
because the other reading is equally plausible and half of everyone guesses
wrong.

**Up to four windows**, over one set of totals. That is the point of having more
than one: damage in the left window and healing beside it, from the same fight,
without switching. Each window carries its own segment, statistic, columns, size
and position. The first window is the one the settings page edits and cannot be
closed.

Drag the **grip** in the bottom-right corner to resize. It writes a width and a
row count rather than a frame size, so the window is always a whole number of
rows tall and a drag and a slider are the same edit. A locked window has no grip.

Rows are scaled against the leader, and the four columns — **rank**, **total**,
**per second** and **share** — are independent switches that can all be on at
once. They answer different questions, and which of them matter depends on what
you are looking for.

Color goes **bar color, then class**: the bar color is what a row is unless
something knows better, and class knows better because it is how you find a name
in a list. A row whose class cannot be resolved — a pet, a boss, anybody outside
your group — falls back to the bar color rather than to something louder. The
threat meter runs the same rule with a third step on top: bar, then class, then
your own pull ramp.

**Updates per second** is a slider, one to ten. It is a real speed rather than a
throttle — the totals only change when something is hit, but the seconds they are
divided by keep running, so a per-second figure moves between events. **Test
Bars** re-seeds its numbers at the same rate, so the slider is something you can
actually see rather than something you have to take on trust.

Neither window can be dragged off the screen. The client refuses the move while
it is happening, and the saved position is bounded again on the way in — a
profile carried to a smaller monitor needs the second one.

By default the meter follows your group; a boss's own damage is noise you cannot
improve and it dwarfs everybody. **Track Everyone** turns that off.

Off by default.

### Show, and Enable

Both meters' pages have a second column — **Window**, **Bar**, **Text** — because
those are three separate sittings. You place a window once, tune the bars when
you dislike how they look, and change the columns when you want a different
question answered. Same three on both, in the same order, so two meters open side
by side do not make you learn the layout twice.

**Show** is at the top of a subsystem's own page: do I want this on screen right
now. **Enable**, on the **Modules** page, is the heavier question — should this
subsystem run at all.

They are two settings, not one. A meter that is enabled but hidden **keeps
counting**: hide the damage meter for a pull, show it again at the end, and the
fight is there. That is the whole reason to have both — if Show unbound the
module, those numbers would never have existed, and "hide this for a moment"
would quietly cost you the fight. Enable is the one that stops it running.

### Nothing goes off screen

Every bar and every window is bounded to the monitor, on both axes, against its
own size — so the far edge of the thing you are dragging stops on the edge of the
screen and no further. That applies when you drag it, when you type a coordinate,
and again every time the addon draws: a profile carries positions across
resolutions, monitors and scale settings, and something that was on screen when
it was saved need not be now.

**Scale** on the General page is the addon's, not the bar cluster's. It reaches
the meters too.

**Bar Spacing** on the Bars page is how much room the stack leaves between bars,
on top of whatever the border needs. Like everything else about geometry it takes
effect on the next **Restack** rather than immediately: bar positions are
account-wide, so a setting that silently relaid the HUD would move another
character's bars too. The meters have their own **Gap Between Bars** under their
Bar section, which applies at once — a meter's rows are its own.

## Profiles

One account-wide store. Every character starts on `Default`, which is why they
all line up: move a bar on one and it moves for all of them. Create as many
named profiles as you like and bind characters to them individually.

An existing `RogueBarsConfig` is imported into `Default` the first time the Overhaul
loads, once. RogueBars' own saved variables are never modified.

## Commands

```
/eq                          open the panel            (also /ob, /omnibars)
/eq help                     every option, every scope
/eq scale 120                a general option
/eq bar resource h 20        a bar's geometry
/eq power ticker nofull      a module's setting
/eq profile use Raiding      use|new|copy|delete
/eq restack                  re-stack the occupied bars
/eq windows                  where each meter window is stored and drawn
/eq test                     preview every bar without a target
/eq selftest                 check the addon against your client
/eq rangedebug               every value behind the distance readout
/eq rangescan                every distance band this client can measure
/eq reset                    this profile   ( reset all for every profile )
```

`/eq rangedebug` is for when the Distance bar disagrees with your eyes. Target
something, run it, and it prints every raw client answer behind the reading —
which extensions replied and with what, what each of the four backends says about
*that* unit, and the state and yardage that came out. It also names the target
type, so a run against a friendly NPC and a run against an enemy player can be
compared line for line.

`/eq selftest` is the one to run first if something looks wrong. It verifies
that every API each module needs exists on your client, that the bars were built
with a size and a position, that the values they draw from are sane, which range
backend you ended up on, and that the settings panel built completely — then
reports pass or fail per section. It changes nothing.

The panel and the prompt are generated from the same table, so anything you can
click you can type, and neither can drift out of step with the other.

## Where the text sits

Every label has a **Position** slider: 0 is hard left, 100 hard right, and
anywhere in between is a place you can put it. That replaces Swap Text Sides,
which was the same choice with only two answers.

The travel stops at the edge rather than letting a label hang off the end, and it
stops sooner for a longer label — the clamp is against the text's own width, not
a fixed inset.

## Moving things

Drag any bar. Right-click one for a nudge overlay with 1px arrows. Or type exact
coordinates on the Bars page.

**Move Bars Together** (on by default) drags the whole cluster and keeps the
spacing. Turn it off to place bars individually; **Allow Bar Overlap** governs
whether they may then stack, and border art counts as part of a bar.

## Installation

1. Download the latest version
2. Unpack the zip
3. Rename the folder to **`EquadisClassicOverhaul`** — the name must match exactly, or
   the bundled textures and fonts will not load
4. Copy it into `Wow-Directory\Interface\AddOns`
5. Restart WoW

## Compatibility

Vanilla 1.12 client APIs only, Lua 5.0, no libraries, no dependencies, no
localisation requirements.

SuperWoW and UnitXP_SP3 are optional. SuperWoW's `UnitPosition` supplies exact
friendly-unit coordinates; it does **not** expose hostile-unit coordinates, and
passing the unit's GUID instead of its token does not get round it — both
confirmed in game, not assumed. The Overhaul also supports
`GetUnitDistance(unitToken)` from a Nampower build that exposes its existing
object-manager positions. UnitXP_SP3 remains a compatible exact hostile-distance
source.

An **exact** yard count on a hostile target needs one of those two native
extensions. With only stock Nampower there is still a number, but it is a band —
see below. The yards label is always
one exact current distance such as `23y`. The equipped attack's complete usable
range is shown separately as `[8-30y]`; both labels can be hidden or swapped
between the left and right sides. Stock Nampower 4.6.2 still provides the hostile
range state, but not the exact-yard label.

If RogueBars is enabled at the same time you will see two sets of bars, because
The Overhaul supersedes it. It says so once in chat rather than refusing to load.

## Development

`tests/` holds a stub of the 1.12 client and a suite that boots the real addon
against it — nine classes, event dispatch, rendering maths, ticker phase, swing
attribution, range backend selection, collision, profiles, migrations, the
options panel and every slash command. The TOC does not list `tests/`, so the
game never loads it.

```
luajit tests/run.lua
```

That half proves the addon is internally consistent. It cannot prove the client
agrees — a stub that shares a wrong assumption passes happily, which is exactly
how a settings panel that could not open once shipped past a green suite.
`/eq selftest` is the other half, and asks the questions only the real client
can answer.

Any Lua 5.1-compatible interpreter works; LuaJIT is the closest easily available
match to the client's 5.0. `luac -p *.lua` is a syntax-only check and a weak one:
whichever `luac` is on your path is almost certainly 5.4, which accepts a great
deal 5.0 rejects. LuaJIT running the suite is the stricter gate of the two.

**Adding a file to the TOC needs a full client restart.** 1.12 reads each addon's
file list once, at startup, so `/reload` re-runs only the files the client
already knew about — the version string updates, the new module does not load,
and it looks exactly like a broken module. `/eq selftest` says so if no feature
module registered.

## Credits

Built on the architecture of Equadis' Rogue Bars, which it supersedes, and drawing
on patterns from ShaguDPS (namespace, dirty-flag dispatch), Equadis' Threat Meter
(config loader, declarative options, widget factory, and the threat meter itself)
and Equadis' UnitFrames (the mana tick heuristic).

The druid secondary mana estimate is ported from DruidManaLib-1.0 by Aviana,
rewritten standalone so it no longer needs Ace2.

The combat log parser is derived from **ShaguDPS** by Eric Mauser (Shagu), MIT
licensed, which parses the 1.12 combat log in a locale-independent way rather
than matching translated strings.

The Overhaul is **GPL-3.0 licensed**. It began MIT and moved deliberately: two of
the addons worth taking from -- VCB and T-RestedXP -- are GPL-3, and GPL-3 code
can only be combined into a GPL-3 work. Staying MIT would have meant either
reimplementing them from behaviour or going without.

MIT is compatible in that direction, so every MIT-licensed port already here
remains what it was: its licence and copyright are preserved in `NOTICE`, which
reproduces the licences of the bundled work in full, and each ported file names
its origin at the top.

**The move is one-way.** GPL-3 code cannot be taken back out from under GPL-3,
so this cannot return to MIT.
