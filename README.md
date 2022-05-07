# ku

![Screenshot](https://github.com/mattmcginty89/ffxi-ku/blob/master/assets/screenshot.PNG?raw=true "Screenshot")


**ku - "Keeper Upper"**

FFXI Addon that automatically casts configured abilities 

Use at your own risk

Watches for player buffs and intelligently recasts when ability effects wear off

**Features:**

- Build up a list of multiple abilities to auto-cast
  - Abilities can be added/removed manually 1 by 1
  - Sets are also support via config for loading pre-configured sets of abilities
    - Multiple sets can be configured and named
- Stop/Start commands to easily disable/enable auto-casting
- Intelligent recasting / re-applying of buffs
  - Cures can be configured via HP threshold
  - Buffs only reapply when they wear off
  - Abilities with timers only cast when recast timer reaches zero
- Most types of ability supported, split into the following categories:
  - `curema` Cure magic used on self
  - `cureda` Cure dance used on self
  - `selfma` Buff magic used on self
  - `selfja` JA used on self
  - `selfda` Dances used on self
  - `targma` Magic used on a target
  - `targja` JA used on a target
  - `targda` Dance used on a target  
- Limit when abilities should be cast 
  - In combat only
  - Out of combat only
  - All the time
- Limit auto-casting to a single zone

**Examples:**

_See the examples files for many more examples_

- Print help
 
`//ku help`

- Stop
 
`//ku stop`

- Start/Resume
 
`//ku start`

- Apply a set of abilities from config (See settings.xml for example)

Params -> `//ku set [setname]`

Example -> `//ku set pldwar`

- Remove a specific ability from the current list

Params -> `//ku remove [position in list]`

Example -> `//ku remove 1`

- Limit usage to a single zone
 
Params -> `//ku zone [zoneid]`

Example -> `//ku zone 62`

- Magic cast on self

Params -> `//ku add selfma [spell] [spell_id] [buff_id] [when]`

Example -> `//ku add selfma Cocoon 547 93 in`

- JA used on self

Params -> `//ku add selfja [ja] [ability_id] [recast_id] [when]`

Example -> `//ku add selfja Drain_Samba 184 368 216 in`

- Magic used on target

Params -> `//ku add targma [spell] [spell_id]`

Example -> `//ku add targma Jet_Stream 569`

- JA used on target

Params -> `//ku add selfja [ja] [ability_id] [recast_id]`

Example -> `//ku add targja Box_Step 202 220`

**Notes**

- [when] param refers to combat engaged status; i.e in combat, out of combat, or both
- Valid [when] options are `all` / `out` / `in`
- Multi-word abilities must have underscores, e.g -> Drain_Samba
- [zone_id] found at windower github -> Windower/Resources/zones
- [spell_id] found at windower github -> Windower/Resources/spells
- [ability_id] found at windower github -> Windower/Resources/job_abilities
- [buff_id] found at windower github -> Windower/Resources/buffs
- [recast_id] found at windower github -> Windower/Resources/ability_recasts

**Version History**

- 1.3 - Added support for sets
- 1.2 - Added zone exclusions & fixed curema
- 1.12 - Added cureda and curema
- 1.11 - Added selfda and targda
- 1.10 - Overhaul/refactor
- 1.00 - Inital with selfja/selfma/targma/targja

Any contributions to this codebase are welcomed, there's huge room for improvement in code quality and feature set
