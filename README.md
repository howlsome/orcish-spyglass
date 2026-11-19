# Orcish Spyglass
A World of Warcraft addon that warns you when a rare, rare elite or treasure is nearby: rare scanner, treasure finder and rare-kill alerts in one.

Built for **WoW: Forever** (interface 16001).

When a rare or treasure appears on your minimap, or a rare / rare elite nameplate comes
into view, you get an on-screen raid warning, a chat line and a sound. Minimap finds are
pinned on your map with a navigation arrow, and the chat line has a clickable map link.

If someone outside your group kills a rare you've seen, you're told:
*Someone other than you just killed &lt;name&gt;.*

## Options
Open them with `/spyglass` (or `/osg`), or Esc > Options > AddOns > Orcish Spyglass.

- **Rares / Treasures / Other minimap icons**: choose what to be alerted about
- **Rares killed by others**: the "someone else got it" message
- **Scan nameplates for rares** (needs enemy nameplates turned on)
- **Pin alerts on the map**: won't replace a pin you placed yourself
- **Play sound / Show on-screen warning / Print to chat**

The **Ignore list** page (under Orcish Spyglass) lets you add names, add your target or
the last alert, and remove entries.

## Commands
| Command | What it does |
| --- | --- |
| `/spyglass` | Open the settings |
| `/spyglass sound [on\|off]` | Turn the alert sound on or off (toggles with no argument) |
| `/spyglass rares\|treasures\|others\|deaths\|pins [on\|off]` | Turn an alert type on or off |
| `/spyglass ignore [name]` | Stop alerts for a name. With no name: your target, or else the last alert |
| `/spyglass unignore <name>` | Start alerting for a name again |
| `/spyglass list` | Show the ignore list |
| `/spyglass pin` | Pin the last alert on the map, replacing any pin |
| `/spyglass test` | Fire a test alert |

Names aren't case sensitive, and `*` is a wildcard: `/spyglass ignore *Chest*` ignores every
chest.

Kills by you, your pet or anyone in your group don't count as "someone else".
Settings and the ignore list are saved per account.
